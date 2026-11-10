import 'dart:async';
import 'package:flutter/foundation.dart';

/// Автоприховування панелей керування на сенсорному екрані.
///
/// Курсора немає, тож «зона наведення» не працює: панелі показує тап по відео, а ховає цей таймер.
/// Кожен дотик до екрана ([arm]) відкладає приховування, тому панелі не зникають під пальцем.
class TouchHideTimer {
  TouchHideTimer({
    required this.shouldStayVisible,
    required this.onHide,
    this.delay = const Duration(seconds: 4),
  });

  /// Чи треба лишити панелі (пауза, відкрите меню, прискорення тощо) — тоді вони не ховаються
  final bool Function() shouldStayVisible;
  final VoidCallback onHide;
  final Duration delay;

  Timer? _timer;

  bool get isArmed => _timer != null;

  /// (Пере)запускає відлік. Викликається на кожен дотик, поки панелі видно.
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
