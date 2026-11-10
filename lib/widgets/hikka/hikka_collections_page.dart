import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../models/hikka_models.dart';
import '../../services/hikka_api.dart';
import '../../services/hikka_pager.dart';
import '../../services/hikka_prefs.dart';
import '../app_animation_kit.dart';
import 'hikka_common.dart';
import 'hikka_community_cards.dart';
import 'hikka_paged_list.dart';

/// Розділ «Колекції»: добірки аніме від користувачів Hikka; за замовчуванням — найпопулярніші, можна — найновіші.
class HikkaCollectionsPage extends StatefulWidget {
  final double scale;
  final double bottomInset;
  final int refreshToken;

  const HikkaCollectionsPage({super.key, required this.scale, this.bottomInset = 0, this.refreshToken = 0});

  @override
  State<HikkaCollectionsPage> createState() => _HikkaCollectionsPageState();
}

class _HikkaCollectionsPageState extends State<HikkaCollectionsPage> {
  late final HikkaPager<HikkaCollection> _pager;
  final ScrollController _scroll = AppSmoothScrollController();
  String _sort = 'popular';
  late bool _adult;
  late int _token;

  @override
  void initState() {
    super.initState();
    _adult = HikkaPrefs.instance.allowAdult;
    _token = widget.refreshToken;
    _pager = HikkaPager<HikkaCollection>(
      (page) => HikkaApi.instance.collections(sort: _sort, page: page, size: 20, allowAdult: HikkaPrefs.instance.allowAdult),
      keyOf: (c) => c.reference,
    );
    _pager.reload();
  }

  @override
  void didUpdateWidget(HikkaCollectionsPage old) {
    super.didUpdateWidget(old);
    final adult = HikkaPrefs.instance.allowAdult;
    if (adult != _adult || widget.refreshToken != _token) {
      _adult = adult;
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

  void _setSort(String sort) {
    if (sort == _sort) return;
    setState(() => _sort = sort);
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _pager.reload();
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.scale;
    return HikkaPagedList<HikkaCollection>(
      pager: _pager,
      scale: scale,
      controller: _scroll,
      bottomInset: widget.bottomInset,
      emptyIcon: Symbols.collections_bookmark_rounded,
      emptyText: 'Колекцій не знайдено',
      header: Padding(
        padding: EdgeInsets.only(top: 4 * scale, bottom: 8 * scale),
        child: HikkaChipRow(
          scale: scale,
          children: [
            HikkaChip(label: 'Популярні', icon: Symbols.local_fire_department_rounded, scale: scale, selected: _sort == 'popular', onTap: () => _setSort('popular')),
            HikkaChip(label: 'Нові', icon: Symbols.schedule_rounded, scale: scale, selected: _sort == 'new', onTap: () => _setSort('new')),
          ],
        ),
      ),
      itemBuilder: (context, c) => HikkaCollectionCard(collection: c, scale: scale),
    );
  }
}
