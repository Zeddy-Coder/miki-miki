import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

/// Gesture math on the video (phone). Pure, without widgets: tested separately.
///
/// - vertical drag: the left half of the screen is brightness, the right is volume;
/// - horizontal drag: seek (full screen width ≈ 10 % of the duration, 60…240 s).
class TouchGestureMath {
  const TouchGestureMath._();

  /// How many seconds a full-screen-width drag corresponds to
  static double seekSpanSeconds(Duration total) {
    final totalSec = total.inMilliseconds / 1000.0;
    final span = (totalSec * 0.10).clamp(60.0, 240.0);
    // A short video is not seeked past its end
    return math.min(span, math.max(totalSec, 1.0));
  }

  /// Position after a horizontal shift [dx] (px) on a screen of width [width]
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

  /// Level 0..1 (brightness / volume) after a vertical shift [dy] (px; up is negative).
  /// The whole range is ~85 % of the screen height.
  static double levelAfterDrag({required double start, required double dy, required double height}) {
    if (height <= 0) return start.clamp(0.0, 1.0);
    return (start - dy / (height * 0.85)).clamp(0.0, 1.0);
  }

  /// The left half of the screen is brightness, the right is volume
  static bool isBrightnessSide(double x, double width) => x < width / 2;

  /// A gesture that starts right at the screen edge is a system gesture (back, shade, "home"): we do not touch it
  static bool inSystemEdge(Offset p, Size size, {double side = 22, double top = 30, double bottom = 30}) {
    return p.dx < side || p.dx > size.width - side || p.dy < top || p.dy > size.height - bottom;
  }

  /// Label of the seek offset: "+0:23", "−1:05"
  static String deltaLabel(Duration delta) {
    final neg = delta.isNegative;
    final s = delta.inSeconds.abs();
    final m = s ~/ 60;
    final sec = (s % 60).toString().padLeft(2, '0');
    final body = m >= 60 ? '${m ~/ 60}:${(m % 60).toString().padLeft(2, '0')}:$sec' : '$m:$sec';
    return '${neg ? '−' : '+'}$body';
  }
}
