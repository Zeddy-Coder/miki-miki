import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../models/hikka_models.dart';
import '../../models/hikka_user_models.dart';
import '../../services/hikka_api.dart';
import '../../services/hikka_auth.dart';
import '../../services/hikka_lists.dart';
import '../../services/hikka_nav.dart';
import '../../services/hikka_pager.dart';
import '../../services/hikka_prefs.dart';
import '../../services/storage_service.dart';
import '../../services/ui_theme_service.dart';
import '../../utils/platform_info.dart';
import '../app_animation_kit.dart';
import '../app_tones.dart';
import '../app_ui_kit.dart' show AppPullToRefresh;
import '../design_kit.dart';
import '../line_icons.dart';
import '../mobile_sheet.dart';
import 'hikka_account_ui.dart';
import 'hikka_cards.dart';
import 'hikka_common.dart';
import 'hikka_community_cards.dart';
import 'hikka_filter_sheet.dart';
import 'hikka_my_list_bar.dart';
import 'hikka_page_kit.dart';
import 'hikka_paged_list.dart';

/// The "Списки" tab: Hikka watch lists (watching, planned, completed, on hold, dropped) and favorites as pill tabs with
/// the bookmark glyphs and counters; a quiet sort drop-down and a grid / rows switch; posters with a thin progress bar.
/// Without sign-in: the mascot, one "Увійти через Hikka" button and what will appear.
class HikkaListsPage extends StatefulWidget {
  final double scale;
  final double bottomInset;

  const HikkaListsPage({super.key, required this.scale, this.bottomInset = 0});

  /// What signing in gives: an icon, a title, an explanation
  static const List<(LineIcon, String, String)> planned = [
    (LineIcon.bookmark, 'Ваші списки', 'Дивлюсь, у планах, переглянуто — як на hikka.io'),
    (LineIcon.list, 'Прогрес серій', 'Позначки переглянутого передаються на Hikka самі'),
    (LineIcon.bell, 'Нові серії', 'Сповіщення про вихід у вибраній озвучці'),
    (LineIcon.heart, 'Улюблене', 'Тайтли, позначені сердечком'),
  ];

  /// The sort drop-down: the long names of the lists' sort options
  static String sortLabel(String key) => switch (key) {
        'watch_updated' => 'Оновлені нещодавно',
        'watch_created' => 'Додані нещодавно',
        'watch_score' => 'За моєю оцінкою',
        'score' => 'За оцінкою MAL',
        'start_date' => 'За датою виходу',
        'scored_by' => 'За популярністю',
        _ => key,
      };

  /// The empty tab: a title and how something gets here
  static (String, String) emptyOf(HikkaWatchStatus? s) => switch (s) {
        HikkaWatchStatus.watching => ('Зараз нічого не дивитеся', 'Сюди потрапляє те, що ви почали дивитися. Додати тайтл можна закладкою на його сторінці'),
        HikkaWatchStatus.planned => ('Планів поки немає', 'Додайте тайтл закладкою на його сторінці, щоб не загубити'),
        HikkaWatchStatus.completed => ('Переглянутого ще немає', 'Сюди потрапляють тайтли, які ви додивилися до кінця'),
        HikkaWatchStatus.onHold => ('Відкладеного немає', 'Сюди потрапляє те, що ви поставили на паузу. Змінити статус можна закладкою на сторінці тайтла'),
        HikkaWatchStatus.dropped => ('Кинутого немає', 'Сюди потрапляє те, що ви вирішили не дивитися'),
        null => ('В улюбленому порожньо', 'Позначте тайтл сердечком у «Моєму списку» на його сторінці'),
      };

  @override
  State<HikkaListsPage> createState() => _HikkaListsPageState();
}

class _HikkaListsPageState extends State<HikkaListsPage> {
  final ScrollController _scroll = AppSmoothScrollController();
  HikkaSearchFilters _filters = const HikkaSearchFilters(sort: HikkaSearchFilters.defaultListSort);
  bool _sheetOpen = false;
  int _filterRev = 0;
  final Map<int, HikkaPager<HikkaWatchEntry>> _pagers = {};
  bool _rows = StorageService.getHikkaListRows();

