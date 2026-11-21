import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../models/hikka_models.dart';
import '../../services/hikka_api.dart';
import '../../services/hikka_nav.dart';
import '../../services/hikka_pager.dart';
import '../../services/hikka_prefs.dart';
import '../../services/ui_theme_service.dart';
import '../app_animation_kit.dart';
import '../design_kit.dart' show AppMediaRow, AppPillTab;
import '../line_icons.dart';
import 'hikka_cards.dart';
import 'hikka_common.dart';
import 'hikka_markdown_view.dart';
import 'hikka_page_kit.dart';
import 'hikka_paged_list.dart';

/// The whole crew of an anime: a grid of portraits with roles
class HikkaAnimeStaffPage extends StatefulWidget {
  final HikkaRoute route;
  final double scale;
  final double bottomInset;

  const HikkaAnimeStaffPage({super.key, required this.route, required this.scale, this.bottomInset = 0});

  @override
  State<HikkaAnimeStaffPage> createState() => _HikkaAnimeStaffPageState();
}

class _HikkaAnimeStaffPageState extends State<HikkaAnimeStaffPage> {
  late final ScrollController _scroll = AppSmoothScrollController(initialScrollOffset: widget.route.scroll);
  late final HikkaPager<HikkaStaff> _pager;

  @override
  void initState() {
    super.initState();
    final cached = widget.route.memo['pager'];
    if (cached is HikkaPager<HikkaStaff>) {
      _pager = cached;
    } else {
      _pager = HikkaPager<HikkaStaff>(
        (page) => HikkaApi.instance.animeStaff(widget.route.slug, page: page, size: 30),
        keyOf: (s) => s.person.slug,
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

  /// "Режисер епізодів · Розкадрування · ще 2": the first three roles, the rest as a number
  static String rolesOf(HikkaStaff s) {
    final names = [for (final r in s.roles) r.name];
    if (names.length <= 3) return names.join(' · ');
    return '${names.take(3).join(' · ')} · ще ${names.length - 3}';
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.scale;
    final pad = HikkaLayout.sidePad(context, scale);
    final a = widget.route.memo['anime'] ?? widget.route.seed;
    final title = a is HikkaAnime ? a.title(HikkaPrefs.instance.titleLang) : null;
    return HikkaPagedList<HikkaStaff>(
      pager: _pager,
      scale: scale,
      controller: _scroll,
      bottomInset: widget.bottomInset,
      flush: true,
      emptyIcon: Symbols.groups_rounded,
      emptyText: 'Для цього аніме ще немає знімальної групи',
      header: ListenableBuilder(
        listenable: _pager,
        builder: (context, _) => HikkaLeadLine(scale: scale, pad: pad, parts: [if (title != null) title, if (_pager.total > 0) HikkaText.count(_pager.total)]),
      ),
      itemBuilder: (context, s) => AppMediaRow(
        key: ValueKey('staff-${s.person.slug}'),
        scale: scale,
        inset: pad,
        leading: HikkaAvatar(url: s.person.image, size: 46 * scale, scale: scale),
        title: s.person.name,
        subtitle: rolesOf(s),
        titleLines: 1,
        onTap: () => HikkaNav.instance.openPerson(s.person.slug, seed: s.person),
      ),
    );
  }
}

/// Person page: a portrait, names, description and a list of works: anime with roles and voiced characters
class HikkaPersonPage extends StatefulWidget {
  final HikkaRoute route;
  final double scale;
  final double bottomInset;

  const HikkaPersonPage({super.key, required this.route, required this.scale, this.bottomInset = 0});

  @override
  State<HikkaPersonPage> createState() => _HikkaPersonPageState();
}

class _HikkaPersonPageState extends State<HikkaPersonPage> {
  late final ScrollController _scroll = AppSmoothScrollController(initialScrollOffset: widget.route.scroll);
  late final HikkaPager<HikkaPersonAnime> _animePager;
  late final HikkaPager<HikkaPersonCharacter> _charPager;
  HikkaPerson? _full;
  Object? _error;
  int _generation = 0;

  HikkaRoute get _route => widget.route;
  HikkaPerson? get _seed => _route.seed is HikkaPerson ? _route.seed as HikkaPerson : null;
  double get _scale => widget.scale;

  /// Which tab is open: `anime` or `characters`; empty means chosen by the counters
  String? get _tab => _route.memo['tab'] as String?;

  @override
  void initState() {
    super.initState();
    final a = _route.memo['animePager'];
    if (a is HikkaPager<HikkaPersonAnime>) {
      _animePager = a;
    } else {
      _animePager = HikkaPager<HikkaPersonAnime>(
        (page) => HikkaApi.instance.personAnime(_route.slug, page: page, size: 30, allowAdult: HikkaPrefs.instance.allowAdult),
        keyOf: (e) => e.anime.slug,
      );
      _route.memo['animePager'] = _animePager;
    }
    final c = _route.memo['charPager'];
    if (c is HikkaPager<HikkaPersonCharacter>) {
      _charPager = c;
    } else {
      _charPager = HikkaPager<HikkaPersonCharacter>(
        (page) => HikkaApi.instance.personCharacters(_route.slug, page: page, size: 30, allowAdult: HikkaPrefs.instance.allowAdult),
        keyOf: (e) => '${e.character.slug}/${e.anime.slug}',
      );
      _route.memo['charPager'] = _charPager;
    }
    final cached = _route.memo['person'];
    if (cached is HikkaPerson) {
      _full = cached;
    } else {
      _load();
    }
    _scroll.addListener(_saveScroll);
    _loadActive();
  }

  @override
  void dispose() {
    _scroll.removeListener(_saveScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _saveScroll() {
    if (_scroll.hasClients) _route.scroll = _scroll.offset;
  }

  void _load() {
    final gen = ++_generation;
    HikkaApi.instance.person(_route.slug).then<void>((p) {
      if (!mounted || gen != _generation) return;
      _route.memo['person'] = p;
      setState(() {
        _full = p;
        _error = null;
      });
      _loadActive();
    }, onError: (Object e) {
      if (!mounted || gen != _generation) return;
      setState(() => _error = e);
    });
  }

  void _retry() {
    setState(() => _error = null);
    _load();
  }

  /// While there are no counters the "Аніме" tab is open; after the response, the one where the person has works
  String get _activeTab {
    final t = _tab;
    if (t != null) return t;
    final p = _full;
    if (p != null && p.charactersCount > p.animeCount) return 'characters';
    return 'anime';
  }

  void _loadActive() {
    final pager = _activeTab == 'characters' ? _charPager : _animePager;
    if (pager.items.isEmpty && !pager.loading && pager.error == null) pager.reload();
  }

  void _pick(String tab) {
    if (tab == _activeTab) return;
    setState(() => _route.memo['tab'] = tab);
    _loadActive();
  }

  /// Name, the other spellings in grey, then quietly "303 персонажі" and "10 аніме" with line icons
  Widget _names(HikkaPerson p, {required bool wide}) {
    final scale = _scale;
    final others = p.otherNames;
    final full = _full;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(p.name, style: hikkaStyle((wide ? 26 : 22) * scale, weight: FontWeight.bold, height: 1.2)),
        if (others.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(top: 5 * scale),
            child: Text(others.join(' · '), style: hikkaStyle(13 * scale, color: uiTheme.textMuted, height: 1.35)),
          ),
        if (p.synonyms.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(top: 4 * scale),
            child: Text(
              p.synonyms.take(6).join(', '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: hikkaStyle(12 * scale, color: uiTheme.textDarkMuted, height: 1.35),
            ),
          ),
        if (full != null && (full.charactersCount > 0 || full.animeCount > 0))
          Padding(
            padding: EdgeInsets.only(top: 14 * scale),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (full.charactersCount > 0)
                  hikkaCountLine(scale, LineIcon.face, '${HikkaText.count(full.charactersCount)} ${HikkaText.plural(full.charactersCount, 'персонаж', 'персонажі', 'персонажів')}'),
                if (full.charactersCount > 0 && full.animeCount > 0) SizedBox(height: 7 * scale),
                if (full.animeCount > 0) hikkaCountLine(scale, LineIcon.monitor, '${HikkaText.count(full.animeCount)} аніме'),
              ],
            ),
          ),
      ],
    );
  }

  /// The description as on the title page (when there is one)
  Widget _description(HikkaPerson p) {
    final scale = _scale;
    final text = p.descriptionUa;
    if (text == null) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(top: 20 * scale),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Опис', style: hikkaStyle(15 * scale, weight: FontWeight.bold)),
          SizedBox(height: 6 * scale),
          HikkaSynopsis(
            source: text,
            scale: scale,
            open: _route.memo['synopsis'] == true,
            onOpen: (v) => _route.memo['synopsis'] = v,
          ),
        ],
      ),
    );
  }

  Widget _header(HikkaPerson p, double pad) {
    final scale = _scale;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= hikkaWideBreakpoint;
        final posterW = wide ? hikkaHeaderPosterWidth(scale, wide: true) : 112 * scale;
        final poster = SizedBox(width: posterW, child: HikkaPoster(url: p.image, scale: scale, radius: 14, aspect: 112 / 158, icon: Symbols.person_rounded));
        return Padding(
          padding: EdgeInsets.fromLTRB(pad, 6 * scale, pad, 18 * scale),
          child: wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    poster,
                    SizedBox(width: 28 * scale),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_names(p, wide: true), _description(p)])),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [poster, SizedBox(width: 16 * scale), Expanded(child: Padding(padding: EdgeInsets.only(top: 4 * scale), child: _names(p, wide: false)))],
                    ),
                    _description(p),
                  ],
                ),
        );
      },
    );
  }

  /// "Ролі 303" and "Аніме 10" as pill tabs (as in "Списки"); shown only when there is something to switch
  Widget _tabs(HikkaPerson p, double pad) {
    final scale = _scale;
    final tabs = <(String, String, LineIcon, int)>[
      if (p.charactersCount > 0) ('characters', 'Ролі', LineIcon.face, p.charactersCount),
      if (p.animeCount > 0 || p.charactersCount == 0) ('anime', 'Аніме', LineIcon.monitor, p.animeCount),
    ];
    // The larger list first (a voice actor's roles, a director's anime), as it is also the one open by default
    if (tabs.length == 2 && p.animeCount >= p.charactersCount) tabs.insert(0, tabs.removeAt(1));
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 0, pad, 14 * scale),
      child: Wrap(
        spacing: 8 * scale,
        runSpacing: 8 * scale,
        children: [
          for (final t in tabs)
            AppPillTab(
              key: ValueKey('person-tab-${t.$1}'),
              scale: scale,
              label: t.$2,
              count: t.$4 > 0 ? HikkaText.count(t.$4) : null,
              selected: _activeTab == t.$1,
              icon: (c) => LineIconView(t.$3, size: 16 * scale, color: c),
              onTap: () => _pick(t.$1),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scale = _scale;
    final p = _full ?? _seed;
    if (p == null) {
      return _error != null ? HikkaErrorView(scale: scale, error: _error!, onRetry: _retry) : HikkaLoading(scale: scale, height: 320);
    }
    final pad = HikkaLayout.sidePad(context, scale);
    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [_header(p, pad), _tabs(p, pad)],
    );

    if (_activeTab == 'characters') {
      return HikkaPagedGrid<HikkaPersonCharacter>(
        key: const ValueKey('person-characters'),
        pager: _charPager,
        scale: scale,
        controller: _scroll,
        bottomInset: widget.bottomInset,
        maxTileWidth: 150,
        emptyIcon: Symbols.person_search_rounded,
        emptyText: 'Озвучених персонажів не знайдено',
        header: header,
        itemBuilder: (context, e) => HikkaCharacterCard(
          character: e.character,
          scale: scale,
          caption: e.anime.title(HikkaPrefs.instance.titleLang),
        ),
      );
    }
    return HikkaPagedGrid<HikkaPersonAnime>(
      key: const ValueKey('person-anime'),
      pager: _animePager,
      scale: scale,
      controller: _scroll,
      bottomInset: widget.bottomInset,
      maxTileWidth: 150,
      emptyIcon: Symbols.movie_rounded,
      emptyText: 'Аніме з цією людиною не знайдено',
      header: header,
      itemBuilder: (context, e) => HikkaAnimeCard(
        anime: e.anime,
        scale: scale,
        caption: [if (e.rolesLabel.isNotEmpty) e.rolesLabel, if (e.anime.year != null) '${e.anime.year}'].join(' · '),
      ),
    );
  }
}
