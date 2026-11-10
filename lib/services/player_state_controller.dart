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
import 'orientation_policy.dart';
import 'player_diagnostics.dart';
import 'osd_message.dart';
import 'playback_clock.dart';
import 'player_actions.dart';
import 'shortcut_catalog.dart';
import 'storage_service.dart';
import 'thumbnail_service.dart';
import 'seek_preview_service.dart';
import 'system_controls.dart';
import 'touch_hide_timer.dart';
import 'mpv_config.dart';
import 'playlist_service.dart';
import 'remote_driver.dart';
import 'remote_engine.dart';
import 'remote_playback.dart';
import 'source_prefs.dart';
import 'source_registry.dart';
import 'stream_resolver.dart';
import 'track_defaults.dart';

class PlayerStateController extends ChangeNotifier {
  late final Player player;
  late final VideoController videoController;

  double currentSpeed = 1.0;
  double prevSpeed = 1.0;
  double currentVolume = 100.0;

  /// Гучність і «mute» для повзунка в доці. Окремий нотифікатор: перетягування повзунка чи колесо
  /// дають десятки подій на секунду, і вони не повинні перебудовувати весь екран.
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
  /// Плеєр згорнуто в док поверх головної сторінки (відтворення триває)
  bool isCollapsed = false;
  Rect? _savedBounds;

  String currentFilePath = "";
  String currentTitle = "YouTube Mobile";
  String? activeDrawer;
  /// Стек навігації всередині меню (Налаштування → Більше → Декодер)
  final List<String> _drawerStack = [];
  /// Кнопка, яка відкрила меню: 'settings' / 'subs' / 'audio' / 'speed'.
  /// Саме за нею підсвічуються кнопки доку, а не за поточною сторінкою меню.
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
  List<VideoChapter> currentChapters = [];
  List<CachedSubtitleTrack> cachedSubtitleTracks = [];
  List<CachedAudioTrack> cachedAudioTracks = [];
  /// Живі показники для «Статистики для нердів». Окремий нотифікатор: опитування раз на ~0,8 с
  /// не перебудовує весь екран (і саме не заважає вимірюваним пропускам кадрів).
  final ValueNotifier<PlaybackStats> liveStats = ValueNotifier<PlaybackStats>(const PlaybackStats());
  PlaybackStats get currentStats => liveStats.value;
  final List<String> mpvLogs = [];

  // ───────── Екранні сповіщення (OSD) ─────────
  final ValueNotifier<OsdMessage?> osd = ValueNotifier<OsdMessage?>(null);
  Timer? _osdTimer;

  // ───────── Anime4K ─────────
  late final Anime4kController anime4k = Anime4kController(
    command: mpv,
    osd: (message, {duration}) => _pushOsd(message, duration: duration),
  );

  // ───────── Серії із сайтів («Дивитись») ─────────
  /// Перегляд серій із сайтів-джерел: чергу, пошук посилань, місце, «переглянуто» й автоперехід веде драйвер.
  /// Для решти інтерфейсу це виглядає як звичайна черга: `playlistItems` — серії, `currentFilePath` — ключ серії.
  late final RemoteDriver remote = RemoteDriver(
    engine: MpvRemoteEngine(player: player, command: mpv),
    registry: SourceRegistry.instance,
    resolver: StreamResolver(maxHeight: () => SourcePrefs.instance.maxHeight, preferredHoster: () => SourcePrefs.instance.hoster),
  );

  // ───────── Гарячі клавіші ─────────
  late final PlayerActions actions = PlayerActions(this);
  KeyScheme keyScheme = KeyScheme.standard;
  bool isAlwaysOnTop = false;

  /// Відкриває довідку з гарячих клавіш (задає екран плеєра, якому відомий контекст і масштаб)
  VoidCallback? onShowShortcuts;

  Timer? _hideTimer;
  Timer? _positionSaveTimer;
  Timer? _liveStatsTimer;

  /// Сенсорний екран: панелі ховає цей таймер (4 с без дотиків), а не вихід курсора із зони
  late final TouchHideTimer _touchHide = TouchHideTimer(
    shouldStayVisible: () =>
        _disposed || isHome || !player.state.playing || isSpeeding || activeDrawer != null || activeSidePanel != null || showStatsOverlay,
    onHide: () {
      if (!showControls) return;
      showControls = false;
      notifyListeners();
    },
  );

