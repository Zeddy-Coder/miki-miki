import 'dart:typed_data';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import '../models/media_models.dart';
import '../services/playback_clock.dart';
import '../services/seek_preview_service.dart';
import '../services/ui_theme_service.dart';
import '../utils/formatters.dart';
import 'app_animation_kit.dart';
import 'line_icons.dart';
import 'player_kit.dart';

/// Mouse wheel over a widget. Fires only for the deepest (closest to the cursor)
/// listener, so the wheel over a button does not also change the volume of the video under it.
class AppWheelRegion extends StatelessWidget {
  /// +1 means scrolling up, -1 down
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

/// Like `ValueListenableBuilder`, but with a [live] switch: while it is off (the control panel
/// is hidden), the widget does not rebuild on events, and when it is turned on it shows the current value at once.
/// Needed so time labels do not wake the UI when they are not visible.
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

  // The value is read at build time: a rebuild from the parent always shows the current one
  @override
  Widget build(BuildContext context) => widget.builder(context, widget.listenable.value);
}

/// A thin progress bar (collapsed and mini player): updates in per mille, not on every position event
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

// ─────────────────────────────────────────────────────────────────────────────
// Volume
// ─────────────────────────────────────────────────────────────────────────────

/// The volume: a line icon (a click mutes) and a thin slider always in view, white on the video like the concept;
/// under the cursor or while dragged the bar thickens and a round thumb appears. The slider keeps following a drag
/// that left its bounds, and the clickable area takes the full height.
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
    final icon = muted ? LineIcon.volumeOff : (widget.volume > 50 ? LineIcon.volume : LineIcon.volumeLow);

    final double pad = 6 * scale; // the slider zone's side padding (it responds too)
    final double trackW = 76 * scale;
    final double h = 40 * scale;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PlayerIconButton(
            key: const ValueKey('volume-mute'),
            icon: icon,
            label: muted ? 'Увімкнути звук' : 'Вимкнути звук',
            onTap: widget.onToggleMute,
            size: h,
            iconSize: 21 * scale,
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => _setFromDx(d.localPosition.dx - pad, trackW),
            onHorizontalDragStart: (d) {
              setState(() => _drag = true);
              _setFromDx(d.localPosition.dx - pad, trackW);
            },
            onHorizontalDragUpdate: (d) => _setFromDx(d.localPosition.dx - pad, trackW),
            onHorizontalDragEnd: (_) => setState(() => _drag = false),
            onHorizontalDragCancel: () => setState(() => _drag = false),
            child: SizedBox(
              key: const ValueKey('volume-slider'),
              width: trackW + pad * 2,
              height: h,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: pad),
                child: AppAnimatedValue(
                  value: expanded ? 1 : 0,
                  builder: (context, t) => CustomPaint(
                    painter: _VolumePainter(fraction: shown.clamp(0.0, 1.0), scale: scale, active: t),
                  ),
                ),
              ),
            ),
          ),
        ],
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
    final h = (3.0 + 1.0 * active) * scale;
    final cy = size.height / 2;
    final radius = Radius.circular(h / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, cy - h / 2, size.width, h), radius),
      Paint()..color = Colors.white.withValues(alpha: 0.25),
    );
    final fillW = size.width * fraction;
    if (fillW > 0) {
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, cy - h / 2, fillW, h), radius), Paint()..color = PlayerTones.fg);
    }
    if (active > 0.01) {
      final r = 5.5 * scale * active;
      canvas.drawCircle(Offset(fillW.clamp(r, size.width - r), cy), r, Paint()..color = PlayerTones.fg);
    }
  }

  @override
  bool shouldRepaint(_VolumePainter old) => old.fraction != fraction || old.active != active || old.scale != scale;
}

// ─────────────────────────────────────────────────────────────────────────────
// Progress slider
// ─────────────────────────────────────────────────────────────────────────────

/// Progress slider: a large hitbox, hover highlight up to the cursor, buffer, chapter segments,
/// snapping to chapters, dragging with smooth following and a seek frame preview.
class AppSeekBar extends StatefulWidget {
  final double scale;
  final Player player;
  final List<VideoChapter> chapters;

  /// false: the panel is hidden: the bar does not follow the position (no idle frames)
  final bool live;

  /// Height of the touch zone (30 × scale by default; 48 dp on a phone)
  final double? hitHeight;

  /// Scale of the frame-preview tooltip (equals scale by default)
  final double? bubbleScale;

  /// A finger/cursor started (true) or finished (false) dragging: so the panels do not hide mid-gesture
  final ValueChanged<bool>? onDragChanged;

  const AppSeekBar({
    super.key,
    required this.scale,
    required this.player,
    required this.chapters,
    this.live = true,
    this.hitHeight,
    this.bubbleScale,
    this.onDragChanged,
  });

  @override
  State<AppSeekBar> createState() => _AppSeekBarState();
}

