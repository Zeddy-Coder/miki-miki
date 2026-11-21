import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../services/hikka_nav.dart';
import '../app_ui_kit.dart';
import '../design_kit.dart';
import '../line_icons.dart';
import '../../utils/platform_info.dart';
import 'hikka_articles_page.dart';
import 'hikka_catalog_page.dart';
import 'hikka_characters_page.dart';
import 'hikka_collections_page.dart';
import 'hikka_common.dart';
import 'hikka_community_cards.dart';
import 'hikka_overview_page.dart';
import 'hikka_page_kit.dart';
import 'hikka_schedule_page.dart';

/// The "Огляд" tab: sections for discovery: collections, articles, a catalog with search and filters, characters and the calendar.
/// Opened sections are not destroyed (search and scroll stay in place until the app is closed).
class HikkaDiscoverPage extends StatefulWidget {
  final double scale;
  final double bottomInset;
  final int refreshToken;

  /// The "Оновити" button in the heading
  final VoidCallback onRefresh;

  const HikkaDiscoverPage({super.key, required this.scale, required this.onRefresh, this.bottomInset = 0, this.refreshToken = 0});

  static IconData iconOf(HikkaTab tab) => switch (tab) {
        HikkaTab.overview => Symbols.dashboard_rounded,
        HikkaTab.collections => Symbols.collections_bookmark_rounded,
        HikkaTab.articles => Symbols.article_rounded,
        HikkaTab.anime => Symbols.grid_view_rounded,
        HikkaTab.characters => Symbols.face_rounded,
        HikkaTab.schedule => Symbols.calendar_month_rounded,
      };

  /// The line icons of the section tabs
  static LineIcon lineIconOf(HikkaTab tab) => switch (tab) {
        HikkaTab.overview => LineIcon.grid,
        HikkaTab.schedule => LineIcon.calendar,
        HikkaTab.collections => LineIcon.stack,
        HikkaTab.articles => LineIcon.doc,
        HikkaTab.anime => LineIcon.sliders,
        HikkaTab.characters => LineIcon.face,
      };

  /// The order of the section tabs (and of swiping between them): the catalog follows the community sections,
  /// its search is the field at the top
  static const List<HikkaTab> order = [HikkaTab.overview, HikkaTab.schedule, HikkaTab.collections, HikkaTab.articles, HikkaTab.anime, HikkaTab.characters];

  /// The hint of the search field: what a tap on it searches
  static String searchHint(HikkaTab tab) => switch (tab) {
        HikkaTab.characters => 'Пошук персонажа за іменем…',
        HikkaTab.anime => 'Пошук аніме за назвою…',
        _ => 'Пошук аніме…',
      };

  @override
  State<HikkaDiscoverPage> createState() => _HikkaDiscoverPageState();
}

class _HikkaDiscoverPageState extends State<HikkaDiscoverPage> {
  final HikkaNav _nav = HikkaNav.instance;

  /// Sections already opened: we do not destroy them so search and scroll stay in place
  final Set<HikkaTab> _mounted = {};

  /// One search field for the whole tab (in the header): it searches the catalog, in "Персонажі" the characters;
  /// a tap on it in another section leads to the catalog
  final TextEditingController _animeQuery = TextEditingController();
  final TextEditingController _characterQuery = TextEditingController();
  final FocusNode _searchFocus = FocusNode(debugLabel: 'discover-search');

  /// The section shown in the last build: only a change of it concerns this page
  late HikkaTab _shownTab = _nav.tab;

  /// The section pages, built once per set of inputs: a tab switch or a rebuild of the header leaves the hidden
  /// sections alone (the catalog grid, the calendar…)
  final Map<HikkaTab, (Object, Widget)> _built = {};

  @override
  void initState() {
    super.initState();
    _mounted.add(_nav.tab);
    _nav.addListener(_onNav);
  }

