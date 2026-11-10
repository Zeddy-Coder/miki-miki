import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

/// Математика жестів на відео (телефон). Чиста, без віджетів — перевіряється окремими тестами.
///
/// - вертикальне перетягування: ліва половина екрана — яскравість, права — гучність;
/// - горизонтальне перетягування: перемотка (повна ширина екрана ≈ 10 % тривалості, 60…240 с).
class TouchGestureMath {
  const TouchGestureMath._();

  /// Скільки секунд відповідає перетягуванню на всю ширину екрана
  static double seekSpanSeconds(Duration total) {
    final totalSec = total.inMilliseconds / 1000.0;
    final span = (totalSec * 0.10).clamp(60.0, 240.0);
    // Коротке відео не перемотуємо далі за його кінець
    return math.min(span, math.max(totalSec, 1.0));
  }

  /// Позиція після горизонтального зсуву [dx] (px) на екрані завширшки [width]
  static Duration seekTarget({
    required Duration start,
    required Duration total,
    required double dx,
    required double width,
  }) {
    if (width <= 0 || total <= Duration.zero) return start;
    final deltaMs = (dx / width * seekSpanSeconds(total) * 1000).round();
    final ms = (start.inMilliseconds + deltaMs).clamp(0, total.inMilliseconds);
    return Duration(milliseconds: ms);
  }

  /// Рівень 0..1 (яскравість / гучність) після вертикального зсуву [dy] (px; вгору — від'ємний).
  /// Увесь діапазон — це ~85 % висоти екрана.
  static double levelAfterDrag({required double start, required double dy, required double height}) {
    if (height <= 0) return start.clamp(0.0, 1.0);
    return (start - dy / (height * 0.85)).clamp(0.0, 1.0);
  }

  /// Ліва половина екрана — яскравість, права — гучність
  static bool isBrightnessSide(double x, double width) => x < width / 2;

  /// Початок жесту впритул до краю екрана — це системні жести (назад, шторка, «додому»): не чіпаємо
  static bool inSystemEdge(Offset p, Size size, {double side = 22, double top = 30, double bottom = 30}) {
    return p.dx < side || p.dx > size.width - side || p.dy < top || p.dy > size.height - bottom;
  }

  /// Підпис зсуву перемотки: «+0:23», «−1:05»
  static String deltaLabel(Duration delta) {
    final neg = delta.isNegative;
    final s = delta.inSeconds.abs();
    final m = s ~/ 60;
    final sec = (s % 60).toString().padLeft(2, '0');
    final body = m >= 60 ? '${m ~/ 60}:${(m % 60).toString().padLeft(2, '0')}:$sec' : '$m:$sec';
    return '${neg ? '−' : '+'}$body';
  }
}
