import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../services/hikka_pager.dart';
import '../../utils/platform_info.dart';
import '../app_animation_kit.dart';
import '../app_ui_kit.dart';
import 'hikka_common.dart';

/// Прокручуваний список широких карток (колекції, статті) з підвантаженням: слухає [pager] і докантажує
/// сторінки при наближенні до кінця. На широких вікнах картки лягають у два стовпці.
class HikkaPagedList<T> extends StatefulWidget {
  final HikkaPager<T> pager;
  final double scale;
  final Widget Function(BuildContext context, T item) itemBuilder;
  final String emptyText;
  final IconData emptyIcon;
  final ScrollController? controller;

  /// Додатковий відступ знизу (згорнутий плеєр)
  final double bottomInset;

  /// Блок над списком, що прокручується разом з ним
  final Widget? header;

  /// Найбільша ширина однієї картки; ширші вікна ділять рядок на стовпці
  final double maxCardWidth;

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
  });

  @override
  State<HikkaPagedList<T>> createState() => _HikkaPagedListState<T>();
}

class _HikkaPagedListState<T> extends State<HikkaPagedList<T>> {
  ScrollController? _own;
  ScrollController get _controller => widget.controller ?? (_own ??= AppSmoothScrollController());

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

  @override
  Widget build(BuildContext context) {
    final scale = widget.scale;
    final pager = widget.pager;
    final pad = HikkaLayout.sidePad(context, scale);
    final gap = HikkaLayout.compact(context) ? 12.0 : 14 * scale;

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
      // Заглушка замість кола: вкладка одразу виглядає «як сторінка»
      body = HikkaListSkeleton(scale: scale, maxCardWidth: widget.maxCardWidth);
    } else if (pager.isEmpty) {
      body = SizedBox(height: 260, child: AppEmptyState(scale: scale, icon: widget.emptyIcon, text: widget.emptyText));
    }

    return AppScrollbar(
      scale: scale,
      controller: _controller,
      child: CustomScrollView(
        controller: _controller,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: SizedBox(height: AppHeaderInset.of(context))), // місце під шапкою-накладкою
          if (widget.header != null) SliverToBoxAdapter(child: widget.header),
          if (pager.items.isEmpty)
            SliverToBoxAdapter(child: body)
          else
            SliverLayoutBuilder(
              builder: (context, constraints) {
                // Один стовпець на телефоні й у вузькому вікні, два й більше — коли картки не розтягуються без потреби
                final width = (constraints.crossAxisExtent - pad * 2).clamp(0.0, HikkaLayout.maxContentWidth);
                final maxW = widget.maxCardWidth * (AppPlatform.isMobile ? 1.0 : scale);
                final columns = ((width + gap) / (maxW + gap)).floor().clamp(1, 3);
                final side = ((constraints.crossAxisExtent - width) / 2).clamp(pad, double.infinity);
                final items = pager.items;
                return SliverPadding(
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
                                Expanded(child: i < to ? widget.itemBuilder(context, items[i]) : const SizedBox.shrink()),
                              ],
                            ],
                          ),
                        );
                      },
                      childCount: (items.length / columns).ceil(),
                    ),
                  ),
                );
              },
            ),
          SliverToBoxAdapter(child: footer),
          SliverToBoxAdapter(child: SizedBox(height: 24 * scale + widget.bottomInset)),
        ],
      ),
    );
  }
}
