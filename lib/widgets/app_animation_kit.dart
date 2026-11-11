import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../services/ui_theme_service.dart';

class AppAnim {
  static const Duration fast = Duration(milliseconds: 140);
  static const Duration normal = Duration(milliseconds: 180);
  static const Duration medium = Duration(milliseconds: 240);
  static const Duration slow = Duration(milliseconds: 320);
  static const Duration long = Duration(milliseconds: 600);

  static const Curve easeOut = Curves.easeOutCubic;
  static const Curve easeInOut = Curves.easeInOutCubic;
  static const Curve easeIn = Curves.easeInCubic;
}

class AppFadeSlideSwitcher extends StatelessWidget {
  final Widget child;
  final Duration duration;
  final AlignmentGeometry alignment;

  const AppFadeSlideSwitcher({
    super.key,
    required this.child,
    this.duration = AppAnim.normal,
    this.alignment = Alignment.topLeft,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: AppAnim.easeInOut,
      switchOutCurve: AppAnim.easeInOut,
      layoutBuilder: (Widget? currentChild, List<Widget> previousChildren) {
        return Stack(
          alignment: alignment,
          children: <Widget>[
            ...previousChildren,
            if (currentChild != null) currentChild,
          ],
        );
      },
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: child,
        );
      },
      child: child,
    );
  }
}

class AppFadeSwitcher extends StatelessWidget {
  final Widget child;
  final Duration duration;
  final AlignmentGeometry alignment;

  /// true — старий і новий вміст розтягуються на весь доступний простір
  final bool expand;

  const AppFadeSwitcher({
    super.key,
    required this.child,
    this.duration = AppAnim.fast,
    this.alignment = Alignment.topLeft,
    this.expand = false,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: AppAnim.easeOut,
      switchOutCurve: AppAnim.easeIn,
      layoutBuilder: (Widget? currentChild, List<Widget> previousChildren) {
        return Stack(
          alignment: alignment,
          fit: expand ? StackFit.expand : StackFit.loose,
          children: <Widget>[
            ...previousChildren,
            if (currentChild != null) currentChild,
          ],
        );
      },
      transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
      child: child,
    );
  }
}

/// Плавна поява/зникнення віджета (fade + легкий зсув). На відміну від `if (...)`,
/// під час зникнення вміст ще лишається на екрані й плавно гасне.
class AppPresence extends StatelessWidget {
  final bool visible;
  final Widget child;
  final Duration duration;
  final Offset slide;
  final bool expand;

  const AppPresence({
    super.key,
    required this.visible,
    required this.child,
    this.duration = AppAnim.normal,
    this.slide = const Offset(0, -0.25),
    this.expand = false,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: AppAnim.easeOut,
      switchOutCurve: AppAnim.easeIn,
      layoutBuilder: (Widget? currentChild, List<Widget> previousChildren) {
        return Stack(
          alignment: Alignment.center,
          fit: expand ? StackFit.expand : StackFit.loose,
          children: <Widget>[
            ...previousChildren,
            if (currentChild != null) currentChild,
          ],
        );
      },
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween<Offset>(begin: slide, end: Offset.zero).animate(anim),
          child: child,
        ),
      ),
      child: visible
          ? KeyedSubtree(key: const ValueKey('presence-on'), child: child)
          : const SizedBox.shrink(key: ValueKey('presence-off')),
    );
  }
}

/// AnimatedContainer із токенами кіта за замовчуванням
class AppAnimatedContainer extends StatelessWidget {
  final Duration duration;
  final Curve curve;
  final AlignmentGeometry? alignment;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? color;
  final Decoration? decoration;
  final Decoration? foregroundDecoration;
  final double? width;
  final double? height;
  final BoxConstraints? constraints;
  final Matrix4? transform;
  final AlignmentGeometry? transformAlignment;
  final Clip clipBehavior;
  final VoidCallback? onEnd;
  final Widget? child;

