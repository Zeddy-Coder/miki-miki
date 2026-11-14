import 'dart:async';
import 'package:flutter/foundation.dart';

/// Auto-hiding the control panels on a touch screen.
///
/// There is no cursor, so the "hover zone" does not work: a tap on the video shows the panels and this timer hides them.
/// Every touch on the screen ([arm]) postpones hiding, so the panels do not vanish under a finger.
class TouchHideTimer {
  TouchHideTimer({
    required this.shouldStayVisible,
    required this.onHide,
    this.delay = const Duration(seconds: 4),
  });

  /// Whether to keep the panels (pause, an open menu, speed-up etc.): then they do not hide
  final bool Function() shouldStayVisible;
  final VoidCallback onHide;
  final Duration delay;

  Timer? _timer;

  bool get isArmed => _timer != null;

  /// (Re)starts the countdown. Called on every touch while the panels are visible.
  void arm() {
    _timer?.cancel();
    _timer = Timer(delay, () {
      _timer = null;
      if (!shouldStayVisible()) onHide();
    });
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }
}
