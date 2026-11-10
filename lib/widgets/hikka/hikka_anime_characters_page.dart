import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../models/hikka_models.dart';
import '../../services/hikka_api.dart';
import '../../services/hikka_nav.dart';
import '../../services/hikka_pager.dart';
import '../app_animation_kit.dart';
import 'hikka_cards.dart';
import 'hikka_common.dart';

/// Усі персонажі аніме: сітка портретів із позначкою «Головний» / «Другорядний»
class HikkaAnimeCharactersPage extends StatefulWidget {
  final HikkaRoute route;
  final double scale;
  final double bottomInset;

  const HikkaAnimeCharactersPage({super.key, required this.route, required this.scale, this.bottomInset = 0});

  @override
  State<HikkaAnimeCharactersPage> createState() => _HikkaAnimeCharactersPageState();
}

class _HikkaAnimeCharactersPageState extends State<HikkaAnimeCharactersPage> {
  late final ScrollController _scroll = AppSmoothScrollController(initialScrollOffset: widget.route.scroll);
  late final HikkaPager<HikkaCharacterRole> _pager;

  @override
  void initState() {
    super.initState();
    // Список лишається в маршруті: повернувшись «Назад» від персонажа, людина бачить те саме місце
    final cached = widget.route.memo['pager'];
    if (cached is HikkaPager<HikkaCharacterRole>) {
      _pager = cached;
    } else {
      _pager = HikkaPager<HikkaCharacterRole>(
        (page) => HikkaApi.instance.animeCharacters(widget.route.slug, page: page, size: 30),
        keyOf: (r) => r.character.slug,
      );
      widget.route.memo['pager'] = _pager;
    }
    if (_pager.items.isEmpty && !_pager.loading && _pager.error == null) _pager.reload();
    _scroll.addListener(_saveScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_saveScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _saveScroll() {
    if (_scroll.hasClients) widget.route.scroll = _scroll.offset;
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.scale;
    return HikkaPagedGrid<HikkaCharacterRole>(
      pager: _pager,
      scale: scale,
      controller: _scroll,
      bottomInset: widget.bottomInset,
      maxTileWidth: 150,
      emptyIcon: Symbols.person_search_rounded,
      emptyText: 'Для цього аніме ще немає персонажів',
      itemBuilder: (context, r) => HikkaCharacterCard(
        character: r.character,
        scale: scale,
        caption: r.main ? 'Головний' : 'Другорядний',
      ),
    );
  }
}
