import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../services/hikka_pager.dart';
import '../../utils/platform_info.dart';
import '../app_animation_kit.dart';
import '../app_ui_kit.dart';
import 'hikka_common.dart';

/// A scrollable list of wide cards (collections, articles) with incremental loading: listens to [pager] and loads
/// more pages when nearing the end. On wide windows the cards lay out in two columns.
class HikkaPagedList<T> extends StatefulWidget {
  final HikkaPager<T> pager;
  final double scale;
  final Widget Function(BuildContext context, T item) itemBuilder;
  final String emptyText;
  final IconData emptyIcon;
  final ScrollController? controller;

  /// Extra bottom padding (collapsed player)
  final double bottomInset;

  /// A block above the list that scrolls together with it
  final Widget? header;

  /// Maximum width of one card; wider windows split the row into columns
  final double maxCardWidth;

  /// Rows that carry their own padding (the lists' rows): no gaps and no side padding of the list
  final bool flush;

  /// Its own empty state instead of the icon with [emptyText]
  final Widget? empty;

  const HikkaPagedList({
    super.key,
    required this.pager,
    required this.scale,
    required this.itemBuilder,
    required this.emptyText,
    this.emptyIcon = Symbols.search_off_rounded,
    this.controller,
    this.bottomInset = 0,
    this.header,
    this.maxCardWidth = 560,
    this.flush = false,
    this.empty,
  });

  @override
  State<HikkaPagedList<T>> createState() => _HikkaPagedListState<T>();
}

class _HikkaPagedListState<T> extends State<HikkaPagedList<T>> {
  ScrollController? _own;
  ScrollController get _controller => widget.controller ?? (_own ??= AppSmoothScrollController());

  /// The cards made by this widget's [HikkaPagedList.itemBuilder], by item: a new page or the loading footer hands the
  /// cards on screen back as they are instead of rebuilding them (as in `HikkaPagedGrid`)
  final Map<Object?, Widget> _cards = HashMap<Object?, Widget>.identity();
  HikkaPagedList<T>? _cardsFor;

  /// The list sliver of the last build and what it was made of
  Widget? _sliver;
  Object? _sliverKey;

  Widget _card(BuildContext context, T item) {
    if (!identical(_cardsFor, widget)) {
      _cards.clear();
      _cardsFor = widget;
    }
    return _cards[item] ??= widget.itemBuilder(context, item);
  }

  @override
  void initState() {
    super.initState();
    widget.pager.addListener(_onPager);
    _controller.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(HikkaPagedList<T> old) {
    super.didUpdateWidget(old);
    if (old.pager != widget.pager) {
      old.pager.removeListener(_onPager);
      widget.pager.addListener(_onPager);
    }
    if (old.controller != widget.controller) {
      (old.controller ?? _own)?.removeListener(_onScroll);
      _controller.addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    widget.pager.removeListener(_onPager);
    _controller.removeListener(_onScroll);
    _own?.dispose();
    super.dispose();
  }

  void _onPager() {
    if (!mounted) return;
    if (widget.pager.items.isEmpty) _cards.clear(); // reloaded: the old cards are not coming back
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) => _fillViewport());
  }

  void _onScroll() {
    final c = _controller;
    if (c.hasClients && c.position.extentAfter < 900) widget.pager.loadMore();
  }

  void _fillViewport() {
    if (!mounted) return;
    final c = _controller;
    final p = widget.pager;
    if (c.hasClients && c.position.maxScrollExtent <= 0 && p.hasMore && !p.loading && p.error == null) p.loadMore();
  }

  /// The rows of cards; made again only when the items, the widget or the layout changed (the loading footer coming
  /// and going leaves it, and so the cards, as they are)
  Widget _rowsSliver(List<T> items, int columns, double side, double gap) {
    final key = (widget, items, columns, side, gap);
    if (_sliver != null && _sliverKey == key) return _sliver!;
    _sliverKey = key;
    return _sliver = SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: side),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, row) {
            final from = row * columns;
            final to = (from + columns).clamp(0, items.length);
            return Padding(
              padding: EdgeInsets.only(bottom: gap),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (int i = from; i < from + columns; i++) ...[
                    if (i > from) SizedBox(width: gap),
                    Expanded(child: i < to ? _card(context, items[i]) : const SizedBox.shrink()),
                  ],
                ],
              ),
            );
          },
          childCount: (items.length / columns).ceil(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.scale;
    final pager = widget.pager;
    final pad = widget.flush ? 0.0 : HikkaLayout.sidePad(context, scale);
    final gap = widget.flush ? 0.0 : (HikkaLayout.compact(context) ? 12.0 : 14 * scale);

    final Widget footer;
    if (pager.error != null && pager.items.isNotEmpty) {
      footer = HikkaErrorView(scale: scale, error: pager.error!, onRetry: pager.retry, compact: true);
    } else if (pager.loading && pager.items.isNotEmpty) {
      footer = HikkaLoading(scale: scale, height: 72);
    } else {
      footer = const SizedBox(height: 8);
    }

    Widget body = const SizedBox.shrink();
    if (pager.error != null && pager.items.isEmpty) {
      body = HikkaErrorView(scale: scale, error: pager.error!, onRetry: pager.retry);
    } else if (pager.isInitialLoading || pager.isFresh) {
      // A placeholder instead of a spinner: the tab looks "like a page" at once
      body = HikkaListSkeleton(scale: scale, maxCardWidth: widget.maxCardWidth);
    } else if (pager.isEmpty) {
      body = widget.empty ?? SizedBox(height: 260, child: AppEmptyState(scale: scale, icon: widget.emptyIcon, text: widget.emptyText));
    }

    // The columns come from the width alone, outside the scroll view. A SliverLayoutBuilder here ran on every scroll
    // frame (its constraints carry the scroll offset), and its new delegate rebuilt every visible card each frame
    // (~700 widgets per frame in the collections list)
    return LayoutBuilder(
      builder: (context, box) {
        final crossAxisExtent = box.maxWidth;
        // One column on a phone and in a narrow window, two or more when cards are not stretched unnecessarily
        final width = (crossAxisExtent - pad * 2).clamp(0.0, HikkaLayout.maxContentWidth);
        final maxW = widget.maxCardWidth * (AppPlatform.isMobile ? 1.0 : scale);
        final columns = ((width + gap) / (maxW + gap)).floor().clamp(1, 3);
        final side = ((crossAxisExtent - width) / 2).clamp(pad, double.infinity);
        final items = pager.items;
        return AppScrollbar(
          scale: scale,
          controller: _controller,
          child: CustomScrollView(
            controller: _controller,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: SizedBox(height: AppHeaderInset.of(context))), // room under the overlay header
              if (widget.header != null) SliverToBoxAdapter(child: widget.header),
              if (items.isEmpty)
                SliverToBoxAdapter(child: body)
              else
                _rowsSliver(items, columns, side, gap),
              SliverToBoxAdapter(child: footer),
              SliverToBoxAdapter(child: SizedBox(height: 24 * scale + widget.bottomInset)),
            ],
          ),
        );
      },
    );
  }
}
