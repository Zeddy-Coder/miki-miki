import 'dart:ui' show FontFeature;
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:media_kit/media_kit.dart';
import '../models/media_models.dart';
import '../services/playback_clock.dart';
import '../services/storage_service.dart';
import '../utils/formatters.dart';
import 'app_ui_kit.dart';
import 'app_animation_kit.dart';
import 'app_dock_widgets.dart';

class BottomDock extends StatefulWidget {
  final double scale;
  final Player player;
  final double currentSpeed;
  /// Гучність і «mute»: слухаємо лише повзунок гучності, а не весь док
  final ValueListenable<VolumeState> volume;
  final bool isFullscreen;
  final String? drawerOwner;
  final bool isEpisodesOpen;
  final List<VideoChapter> chapters;

  /// false — панель прихована: підписи часу, прогрес і розділ не стежать за відтворенням
  /// (інтерфейс не прокидається вхолосту), а при показі одразу оновлюються
  final bool live;

  /// Anime4K зараз працює (на кнопці з'являється індикатор)
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

  /// «Попередній / наступний»: типово — наступний файл черги; для серій із сайту задає контролер
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

  /// Номер поточного розділу: змінюється лише на межі розділів, а не на кожну подію позиції
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
    final scale = widget.scale;
    final player = widget.player;

