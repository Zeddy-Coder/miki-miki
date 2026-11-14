import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:material_symbols_icons/symbols.dart';
import 'package:media_kit/media_kit.dart';

import '../services/osd_message.dart';
import '../services/system_controls.dart';
import '../services/touch_gestures.dart';
import '../services/video_zoom.dart';
import '../utils/formatters.dart';

/// Gestures on the video for a phone (a layer between the video and the buttons):
/// - vertically on the left half: screen brightness;
/// - vertically on the right half: system volume;
/// - with two fingers: image zoom (pinch) snapping to the screen edges;
/// - horizontally: seek (applied when the finger is released; the target time is visible during the gesture).
///
/// Taps, double tap and hold (2×) are handled by the video's lower layer; this layer reacts only to dragging,
/// so it does not conflict with them. The buttons lie above and catch touches themselves.
class MobileGestureLayer extends StatefulWidget {
  final Player player;

  /// An on-screen notification with the current value (player controller: `showOsd`)
  final OsdSink osd;
  final bool enabled;

  /// Pinch zoom of the video; null means off
  final VideoZoomController? zoom;

  final Future<double?> Function() readBrightness;
  final Future<void> Function(double value) writeBrightness;
  final Future<double?> Function() readVolume;
  final Future<void> Function(double value) writeVolume;

  const MobileGestureLayer({
    super.key,
    required this.player,
    required this.osd,
    this.enabled = true,
    this.zoom,
    this.readBrightness = SystemControls.getBrightness,
    this.writeBrightness = SystemControls.setBrightness,
    this.readVolume = SystemControls.getVolume,
    this.writeVolume = SystemControls.setVolume,
  });

  @override
  State<MobileGestureLayer> createState() => _MobileGestureLayerState();
}

enum _Kind { none, brightness, volume, seek }

class _MobileGestureLayerState extends State<MobileGestureLayer> with SingleTickerProviderStateMixin {
  static const Duration _hud = Duration(milliseconds: 900);

  Size _size = Size.zero;

  /// Android system gesture zones (back from the edges, "home" from the bottom): we do not start video gestures from them
  EdgeInsets _systemInsets = EdgeInsets.zero;

  bool _inSystemEdge(Offset p) => TouchGestureMath.inSystemEdge(
        p,
        _size,
        side: math.max(22.0, math.max(_systemInsets.left, _systemInsets.right)),
        top: math.max(30.0, _systemInsets.top),
        bottom: math.max(30.0, _systemInsets.bottom),
      );
  _Kind _kind = _Kind.none;

  /// Number of the current gesture: responses from earlier gestures are discarded
  int _id = 0;

  // brightness / volume
  double? _base; // value at the gesture start (null means still being read from the system)
  double _dy = 0;
  double? _pending;
  Future<void> Function(double)? _pendingWriter;
  Timer? _writeTimer;

  // seek
  Duration _startPos = Duration.zero;
  Duration _total = Duration.zero;
  Duration _target = Duration.zero;
  double _dx = 0;

