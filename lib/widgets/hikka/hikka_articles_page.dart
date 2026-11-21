import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../models/hikka_models.dart';
import '../../services/hikka_api.dart';
import '../../services/hikka_pager.dart';
import '../app_animation_kit.dart';
import '../design_kit.dart' show AppPlate;
import 'hikka_common.dart';
import 'hikka_community_cards.dart';
import 'hikka_page_kit.dart';
import 'hikka_paged_list.dart';

/// The "Статті" section: news, reviews and original texts of the Hikka community. A category filter and order
/// (newest or top rated).
class HikkaArticlesPage extends StatefulWidget {
  final double scale;
  final double bottomInset;
  final int refreshToken;

  const HikkaArticlesPage({super.key, required this.scale, this.bottomInset = 0, this.refreshToken = 0});

  @override
  State<HikkaArticlesPage> createState() => _HikkaArticlesPageState();
}

class _HikkaArticlesPageState extends State<HikkaArticlesPage> {
  /// Categories that can be chosen (the site's system messages do not get into the feed)
  static const List<(String? key, String label)> _categories = [
    (null, 'Усі'),
    ('news', 'Новини'),
    ('reviews', 'Огляди'),
    ('original', 'Авторські'),
  ];

  late final HikkaPager<HikkaArticle> _pager;
  final ScrollController _scroll = AppSmoothScrollController();
  String? _category;
  String _sort = 'new';
  late int _token;

  @override
  void initState() {
    super.initState();
    _token = widget.refreshToken;
    _pager = HikkaPager<HikkaArticle>(
      (page) => HikkaApi.instance.articles(category: _category, sort: _sort, page: page, size: 20),
      keyOf: (a) => a.slug,
    );
    _pager.reload();
  }

  @override
  void didUpdateWidget(HikkaArticlesPage old) {
    super.didUpdateWidget(old);
    if (widget.refreshToken != _token) {
      _token = widget.refreshToken;
      _pager.reload();
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    _pager.dispose();
    super.dispose();
  }

  void _apply({String? category, String? sort, bool resetCategory = false}) {
    final nextCategory = resetCategory ? category : (category ?? _category);
    final nextSort = sort ?? _sort;
    if (nextCategory == _category && nextSort == _sort) return;
    setState(() {
      _category = nextCategory;
      _sort = nextSort;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _pager.reload();
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.scale;
    final pad = HikkaLayout.sidePad(context, scale);
    return HikkaPagedList<HikkaArticle>(
      pager: _pager,
      scale: scale,
      controller: _scroll,
      bottomInset: widget.bottomInset,
      flush: true,
      emptyIcon: Symbols.article_rounded,
      emptyText: 'Статей не знайдено',
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Categories as round plates (as the filters), the order as a quiet line under them
          Padding(
            padding: EdgeInsets.fromLTRB(pad, 6 * scale, pad, 0),
            child: Wrap(
              spacing: 8 * scale,
              runSpacing: 8 * scale,
              children: [
                for (final (key, label) in _categories)
                  AppPlate(
                    key: ValueKey('articles-category-${key ?? 'all'}'),
                    scale: scale,
                    label: label,
                    height: 34,
                    radius: 17,
                    selected: _category == key,
                    onTap: () => _apply(category: key, resetCategory: true),
                  ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.only(bottom: 2 * scale),
            child: HikkaSortLine<String>(
              key: const ValueKey('articles-sort'),
              scale: scale,
              pad: pad,
              top: 6,
              value: _sort,
              options: const [('new', 'Спершу нові'), ('top', 'Спершу найкращі')],
              onChanged: (v) => _apply(sort: v),
            ),
          ),
        ],
      ),
      itemBuilder: (context, a) => HikkaArticleRow(article: a, scale: scale, pad: pad),
    );
  }
}
