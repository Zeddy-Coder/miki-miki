import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/ui_theme_service.dart';
import '../../utils/platform_info.dart';
import '../app_animation_kit.dart';
import '../app_ui_kit.dart';
import 'hikka_common.dart';

/// Каркас сторінки з прокруткою: вміст по центру до [HikkaLayout.maxContentWidth], тонкий скролбар,
/// відступ знизу під згорнутий плеєр. Діти самі відповідають за бічні відступи (полиці йдуть до краю екрана).
class HikkaPageFrame extends StatelessWidget {
  final double scale;
  final ScrollController controller;
  final double bottomInset;
  final List<Widget> children;

  /// Оновлення потягом вниз (лише на телефоні; на ПК є кнопка «Оновити»)
  final Future<void> Function()? onRefresh;

  const HikkaPageFrame({
    super.key,
    required this.scale,
    required this.controller,
    required this.children,
    this.bottomInset = 0,
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final refresh = AppPlatform.isMobile ? onRefresh : null;
    Widget content = AppScrollbar(
      scale: scale,
      controller: controller,
      child: SingleChildScrollView(
        controller: controller,
        physics: refresh == null ? null : const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(top: 6 * scale, bottom: 28 * scale + bottomInset),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: HikkaLayout.maxContentWidth),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
          ),
        ),
      ),
    );
    if (refresh != null) {
      content = AppPullToRefresh(onRefresh: refresh, child: content);
    }
    return content;
  }
}

/// Секція сторінки: заголовок (з підзаголовком і діями справа) і вміст
class HikkaSection extends StatelessWidget {
  final double scale;
  final double pad;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;
  final double bottom;

  const HikkaSection({
    super.key,
    required this.scale,
    required this.pad,
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
    this.bottom = 22,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 0, pad, bottom * scale),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionHeader(scale: scale, title: title, subtitle: subtitle, trailing: trailing),
          SizedBox(height: 10 * scale),
          child,
        ],
      ),
    );
  }
}

/// Ширина постера / портрета в шапці сторінки
double hikkaHeaderPosterWidth(double scale, {required bool wide}) {
  if (AppPlatform.isMobile) return wide ? 190.0 : 112.0;
  return (wide ? 250 : 130) * scale;
}

/// Вміст ширший за цю межу розкладається у два стовпці (постер ліворуч)
const double hikkaWideBreakpoint = 760;

/// Найбільша ширина списків «рядок на тайтл» і текстових блоків (на широких вікнах решта порожня)
double hikkaReadableWidth(double scale) => 780 * (AppPlatform.isMobile ? 1.0 : scale);

/// Заголовок головної вкладки (Огляд, Списки, Профіль): назва з підписом і дії справа. На телефоні — компактний
/// рядок з відступами сторінки, на ПК — як шапки панелей застосунку.
class HikkaTabHeader extends StatelessWidget {
  final double scale;
  final String title;
  final String? subtitle;
  final List<Widget> actions;

  const HikkaTabHeader({super.key, required this.scale, required this.title, this.subtitle, this.actions = const []});

  @override
  Widget build(BuildContext context) {
    final mobile = AppPlatform.isMobile;
    final pad = HikkaLayout.sidePad(context, scale);
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, (mobile ? 6 : 14) * scale, math.max(pad - 8, 4), (mobile ? 4 : 8) * scale),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: hikkaStyle((mobile ? 22 : 18) * scale, weight: FontWeight.bold, height: 1.2)),
                if (subtitle != null)
                  Padding(
                    padding: EdgeInsets.only(top: 2 * scale),
                    child: Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: hikkaStyle(12 * scale, color: uiTheme.textDarkMuted)),
                  ),
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

/// Перегортання вкладок свайпом убік: різкий рух ліворуч — наступна вкладка, праворуч — попередня. Зміну вкладки
/// (свайпом чи тапом по мітці) супроводжує коротка анімація: вміст виїжджає з того боку, куди йде перехід.
/// Внутрішні горизонтальні списки (полиці) мають пріоритет, тож не заважають.
class HikkaSwipeTabs extends StatefulWidget {
  final int index;
  final int count;
  final ValueChanged<int> onChanged;
  final Widget child;

