import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../services/ui_theme_service.dart';
import '../../utils/platform_info.dart';
import '../app_animation_kit.dart';
import '../app_ui_kit.dart';
import 'hikka_common.dart';

/// Card sizes on horizontal shelves
class HikkaShelfMetrics {
  const HikkaShelfMetrics._();

  static double cardWidth(double scale) => AppPlatform.isMobile ? 128.0 : 148 * scale;

  /// Shelf height: a poster + the text under it
  static double height(BuildContext context, double scale) =>
      cardWidth(scale) / 0.7 + hikkaCardTextHeight(context, scale);
}

/// A horizontal shelf of cards with a heading. On desktop, scroll arrows on the right (the list can also be dragged with a mouse or Shift+wheel).
class HikkaShelf extends StatefulWidget {
  final double scale;
  final double pad;
  final String title;
  final String? subtitle;
  final VoidCallback? onMore;
  final String moreLabel;
  final int count;
  final IndexedWidgetBuilder itemBuilder;

  /// Its own card width and height (for horizontal cards); without them, ordinary poster cards
  final double? cardWidth;
  final double? cardHeight;

  /// Space between cards and the heading size before scaling (the title page uses its own)
  final double gap;
  final double titleSize;

  /// The new design: a grey, low "Усі ›" and a larger grey line under the heading (the wide title page keeps the old look)
  final bool calm;

  const HikkaShelf({
    super.key,
    required this.scale,
    required this.pad,
    required this.title,
    required this.count,
    required this.itemBuilder,
    this.subtitle,
    this.onMore,
    this.moreLabel = 'Усі',
    this.cardWidth,
    this.cardHeight,
    this.gap = 10,
    this.titleSize = 15,
    this.calm = true,
  });

  @override
  State<HikkaShelf> createState() => _HikkaShelfState();
}

class _HikkaShelfState extends State<HikkaShelf> {
  final ScrollController _controller = AppSmoothScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _page(int dir) {
    if (!_controller.hasClients) return;
    final p = _controller.position;
    final target = (p.pixels + dir * p.viewportDimension * 0.85).clamp(0.0, p.maxScrollExtent);
    _controller.animateTo(target, duration: AppAnim.slow, curve: AppAnim.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.scale;
    final showArrows = !AppPlatform.isMobile && widget.count > 4;
    return Padding(
      padding: EdgeInsets.only(bottom: (widget.calm ? 20 : 22) * scale),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: widget.pad),
            child: AppSectionHeader(
              scale: scale,
              title: widget.title,
              subtitle: widget.subtitle,
              titleSize: widget.titleSize,
              calm: widget.calm,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showArrows) ...[
                    HikkaIconButton(icon: Symbols.chevron_left_rounded, tooltip: 'Назад', scale: scale * 0.8, onTap: () => _page(-1)),
                    HikkaIconButton(icon: Symbols.chevron_right_rounded, tooltip: 'Далі', scale: scale * 0.8, onTap: () => _page(1)),
                  ],
                  if (widget.onMore != null) HikkaLinkButton(label: widget.moreLabel, scale: scale, onTap: widget.onMore!, calm: widget.calm),
                ],
              ),
            ),
          ),
          SizedBox(height: 10 * scale),
          SizedBox(
            height: widget.cardHeight ?? HikkaShelfMetrics.height(context, scale),
            child: ListView.separated(
              controller: _controller,
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: widget.pad),
              itemCount: widget.count,
              separatorBuilder: (_, __) => SizedBox(width: widget.gap * scale),
              itemBuilder: (context, i) => SizedBox(width: widget.cardWidth ?? HikkaShelfMetrics.cardWidth(scale), child: widget.itemBuilder(context, i)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shelf placeholder: gray rectangles in place of cards
class HikkaShelfSkeleton extends StatelessWidget {
  final double scale;
  final double pad;
  final double? cardWidth;
  final double? cardHeight;

  const HikkaShelfSkeleton({super.key, required this.scale, required this.pad, this.cardWidth, this.cardHeight});

  @override
  Widget build(BuildContext context) {
    if (cardWidth != null && cardHeight != null) {
      // Horizontal cards: simple rectangles
      return SizedBox(
        height: cardHeight,
        child: ListView.separated(
          physics: const NeverScrollableScrollPhysics(),
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(horizontal: pad),
          itemCount: 4,
          separatorBuilder: (_, __) => SizedBox(width: 10 * scale),
          itemBuilder: (context, i) => Container(
            width: cardWidth,
            decoration: BoxDecoration(color: uiTheme.bgElevated.withValues(alpha: 0.6), borderRadius: uiTheme.borderRadius(14 * scale)),
          ),
        ),
      );
    }
    final w = HikkaShelfMetrics.cardWidth(scale);
    Widget bar(double width, double height) => Container(
          height: height,
          width: width,
          decoration: BoxDecoration(color: uiTheme.bgElevated, borderRadius: uiTheme.borderRadius(4)),
        );
    return SizedBox(
      height: HikkaShelfMetrics.height(context, scale),
      child: ListView.separated(
        physics: const NeverScrollableScrollPhysics(),
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: pad),
        itemCount: 8,
        separatorBuilder: (_, __) => SizedBox(width: 10 * scale),
        itemBuilder: (context, i) => SizedBox(
          width: w,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 0.7,
                child: DecoratedBox(decoration: BoxDecoration(color: uiTheme.bgElevated, borderRadius: uiTheme.borderRadius(12 * scale))),
              ),
              SizedBox(height: 9 * scale),
              bar(w * 0.85, 9 * scale),
              SizedBox(height: 6 * scale),
              bar(w * 0.5, 8 * scale),
            ],
          ),
        ),
      ),
    );
  }
}

