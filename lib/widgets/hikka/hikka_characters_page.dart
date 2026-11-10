import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../models/hikka_models.dart';
import '../../services/hikka_api.dart';
import '../../services/hikka_pager.dart';
import '../app_animation_kit.dart';
import 'hikka_cards.dart';
import 'hikka_common.dart';

/// Вкладка «Персонажі»: пошук за іменем; без запиту — найпопулярніші.
class HikkaCharactersPage extends StatefulWidget {
  final double scale;
  final double bottomInset;
  final int refreshToken;

  const HikkaCharactersPage({super.key, required this.scale, this.bottomInset = 0, this.refreshToken = 0});

  @override
  State<HikkaCharactersPage> createState() => _HikkaCharactersPageState();
}

class _HikkaCharactersPageState extends State<HikkaCharactersPage> {
  late final HikkaPager<HikkaCharacter> _pager;
  final TextEditingController _search = TextEditingController();
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
    _pager.reload();
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
    _search.dispose();
    _scroll.dispose();
    _pager.dispose();
    super.dispose();
  }

  void _onQuery(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () {
      final q = text.trim();
      // API шукає від двох символів; коротший запит дорівнює порожньому
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
    return Column(
      children: [
        HikkaSearchBar(scale: scale, controller: _search, hint: 'Пошук персонажа за іменем…', onChanged: _onQuery),
        Expanded(
          child: HikkaPagedGrid<HikkaCharacter>(
            pager: _pager,
            scale: scale,
            controller: _scroll,
            bottomInset: widget.bottomInset,
            maxTileWidth: 150,
            header: SizedBox(height: 8 * scale),
            emptyIcon: Symbols.person_search_rounded,
            emptyText: 'Персонажів не знайдено',
            itemBuilder: (context, c) => HikkaCharacterCard(character: c, scale: scale),
          ),
        ),
      ],
    );
  }
}
