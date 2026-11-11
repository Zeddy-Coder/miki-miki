import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../models/hikka_models.dart';
import '../../models/hikka_user_models.dart';
import '../../services/hikka_api.dart';
import '../../services/hikka_auth.dart';
import '../../services/hikka_lists.dart';
import '../../services/hikka_pager.dart';
import '../../services/hikka_prefs.dart';
import '../../services/ui_theme_service.dart';
import '../app_animation_kit.dart';
import '../../utils/platform_info.dart';
import '../app_ui_kit.dart';
import '../mobile_sheet.dart';
import 'hikka_account_ui.dart';
import 'hikka_cards.dart';
import 'hikka_common.dart';
import 'hikka_community_cards.dart';
import 'hikka_filter_sheet.dart';
import 'hikka_my_list_bar.dart';
import 'hikka_page_kit.dart';

/// Вкладка «Списки»: списки перегляду Hikka (дивлюсь, у планах, переглянуто, відкладено, кинуто) й улюблене.
/// Без входу — запрошення увійти й перелік того, що з'явиться.
class HikkaListsPage extends StatefulWidget {
  final double scale;
  final double bottomInset;

  const HikkaListsPage({super.key, required this.scale, this.bottomInset = 0});

  /// Що дасть вхід: значок, назва, пояснення
  static const List<(IconData, String, String)> planned = [
    (Symbols.play_circle_rounded, 'Дивлюсь', 'Що ви дивитеся просто зараз'),
    (Symbols.bookmark_rounded, 'У планах', 'Відкладено «на потім»'),
    (
      Symbols.check_circle_rounded,
      'Переглянуто',
      'Завершені тайтли з вашою оцінкою',
    ),
    (Symbols.pause_circle_rounded, 'Відкладено', 'Призупинений перегляд'),
    (Symbols.cancel_rounded, 'Кинуто', 'Те, що ви вирішили не дивитися'),
    (
      Symbols.favorite_rounded,
      'Улюблене',
      'Тайтли, до яких хочеться повертатися',
    ),
  ];

  @override
  State<HikkaListsPage> createState() => _HikkaListsPageState();
}

class _HikkaListsPageState extends State<HikkaListsPage> {
  final ScrollController _scroll = AppSmoothScrollController();
  HikkaSearchFilters _filters = const HikkaSearchFilters(sort: HikkaSearchFilters.defaultListSort);
  bool _sheetOpen = false;
  int _filterRev = 0;
  final Map<int, HikkaPager<HikkaWatchEntry>> _pagers = {};

  /// Номер вкладки: 0…4 — статуси за порядком [HikkaWatchStatus.values], 5 — улюблене
  int _tab = 0;
  static const int _favouriteTab = 5;

  HikkaWatchStats? _stats;
  String _user = '';
  int _seenVersion = 0;
  String? _error;

  double get _scale => widget.scale;
  HikkaAuth get _auth => HikkaAuth.instance;
  HikkaMyList get _list => HikkaMyList.instance;

  @override
  void initState() {
    super.initState();
    _user = _auth.signedIn ? _auth.username : '';
    _seenVersion = _list.version;
    _auth.addListener(_onChange);
    _list.addListener(_onChange);
    if (_user.isNotEmpty) unawaited(_loadStats());
  }

  @override
  void dispose() {
    _auth.removeListener(_onChange);
    _list.removeListener(_onChange);
    _disposePagers();
    _scroll.dispose();
    super.dispose();
  }

  void _disposePagers() {
    for (final p in _pagers.values) {
      p.dispose();
    }
    _pagers.clear();
  }

  void _onChange() {
    if (!mounted) return;
    final user = _auth.signedIn ? _auth.username : '';
    if (user != _user) {
      _user = user;
      _disposePagers();
      _stats = null;
      _error = null;
      _seenVersion = _list.version;
      if (user.isNotEmpty) unawaited(_loadStats());
    } else if (_list.version != _seenVersion) {
      _seenVersion = _list.version;
      for (final p in _pagers.values) {
        unawaited(p.reload());
      }
      unawaited(_loadStats());
    }
    setState(() {});
  }

  Future<void> _loadStats() async {
    try {
      final s = await _list.stats(refresh: true);
      if (mounted) setState(() => _stats = s);
    } on HikkaException {
      // Лічильники — прикраса: без них вкладки просто без цифр
    }
  }