  /// Ключ твору для збереженої затримки звуку: серії із сайту — аніме та озвучка, локальні файли — тека
  String get audioDelayKey {
    final sess = remote.session;
    if (remote.active && sess != null) return 'r|${sess.animeKey}|${sess.groupLabel}';
    if (currentFilePath.isEmpty) return '';
    final path = currentFilePath.replaceAll('\\', '/');
    final cut = path.lastIndexOf('/');
    return cut > 0 ? 'l|${path.substring(0, cut)}' : 'l|$path';
  }

  /// Повертає твору його затримку звуку (mpv інакше тягне значення попередньої серії)
  Future<void> _applyAudioDelay() async {
    final key = audioDelayKey;
    if (key.isEmpty) return;
    try {
      final dynamic platform = player.platform;
      await platform?.setProperty('audio-delay', (StorageService.getAudioDelay(key) / 1000).toStringAsFixed(3));
    } catch (_) {}
  }

  bool get isHome => currentFilePath.isEmpty && playlistItems.isEmpty;

  /// Показувати головну сторінку (немає медіа або плеєр згорнуто)
  bool get showHome => isHome || isCollapsed;

  void collapsePlayer() {
    if (isHome || isCollapsed) return;
    _clearDrawer();
    activeSidePanel = null;
    if (showStatsOverlay) closeStatsOverlay();
    AppLog.i('дія', 'плеєр згорнуто в міні-плеєр: $currentTitle');
    isCollapsed = true;
    notifyListeners(); // орієнтацію при цьому повертає _syncSystemUi
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
        // Android: у збірці libmpv немає жодного системного шрифту, тож без власного libass не малює субтитри взагалі
        libassAndroidFont: MpvConfig.androidSubtitleFontAsset,
        libassAndroidFontName: MpvConfig.androidSubtitleFontName,
        bufferSize: 64 * 1024 * 1024,
        // Детальний журнал: докладніші повідомлення рушія (зміна діє після перезапуску застосунку)
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
    // Anime4K підключаємо після базового налаштування рушія (і mpv.conf користувача)
    MpvConfig.configureEngine(player, currentHwdec).then((_) => anime4k.syncToEngine());

    _bindStreams();
    _bindRemote();
    _startHideTimer();
    _diag = PlayerDiagnostics(player, context: _diagContext)..start();

    if (AppPlatform.isMobile) {
      _ready = true;
      SystemControls.inPip.addListener(_onPipChanged);
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
      // Під час «mute» плеєр повідомляє 0 — запам'ятовуємо реальну гучність, щоб її можна було повернути
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

    // Телефон: автоматичний вхід у PiP має бути ввімкнений лише під час відтворення
    player.stream.playing.listen((_) {
      if (AppPlatform.isMobile && _ready && !_disposed) _syncPipArm();
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
        // Серія із сайту: місце відновив драйвер (Media.start), розділи — з таймкодів сайту
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
      if (remote.active) return; // у mpv лише одне відео; чергу серій веде драйвер
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
      // Докладні (v / debug / trace) рядки йдуть лише у журнал-файл, щоб не витісняти важливе з вікна статистики
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

  /// Прев'юшка поточного відео береться прямо з плеєра (без повторного декодування файлу)
  Future<void> _captureLiveThumbnail() async {
    final pl = player.state.playlist;
    if (pl.index < 0 || pl.index >= pl.medias.length) return;
    final uri = pl.medias[pl.index].uri;
    if (_liveThumbUri == uri || ThumbnailService.getCachedThumbnail(uri) != null) return;
    _liveThumbUri = uri;

    await Future.delayed(const Duration(seconds: 6));
    // Якщо за цей час переключили файл — знімок вже не той
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

  /// Курсор у «активній зоні» (верх або низ екрана): інтерфейс показується і не зникає, доки курсор там
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

  /// Дія користувача без курсора (клавіатура, відкриття файлу): інтерфейс не показується,
  /// лише перевіряємо, чи його не пора сховати.
  void refreshSettings() => notifyListeners();

  void handleInteraction() => _startHideTimer();

  /// Тап по відео на телефоні: показує панелі (і запускає автоприховування) або одразу ховає їх
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

  /// Будь-який дотик, поки панелі видно, відкладає їх приховування
  void touchActivity() {
    if (showControls && !isHome) _touchHide.arm();
  }

  // ── Телефон: PiP, поворот екрана, системні панелі, кнопка «Назад» ──────────

  /// Вікно застосунку зараз у режимі «картинка в картинці»
  bool get isInPip => SystemControls.inPip.value;

  /// Пристрій підтримує PiP (кнопка PiP показується лише тоді)
  bool pipSupported = false;

  /// Орієнтація екрана: налаштування «Орієнтація плеєра» діє, поки відео на екрані, а при виході чи згортанні
  /// в міні-плеєр повертається попередня
  late final OrientationPolicy _orientation = OrientationPolicy(
    apply: SystemChrome.setPreferredOrientations,
    preference: () => PlayerOrientation.parse(StorageService.getPlayerOrientation()),
    log: (m) => AppLog.i('орієнтація', m),
  );

  /// Орієнтацію зафіксовано (налаштуванням або кнопкою); інакше її визначає датчик і системне блокування повороту
  bool get rotationLocked => _orientation.locked;

  /// Налаштування «Орієнтація плеєра» змінили: застосувати одразу, якщо відео на екрані
  void refreshOrientationPreference() {
    if (AppPlatform.isMobile) _orientation.preferenceChanged();
  }

  PlayerDiagnostics? _diag;

  /// Додаткові дані для знімків синхронізації в журналі
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

  /// `init()` завершено (плеєр створено)
  bool _ready = false;

  @override
  void notifyListeners() {
    super.notifyListeners();
    if (AppPlatform.isMobile && _ready && !_disposed) {
      _syncSystemUi();
      _syncPipArm();
    }
  }

  /// Відео — на весь екран без системних панелей; головна — з ними
  void _syncSystemUi() {
    // Плеєр на екрані — діє «Орієнтація плеєра»; вийшов чи згорнувся — повертається попередня
    if (showHome) {
      _orientation.leavePlayer();
    } else {
      _orientation.enterPlayer();
    }
    final immersive = !showHome && !isInPip;
    if (_systemUiImmersive == immersive) return;
    _systemUiImmersive = immersive;
    SystemChrome.setEnabledSystemUIMode(immersive ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
    // Яскравість, виставлена жестом, діє лише у відео; на головній — системна
    if (immersive) {
      SystemControls.restoreBrightness();
    } else if (showHome) {
      SystemControls.resetBrightness();
    }
  }

  /// Пропорції кадру для вікна PiP
  (int, int) _pipSize() {
    final w = player.state.width, h = player.state.height;
    return (w != null && h != null && w > 0 && h > 0) ? (w, h) : (16, 9);
  }

  /// Автоматичний вхід у PiP (жест «додому») — лише поки відео відтворюється
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

  void _onPipChanged() {
    if (_disposed) return;
    AppLog.i('дія', isInPip ? 'увійшов у PiP' : 'вийшов із PiP');
    if (isInPip) {
      _clearDrawer();
      activeSidePanel = null;
      if (showStatsOverlay) closeStatsOverlay();
      showControls = false;
    } else {
      showControls = true;
      _startHideTimer();
      // Вікно PiP закрили хрестиком: застосунок уже не на екрані — зупиняємо відтворення
      final life = WidgetsBinding.instance.lifecycleState;
      if (life == AppLifecycleState.paused || life == AppLifecycleState.hidden || life == AppLifecycleState.detached) {
        onAppBackgrounded();
      }
    }
    notifyListeners();
  }

  /// Екранне сповіщення, зібране ззовні (жести яскравості / гучності / перемотки)
  void showOsdMessage(OsdMessage message, {Duration? duration}) => _pushOsd(message, duration: duration);

  /// Кнопка PiP: згортає відео у маленьке вікно поверх інших застосунків
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

  /// Кнопка повороту: портрет ↔ альбомна (і фіксує вибір)
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

  /// Повертає автоповорот (орієнтацію знову визначає датчик)
  Future<void> unlockRotation({bool announce = true}) async {
    if (!AppPlatform.isMobile || !rotationLocked) return;
    AppLog.i('дія', 'автоповорот увімкнено');
    _orientation.unlock();
    notifyListeners();
    if (announce) {
      showOsd('Автоповорот', icon: Symbols.screen_rotation_rounded, duration: const Duration(seconds: 2));
    }
  }

  /// Системна кнопка «Назад»: закриває верхній шар інтерфейсу. false — закривати нічого, можна виходити.
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
      closeSidePanel();
      return true;
    }
    if (!showHome) {
      collapsePlayer();
      return true;
    }
    return false;
  }

  /// Застосунок пішов у фон (не PiP): ставимо на паузу й зберігаємо позицію
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

  /// Зберігає поточну чергу (лише з кількох елементів), щоб її можна було відновити з головної
  void persistQueue() {
    if (remote.active || playlistItems.length < 2) return; // серії із сайтів не є «останньою чергою» файлів
    StorageService.saveLastQueue(_queueSnapshot(), currentPlaylistIndex);
  }

  /// Відкриває збережену чергу / плейлист, починаючи з [startIndex].
  /// Локальні файли, яких більше немає на диску, пропускаються.
  Future<void> openQueue(List<Map<String, String>> items, {int startIndex = 0}) async {
    AppLog.i('дія', 'відкрито чергу: ${items.length} елем., старт з ${startIndex + 1}');
    remote.stop();
    final valid = <Map<String, String>>[];
    String? wantedUri = (startIndex >= 0 && startIndex < items.length) ? items[startIndex]['uri'] : null;
    // Наявність файлів перевіряємо асинхронно й паралельно: синхронний обхід довгої черги на
    // повільному диску (SD-картка, мережевий шлях) заморожував би інтерфейс
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

  /// [to] — індекс після вилучення елемента (як у ReorderableListView.onReorderItem)
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

  /// Кнопка «наступний»: у черзі файлів — наступний файл, у серіях із сайту — наступна серія
  Future<void> playNext() async {
    AppLog.i('дія', 'наступний елемент черги');
    if (!remote.active) {
      await player.next();
      return;
    }
    if (!await remote.next()) showOsd('Це остання серія', icon: Symbols.queue_music_rounded);
  }

  /// Кнопка «попередній»
  Future<void> playPrevious() async {
    AppLog.i('дія', 'попередній елемент черги');
    if (!remote.active) {
      await player.previous();
      return;
    }
    if (!await remote.previous()) showOsd('Це перша серія', icon: Symbols.queue_music_rounded);
  }

  // ───────── Серії із сайтів ─────────

  /// Запускає перегляд із сторінки аніме: [launch] несе озвучку, стартову серію й усі варіанти для перемикання
  Future<void> openRemote(RemoteLaunch launch) async {
    AppLog.i('дія', 'відкриваю серії із джерела');
    StorageService.flush();
    isCollapsed = false;
    _hasResumedPlayback = true; // місце відновлює драйвер (Media.start), а не слухач тривалості
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
    remote.onMessage = (text, {bool error = false}) => showOsd(
          text,
          icon: error ? Symbols.error_rounded : Symbols.skip_next_rounded,
          isError: error,
          duration: const Duration(seconds: 2),
        );
    remote.addListener(notifyListeners);
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

  /// Відкриває панель (на відміну від [toggleSidePanel], уже відкриту не закриває)
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

  // МЕТОДИ ВСТАНОВЛЕННЯ ДОРІЖОК
  // Вибір людини (з меню чи клавішами) зупиняє автовибір за мовою для цього файлу: він не переб'є її вибір
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

  /// Додає зовнішні субтитри (файл `.srt`, `.ass`, `.vtt` …) до відкритого відео й одразу вмикає їх.
  /// `false` — відео не відкрито або файл не схожий на субтитри.
  Future<bool> addExternalSubtitle(String path) async {
    AppLog.i('дія', 'зовнішні субтитри: $path');
    if (!isSubtitleFile(path) || isHome || player.state.playlist.medias.isEmpty) return false;
    final name = path.split(RegExp(r'[/\\]')).last;
    setSubtitleTrack(SubtitleTrack.uri(path, title: name), closeMenu: false);
    showOsd('Субтитри', icon: Symbols.subtitles_rounded, detail: name);
    return true;
  }

  /// Розширення файлів субтитрів, що їх приймає mpv
  static const List<String> subtitleExtensions = ['srt', 'ass', 'ssa', 'vtt', 'sub', 'sup', 'smi', 'lrc'];

  static bool isSubtitleFile(String path) {
    final dot = path.lastIndexOf('.');
    return dot >= 0 && subtitleExtensions.contains(path.substring(dot + 1).toLowerCase());
  }

  /// Файли, перетягнуті на вікно: відео відкривається як і раніше (перше з них); самі лише субтитри додаються
  /// до відкритого відео
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

  /// «Додати файл субтитрів…» у меню субтитрів
  Future<void> pickSubtitleFile() async {
    closeDrawers();
    String? path;
    try {
      final result = await FilePicker.pickFiles(
        // Android не знає типів .srt / .ass, тож там вибір без фільтра, а розширення перевіряємо після нього
        type: AppPlatform.isMobile ? FileType.any : FileType.custom,
        allowedExtensions: AppPlatform.isMobile ? null : subtitleExtensions,
      );
      path = result == null || result.files.isEmpty ? null : result.files.first.path;
    } catch (_) {}
    if (path == null) return;
    if (!await addExternalSubtitle(path)) showOsd('Субтитри', icon: Symbols.subtitles_off_rounded, detail: 'Це не файл субтитрів');
  }

  // ───────── Автовибір доріжок за мовою з налаштувань ─────────
  bool _trackChoiceManual = false;
  String? _autoSubId;
  String? _autoAudioId;

  /// Новий файл: автовибір знову дозволений
  void _resetAutoTracks() {
    _trackChoiceManual = false;
    _autoSubId = null;
    _autoAudioId = null;
  }

  /// Вмикає субтитри й звук за пріоритетом мов (див. [TrackDefaults]). Викликається щоразу, як змінився перелік
  /// доріжок (зовнішні субтитри mpv додає трохи згодом), але одну й ту саму доріжку вмикає лише раз.
  /// Серії із сайтів сюди не входять: їхні субтитри вмикає драйвер.
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
      // Коротко повідомляємо, що ввімкнено: так видно, що субтитри обрано, і яку саме доріжку
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
    // Телефон: окремого повноекранного режиму немає — системні панелі в плеєрі приховані завжди
    if (!AppPlatform.isDesktop) return;
    final isFull = await windowManager.isFullScreen();
    if (!isFull) {
      // З розгорнутого вікна повноекранний режим не вмикається коректно — спершу повертаємо звичайний стан
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
  }

  /// Міні-плеєр: маленьке вікно поверх усіх з відео та мінімальним керуванням
  Future<void> enterMiniPlayer() async {
    AppLog.i('дія', 'вікно міні-плеєра');
    if (!AppPlatform.isDesktop) return; // міні-вікно є лише на десктопі
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
    // Згорнутий плеєр лишається згорнутим до самого кінця: інакше будь-яке сповіщення під час await нижче
    // «розгортало» б плеєр (з його орієнтацією екрана), а вже потім він закривався
    if (isMiniPlayer) await exitMiniPlayer();
    remote.stop(); // зберігає місце серії, поки плеєр ще знає позицію
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
    isCollapsed = false; // тепер showHome стає true, тож орієнтація повертається одразу, без проміжного плеєра
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

  // ───────── Прямий доступ до mpv ─────────

  /// Виконує команду mpv (`add contrast 1`, `frame-step`, `change-list …`). Помилки не кидає.
  Future<void> mpv(List<String> args) async {
    try {
      final dynamic platform = player.platform;
      if (platform == null) return;
      await platform.command(args);
    } catch (e) {
      debugPrint('[mpv] ${args.join(' ')}: $e');
    }
  }

  /// Значення властивості mpv у вигляді рядка (порожній рядок, якщо недоступна)
  Future<String> mpvGet(String property) async {
    try {
      final dynamic platform = player.platform;
      if (platform == null) return '';
      return (await platform.getProperty(property)) as String;
    } catch (_) {
      return '';
    }
  }

  // ───────── Екранні сповіщення ─────────

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
    // Коли видно панель керування, значення (гучність, позиція) і так видно на ній
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

  // ───────── Клавіатура, вікно, знімки ─────────

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

  /// Зберігає знімок поточного кадру в `Зображення/MikiMiki`
  Future<void> takeScreenshot({bool withSubtitles = true}) async {
    AppLog.i('дія', 'знімок екрана (субтитри: $withSubtitles)');
    try {
      final bytes = await player.screenshot(format: 'image/png', includeLibassSubtitles: withSubtitles);
      if (bytes == null || bytes.isEmpty) {
        showOsd('Не вдалося зробити знімок', icon: Symbols.error_rounded, isError: true);
        return;
      }
      final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
      // Android: спільна папка «Зображення» (із кешу застосунку знімок не дістати); якщо не вийшло — кеш
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