  /// Вимкнути жест (внутрішні вкладки, щоб свайп лишався зовнішнім вкладкам); анімація зміни лишається
  final bool swipe;

  const HikkaSwipeTabs({super.key, required this.index, required this.count, required this.onChanged, required this.child, this.swipe = true});

  @override
  State<HikkaSwipeTabs> createState() => _HikkaSwipeTabsState();
}

class _HikkaSwipeTabsState extends State<HikkaSwipeTabs> with SingleTickerProviderStateMixin {
  late final AnimationController _ctl = AnimationController(vsync: this, duration: AppAnim.medium, value: 1);
  late final CurvedAnimation _curve = CurvedAnimation(parent: _ctl, curve: AppAnim.easeOut);
  double _dir = 1;

  @override
  void didUpdateWidget(HikkaSwipeTabs old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) {
      _dir = widget.index > old.index ? 1 : -1;
      _ctl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragEnd: !widget.swipe ? null : (d) {
        final v = d.primaryVelocity ?? 0;
        if (v < -300 && widget.index < widget.count - 1) widget.onChanged(widget.index + 1);
        if (v > 300 && widget.index > 0) widget.onChanged(widget.index - 1);
      },
      child: AnimatedBuilder(
        animation: _curve,
        child: widget.child,
        builder: (context, child) {
          final t = _curve.value;
          return Opacity(
            opacity: 0.25 + 0.75 * t,
            child: FractionalTranslation(translation: Offset(_dir * 0.12 * (1 - t), 0), child: child),
          );
        },
      ),
    );
  }
}

/// Шапка, що ховається при прокрутці вмісту вниз і повертається при прокрутці вгору (або на самому верху).
/// [header] стоїть над [body]; реагує на вертикальну прокрутку будь-якого списку всередині [body]. Вкладені
/// шапки (наприклад, дні календаря в «Огляді») ховаються разом із зовнішньою. [resetOn] — значення, зміна якого
/// знову показує шапку (перехід на іншу вкладку).
///
/// Щоб поява/зникнення шапки не «підштовхувала» вміст (відчувається як прискорення прокрутки), разом зі зміною
/// висоти шапки зсувається позиція прокрутки на таку саму величину: вміст лишається на місці, а шапка немов
/// з'їжджає поверх нього. Додатково є «мертва зона»: шапка реагує лише після помітного руху в один бік.
class HikkaCollapsingHeader extends StatefulWidget {
  final Widget header;
  final Widget body;
  final Object? resetOn;

  const HikkaCollapsingHeader({super.key, required this.header, required this.body, this.resetOn});

  @override
  State<HikkaCollapsingHeader> createState() => _HikkaCollapsingHeaderState();
}

class _HikkaCollapsingHeaderState extends State<HikkaCollapsingHeader> with SingleTickerProviderStateMixin {
  /// Скільки пікселів треба проскролити вниз, щоб шапка сховалась, і вгору, щоб з'явилась
  static const double _hideAfter = 24;
  static const double _showAfter = 40;

  final GlobalKey _headerKey = GlobalKey();
  late final AnimationController _c = AnimationController(vsync: this, duration: AppAnim.medium, value: 1);
  late final Animation<double> _factor = CurvedAnimation(parent: _c, curve: AppAnim.easeOut, reverseCurve: AppAnim.easeOut);
  ScrollPosition? _pos;
  double _lastFactor = 1;
  double _acc = 0;
  bool _shown = true;

  @override
  void initState() {
    super.initState();
    _factor.addListener(_onTick);
  }

  @override
  void didUpdateWidget(HikkaCollapsingHeader old) {
    super.didUpdateWidget(old);
    if (old.resetOn != widget.resetOn && !_shown) {
      _pos = null; // інший список — позицію не коригуємо
      _setShown(true);
    }
  }