    // Активний стан кнопки = відкрите її меню (навіть якщо ви зайшли в підменю через «Налаштування» — тоді активна лише кнопка налаштувань)
    final bool isA4kOpen = widget.drawerOwner == 'anime4k';
    final bool isSubActive = widget.drawerOwner == 'subs';
    final bool isAudActive = widget.drawerOwner == 'audio';
    final bool isSpdActive = widget.drawerOwner == 'speed';
    // Однакова ширина обох міток (за довжиною тривалості), щоб сікбар був відцентрований
    final String durText = AppFormatters.formatTime(player.state.duration);
    final double timeW = (durText.length.clamp(4, 8) * 7.6 + 22) * scale;
    final bool seekButtons = StorageService.getSeekButtons();
    final int seekStep = StorageService.getSeekStep();
    final bool hasSubsOn = player.state.track.subtitle.id != 'no' && player.state.track.subtitle.id.isNotEmpty && player.state.tracks.subtitle.any((t) => t.id != 'auto' && t.id != 'no');

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(left: 35 * scale, right: 35 * scale, bottom: 20 * scale, top: 40 * scale),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.transparent, Colors.black.withValues(alpha: 0.9)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                AppClockBuilder<int>(
                  listenable: _clock.seconds,
                  live: widget.live,
                  builder: (context, sec) => _timeText(scale, AppFormatters.formatTime(Duration(seconds: sec)), timeW),
                ),
                SizedBox(width: 12 * scale),
                Expanded(child: AppSeekBar(scale: scale, player: player, chapters: widget.chapters, live: widget.live)),
                SizedBox(width: 12 * scale),
                AppClockBuilder<Duration>(
                  listenable: _clock.duration,
                  live: widget.live,
                  builder: (context, dur) => _timeText(scale, AppFormatters.formatTime(dur), timeW),
                ),
              ],
            ),
            SizedBox(height: 8 * scale),
            LayoutBuilder(builder: (context, cons) {
              final double w = cons.maxWidth;
              final double centerW = (seekButtons ? 212 : 128) * scale;
              final double rightFull = 412 * scale;
              final bool symmetric = w >= 2 * rightFull + centerW + 48 * scale;
              // Місця мало — «Епізоди» стає іконкою (кнопки не стискаємо)
              final bool compactEp = !symmetric && (w - centerW - rightFull - 24 * scale) < 52 * scale;
              final double rightW = (compactEp ? 340 : 412) * scale;
              final double needed = 52 * scale + centerW + rightW + 24 * scale;

              final Widget left = Row(
                      children: [
                        ValueListenableBuilder<VolumeState>(
                          valueListenable: widget.volume,
                          builder: (context, vol, _) => AppVolumeControl(
                            key: widget.volumeKey,
                            scale: scale,
                            volume: vol.volume,
                            isMuted: vol.muted,
                            onVolumeChanged: widget.onVolumeChanged,
                            onToggleMute: widget.onToggleMute,
                          ),
                        ),
                        SizedBox(width: 12 * scale),
                        Flexible(
                          child: AppClockBuilder<int>(
                            listenable: _chapterIdx,
                            live: widget.live,
                            builder: (context, chIndex) {
                              final chTitle = (chIndex >= 0 && chIndex < widget.chapters.length)
                                  ? AppFormatters.translateChapterTitle(widget.chapters[chIndex].title)
                                  : '';
                              if (chTitle.isEmpty) return const SizedBox.shrink();
                              return Align(
                                alignment: Alignment.centerLeft,
                                child: IntrinsicWidth(child: AppOverlayButton(
                                  scale: scale,
                                  height: 30 * scale,
                                  borderRadius: 8 * scale,
                                  padding: EdgeInsets.only(left: 12 * scale, right: 6 * scale),
                                  onTap: widget.onChaptersTap,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Flexible(
                                        child: Text(
                                          chTitle,
                                          style: TextStyle(
                                            fontFamily: 'Arial',
                                            color: Colors.white,
                                            fontSize: 12.5 * scale,
                                            fontWeight: FontWeight.w400,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      SizedBox(width: 2 * scale),
                                      Icon(Symbols.chevron_right_rounded, color: Colors.white70, size: 16 * scale),
                                    ],
                                  ),
                                )),
                              );
                            },
                          ),
                        ),
                      ],
                    );
              final Widget center = Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _navButton(scale, Symbols.skip_previous_rounded, widget.onPrevious ?? () => player.previous()),
                      if (seekButtons) ...[
                        SizedBox(width: 8 * scale),
                        _navButton(scale, Symbols.fast_rewind_rounded, () => player.seek(player.state.position - Duration(seconds: seekStep))),
                      ],
                      SizedBox(width: 8 * scale),
                      StreamBuilder<bool>(
                        stream: player.stream.playing,
                        initialData: player.state.playing,
                        builder: (context, snapshot) {
                          final playing = snapshot.data ?? player.state.playing;
                          return AppOverlayButton(
                            scale: scale,
                            width: 44 * scale,
                            height: 30 * scale,
                            borderRadius: 8 * scale,
                            onTap: () => player.playOrPause(),
                            child: AppFadeSwitcher(
                              alignment: Alignment.center,
                              child: Icon(
                                playing ? Symbols.pause_rounded : Symbols.play_arrow_rounded,
                                key: ValueKey(playing),
                                color: Colors.white,
                                size: 22 * scale,
                                fill: 1,
                                weight: 300,
                                opticalSize: 24,
                              ),
                            ),
                          );
                        },
                      ),
                      SizedBox(width: 8 * scale),
                      if (seekButtons) ...[
                        _navButton(scale, Symbols.fast_forward_rounded, () => player.seek(player.state.position + Duration(seconds: seekStep))),
                        SizedBox(width: 8 * scale),
                      ],
                      _navButton(scale, Symbols.skip_next_rounded, widget.onNext ?? () => player.next()),
                    ],
                  );
              final Widget right = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppOverlayButton(
                    key: widget.anime4kKey,
                    scale: scale,
                    width: 38 * scale,
                    height: 30 * scale,
                    borderRadius: 8 * scale,
                    isActive: isA4kOpen,
                    showBadge: widget.anime4kActive,
                    onTap: widget.onAnime4kTap,
                    onSecondaryTap: widget.onAnime4kSecondaryTap,
                    child: Icon(
                      Symbols.auto_awesome_rounded,
                      color: AppOverlayButton.foreground(isA4kOpen),
                      size: 17 * scale,
                      weight: 300,
                      opticalSize: 24,
                    ),
                  ),
                  SizedBox(width: 8 * scale),
                  AppOverlayButton(
                    key: widget.subsKey,
                    scale: scale,
                    width: 38 * scale,
                    height: 30 * scale,
                    borderRadius: 8 * scale,
                    isActive: isSubActive,
                    showBadge: hasSubsOn,
                    onTap: widget.onSubsTap,
                    child: Icon(
                      Symbols.subtitles_rounded,
                      color: AppOverlayButton.foreground(isSubActive),
                      size: 17 * scale,
                      weight: 300,
                      opticalSize: 24,
                    ),
                  ),
                  SizedBox(width: 8 * scale),
                  AppOverlayButton(
                    key: widget.audioKey,
                    scale: scale,
                    width: 38 * scale,
                    height: 30 * scale,
                    borderRadius: 8 * scale,
                    isActive: isAudActive,
                    onTap: widget.onAudioTap,
                    child: Icon(
                      Symbols.music_note_rounded,
                      color: AppOverlayButton.foreground(isAudActive),
                      size: 17 * scale,
                      fill: 1,
                      weight: 300,
                      opticalSize: 24,
                    ),
                  ),
                  SizedBox(width: 8 * scale),
                  AppOverlayButton(
                      key: widget.speedKey,
                      scale: scale,
                      width: 64 * scale,
                      height: 30 * scale,
                      borderRadius: 8 * scale,
                      isActive: isSpdActive,
                      onTap: widget.onSpeedTap,
                      onSecondaryTap: widget.onSpeedSecondaryTap,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            AppFormatters.getSpeedIcon(widget.currentSpeed),
                            size: 16 * scale,
                            color: AppOverlayButton.foreground(isSpdActive),
                            weight: 300,
                            opticalSize: 24,
                          ),
                          SizedBox(width: 5 * scale),
                          Text(
                            AppFormatters.formatSpeed(widget.currentSpeed),
                            style: TextStyle(
                              fontFamily: 'Arial',
                              color: AppOverlayButton.foreground(isSpdActive),
                              fontWeight: FontWeight.w500,
                              fontSize: 11.5 * scale,
                            ),
                          ),
                        ],
                      ),
                  ),
                  SizedBox(width: 8 * scale),
                  AppOverlayButton(
                    scale: scale,
                    width: (compactEp ? 38 : 110) * scale,
                    height: 32 * scale,
                    borderRadius: 16 * scale,
                    isActive: widget.isEpisodesOpen,
                    onTap: widget.onEpisodesTap,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (!compactEp) ...[
                        Text(
                          'Епізоди',
                          style: TextStyle(
                            fontFamily: 'Arial',
                            color: AppOverlayButton.foreground(widget.isEpisodesOpen),
                            fontWeight: FontWeight.w500,
                            fontSize: 11.5 * scale,
                          ),
                        ),
                        SizedBox(width: 8 * scale),
                        ],
                        Icon(Symbols.video_library_rounded, color: AppOverlayButton.foreground(widget.isEpisodesOpen), size: 16 * scale, weight: 300, opticalSize: 24),
                      ],
                    ),
                  ),
                  SizedBox(width: 8 * scale),
                  AppOverlayButton(
                    scale: scale,
                    width: 38 * scale,
                    height: 30 * scale,
                    borderRadius: 8 * scale,
                    onTap: widget.onMiniPlayer,
                    child: Icon(
                      Symbols.picture_in_picture_alt_rounded,
                      color: Colors.white,
                      size: 18 * scale,
                      weight: 300,
                      opticalSize: 24,
                    ),
                  ),
                  SizedBox(width: 8 * scale),
                  AppOverlayButton(
                    scale: scale,
                    width: 38 * scale,
                    height: 30 * scale,
                    borderRadius: 8 * scale,
                    onTap: widget.onToggleFullscreen,
                    child: Icon(
                      widget.isFullscreen ? Symbols.fullscreen_exit_rounded : Symbols.fullscreen_rounded,
                      color: Colors.white,
                      size: 18 * scale,
                      weight: 300,
                      opticalSize: 24,
                    ),
                  ),
                ],
              );

              Widget row = Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: symmetric
                    ? [
                        Expanded(child: left),
                        center,
                        Expanded(child: Align(alignment: Alignment.centerRight, child: right)),
                      ]
                    : [
                        Expanded(child: left),
                        SizedBox(width: 8 * scale),
                        center,
                        SizedBox(width: 16 * scale),
                        right,
                      ],
              );
              // Крайній випадок: зовсім вузьке вікно — стискаємо весь ряд як одне ціле
              if (w < needed) {
                row = FittedBox(fit: BoxFit.scaleDown, child: SizedBox(width: needed, child: row));
              }
              return SizedBox(height: 32 * scale, child: row);
            }),
          ],
        ),
      ),
    );
  }

  Widget _navButton(double scale, IconData icon, VoidCallback onTap) {
    return AppOverlayButton(
      scale: scale,
      width: 34 * scale,
      height: 30 * scale,
      borderRadius: 8 * scale,
      onTap: onTap,
      child: Icon(icon, color: Colors.white, size: 18 * scale, weight: 300, opticalSize: 24),
    );
  }

  Widget _timeText(double scale, String text, double width) {
    return AppOverlayButton(
      scale: scale,
      width: width,
      height: 26 * scale,
      borderRadius: 8 * scale,
      child: Text(
        text,
        maxLines: 1,
        style: TextStyle(
          fontFamily: 'Arial',
          color: Colors.white,
          fontSize: 12.5 * scale,
          fontWeight: FontWeight.w400,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
