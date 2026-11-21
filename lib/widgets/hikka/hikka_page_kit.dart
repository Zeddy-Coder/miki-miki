import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/ui_theme_service.dart';
import '../../utils/platform_info.dart';
import '../app_animation_kit.dart';
import '../app_tones.dart';
import '../app_ui_kit.dart';
import '../design_kit.dart' show showAppMenu, appRectOf, AppMenuEntry;
import '../line_icons.dart';
import 'hikka_common.dart';

/// A scrolling page frame: content centered up to [HikkaLayout.maxContentWidth], a thin scrollbar,
/// bottom padding for the collapsed player. Children handle the side padding themselves (shelves go to the screen edge).
class HikkaPageFrame extends StatelessWidget {
  final double scale;
  final ScrollController controller;
  final double bottomInset;
  final List<Widget> children;

  /// A long run after [children] (a hundred notifications, the titles of a franchise, the blocks of an article):
  /// [itemCount] pieces, each built only when it comes near the screen. Laid out as [children] are: in the content
  /// column, each at its own width from the left edge
  final int itemCount;
  final IndexedWidgetBuilder? itemBuilder;

  /// With [itemBuilder]: how wide the page's content is when narrower than the frame (an article's reading column).
  /// The column is centered, as the content of an ordinary page (a column as wide as its widest child) is
  final double? columnWidth;

  /// Pull-down refresh (phone only; on PC there is an "Оновити" button)
  final Future<void> Function()? onRefresh;

  const HikkaPageFrame({
    super.key,
    required this.scale,
    required this.controller,
    required this.children,
    this.bottomInset = 0,
    this.onRefresh,
    this.itemCount = 0,
    this.itemBuilder,
    this.columnWidth,
  });

  @override
  Widget build(BuildContext context) {
    final refresh = AppPlatform.isMobile ? onRefresh : null;
    final physics = refresh == null ? null : const AlwaysScrollableScrollPhysics();
    final top = 6 * scale + AppHeaderInset.of(context);
    final bottom = 28 * scale + bottomInset;
    final builder = itemBuilder;
    Widget content;
    if (builder == null || itemCount <= 0) {
      content = AppScrollbar(
        scale: scale,
        controller: controller,
        child: SingleChildScrollView(
          controller: controller,
          physics: physics,
          padding: EdgeInsets.only(top: top, bottom: bottom),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: HikkaLayout.maxContentWidth),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
            ),
          ),
        ),
      );
    } else {
      // A lazy list: a column with everything built at once laid out a hundred posters on opening and repainted the
      // whole page on every scroll frame. The column is centered from the frame's width alone (a SliverLayoutBuilder
      // would run on every scroll frame); the pieces keep the column's loose width, as in it
      content = LayoutBuilder(
        builder: (context, box) {
          final column = math.min(HikkaLayout.maxContentWidth, columnWidth ?? double.infinity);
          final side = math.max(0.0, (box.maxWidth - column) / 2);
          return AppScrollbar(
            scale: scale,
            controller: controller,
            child: CustomScrollView(
              controller: controller,
              physics: physics,
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(side, top, side, 0),
                  sliver: SliverToBoxAdapter(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children)),
                ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(side, 0, side, bottom),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => Align(alignment: AlignmentDirectional.topStart, child: builder(context, i)),
                      childCount: itemCount,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    }
    if (refresh != null) {
      content = AppPullToRefresh(onRefresh: refresh, child: content);
    }
    return content;
  }
}

/// A page section: a heading (with a subtitle and actions on the right) and content
class HikkaSection extends StatelessWidget {
  final double scale;
  final double pad;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;
  final double bottom;

  /// Heading size before scaling (the title page's phone layout uses a larger one)
  final double titleSize;

  const HikkaSection({
    super.key,
    required this.scale,
    required this.pad,
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
    this.bottom = 22,
    this.titleSize = 13.5,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 0, pad, bottom * scale),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionHeader(scale: scale, title: title, subtitle: subtitle, trailing: trailing, titleSize: titleSize, calm: titleSize >= 15),
          SizedBox(height: 10 * scale),
          child,
        ],
      ),
    );
  }
}