  @override
  void dispose() {
    _factor.removeListener(_onTick);
    _c.dispose();
    super.dispose();
  }

  double get _headerHeight => (_headerKey.currentContext?.size?.height) ?? 0;

  /// Висота шапки змінюється — зсуваємо прокрутку на стільки ж, щоб вміст не рухався
  void _onTick() {
    final f = _factor.value;
    final delta = (f - _lastFactor) * _headerHeight;
    _lastFactor = f;
    final pos = _pos;
    if (pos == null || !pos.hasPixels || delta == 0) return;
    if (delta > 0 && pos.pixels <= 1) return; // шапка повертається на верху списку — вміст природно зсувається вниз
    final correction = delta < 0 ? math.max(delta, -pos.pixels) : delta;
    pos.correctBy(correction);
  }

  void _setShown(bool v) {
    if (_shown == v) return;
    _shown = v;
    _acc = 0;
    if (v) {
      _c.forward();
    } else {
      _c.reverse();
    }
  }

  bool _onScroll(ScrollNotification n) {
    if (n.metrics.axis != Axis.vertical) return false;
    if (n is ScrollStartNotification || n is ScrollUpdateNotification) {
      final ctx = n.context;
      if (ctx != null) {
        final st = Scrollable.maybeOf(ctx);
        if (st != null && st.position.axis == Axis.vertical) _pos = st.position;
      }
    }
    if (n is! ScrollUpdateNotification) return false;
    final delta = n.scrollDelta ?? 0;
    final m = n.metrics;
    if (delta == 0) return false;
    // Накопичуємо рух в один бік; зміна напряму скидає лічильник
    _acc = (_acc != 0 && (_acc > 0) != (delta > 0)) ? delta : _acc + delta;
    if (m.pixels <= 1 && !_shown) {
      _setShown(true);
    } else if (_acc <= -_showAfter && !_shown) {
      _setShown(true);
    } else if (_acc >= _hideAfter && _shown && m.pixels > 24) {
      // Без запасу прокрутки шапка не повернулася б: після її приховування вміст міг би перестати скролитись
      if (m.maxScrollExtent - _headerHeight > 48) _setShown(false);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedBuilder(
          animation: _factor,
          builder: (context, child) => ClipRect(
            child: Align(
              alignment: Alignment.topCenter,
              heightFactor: _factor.value.clamp(0.0, 1.0),
              child: Opacity(opacity: _factor.value.clamp(0.0, 1.0), child: child),
            ),
          ),
          child: KeyedSubtree(key: _headerKey, child: widget.header),
        ),
        Expanded(child: NotificationListener<ScrollNotification>(onNotification: _onScroll, child: widget.body)),
      ],
    );
  }
}

/// Будує [builder] (а отже й запускає його запити) лише тоді, коли місце секції наближається до видимої
/// частини прокрутки. До того там порожня ділянка висотою [height]. Раз змонтована, секція лишається.
/// Для довгих сторінок: нижні полиці не вантажаться, поки їх не прокрутили.
class HikkaLazy extends StatefulWidget {
  final double height;

  /// За скільки пікселів до краю екрана починати завантаження
  final double lead;
  final WidgetBuilder builder;

  const HikkaLazy({super.key, required this.height, required this.builder, this.lead = 700});

  @override
  State<HikkaLazy> createState() => _HikkaLazyState();
}

class _HikkaLazyState extends State<HikkaLazy> {
  bool _shown = false;
  ScrollPosition? _position;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_shown) return;
    final next = Scrollable.maybeOf(context)?.position;
    if (next != _position) {
      _position?.removeListener(_check);
      _position = next;
      next?.addListener(_check);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    _position?.removeListener(_check);
    super.dispose();
  }

  void _check() {
    if (_shown || !mounted) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    final top = box.localToGlobal(Offset.zero).dy;
    final screen = MediaQuery.sizeOf(context).height;
    if (top < screen + widget.lead) {
      _position?.removeListener(_check);
      setState(() => _shown = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_shown) return widget.builder(context);
    return SizedBox(height: widget.height);
  }
}
