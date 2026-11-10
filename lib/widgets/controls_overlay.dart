import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import '../models/media_models.dart';
import '../services/anime4k_controller.dart';
import 'top_dock.dart';
import 'bottom_dock.dart';
import 'settings_drawer.dart';
import 'app_animation_kit.dart';

class ControlsOverlay extends StatelessWidget {
  final double scale;
  final bool showControls;
  final bool isSpeeding;
  final bool isDraggingFile;
  final String currentTitle;
  final Player player;
  final double currentSpeed;
  /// Гучність і «mute» — окремим нотифікатором, щоб їх зміна не перебудовувала всю панель
  final ValueListenable<VolumeState> volume;
  final bool isFullscreen;
  final String? activeDrawer;
  final String? activeDrawerPrev;
  final String? drawerOwner;
  final bool isEpisodesOpen;
  final double drawerAnchorPixelX;
  final bool drawerIsTop;
  final List<VideoChapter> chapters;
  final List<CachedSubtitleTrack> subtitleTracks;
  final List<CachedAudioTrack> audioTracks;
  final String currentHwdec;
  final ScrollController drawerScrollController;
  final Anime4kController anime4k;

  final GlobalKey settingsKey;
  final GlobalKey anime4kKey;
  final GlobalKey subsKey;
  final GlobalKey audioKey;
  final GlobalKey speedKey;
  final GlobalKey volumeKey;

  final VoidCallback onMiniPlayer;
  final VoidCallback onCollapse;
  final VoidCallback onClosePlayer;
  final VoidCallback onOpenFile;
  final VoidCallback onToggleFullscreen;
  final VoidCallback onToggleMute;
  final ValueChanged<double> onVolumeChanged;
  final VoidCallback onSettingsTap;
  final VoidCallback onInfoTap;
  final VoidCallback onEpisodesTap;
  final VoidCallback onChaptersTap;
  final VoidCallback onAnime4kTap;
  final VoidCallback onAnime4kSecondaryTap;
  final VoidCallback onSubsTap;
  final VoidCallback onAudioTap;
  final VoidCallback onSpeedTap;
  final VoidCallback onSpeedSecondaryTap;
  final VoidCallback onCloseDrawer;
  final VoidCallback onBackDrawer;
  final ValueChanged<String> onOpenSubDrawer;
  final ValueChanged<double> onSpeedSelected;
  final ValueChanged<SubtitleTrack> onSubtitleSelected;
  final VoidCallback? onAddSubtitleFile;
  final ValueChanged<AudioTrack> onAudioSelected;
  final String audioDelayKey;
  final ValueChanged<String> onHwdecSelected;
  final VoidCallback onOpenStats;

