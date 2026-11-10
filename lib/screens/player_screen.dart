import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:desktop_drop/desktop_drop.dart';

import '../constants/app_constants.dart';
import '../models/media_models.dart';
import '../utils/platform_info.dart';
import '../services/ui_theme_service.dart';
import '../services/storage_service.dart';
import '../services/player_state_controller.dart';
import '../services/keyboard_shortcuts.dart';
import '../services/remote_playback.dart';
import '../widgets/app_animation_kit.dart';
import '../widgets/home_hub.dart';
import '../widgets/side_panel.dart';
import '../widgets/skip_button.dart';
import '../widgets/controls_overlay.dart';
import '../widgets/stats_overlay.dart';
import '../widgets/video_viewport.dart';
import '../widgets/side_panel_drawer.dart';
import '../widgets/app_settings_dialog.dart';
import '../widgets/mini_player.dart';
import '../widgets/collapsed_player.dart';
import '../widgets/center_flash.dart';
import '../widgets/osd_toast.dart';
import '../widgets/shortcuts_view.dart';
import '../widgets/mobile_controls.dart';
import '../widgets/mobile_gesture_layer.dart';
import '../widgets/mobile_sheet.dart';
import '../widgets/remote_status_overlay.dart';
import '../widgets/settings_drawer.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> with WidgetsBindingObserver {
  final PlayerStateController state = PlayerStateController();
  final FocusNode _keyboardFocusNode = FocusNode();
  final ScrollController _drawerScrollController = AppSmoothScrollController();
  final ScrollController _logScrollController = AppSmoothScrollController();

  final GlobalKey _anime4kKey = GlobalKey();
  final GlobalKey _subsKey = GlobalKey();
  final GlobalKey _audioKey = GlobalKey();
  final GlobalKey _speedKey = GlobalKey();
  final GlobalKey _volumeKey = GlobalKey();
  final GlobalKey _playerAreaKey = GlobalKey();
  Size get _playerSize {
    final box = _playerAreaKey.currentContext?.findRenderObject();
    return (box is RenderBox && box.hasSize) ? box.size : Size.zero;
  }

  double get _playerWidth => _playerSize.width;
  final GlobalKey _settingsKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    state.init();
    WatchLauncher.attach(state.openRemote); // кнопка «Дивитись» на сторінках Hikka запускає серії тут
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
    WidgetsBinding.instance.addObserver(this);
  }

  /// Застосунок пішов у фон (не PiP): пауза й збереження позиції
  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (AppPlatform.isMobile && lifecycle == AppLifecycleState.paused) state.onAppBackgrounded();
  }

  bool _over(GlobalKey key, Offset p) {
    final box = key.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached) return false;
    final r = box.localToGlobal(Offset.zero) & box.size;
    return r.inflate(4).contains(p);
  }

  /// Колесо миші та дотики: глобальний маршрут, не залежить від hit-test віджетів.
  void _onPointer(PointerEvent e) {
    if (!mounted) return;
    // Телефон: кожен дотик (тап, перетягування повзунка) відкладає приховування панелей
    if (AppPlatform.isMobile && e.kind == PointerDeviceKind.touch && (e is PointerDownEvent || e is PointerMoveEvent || e is PointerUpEvent)) {
      state.touchActivity();
      return;
    }
    if (e is! PointerScrollEvent) return;
    if (ModalRoute.of(context)?.isCurrent == false) return;
    if (state.showHome) return;
    final dir = e.scrollDelta.dy < 0 ? 1.0 : -1.0;
    if (state.isMiniPlayer) {
      state.setVolumeDelta(dir * 5.0);
      return;
    }
    if (state.activeDrawer != null || state.showStatsOverlay) return;
    if (state.showControls) {
      if (_over(_speedKey, e.position)) {
        final next = (((state.currentSpeed + dir * 0.25).clamp(0.25, 2.5)) * 4).round() / 4;
        state.player.setRate(next);
        return;
      }
      if (_over(_volumeKey, e.position)) {
        state.setVolumeDelta(dir * 5.0);
        return;
      }
    }
    if (state.activeSidePanel != null && e.position.dx >= _playerWidth) return;
    state.setVolumeDelta(dir * 5.0);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WatchLauncher.detach(state.openRemote);
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
    _keyboardFocusNode.dispose();
    _drawerScrollController.dispose();
    _logScrollController.dispose();
    state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Реактивно слухаємо і стан плеєра, і глобальну тему
    return ListenableBuilder(
      listenable: Listenable.merge([state, uiTheme]),
      builder: (context, _) {
        final Widget screen = Focus(
          focusNode: _keyboardFocusNode,
          autofocus: true,
          onKeyEvent: (node, event) {
            if (state.isMiniPlayer && event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
              state.exitMiniPlayer();
              return KeyEventResult.handled;
            }
            return KeyboardShortcuts.handle(event, state);
          },
          child: Scaffold(
            backgroundColor: Colors.black,
            body: LayoutBuilder(
              builder: (context, constraints) {
                final bool mobile = AppPlatform.isMobile;
                final double screenHeight = constraints.maxHeight;
                final double rawScale = screenHeight / 720.0;
                // Телефон: масштаб не залежить від висоти (в альбомній вона мала); розміри нових віджетів задано в dp
                final double scale = mobile ? AppPlatform.mobileScale : (1.0 + (rawScale - 1.0) * 0.40).clamp(0.80, 1.25);
                // Довідка з гарячих клавіш (клавіші ? та F1) відкривається з контексту цього екрана
                state.onShowShortcuts = () => ShortcutsDialog.show(context, scale, state);

                return DropTarget(
                  onDragEntered: (_) => state.isDraggingFile = true,
                  onDragExited: (_) => state.isDraggingFile = false,
                  onDragDone: (detail) {
                    state.isDraggingFile = false;
                    if (detail.files.isNotEmpty) state.handleDroppedFiles([for (final f in detail.files) f.path]);
                  },
                  child: AppFadeSwitcher(
                    expand: true,
                    duration: AppAnim.normal,
                    child: state.showHome
                        ? _homeLayer(context, scale)
                        : state.isMiniPlayer
                            ? KeyedSubtree(
                                key: const ValueKey('mini'),
                                child: MiniPlayer(
                                  player: state.player,
                                  controller: state.videoController,
                                  title: state.currentTitle,
                                  onExpand: state.exitMiniPlayer,
                                  onClose: state.returnToHome,
                                ),
                              )
                            : mobile
                                ? _mobilePlayer(context, scale)
                                : _desktopPlayer(scale),
                  ),
                );
              },
            ),
          ),
        );
        return AppPlatform.isMobile ? _wrapMobile(screen) : screen;
      },
    );
  }

  // ── Телефон: кнопка «Назад», кольори системних панелей ─────────────────────

  Widget _wrapMobile(Widget child) {
    final bool darkIcons = uiTheme.isLight && state.showHome;
    final Brightness icons = darkIcons ? Brightness.dark : Brightness.light;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // Закриває верхній шар (меню, панель, плеєр → головна); на головній — спершу сторінка каталогу,
        // а коли закривати нічого — вихід із застосунку
        if (state.handleBack()) return;
        if (HomeHub.backHandler?.call() ?? false) return;
        SystemNavigator.pop();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarContrastEnforced: false,
          statusBarIconBrightness: icons,
          systemNavigationBarIconBrightness: icons,
        ),
        child: child,
      ),
    );
  }

  // ── Головна ────────────────────────────────────────────────────────────────

  Widget _homeLayer(BuildContext context, double scale) {
    final bool mobile = AppPlatform.isMobile;
    final bool compact = HomeHub.isCompact(context);
    final EdgeInsets pad = mobile ? MediaQuery.paddingOf(context) : EdgeInsets.zero;
    // Згорнутий плеєр: на вузькому екрані — над нижньою навігацією на всю ширину, інакше в куті
    final double bottom = compact ? HomeHub.bottomNavHeight + pad.bottom + 12 : 24 * scale + pad.bottom;
    return KeyedSubtree(
      key: const ValueKey('home'),
      child: Stack(
        children: [
          Positioned.fill(
            child: HomeHub(
              scale: scale,
              reserveBottom: mobile && state.isCollapsed ? 104 : 0,
              onOpenFile: state.openFileOrPlaylist,
              onOpenMultipleFiles: state.openMultipleFiles,
              onOpenQueue: (items, i) => state.openQueue(items, startIndex: i),
              onOpenSettings: ({int? tab}) => AppSettingsDialog.show(context, scale, state, initialTab: tab ?? 0),
              settingsBuilder: mobile ? (ctx) => AppSettingsDialog(scale: scale, controller: state, embedded: true) : null,
            ),
          ),
          Positioned(
            left: compact ? 12 + pad.left : null,
            right: compact ? 12 + pad.right : 24 * scale + pad.right,
            bottom: bottom,
            child: AppPresence(
              visible: state.isCollapsed,
              slide: const Offset(0, 0.3),
              child: state.isCollapsed
                  ? CollapsedPlayer(
                      scale: scale,
                      player: state.player,
                      controller: state.videoController,
                      title: state.currentTitle,
                      onExpand: state.expandPlayer,
                      onClose: state.returnToHome,
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }

  // ── Десктоп: відео + панелі наведенням миші, бічна панель ──────────────────

  Widget _desktopPlayer(double scale) {
    return KeyedSubtree(
      key: const ValueKey('player'),
      child: Row(
        children: [
          Expanded(
            // Без LayoutBuilder: під час висування бокової панелі область відео лише
            // перелаштовується, а не перебудовується щокадру (розміри читаємо за ключем).
            child: Builder(
              builder: (context) {
                return MouseRegion(
                  key: _playerAreaKey,
                  onHover: (ev) => state.pointerInZone(ev.localPosition.dy <= 90 * scale || ev.localPosition.dy >= _playerSize.height - 150 * scale),
                  onExit: (_) => state.pointerInZone(false),
                  child: VideoViewport(
                    scale: scale,
                    controller: state.videoController,
                    isSpeeding: state.isSpeeding,
                    onSpeedStart: () {
                      state.prevSpeed = state.currentSpeed;
                      state.player.setRate(2.0);
                      state.isSpeeding = true;
                    },
                    onSpeedEnd: () {
                      state.player.setRate(state.prevSpeed);
                      state.isSpeeding = false;
                    },
                    doubleTapLabel: '${StorageService.getSeekStep()} с',
                    onDoubleTapSide: _doubleTapSeek(),
                    onTap: () {
                      if (state.showStatsOverlay) {
                        state.closeStatsOverlay();
                      } else if (state.activeDrawer != null) {
                        state.closeDrawers();
                      } else {
                        state.player.playOrPause();
                      }
                    },
                    overlays: [
                      CenterFlash(scale: scale, player: state.player),
                      SkipButton(
                        scale: scale,
                        showControls: state.showControls,
                        player: state.player,
                        chapters: state.currentChapters,
                        dismissedChapterStartTime: state.dismissedChapterStartTime,
                      ),
                      RemoteStatusOverlay(
                        scale: scale,
                        driver: state.remote,
                        onOpenPanel: () => state.openSidePanel(SidePanelType.episodes),
                        onClose: state.returnToHome,
                      ),
                      ControlsOverlay(
                        scale: scale,
                        showControls: state.showControls,
                        isSpeeding: state.isSpeeding,
                        isDraggingFile: state.isDraggingFile,
                        currentTitle: state.currentTitle,
                        player: state.player,
                        currentSpeed: state.currentSpeed,
                        volume: state.volumeState,
                        isFullscreen: state.isFullscreen,
                        activeDrawer: state.activeDrawer,
                        activeDrawerPrev: state.activeDrawerPrev,
                        drawerOwner: state.drawerOwner,
                        isEpisodesOpen: state.activeSidePanel == SidePanelType.episodes,
                        drawerAnchorPixelX: state.drawerAnchorPixelX,
                        drawerIsTop: state.drawerIsTop,
                        chapters: state.currentChapters,
                        subtitleTracks: state.cachedSubtitleTracks,
                        audioTracks: state.cachedAudioTracks,
                        currentHwdec: state.currentHwdec,
                        drawerScrollController: _drawerScrollController,
                        anime4k: state.anime4k,
                        settingsKey: _settingsKey,
                        anime4kKey: _anime4kKey,
                        subsKey: _subsKey,
                        audioKey: _audioKey,
                        speedKey: _speedKey,
                        volumeKey: _volumeKey,
                        onMiniPlayer: state.enterMiniPlayer,
                        onCollapse: state.collapsePlayer,
                        onClosePlayer: state.returnToHome,
                        onOpenFile: state.pickAndOpenFile,
                        onToggleFullscreen: state.toggleFullscreen,
                        onToggleMute: state.toggleMute,
                        onVolumeChanged: (vol) => state.setVolumeDelta(vol - state.currentVolume),
                        onSettingsTap: () => state.openDrawer('settings', _settingsKey, isTop: true),
                        onInfoTap: () => state.toggleSidePanel(SidePanelType.info),
                        onEpisodesTap: () => state.toggleSidePanel(SidePanelType.episodes),
                        onChaptersTap: () => state.toggleSidePanel(SidePanelType.chapters),
                        onAnime4kTap: () => state.openDrawer('anime4k', _anime4kKey),
                        onAnime4kSecondaryTap: state.anime4k.toggle,
                        onSubsTap: () => state.openDrawer('subs', _subsKey),
                        onAudioTap: () => state.openDrawer('audio', _audioKey),
                        onSpeedTap: () => state.openDrawer('speed', _speedKey),
                        onSpeedSecondaryTap: () {
                          final next = AppConstants.speeds[(AppConstants.speeds.indexOf(state.currentSpeed) + 1) % AppConstants.speeds.length];
                          state.player.setRate(next);
                        },
                        onCloseDrawer: state.closeDrawers,
                        onBackDrawer: state.backDrawer,
                        onOpenSubDrawer: state.openSubDrawer,
                        onSpeedSelected: state.setSpeed,
                        onSubtitleSelected: state.setSubtitleTrack,
                        onAddSubtitleFile: state.pickSubtitleFile,
                        onAudioSelected: state.setAudioTrack,
                        audioDelayKey: state.audioDelayKey,
                        onHwdecSelected: (h) => state.changeHwdec(h),
                        onOpenStats: state.openStatsOverlay,
                        onPrevious: state.playPrevious,
                        onNext: state.playNext,
                      ),
                      OsdToast(scale: scale, message: state.osd),
                      _statsLayer(scale),
                    ],
                  ),
                );
              },
            ),
          ),
          SidePanelDrawer(
            scale: scale,
            activeSidePanel: state.activeSidePanel,
            player: state.player,
            playlistItems: state.playlistItems,
            currentPlaylistIndex: state.currentPlaylistIndex,
            chapters: state.currentChapters,
            onClose: state.closeSidePanel,
            onAddMedia: state.addMediaToQueue,
            onEpisodeSelected: state.selectEpisode,
            onChapterSelected: (startTime) => state.player.seek(startTime),
            onQueueReorder: state.reorderQueue,
            onQueueRemove: state.removeFromQueue,
            onQueueClear: state.clearQueueExceptCurrent,
            remote: state.remote,
          ),
        ],
      ),
    );
  }

  /// Подвійний тап: перемотка на крок (null — вимкнено в налаштуваннях)
  ValueChanged<bool>? _doubleTapSeek() {
    if (!StorageService.getDoubleTapSeek()) return null;
    return (forward) {
      final step = Duration(seconds: StorageService.getSeekStep());
      final pos = state.player.state.position;
      state.player.seek(forward ? pos + step : (pos - step < Duration.zero ? Duration.zero : pos - step));
    };
  }

  /// «Статистика для нердів» на весь екран
  Widget _statsLayer(double scale) {
    return Positioned.fill(
      child: AppFadeSwitcher(
        expand: true,
        child: state.showStatsOverlay
            // Показники оновлюються окремим нотифікатором — без перебудови всього екрана
            ? ValueListenableBuilder<PlaybackStats>(
                key: const ValueKey('stats-on'),
                valueListenable: state.liveStats,
                builder: (context, stats, _) => StatsOverlay(
                  scale: scale,
                  player: state.player,
                  currentSpeed: state.currentSpeed,
                  currentVolume: state.currentVolume,
                  stats: stats,
                  mpvLogs: state.mpvLogs,
                  logScrollController: _logScrollController,
                  onClose: state.closeStatsOverlay,
                  onClearLogs: () => state.mpvLogs.clear(),
                ),
              )
            : const SizedBox.shrink(key: ValueKey('stats-off')),
      ),
    );
  }

  // ── Телефон: відео на весь екран, великі кнопки, жести, меню-панелі ────────

  Widget _mobilePlayer(BuildContext context, double scale) {
    final EdgeInsets pad = MediaQuery.paddingOf(context);
    final bool panelOpen = state.activeDrawer != null || state.activeSidePanel != null || state.showStatsOverlay;
    final sub = state.player.state.track.subtitle;
    final bool subtitlesOn = sub.id != 'no' && sub.id.isNotEmpty && state.cachedSubtitleTracks.isNotEmpty;
    final int queue = state.playlistItems.length;
    final rd = state.remote; // серії із сайту: свої «попередній / наступний» і підпис

    return KeyedSubtree(
      key: const ValueKey('player'),
      child: VideoViewport(
        scale: scale,
        controller: state.videoController,
        isSpeeding: state.isSpeeding,
        onSpeedStart: () {
          state.prevSpeed = state.currentSpeed;
          state.player.setRate(2.0);
          state.isSpeeding = true;
        },
        onSpeedEnd: () {
          state.player.setRate(state.prevSpeed);
          state.isSpeeding = false;
        },
        doubleTapLabel: '${StorageService.getSeekStep()} с',
        onDoubleTapSide: _doubleTapSeek(),
        onTap: () {
          if (state.showStatsOverlay) {
            state.closeStatsOverlay();
          } else if (state.activeDrawer != null) {
            state.closeDrawers();
          } else {
            // Тап показує / ховає панелі; пауза — кнопка по центру
            state.toggleControlsByTouch();
          }
        },
        // У вікні PiP лишається тільки відео (кнопки дає сама система)
        overlays: state.isInPip
            ? const []
            : [
                MobileGestureLayer(
                  player: state.player,
                  osd: state.showOsdMessage,
                  enabled: !panelOpen && !state.isSpeeding,
                ),
                SkipButton(
                  touch: true,
                  scale: scale,
                  showControls: state.showControls,
                  player: state.player,
                  chapters: state.currentChapters,
                  dismissedChapterStartTime: state.dismissedChapterStartTime,
                ),
                RemoteStatusOverlay(
                  scale: scale,
                  driver: rd,
                  onOpenPanel: () => state.openSidePanel(SidePanelType.episodes),
                  onClose: state.returnToHome,
                ),
                MobileControls(
                  visible: state.showControls && !state.isSpeeding,
                  player: state.player,
                  title: state.currentTitle,
                  subtitle: rd.active ? rd.nowPlaying(withKind: false) : (queue > 1 ? 'Серія ${state.currentPlaylistIndex + 1} з $queue' : ''),
                  chapters: state.currentChapters,
                  currentSpeed: state.currentSpeed,
                  anime4kActive: state.anime4k.active,
                  subtitlesOn: subtitlesOn,
                  hasQueue: rd.active ? (rd.hasNext || rd.hasPrevious) : queue > 1,
                  onPrevious: state.playPrevious,
                  onNext: state.playNext,
                  showTransport: !rd.showsStatus,
                  pipSupported: state.pipSupported,
                  rotationLocked: state.rotationLocked,
                  drawerOwner: state.drawerOwner,
                  isEpisodesOpen: state.activeSidePanel == SidePanelType.episodes,
                  seekStep: StorageService.getSeekStep(),
                  seekButtons: StorageService.getMobileSeekButtons(),
                  onBack: state.collapsePlayer,
                  onInfo: () => state.toggleSidePanel(SidePanelType.info),
                  onPip: state.enterPip,
                  onRotate: state.toggleRotation,
                  onRotateAuto: state.unlockRotation,
                  onSettings: () => state.openDrawer('settings', _settingsKey, isTop: true),
                  onSpeed: () => state.openDrawer('speed', _speedKey),
                  onAnime4k: () => state.openDrawer('anime4k', _anime4kKey),
                  onAnime4kToggle: state.anime4k.toggle,
                  onSubs: () => state.openDrawer('subs', _subsKey),
                  onAudio: () => state.openDrawer('audio', _audioKey),
                  onEpisodes: () => state.toggleSidePanel(SidePanelType.episodes),
                ),
                // Меню: у портреті нижня панель, в альбомній — бічна
                MobileSheetFrame(
                  open: state.activeDrawer != null,
                  onDismiss: state.closeDrawers,
                  child: state.activeDrawer == null
                      ? const SizedBox.shrink()
                      : SettingsDrawer(
                          sheet: true,
                          scale: scale,
                          activeDrawer: state.activeDrawer!,
                          activeDrawerPrev: state.activeDrawerPrev,
                          player: state.player,
                          currentSpeed: state.currentSpeed,
                          currentHwdec: state.currentHwdec,
                          subtitleTracks: state.cachedSubtitleTracks,
                          audioTracks: state.cachedAudioTracks,
                          chapters: state.currentChapters,
                          scrollController: _drawerScrollController,
                          onClose: state.closeDrawers,
                          onBack: state.backDrawer,
                          onOpenSubDrawer: state.openSubDrawer,
                          onSpeedSelected: state.setSpeed,
                          onSubtitleSelected: state.setSubtitleTrack,
                          onAddSubtitleFile: state.pickSubtitleFile,
                          onAudioSelected: state.setAudioTrack,
                        audioDelayKey: state.audioDelayKey,
                          onHwdecSelected: (h) => state.changeHwdec(h),
                          onOpenChaptersSidePanel: () => state.toggleSidePanel(SidePanelType.chapters),
                          onOpenStats: state.openStatsOverlay,
                          anime4k: state.anime4k,
                        ),
                ),
                MobileSheetFrame(
                  open: state.activeSidePanel != null,
                  onDismiss: state.closeSidePanel,
                  child: state.activeSidePanel == null
                      ? const SizedBox.shrink()
                      : SidePanel(
                          key: ValueKey(state.activeSidePanel),
                          sheet: true,
                          scale: scale,
                          type: state.activeSidePanel!,
                          player: state.player,
                          playlistItems: state.playlistItems,
                          currentPlaylistIndex: state.currentPlaylistIndex,
                          chapters: state.currentChapters,
                          onClose: state.closeSidePanel,
                          onAddMedia: state.addMediaToQueue,
                          onEpisodeSelected: state.selectEpisode,
                          onChapterSelected: (startTime) => state.player.seek(startTime),
                          onQueueReorder: state.reorderQueue,
                          onQueueRemove: state.removeFromQueue,
                          onQueueClear: state.clearQueueExceptCurrent,
                          remote: rd,
                        ),
                ),
                OsdToast(scale: scale, message: state.osd, topInset: pad.top),
                _statsLayer(scale),
              ],
      ),
    );
  }
}
