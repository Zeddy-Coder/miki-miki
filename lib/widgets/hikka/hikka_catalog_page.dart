import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../models/hikka_models.dart';
import '../../services/hikka_api.dart';
import '../../services/hikka_nav.dart';
import '../../services/hikka_pager.dart';
import '../../services/hikka_prefs.dart';
import '../../services/ui_theme_service.dart';
import '../../utils/platform_info.dart';
import '../app_animation_kit.dart';
import '../mobile_sheet.dart';
import 'hikka_cards.dart';
import 'hikka_common.dart';
import 'hikka_filter_sheet.dart';
import 'hikka_page_kit.dart';

/// Розділ «Каталог» в «Огляді»: пошук, фільтри з панеллю та нескінченна сітка карток.
class HikkaCatalogPage extends StatefulWidget {
  final double scale;
  final double bottomInset;
  final int refreshToken;

  const HikkaCatalogPage({super.key, required this.scale, this.bottomInset = 0, this.refreshToken = 0});

  @override
  State<HikkaCatalogPage> createState() => _HikkaCatalogPageState();
}

class _HikkaCatalogPageState extends State<HikkaCatalogPage> {
  late final HikkaPager<HikkaAnime> _pager;
  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode(debugLabel: 'catalog-search');
  final ScrollController _scroll = AppSmoothScrollController();
  HikkaSearchFilters _filters = const HikkaSearchFilters();
  Timer? _debounce;
  bool _sheetOpen = false;
  late bool _adult;
  late int _token;

  @override
  void initState() {
    super.initState();
    _adult = HikkaPrefs.instance.allowAdult;
    _token = widget.refreshToken;
    _pager = HikkaPager<HikkaAnime>(
      (page) => HikkaApi.instance.searchAnime(_filters, page: page, size: 30, allowAdult: HikkaPrefs.instance.allowAdult),
      keyOf: (a) => a.slug,
    );
    HikkaNav.instance.addListener(_takePending);
    HikkaNav.instance.addBackGuard(_backGuard);
    final pending = HikkaNav.instance.takePendingFilters();
    if (pending != null) {
      _filters = pending;
      _search.text = pending.query;
    }
    _pager.reload();
    _takeSearchFocus();
  }

  @override
  void didUpdateWidget(HikkaCatalogPage old) {
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
    HikkaNav.instance.removeListener(_takePending);
    HikkaNav.instance.removeBackGuard(_backGuard);
    _debounce?.cancel();
    _search.dispose();
    _searchFocus.dispose();
    _scroll.dispose();
    _pager.dispose();
    super.dispose();
  }

  /// Пошукова панель «Головної» просить курсор у полі пошуку: ставимо його, коли сторінка вже на екрані
  void _takeSearchFocus() {
    if (!HikkaNav.instance.takeFocusSearch()) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  /// Умови, передані з іншої сторінки (кнопка «Усі», жанр на сторінці аніме)
  void _takePending() {
    if (!mounted) return;
    final nav = HikkaNav.instance;
    // Користувач пішов на іншу вкладку чи сторінку — панель фільтрів не лишається відкритою позаду
    if (_sheetOpen && (nav.main != MainTab.discover || nav.tab != HikkaTab.anime || nav.top != null)) setState(() => _sheetOpen = false);
    if (nav.hasPendingFilters) {
      final f = nav.takePendingFilters();
      if (f != null) _apply(f);
    }
    if (nav.wantsSearchFocus) _takeSearchFocus();
  }

  /// «Назад» спершу закриває відкриту панель фільтрів
  bool _backGuard() {
    if (!_sheetOpen) return false;
    setState(() => _sheetOpen = false);
    return true;
  }

  void _apply(HikkaSearchFilters f) {
    setState(() {
      _filters = f;
      _sheetOpen = false;
    });
    if (_search.text != f.query) _search.text = f.query;
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _pager.reload();
  }

  void _onQuery(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () {
      if (!mounted || text.trim() == _filters.query.trim()) return;
      _apply(_filters.copyWith(query: text));
    });
  }

  String get _summary {
    final sort = HikkaSearchFilters.sorts.firstWhere((s) => s.key == _filters.sort, orElse: () => HikkaSearchFilters.sorts.first);
    final arrow = _filters.ascending ? '↑' : '↓';
    final total = _pager.total > 0 ? ' · ${HikkaText.count(_pager.total)} знайдено' : '';
    return '${sort.label} $arrow$total';
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.scale;
    final count = _filters.activeCount;
    final pad = HikkaLayout.sidePad(context, scale);

    final filterButton = Stack(
      clipBehavior: Clip.none,
      children: [
        HikkaIconButton(
          icon: Symbols.tune_rounded,
          tooltip: 'Фільтри',
          scale: scale,
          active: count > 0,
          onTap: () => setState(() => _sheetOpen = true),
        ),
        if (count > 0)
          Positioned(
            right: 2,
            top: 2,
            child: IgnorePointer(
              child: Container(
                constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: uiTheme.accentColor, borderRadius: BorderRadius.circular(9)),
                child: Text('$count', style: TextStyle(fontFamily: 'Arial', color: uiTheme.onAccent, fontSize: 10.5, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
      ],
    );

    return Stack(
      children: [
        HikkaCollapsingHeader(
          header: Column(
            children: [
            HikkaSearchBar(
              scale: scale,
              controller: _search,
              focusNode: _searchFocus,
              hint: 'Пошук аніме за назвою…',
              onChanged: _onQuery,
              trailing: filterButton,
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(pad, 0, pad, 6 * scale),
              child: Align(
                alignment: Alignment.centerLeft,
                child: InkWell(
                  onTap: () => setState(() => _sheetOpen = true),
                  borderRadius: uiTheme.borderRadius(6 * scale),
                  splashColor: Colors.transparent,
                  highlightColor: uiTheme.touchHighlight,
                  hoverColor: uiTheme.hoverOverlay,
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: AppPlatform.isMobile ? 8 : 3 * scale, horizontal: 2),
                    child: ListenableBuilder(
                      listenable: _pager,
                      builder: (context, _) => Text(
                        _summary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontFamily: 'Arial', color: uiTheme.textDarkMuted, fontSize: 12 * scale),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            ],
          ),
          body: HikkaPagedGrid<HikkaAnime>(
                pager: _pager,
                scale: scale,
                controller: _scroll,
                bottomInset: widget.bottomInset,
                emptyText: 'Нічого не знайдено. Змініть запит або фільтри',
                itemBuilder: (context, a) => HikkaAnimeCard(anime: a, scale: scale),
              ),
        ),
        MobileSheetFrame(
          open: _sheetOpen,
          onDismiss: () => setState(() => _sheetOpen = false),
          child: HikkaFilterSheet(
            scale: scale,
            initial: _filters,
            allowAdult: HikkaPrefs.instance.allowAdult,
            onApply: _apply,
            onClose: () => setState(() => _sheetOpen = false),
          ),
        ),
      ],
    );
  }
}
