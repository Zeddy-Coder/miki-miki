import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import '../models/media_models.dart';
import '../services/playback_clock.dart';
import '../services/storage_service.dart';
import '../utils/formatters.dart';
import 'app_dock_widgets.dart';
import 'line_icons.dart';
import 'player_kit.dart';

/// The PC player's bottom panel: the progress bar over the whole width; under it pause, previous, next, the volume,
/// "8:12 / 24:00" and the chapter's name; on the right Anime4K, subtitles, sound, speed, "Серії", the mini player and
/// full screen. Line icons straight on the video; the open menu's button and an engaged feature are in the accent.
class BottomDock extends StatefulWidget {
  final double scale;
  final Player player;
  final double currentSpeed;
  /// Volume and "mute": we listen only to the volume slider, not the whole dock
  final ValueListenable<VolumeState> volume;
  final bool isFullscreen;
  final String? drawerOwner;
  final bool isEpisodesOpen;
  final List<VideoChapter> chapters;

  /// false: the panel is hidden: time labels, progress and chapter do not follow playback
  /// (the UI does not wake up idle), and on showing they update at once
  final bool live;

  /// Anime4K is working now (an indicator appears on the button)
  final bool anime4kActive;
  final GlobalKey anime4kKey;
  final GlobalKey subsKey;
  final GlobalKey audioKey;
  final GlobalKey speedKey;
  final GlobalKey volumeKey;
  final VoidCallback onToggleFullscreen;
  final VoidCallback onMiniPlayer;
  final ValueChanged<double> onVolumeChanged;
  final VoidCallback onToggleMute;
  final VoidCallback onAnime4kTap;
  final VoidCallback onAnime4kSecondaryTap;
  final VoidCallback onSubsTap;
  final VoidCallback onAudioTap;
  final VoidCallback onSpeedTap;
  final VoidCallback onSpeedSecondaryTap;
  final VoidCallback onEpisodesTap;
  final VoidCallback onChaptersTap;

  /// "Previous / next": by default the next queue file; for site episodes the controller sets it
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  const BottomDock({
    super.key,
    required this.scale,
    required this.player,
    required this.currentSpeed,
    required this.volume,
    required this.isFullscreen,
    required this.drawerOwner,
    required this.isEpisodesOpen,
    required this.chapters,
    this.live = true,
    required this.anime4kActive,
    required this.anime4kKey,
    required this.subsKey,
    required this.audioKey,
    required this.speedKey,
    required this.volumeKey,
    required this.onToggleFullscreen,
    required this.onMiniPlayer,
    required this.onVolumeChanged,
    required this.onToggleMute,
    required this.onAnime4kTap,
    required this.onAnime4kSecondaryTap,
    required this.onSubsTap,
    required this.onAudioTap,
    required this.onSpeedTap,
    required this.onSpeedSecondaryTap,
    required this.onEpisodesTap,
    required this.onChaptersTap,
    this.onPrevious,
    this.onNext,
  });

  @override
  State<BottomDock> createState() => _BottomDockState();
}

class _BottomDockState extends State<BottomDock> {
  late PlaybackClock _clock;

  /// Current chapter number: changes only at chapter boundaries, not on every position event
  late ClockValue<int> _chapterIdx;

  @override
  void initState() {
    super.initState();
    _bindClock();
  }

  void _bindClock() {
    _clock = PlaybackClock.of(widget.player);
    _chapterIdx = _clock.derive((pos, _) => ChapterMath.indexAt(widget.chapters, pos));
  }

  @override
  void didUpdateWidget(BottomDock old) {
    super.didUpdateWidget(old);
    if (old.player != widget.player) {
      _chapterIdx.dispose();
      _bindClock();
    } else {
      _chapterIdx.refresh();
    }
  }