  /// Tab number: 0…4 are the statuses in the order of [HikkaWatchStatus.values], 5 is favorites
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
    HikkaNav.instance.listsTab.addListener(_onTabRequest);
    final want = HikkaNav.instance.listsTab.value;
    if (want != null) {
      HikkaNav.instance.listsTab.value = null;
      if (want >= 0 && want <= _favouriteTab) _tab = want;
    }
    if (_user.isNotEmpty) unawaited(_loadStats());
  }

  /// The profile asks to open a particular status (`HikkaNav.openLists`)
  void _onTabRequest() {
    final want = HikkaNav.instance.listsTab.value;
    if (want == null) return;
    HikkaNav.instance.listsTab.value = null;
    if (want < 0 || want > _favouriteTab) return;
    if (!mounted || want == _tab) return;
    if (_scroll.hasClients) _scroll.jumpTo(0);
    setState(() => _tab = want);
  }

  @override
  void dispose() {
    _auth.removeListener(_onChange);
    _list.removeListener(_onChange);
    HikkaNav.instance.listsTab.removeListener(_onTabRequest);
    _disposePagers();
    _scroll.dispose();
    super.dispose();
  }

  void _disposePagers() {
    for (final p in _pagers.values) {
      p.removeListener(_onPager);
      p.dispose();
    }
    _pagers.clear();
  }

  /// A page of a tab arrived: the favorites counter in its tab may change
  void _onPager() {
    if (mounted) setState(() {});
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
      // Counters are decoration: without them the tabs just have no numbers
    }
  }

  Future<HikkaPage<HikkaWatchEntry>> _fetch(int tab, String user, int page) async {
    final api = HikkaApi.instance;
    final adult = HikkaPrefs.instance.allowAdult;
    if (tab == _favouriteTab) {
      final p = await api.favourites(user, page: page, size: 30);
      return HikkaPage(
        items: [
          for (final a in p.items)
            if (adult || !a.isAdult) HikkaWatchEntry(status: HikkaWatchStatus.planned, anime: a),
        ],
        page: p.page,
        pages: p.pages,
        total: p.total,
      );
    }
    final p = await api.watchList(user, status: HikkaWatchStatus.values[tab], page: page, size: 30, filters: _filters);
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
      final p = HikkaPager<HikkaWatchEntry>((page) => _fetch(tab, user, page), keyOf: (e) => e.anime?.slug ?? e.reference);
      if (tab == _favouriteTab) p.addListener(_onPager);
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

  void _setRows(bool rows) {
    if (rows == _rows) return;
    StorageService.saveHikkaListRows(rows);
    setState(() => _rows = rows);
  }

  /// The sort drop-down under the sort line: one tile, the chosen order bold with the accent check mark
  Future<void> _pickSort(BuildContext anchor) async {
    final picked = await showAppMenu<String>(
      context,
      scale: _scale,
      anchor: appRectOf(anchor),
      caption: 'Сортування',
      entries: [
        for (final o in HikkaSearchFilters.listSorts) AppMenuEntry(o.key, HikkaListsPage.sortLabel(o.key), selected: _filters.sort == o.key),
      ],
    );
    if (picked == null || picked == _filters.sort) return;
    _applyFilters(_filters.copyWith(sort: picked));
  }

  Future<void> _remove(HikkaWatchEntry e, {required bool favourite}) async {
    final slug = e.anime?.slug;
    if (slug == null) return;
    try {
      if (favourite) {
        await _list.setFavourite(slug, false);
        unawaited(_pagerFor(_favouriteTab).reload());
      } else {
        await _list.remove(slug);
      }
      if (mounted) setState(() => _error = null);
    } on HikkaException catch (err) {
      if (mounted) setState(() => _error = err.message);
    }
  }

  // ── Cards ─────────────────────────────────────────────────────

  /// Watched share for statuses with progress (none for "У планах", "Переглянуто" and favorites)
  static double? _progressOf(HikkaWatchEntry e, HikkaWatchStatus? s) {
    final total = e.anime?.episodesTotal ?? 0;
    if (s == null || total <= 0 || e.episodes <= 0) return null;
    if (s == HikkaWatchStatus.planned || s == HikkaWatchStatus.completed) return null;
    return e.episodes / total;
  }

  static String _episodes(int n) => '$n ${HikkaText.plural(n, 'серія', 'серії', 'серій')}';

  /// The grey line under a card: "6 з 25 · ★ 8", "Анонс · Зима 2027", "TV Серіал · 2023 · ★ 9"
  static String _metaOf(HikkaWatchEntry e, HikkaWatchStatus? s, {bool score = true}) {
    final a = e.anime!;
    final total = a.episodesTotal ?? 0;
    final released = a.episodesReleased ?? 0;
    final mine = score && e.score > 0 ? '★ ${e.score}' : null;
    switch (s) {
      case HikkaWatchStatus.watching || HikkaWatchStatus.onHold || HikkaWatchStatus.dropped:
        final progress = total > 0 ? '${e.episodes} з $total' : _episodes(e.episodes);
        return [progress, if (mine != null) mine].join(' · ');
      case HikkaWatchStatus.planned:
        if (a.isAnnounced) return ['Анонс', if (a.seasonLabel.isNotEmpty) a.seasonLabel].join(' · ');
        if (a.isOngoing) {
          if (released > 0 && total > 0) return 'Онґоїнґ · $released з $total';
          if (released > 0) return 'Онґоїнґ · ${_episodes(released)}';
          return 'Онґоїнґ';
        }
        return HikkaAnimeCard.typeYearOf(a);
      case HikkaWatchStatus.completed:
        return [HikkaAnimeCard.typeYearOf(a), if (mine != null) mine].where((x) => x.isNotEmpty).join(' · ');
      case null:
        return HikkaAnimeCard.typeYearOf(a);
    }
  }

  /// A row's grey line: the type, the year and how many episodes (the score stands on the right)
  static String _rowMetaOf(HikkaWatchEntry e, HikkaWatchStatus? s) {
    final a = e.anime!;
    final total = a.episodesTotal ?? 0;
    if (s == HikkaWatchStatus.watching || s == HikkaWatchStatus.onHold || s == HikkaWatchStatus.dropped) {
      return [_metaOf(e, s, score: false), if (a.typeLabel.isNotEmpty) a.typeLabel].join(' · ');
    }
    if (s == HikkaWatchStatus.planned) return _metaOf(e, s, score: false);
    return [
      HikkaAnimeCard.typeYearOf(a),
      if (total > 1) _episodes(total),
    ].where((x) => x.isNotEmpty).join(' · ');
  }

  Widget _card(HikkaWatchEntry e, int tab) {
    final a = e.anime;
    if (a == null) return const SizedBox.shrink();
    final fav = tab == _favouriteTab;
    final status = fav ? null : HikkaWatchStatus.values[tab];
    return HikkaAnimeCard(
      anime: a,
      scale: _scale,
      caption: _metaOf(e, status),
      progress: _progressOf(e, status),
      seen: fav ? null : e.episodes,
      removeLabel: fav ? 'Прибрати з улюбленого' : 'Прибрати зі списку',
      onRemove: () => unawaited(_remove(e, favourite: fav)),
    );
  }

  Widget _row(HikkaWatchEntry e, int tab) {
    final a = e.anime;
    if (a == null) return const SizedBox.shrink();
    final fav = tab == _favouriteTab;
    final status = fav ? null : HikkaWatchStatus.values[tab];
    return _ListRow(
      entry: e,
      scale: _scale,
      pad: HikkaLayout.sidePad(context, _scale),
      meta: _rowMetaOf(e, status),
      showScore: !fav,
      onRemove: () => unawaited(_remove(e, favourite: fav)),
      removeLabel: fav ? 'Прибрати з улюбленого' : 'Прибрати зі списку',
    );
  }

  // ── Header ────────────────────────────────────────────────────

  Widget _tabs() {
    final scale = _scale;
    final accent = uiTheme.accentColor;
    return HikkaChipRow(
      scale: scale,
      selectedIndex: _tab,
      children: [
        for (int i = 0; i < HikkaWatchStatus.values.length; i++)
          AppPillTab(
            key: ValueKey('list-tab-$i'),
            scale: scale,
            label: HikkaWatchStatus.values[i].label,
            count: _stats == null ? null : HikkaText.count(_stats!.of(HikkaWatchStatus.values[i])),
            selected: _tab == i,
            icon: (c) => HikkaListMark(status: HikkaWatchStatus.values[i], size: 17 * scale, color: _tab == i ? accent : c),
            onTap: () => _select(i),
          ),
        AppPillTab(
          key: const ValueKey('list-tab-5'),
          scale: scale,
          label: 'Улюблене',
          count: _favouriteCount(),
          selected: _tab == _favouriteTab,
          icon: (c) => LineIconView(LineIcon.heart, size: 17 * scale, color: c),
          onTap: () => _select(_favouriteTab),
        ),
      ],
    );
  }

  /// The favorites counter comes with the first page (Hikka has no separate number for it)
  String? _favouriteCount() {
    final p = _pagers[_favouriteTab];
    if (p == null || (p.items.isEmpty && !p.isEmpty)) return null;
    return HikkaText.count(p.total);
  }

  /// "Оновлені нещодавно ⌄" (or "7 тайтлів" in favorites) and the grid / rows switch
  Widget _sortRow(double pad) {
    final scale = _scale;
    final fav = _tab == _favouriteTab;
    Widget mode(LineIcon icon, bool rows, String tip) => Semantics(
          button: true,
          selected: _rows == rows,
          label: tip,
          excludeSemantics: true,
          child: Tooltip(
            message: tip,
            child: InkResponse(
              onTap: () => _setRows(rows),
              radius: 20 * scale,
              splashColor: Colors.transparent,
              highlightColor: uiTheme.touchHighlight,
              child: SizedBox.square(
                dimension: AppPlatform.isMobile ? 40.0 : 34 * scale,
                child: Center(
                  child: LineIconView(icon, size: 19 * scale, color: _rows == rows ? (uiTheme.isLight ? uiTheme.textPrimary : const Color(0xFFEEEEEE)) : uiTheme.textDarkMuted),
                ),
              ),
            ),
          ),
        );
    final Widget left;
    if (fav) {
      final count = _favouriteCount();
      final total = _pagers[_favouriteTab]?.total ?? 0;
      left = Text(count == null ? '' : '$count ${HikkaText.plural(total, 'тайтл', 'тайтли', 'тайтлів')}', style: hikkaStyle(13 * scale, color: uiTheme.textMuted));
    } else {
      left = Builder(
        builder: (anchor) => Semantics(
          button: true,
          label: 'Сортування: ${HikkaListsPage.sortLabel(_filters.sort)}',
          excludeSemantics: true,
          child: InkWell(
            onTap: () => unawaited(_pickSort(anchor)),
            borderRadius: uiTheme.borderRadius(8 * scale),
            splashColor: Colors.transparent,
            highlightColor: uiTheme.touchHighlight,
            hoverColor: uiTheme.hoverOverlay,
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 8 * scale),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(HikkaListsPage.sortLabel(_filters.sort), style: hikkaStyle(13 * scale, color: AppTones.plateText)),
                  SizedBox(width: 4 * scale),
                  Transform.rotate(
                    angle: _filters.ascending ? math.pi : 0,
                    child: LineIconView(LineIcon.chevronDown, size: 16 * scale, color: uiTheme.textMuted),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 8 * scale, pad - 8 * scale, 2 * scale),
      child: Row(
        children: [
          Expanded(child: Align(alignment: Alignment.centerLeft, child: left)),
          mode(LineIcon.grid, false, 'Сіткою'),
          mode(LineIcon.rows, true, 'Списком'),
        ],
      ),
    );
  }

  Widget _empty(int tab) {
    final scale = _scale;
    final fav = tab == _favouriteTab;
    final status = fav ? null : HikkaWatchStatus.values[tab];
    final filtered = !fav && _filters.activeCount > 0;
    final (title, text) = filtered ? ('Нічого не знайдено', 'Змініть фільтри або скиньте їх') : HikkaListsPage.emptyOf(status);
    final glyph = AppTones.chevron;
    return Padding(
      padding: EdgeInsets.fromLTRB(30 * scale, 90 * scale, 30 * scale, 0),
      child: Column(
        children: [
          fav ? LineIconView(LineIcon.heart, size: 56 * scale, color: glyph) : HikkaListMark(status: status, size: 56 * scale, color: glyph),
          SizedBox(height: 14 * scale),
          Text(title, textAlign: TextAlign.center, style: hikkaStyle(16 * scale, weight: FontWeight.bold, color: uiTheme.isLight ? uiTheme.textPrimary : const Color(0xFFDDDDDD))),
          SizedBox(height: 6 * scale),
          Text(text, textAlign: TextAlign.center, style: hikkaStyle(13.5 * scale, color: uiTheme.textMuted, height: 1.45)),
          if (!filtered) ...[
            SizedBox(height: 16 * scale),
            AppPlate(
              scale: scale,
              label: 'Перейти до огляду',
              height: 40,
              leading: (c) => LineIconView(LineIcon.search, size: 17 * scale, color: c),
              onTap: () => HikkaNav.instance.setMain(MainTab.discover),
            ),
          ],
        ],
      ),
    );
  }

  Widget _signedIn() {
    final scale = _scale;
    final pad = HikkaLayout.sidePad(context, scale);
    final tab = _tab;
    final filterCount = _filters.activeCount + (_filters.sort != HikkaSearchFilters.defaultListSort || _filters.ascending ? 1 : 0);
    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HikkaTabHeader(
          scale: scale,
          title: 'Списки',
          subtitle: _auth.username.isEmpty ? 'Ваш перегляд на Hikka' : _auth.username,
          actions: [
            if (tab != _favouriteTab)
              HikkaLineButton(
                scale: scale,
                icon: LineIcon.sliders,
                tooltip: 'Фільтри й сортування',
                dot: filterCount > 0,
                onTap: () => setState(() => _sheetOpen = true),
              ),
            // On a phone, refresh is a pull-down
            if (!AppPlatform.isMobile) HikkaLineButton(scale: scale, icon: LineIcon.refresh, tooltip: 'Оновити', onTap: () => unawaited(_refresh())),
          ],
        ),
        SizedBox(height: 8 * scale),
        _tabs(),
        _sortRow(pad),
        if (_error != null)
          Padding(
            padding: EdgeInsets.fromLTRB(pad, 4 * scale, pad, 0),
            child: Text(_error!, style: hikkaStyle(12 * scale, color: AppTones.danger)),
          ),
        SizedBox(height: 6 * scale),
      ],
    );
    final pager = _pagerFor(tab);
    final key = ValueKey('list-$tab-$_user-$_filterRev-$_rows');
    final content = HikkaCollapsingHeader(
      resetOn: tab,
      header: header,
      body: HikkaSwipeTabs(
        index: tab,
        count: _favouriteTab + 1,
        onChanged: _select,
        child: _withRefresh(
          _rows
              ? HikkaPagedList<HikkaWatchEntry>(
                  key: key,
                  pager: pager,
                  scale: scale,
                  controller: _scroll,
                  bottomInset: widget.bottomInset,
                  flush: true,
                  maxCardWidth: 720,
                  emptyText: '',
                  empty: _empty(tab),
                  itemBuilder: (context, e) => _row(e, tab),
                )
              : HikkaPagedGrid<HikkaWatchEntry>(
                  key: key,
                  pager: pager,
                  scale: scale,
                  controller: _scroll,
                  bottomInset: widget.bottomInset,
                  emptyText: '',
                  empty: _empty(tab),
                  itemBuilder: (context, e) => _card(e, tab),
                ),
        ),
      ),
    );
    final user = _user;
    return Stack(
      children: [
        content,
        MobileSheetFrame(
          open: _sheetOpen,
          onDismiss: () => setState(() => _sheetOpen = false),
          child: HikkaFilterSheet(
            scale: scale,
            title: 'Сортування й фільтри',
            initial: _filters,
            allowAdult: HikkaPrefs.instance.allowAdult,
            sortOptions: HikkaSearchFilters.listSorts,
            defaultSort: HikkaSearchFilters.defaultListSort,
            countOf: tab == _favouriteTab
                ? null
                : (f) async => (await HikkaApi.instance.watchList(user, status: HikkaWatchStatus.values[tab], page: 1, size: 1, filters: f)).total,
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
    final inset = pad + 2 * scale;
    return HikkaCollapsingHeader(
      header: HikkaTabHeader(scale: scale, title: 'Списки', subtitle: 'Ваш перегляд на Hikka'),
      body: HikkaPageFrame(
        scale: scale,
        controller: _scroll,
        bottomInset: widget.bottomInset,
        children: [
          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: hikkaReadableWidth(scale)),
              child: ListenableBuilder(
                listenable: _auth,
                builder: (context, _) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(24 * scale, 22 * scale, 24 * scale, 0),
                      child: Column(
                        children: [
                          Image.asset('assets/images/app_mascot.png', width: 118 * scale, filterQuality: FilterQuality.medium),
                          SizedBox(height: 12 * scale),
                          Text('Увійдіть через Hikka', textAlign: TextAlign.center, style: hikkaStyle(18 * scale, weight: FontWeight.bold)),
                          SizedBox(height: 6 * scale),
                          Text(
                            'Списки, прогрес і улюблене підтягнуться з вашого акаунта',
                            textAlign: TextAlign.center,
                            style: hikkaStyle(13.5 * scale, color: uiTheme.textMuted, height: 1.45),
                          ),
                          if (_auth.error != null) ...[
                            SizedBox(height: 10 * scale),
                            Text(_auth.error!, textAlign: TextAlign.center, style: hikkaStyle(12.5 * scale, color: AppTones.danger, height: 1.4)),
                          ],
                          SizedBox(height: 16 * scale),
                          HikkaLoginButton(scale: scale),
                        ],
                      ),
                    ),
                    AppGroupCaption(scale: scale, text: 'Що з’явиться після входу', inset: inset, top: 22),
                    for (final (icon, title, text) in HikkaListsPage.planned) AppLineRow(scale: scale, inset: inset, icon: icon, title: title, subtitle: text),
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
  Widget build(BuildContext context) => _auth.signedIn && _user.isNotEmpty ? _signedIn() : _guest();
}

/// One title as a row (the "Списком" mode): a small poster, the title, the type · year · episodes, my score on the right
class _ListRow extends StatelessWidget {
  final HikkaWatchEntry entry;
  final double scale;
  final double pad;
  final String meta;
  final bool showScore;
  final VoidCallback onRemove;
  final String removeLabel;

  const _ListRow({
    required this.entry,
    required this.scale,
    required this.pad,
    required this.meta,
    required this.showScore,
    required this.onRemove,
    required this.removeLabel,
  });

  Future<void> _menu(BuildContext context, {Offset? at}) => showHikkaCardMenu(
        context,
        anime: entry.anime!,
        scale: scale,
        anchor: at != null ? Rect.fromLTWH(at.dx, at.dy, 1, 1) : appRectOf(context),
        lift: at != null ? null : Material(color: Colors.transparent, child: _content()),
        seen: showScore ? entry.episodes : null,
        removeLabel: removeLabel,
        onRemove: onRemove,
      );

  Widget _content() {
    final a = entry.anime!;
    final title = a.title(HikkaPrefs.instance.titleLang);
    final Widget right;
    if (!showScore) {
      right = const SizedBox.shrink();
    } else if (entry.score > 0) {
      right = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          LineIconView(LineIcon.star, size: 14 * scale, color: AppTones.plateText, stroke: 1.8),
          SizedBox(width: 4 * scale),
          Text('${entry.score}', style: hikkaStyle(14 * scale, color: uiTheme.isLight ? uiTheme.textPrimary : const Color(0xFFDDDDDD))),
        ],
      );
    } else {
      right = Text('без оцінки', style: hikkaStyle(12.5 * scale, color: AppTones.chevron));
    }
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: pad, vertical: 8 * scale),
      child: Row(
        children: [
          SizedBox(
            width: 48 * scale,
            height: 68 * scale,
            child: HikkaPoster(url: a.image, malId: a.malId, scale: scale, aspect: 48 / 68, radius: 9, icon: Symbols.movie_rounded),
          ),
          SizedBox(width: 14 * scale),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: hikkaStyle(14.5 * scale)),
                SizedBox(height: 3 * scale),
                HikkaMetaLine(text: meta, scale: scale, size: 12.5, color: AppTones.rowSub),
              ],
            ),
          ),
          SizedBox(width: 10 * scale),
          right,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final a = entry.anime!;
    return Semantics(
      button: true,
      label: '${a.title(HikkaPrefs.instance.titleLang)}. ${meta.replaceAll('★', 'оцінка')}${showScore && entry.score > 0 ? '. Моя оцінка ${entry.score}' : ''}',
      excludeSemantics: true,
      child: InkWell(
        onTap: () => HikkaNav.instance.openAnime(a.slug, seed: a),
        onLongPress: () => unawaited(_menu(context)),
        onSecondaryTapDown: (d) => unawaited(_menu(context, at: d.globalPosition)),
        splashColor: Colors.transparent,
        highlightColor: uiTheme.touchHighlight,
        hoverColor: uiTheme.hoverOverlay,
        child: _content(),
      ),
    );
  }
}