  @override
  void dispose() {
    _nav.removeListener(_onNav);
    _animeQuery.dispose();
    _characterQuery.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// Every navigation notifies (a page opened over the app, a main tab switched): rebuilding this whole tab for each
  /// of them cost ~900 widgets per tap. Only a change of the section matters here
  void _onNav() {
    if (!mounted || _nav.tab == _shownTab) return;
    setState(() {
      _shownTab = _nav.tab;
      _mounted.add(_nav.tab);
    });
  }

  Widget _section(HikkaTab tab) {
    final scale = widget.scale;
    final inset = widget.bottomInset;
    final token = widget.refreshToken;
    final key = (scale, inset, token);
    final hit = _built[tab];
    if (hit != null && hit.$1 == key) return hit.$2;
    final page = _build(tab, scale, inset, token);
    _built[tab] = (key, page);
    return page;
  }

  Widget _build(HikkaTab tab, double scale, double inset, int token) {
    return switch (tab) {
      HikkaTab.overview => HikkaOverviewPage(scale: scale, bottomInset: inset, refreshToken: token),
      HikkaTab.collections => HikkaCollectionsPage(scale: scale, bottomInset: inset, refreshToken: token),
      HikkaTab.articles => HikkaArticlesPage(scale: scale, bottomInset: inset, refreshToken: token),
      HikkaTab.anime => HikkaCatalogPage(scale: scale, bottomInset: inset, refreshToken: token, search: _animeQuery, searchFocus: _searchFocus),
      HikkaTab.characters => HikkaCharactersPage(scale: scale, bottomInset: inset, refreshToken: token, search: _characterQuery),
      HikkaTab.schedule => HikkaSchedulePage(scale: scale, bottomInset: inset, refreshToken: token),
    };
  }

  Widget _sections(HikkaTab current) {
    return Stack(
      fit: StackFit.expand,
      children: [
        for (final tab in HikkaTab.values)
          if (_mounted.contains(tab))
            // Keys are needed so that when a new section appears the already opened ones do not lose state
            Offstage(
              key: ValueKey('discover-${tab.name}'),
              offstage: current != tab,
              child: TickerMode(enabled: current == tab, child: _section(tab)),
            ),
      ],
    );
  }

  /// On a phone the section refreshes by pulling down (on PC there is a button in the heading)
  Widget _withRefresh(Widget child) {
    if (!AppPlatform.isMobile) return child;
    return AppPullToRefresh(
      onRefresh: () async {
        widget.onRefresh();
        await Future<void>.delayed(const Duration(milliseconds: 600));
      },
      child: child,
    );
  }

  /// The search field: a real field in the catalog and characters; elsewhere a tap leads to the catalog with the cursor
  Widget _search(double scale, HikkaTab current) {
    final characters = current == HikkaTab.characters;
    return HikkaSearchField(
      key: const ValueKey('discover-search'),
      scale: scale,
      controller: characters ? _characterQuery : _animeQuery,
      focusNode: _searchFocus,
      hint: HikkaDiscoverPage.searchHint(current),
      onChanged: (_) {},
      onTap: () {
        if (current != HikkaTab.anime && current != HikkaTab.characters) _nav.setTab(HikkaTab.anime);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.scale;
    final current = _shownTab = _nav.tab;
    final pad = HikkaLayout.sidePad(context, scale);
    final order = HikkaDiscoverPage.order;
    return HikkaCollapsingHeader(
      resetOn: current,
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HikkaTabHeader(
            scale: scale,
            title: 'Огляд',
            subtitle: 'Знайдіть, що подивитися',
            // On a phone the section refreshes by pulling down
            actions: [if (!AppPlatform.isMobile) HikkaLineButton(scale: scale, icon: LineIcon.refresh, tooltip: 'Оновити', onTap: widget.onRefresh)],
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(pad, 12 * scale, pad, 8 * scale),
            child: Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: AppPlatform.isMobile ? double.infinity : 560 * scale),
                child: _search(scale, current),
              ),
            ),
          ),
          HikkaChipRow(
            scale: scale,
            selectedIndex: order.indexOf(current),
            children: [
              for (final t in order)
                AppPillTab(
                  key: ValueKey('discover-tab-${t.name}'),
                  scale: scale,
                  label: t.label,
                  icon: (c) => LineIconView(HikkaDiscoverPage.lineIconOf(t), size: 16 * scale, color: c),
                  selected: t == current,
                  onTap: () => _nav.setTab(t),
                ),
            ],
          ),
          SizedBox(height: 4 * scale),
        ],
      ),
      body: HikkaSwipeTabs(
        index: order.indexOf(current),
        count: order.length,
        onChanged: (i) => _nav.setTab(order[i]),
        child: _withRefresh(_sections(current)),
      ),
    );
  }
}