  // pinch zoom
  final Map<int, Offset> _pointers = {};
  double _pinchStartDist = 1;
  double _pinchStartScale = 1;
  Offset _pinchStartFocal = Offset.zero;
  Offset _pinchStartOffset = Offset.zero;
  int _magnet = 0; // 0 is free, 1 is snapped to 1×, 2 to "fill the screen"
  late final AnimationController _settle = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));

  Size _fit() {
    final st = widget.player.state;
    final w = st.width, h = st.height;
    final aspect = (w != null && h != null && w > 0 && h > 0) ? w / h : (_size.height > 0 ? _size.width / _size.height : 1.0);
    return VideoZoomMath.fitSize(_size, aspect);
  }

  Offset _fromCenter(Offset p) => p - Offset(_size.width / 2, _size.height / 2);

  void _pointerDown(PointerDownEvent e) {
    final z = widget.zoom;
    if (z == null || !widget.enabled) return;
    _pointers[e.pointer] = e.localPosition;
    if (_pointers.length == 2) {
      _settle.stop();
      final pts = _pointers.values.toList();
      _pinchStartDist = math.max(1.0, (pts[0] - pts[1]).distance);
      _pinchStartScale = z.scale;
      _pinchStartOffset = z.offset;
      _pinchStartFocal = _fromCenter((pts[0] + pts[1]) / 2);
      _magnet = 0;
      z.pinching = true;
      // One-finger gestures (brightness / volume / seek) are cancelled for the duration of the pinch
      _reset();
    }
  }

  void _pointerMove(PointerMoveEvent e) {
    final z = widget.zoom;
    if (z == null || !_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.localPosition;
    if (_pointers.length < 2 || !z.pinching) return;
    final pts = _pointers.values.toList();
    final dist = (pts[0] - pts[1]).distance;
    // Zoom is always from the screen center; below 1× (normal size) is not possible
    var s = (_pinchStartScale * dist / _pinchStartDist).clamp(VideoZoomMath.minScale, VideoZoomMath.maxScale).toDouble();
    // Snapping to 1× and "fill the screen": a noticeable click and a label
    final cover = VideoZoomMath.coverScale(_size, _fit());
    final magnet = VideoZoomMath.magnetOf(s, cover: cover);
    if (magnet != 0) s = magnet == 1 ? 1.0 : cover;
    if (magnet != _magnet) {
      _magnet = magnet;
      if (magnet != 0) HapticFeedback.mediumImpact();
    }
    z.set(s, Offset.zero);
    widget.osd(
      OsdMessage(
        icon: s >= cover && cover > 1.05 && magnet == 2 ? Symbols.fit_screen_rounded : Symbols.zoom_in_rounded,
        title: '×${s.toStringAsFixed(s < 10 ? 2 : 1)}',
        detail: magnet == 2 ? 'На весь екран' : (magnet == 1 ? 'Звичайний розмір' : ''),
        progress: ((s - 1) / (VideoZoomMath.maxScale - 1)).clamp(0.0, 1.0),
      ),
      duration: _hud,
    );
  }

  void _pointerUp(PointerEvent e) {
    final z = widget.zoom;
    if (z == null || _pointers.remove(e.pointer) == null) return;
    if (!z.pinching || _pointers.length >= 2) return;
    // Pinch finished: the scale snaps to 1× or "fill the screen", the image to the edges
    final fit = _fit();
    final cover = VideoZoomMath.coverScale(_size, fit);
    final target = VideoZoomMath.snapScale(z.scale, cover: cover);
    const targetOffset = Offset.zero;
    final fromS = z.scale, fromO = z.offset;
    z.pinching = false;
    _settle
      ..removeListener(_noop)
      ..reset();
    final curve = CurvedAnimation(parent: _settle, curve: Curves.easeOutCubic);
    void tick() => z.set(fromS + (target - fromS) * curve.value, Offset.lerp(fromO, targetOffset, curve.value)!);
    _settle.addListener(tick);
    _settle.forward().whenComplete(() {
      _settle.removeListener(tick);
      z.set(target, targetOffset);
    });
  }

  void _noop() {}

  @override
  void dispose() {
    _writeTimer?.cancel();
    _settle.dispose();
    widget.zoom?.pinching = false;
    super.dispose();
  }

  void _reset() {
    _flush();
    _writeTimer?.cancel();
    _writeTimer = null;
    _kind = _Kind.none;
    _base = null;
    _dy = 0;
    _dx = 0;
    _id++;
  }

  // ── Vertical gestures ──────────────────────────────────────────────────────

  void _onVerticalStart(DragStartDetails d) {
    _id++;
    if (!widget.enabled || (widget.zoom?.pinching ?? false) || _inSystemEdge(d.localPosition)) {
      _kind = _Kind.none;
      return;
    }
    final brightness = TouchGestureMath.isBrightnessSide(d.localPosition.dx, _size.width);
    _kind = brightness ? _Kind.brightness : _Kind.volume;
    _base = null;
    _dy = 0;
    final id = _id;
    // We take the initial value from the system: it could have been changed by the volume buttons or the shade
    (brightness ? widget.readBrightness() : widget.readVolume()).then((v) {
      if (!mounted || id != _id) return;
      _base = (v ?? 0.5).clamp(0.0, 1.0);
      _applyLevel();
    });
  }

  void _onVerticalUpdate(DragUpdateDetails d) {
    if (_kind != _Kind.brightness && _kind != _Kind.volume) return;
    _dy += d.delta.dy;
    _applyLevel();
  }

  void _applyLevel() {
    final base = _base;
    if (base == null) return;
    final level = TouchGestureMath.levelAfterDrag(start: base, dy: _dy, height: _size.height);
    final bool brightness = _kind == _Kind.brightness;
    final IconData icon = brightness
        ? (level < 0.34 ? Symbols.brightness_low_rounded : (level < 0.67 ? Symbols.brightness_medium_rounded : Symbols.brightness_high_rounded))
        : (level <= 0.001 ? Symbols.volume_off_rounded : (level < 0.5 ? Symbols.volume_down_rounded : Symbols.volume_up_rounded));
    widget.osd(
      OsdMessage(
        icon: icon,
        title: brightness ? 'Яскравість' : 'Гучність',
        detail: '${(level * 100).round()}%',
        progress: level,
      ),
      duration: _hud,
    );
    _queue(level, brightness ? widget.writeBrightness : widget.writeVolume);
  }

  /// Writes to the system at most ~25 times per second (the last value always arrives)
  void _queue(double value, Future<void> Function(double) writer) {
    _pending = value;
    _pendingWriter = writer;
    if (_writeTimer != null) return;
    _flush();
    _writeTimer = Timer(const Duration(milliseconds: 40), () {
      _writeTimer = null;
      _flush();
    });
  }

  void _flush() {
    final v = _pending, w = _pendingWriter;
    _pending = null;
    if (v != null && w != null) w(v);
  }

  // ── Horizontal seek ────────────────────────────────────────────────────────

  void _onHorizontalStart(DragStartDetails d) {
    _id++;
    final total = widget.player.state.duration;
    if (!widget.enabled || (widget.zoom?.pinching ?? false) || total <= Duration.zero || _inSystemEdge(d.localPosition)) {
      _kind = _Kind.none;
      return;
    }
    _kind = _Kind.seek;
    _total = total;
    _startPos = widget.player.state.position;
    _target = _startPos;
    _dx = 0;
  }

  void _onHorizontalUpdate(DragUpdateDetails d) {
    if (_kind != _Kind.seek) return;
    _dx += d.delta.dx;
    _target = TouchGestureMath.seekTarget(start: _startPos, total: _total, dx: _dx, width: _size.width);
    final delta = _target - _startPos;
    widget.osd(
      OsdMessage(
        icon: delta.isNegative ? Symbols.fast_rewind_rounded : Symbols.fast_forward_rounded,
        title: TouchGestureMath.deltaLabel(delta),
        detail: '${AppFormatters.formatTime(_target)} / ${AppFormatters.formatTime(_total)}',
        progress: _total.inMilliseconds == 0 ? null : _target.inMilliseconds / _total.inMilliseconds,
      ),
      duration: _hud,
    );
  }

  void _onHorizontalEnd(DragEndDetails d) {
    if (_kind == _Kind.seek && _target != _startPos) widget.player.seek(_target);
    _reset();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        _size = c.biggest;
        _systemInsets = MediaQuery.systemGestureInsetsOf(context);
        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: _pointerDown,
          onPointerMove: _pointerMove,
          onPointerUp: _pointerUp,
          onPointerCancel: _pointerUp,
          child: GestureDetector(
          // translucent: both this layer (dragging) and the video under it (tap, double tap) see the touch
          behavior: HitTestBehavior.translucent,
          // The gesture start = where the finger touched (not the point after the ~18 px "threshold"): this way
          // the screen half (brightness / volume) and the system edges are determined correctly, and the motion feels immediate
          dragStartBehavior: DragStartBehavior.down,
          onVerticalDragStart: _onVerticalStart,
          onVerticalDragUpdate: _onVerticalUpdate,
          onVerticalDragEnd: (_) => _reset(),
          onVerticalDragCancel: _reset,
          onHorizontalDragStart: _onHorizontalStart,
          onHorizontalDragUpdate: _onHorizontalUpdate,
          onHorizontalDragEnd: _onHorizontalEnd,
          onHorizontalDragCancel: _reset,
          child: const SizedBox.expand(),
          ),
        );
      },
    );
  }
}