/// A quiet order line ("Популярні ⌄", as the sort line of "Списки"): a tap opens the shared drop-down under it
class HikkaSortLine<T> extends StatelessWidget {
  final double scale;
  final double pad;
  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;

  /// The menu's caption ("Порядок")
  final String caption;
  final double top;

  const HikkaSortLine({
    super.key,
    required this.scale,
    required this.pad,
    required this.value,
    required this.options,
    required this.onChanged,
    this.caption = 'Порядок',
    this.top = 8,
  });

  Future<void> _pick(BuildContext context, BuildContext anchor) async {
    final picked = await showAppMenu<T>(
      context,
      scale: scale,
      anchor: appRectOf(anchor),
      caption: caption,
      entries: [for (final (v, label) in options) AppMenuEntry<T>(v, label, selected: v == value)],
    );
    if (picked != null && picked != value) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final label = options.firstWhere((o) => o.$1 == value, orElse: () => options.first).$2;
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, top * scale, pad, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Builder(
          builder: (anchor) => Semantics(
            button: true,
            label: '$caption: $label',
            excludeSemantics: true,
            child: InkWell(
              onTap: () => _pick(context, anchor),
              borderRadius: uiTheme.borderRadius(8 * scale),
              splashColor: Colors.transparent,
              highlightColor: uiTheme.touchHighlight,
              hoverColor: uiTheme.hoverOverlay,
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 8 * scale),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label, style: hikkaStyle(13.5 * scale, color: AppTones.plateText)),
                    SizedBox(width: 4 * scale),
                    LineIconView(LineIcon.chevronDown, size: 16 * scale, color: uiTheme.textMuted),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A grey line right under the bar of an open page: what the page is about ("Проводжальниця Фрірен · 53")
class HikkaLeadLine extends StatelessWidget {
  final double scale;
  final double pad;
  final List<String> parts;

  const HikkaLeadLine({super.key, required this.scale, required this.pad, required this.parts});

  @override
  Widget build(BuildContext context) {
    if (parts.isEmpty) return SizedBox(height: 4 * scale);
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 0, pad, 8 * scale),
      child: Text(parts.join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis, style: hikkaStyle(13 * scale, color: uiTheme.textMuted, height: 1.35)),
    );
  }
}

/// A quiet counter under a name in a page header: a line icon and "5 аніме"
Widget hikkaCountLine(double scale, LineIcon icon, String text) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        LineIconView(icon, size: 18 * scale, color: AppTones.rowSub),
        SizedBox(width: 8 * scale),
        Flexible(child: Text(text, style: hikkaStyle(13 * scale, color: AppTones.plateText))),
      ],
    );

/// Width of the poster / portrait in the page header
double hikkaHeaderPosterWidth(double scale, {required bool wide}) {
  if (AppPlatform.isMobile) return wide ? 190.0 : 112.0;
  return (wide ? 250 : 130) * scale;
}

/// Content wider than this limit lays out in two columns (the poster on the left)
const double hikkaWideBreakpoint = 760;

/// Maximum width of "one row per title" lists and text blocks (on wide windows the rest is empty)
double hikkaReadableWidth(double scale) => 780 * (AppPlatform.isMobile ? 1.0 : scale);

/// Heading of a main tab (Огляд, Списки, Профіль): a title with a label and actions on the right. On a phone a compact
/// row with the page padding, on PC like the app's panel headers.
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
      padding: EdgeInsets.fromLTRB(pad, (mobile ? 8 : 14) * scale, math.max(pad - 8, 4), (mobile ? 0 : 6) * scale),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: hikkaStyle((mobile ? 24 : 20) * scale, weight: FontWeight.bold, height: 1.2)),
                if (subtitle != null)
                  Padding(
                    padding: EdgeInsets.only(top: 2 * scale),
                    child: Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: hikkaStyle(13 * scale, color: uiTheme.textMuted)),
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

/// Flipping tabs by a sideways swipe: a sharp move left is the next tab, right is the previous. A tab change
/// (by swipe or tapping a label) comes with a short animation: the content slides in from the side the transition goes to.
/// Inner horizontal lists (shelves) take priority, so they do not interfere.
class HikkaSwipeTabs extends StatefulWidget {
  final int index;
  final int count;
  final ValueChanged<int> onChanged;
  final Widget child;