  const AppAnimatedContainer({
    super.key,
    this.duration = AppAnim.normal,
    this.curve = AppAnim.easeOut,
    this.alignment,
    this.padding,
    this.margin,
    this.color,
    this.decoration,
    this.foregroundDecoration,
    this.width,
    this.height,
    this.constraints,
    this.transform,
    this.transformAlignment,
    this.clipBehavior = Clip.none,
    this.onEnd,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: duration,
      curve: curve,
      alignment: alignment,
      padding: padding,
      margin: margin,
      color: color,
      decoration: decoration,
      foregroundDecoration: foregroundDecoration,
      width: width,
      height: height,
      constraints: constraints,
      transform: transform,
      transformAlignment: transformAlignment,
      clipBehavior: clipBehavior,
      onEnd: onEnd,
      child: child,
    );
  }
}

/// Плавна прозорість (AnimatedOpacity з токенами кіта)
class AppFade extends StatelessWidget {
  final double opacity;
  final Duration duration;
  final Curve curve;
  final Widget? child;

  const AppFade({
    super.key,
    required this.opacity,
    this.duration = AppAnim.normal,
    this.curve = AppAnim.easeOut,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(opacity: opacity, duration: duration, curve: curve, child: child);
  }
}

/// Плавний поворот (AnimatedRotation з токенами кіта)
class AppRotate extends StatelessWidget {
  final double turns;
  final Duration duration;
  final Curve curve;
  final Widget? child;

  const AppRotate({
    super.key,
    required this.turns,
    this.duration = AppAnim.normal,
    this.curve = AppAnim.easeOut,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedRotation(turns: turns, duration: duration, curve: curve, child: child);
  }
}

/// Плавна зміна розміру за вмістом
class AppAnimatedSize extends StatelessWidget {
  final Duration duration;
  final Curve curve;
  final AlignmentGeometry alignment;
  final Widget? child;

  const AppAnimatedSize({
    super.key,
    this.duration = AppAnim.normal,
    this.curve = AppAnim.easeOut,
    this.alignment = Alignment.topCenter,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(duration: duration, curve: curve, alignment: alignment, child: child);
  }
}

/// AnimatedPositioned із токенами кіта
class AppAnimatedPositioned extends StatelessWidget {
  final Duration duration;
  final Curve curve;
  final double? left;
  final double? top;
  final double? right;
  final double? bottom;
  final double? width;
  final double? height;
  final Widget child;

  const AppAnimatedPositioned({
    super.key,
    this.duration = AppAnim.medium,
    this.curve = AppAnim.easeOut,
    this.left,
    this.top,
    this.right,
    this.bottom,
    this.width,
    this.height,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedPositioned(
      duration: duration,
      curve: curve,
      left: left,
      top: top,
      right: right,
      bottom: bottom,
      width: width,
      height: height,
      child: child,
    );
  }
}

/// Бокова панель, що висувається: ширина плавно росте з 0 до [extent],
/// вміст при цьому не стискається (обрізається), а старий вміст плавно гасне.
class AppSlideReveal extends StatelessWidget {
  final bool isOpen;
  final double extent;
  final Widget child;
  final Duration duration;

  const AppSlideReveal({
    super.key,
    required this.isOpen,
    required this.extent,
    required this.child,
    this.duration = AppAnim.slow,
  });

  @override
  Widget build(BuildContext context) {
    return AppAnimatedContainer(
      duration: duration,
      width: isOpen ? extent : 0.0,
      child: ClipRect(
        child: OverflowBox(
          minWidth: extent,
          maxWidth: extent,
          alignment: Alignment.topRight,
          // Окремий шар: панель (з тінню) растеризується раз і лише зсувається під час анімації
          child: RepaintBoundary(child: child),
        ),
      ),
    );
  }
}

/// Плавне число 0..1 (для кастомних малювальників): значення анімується до [value]
class AppAnimatedValue extends StatelessWidget {
  final double value;
  final Duration duration;
  final Curve curve;
  final Widget Function(BuildContext context, double t) builder;

