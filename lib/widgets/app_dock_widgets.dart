import 'dart:typed_data';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:media_kit/media_kit.dart';
import '../models/media_models.dart';
import '../services/playback_clock.dart';
import '../services/seek_preview_service.dart';
import '../services/ui_theme_service.dart';
import '../utils/formatters.dart';
import 'app_animation_kit.dart';

/// Колесо миші над віджетом. Спрацьовує лише для найглибшого (найближчого до курсора)
/// слухача, тому колесо над кнопкою не змінює ще й гучність відео під нею.
class AppWheelRegion extends StatelessWidget {
  /// +1 — крутять вгору, -1 — вниз
  final ValueChanged<int> onWheel;
  final Widget child;

  const AppWheelRegion({super.key, required this.onWheel, required this.child});

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) {
          GestureBinding.instance.pointerSignalResolver.register(event, (e) {
            onWheel((e as PointerScrollEvent).scrollDelta.dy < 0 ? 1 : -1);
          });
        }
      },
      child: child,
    );
  }
}

/// Як `ValueListenableBuilder`, але з вимикачем [live]: поки він вимкнений (панель керування
/// прихована), віджет не перебудовується від подій, а при вмиканні одразу показує актуальне.
/// Потрібен, щоб підписи часу не будили інтерфейс, коли їх не видно.
class AppClockBuilder<T> extends StatefulWidget {
  final ValueListenable<T> listenable;
  final bool live;
  final Widget Function(BuildContext context, T value) builder;

  const AppClockBuilder({super.key, required this.listenable, required this.builder, this.live = true});

  @override
  State<AppClockBuilder<T>> createState() => _AppClockBuilderState<T>();
}