  /// Disable the gesture (inner tabs, so the swipe stays with the outer tabs); the change animation remains
  final bool swipe;

  /// Disable the own tab change animation (when the content already animates the transition itself, as in settings)
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

/// Tab appearance: when [active] becomes true, the content briefly slides in from side [direction] (1 is right, -1 is left) and
/// fades in. At other times it changes nothing, so a tab's first display and closing a page over it have no animation.
class HikkaTabEnter extends StatefulWidget {
  final bool active;
  final double direction;
  final Widget child;

  /// Animate creation too (a tab opened for the first time already active); false for the app's first tab
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
        // The tree structure is constant so as not to lose tab state when the animation ends
        final t = _curve.value;
        return Opacity(
          opacity: t >= 1 ? 1 : 0.2 + 0.8 * t,
          child: FractionalTranslation(translation: Offset(_dir * 0.08 * (1 - t), 0), child: child),
        );
      },
    );
  }
}

/// A place in the nearest [HikkaCollapsingHeader] where a page below it can put its own header part (e.g. the calendar's
/// weekday tabs): that part is drawn under the outer header's content, is measured together with it and hides and shows
/// with it as one block, so the two never go out of step (a separate nested header did).
class HikkaHeaderSlot extends ChangeNotifier {
  bool _dead = false;
  Widget? _widget;
  Object? _resetOn;
  Object? _seenReset;
  Object? _same;

  Widget? get widget => _widget;

  /// Puts [w] into the slot; a change of [resetOn] shows the header again. [same] — what [w] is made of: while it is
  /// equal, the slot keeps the widget it has and the header is not rebuilt (the page puts its part after every build)
  void put(Widget? w, {Object? resetOn, Object? same}) {
    if (_dead) return;
    if (same != null && same == _same && _widget != null && resetOn == _resetOn) return;
    _widget = w;
    _resetOn = resetOn;
    _same = same;
    notifyListeners();
  }

  void clear() {
    if (_dead || _widget == null) return;
    _widget = null;
    _same = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _dead = true;
    super.dispose();
  }

  /// true once if [resetOn] changed since the last call
  bool takeReset() {
    final changed = _seenReset != _resetOn;
    _seenReset = _resetOn;
    return changed;
  }
}

class _HeaderSlotScope extends InheritedWidget {
  final HikkaHeaderSlot slot;

  const _HeaderSlotScope({required this.slot, required super.child});

  @override
  bool updateShouldNotify(_HeaderSlotScope old) => slot != old.slot;
}

/// The slot of the nearest [HikkaCollapsingHeader] above [context] (null if there is none)
HikkaHeaderSlot? hikkaHeaderSlot(BuildContext context) => context.getInheritedWidgetOfExactType<_HeaderSlotScope>()?.slot;

/// The header "floats" with scrolling (like a floating bar): on scrolling down its shift equals the content shift and it
/// goes up, and on moving up it slides back by the same amount, anywhere on the page, and sticks to the top.
/// When the gesture ends, the header rolls to fully visible or fully hidden. [header] lies OVER [body]
/// and only shifts: the size and scroll position of the content do not change. The content leaves a top padding
/// `AppHeaderInset.of(context)` (see `HikkaPageFrame`, `HikkaPagedList`); until the content is scrolled past that padding,
/// the header cannot be hidden deeper than the scroll, so no empty space appears at its position.
/// Nested headers (calendar days in "Огляд") sit under the outer one and hide with it.
/// [resetOn] is a value whose change shows the header again.
class HikkaCollapsingHeader extends StatefulWidget {
  final Widget header;
  final Widget body;
  final Object? resetOn;

  const HikkaCollapsingHeader({super.key, required this.header, required this.body, this.resetOn});

  @override
  State<HikkaCollapsingHeader> createState() => _HikkaCollapsingHeaderState();
}

class _HikkaCollapsingHeaderState extends State<HikkaCollapsingHeader> with SingleTickerProviderStateMixin {
  final GlobalKey _headerKey = GlobalKey();