  /// «Попередній / наступний» у доці (див. [BottomDock.onPrevious])
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  const ControlsOverlay({
    super.key,
    required this.scale,
    required this.showControls,
    required this.isSpeeding,
    required this.isDraggingFile,
    required this.currentTitle,
    required this.player,
    required this.currentSpeed,
    required this.volume,
    required this.isFullscreen,
    required this.activeDrawer,
    required this.activeDrawerPrev,
    required this.drawerOwner,
    required this.isEpisodesOpen,
    required this.drawerAnchorPixelX,
    required this.drawerIsTop,
    required this.chapters,
    required this.subtitleTracks,
    required this.audioTracks,
    required this.currentHwdec,
    required this.drawerScrollController,
    required this.anime4k,
    required this.settingsKey,
    required this.anime4kKey,
    required this.subsKey,
    required this.audioKey,
    required this.speedKey,
    required this.volumeKey,
    required this.onMiniPlayer,
    required this.onCollapse,
    required this.onClosePlayer,
    required this.onOpenFile,
    required this.onToggleFullscreen,
    required this.onToggleMute,
    required this.onVolumeChanged,
    required this.onSettingsTap,
    required this.onInfoTap,
    required this.onEpisodesTap,
    required this.onChaptersTap,
    required this.onAnime4kTap,
    required this.onAnime4kSecondaryTap,
    required this.onSubsTap,
    required this.onAudioTap,
    required this.onSpeedTap,
    required this.onSpeedSecondaryTap,
    required this.onCloseDrawer,
    required this.onBackDrawer,
    required this.onOpenSubDrawer,
    required this.onSpeedSelected,
    required this.onSubtitleSelected,
    this.onAddSubtitleFile,
    required this.onAudioSelected,
    this.audioDelayKey = '',
    required this.onHwdecSelected,
    required this.onOpenStats,
    this.onPrevious,
    this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    // Панель видно лише тоді, коли вона має слідкувати за відтворенням
    final bool visible = showControls && !isSpeeding && !isDraggingFile;
    return Positioned.fill(
      child: RepaintBoundary(
        child: AppFade(
          opacity: visible ? 1.0 : 0.0,
          duration: AppAnim.normal,
          child: IgnorePointer(
            ignoring: !visible,
            child: Stack(
              children: [
                TopDock(
                  scale: scale,
                  title: currentTitle,
                  player: player,
                  settingsKey: settingsKey,
                  isSettingsOpen: drawerOwner == 'settings',
                  onCollapse: onCollapse,
                  onClose: onClosePlayer,
                  onOpenFile: onOpenFile,
                  onSettingsTap: onSettingsTap,
                  onInfoTap: onInfoTap,
                ),
                BottomDock(
                  scale: scale,
                  player: player,
                  currentSpeed: currentSpeed,
                  volume: volume,
                  isFullscreen: isFullscreen,
                  drawerOwner: drawerOwner,
                  isEpisodesOpen: isEpisodesOpen,
                  chapters: chapters,
                  live: visible,
                  anime4kActive: anime4k.active,
                  anime4kKey: anime4kKey,
                  subsKey: subsKey,
                  audioKey: audioKey,
                  speedKey: speedKey,
                  volumeKey: volumeKey,
                  onToggleFullscreen: onToggleFullscreen,
                  onMiniPlayer: onMiniPlayer,
                  onVolumeChanged: onVolumeChanged,
                  onToggleMute: onToggleMute,
                  onAnime4kTap: onAnime4kTap,
                  onAnime4kSecondaryTap: onAnime4kSecondaryTap,
                  onSubsTap: onSubsTap,
                  onAudioTap: onAudioTap,
                  onSpeedTap: onSpeedTap,
                  onSpeedSecondaryTap: onSpeedSecondaryTap,
                  onEpisodesTap: onEpisodesTap,
                  onChaptersTap: onChaptersTap,
                  onPrevious: onPrevious,
                  onNext: onNext,
                ),
                Positioned.fill(
                  child: AppPresence(
                    expand: true,
                    visible: activeDrawer != null,
                    duration: AppAnim.normal,
                    slide: Offset(0, drawerIsTop ? -0.03 : 0.03),
                    child: activeDrawer == null
                        ? const SizedBox.shrink()
                        : LayoutBuilder(builder: (context, drawerCons) => SettingsDrawer(
                    scale: scale,
                    screenWidth: drawerCons.maxWidth,
                    drawerAnchorPixelX: drawerAnchorPixelX,
                    drawerIsTop: drawerIsTop,
                    activeDrawer: activeDrawer!,
                    activeDrawerPrev: activeDrawerPrev,
                    player: player,
                    currentSpeed: currentSpeed,
                    currentHwdec: currentHwdec,
                    subtitleTracks: subtitleTracks,
                    audioTracks: audioTracks,
                    chapters: chapters,
                    scrollController: drawerScrollController,
                    onClose: onCloseDrawer,
                    onBack: onBackDrawer,
                    onOpenSubDrawer: onOpenSubDrawer,
                    onSpeedSelected: onSpeedSelected,
                    onSubtitleSelected: onSubtitleSelected,
                    onAddSubtitleFile: onAddSubtitleFile,
                    onAudioSelected: onAudioSelected,
                    audioDelayKey: audioDelayKey,
                    onHwdecSelected: onHwdecSelected,
                    onOpenChaptersSidePanel: onChaptersTap,
                    onOpenStats: onOpenStats,
                    anime4k: anime4k,
                  )),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}