class _AppSeekBarState extends State<AppSeekBar> {
  bool _hover = false;
  bool _drag = false;
  int? _pointer;
  double _hoverX = 0;
  double? _dragFraction;
  double _lastDx = 0;
  double _lastWidth = 1;
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
    _lastDx = dx;
    _lastWidth = width;
    setState(() {
      _dragFraction = f;
      _hoverX = dx.clamp(0.0, width);
    });
    // A stream (network): during dragging we do not flood the engine with seeks, they hang; the last one goes on release.
    // A local file seeks "live" (with frame previews).
    if (_drag && !force && !SeekPreviewService.supports(_currentUri())) return;
    final now = DateTime.now();
    if (force || now.difference(_lastSeek).inMilliseconds >= 40) {
      _lastSeek = now;
      widget.player.seek(_snap(_timeAt(dx, width)));
    }
  }

  /// The finger is released (or the gesture is cancelled): the final seek and a full reset of the drag state
  void _finishDrag({bool seek = true}) {
    if (seek && _drag && _total > Duration.zero) {
      _lastSeek = DateTime.now();
      widget.player.seek(_snap(_timeAt(_lastDx, _lastWidth)));
    }
    _pointer = null;
    widget.onDragChanged?.call(false);
    if (!mounted) return;
    setState(() {
      _drag = false;
      _dragFraction = null;
    });
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
        // We repaint the bar only when it moved by a physical pixel
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
                  // Raw pointer events instead of gestures: dragging cannot "hang" because of gesture competition
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (e) {
                      if (_pointer != null) return;
                      _pointer = e.pointer;
                      SeekPreviewService.prepare(_currentUri(), _total);
                      setState(() => _drag = true);
                      widget.onDragChanged?.call(true);
                      _seekTo(e.localPosition.dx, width, force: true);
                    },
                    onPointerMove: (e) {
                      if (e.pointer != _pointer) return;
                      _seekTo(e.localPosition.dx, width);
                      SeekPreviewService.request(_snap(_timeAt(e.localPosition.dx, width)));
                    },
                    onPointerUp: (e) {
                      if (e.pointer != _pointer) return;
                      _finishDrag();
                    },
                    onPointerCancel: (e) {
                      if (e.pointer != _pointer) return;
                      _finishDrag(seek: false);
                    },
                    child: AppAnimatedValue(
                      value: active ? 1 : 0,
                      // The painter itself draws the position and buffer (repaint: _progress), without rebuilding widgets.
                      // Its own layer: moving the thumb or cursor does not repaint the whole control panel.
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

  /// Under the cursor: the frame (a local file) with a thin light edge and, under it, "8:40 · Частина А" on a dark plate
  Widget _buildBubble(double scale, double width, double hitH) {
    final time = _snap(_timeAt(_hoverX, width));
    final chTitle = _chapterTitleAt(time);
    final uri = _currentUri();
    final bool preview = SeekPreviewService.supports(uri);
    final double bw = preview ? 176 * scale : (chTitle.isNotEmpty ? 220 : 84) * scale;
    final double left = (_hoverX - bw / 2).clamp(0.0, (width - bw).clamp(0.0, double.infinity));
    final label = chTitle.isEmpty ? AppFormatters.formatTime(time) : '${AppFormatters.formatTime(time)} · $chTitle';

    return Positioned(
      left: left,
      bottom: hitH - 2 * scale,
      child: IgnorePointer(
        child: SizedBox(
          key: const ValueKey('seek-preview'),
          width: bw,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (preview) ...[
                Container(
                  width: bw,
                  height: bw * 9 / 16,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(8 * scale),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 14 * scale, offset: Offset(0, 4 * scale))],
                  ),
                  child: ValueListenableBuilder<int>(
                    valueListenable: SeekPreviewService.revision,
                    builder: (context, _, __) {
                      final Uint8List? bytes = SeekPreviewService.frame(time);
                      return bytes == null
                          ? Center(child: LineIconView(LineIcon.play, size: 20 * scale, color: Colors.white24))
                          : Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true, filterQuality: FilterQuality.medium);
                    },
                  ),
                ),
                SizedBox(height: 6 * scale),
              ],
              Container(
                padding: EdgeInsets.symmetric(horizontal: 9 * scale, vertical: 4 * scale),
                decoration: BoxDecoration(color: const Color(0xDB18181C), borderRadius: BorderRadius.circular(7 * scale)),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Arial',
                    fontFamilyFallback: const ['MikiSans'],
                    color: const Color(0xFFF0F0F2),
                    fontSize: 12.5 * scale,
                    fontFeatures: const [FontFeature.tabularFigures()],
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

class _SeekPainter extends CustomPainter {
  final ClockProgress progress;
  final double? dragFraction; // while dragging, the position of the finger / cursor
  final double? hoverFraction;
  final List<double> chapters;
  final double scale;
  final double t; // 0..1: how "expanded" the bar is (hover / drag)

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

    // A solid accent thumb; under the finger or cursor a soft halo around it
    final thumbR = (5.5 + 1.5 * t) * scale;
    final cx = playedX.clamp(thumbR, w - thumbR);
    canvas.drawCircle(
      Offset(cx, cy),
      thumbR + (2.0 + 2.5 * t) * scale,
      Paint()..color = uiTheme.accentOnDark.withValues(alpha: 0.16 + 0.08 * t),
    );
    canvas.drawCircle(Offset(cx, cy), thumbR, Paint()..color = uiTheme.accentOnDark);
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
