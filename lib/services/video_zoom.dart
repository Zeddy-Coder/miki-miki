import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Математика збільшення відео щипком: межі, «прилипання» до країв екрана й до характерних масштабів.
class VideoZoomMath {
  VideoZoomMath._();

  static const double minScale = 1.0;
  static const double maxScale = 5.0;

  /// Зона прилипання до краю (логічні пікселі): ближче — зображення «клацає» в край
  static const double edgeSnap = 28.0;

  /// Розмір відео, вписаного в екран (BoxFit.contain)
  static Size fitSize(Size view, double videoAspect) {
    if (view.isEmpty || videoAspect <= 0) return view;
    final viewAspect = view.width / view.height;
    return viewAspect > videoAspect ? Size(view.height * videoAspect, view.height) : Size(view.width, view.width / videoAspect);
  }

  /// Масштаб, за якого відео заповнює весь екран без чорних смуг (обрізаючи зайве)
  static double coverScale(Size view, Size fit) {
    if (fit.isEmpty) return 1.0;
    return math.max(view.width / fit.width, view.height / fit.height);
  }

  /// Чи притягує масштаб [s]: 1 — до звичайного розміру, 2 — до «на весь екран», 0 — вільно
  static int magnetOf(double s, {required double cover}) {
    if ((s - 1.0).abs() < 0.06) return 1;
    if (cover > 1.05 && (s - cover).abs() <= cover * 0.06) return 2;
    return 0;
  }

  /// Масштаб після відпускання щипка: близько до 1× або до «на весь екран» — прилипає
  static double snapScale(double s, {required double cover}) {
    if (s < 1.0 + 0.06) return 1.0;
    if (cover > 1.05 && (s - cover).abs() <= cover * 0.06) return cover;
    return s.clamp(minScale, maxScale).toDouble();
  }

  /// Зміщення в межах екрана: краї відео не заходять усередину екрана; поблизу краю чи центру — прилипає
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

  /// Зміщення так, щоб точка під пальцями (focal, від центру екрана) лишалась під ними при зміні масштабу
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

/// Стан збільшення відео: масштаб і зсув від центру. Слухає відеошар (Transform) і шар жестів.
class VideoZoomController extends ChangeNotifier {
  double _scale = 1.0;
  Offset _offset = Offset.zero;
  bool _pinching = false;

  double get scale => _scale;
  Offset get offset => _offset;

  /// Йде щипок двома пальцями: решта жестів (яскравість, гучність, перемотка) мовчать
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

/// Малює дитину з масштабом і зсувом контролера
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
