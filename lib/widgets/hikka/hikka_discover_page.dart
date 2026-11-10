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

/// Вкладка «Огляд»: розділи для відкриттів — колекції, статті, каталог з пошуком і фільтрами, персонажі та календар.
/// Відкриті розділи не руйнуються (пошук і прокрутка лишаються на місці, поки не закрито застосунок).
class HikkaDiscoverPage extends StatefulWidget {
  final double scale;
  final double bottomInset;
  final int refreshToken;

  /// Кнопка «Оновити» в заголовку
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

  /// Розділи, які вже відкривали: їх не руйнуємо, щоб пошук і прокрутка лишались на місці
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
            // Ключі потрібні, щоб при появі нового розділу вже відкриті не втрачали стан
            Offstage(
              key: ValueKey('discover-${tab.name}'),
              offstage: current != tab,
              child: TickerMode(enabled: current == tab, child: _section(tab)),
            ),
      ],
    );
  }

  /// На телефоні розділ оновлюється потягом вниз (на ПК є кнопка в заголовку)
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
            // На телефоні розділ оновлюється потягом вниз
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
