import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Pinch-zoom math for the video: bounds, "snapping" to screen edges and to characteristic scales.
class VideoZoomMath {
  VideoZoomMath._();

  static const double minScale = 1.0;
  static const double maxScale = 5.0;

  /// Edge snapping zone (logical pixels): closer than that the image "clicks" to the edge
  static const double edgeSnap = 28.0;

  /// Size of the video fitted to the screen (BoxFit.contain)
  static Size fitSize(Size view, double videoAspect) {
    if (view.isEmpty || videoAspect <= 0) return view;
    final viewAspect = view.width / view.height;
    return viewAspect > videoAspect ? Size(view.height * videoAspect, view.height) : Size(view.width, view.width / videoAspect);
  }

  /// The scale at which the video fills the whole screen without black bars (cropping the excess)
  static double coverScale(Size view, Size fit) {
    if (fit.isEmpty) return 1.0;
    return math.max(view.width / fit.width, view.height / fit.height);
  }

  /// Whether scale [s] snaps: 1 to normal size, 2 to "fill the screen", 0 is free
  static int magnetOf(double s, {required double cover}) {
    if ((s - 1.0).abs() < 0.06) return 1;
    if (cover > 1.05 && (s - cover).abs() <= cover * 0.06) return 2;
    return 0;
  }

  /// Scale after the pinch is released: close to 1× or to "fill the screen" it snaps
  static double snapScale(double s, {required double cover}) {
    if (s < 1.0 + 0.06) return 1.0;
    if (cover > 1.05 && (s - cover).abs() <= cover * 0.06) return cover;
    return s.clamp(minScale, maxScale).toDouble();
  }

  /// Offset within the screen: video edges do not move inside the screen; near an edge or the center it snaps
  static Offset clampOffset(Offset o, double scale, Size view, Size fit, {double snap = edgeSnap}) {
    double axis(double v, double content, double viewLen) {
      final maxOff = math.max(0.0, (content - viewLen) / 2);
      if (maxOff <= 0) return 0.0;
      var r = v.clamp(-maxOff, maxOff).toDouble();
      if ((r - maxOff).abs() < snap) return maxOff;
      if ((r + maxOff).abs() < snap) return -maxOff;
      if (r.abs() < snap) return 0.0;
      return r;
    }

    return Offset(axis(o.dx, fit.width * scale, view.width), axis(o.dy, fit.height * scale, view.height));
  }

  /// Offset so that the point under the fingers (focal, from the screen center) stays under them when the scale changes
  static Offset zoomAround({
    required Offset startOffset,
    required double startScale,
    required double scale,
    required Offset startFocal,
    required Offset focal,
  }) {
    final k = scale / startScale;
    return focal - (startFocal - startOffset) * k;
  }
}

/// Video zoom state: scale and offset from the center. Listened to by the video layer (Transform) and the gesture layer.
class VideoZoomController extends ChangeNotifier {
  double _scale = 1.0;
  Offset _offset = Offset.zero;
  bool _pinching = false;

  double get scale => _scale;
  Offset get offset => _offset;

  /// A two-finger pinch is in progress: the other gestures (brightness, volume, seek) stay quiet
  bool get pinching => _pinching;

  bool get zoomed => _scale > 1.0001 || _offset != Offset.zero;

  set pinching(bool v) {
    if (_pinching == v) return;
    _pinching = v;
    notifyListeners();
  }

  void set(double scale, Offset offset) {
    if (scale == _scale && offset == _offset) return;
    _scale = scale;
    _offset = offset;
    notifyListeners();
  }

  void reset() => set(1.0, Offset.zero);
}

/// Paints the child with the controller's scale and offset
class VideoZoomTransform extends StatelessWidget {
  final VideoZoomController? zoom;
  final Widget child;

  const VideoZoomTransform({super.key, required this.zoom, required this.child});

  @override
  Widget build(BuildContext context) {
    final z = zoom;
    if (z == null) return child;
    return ListenableBuilder(
      listenable: z,
      builder: (context, child) => Transform(
        alignment: Alignment.center,
        transform: Matrix4.translationValues(z.offset.dx, z.offset.dy, 0) * Matrix4.diagonal3Values(z.scale, z.scale, 1),
        child: child,
      ),
      child: child,
    );
  }
}
