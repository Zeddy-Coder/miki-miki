import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:media_kit/media_kit.dart';
import '../models/media_models.dart';
import '../services/app_log.dart';
import '../services/playback_clock.dart';
import '../services/storage_service.dart';
import '../services/ui_theme_service.dart';
import '../utils/formatters.dart';
import 'app_animation_kit.dart';
import 'app_dock_widgets.dart';

class SkipButton extends StatefulWidget {
  final double scale;
  final bool showControls;
  final Player player;
  final List<VideoChapter> chapters;
  final Duration? dismissedChapterStartTime;

  /// Телефон: кнопка вища (44 dp), стоїть над нижньою панеллю керування й не заходить за системні відступи
  final bool touch;

  const SkipButton({
    super.key,
    required this.scale,
    required this.showControls,
    required this.player,
    required this.chapters,
    required this.dismissedChapterStartTime,
    this.touch = false,
  });

  @override
  State<SkipButton> createState() => _SkipButtonState();
}

class _SkipButtonState extends State<SkipButton> {
  late List<VideoChapter> _chapters;
  late List<bool> _flags;

  /// Розділ, для якого зараз пропонуємо «Пропустити» (-1 — жодного). Рахується на кожну подію
  /// позиції, але віджет перебудовується лише коли результат змінюється (раз на розділ).
  late ClockValue<int> _skipIndex;

  /// Розділ, який уже пропустили автоматично (щоб не пропускати повторно, якщо перемотали назад)
  int _autoSkipped = -1;

  @override
  void initState() {
    super.initState();
    _chapters = widget.chapters;
    _flags = ChapterMath.skippableFlags(_chapters);
    _skipIndex = _derive();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutoSkip());
  }

  ClockValue<int> _derive() {
    final clock = PlaybackClock.of(widget.player);
    final v = clock.derive((pos, dur) => ChapterMath.skipIndexAt(_chapters, _flags, pos, dur));
    v.addListener(_maybeAutoSkip);
    return v;
  }

  /// Автопропуск (налаштування, типово вимкнено): на початку розділу-опенінгу чи ендінгу одразу перемотує до його кінця
  void _maybeAutoSkip() {
    final index = _skipIndex.value;
    if (index < 0) {
      _autoSkipped = -1;
      return;
    }
    if (!StorageService.getAutoSkipChapters() || index == _autoSkipped || index >= _chapters.length) return;
    if (widget.dismissedChapterStartTime == _chapters[index].startTime) return;
    final end = (index + 1 < _chapters.length) ? _chapters[index + 1].startTime : widget.player.state.duration;
    if (end <= _chapters[index].startTime) return;
    _autoSkipped = index;
    AppLog.i('дія', 'автопропуск «${_chapters[index].title}» → ${end.inSeconds} с');
    widget.player.seek(end);
  }

  @override
  void didUpdateWidget(SkipButton old) {
    super.didUpdateWidget(old);
    if (!identical(old.chapters, widget.chapters)) {
      _chapters = widget.chapters;
      _flags = ChapterMath.skippableFlags(_chapters);
      _autoSkipped = -1;
    }
    if (old.player != widget.player) {
      _skipIndex.dispose();
      _skipIndex = _derive();
    } else {
      _skipIndex.refresh();
      _maybeAutoSkip();
    }
  }

  @override
  void dispose() {
    _skipIndex.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.scale;
    final player = widget.player;
    final chapters = _chapters;
    final bool touch = widget.touch;
    final EdgeInsets safe = touch ? MediaQuery.paddingOf(context) : EdgeInsets.zero;
    return AppAnimatedPositioned(
      duration: AppAnim.medium,
      curve: AppAnim.easeOut,
      // Телефон: над повзунком і рядом кнопок (≈ 110 dp + системний відступ), а без панелі — біля нижнього краю
      bottom: touch ? (widget.showControls ? 132.0 : 28.0) + safe.bottom : (widget.showControls ? 95.0 : 35.0) * scale,
      right: touch ? 20.0 + safe.right : 35.0 * scale,
      // AppClockBuilder читає значення в момент побудови (зміна списку розділів одразу враховується)
      child: AppClockBuilder<int>(
        listenable: _skipIndex,
        builder: (context, index) {
          final bool show = StorageService.getShowSkipButton() &&
              index >= 0 &&
              index < chapters.length &&
              widget.dismissedChapterStartTime != chapters[index].startTime;
          if (!show) return const AppPresence(visible: false, child: SizedBox.shrink());
          final ch = chapters[index];
          final skippable = VideoChapter(
            title: AppFormatters.translateChapterTitle(ch.title),
            startTime: ch.startTime,
            endTime: (index + 1 < chapters.length) ? chapters[index + 1].startTime : player.state.duration,
          );


          return AppPresence(
            visible: true,
            slide: const Offset(0.12, 0),
            child: RepaintBoundary(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  if (skippable.endTime != null) player.seek(skippable.endTime!);
                },
                borderRadius: uiTheme.borderRadius(touch ? 24.0 : 20 * scale),
                splashColor: Colors.transparent,
                highlightColor: uiTheme.touchHighlight,
                hoverColor: uiTheme.isLight ? Colors.black.withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.15),
                child: Container(
                  height: touch ? 48.0 : 38 * scale,
                  padding: EdgeInsets.symmetric(horizontal: (touch ? 16 : 14) * scale),
                  decoration: BoxDecoration(
                    color: uiTheme.colors.drawerBg.withValues(alpha: uiTheme.isLight ? 0.95 : 0.92),
                    borderRadius: uiTheme.borderRadius(touch ? 24.0 : 20 * scale),
                    border: Border.all(color: uiTheme.colors.borderMedium, width: 1.0),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.40),
                        blurRadius: 10 * scale,
                        offset: Offset(0, 3 * scale),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Пропустити ${skippable.title.toLowerCase()}',
                        style: TextStyle(
                          fontFamily: 'Arial',
                          color: uiTheme.colors.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: touch ? 14.5 : 12.5 * scale,
                        ),
                      ),
                      SizedBox(width: 8 * scale),
                      Icon(Symbols.skip_next_rounded, color: uiTheme.accentColor, size: touch ? 24.0 : 20 * scale),
                    ],
                  ),
                ),
              ),
            ),
          ));
        },
      ),
    );
  }
}