  const AppAnimatedValue({
    super.key,
    required this.value,
    required this.builder,
    this.duration = AppAnim.fast,
    this.curve = AppAnim.easeOut,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: value),
      duration: duration,
      curve: curve,
      builder: (context, t, _) => builder(context, t),
    );
  }
}

/// Діалоги з єдиною анімацією (fade + scale) замість стандартного showDialog
class AppDialogs {
  static Future<T?> show<T>(
    BuildContext context, {
    required WidgetBuilder builder,
    Color? barrierColor,
  }) {
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'dialog',
      barrierColor: barrierColor ?? Colors.black.withValues(alpha: 0.6),
      transitionDuration: AppAnim.medium,
      pageBuilder: (ctx, a1, a2) => builder(ctx),
      transitionBuilder: AppDialogTransition.build,
    );
  }
}

/// Суворо вертикальне розкриття (Top-to-Bottom, без горизонтального розширення)
class AppVerticalCollapse extends StatefulWidget {
  final bool isExpanded;
  final Widget child;
  final Duration duration;
  final Curve curve;

  const AppVerticalCollapse({
    super.key,
    required this.isExpanded,
    required this.child,
    this.duration = AppAnim.normal,
    this.curve = AppAnim.easeOut,
  });

  @override
  State<AppVerticalCollapse> createState() => _AppVerticalCollapseState();
}

class _AppVerticalCollapseState extends State<AppVerticalCollapse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
      value: widget.isExpanded ? 1.0 : 0.0,
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: widget.curve,
      reverseCurve: AppAnim.easeIn,
    );
  }

  @override
  void didUpdateWidget(AppVerticalCollapse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isExpanded != oldWidget.isExpanded) {
      if (widget.isExpanded) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: SizeTransition(
        axis: Axis.vertical,
        axisAlignment: -1.0,
        sizeFactor: _animation,
        child: widget.child,
      ),
    );
  }
}

class AppSlideDownCollapse extends StatefulWidget {
  final bool isExpanded;
  final Widget child;
  final Duration duration;
  final Curve curve;

  const AppSlideDownCollapse({
    super.key,
    required this.isExpanded,
    required this.child,
    this.duration = AppAnim.medium,
    this.curve = AppAnim.easeOut,
  });

  @override
  State<AppSlideDownCollapse> createState() => _AppSlideDownCollapseState();
}

class _AppSlideDownCollapseState extends State<AppSlideDownCollapse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
      value: widget.isExpanded ? 1.0 : 0.0,
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: widget.curve,
      reverseCurve: AppAnim.easeIn,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0.0, -0.15),
      end: Offset.zero,
    ).animate(_animation);
  }

  @override
  void didUpdateWidget(AppSlideDownCollapse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isExpanded != oldWidget.isExpanded) {
      if (widget.isExpanded) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: SizeTransition(
        sizeFactor: _animation,
        axisAlignment: -1.0,
        child: FadeTransition(
          opacity: _animation,
          child: SlideTransition(
            position: _slideAnimation,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class AppActivePillIndicator extends StatelessWidget {
  final bool isSelected;
  final double scale;
  final double activeHeight;
  final Color? color;

  const AppActivePillIndicator({
    super.key,
    required this.isSelected,
    required this.scale,
    this.activeHeight = 16.0,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: AppAnim.fast,
      curve: AppAnim.easeOut,
      opacity: isSelected ? 1.0 : 0.0,
      child: Container(
        width: 3.0 * scale,
        height: activeHeight * scale,
        decoration: BoxDecoration(
          color: color ?? uiTheme.accentColor,
          borderRadius: uiTheme.borderRadius(2.0 * scale),
        ),
      ),
    );
  }
}

class AppDialogTransition {
  static Widget build(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: AppAnim.easeOut,
      reverseCurve: AppAnim.easeIn,
    );
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.97, end: 1.0).animate(curved),
        child: child,
      ),
    );
  }
}

/// Розумний скрол: 1:1 прямий безконфліктний трекінг для тачпада, плавний інерційний наплив для мишки
class AppSmoothScrollView extends StatefulWidget {
  final ScrollController? controller;
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final ScrollPhysics? physics;

  const AppSmoothScrollView({
    super.key,
    this.controller,
    required this.child,
    this.padding,
    this.physics,
  });

  @override
  State<AppSmoothScrollView> createState() => _AppSmoothScrollViewState();
}

class _AppSmoothScrollViewState extends State<AppSmoothScrollView> {
  late ScrollController _scrollController;
  double _targetOffset = 0.0;
  bool _isOwnController = false;

  @override
  void initState() {
    super.initState();
    if (widget.controller != null) {
      _scrollController = widget.controller!;
    } else {
      _scrollController = ScrollController();
      _isOwnController = true;
    }
  }

