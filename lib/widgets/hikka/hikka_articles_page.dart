import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../models/hikka_models.dart';
import '../../services/hikka_api.dart';
import '../../services/hikka_pager.dart';
import '../../services/ui_theme_service.dart';
import '../app_animation_kit.dart';
import 'hikka_common.dart';
import 'hikka_community_cards.dart';
import 'hikka_paged_list.dart';

/// Розділ «Статті»: новини, огляди й авторські тексти спільноти Hikka. Фільтр за категорією та порядок
/// (найновіші чи найвище оцінені).
class HikkaArticlesPage extends StatefulWidget {
  final double scale;
  final double bottomInset;
  final int refreshToken;

  const HikkaArticlesPage({super.key, required this.scale, this.bottomInset = 0, this.refreshToken = 0});

  @override
  State<HikkaArticlesPage> createState() => _HikkaArticlesPageState();
}

class _HikkaArticlesPageState extends State<HikkaArticlesPage> {
  /// Категорії, які можна вибрати (системні повідомлення сайту в стрічку не потрапляють)
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
    return HikkaPagedList<HikkaArticle>(
      pager: _pager,
      scale: scale,
      controller: _scroll,
      bottomInset: widget.bottomInset,
      emptyIcon: Symbols.article_rounded,
      emptyText: 'Статей не знайдено',
      header: Padding(
        padding: EdgeInsets.only(top: 4 * scale, bottom: 8 * scale),
        child: HikkaChipRow(
          scale: scale,
          children: [
            for (final (key, label) in _categories)
              HikkaChip(label: label, scale: scale, selected: _category == key, onTap: () => _apply(category: key, resetCategory: true)),
            SizedBox(height: 22 * scale, child: VerticalDivider(width: 8 * scale, thickness: 1, color: uiTheme.borderSubtle)),
            HikkaChip(label: 'Нові', icon: Symbols.schedule_rounded, scale: scale, selected: _sort == 'new', onTap: () => _apply(sort: 'new')),
            HikkaChip(label: 'Найкращі', icon: Symbols.star_rounded, scale: scale, selected: _sort == 'top', onTap: () => _apply(sort: 'top')),
          ],
        ),
      ),
      itemBuilder: (context, a) => HikkaArticleCard(article: a, scale: scale),
    );
  }
}