  Future<HikkaPage<HikkaWatchEntry>> _fetch(
    int tab,
    String user,
    int page,
  ) async {
    final api = HikkaApi.instance;
    final adult = HikkaPrefs.instance.allowAdult;
    if (tab == _favouriteTab) {
      final p = await api.favourites(user, page: page, size: 30);
      return HikkaPage(
        items: [
          for (final a in p.items)
            if (adult || !a.isAdult)
              HikkaWatchEntry(status: HikkaWatchStatus.planned, anime: a),
        ],
        page: p.page,
        pages: p.pages,
        total: p.total,
      );
    }
    final p = await api.watchList(
      user,
      status: HikkaWatchStatus.values[tab],
      page: page,
      size: 30,
      filters: _filters,
    );
    return HikkaPage(
      items: [
        for (final e in p.items)
          if (e.anime != null && (adult || !e.anime!.isAdult)) e,
      ],
      page: p.page,
      pages: p.pages,
      total: p.total,
    );
  }

  HikkaPager<HikkaWatchEntry> _pagerFor(int tab) {
    return _pagers.putIfAbsent(tab, () {
      final user = _user;
      final p = HikkaPager<HikkaWatchEntry>(
        (page) => _fetch(tab, user, page),
        keyOf: (e) => e.anime?.slug ?? e.reference,
      );
      unawaited(p.loadMore());
      return p;
    });
  }

