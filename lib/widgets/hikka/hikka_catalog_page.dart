import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/hikka_models.dart';
import '../../services/hikka_api.dart';
import '../../services/hikka_nav.dart';
import '../../services/hikka_pager.dart';
import '../../services/hikka_prefs.dart';
import '../../services/ui_theme_service.dart';
import '../../utils/platform_info.dart';
import '../app_animation_kit.dart';
import '../line_icons.dart';
import '../mobile_sheet.dart';
import 'hikka_cards.dart';
import 'hikka_common.dart';
import 'hikka_filter_sheet.dart';
import 'hikka_page_kit.dart';

/// The "Каталог" section in "Огляд": search, filters with a panel and an infinite grid of cards.
class HikkaCatalogPage extends StatefulWidget {
  final double scale;
  final double bottomInset;
  final int refreshToken;

  /// The query and focus of "Огляд"'s search field (the field is in its header): then the section has no field of its own
  final TextEditingController? search;
  final FocusNode? searchFocus;

  const HikkaCatalogPage({super.key, required this.scale, this.bottomInset = 0, this.refreshToken = 0, this.search, this.searchFocus});

  @override
  State<HikkaCatalogPage> createState() => _HikkaCatalogPageState();
}

class _HikkaCatalogPageState extends State<HikkaCatalogPage> {
  late final HikkaPager<HikkaAnime> _pager;
  TextEditingController? _ownSearch;
  FocusNode? _ownFocus;
  TextEditingController get _search => widget.search ?? (_ownSearch ??= TextEditingController());
  FocusNode get _searchFocus => widget.searchFocus ?? (_ownFocus ??= FocusNode(debugLabel: 'catalog-search'));
  String _text = '';
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
    } else if (_search.text.trim().isNotEmpty) {
      // The shared field already has a query (typed in another section)
      _filters = _filters.copyWith(query: _search.text);
    }
    _text = _search.text;
    widget.search?.addListener(_onShared);
    _pager.reload();
    _takeSearchFocus();
  }

  /// The shared field changed (typing in "Огляд"'s header)
  void _onShared() {
    final t = _search.text;
    if (t == _text) return;
    _text = t;
    _onQuery(t);
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
    widget.search?.removeListener(_onShared);
    _ownSearch?.dispose();
    _ownFocus?.dispose();
    _scroll.dispose();
    _pager.dispose();
    super.dispose();
  }

  /// The "Головна" search bar asks for the cursor in the search field: we place it once the page is on screen
  void _takeSearchFocus() {
    if (!HikkaNav.instance.takeFocusSearch()) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  /// Conditions passed from another page (the "Усі" button, a genre on the anime page)
  void _takePending() {
    if (!mounted) return;
    final nav = HikkaNav.instance;
    // The user went to another tab or page: the filter panel does not stay open behind
    if (_sheetOpen && (nav.main != MainTab.discover || nav.tab != HikkaTab.anime || nav.top != null)) setState(() => _sheetOpen = false);
    if (nav.hasPendingFilters) {
      final f = nav.takePendingFilters();
      if (f != null) _apply(f);
    }
    if (nav.wantsSearchFocus) _takeSearchFocus();
  }

  /// "Back" first closes an open filter panel
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
    if (_search.text != f.query) {
      _text = f.query;
      _search.text = f.query;
    }
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

    final filterButton = HikkaLineButton(
      scale: scale,
      icon: LineIcon.sliders,
      tooltip: 'Фільтри',
      dot: count > 0,
      onTap: () => setState(() => _sheetOpen = true),
    );
    final shared = widget.search != null;
    final summary = InkWell(
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
            style: TextStyle(fontFamily: 'Arial', color: uiTheme.textMuted, fontSize: 13 * scale),
          ),
        ),
      ),
    );

    return Stack(
      children: [
        HikkaCollapsingHeader(
          header: shared
              // "Огляд" has the search field in its header: here the summary with the filter button
              ? Padding(
                  padding: EdgeInsets.fromLTRB(pad, 2 * scale, pad - 8 * scale, 4 * scale),
                  child: Row(children: [Expanded(child: Align(alignment: Alignment.centerLeft, child: summary)), filterButton]),
                )
              : Column(
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
                      child: Align(alignment: Alignment.centerLeft, child: summary),
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
            countOf: (f) async => (await HikkaApi.instance.searchAnime(f, page: 1, size: 1, allowAdult: HikkaPrefs.instance.allowAdult)).total,
            onApply: _apply,
            onClose: () => setState(() => _sheetOpen = false),
          ),
        ),
      ],
    );
  }
}