  /// Header visibility 0…1: the value is set manually by scrolling, and after the gesture it rolls by animation
  late final AnimationController _c = AnimationController(vsync: this, duration: AppAnim.medium, value: 1);
  late final Animation<double> _factor = _c;
  final HikkaHeaderSlot _slot = HikkaHeaderSlot();
  double _height = 0;

  @override
  void initState() {
    super.initState();
    _slot.addListener(_onSlot);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  void _onSlot() {
    if (!mounted) return;
    if (_slot.takeReset() && _c.value < 1) _c.animateTo(1, curve: AppAnim.easeOut);
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  void didUpdateWidget(HikkaCollapsingHeader old) {
    super.didUpdateWidget(old);
    if (old.resetOn != widget.resetOn && _c.value < 1) _c.animateTo(1, curve: AppAnim.easeOut);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  void dispose() {
    _slot.removeListener(_onSlot);
    _slot.dispose();
    _c.dispose();
    super.dispose();
  }

  void _measure() {
    if (!mounted) return;
    final h = _headerKey.currentContext?.size?.height;
    if (h != null && (h - _height).abs() > 0.5) setState(() => _height = h);
  }

  /// The smallest visibility at which the header still covers the padding above the content (until the content is scrolled past it)
  double _minFactor(ScrollMetrics m) => _height <= 0 ? 0 : (1 - m.pixels / _height).clamp(0.0, 1.0);

  bool _onScroll(ScrollNotification n) {
    // Only the page's main scroll: a nested list (e.g. of teams in settings) does not move the header
    if (n.depth != 0 || n.metrics.axis != Axis.vertical || _height <= 0) return false;
    final m = n.metrics;
    // Short content does not hide the header: otherwise there would be nothing to bring it back
    if (m.maxScrollExtent <= _height) return false;
    if (n is ScrollUpdateNotification) {
      final delta = n.scrollDelta ?? 0;
      if (delta == 0) return false;
      // We set the new value directly, so the current rolling animation (if any) stops
      _c.value = (_c.value - delta / _height).clamp(_minFactor(m), 1.0);
    } else if (n is ScrollEndNotification) {
      final f = _c.value;
      if (f > 0 && f < 1 && m.pixels > _height) {
        _c.animateTo(f >= 0.5 ? 1.0 : 0.0, curve: AppAnim.easeOut);
      }
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
        // Under the outer header: its visible part, and the hiding itself is a shift up by the header's height
        final base = outer == null ? 0.0 : outerInset * (outer.shown?.value.clamp(0.0, 1.0) ?? 1.0);
        return Transform.translate(
          offset: Offset(0, base - (1 - f) * _height),
          child: IgnorePointer(ignoring: f < 0.05, child: child),
        );
      },
      // The background is only painted and does not intercept touches outside the header's content
      child: CustomPaint(
        painter: _HeaderBg(bg),
        child: NotificationListener<SizeChangedLayoutNotification>(
          onNotification: (_) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
            return false;
          },
          // Column(min) gives the header unbounded height: otherwise its Column(max) would stretch across the whole screen and catch touches
          child: SizeChangedLayoutNotifier(child: Column(mainAxisSize: MainAxisSize.min, children: [KeyedSubtree(key: _headerKey, child: Padding(padding: const EdgeInsets.only(bottom: 8), child: _slot.widget == null ? widget.header : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [widget.header, _slot.widget!])))])),
        ),
      ),
    );
    // ClipRect: a hidden header must not peek out from under the edge (e.g. in the status bar zone)
    return ClipRect(
      child: Stack(
        children: [
          Positioned.fill(
            child: AppHeaderInset(
              inset: outerInset + _height,
              shown: _factor,
              child: _HeaderSlotScope(slot: _slot, child: NotificationListener<ScrollNotification>(onNotification: _onScroll, child: widget.body)),
            ),
          ),
          Positioned(top: 0, left: 0, right: 0, child: header),
        ],
      ),
    );
  }
}

/// Builds [builder] (and so starts its requests) only when the section's place nears the visible
/// part of the scroll. Until then there is an empty area of height [height]. Once mounted, the section stays.
/// For long pages: the lower shelves do not load until scrolled to.
class HikkaLazy extends StatefulWidget {
  final double height;

  /// How many pixels before the screen edge to start loading
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

/// A solid background of the overlay header, transparent to touches
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
