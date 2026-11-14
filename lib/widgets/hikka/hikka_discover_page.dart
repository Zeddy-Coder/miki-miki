import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../services/hikka_nav.dart';
import '../app_ui_kit.dart';
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

  @override
  State<HikkaDiscoverPage> createState() => _HikkaDiscoverPageState();
}

class _HikkaDiscoverPageState extends State<HikkaDiscoverPage> {
  final HikkaNav _nav = HikkaNav.instance;

  /// Sections already opened: we do not destroy them so search and scroll stay in place
  final Set<HikkaTab> _mounted = {};

  @override
  void initState() {
    super.initState();
    _mounted.add(_nav.tab);
    _nav.addListener(_onNav);
  }

  @override
  void dispose() {
    _nav.removeListener(_onNav);
    super.dispose();
  }

  void _onNav() {
    if (!mounted) return;
    setState(() => _mounted.add(_nav.tab));
  }

  Widget _section(HikkaTab tab) {
    final scale = widget.scale;
    final inset = widget.bottomInset;
    final token = widget.refreshToken;
    return switch (tab) {
      HikkaTab.overview => HikkaOverviewPage(scale: scale, bottomInset: inset, refreshToken: token),
      HikkaTab.collections => HikkaCollectionsPage(scale: scale, bottomInset: inset, refreshToken: token),
      HikkaTab.articles => HikkaArticlesPage(scale: scale, bottomInset: inset, refreshToken: token),
      HikkaTab.anime => HikkaCatalogPage(scale: scale, bottomInset: inset, refreshToken: token),
      HikkaTab.characters => HikkaCharactersPage(scale: scale, bottomInset: inset, refreshToken: token),
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

  @override
  Widget build(BuildContext context) {
    final scale = widget.scale;
    final current = _nav.tab;
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
            actions: [if (!AppPlatform.isMobile) HikkaIconButton(icon: Symbols.refresh_rounded, tooltip: 'Оновити', scale: scale, onTap: widget.onRefresh)],
          ),
          HikkaChipRow(
            scale: scale,
            selectedIndex: current.index,
            children: [
              for (final t in HikkaTab.values)
                HikkaChip(label: t.label, icon: HikkaDiscoverPage.iconOf(t), scale: scale, selected: t == current, onTap: () => _nav.setTab(t)),
            ],
          ),
          SizedBox(height: 4 * scale),
        ],
      ),
      body: HikkaSwipeTabs(
        index: current.index,
        count: HikkaTab.values.length,
        onChanged: (i) => _nav.setTab(HikkaTab.values[i]),
        child: _withRefresh(_sections(current)),
      ),
    );
  }
}
