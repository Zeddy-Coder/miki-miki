import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';

import '../constants/app_identity.dart';
import '../models/media_models.dart';
import '../utils/formatters.dart';
import '../utils/platform_info.dart';
import '../widgets/side_panel.dart';
import 'anime4k_controller.dart';
import 'app_log.dart';
import 'audio_route_guard.dart';
import 'downloads/download_manager.dart';
import 'downloads/download_resolver.dart';
import 'orientation_policy.dart';
import 'player_diagnostics.dart';
import 'osd_message.dart';
import 'playback_clock.dart';
import 'player_actions.dart';
import 'shortcut_catalog.dart';
import 'storage_service.dart';
import 'thumbnail_service.dart';
import 'seek_preview_service.dart';
import 'media_controls.dart';
import 'system_controls.dart';
import 'touch_hide_timer.dart';
import 'mpv_config.dart';
import 'playlist_service.dart';
import 'remote_driver.dart';
import 'skips/skip_service.dart';
import 'songs/song_service.dart';
import 'songs/theme_songs.dart';
import 'remote_engine.dart';
import 'remote_playback.dart';
import 'watch_models.dart';
import 'source_prefs.dart';
import 'source_registry.dart';
import 'track_defaults.dart';

class PlayerStateController extends ChangeNotifier {
  late final Player player;
  late final VideoController videoController;

  double currentSpeed = 1.0;
  double prevSpeed = 1.0;
  double currentVolume = 100.0;

  /// Volume and "mute" for the slider in the dock. A separate notifier: dragging the slider or the wheel
  /// produces dozens of events per second, and they must not rebuild the whole screen.
  final ValueNotifier<VolumeState> volumeState = ValueNotifier<VolumeState>(const VolumeState(100, false));

  void _publishVolume() => volumeState.value = VolumeState(currentVolume, isMuted);
  String currentHwdec = AppPlatform.defaultHwdec;
  bool isMuted = false;
  bool isSpeeding = false;
  bool showControls = true;
  bool isDraggingFile = false;
  bool isFullscreen = false;
  bool showStatsOverlay = false;
  bool isMiniPlayer = false;
  /// The player is collapsed into the dock over the home page (playback continues)
  bool isCollapsed = false;
  Rect? _savedBounds;

  String currentFilePath = "";
  String currentTitle = "YouTube Mobile";
  String? activeDrawer;
  /// Navigation stack inside the menu (Settings → More → Decoder)
  final List<String> _drawerStack = [];
  /// The button that opened the menu: 'settings' / 'subs' / 'audio' / 'speed'.
  /// The dock buttons are highlighted by it, not by the current menu page.
  String? drawerOwner;
  String? get activeDrawerPrev => _drawerStack.isEmpty ? null : _drawerStack.last;

  void _clearDrawer() {
    activeDrawer = null;
    drawerOwner = null;
    _drawerStack.clear();
  }
  double drawerAnchorPixelX = 260.0;
  bool drawerIsTop = false;

  bool _hasResumedPlayback = false;
  String _delayAppliedFor = '';
  Duration? dismissedChapterStartTime;
  SidePanelType? activeSidePanel;

  List<Media> playlistItems = [];
  int currentPlaylistIndex = 0;

  /// The player chrome's title: the anime for site episodes ("Проводжальниця Фрірен"), else the file's title
  String get chromeTitle {
    final s = remote.active ? remote.session : null;
    return s != null && s.animeTitle.isNotEmpty ? s.animeTitle : currentTitle;
  }

  /// The grey line under it: "Серія 6 з 28 · Inari" (with [quality] also " · 1080p", as on a PC); a file queue —
  /// "Серія 2 з 3"; a single file — nothing
  String chromeSubtitle({bool quality = false}) {
    final s = remote.active ? remote.session : null;
    if (s != null) {
      final i = remote.index;
      final e = i >= 0 && i < s.entries.length ? s.entries[i] : null;
      final q = remote.video?.title ?? '';
      return [
        if (e != null) 'Серія ${episodeLabel(e.episode, i)} з ${episodesOfList(s.entries.map((x) => x.episode), total: remote.hikka?.total)}',
        if (remote.group != null) remote.group!.teamLabel,
        if (quality && q.isNotEmpty) q,
      ].join(' · ');
    }
    final queue = playlistItems.length;
    return queue > 1 ? 'Серія ${currentPlaylistIndex + 1} з $queue' : '';
  }
  List<VideoChapter> currentChapters = [];
  List<CachedSubtitleTrack> cachedSubtitleTracks = [];
  List<CachedAudioTrack> cachedAudioTracks = [];
  /// Live metrics for "Stats for nerds". A separate notifier: polling once per ~0.8 s
  /// does not rebuild the whole screen (and does not itself disturb the measured frame drops).
  final ValueNotifier<PlaybackStats> liveStats = ValueNotifier<PlaybackStats>(const PlaybackStats());
  PlaybackStats get currentStats => liveStats.value;
  final List<String> mpvLogs = [];

  // ───────── On-screen notifications (OSD) ─────────
  final ValueNotifier<OsdMessage?> osd = ValueNotifier<OsdMessage?>(null);
  Timer? _osdTimer;

  // ───────── Anime4K ─────────
  late final Anime4kController anime4k = Anime4kController(
    command: mpv,
    osd: (message, {duration}) => _pushOsd(message, duration: duration),
  );

  // ───────── Site episodes ("Дивитись") ─────────
  /// Watching episodes from source sites: the driver handles the queue, link lookup, position, "watched" and auto-advance.
  /// To the rest of the UI this looks like an ordinary queue: `playlistItems` are the episodes, `currentFilePath` is the episode key.
  late final RemoteDriver remote = RemoteDriver(
    engine: MpvRemoteEngine(player: player, command: mpv),
    registry: SourceRegistry.instance,
    // A downloaded episode plays from the device, the rest from the site
    resolver: DownloadAwareResolver(maxHeight: () => SourcePrefs.instance.maxHeight, preferredHoster: () => SourcePrefs.instance.hoster),
    // Opening and ending for episodes the site gave no times for: AniSkip, made exact by listening
    skips: SkipService.instance,
    // The songs of the opening and ending: a card over the video, where to listen to them
    songs: SongService.instance,
  );

  // ───────── Hotkeys ─────────
  late final PlayerActions actions = PlayerActions(this);
  KeyScheme keyScheme = KeyScheme.standard;
  bool isAlwaysOnTop = false;

  /// Opens the hotkey help (set by the player screen, which knows the context and scale)
  VoidCallback? onShowShortcuts;

  /// Gives hotkeys back to the player screen (set by `PlayerScreen`); needed after the window mode changes
  VoidCallback? onRestoreKeyboardFocus;

  Timer? _hideTimer;
  Timer? _positionSaveTimer;
  Timer? _liveStatsTimer;

  /// A finger holds the progress slider: panels do not hide while dragging continues
  bool seekDragging = false;

  void setSeekDragging(bool value) {
    if (seekDragging == value) return;
    seekDragging = value;
    if (value) {
      _touchHide.cancel();
      _hideTimer?.cancel();
    } else if (showControls) {
      _startHideTimer();
    }
  }

