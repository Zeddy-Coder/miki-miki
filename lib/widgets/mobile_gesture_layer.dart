import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:media_kit/media_kit.dart';

import '../services/osd_message.dart';
import '../services/system_controls.dart';
import '../services/touch_gestures.dart';
import '../utils/formatters.dart';

/// Жести на відео для телефона (шар між відео та кнопками):
/// - вертикально по лівій половині — яскравість екрана;
/// - вертикально по правій половині — системна гучність;
/// - горизонтально — перемотка (застосовується, коли палець відпущено; під час жесту видно цільовий час).
///
/// Тапи, подвійний тап і утримання (2×) обробляє нижній шар відео; цей шар реагує лише на перетягування,
/// тому з ними не конфліктує. Кнопки лежать вище й перехоплюють дотики до себе.
class MobileGestureLayer extends StatefulWidget {
  final Player player;

  /// Екранне сповіщення з поточним значенням (контролер плеєра: `showOsd`)
  final OsdSink osd;
  final bool enabled;

  final Future<double?> Function() readBrightness;
  final Future<void> Function(double value) writeBrightness;
  final Future<double?> Function() readVolume;
  final Future<void> Function(double value) writeVolume;

  const MobileGestureLayer({
    super.key,
    required this.player,
    required this.osd,
    this.enabled = true,
    this.readBrightness = SystemControls.getBrightness,
    this.writeBrightness = SystemControls.setBrightness,
    this.readVolume = SystemControls.getVolume,
    this.writeVolume = SystemControls.setVolume,
  });

  @override
  State<MobileGestureLayer> createState() => _MobileGestureLayerState();
}

enum _Kind { none, brightness, volume, seek }

class _MobileGestureLayerState extends State<MobileGestureLayer> {
  static const Duration _hud = Duration(milliseconds: 900);

  Size _size = Size.zero;

  /// Зони системних жестів Android (назад — з країв, «додому» — знизу): з них жести на відео не починаємо
  EdgeInsets _systemInsets = EdgeInsets.zero;

  bool _inSystemEdge(Offset p) => TouchGestureMath.inSystemEdge(
        p,
        _size,
        side: math.max(22.0, math.max(_systemInsets.left, _systemInsets.right)),
        top: math.max(30.0, _systemInsets.top),
        bottom: math.max(30.0, _systemInsets.bottom),
      );
  _Kind _kind = _Kind.none;

  /// Номер поточного жесту: відповіді від попередніх жестів відкидаються
  int _id = 0;

  // яскравість / гучність
  double? _base; // значення на початку жесту (null — ще читається з системи)
  double _dy = 0;
  double? _pending;
  Future<void> Function(double)? _pendingWriter;
  Timer? _writeTimer;

  // перемотка
  Duration _startPos = Duration.zero;
  Duration _total = Duration.zero;
  Duration _target = Duration.zero;
  double _dx = 0;

  @override
  void dispose() {
    _writeTimer?.cancel();
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

  // ── Вертикальні жести ──────────────────────────────────────────────────────

  void _onVerticalStart(DragStartDetails d) {
    _id++;
    if (!widget.enabled || _inSystemEdge(d.localPosition)) {
      _kind = _Kind.none;
      return;
    }
    final brightness = TouchGestureMath.isBrightnessSide(d.localPosition.dx, _size.width);
    _kind = brightness ? _Kind.brightness : _Kind.volume;
    _base = null;
    _dy = 0;
    final id = _id;
    // Початкове значення беремо в системи: його могли змінити кнопки гучності чи шторка
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

  /// Запис у систему не частіше ~25 разів на секунду (останнє значення завжди доходить)
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

  // ── Горизонтальна перемотка ────────────────────────────────────────────────

  void _onHorizontalStart(DragStartDetails d) {
    _id++;
    final total = widget.player.state.duration;
    if (!widget.enabled || total <= Duration.zero || _inSystemEdge(d.localPosition)) {
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
        return GestureDetector(
          // translucent: дотик бачать і цей шар (перетягування), і відео під ним (тап, подвійний тап)
          behavior: HitTestBehavior.translucent,
          // Початок жесту = місце, куди торкнувся палець (а не точка після «порога» ~18 px): так правильно
          // визначаються половина екрана (яскравість / гучність) і системні краї, а рух відчувається одразу
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
        );
      },
    );
  }
}