  void _select(int tab) {
    if (tab == _tab) return;
    setState(() => _tab = tab);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _refresh() async {
    unawaited(_loadStats());
    await Future.wait([for (final p in _pagers.values) p.reload()]);
  }

  void _applyFilters(HikkaSearchFilters f) {
    setState(() {
      _filters = f;
      _sheetOpen = false;
      _filterRev++;
      _disposePagers();
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Widget _filterButton(double scale) {
    final count = _filters.activeCount + (_filters.sort != HikkaSearchFilters.defaultListSort || _filters.ascending ? 1 : 0);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        HikkaIconButton(icon: Symbols.tune_rounded, tooltip: 'Фільтри й сортування', scale: scale, active: count > 0, onTap: () => setState(() => _sheetOpen = true)),
        if (count > 0)
          Positioned(
            right: 2,
            top: 2,
            child: IgnorePointer(
              child: Container(
                constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: uiTheme.accentColor, borderRadius: uiTheme.borderRadius(9)),
                child: Text('$count', style: TextStyle(fontFamily: 'Arial', color: uiTheme.onAccent, fontSize: 10.5, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _remove(HikkaWatchEntry e) async {
    final slug = e.anime?.slug;
    if (slug == null) return;
    try {
      await _list.remove(slug);
      if (mounted) setState(() => _error = null);
    } on HikkaException catch (err) {
      if (mounted) setState(() => _error = err.message);
    }
  }

  // ── Вкладки ────────────────────────────────────────────────────

  Widget _tabs(double pad) {
    final scale = _scale;
    final items = <Widget>[
      for (int i = 0; i < HikkaWatchStatus.values.length; i++)
        HikkaChip(
          label:
              _stats == null
                  ? HikkaWatchStatus.values[i].label
                  : '${HikkaWatchStatus.values[i].label} · ${_stats!.of(HikkaWatchStatus.values[i])}',
          scale: scale,
          icon: hikkaStatusIcon(HikkaWatchStatus.values[i]),
          color: hikkaStatusColor(HikkaWatchStatus.values[i]),
          selected: _tab == i,
          onTap: () => _select(i),
        ),
      HikkaChip(
        label: 'Улюблене',
        scale: scale,
        icon: Symbols.favorite_rounded,
        color: hikkaFavouriteColor,
        selected: _tab == _favouriteTab,
        onTap: () => _select(_favouriteTab),
      ),
    ];
    return HikkaChipRow(scale: scale, selectedIndex: _tab, children: items);
  }

  Widget _card(HikkaWatchEntry e, int tab) {
    final a = e.anime;
    if (a == null) return const SizedBox.shrink();
    final status = tab == _favouriteTab ? null : HikkaWatchStatus.values[tab];
    final showProgress =
        status == HikkaWatchStatus.watching ||
        status == HikkaWatchStatus.onHold ||
        status == HikkaWatchStatus.dropped;
    final total = a.episodesTotal;
    final meta = HikkaAnimeCard.metaOf(a);
    final caption = [
      if (e.score > 0) '★ ${e.score}',
      if (meta.isNotEmpty) meta,
    ].join(' · ');
    return HikkaAnimeCard(
      anime: a,
      scale: _scale,
      showStatus: false,
      pill:
          showProgress
              ? '${e.episodes}/${total != null && total > 0 ? total : '?'}'
              : null,
      pillColor: status == null ? null : hikkaStatusColor(status),
      caption: caption.isEmpty ? null : caption,
      onRemove: status == null ? null : () => unawaited(_remove(e)),
    );
  }

  Widget _signedIn() {
    final scale = _scale;
    final pad = HikkaLayout.sidePad(context, scale);
    final tab = _tab;
    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HikkaTabHeader(
          scale: scale,
          title: 'Списки',
          subtitle:
              _auth.username.isEmpty ? 'Ваш перегляд на Hikka' : _auth.username,
          actions: [
            if (tab != _favouriteTab) _filterButton(scale),
            // На телефоні оновлення — потяг вниз
            if (!AppPlatform.isMobile)
              HikkaIconButton(
                icon: Symbols.refresh_rounded,
                tooltip: 'Оновити',
                scale: scale,
                onTap: () => unawaited(_refresh()),
              ),
          ],
        ),
        _tabs(pad),
        if (_error != null)
          Padding(
            padding: EdgeInsets.fromLTRB(pad, 8 * scale, pad, 0),
            child: Text(
              _error!,
              style: hikkaStyle(12 * scale, color: const Color(0xFFE57373)),
            ),
          ),
        SizedBox(height: 8 * scale),
      ],
    );
    final content = HikkaCollapsingHeader(
      resetOn: tab,
      header: header,
      body: HikkaSwipeTabs(
            index: tab,
            count: _favouriteTab + 1,
            onChanged: _select,
            child: _withRefresh(
            HikkaPagedGrid<HikkaWatchEntry>(
              key: ValueKey('list-$tab-$_user-$_filterRev'),
              pager: _pagerFor(tab),
              scale: scale,
              controller: _scroll,
              bottomInset: widget.bottomInset,
              emptyIcon:
                  tab == _favouriteTab
                      ? Symbols.favorite_rounded
                      : Symbols.bookmarks_rounded,
              emptyText:
                  tab == _favouriteTab
                      ? 'В улюбленому порожньо. Позначте тайтл сердечком на його сторінці.'
                      : 'Тут поки порожньо. Додайте тайтл зі сторінки аніме.',
              itemBuilder: (context, e) => _card(e, tab),
            ),
            ),
          ),
    );
    return Stack(
      children: [
        content,
        MobileSheetFrame(
          open: _sheetOpen,
          onDismiss: () => setState(() => _sheetOpen = false),
          child: HikkaFilterSheet(
            scale: scale,
            initial: _filters,
            allowAdult: HikkaPrefs.instance.allowAdult,
            sortOptions: HikkaSearchFilters.listSorts,
            defaultSort: HikkaSearchFilters.defaultListSort,
            onApply: _applyFilters,
            onClose: () => setState(() => _sheetOpen = false),
          ),
        ),
      ],
    );
  }

  Widget _withRefresh(Widget child) {
    if (!AppPlatform.isMobile) return child;
    return AppPullToRefresh(onRefresh: _refresh, child: child);
  }

  Widget _guest() {
    final scale = _scale;
    final pad = HikkaLayout.sidePad(context, scale);
    return HikkaCollapsingHeader(
      header: HikkaTabHeader(
        scale: scale,
        title: 'Списки',
        subtitle: 'Ваш перегляд на Hikka',
      ),
      body: HikkaPageFrame(
            scale: scale,
            controller: _scroll,
            bottomInset: widget.bottomInset,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(pad, 8 * scale, pad, 16 * scale),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: hikkaReadableWidth(scale),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        HikkaAccountCard(scale: scale),
                        SizedBox(height: 20 * scale),
                        AppSectionHeader(
                          scale: scale,
                          title: 'Що з’явиться після входу',
                          subtitle: 'Так само, як на hikka.io',
                        ),
                        SizedBox(height: 10 * scale),
                        AppCard(
                          scale: scale,
                          radius: 14,
                          padding: EdgeInsets.symmetric(
                            horizontal: 14 * scale,
                            vertical: 4 * scale,
                          ),
                          child: Column(
                            children: [
                              for (
                                int i = 0;
                                i < HikkaListsPage.planned.length;
                                i++
                              ) ...[
                                if (i > 0)
                                  Divider(
                                    height: 1,
                                    color: uiTheme.borderSubtle,
                                  ),
                                _PlannedRow(
                                  scale: scale,
                                  icon: HikkaListsPage.planned[i].$1,
                                  title: HikkaListsPage.planned[i].$2,
                                  text: HikkaListsPage.planned[i].$3,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) =>
      _auth.signedIn && _user.isNotEmpty ? _signedIn() : _guest();
}

class _PlannedRow extends StatelessWidget {
  final double scale;
  final IconData icon;
  final String title;
  final String text;

  const _PlannedRow({
    required this.scale,
    required this.icon,
    required this.title,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 11 * scale),
      child: Row(
        children: [
          Icon(
            icon,
            color: uiTheme.textDarkMuted,
            size: 22 * scale,
            weight: 300,
          ),
          SizedBox(width: 14 * scale),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: hikkaStyle(13.5 * scale, weight: FontWeight.w600),
                ),
                SizedBox(height: 1 * scale),
                Text(
                  text,
                  style: hikkaStyle(11.5 * scale, color: uiTheme.textDarkMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