  /// Touch screen: this timer hides the panels (4 s without touches), not the cursor leaving the zone
  late final TouchHideTimer _touchHide = TouchHideTimer(
    shouldStayVisible: () =>
        _disposed || isHome || seekDragging || !player.state.playing || isSpeeding || activeDrawer != null || activeSidePanel != null || showStatsOverlay,
    onHide: () {
      if (!showControls) return;
      showControls = false;
      notifyListeners();
    },
  );

  /// Work key for the saved audio delay: site episodes use the anime and dub, local files the folder
  String get audioDelayKey {
    final sess = remote.session;
    if (remote.active && sess != null) return 'r|${sess.animeKey}|${sess.groupLabel}';
    if (currentFilePath.isEmpty) return '';
    final path = currentFilePath.replaceAll('\\', '/');
    final cut = path.lastIndexOf('/');
    return cut > 0 ? 'l|${path.substring(0, cut)}' : 'l|$path';
  }

  /// Gives the work its audio delay (otherwise mpv carries over the previous episode's value)
  Future<void> _applyAudioDelay() async {
    final key = audioDelayKey;
    if (key.isEmpty) return;
    try {
      final dynamic platform = player.platform;
      await platform?.setProperty('audio-delay', (StorageService.getAudioDelay(key) / 1000).toStringAsFixed(3));
    } catch (_) {}
  }

  bool get isHome => currentFilePath.isEmpty && playlistItems.isEmpty;

  /// Show the home page (no media, or the player is collapsed)
  bool get showHome => isHome || isCollapsed;

  void collapsePlayer() {
    if (isHome || isCollapsed) return;
    _clearDrawer();
    activeSidePanel = null;
    if (showStatsOverlay) closeStatsOverlay();
    AppLog.i('дія', 'плеєр згорнуто в міні-плеєр: $currentTitle');
    isCollapsed = true;
    notifyListeners(); // the orientation is restored by _syncSystemUi
  }

  void expandPlayer() {
    if (!isCollapsed) return;
    AppLog.i('дія', 'міні-плеєр розгорнуто: $currentTitle');
    isCollapsed = false;
    notifyListeners();
    handleInteraction();
  }

  void init() {
    AppFormatters.clearTrackCache();

    currentVolume = StorageService.getVolume(fallback: 100.0);
    _publishVolume();
    currentSpeed = StorageService.getSpeed(fallback: 1.0);
    currentHwdec = StorageService.getHwdec();

    player = Player(
      configuration: PlayerConfiguration(
        libass: true,
        // Android: the libmpv build has no system fonts at all, so without our own libass draws no subtitles whatsoever
        libassAndroidFont: MpvConfig.androidSubtitleFontAsset,
        libassAndroidFontName: MpvConfig.androidSubtitleFontName,
        bufferSize: 64 * 1024 * 1024,
        // Verbose log: more detailed engine messages (the change takes effect after the app restarts)
        logLevel: AppLog.on ? MPVLogLevel.v : MPVLogLevel.info,
      ),
    );

    videoController = VideoController(
      player,
      configuration: VideoControllerConfiguration(enableHardwareAcceleration: true, hwdec: currentHwdec),
    );

    player.setVolume(currentVolume);
    player.setRate(currentSpeed);

    keyScheme = KeyScheme.parse(StorageService.getKeyScheme());
    anime4k.load();
    anime4k.addListener(notifyListeners);
    // We attach Anime4K after the base engine setup (and the user's mpv.conf)
    MpvConfig.configureEngine(player, currentHwdec).then((_) => anime4k.syncToEngine());

    _bindStreams();
    _bindRemote();
    if (MediaControls.active) MediaControls.onButton = _onMediaButton;
    _startHideTimer();
    _diag = PlayerDiagnostics(player, context: _diagContext)..start();

    if (AppPlatform.isMobile) {
      _ready = true;
      SystemControls.inPip.addListener(_onPipChanged);
      SystemControls.onPipToggle = _onPipToggle;
      SystemControls.onAudioFocus = _onAudioFocus;
      SystemControls.onAudioRoute = _audioRoute.routeChanged;
      SystemControls.onAudioNoisy = _audioRoute.becomingNoisy;
      SystemControls.pipSupported().then((ok) {
        if (_disposed) return;
        pipSupported = ok;
        notifyListeners();
      });
      _syncSystemUi();
    }
  }