  @override
  void didUpdateWidget(AppSmoothScrollView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != null && widget.controller != _scrollController) {
      if (_isOwnController) _scrollController.dispose();
      _scrollController = widget.controller!;
      _isOwnController = false;
    }
  }

  @override
  void dispose() {
    if (_isOwnController) _scrollController.dispose();
    super.dispose();
  }

  void _onPointerSignal(PointerSignalEvent pointerSignal) {
    if (pointerSignal is PointerScrollEvent) {
      final dy = pointerSignal.scrollDelta.dy;
      // Розпізнавання тачпада: PointerDeviceKind.trackpad або мікродельти
      final bool isTrackpad = pointerSignal.kind == PointerDeviceKind.trackpad ||
          dy.abs() < 24.0 ||
          (dy != dy.roundToDouble() && dy.abs() < 40.0);

      if (isTrackpad) {
        // Тачпад: пропускаємо напряму в нативний рушій Flutter для ідеального 1:1 відгуку
        return;
      }

      // Мишка: перехоплюємо грубі клацання коліщатка для надання інерційного напливу
      GestureBinding.instance.pointerSignalResolver.register(pointerSignal, (event) {
        if (event is! PointerScrollEvent) return;
        if (!_scrollController.hasClients) return;

        final pos = _scrollController.position;
        if ((_targetOffset - pos.pixels).abs() > 300) {
          _targetOffset = pos.pixels;
        }

        final double scrollAmount = event.scrollDelta.dy * 1.25;
        _targetOffset = (_targetOffset + scrollAmount).clamp(
          pos.minScrollExtent,
          pos.maxScrollExtent,
        );

        _scrollController.animateTo(
          _targetOffset,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SingleChildScrollView(
        controller: _scrollController,
        padding: widget.padding,
        physics: widget.physics,
        child: Listener(
          onPointerSignal: _onPointerSignal,
          behavior: HitTestBehavior.translucent,
          child: widget.child,
        ),
      ),
    );
  }
}

/// Контролер плавної прокрутки колесом миші для БУДЬ-ЯКОГО скролу (ListView, SingleChildScrollView…).
///
/// Стандартна поведінка Flutter на десктопі: кожен «клік» колеса миттєво стрибає на
/// фіксовану відстань без інерції, і це виглядає як гальмування. Тут колесо
/// накопичує цільову позицію й пливе до неї 220 мс (easeOutCubic). Тачпад і
/// дрібні дельти йдуть напряму, без згладжування, щоб відгук був 1:1.
///
/// На відміну від [AppSmoothScrollView], працює і зі списками, які будуються ліниво.
class AppSmoothScrollController extends ScrollController {
  AppSmoothScrollController({
    super.initialScrollOffset,
    super.keepScrollOffset,
    super.debugLabel,
  });

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    return _AppSmoothScrollPosition(
      physics: physics,
      context: context,
      initialPixels: initialScrollOffset,
      keepScrollOffset: keepScrollOffset,
      oldPosition: oldPosition,
      debugLabel: debugLabel,
    );
  }
}

class _AppSmoothScrollPosition extends ScrollPositionWithSingleContext {
  _AppSmoothScrollPosition({
    required ScrollPhysics physics,
    required ScrollContext context,
    double? initialPixels = 0.0,
    bool keepScrollOffset = true,
    ScrollPosition? oldPosition,
    String? debugLabel,
  }) : super(
          physics: physics,
          context: context,
          initialPixels: initialPixels,
          keepScrollOffset: keepScrollOffset,
          oldPosition: oldPosition,
          debugLabel: debugLabel,
        );

  double _target = 0.0;

  @override
  void pointerScroll(double delta) {
    // Тачпад / мікродельти: напряму, як у стандартному рушії
    if (delta == 0.0 || delta.abs() < 24.0) {
      super.pointerScroll(delta);
      return;
    }

    // Якщо анімація не триває, цільова позиція починається з поточної
    if (activity is! DrivenScrollActivity || (_target - pixels).abs() > 400) {
      _target = pixels;
    }

    _target = (_target + delta * 1.25).clamp(minScrollExtent, maxScrollExtent).toDouble();
    if (_target == pixels) return;

    animateTo(
      _target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }
}