  @override
  void dispose() {
    _chapterIdx.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.scale;
    final player = widget.player;

    // The button's active state = its menu is open (even if you entered a submenu via "Налаштування", then only the settings button is active)
    final bool isA4kOpen = widget.drawerOwner == 'anime4k';
    final bool isSubActive = widget.drawerOwner == 'subs';
    final bool isAudActive = widget.drawerOwner == 'audio';
    final bool isSpdActive = widget.drawerOwner == 'speed';
    final bool customSpeed = (widget.currentSpeed - 1.0).abs() > 0.01;
    final bool seekButtons = StorageService.getSeekButtons();
    final int seekStep = StorageService.getSeekStep();
    final bool hasSubsOn = player.state.track.subtitle.id != 'no' && player.state.track.subtitle.id.isNotEmpty && player.state.tracks.subtitle.any((t) => t.id != 'auto' && t.id != 'no');
    // "8:12 / 24:00": two times as long as the duration, a digit ≈ 7.3 px at 13 px
    final int durLen = AppFormatters.formatTime(player.state.duration).length.clamp(4, 8);
    final double timeW = (durLen * 2 * 7.3 + 16) * s;

    Widget icon(LineIcon icon, String label, VoidCallback? onTap, {Key? key, bool active = false, bool badge = false, VoidCallback? onSecondaryTap, Widget? glyph}) =>
        PlayerIconButton(
          key: key,
          icon: icon,
          glyph: glyph,
          label: label,
          active: active,
          badge: badge,
          onTap: onTap,
          onSecondaryTap: onSecondaryTap,
          size: 40 * s,
          iconSize: 21 * s,
        );

    void seekBy(int seconds) {
      final pos = player.state.position + Duration(seconds: seconds);
      player.seek(pos < Duration.zero ? Duration.zero : pos);
    }

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.fromLTRB(14 * s, 64 * s, 14 * s, 8 * s),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.transparent, Colors.black.withValues(alpha: 0.78)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 10 * s),
              child: AppSeekBar(scale: s, player: player, chapters: widget.chapters, live: widget.live),
            ),
            LayoutBuilder(builder: (context, cons) {
              final double w = cons.maxWidth;
              // Little room: "Серії" becomes an icon, the chapter name goes (the buttons are not squeezed)
              final bool compact = w < 900 * s;

              final Widget left = Row(
                children: [
                  StreamBuilder<bool>(
                    stream: player.stream.playing,
                    initialData: player.state.playing,
                    builder: (context, snapshot) {
                      final playing = snapshot.data ?? player.state.playing;
                      return PlayerIconButton(
                        key: const ValueKey('dock-play'),
                        icon: playing ? LineIcon.pause : LineIcon.play,
                        label: playing ? 'Пауза' : 'Відтворити',
                        onTap: () => player.playOrPause(),
                        size: 42 * s,
                        iconSize: 24 * s,
                      );
                    },
                  ),
                  icon(LineIcon.skipPrevious, 'Попередній', widget.onPrevious ?? () => player.previous()),
                  icon(LineIcon.skipNext, 'Наступний', widget.onNext ?? () => player.next()),
                  if (seekButtons) ...[
                    icon(LineIcon.replay, 'Назад на $seekStep с', () => seekBy(-seekStep), glyph: PlayerSeekGlyph(forward: false, seconds: seekStep, size: 22 * s)),
                    icon(LineIcon.forward, 'Вперед на $seekStep с', () => seekBy(seekStep), glyph: PlayerSeekGlyph(forward: true, seconds: seekStep, size: 22 * s)),
                  ],
                  ValueListenableBuilder<VolumeState>(
                    valueListenable: widget.volume,
                    builder: (context, vol, _) => AppVolumeControl(
                      key: widget.volumeKey,
                      scale: s,
                      volume: vol.volume,
                      isMuted: vol.muted,
                      onVolumeChanged: widget.onVolumeChanged,
                      onToggleMute: widget.onToggleMute,
                    ),
                  ),
                  SizedBox(width: 12 * s),
                  // A box as wide as "24:00 / 24:00" in tabular digits: the row does not jump while the time runs
                  SizedBox(
                    width: timeW,
                    child: AppClockBuilder<int>(
                      listenable: _clock.seconds,
                      live: widget.live,
                      builder: (context, sec) => AppClockBuilder<Duration>(
                        listenable: _clock.duration,
                        live: widget.live,
                        builder: (context, dur) => Text(
                          '${AppFormatters.formatTime(Duration(seconds: sec))} / ${AppFormatters.formatTime(dur)}',
                          key: const ValueKey('dock-time'),
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.fade,
                          style: playerText(13 * s, color: const Color(0xFFE8E8EC), features: const [FontFeature.tabularFigures()]),
                        ),
                      ),
                    ),
                  ),
                  if (!compact)
                    Flexible(
                      child: AppClockBuilder<int>(
                        listenable: _chapterIdx,
                        live: widget.live,
                        builder: (context, chIndex) {
                          final chTitle = (chIndex >= 0 && chIndex < widget.chapters.length)
                              ? AppFormatters.translateChapterTitle(widget.chapters[chIndex].title)
                              : '';
                          if (chTitle.isEmpty) return const SizedBox.shrink();
                          return MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: GestureDetector(
                              key: const ValueKey('dock-chapter'),
                              behavior: HitTestBehavior.opaque,
                              onTap: widget.onChaptersTap,
                              child: Padding(
                                padding: EdgeInsets.symmetric(horizontal: 8 * s, vertical: 8 * s),
                                child: Text(
                                  '· $chTitle',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: playerText(13 * s, color: const Color(0xFF9A9AA2)),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              );

              final Widget right = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  icon(LineIcon.sparkle, 'Anime4K', widget.onAnime4kTap,
                      key: widget.anime4kKey, active: isA4kOpen, badge: widget.anime4kActive, onSecondaryTap: widget.onAnime4kSecondaryTap),
                  icon(LineIcon.subtitles, 'Субтитри', widget.onSubsTap, key: widget.subsKey, active: isSubActive, badge: hasSubsOn),
                  icon(LineIcon.musicNote, 'Аудіодоріжка', widget.onAudioTap, key: widget.audioKey, active: isAudActive),
                  PlayerPill(
                    key: widget.speedKey,
                    text: AppFormatters.formatSpeed(widget.currentSpeed),
                    label: 'Швидкість відтворення',
                    plain: true,
                    active: isSpdActive || customSpeed,
                    height: 34 * s,
                    fontSize: 13.5 * s,
                    onTap: widget.onSpeedTap,
                    onSecondaryTap: widget.onSpeedSecondaryTap,
                  ),
                  SizedBox(width: 6 * s),
                  PlayerPill(
                    key: const ValueKey('dock-episodes'),
                    icon: LineIcon.list,
                    text: compact ? null : 'Серії',
                    label: 'Серії',
                    active: widget.isEpisodesOpen,
                    height: 34 * s,
                    fontSize: 13.5 * s,
                    onTap: widget.onEpisodesTap,
                  ),
                  SizedBox(width: 6 * s),
                  icon(LineIcon.pictureInPicture, 'Міні-плеєр', widget.onMiniPlayer),
                  icon(widget.isFullscreen ? LineIcon.fullscreenExit : LineIcon.fullscreen, widget.isFullscreen ? 'Вийти з повного екрана' : 'На весь екран', widget.onToggleFullscreen),
                ],
              );

              // The narrowest windows: the row shrinks as one piece instead of overflowing
              final double needed = (compact ? 600 : 650) * s + timeW + (seekButtons ? 80 * s : 0);
              Widget row = Row(
                children: [
                  Expanded(child: left),
                  SizedBox(width: 12 * s),
                  right,
                ],
              );
              if (w < needed) {
                row = FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: SizedBox(width: needed, child: row));
              }
              return SizedBox(height: 44 * s, child: row);
            }),
          ],
        ),
      ),
    );
  }
}