  void _bindStreams() {
    player.stream.rate.listen((rate) {
      currentSpeed = rate;
      StorageService.saveSpeed(rate);
      notifyListeners();
    });

    player.stream.volume.listen((vol) {
      // During "mute" the player reports 0: we remember the real volume so it can be restored
      if (!isMuted) {
        currentVolume = vol;
        StorageService.saveVolume(vol);
      }
      _publishVolume();
    });

    player.stream.track.listen((_) {
      notifyListeners();
    });

    player.stream.height.listen((h) {
      anime4k.onVideoHeight(h ?? 0);
      if (AppPlatform.isMobile) _syncPipArm();
    });

    // Phone: automatic PiP entry must be enabled only during playback
    player.stream.playing.listen((_) {
      if (AppPlatform.isMobile && _ready && !_disposed) {
        _syncPipArm();
        _syncPlaybackSystem();
      }
      _syncMediaControls();
    });

    player.stream.tracks.listen((tracks) {
      cachedSubtitleTracks = MpvConfig.extractSubtitleTracks(tracks);
      cachedAudioTracks = MpvConfig.extractAudioTracks(tracks);
      _applyTrackDefaults(tracks);
      notifyListeners();
    });

    player.stream.duration.listen((dur) async {
      if (dur > Duration.zero && _delayAppliedFor != currentFilePath) {
        _delayAppliedFor = currentFilePath;
        unawaited(_applyAudioDelay());
      }
      if (remote.active) {
        // Site episode: the position was restored by the driver (Media.start), chapters come from the site's timestamps
        if (dur > Duration.zero) {
          remote.onDuration(dur);
          currentChapters = remote.chapters;
          notifyListeners();
        }
        return;
      }
      if (!_hasResumedPlayback && dur > Duration.zero && currentFilePath.isNotEmpty) {
        _hasResumedPlayback = true;
        final savedPosMs = StorageService.getPlaybackPosition(currentFilePath);
        if (savedPosMs > 5000 && savedPosMs < dur.inMilliseconds - 10000) {
          player.seek(Duration(milliseconds: savedPosMs));
        }
      }
      currentChapters = await MpvConfig.extractChapters(player);
      notifyListeners();
      if (dur > Duration.zero) _captureLiveThumbnail();
    });

    player.stream.playlist.listen((pl) {
      if (remote.active) return; // mpv has just one video; the episode queue is handled by the driver
      if (pl.index >= 0 && pl.index < playlistItems.length) {
        currentPlaylistIndex = pl.index;
        currentTitle = playlistItems[pl.index].extras?['title'] ?? currentTitle;
        final curUri = playlistItems[pl.index].uri;
        if (currentFilePath != curUri) {
          currentFilePath = curUri;
          _hasResumedPlayback = false;
          _resetAutoTracks();
          anime4k.onFileChanged();
        }
        persistQueue();
        notifyListeners();
      }
    });

    player.stream.log.listen((log) {
      // The audio output: what opened (format, channels), its device latency, its failures — the facts behind "the sound lags"
      if (log.prefix == 'cplayer' && log.text.startsWith('AO: ') || (log.prefix.startsWith('ao') && log.level != 'trace' && log.level != 'debug')) {
        AppLog.i('звук', '[${log.prefix}] ${log.text.trim()}');
      }
      // Detailed (v / debug / trace) lines go only to the log file so they do not push important things out of the stats window
      final noisy = log.level == 'v' || log.level == 'debug' || log.level == 'trace';
      if (!noisy) {
        if (mpvLogs.length > 300) mpvLogs.removeAt(0);
        mpvLogs.add('[${log.prefix}] ${log.text}');
      }
      anime4k.onEngineLog(log.level, log.text);
    });

    player.stream.completed.listen((done) {
      if (done && remote.active) remote.onCompleted();
    });

    player.stream.error.listen((message) {
      if (remote.active) remote.onPlayerError(message);
    });

    _positionSaveTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (remote.active) {
        remote.tick();
        return;
      }
      if (currentFilePath.isNotEmpty && player.state.duration.inMilliseconds > 0) {
        StorageService.savePlaybackPosition(currentFilePath, player.state.position.inMilliseconds, player.state.duration.inMilliseconds);
      }
    });
  }

  String? _liveThumbUri;

  /// The thumbnail of the current video is taken straight from the player (without decoding the file again)
  Future<void> _captureLiveThumbnail() async {
    final pl = player.state.playlist;
    if (pl.index < 0 || pl.index >= pl.medias.length) return;
    final uri = pl.medias[pl.index].uri;
    if (_liveThumbUri == uri || ThumbnailService.getCachedThumbnail(uri) != null) return;
    _liveThumbUri = uri;

    await Future.delayed(const Duration(seconds: 6));
    // If the file was switched in the meantime, the snapshot is no longer the right one
    final now = player.state.playlist;
    if (now.index != pl.index || now.index >= now.medias.length || now.medias[now.index].uri != uri) return;
    try {
      final bytes = await player.screenshot(format: 'image/png');
      debugPrint('[Thumb] live screenshot for $uri: ${bytes?.length} bytes');
      if (bytes != null) await ThumbnailService.saveLiveThumbnail(uri, bytes);
    } catch (e) {
      debugPrint('[Thumb] live screenshot error: $e');
    }
  }

  /// Cursor in the "active zone" (top or bottom of the screen): the UI is shown and does not disappear while the cursor is there
  bool _pointerInZone = false;

  void pointerInZone(bool inZone) {
    if (inZone) {
      _pointerInZone = true;
      _hideTimer?.cancel();
      if (!showControls) {
        showControls = true;
        notifyListeners();
      }
    } else if (_pointerInZone) {
      _pointerInZone = false;
      _startHideTimer();
    }
  }

  /// A user action without the cursor (keyboard, opening a file): the UI is not shown,
  /// we only check whether it is time to hide it.
  void refreshSettings() => notifyListeners();

  void handleInteraction() => _startHideTimer();

  /// Tap on the video on a phone: shows the panels (and starts auto-hide) or hides them at once
  void toggleControlsByTouch() {
    if (isHome) return;
    _hideTimer?.cancel();
    if (showControls) {
      _touchHide.cancel();
      showControls = false;
      notifyListeners();
    } else {
      showControls = true;
      notifyListeners();
      _touchHide.arm();
    }
  }

  /// Any touch while the panels are visible postpones hiding them
  void touchActivity() {
    if (showControls && !isHome) _touchHide.arm();
  }

  // ── Phone: PiP, screen rotation, system bars, the "Back" button ──────────

  /// The app window is currently in picture-in-picture mode
  bool get isInPip => SystemControls.inPip.value;

  /// The device supports PiP (the PiP button is shown only then)
  bool pipSupported = false;

  /// Screen orientation: the "Орієнтація плеєра" setting applies while the video is on screen, and on exit or collapse
  /// into the mini player the previous one is restored
  late final OrientationPolicy _orientation = OrientationPolicy(
    apply: SystemChrome.setPreferredOrientations,
    preference: () => PlayerOrientation.parse(StorageService.getPlayerOrientation()),
    log: (m) => AppLog.i('орієнтація', m),
  );

  /// Orientation is locked (by the setting or the button); otherwise the sensor and the system rotation lock decide
  bool get rotationLocked => _orientation.locked;

  /// The "Орієнтація плеєра" setting changed: apply it at once if the video is on screen
  void refreshOrientationPreference() {
    if (AppPlatform.isMobile) _orientation.preferenceChanged();
  }

  PlayerDiagnostics? _diag;

  /// Extra data for sync snapshots in the log
  String _diagContext() {
    final parts = <String>[
      'шейдери: ${anime4k.enabled ? '${anime4k.mode.name}/${anime4k.quality.name}' : 'вимк.'}',
      if (remote.active) 'джерело перегляду',
      if (isCollapsed) 'згорнуто',
      if (isInPip) 'PiP',
    ];
    return parts.join('; ');
  }

  bool? _systemUiImmersive;
  bool? _pipArmed;
  int _pipArmW = 0, _pipArmH = 0;

  /// `init()` finished (the player is created)
  bool _ready = false;

  @override
  void notifyListeners() {
    super.notifyListeners();
    if (AppPlatform.isMobile && _ready && !_disposed) {
      _syncSystemUi();
      _syncPipArm();
    }
    _syncMediaControls();
  }

  /// The video is full screen without system bars; home has them
  void _syncSystemUi() {
    // Player on screen: "Орієнтація плеєра" applies; on exit or collapse the previous one is restored
    if (showHome) {
      _orientation.leavePlayer();
    } else {
      _orientation.enterPlayer();
    }
    final immersive = !showHome && !isInPip;
    if (_systemUiImmersive == immersive) return;
    _systemUiImmersive = immersive;
    SystemChrome.setEnabledSystemUIMode(immersive ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
    // Brightness set by a gesture applies only in the video; on home it is the system one
    if (immersive) {
      SystemControls.restoreBrightness();
    } else if (showHome) {
      SystemControls.resetBrightness();
    }
  }

  /// Aspect ratio of the frame for the PiP window
  (int, int) _pipSize() {
    final w = player.state.width, h = player.state.height;
    return (w != null && h != null && w > 0 && h > 0) ? (w, h) : (16, 9);
  }

  /// Automatic PiP entry (the "home" gesture) only while the video is playing
  void _syncPipArm() {
    if (!AppPlatform.isAndroid) return;
    final arm = !showHome && player.state.playing;
    final (w, h) = _pipSize();
    if (_pipArmed == arm && _pipArmW == w && _pipArmH == h) return;
    _pipArmed = arm;
    _pipArmW = w;
    _pipArmH = h;
    SystemControls.setPipAuto(arm, width: w, height: h);
  }

  /// Passes the playback state to Android: audio focus (other music goes silent) and the button icon in the PiP window
  void _syncPlaybackSystem() {
    final playing = player.state.playing;
    SystemControls.setPipPlaying(playing);
    // Pause due to a temporary focus loss (a call): we do not give focus up so we can hear "gain" and resume
    SystemControls.setAudioFocus(playing || _resumeOnFocus);
  }

  /// The "pause / play" button in the PiP window
  void _onPipToggle() {
    if (_disposed) return;
    AppLog.i('дія', 'кнопка у вікні PiP: ${player.state.playing ? 'пауза' : 'відтворення'}');
    _resumeOnFocus = false;
    player.playOrPause();
  }

  // ───────── Windows media controls (headphone / keyboard media keys) ─────────

  /// Publishes the current title and play state to the system overlay; clears it when nothing is open
  void _syncMediaControls() {
    if (_disposed || !MediaControls.active) return;
    if (isHome) {
      MediaControls.clear();
      return;
    }
    final total = remote.active ? (remote.session?.entries.length ?? 0) : playlistItems.length;
    MediaControls.update(
      title: currentTitle,
      subtitle: AppIdentity.name,
      playing: player.state.playing,
      hasPrevious: currentPlaylistIndex > 0,
      hasNext: currentPlaylistIndex < total - 1,
      thumbnail: remote.active ? remote.session?.poster : null,
    );
  }

  /// A system media button (headphones, keyboard, the Windows overlay)
  void _onMediaButton(String button) {
    if (_disposed || isHome) return;
    AppLog.i('дія', 'медіа-кнопка: $button');
    switch (button) {
      case 'play':
        player.play();
      case 'pause':
      case 'stop':
        player.pause();
      case 'toggle':
        player.playOrPause();
      case 'next':
        playNext();
      case 'previous':
        playPrevious();
    }
  }

  bool _resumeOnFocus = false;

  /// Bluetooth / headphones / speaker: the audio output is reopened for the new route, headphones off pause
  late final AudioRouteGuard _audioRoute = AudioRouteGuard(
    reload: () => mpv(['ao-reload']),
    hasMedia: () => !_disposed && !isHome,
    isPlaying: () => !_disposed && player.state.playing,
    pause: () {
      _resumeOnFocus = false;
      player.pause();
    },
    notice: (text) => showOsd(text, icon: Symbols.headphones_rounded),
  );

  void _onAudioFocus(String event) {
    if (_disposed) return;
    AppLog.i('дія', 'аудіофокус: $event');
    switch (event) {
      case 'loss':
        _resumeOnFocus = false;
        if (player.state.playing) player.pause();
      case 'transient':
        if (player.state.playing) {
          _resumeOnFocus = true;
          player.pause();
        }
      case 'gain':
        if (_resumeOnFocus) {
          _resumeOnFocus = false;
          player.play();
        }
    }
  }

  /// Anime4K shaders only make sense in a full-size window: in the mini player and in PiP they are paused to save the GPU
  void _syncShaderSuspension() => unawaited(anime4k.setSuspended(isMiniPlayer || isInPip));

  void _onPipChanged() {
    if (_disposed) return;
    _syncShaderSuspension();
    AppLog.i('дія', isInPip ? 'увійшов у PiP' : 'вийшов із PiP');
    if (isInPip) {
      _clearDrawer();
      activeSidePanel = null;
      if (showStatsOverlay) closeStatsOverlay();
      showControls = false;
    } else {
      showControls = true;
      _startHideTimer();
      // The PiP window was closed with the cross: the app is no longer on screen, so we stop playback
      final life = WidgetsBinding.instance.lifecycleState;
      if (life == AppLifecycleState.paused || life == AppLifecycleState.hidden || life == AppLifecycleState.detached) {
        onAppBackgrounded();
      }
    }
    notifyListeners();
  }

  /// An on-screen notification assembled from outside (brightness / volume / seek gestures)
  void showOsdMessage(OsdMessage message, {Duration? duration}) => _pushOsd(message, duration: duration);

  /// PiP button: collapses the video into a small window over other apps
  Future<void> enterPip() async {
    if (!AppPlatform.isMobile || showHome) return;
    AppLog.i('дія', 'кнопка PiP');
    _clearDrawer();
    activeSidePanel = null;
    if (showStatsOverlay) closeStatsOverlay();
    showControls = false;
    notifyListeners();
    final (w, h) = _pipSize();
    final ok = await SystemControls.enterPip(width: w, height: h);
    if (!ok && !_disposed) {
      showControls = true;
      showOsd('Картинка в картинці недоступна', icon: Symbols.picture_in_picture_alt_rounded, isError: true);
      notifyListeners();
    }
  }

  /// Rotate button: portrait ↔ landscape (and locks the choice)
  Future<void> toggleRotation() async {
    if (!AppPlatform.isMobile) return;
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final landscape = view.physicalSize.width > view.physicalSize.height;
    AppLog.i('дія', 'кнопка повороту: ${landscape ? 'альбомна → портретна' : 'портретна → альбомна'}');
    _orientation.toggle(landscapeNow: landscape);
    notifyListeners();
    showOsd(
      landscape ? 'Портретна орієнтація' : 'Альбомна орієнтація',
      icon: Symbols.screen_rotation_rounded,
      detail: 'Утримуйте кнопку — автоповорот',
      duration: const Duration(seconds: 2),
    );
  }

  /// Restores auto-rotate (the sensor decides the orientation again)
  Future<void> unlockRotation({bool announce = true}) async {
    if (!AppPlatform.isMobile || !rotationLocked) return;
    AppLog.i('дія', 'автоповорот увімкнено');
    _orientation.unlock();
    notifyListeners();
    if (announce) {
      showOsd('Автоповорот', icon: Symbols.screen_rotation_rounded, duration: const Duration(seconds: 2));
    }
  }

  /// System "Back" button: closes the top UI layer. false: nothing to close, it is OK to exit.
  bool handleBack() {
    AppLog.d('дія', 'системна кнопка «Назад»');
    if (showStatsOverlay) {
      closeStatsOverlay();
      return true;
    }
    if (activeDrawer != null) {
      if (_drawerStack.isNotEmpty) {
        backDrawer();
      } else {
        closeDrawers();
      }
      return true;
    }
    if (activeSidePanel != null) {
      if (panelStepBack()) return true;
      closeSidePanel();
      return true;
    }
    if (!showHome) {
      collapsePlayer();
      return true;
    }
    return false;
  }

  /// The "Перегляд" panel steps back first: from an episode's details or an inner page to its list
  bool panelStepBack() => activeSidePanel == SidePanelType.episodes && (remote.panelBack?.call() ?? false);

  /// The app went to the background (not PiP): pause and save the position
  void onAppBackgrounded() {
    if (_disposed || isInPip) return;
    AppLog.i('дія', 'застосунок у фоні: пауза й збереження позиції (${player.state.position.inSeconds} с)');
    if (currentFilePath.isNotEmpty && player.state.duration.inMilliseconds > 0) {
      StorageService.savePlaybackPosition(currentFilePath, player.state.position.inMilliseconds, player.state.duration.inMilliseconds);
      StorageService.flush();
    }
    if (player.state.playing) player.pause();
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    if (isHome) {
      if (!showControls) { showControls = true; notifyListeners(); }
      return;
    }
    if (AppPlatform.isMobile) {
      _touchHide.arm();
      return;
    }
    _hideTimer = Timer(const Duration(milliseconds: 450), () {
      if (!_pointerInZone && !isSpeeding && activeDrawer == null && activeSidePanel == null && !showStatsOverlay) {
        showControls = false;
        notifyListeners();
      }
    });
  }

  List<Map<String, String>> _queueSnapshot() => playlistItems
      .map((m) => {'uri': m.uri, 'title': (m.extras?['title'] ?? AppFormatters.cleanMediaTitle(m.uri)).toString()})
      .toList();

  /// Saves the current queue (only if it has several items) so it can be restored from home
  void persistQueue() {
    if (remote.active || playlistItems.length < 2) return; // site episodes are not the "last queue" of files
    StorageService.saveLastQueue(_queueSnapshot(), currentPlaylistIndex);
  }

  /// Opens a saved queue / playlist, starting at [startIndex].
  /// Local files that no longer exist on disk are skipped.
  Future<void> openQueue(List<Map<String, String>> items, {int startIndex = 0}) async {
    AppLog.i('дія', 'відкрито чергу: ${items.length} елем., старт з ${startIndex + 1}');
    remote.stop();
    final valid = <Map<String, String>>[];
    String? wantedUri = (startIndex >= 0 && startIndex < items.length) ? items[startIndex]['uri'] : null;
    // File presence is checked asynchronously and in parallel: a synchronous walk of a long queue on a
    // slow disk (SD card, network path) would freeze the UI
    final exists = await Future.wait(items.map((it) async {
      final uri = it['uri'] ?? '';
      if (uri.isEmpty) return false;
      if (uri.contains('://')) return true;
      return File(uri).exists();
    }));
    for (int i = 0; i < items.length; i++) {
      if (exists[i]) valid.add(items[i]);
    }
    if (valid.isEmpty) return;
    isCollapsed = false;
    int idx = wantedUri == null ? 0 : valid.indexWhere((e) => e['uri'] == wantedUri);
    if (idx < 0) idx = 0;

    StorageService.flush();
    _hasResumedPlayback = false;
    _resetAutoTracks();
    dismissedChapterStartTime = null;
    anime4k.onFileChanged();
    AppFormatters.clearTrackCache();

    final medias = valid.map((e) {
      final uri = e['uri']!;
      final t = (e['title'] ?? '').isNotEmpty ? e['title']! : AppFormatters.cleanMediaTitle(uri);
      return Media(uri, extras: {'title': t});
    }).toList();

    currentFilePath = medias[idx].uri;
    StorageService.addRecentFile(currentFilePath);
    playlistItems = medias;
    currentPlaylistIndex = idx;
    currentTitle = medias[idx].extras?['title'] ?? currentFilePath;
    currentChapters = [];
    _clearDrawer();
    activeSidePanel = null;
    notifyListeners();
    persistQueue();

    await player.open(medias.length > 1 ? Playlist(medias, index: idx) : medias.first);
    handleInteraction();
  }

  Future<void> openFileOrPlaylist(String path) async {
    AppLog.i('дія', 'відкриваю: $path');
    remote.stop();
    StorageService.flush();
    isCollapsed = false;
    currentFilePath = path;
    _hasResumedPlayback = false;
    _resetAutoTracks();
    dismissedChapterStartTime = null;
    anime4k.onFileChanged();
    AppFormatters.clearTrackCache();
    StorageService.addRecentFile(path);

    final medias = await PlaylistService.parsePath(path);
    playlistItems = medias;
    currentPlaylistIndex = 0;
    currentTitle = medias.first.extras?['title'] ?? AppFormatters.cleanMediaTitle(path);
    currentChapters = [];
    _clearDrawer();
    activeSidePanel = null;
    notifyListeners();
    persistQueue();

    await player.open(medias.length > 1 ? Playlist(medias) : medias.first);
    handleInteraction();
  }

  Future<void> openMultipleFiles(List<String> paths) async {
    AppLog.i('дія', 'відкриваю файлів: ${paths.length}');
    if (paths.isEmpty) return;
    remote.stop();
    StorageService.flush();
    isCollapsed = false;
    _hasResumedPlayback = false;
    _resetAutoTracks();
    dismissedChapterStartTime = null;
    anime4k.onFileChanged();
    AppFormatters.clearTrackCache();

    final medias = paths.map((p) {
      StorageService.addRecentFile(p);
      return Media(p, extras: {'title': AppFormatters.cleanMediaTitle(p)});
    }).toList();

    currentFilePath = paths.first;
    playlistItems = medias;
    currentPlaylistIndex = 0;
    currentTitle = medias.first.extras?['title'] ?? currentFilePath;
    currentChapters = [];
    _clearDrawer();
    activeSidePanel = null;
    notifyListeners();
    persistQueue();

    await player.open(Playlist(medias));
    handleInteraction();
  }

  Future<void> pickAndOpenFile() async {
    AppLog.i('дія', 'вибір файлу для відкриття');
    final paths = await PlaylistService.pickVideoPaths();
    if (paths.length == 1) {
      openFileOrPlaylist(paths.first);
    } else if (paths.length > 1) {
      openMultipleFiles(paths);
    }
  }

  Future<void> addMediaToQueue() async {
    AppLog.i('дія', 'додавання файлів у чергу');
    if (remote.active) return;
    final paths = await PlaylistService.pickVideoPaths();
    if (paths.isNotEmpty) {
      final existing = playlistItems.map((m) => m.uri).toSet();
      final newMedias = paths.where((p) => !existing.contains(p)).map((p) => Media(p, extras: {'title': AppFormatters.cleanMediaTitle(p)})).toList();
      if (newMedias.isNotEmpty) {
        if (playlistItems.isEmpty) {
          openMultipleFiles(newMedias.map((m) => m.uri).toList());
        } else {
          playlistItems.addAll(newMedias);
          notifyListeners();
          persistQueue();
          for (var m in newMedias) { await player.add(m); }
        }
      }
    }
  }

  /// [to] is the index after removing the item (as in ReorderableListView.onReorderItem)
  void reorderQueue(int from, int to) {
    AppLog.d('дія', 'черга: переміщено $from → $to');
    if (remote.active || from == to || from < 0 || from >= playlistItems.length) return;
    to = to.clamp(0, playlistItems.length - 1);
    final current = playlistItems[currentPlaylistIndex.clamp(0, playlistItems.length - 1)];
    final item = playlistItems.removeAt(from);
    playlistItems.insert(to, item);
    currentPlaylistIndex = playlistItems.indexOf(current);
    notifyListeners();
    persistQueue();
    player.move(from, to > from ? to + 1 : to);
  }

  void removeFromQueue(int idx) {
    AppLog.i('дія', 'черга: прибрано елемент ${idx + 1}');
    if (remote.active || idx < 0 || idx >= playlistItems.length || idx == currentPlaylistIndex || playlistItems.length < 2) return;
    final current = playlistItems[currentPlaylistIndex];
    playlistItems.removeAt(idx);
    currentPlaylistIndex = playlistItems.indexOf(current);
    notifyListeners();
    persistQueue();
    player.remove(idx);
  }

  Future<void> clearQueueExceptCurrent() async {
    AppLog.i('дія', 'черга: очищено, крім поточного');
    if (remote.active) return;
    for (int i = playlistItems.length - 1; i >= 0; i--) {
      if (i == currentPlaylistIndex) continue;
      playlistItems.removeAt(i);
      if (i < currentPlaylistIndex) currentPlaylistIndex--;
      await player.remove(i);
    }
    notifyListeners();
    persistQueue();
  }

  void selectEpisode(int idx) {
    AppLog.i('дія', 'вибрано серію ${idx + 1}');
    if (remote.active) {
      if (idx != remote.index || remote.phase == RemotePhase.failed) remote.open(idx);
      return;
    }
    if (idx >= 0 && idx < playlistItems.length) {
      player.jump(idx);
      currentPlaylistIndex = idx;
      currentTitle = playlistItems[idx].extras?['title'] ?? currentTitle;
      notifyListeners();
    }
  }

  /// "Next" button: in a file queue the next file, in site episodes the next episode
  Future<void> playNext() async {
    AppLog.i('дія', 'наступний елемент черги');
    if (!remote.active) {
      await player.next();
      return;
    }
    if (!await remote.next()) showOsd('Це остання серія', icon: Symbols.queue_music_rounded);
  }

  /// "Previous" button
  Future<void> playPrevious() async {
    AppLog.i('дія', 'попередній елемент черги');
    if (!remote.active) {
      await player.previous();
      return;
    }
    if (!await remote.previous()) showOsd('Це перша серія', icon: Symbols.queue_music_rounded);
  }

  // ───────── Site episodes ─────────

  /// Starts watching from the anime page: [launch] carries the dub, the starting episode and all variants for switching
  Future<void> openRemote(RemoteLaunch launch) async {
    AppLog.i('дія', 'відкриваю серії із джерела');
    StorageService.flush();
    isCollapsed = false;
    _hasResumedPlayback = true; // the position is restored by the driver (Media.start), not by the duration listener
    dismissedChapterStartTime = null;
    currentChapters = [];
    _clearDrawer();
    activeSidePanel = null;
    await remote.start(launch);
    handleInteraction();
  }

  void _bindRemote() {
    remote.onSession = () {
      final s = remote.session;
      playlistItems = s == null
          ? []
          : [for (final e in s.entries) Media('remote://${Uri.encodeComponent(e.key)}', extras: {'title': e.title})];
      notifyListeners();
    };
    remote.onEntry = (i) {
      final s = remote.session;
      if (s == null || i < 0 || i >= s.entries.length) return;
      currentPlaylistIndex = i;
      currentFilePath = s.entries[i].key;
      currentTitle = s.displayTitle(i);
      currentChapters = [];
      dismissedChapterStartTime = null;
      _hasResumedPlayback = true;
      anime4k.onFileChanged();
      AppFormatters.clearTrackCache();
      notifyListeners();
    };
    // Smart downloads: the next episode downloads, the watched one goes (as set in the downloads' settings)
    remote.onWatched = (animeKey, e) => DownloadManager.instance.onWatched(animeKey, e.epKey, group: remote.group);
    remote.onMessage = (text, {bool error = false}) => showOsd(
          text,
          icon: error ? Symbols.error_rounded : Symbols.skip_next_rounded,
          isError: error,
          duration: const Duration(seconds: 2),
        );
    remote.addListener(() {
      // The skip plan may come after the start (AniSkip, listening): its chapters replace the site's
      if (remote.active && remote.phase == RemotePhase.playing && !identical(currentChapters, remote.chapters)) currentChapters = remote.chapters;
      notifyListeners();
    });
  }

  void openDrawer(String name, GlobalKey key, {bool isTop = false}) {
    AppLog.d('дія', 'меню: $name');
    final renderBox = key.currentContext?.findRenderObject() as RenderBox?;
    double pixelX = 260.0;
    if (renderBox != null) {
      final pos = renderBox.localToGlobal(Offset.zero);
      pixelX = pos.dx + (renderBox.size.width / 2);
    }
    final wasOpen = drawerOwner == name;
    _drawerStack.clear();
    activeDrawer = wasOpen ? null : name;
    drawerOwner = wasOpen ? null : name;
    drawerAnchorPixelX = pixelX;
    drawerIsTop = isTop;
    notifyListeners();
  }

  /// The song card was tapped: «Пісня» (where to listen) from it; on a PC the controls come up with the menu
  void openSongDrawer(SongKind kind, GlobalKey key) {
    showControls = true;
    openDrawer('song-${kind.name}', key);
  }

  void openSubDrawer(String name) {
    if (activeDrawer != null) _drawerStack.add(activeDrawer!);
    activeDrawer = name;
    notifyListeners();
  }

  void backDrawer() {
    activeDrawer = _drawerStack.isEmpty ? null : _drawerStack.removeLast();
    if (activeDrawer == null) drawerOwner = null;
    notifyListeners();
  }

  void closeDrawers() {
    _clearDrawer();
    notifyListeners();
    _startHideTimer();
  }

  void closeSidePanel() {
    activeSidePanel = null;
    notifyListeners();
    _startHideTimer();
  }

  void toggleSidePanel(SidePanelType type) {
    AppLog.d('дія', 'бічна панель: ${type.name}');
    _clearDrawer();
    activeSidePanel = (activeSidePanel == type) ? null : type;
    showControls = true;
    notifyListeners();
  }

  /// Opens the panel (unlike [toggleSidePanel], does not close one that is already open)
  void openSidePanel(SidePanelType type) {
    _clearDrawer();
    activeSidePanel = type;
    showControls = true;
    notifyListeners();
  }

  void setSpeed(double s) {
    AppLog.i('дія', 'швидкість → ×$s');
    player.setRate(s);
    closeDrawers();
  }

  // TRACK SETTING METHODS
  // A person's choice (from the menu or keys) stops the language auto-selection for this file: it will not override their choice
  void setSubtitleTrack(SubtitleTrack track, {bool closeMenu = true}) {
    AppLog.i('дія', 'субтитри → ${track.id} ${track.language ?? ''} ${track.title ?? ''}');
    _trackChoiceManual = true;
    player.setSubtitleTrack(track);
    if (closeMenu) closeDrawers();
  }

  void setAudioTrack(AudioTrack track, {bool closeMenu = true}) {
    AppLog.i('дія', 'звукова доріжка → ${track.id} ${track.language ?? ''} ${track.title ?? ''}');
    _trackChoiceManual = true;
    player.setAudioTrack(track);
    if (closeMenu) closeDrawers();
  }

  /// Adds external subtitles (a `.srt`, `.ass`, `.vtt` … file) to the open video and turns them on immediately.
  /// `false`: no video is open or the file does not look like subtitles.
  Future<bool> addExternalSubtitle(String path) async {
    AppLog.i('дія', 'зовнішні субтитри: $path');
    if (!isSubtitleFile(path) || isHome || player.state.playlist.medias.isEmpty) return false;
    final name = path.split(RegExp(r'[/\\]')).last;
    setSubtitleTrack(SubtitleTrack.uri(path, title: name), closeMenu: false);
    showOsd('Субтитри', icon: Symbols.subtitles_rounded, detail: name);
    return true;
  }

  /// Subtitle file extensions mpv accepts
  static const List<String> subtitleExtensions = ['srt', 'ass', 'ssa', 'vtt', 'sub', 'sup', 'smi', 'lrc'];

  static bool isSubtitleFile(String path) {
    final dot = path.lastIndexOf('.');
    return dot >= 0 && subtitleExtensions.contains(path.substring(dot + 1).toLowerCase());
  }

  /// Files dropped on the window: a video opens as before (the first one); subtitles alone are added
  /// to the open video
  Future<void> handleDroppedFiles(List<String> paths) async {
    if (paths.isEmpty) return;
    final media = paths.where((p) => !isSubtitleFile(p)).toList();
    if (media.isNotEmpty) {
      await openFileOrPlaylist(media.first);
      return;
    }
    var added = false;
    for (final p in paths) {
      added = await addExternalSubtitle(p) || added;
    }
    if (!added) showOsd('Субтитри', icon: Symbols.subtitles_off_rounded, detail: 'Спершу відкрийте відео');
  }

  /// "Додати файл субтитрів…" in the subtitle menu
  Future<void> pickSubtitleFile() async {
    closeDrawers();
    String? path;
    try {
      final result = await FilePicker.pickFiles(
        // Android does not know the .srt / .ass types, so the picker there has no filter and we check the extension afterwards
        type: AppPlatform.isMobile ? FileType.any : FileType.custom,
        allowedExtensions: AppPlatform.isMobile ? null : subtitleExtensions,
      );
      path = result == null || result.files.isEmpty ? null : result.files.first.path;
    } catch (_) {}
    if (path == null) return;
    if (!await addExternalSubtitle(path)) showOsd('Субтитри', icon: Symbols.subtitles_off_rounded, detail: 'Це не файл субтитрів');
  }

  // ───────── Auto-selecting tracks by the language from settings ─────────
  bool _trackChoiceManual = false;
  String? _autoSubId;
  String? _autoAudioId;

  /// New file: auto-selection is allowed again
  void _resetAutoTracks() {
    _trackChoiceManual = false;
    _autoSubId = null;
    _autoAudioId = null;
  }

  /// Turns on subtitles and audio by language priority (see [TrackDefaults]). Called every time the track list
  /// changes (mpv adds external subtitles a bit later), but turns on the same track only once.
  /// Site episodes are not included: the driver turns on their subtitles.
  void _applyTrackDefaults(Tracks tracks) {
    if (_trackChoiceManual || _disposed || remote.active) return;
    final plan = TrackDefaults.plan(
      tracks,
      subtitlesEnabled: StorageService.getDefaultSubLang() != 'no',
      subPriorities: StorageService.getSubLangPriorities(),
      audioPriorities: StorageService.getAudioLangPriorities(),
    );
    final sub = plan.subtitle;
    if (sub != null && sub.id != _autoSubId) {
      _autoSubId = sub.id;
      player.setSubtitleTrack(sub);
      // We briefly report what was turned on: this shows that subtitles were chosen and which track exactly
      if (sub.id != 'no') showOsd('Субтитри', icon: Symbols.subtitles_rounded, detail: AppFormatters.formatTrackTitle(sub.language, sub.title));
    }
    final audio = plan.audio;
    if (audio != null && audio.id != _autoAudioId) {
      _autoAudioId = audio.id;
      player.setAudioTrack(audio);
    }
  }

  Future<void> changeHwdec(String newHwdec) async {
    AppLog.i('дія', 'декодер → $newHwdec');
    final dynamic platform = player.platform;
    if (platform != null) {
      await platform.setProperty('hwdec', newHwdec);
      currentHwdec = newHwdec;
      StorageService.saveHwdec(newHwdec);
      closeDrawers();
    }
  }

  bool _wasMaximized = false;

  Future<void> toggleFullscreen() async {
    AppLog.i('дія', 'повноекранний режим');
    // Phone: there is no separate full-screen mode; system bars in the player are always hidden
    if (!AppPlatform.isDesktop) return;
    final isFull = await windowManager.isFullScreen();
    if (!isFull) {
      // Full-screen mode does not enable correctly from a maximized window, so we first restore the normal state
      _wasMaximized = await windowManager.isMaximized();
      if (_wasMaximized) {
        await windowManager.unmaximize();
        await Future.delayed(const Duration(milliseconds: 120));
      }
      await windowManager.setFullScreen(true);
    } else {
      await windowManager.setFullScreen(false);
      if (_wasMaximized) {
        await Future.delayed(const Duration(milliseconds: 120));
        await windowManager.maximize();
        _wasMaximized = false;
      }
    }
    isFullscreen = !isFull;
    notifyListeners();
    _restoreKeyboardFocus();
  }

  /// After a switch to / from full screen (especially via the button) the window and the focused button lose keyboard focus,
  /// so hotkeys stop working: refocus the window and the player's key handler (the window settles a moment later, hence two tries)
  void _restoreKeyboardFocus() {
    for (final ms in const [0, 250]) {
      Future.delayed(Duration(milliseconds: ms), () async {
        if (!AppPlatform.isDesktop) return;
        try {
          await windowManager.focus();
        } catch (_) {}
        onRestoreKeyboardFocus?.call();
      });
    }
  }

  /// Mini player: a small window above everything with the video and minimal controls
  Future<void> enterMiniPlayer() async {
    AppLog.i('дія', 'вікно міні-плеєра');
    if (!AppPlatform.isDesktop) return; // the mini window exists only on desktop
    if (isMiniPlayer || isHome) return;
    _clearDrawer();
    activeSidePanel = null;
    if (showStatsOverlay) closeStatsOverlay();
    if (isFullscreen) {
      try {
        await windowManager.setFullScreen(false);
      } catch (_) {}
      isFullscreen = false;
    }
    try {
      _savedBounds = await windowManager.getBounds();
    } catch (_) {}
    isMiniPlayer = true;
    showControls = true;
    _syncShaderSuspension();
    notifyListeners();

    try {
      final w = player.state.width, h = player.state.height;
      final ratio = (w != null && h != null && w > 0 && h > 0) ? (w / h).clamp(1.0, 2.4) : 16 / 9;
      const double miniHeight = 236;
      await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
      await windowManager.setAspectRatio(ratio);
      await windowManager.setSize(Size(miniHeight * ratio, miniHeight));
      await windowManager.setAlignment(Alignment.bottomRight);
      await windowManager.setAlwaysOnTop(true);
    } catch (_) {}
  }

  Future<void> exitMiniPlayer() async {
    AppLog.i('дія', 'вихід із вікна міні-плеєра');
    if (!isMiniPlayer) return;
    isMiniPlayer = false;
    _syncShaderSuspension();
    notifyListeners();
    try {
      await windowManager.setAlwaysOnTop(false);
      isAlwaysOnTop = false;
      await windowManager.setAspectRatio(0);
      await windowManager.setTitleBarStyle(TitleBarStyle.normal);
      final b = _savedBounds;
      if (b != null) {
        await windowManager.setBounds(b);
      } else {
        await windowManager.setSize(const Size(1280, 720));
        await windowManager.center();
      }
    } catch (_) {}
  }

  Future<void> returnToHome() async {
    AppLog.i('дія', 'повернення на головну: відео закрито ($currentTitle)');
    SeekPreviewService.dispose();
    // A collapsed player stays collapsed until the very end: otherwise any notification during the awaits below
    // would "expand" the player (with its screen orientation) and only then would it close
    if (isMiniPlayer) await exitMiniPlayer();
    remote.stop(); // saves the episode position while the player still knows it
    persistQueue();
    if (currentFilePath.isNotEmpty && player.state.duration.inMilliseconds > 0) {
      StorageService.savePlaybackPosition(currentFilePath, player.state.position.inMilliseconds, player.state.duration.inMilliseconds);
      await StorageService.flush();
    }
    await player.stop();
    currentFilePath = "";
    playlistItems = [];
    currentChapters = [];
    _clearDrawer();
    activeSidePanel = null;
    dismissedChapterStartTime = null;
    isCollapsed = false; // now showHome becomes true, so the orientation is restored at once, without an intermediate player
    notifyListeners();
    unlockRotation(announce: false);
  }

  void openStatsOverlay() {
    AppLog.i('дія', 'відкрито статистику');
    _clearDrawer();
    showStatsOverlay = true;
    notifyListeners();

    Future.delayed(const Duration(milliseconds: 150), () {
      if (showStatsOverlay) {
        _fetchLiveStats();
        _liveStatsTimer?.cancel();
        _liveStatsTimer = Timer.periodic(const Duration(milliseconds: 800), (_) {
          if (showStatsOverlay) _fetchLiveStats();
        });
      }
    });
  }

  void closeStatsOverlay() {
    AppLog.d('дія', 'закрито статистику');
    _liveStatsTimer?.cancel();
    showStatsOverlay = false;
    notifyListeners();
  }

  Future<void> _fetchLiveStats() async {
    final stats = await MpvConfig.fetchLiveStats(player: player, currentSpeed: currentSpeed, currentHwdec: currentHwdec);
    if (_disposed) return;
    liveStats.value = stats;
  }

  void setVolumeDelta(double delta) {
    currentVolume = (currentVolume + delta).clamp(0.0, 100.0);
    isMuted = false;
    player.setVolume(currentVolume);
    showOsd(
      'Гучність',
      icon: currentVolume <= 0
          ? Symbols.volume_off_rounded
          : (currentVolume < 50 ? Symbols.volume_down_rounded : Symbols.volume_up_rounded),
      detail: '${currentVolume.round()}%',
      progress: currentVolume / 100,
      onlyWhenControlsHidden: true,
    );
    _publishVolume();
  }

  void toggleMute() {
    AppLog.i('дія', 'звук ${isMuted ? 'увімкнено' : 'вимкнено'}');
    isMuted = !isMuted;
    player.setVolume(isMuted ? 0.0 : currentVolume);
    showOsd(
      isMuted ? 'Звук вимкнено' : 'Звук увімкнено',
      icon: isMuted ? Symbols.volume_off_rounded : Symbols.volume_up_rounded,
      onlyWhenControlsHidden: true,
    );
    _publishVolume();
  }

  // ───────── Direct access to mpv ─────────

  /// Runs an mpv command (`add contrast 1`, `frame-step`, `change-list …`). Does not throw errors.
  Future<void> mpv(List<String> args) async {
    try {
      final dynamic platform = player.platform;
      if (platform == null) return;
      await platform.command(args);
    } catch (e) {
      debugPrint('[mpv] ${args.join(' ')}: $e');
    }
  }

  /// The value of an mpv property as a string (an empty string if unavailable)
  Future<String> mpvGet(String property) async {
    try {
      final dynamic platform = player.platform;
      if (platform == null) return '';
      return (await platform.getProperty(property)) as String;
    } catch (_) {
      return '';
    }
  }

  // ───────── On-screen notifications ─────────

  void showOsd(
    String title, {
    IconData icon = Symbols.info_rounded,
    String? detail,
    List<String> keys = const [],
    double? progress,
    bool isError = false,
    Duration? duration,
    bool onlyWhenControlsHidden = false,
  }) {
    // When the control panel is visible, the value (volume, position) is already visible on it
    if (onlyWhenControlsHidden && showControls) return;
    _pushOsd(
      OsdMessage(icon: icon, title: title, detail: detail, keys: keys, progress: progress?.clamp(0.0, 1.0), isError: isError),
      duration: duration,
    );
  }

  void _pushOsd(OsdMessage message, {Duration? duration}) {
    osd.value = message;
    _osdTimer?.cancel();
    _osdTimer = Timer(duration ?? const Duration(milliseconds: 1700), () => osd.value = null);
  }

  // ───────── Keyboard, window, screenshots ─────────

  void setKeyScheme(KeyScheme scheme) {
    if (keyScheme == scheme) return;
    keyScheme = scheme;
    StorageService.saveKeyScheme(scheme.name);
    notifyListeners();
  }

  Future<void> toggleAlwaysOnTop() async {
    AppLog.i('дія', 'поверх усіх вікон');
    if (!AppPlatform.isDesktop) return;
    isAlwaysOnTop = !isAlwaysOnTop;
    try {
      await windowManager.setAlwaysOnTop(isAlwaysOnTop);
    } catch (_) {}
    showOsd('Поверх усіх вікон', icon: Symbols.push_pin_rounded, detail: isAlwaysOnTop ? 'увімкнено' : 'вимкнено');
    notifyListeners();
  }

  /// Saves a snapshot of the current frame to `Pictures/MikiMiki`
  Future<void> takeScreenshot({bool withSubtitles = true}) async {
    AppLog.i('дія', 'знімок екрана (субтитри: $withSubtitles)');
    try {
      final bytes = await player.screenshot(format: 'image/png', includeLibassSubtitles: withSubtitles);
      if (bytes == null || bytes.isEmpty) {
        showOsd('Не вдалося зробити знімок', icon: Symbols.error_rounded, isError: true);
        return;
      }
      final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
      // Android: the shared "Pictures" folder (the snapshot cannot be retrieved from the app cache); if that fails, the cache
      final bases = <String>[
        if (Platform.isAndroid) '/storage/emulated/0/Pictures' else if (home != null) '$home/Pictures',
        Directory.systemTemp.path,
      ];
      Directory? dir;
      for (final base in bases) {
        try {
          final d = Directory('$base/${AppIdentity.shortName}');
          if (!await d.exists()) await d.create(recursive: true);
          dir = d;
          break;
        } catch (_) {}
      }
      if (dir == null) throw const FileSystemException('Немає доступної папки для знімків');

      String two(int n) => n.toString().padLeft(2, '0');
      final now = DateTime.now();
      var title = currentTitle.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_').trim();
      if (title.length > 80) title = title.substring(0, 80).trim();
      if (title.isEmpty) title = 'screenshot';
      final at = AppFormatters.formatTime(player.state.position).replaceAll(':', '-');
      final stamp = '${now.year}${two(now.month)}${two(now.day)}-${two(now.hour)}${two(now.minute)}${two(now.second)}';
      final name = '$title [$at] $stamp.png';
      await File('${dir.path}/$name').writeAsBytes(bytes);
      showOsd('Знімок збережено', icon: Symbols.photo_camera_rounded, detail: name, duration: const Duration(seconds: 3));
    } catch (e) {
      showOsd('Не вдалося зберегти знімок', icon: Symbols.error_rounded, detail: '$e', isError: true);
    }
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    SystemControls.inPip.removeListener(_onPipChanged);
    if (SystemControls.onPipToggle == _onPipToggle) SystemControls.onPipToggle = null;
    if (SystemControls.onAudioFocus == _onAudioFocus) SystemControls.onAudioFocus = null;
    if (SystemControls.onAudioRoute == _audioRoute.routeChanged) SystemControls.onAudioRoute = null;
    if (SystemControls.onAudioNoisy == _audioRoute.becomingNoisy) SystemControls.onAudioNoisy = null;
    _audioRoute.dispose();
    if (MediaControls.onButton == _onMediaButton) MediaControls.onButton = null;
    MediaControls.clear();
    _hideTimer?.cancel();
    _touchHide.cancel();
    _positionSaveTimer?.cancel();
    _liveStatsTimer?.cancel();
    _osdTimer?.cancel();
    _diag?.dispose();
    anime4k.removeListener(notifyListeners);
    anime4k.dispose();
    remote.removeListener(notifyListeners);
    remote.dispose();
    osd.dispose();
    liveStats.dispose();
    volumeState.dispose();
    SeekPreviewService.dispose();
    StorageService.flush();
    PlaybackClock.release(player);
    player.dispose();
    super.dispose();
  }
}