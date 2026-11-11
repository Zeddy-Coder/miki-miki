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
        padding: EdgeInsets.only(top: 6 * scale + AppHeaderInset.of(context), bottom: 28 * scale + bottomInset),
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

  /// Вимкнути власну анімацію зміни вкладки (коли вміст уже сам анімує перехід, як у налаштуваннях)
  final bool animate;

  const HikkaSwipeTabs({super.key, required this.index, required this.count, required this.onChanged, required this.child, this.swipe = true, this.animate = true});

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
    if (old.index != widget.index && widget.animate) {
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
      child: !widget.animate ? widget.child : AnimatedBuilder(
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

/// Поява вкладки: коли [active] стає true, вміст коротко виїжджає з боку [direction] (1 — справа, -1 — зліва) і
/// проявляється. Решту часу нічого не змінює, тож перше відображення вкладки й закриття сторінки поверх неї без анімації.
class HikkaTabEnter extends StatefulWidget {
  final bool active;
  final double direction;
  final Widget child;

  /// Анімувати й саме створення (вкладка вперше відкрита вже активною); для першої вкладки застосунку — false
  final bool animateOnMount;

  const HikkaTabEnter({super.key, required this.active, required this.direction, required this.child, this.animateOnMount = false});

  @override
  State<HikkaTabEnter> createState() => _HikkaTabEnterState();
}

class _HikkaTabEnterState extends State<HikkaTabEnter> with SingleTickerProviderStateMixin {
  late final AnimationController _ctl = AnimationController(vsync: this, duration: AppAnim.medium, value: 1);
  late final CurvedAnimation _curve = CurvedAnimation(parent: _ctl, curve: AppAnim.easeOut);
  double _dir = 1;

  @override
  void initState() {
    super.initState();
    if (widget.active && widget.animateOnMount) {
      _dir = widget.direction;
      _ctl.forward(from: 0);
    }
  }

  @override
  void didUpdateWidget(HikkaTabEnter old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) {
      _dir = widget.direction;
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
    return AnimatedBuilder(
      animation: _curve,
      child: widget.child,
      builder: (context, child) {
        // Структура дерева стала, щоб не губити стан вкладки, коли анімація закінчується
        final t = _curve.value;
        return Opacity(
          opacity: t >= 1 ? 1 : 0.2 + 0.8 * t,
          child: FractionalTranslation(translation: Offset(_dir * 0.08 * (1 - t), 0), child: child),
        );
      },
    );
  }
}

/// Шапка, що закріплена на самому верху сторінки й ховається при прокрутці вмісту вниз. [header] лежить ПОВЕРХ
/// [body] (як у YouTube) і лише зсувається вгору/вниз: вона не змінює ні розмір, ні позицію прокрутки вмісту, тож не
/// додає прискорення чи зміщення. Щоб на самому верху вміст не опинявся під шапкою, списки всередині [body] лишають
/// зверху відступ `AppHeaderInset.of(context)` (див. `HikkaPageFrame`, `HikkaPagedList`). Вкладені шапки (дні
/// календаря в «Огляді») сидять під зовнішньою й ховаються разом із нею.
/// Повертається шапка на самому верху сторінки або після помітного руху вгору: повільний рух рахується з меншою
/// вагою, тож випадковий посмик її не показує. [resetOn] — значення, зміна якого знову показує шапку.
class HikkaCollapsingHeader extends StatefulWidget {
  final Widget header;
  final Widget body;
  final Object? resetOn;

  const HikkaCollapsingHeader({super.key, required this.header, required this.body, this.resetOn});

  @override
  State<HikkaCollapsingHeader> createState() => _HikkaCollapsingHeaderState();
}

class _HikkaCollapsingHeaderState extends State<HikkaCollapsingHeader> with SingleTickerProviderStateMixin {
  /// Скільки пікселів треба проскролити вниз, щоб шапка сховалась, і вгору, щоб з'явилась («мертва зона»)
  static const double _hideAfter = 24;
  static const double _showAfter = 150;

  /// Швидкість (px/мс), від якої рух угору враховується повністю; повільніший рахується з меншою вагою
  static const double _fullSpeed = 1.2;
  static const double _slowWeight = 0.3;

  final GlobalKey _headerKey = GlobalKey();
  late final AnimationController _c = AnimationController(vsync: this, duration: AppAnim.medium, value: 1);
  late final Animation<double> _factor = CurvedAnimation(parent: _c, curve: AppAnim.easeOut, reverseCurve: AppAnim.easeOut);
  double _height = 0;
  double _acc = 0;
  bool _shown = true;
  Duration? _lastStamp;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  void didUpdateWidget(HikkaCollapsingHeader old) {
    super.didUpdateWidget(old);
    if (old.resetOn != widget.resetOn && !_shown) _setShown(true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _measure() {
    if (!mounted) return;
    final h = _headerKey.currentContext?.size?.height;
    if (h != null && (h - _height).abs() > 0.5) setState(() => _height = h);
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
    if (n.metrics.axis != Axis.vertical || n is! ScrollUpdateNotification) return false;
    final delta = n.scrollDelta ?? 0;
    final m = n.metrics;
    if (delta == 0) return false;
    // Підписаний накопичувач із допуском: дрібні посмики назад не скидають рух, а лише зменшують його.
    // Повільний рух угору враховується з меншою вагою: шапка з'являється пізніше, а різкий порух показує її швидко
    var weight = 1.0;
    final stamp = n.dragDetails?.sourceTimeStamp;
    if (delta < 0 && stamp != null && _lastStamp != null) {
      final dt = (stamp - _lastStamp!).inMicroseconds / 1000.0;
      if (dt > 0) weight = ((-delta / dt) / _fullSpeed).clamp(_slowWeight, 1.0);
    }
    _lastStamp = stamp;
    _acc = (_acc + delta * (delta < 0 ? weight : 1.0)).clamp(-_showAfter, _hideAfter);
    if (m.pixels <= 1 && !_shown) {
      _setShown(true);
    } else if (_acc <= -_showAfter && !_shown) {
      _setShown(true);
    } else if (_acc >= _hideAfter && _shown && m.pixels > 24 && m.maxScrollExtent > _height) {
      _setShown(false);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final outer = AppHeaderInset.maybeOf(context);
    final outerInset = outer?.inset ?? 0;
    final bg = uiTheme.bgPrimary;
    final header = AnimatedBuilder(
      animation: Listenable.merge([_factor, if (outer?.shown != null) outer!.shown!]),
      builder: (context, child) {
        final f = _factor.value.clamp(0.0, 1.0);
        // Під зовнішньою шапкою: її видима частина, а власне приховування — зсув угору на висоту шапки
        final base = outer == null ? 0.0 : outerInset * (outer.shown?.value.clamp(0.0, 1.0) ?? 1.0);
        return Transform.translate(
          offset: Offset(0, base - (1 - f) * _height),
          child: IgnorePointer(ignoring: f < 0.05, child: child),
        );
      },
      // Фон лише малюється й не перехоплює дотики поза вмістом шапки
      child: CustomPaint(
        painter: _HeaderBg(bg),
        child: NotificationListener<SizeChangedLayoutNotification>(
          onNotification: (_) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
            return false;
          },
          // Column(min) дає шапці необмежену висоту: інакше її Column(max) розтягнувся б на весь екран і ловив дотики
          child: SizeChangedLayoutNotifier(child: Column(mainAxisSize: MainAxisSize.min, children: [KeyedSubtree(key: _headerKey, child: Padding(padding: const EdgeInsets.only(bottom: 8), child: widget.header))])),
        ),
      ),
    );
    // ClipRect: прихована шапка не має виглядати з-під краю (наприклад, у зоні рядка стану)
    return ClipRect(
      child: Stack(
        children: [
          Positioned.fill(
            child: AppHeaderInset(
              inset: outerInset + _height,
              shown: _factor,
              child: NotificationListener<ScrollNotification>(onNotification: _onScroll, child: widget.body),
            ),
          ),
          Positioned(top: 0, left: 0, right: 0, child: header),
        ],
      ),
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

/// Суцільний фон шапки-накладки, прозорий для дотиків
class _HeaderBg extends CustomPainter {
  final Color color;
  const _HeaderBg(this.color);

  @override
  void paint(Canvas canvas, Size size) => canvas.drawRect(Offset.zero & size, Paint()..color = color);

  @override
  bool shouldRepaint(_HeaderBg old) => old.color != color;

  @override
  bool? hitTest(Offset position) => false;
}