/// A shelf that loads its list itself: placeholder → cards; an empty result hides the whole shelf,
/// an error is shown under the heading with a "Повторити" button.
class HikkaShelfAsync<T> extends StatelessWidget {
  final double scale;
  final double pad;
  final String title;
  final String? subtitle;
  final Future<List<T>> Function() load;
  final Widget Function(BuildContext context, T item) itemBuilder;
  final VoidCallback? onMore;
  final String moreLabel;
  final double? cardWidth;
  final double? cardHeight;
  final double gap;
  final double titleSize;
  final bool calm;

  /// Another value means the shelf loads anew
  final Object? token;

  const HikkaShelfAsync({
    super.key,
    required this.scale,
    required this.pad,
    required this.title,
    required this.load,
    required this.itemBuilder,
    this.subtitle,
    this.onMore,
    this.moreLabel = 'Усі',
    this.token,
    this.cardWidth,
    this.cardHeight,
    this.gap = 10,
    this.titleSize = 15,
    this.calm = true,
  });

  @override
  Widget build(BuildContext context) {
    return HikkaAsync<List<T>>(
      key: ValueKey('shelf-$title-$token'),
      scale: scale,
      compactError: true,
      load: load,
      stateFrame: (context, child) => Padding(
        padding: EdgeInsets.only(bottom: (calm ? 20 : 22) * scale),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: pad),
              child: AppSectionHeader(scale: scale, title: title, subtitle: subtitle, titleSize: titleSize, calm: calm),
            ),
            SizedBox(height: 10 * scale),
            child,
          ],
        ),
      ),
      loading: (context) => HikkaShelfSkeleton(scale: scale, pad: pad, cardWidth: cardWidth, cardHeight: cardHeight),
      builder: (context, list) {
        if (list.isEmpty) return const SizedBox.shrink();
        return HikkaShelf(
          scale: scale,
          pad: pad,
          title: title,
          subtitle: subtitle,
          onMore: onMore,
          moreLabel: moreLabel,
          cardWidth: cardWidth,
          cardHeight: cardHeight,
          gap: gap,
          titleSize: titleSize,
          calm: calm,
          count: list.length,
          itemBuilder: (context, i) => itemBuilder(context, list[i]),
        );
      },
    );
  }
}
