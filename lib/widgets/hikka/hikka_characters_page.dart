import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../models/hikka_models.dart';
import '../../services/hikka_api.dart';
import '../../services/hikka_pager.dart';
import '../../services/ui_theme_service.dart';
import '../app_animation_kit.dart';
import 'hikka_cards.dart';
import 'hikka_common.dart';
import 'hikka_page_kit.dart';

/// The "Персонажі" tab: search by name; without a query, the most popular.
class HikkaCharactersPage extends StatefulWidget {
  final double scale;
  final double bottomInset;
  final int refreshToken;

  /// The query of "Огляд"'s search field (the field is in its header): then the section has no field of its own
  final TextEditingController? search;

  const HikkaCharactersPage({super.key, required this.scale, this.bottomInset = 0, this.refreshToken = 0, this.search});

  @override
  State<HikkaCharactersPage> createState() => _HikkaCharactersPageState();
}

class _HikkaCharactersPageState extends State<HikkaCharactersPage> {
  late final HikkaPager<HikkaCharacter> _pager;
  TextEditingController? _own;
  TextEditingController get _search => widget.search ?? (_own ??= TextEditingController());
  String _text = '';
  final ScrollController _scroll = AppSmoothScrollController();
  Timer? _debounce;
  String _query = '';
  late int _token;

  @override
  void initState() {
    super.initState();
    _token = widget.refreshToken;
    _pager = HikkaPager<HikkaCharacter>(
      (page) => HikkaApi.instance.searchCharacters(_query, page: page, size: 30),
      keyOf: (c) => c.slug,
    );
    _text = _search.text;
    if (widget.search != null) {
      widget.search!.addListener(_onShared);
      _onQuery(_text);
    }
    _pager.reload();
  }

  /// The shared field changed (typing, or "Огляд" cleared it)
  void _onShared() {
    final t = _search.text;
    if (t == _text) return;
    _text = t;
    _onQuery(t);
  }

  @override
  void didUpdateWidget(HikkaCharactersPage old) {
    super.didUpdateWidget(old);
    if (widget.refreshToken != _token) {
      _token = widget.refreshToken;
      _pager.reload();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.search?.removeListener(_onShared);
    _own?.dispose();
    _scroll.dispose();
    _pager.dispose();
    super.dispose();
  }

  void _onQuery(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () {
      final q = text.trim();
      // The API searches from two characters; a shorter query equals an empty one
      final effective = q.length >= 2 ? q : '';
      if (!mounted || effective == _query) return;
      _query = effective;
      if (_scroll.hasClients) _scroll.jumpTo(0);
      _pager.reload();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.scale;
    final grid = HikkaPagedGrid<HikkaCharacter>(
        pager: _pager,
        scale: scale,
        controller: _scroll,
        bottomInset: widget.bottomInset,
        maxTileWidth: 150,
        subtitle: false,
        // A grey line over the grid: what it shows ("Найпопулярніші" until a query is typed)
        header: ListenableBuilder(
          listenable: _pager,
          builder: (context, _) => Padding(
            padding: EdgeInsets.fromLTRB(HikkaLayout.sidePad(context, scale), 10 * scale, HikkaLayout.sidePad(context, scale), 10 * scale),
            child: Text(
              _query.isEmpty ? 'Найпопулярніші' : (_pager.total > 0 ? 'Знайдено ${HikkaText.count(_pager.total)}' : 'Пошук «$_query»'),
              style: hikkaStyle(13 * scale, color: uiTheme.textMuted),
            ),
          ),
        ),
        emptyIcon: Symbols.person_search_rounded,
        emptyText: 'Персонажів не знайдено',
        itemBuilder: (context, c) => HikkaCharacterCard(character: c, scale: scale),
      );
    if (widget.search != null) return grid;
    // Search is a nested header: pinned at the top, hides with scrolling (as in the catalog)
    return HikkaCollapsingHeader(
      header: HikkaSearchBar(scale: scale, controller: _search, hint: 'Пошук персонажа за іменем…', onChanged: _onQuery),
      body: grid,
    );
  }
}