class _AppClockBuilderState<T> extends State<AppClockBuilder<T>> {
  @override
  void initState() {
    super.initState();
    widget.listenable.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(AppClockBuilder<T> old) {
    super.didUpdateWidget(old);
    if (old.listenable != widget.listenable) {
      old.listenable.removeListener(_onChanged);
      widget.listenable.addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    widget.listenable.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (widget.live && mounted) setState(() {});
  }

  // Значення читаємо в момент побудови: перебудова з боку батька завжди показує актуальне
  @override
  Widget build(BuildContext context) => widget.builder(context, widget.listenable.value);
}

/// Тонка смужка прогресу (згорнутий та міні-плеєр): оновлюється в проміле, а не на кожну подію позиції
class AppProgressLine extends StatelessWidget {
  final Player player;
  final double height;
  final Color trackColor;
  final Color fillColor;

  const AppProgressLine({
    super.key,
    required this.player,
    required this.height,
    required this.trackColor,
    required this.fillColor,
  });

  @override
  Widget build(BuildContext context) {
    final clock = PlaybackClock.of(player);
    return LayoutBuilder(
      builder: (context, c) => ValueListenableBuilder<int>(
        valueListenable: clock.permille,
        builder: (context, permille, _) => Stack(
          children: [
            Container(height: height, width: double.infinity, color: trackColor),
            Container(height: height, width: c.maxWidth * permille / 1000, color: fillColor),
          ],
        ),
      ),
    );
  }
}

/// Скляна поверхня оверлею (така сама, як у AppOverlayButton)
BoxDecoration _glass({double radius = 8, bool hover = false}) {
  var bg = const Color(0xFF16161A).withValues(alpha: 0.55);
  if (hover) bg = Color.alphaBlend(Colors.white.withValues(alpha: 0.08), bg);
  return BoxDecoration(
    color: bg,
    borderRadius: uiTheme.borderRadius(radius),
    border: Border.all(color: Colors.white.withValues(alpha: 0.16), width: 1.0),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Гучність
// ─────────────────────────────────────────────────────────────────────────────

/// Кнопка гучності з повзунком, що висувається. Повзунок завжди змонтований (не зникає
/// й не «губить» ховер), лишається розкритим під час перетягування навіть коли курсор
/// вийшов за межі, а клікабельна зона займає всю висоту.
class AppVolumeControl extends StatefulWidget {
  final double scale;
  final double volume; // 0..100
  final bool isMuted;
  final ValueChanged<double> onVolumeChanged;
  final VoidCallback onToggleMute;

  const AppVolumeControl({
    super.key,
    required this.scale,
    required this.volume,
    required this.isMuted,
    required this.onVolumeChanged,
    required this.onToggleMute,
  });

  @override
  State<AppVolumeControl> createState() => _AppVolumeControlState();
}

class _AppVolumeControlState extends State<AppVolumeControl> {
  bool _hover = false;
  bool _drag = false;

  void _setFromDx(double dx, double width) {
    widget.onVolumeChanged(((dx / width) * 100).clamp(0.0, 100.0));
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.scale;
    final expanded = _hover || _drag;
    final muted = widget.isMuted || widget.volume == 0;
    final shown = widget.isMuted ? 0.0 : widget.volume / 100;
    final iconData = muted
        ? Symbols.volume_off_rounded
        : (widget.volume > 50 ? Symbols.volume_up_rounded : Symbols.volume_down_rounded);

    final double btnW = 38 * scale;
    final double sliderW = 92 * scale; // зона повзунка (разом з відступами)
    final double trackW = 70 * scale;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AppAnimatedContainer(
          duration: AppAnim.normal,
          width: btnW + (expanded ? sliderW : 0),
          height: 30 * scale,
          clipBehavior: Clip.hardEdge,
          decoration: _glass(radius: 8, hover: expanded),
          child: OverflowBox(
            alignment: Alignment.centerLeft,
            minWidth: 0,
            maxWidth: btnW + sliderW,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onToggleMute,
                  child: SizedBox(
                    width: btnW - 2,
                    height: 30 * scale,
                    child: Center(
                      child: AppFadeSwitcher(
                        alignment: Alignment.center,
                        child: Icon(
                          iconData,
                          key: ValueKey(iconData),
                          color: Colors.white,
                          size: 18 * scale,
                          weight: 300,
                          opticalSize: 24,
                        ),
                      ),
                    ),
                  ),
                ),
                // Зона повзунка: вся висота, відступи по боках теж реагують
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (d) => _setFromDx(d.localPosition.dx - 6 * scale, trackW),
                  onHorizontalDragStart: (d) {
                    setState(() => _drag = true);
                    _setFromDx(d.localPosition.dx - 6 * scale, trackW);
                  },
                  onHorizontalDragUpdate: (d) => _setFromDx(d.localPosition.dx - 6 * scale, trackW),
                  onHorizontalDragEnd: (_) => setState(() => _drag = false),
                  onHorizontalDragCancel: () => setState(() => _drag = false),
                  child: SizedBox(
                    width: sliderW,
                    height: 30 * scale,
                    child: Padding(
                      padding: EdgeInsets.only(left: 6 * scale),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: SizedBox(
                          width: trackW,
                          height: 18 * scale,
                          child: AppAnimatedValue(
                            value: _drag ? 1 : 0,
                            builder: (context, t) => CustomPaint(
                              painter: _VolumePainter(
                                fraction: shown.clamp(0.0, 1.0),
                                scale: scale,
                                active: t,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
    );
  }
}

class _VolumePainter extends CustomPainter {
  final double fraction;
  final double scale;
  final double active;

  _VolumePainter({required this.fraction, required this.scale, required this.active});

  @override
  void paint(Canvas canvas, Size size) {
    final h = (3.5 + 1.5 * active) * scale;
    final cy = size.height / 2;
    final track = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, cy - h / 2, size.width, h),
      Radius.circular(uiTheme.radius(h / 2)),
    );
    canvas.drawRRect(track, Paint()..color = Colors.white.withValues(alpha: 0.22));

    final fillW = size.width * fraction;
    if (fillW > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(0, cy - h / 2, fillW, h), Radius.circular(uiTheme.radius(h / 2))),
        Paint()..color = uiTheme.accentOnDark,
      );
    }
    final r = (5.0 + 1.5 * active) * scale;
    canvas.drawCircle(Offset(fillW.clamp(r, size.width - r), cy), r, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_VolumePainter old) => old.fraction != fraction || old.active != active || old.scale != scale;
}

// ─────────────────────────────────────────────────────────────────────────────
// Повзунок прогресу
// ─────────────────────────────────────────────────────────────────────────────

/// Повзунок прогресу: великий хітбокс, ховер-підсвітка до курсора, буфер, сегменти глав,
/// прив'язка до глав, перетягування з плавним слідуванням і прев'ю кадру перемотки.
class AppSeekBar extends StatefulWidget {
  final double scale;
  final Player player;
  final List<VideoChapter> chapters;

  /// false — панель прихована: смужка не стежить за позицією (жодних кадрів вхолосту)
  final bool live;

  /// Висота зони дотику (за замовчуванням 30 × scale; на телефоні — 48 dp)
  final double? hitHeight;

  /// Масштаб підказки з прев'ю кадру (за замовчуванням дорівнює scale)
  final double? bubbleScale;

  const AppSeekBar({
    super.key,
    required this.scale,
    required this.player,
    required this.chapters,
    this.live = true,
    this.hitHeight,
    this.bubbleScale,
  });

  @override
  State<AppSeekBar> createState() => _AppSeekBarState();
}

class _AppSeekBarState extends State<AppSeekBar> {
  bool _hover = false;
  bool _drag = false;
  double _hoverX = 0;
  double? _dragFraction;
  DateTime _lastSeek = DateTime.fromMillisecondsSinceEpoch(0);
  late ClockProgress _progress;

  Duration get _total => widget.player.state.duration;

  @override
  void initState() {
    super.initState();
    _progress = ClockProgress(PlaybackClock.of(widget.player), live: widget.live);
  }

  @override
  void didUpdateWidget(AppSeekBar old) {
    super.didUpdateWidget(old);
    if (old.player != widget.player) {
      _progress.dispose();
      _progress = ClockProgress(PlaybackClock.of(widget.player), live: widget.live);
    } else {
      _progress.live = widget.live;
    }
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  String? _currentUri() {
    final pl = widget.player.state.playlist;
    if (pl.index < 0 || pl.index >= pl.medias.length) return null;
    return pl.medias[pl.index].uri;
  }

  List<double> _chapterFractions() {
    final total = _total.inMilliseconds;
    if (widget.chapters.isEmpty || total <= 0) return const [];
    return widget.chapters.map((c) => (c.startTime.inMilliseconds / total).clamp(0.0, 1.0)).toList();
  }

  String _chapterTitleAt(Duration pos) {
    for (int i = widget.chapters.length - 1; i >= 0; i--) {
      if (pos >= widget.chapters[i].startTime) return AppFormatters.translateChapterTitle(widget.chapters[i].title);
    }
    return '';
  }

  Duration _snap(Duration target) {
    final totalMs = _total.inMilliseconds;
    if (widget.chapters.isEmpty || totalMs <= 0) return target;
    final threshold = ((totalMs * 0.025).clamp(5000.0, 12000.0)).toInt();
    for (final ch in widget.chapters) {
      final diff = target.inMilliseconds - ch.startTime.inMilliseconds;
      if (diff >= -2500 && diff <= threshold) return ch.startTime;
    }
    return target;
  }

  Duration _timeAt(double dx, double width) {
    final f = (dx / width).clamp(0.0, 1.0);
    return Duration(milliseconds: (_total.inMilliseconds * f).round());
  }

  void _seekTo(double dx, double width, {bool force = false}) {
    if (_total <= Duration.zero) return;
    final f = (dx / width).clamp(0.0, 1.0);
    setState(() {
      _dragFraction = f;
      _hoverX = dx.clamp(0.0, width);
    });
    final now = DateTime.now();
    if (force || now.difference(_lastSeek).inMilliseconds >= 40) {
      _lastSeek = now;
      widget.player.seek(_snap(_timeAt(dx, width)));
    }
  }

  void _onHover(double dx, double width) {
    setState(() => _hoverX = dx.clamp(0.0, width));
    if (_total > Duration.zero) SeekPreviewService.request(_snap(_timeAt(dx, width)));
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.scale;
    final double hitH = widget.hitHeight ?? 30 * scale;
    final bool active = _hover || _drag;

    final dpr = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (context, c) {
        final width = c.maxWidth;
        // Перемальовуємо смужку лише коли вона зсунулась на фізичний піксель
        _progress.steps = width * dpr;
        return SizedBox(
          height: hitH,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              if (active && _total > Duration.zero)
                _buildBubble(widget.bubbleScale ?? scale, width, hitH),
              Positioned.fill(
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  onEnter: (e) {
                    SeekPreviewService.prepare(_currentUri(), _total);
                    setState(() => _hover = true);
                    _onHover(e.localPosition.dx, width);
                  },
                  onExit: (_) => setState(() => _hover = false),
                  onHover: (e) => _onHover(e.localPosition.dx, width),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (d) => _seekTo(d.localPosition.dx, width, force: true),
                    onTapUp: (_) => setState(() => _dragFraction = null),
                    onHorizontalDragStart: (d) {
                      SeekPreviewService.prepare(_currentUri(), _total);
                      setState(() => _drag = true);
                      _seekTo(d.localPosition.dx, width, force: true);
                    },
                    onHorizontalDragUpdate: (d) {
                      _seekTo(d.localPosition.dx, width);
                      SeekPreviewService.request(_snap(_timeAt(d.localPosition.dx, width)));
                    },
                    onHorizontalDragEnd: (d) {
                      setState(() {
                        _drag = false;
                        _dragFraction = null;
                      });
                    },
                    onHorizontalDragCancel: () => setState(() {
                      _drag = false;
                      _dragFraction = null;
                    }),
                    child: AppAnimatedValue(
                      value: active ? 1 : 0,
                      // Позицію й буфер малює сам painter (repaint: _progress) — без перебудови віджетів.
                      // Власний шар: рух бігунка чи курсора не перемальовує всю панель керування.
                      builder: (context, t) => RepaintBoundary(
                        child: CustomPaint(
                          size: Size(width, hitH),
                          painter: _SeekPainter(
                            progress: _progress,
                            dragFraction: _dragFraction,
                            hoverFraction: _hover && !_drag ? (_hoverX / width).clamp(0.0, 1.0) : null,
                            chapters: _chapterFractions(),
                            scale: scale,
                            t: t,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBubble(double scale, double width, double hitH) {
    final time = _snap(_timeAt(_hoverX, width));
    final chTitle = _chapterTitleAt(time);
    final uri = _currentUri();
    final bool preview = SeekPreviewService.supports(uri);
    final double bw = preview ? 176 * scale : (chTitle.isNotEmpty ? 200 : 84) * scale;
    final double left = (_hoverX - bw / 2).clamp(0.0, (width - bw).clamp(0.0, double.infinity));

    return Positioned(
      left: left,
      bottom: hitH - 2 * scale,
      child: IgnorePointer(
          child: Container(
            width: bw,
            padding: EdgeInsets.all(preview ? 4 * scale : 0),
            decoration: BoxDecoration(
              color: uiTheme.colors.drawerBg,
              borderRadius: uiTheme.borderRadius(12 * scale),
              border: Border.all(color: uiTheme.colors.borderSubtle, width: 1.0),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.6), blurRadius: 12 * scale, offset: Offset(0, 3 * scale)),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (preview)
                  ClipRRect(
                    borderRadius: uiTheme.borderRadius(9 * scale),
                    child: SizedBox(
                      width: double.infinity,
                      height: (bw - 8 * scale) * 9 / 16,
                      child: ValueListenableBuilder<int>(
                        valueListenable: SeekPreviewService.revision,
                        builder: (context, _, __) {
                          final Uint8List? bytes = SeekPreviewService.frame(time);
                          return Stack(
                            fit: StackFit.expand,
                            children: [
                              Container(
                                color: Colors.black,
                                child: Center(
                                  child: Icon(Symbols.movie_rounded, color: Colors.white24, size: 22 * scale),
                                ),
                              ),
                              if (bytes != null)
                                Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true, filterQuality: FilterQuality.medium),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 5 * scale),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        AppFormatters.formatTime(time),
                        style: TextStyle(
                          fontFamily: 'Arial',
                          color: uiTheme.colors.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 11.5 * scale,
                        ),
                      ),
                      if (chTitle.isNotEmpty) ...[
                        Text(' • ', style: TextStyle(fontFamily: 'Arial', color: uiTheme.accentColor, fontWeight: FontWeight.bold, fontSize: 12 * scale)),
                        Flexible(
                          child: Text(
                            chTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Arial',
                              color: uiTheme.colors.textSecondary,
                              fontWeight: FontWeight.w500,
                              fontSize: 11.5 * scale,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
      ),
    );
  }
}

class _SeekPainter extends CustomPainter {
  final ClockProgress progress;
  final double? dragFraction; // під час перетягування — положення пальця/курсора
  final double? hoverFraction;
  final List<double> chapters;
  final double scale;
  final double t; // 0..1 — наскільки «розкрита» смужка (ховер/перетягування)

  _SeekPainter({
    required this.progress,
    required this.dragFraction,
    required this.hoverFraction,
    required this.chapters,
    required this.scale,
    required this.t,
  }) : super(repaint: progress);

  @override
  void paint(Canvas canvas, Size size) {
    final played = dragFraction ?? progress.played;
    final buffered = progress.buffered;
    final trackH = (3.0 + 1.5 * t) * scale;
    final cy = size.height / 2;
    final w = size.width;

    final points = <double>[0.0];
    for (final p in chapters) {
      if (p > 0.005 && p < 0.995 && !points.contains(p)) points.add(p);
    }
    points.sort();
    points.add(1.0);

    final gap = 2.5 * scale;
    final r = Radius.circular(uiTheme.radius(trackH / 2));
    final base = Paint()..color = Colors.white.withValues(alpha: 0.24);
    final buf = Paint()..color = Colors.white.withValues(alpha: 0.36);
    final hov = Paint()..color = Colors.white.withValues(alpha: 0.30);
    final act = Paint()..color = uiTheme.accentOnDark;

    void band(double from, double to, double segStart, double segEnd, Paint paint) {
      final a = from.clamp(segStart, segEnd);
      final b = to.clamp(segStart, segEnd);
      if (b <= a) return;
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB(a, cy - trackH / 2, b, cy + trackH / 2), r), paint);
    }

    final playedX = w * played;
    final bufX = w * buffered;
    final hoverX = hoverFraction != null ? w * hoverFraction! : null;

    for (int i = 0; i < points.length - 1; i++) {
      double s = points[i] * w;
      double e = points[i + 1] * w;
      if (i > 0) s += gap / 2;
      if (i < points.length - 2) e -= gap / 2;
      if (e <= s) continue;

      band(s, e, s, e, base);
      band(s, bufX, s, e, buf);
      if (hoverX != null && hoverX > playedX) band(playedX, hoverX, s, e, hov);
      band(s, playedX, s, e, act);
    }

    // Бігунок у стилі повзунків кіта: акцентове кільце з темною крапкою всередині
    final thumbR = (6.0 + 1.5 * t) * scale;
    final cx = playedX.clamp(thumbR, w - thumbR);
    if (t > 0.01) {
      canvas.drawCircle(
        Offset(cx, cy),
        thumbR + 3.5 * scale * t,
        Paint()..color = uiTheme.accentOnDark.withValues(alpha: 0.22 * t),
      );
    }
    canvas.drawCircle(Offset(cx, cy), thumbR, Paint()..color = uiTheme.accentOnDark);
    canvas.drawCircle(Offset(cx, cy), thumbR * 0.43, Paint()..color = const Color(0xFF111111));
  }

  @override
  bool shouldRepaint(_SeekPainter o) =>
      o.progress != progress ||
      o.dragFraction != dragFraction ||
      o.hoverFraction != hoverFraction ||
      o.t != t ||
      o.scale != scale ||
      !_listEq(o.chapters, chapters);

  static bool _listEq(List<double> a, List<double> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
