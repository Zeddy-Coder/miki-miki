import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../models/hikka_models.dart';
import '../../services/hikka_api.dart';
import '../../services/hikka_nav.dart';
import '../../services/hikka_pager.dart';
import '../../services/hikka_prefs.dart';
import '../../services/ui_theme_service.dart';
import '../app_animation_kit.dart';
import 'hikka_cards.dart';
import 'hikka_common.dart';
import 'hikka_markdown_view.dart';
import 'hikka_page_kit.dart';

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

  @override
  Widget build(BuildContext context) {
    final scale = widget.scale;
    return HikkaPagedGrid<HikkaStaff>(
      pager: _pager,
      scale: scale,
      controller: _scroll,
      bottomInset: widget.bottomInset,
      maxTileWidth: 150,
      emptyIcon: Symbols.groups_rounded,
      emptyText: 'Для цього аніме ще немає знімальної групи',
      itemBuilder: (context, s) => HikkaPersonCard(person: s.person, scale: scale, caption: s.rolesLabel),
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
    if (p != null && p.animeCount == 0 && p.charactersCount > 0) return 'characters';
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

  Widget _names(HikkaPerson p, {required bool wide}) {
    final scale = _scale;
    final others = p.otherNames;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(p.name, style: hikkaStyle((wide ? 24 : 19) * scale, weight: FontWeight.bold, height: 1.2)),
        if (others.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(top: 6 * scale),
            child: Text(others.join('\n'), style: hikkaStyle(12.5 * scale, color: uiTheme.textMuted, height: 1.35)),
          ),
        if (p.synonyms.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(top: 6 * scale),
            child: Text(
              p.synonyms.take(6).join(', '),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: hikkaStyle(11.5 * scale, color: uiTheme.textDarkMuted, height: 1.35),
            ),
          ),
      ],
    );
  }

  Widget _description(HikkaPerson p) {
    final scale = _scale;
    final text = p.descriptionUa;
    if (text == null) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(top: 18 * scale),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Опис', style: hikkaStyle(13.5 * scale, weight: FontWeight.bold)),
          SizedBox(height: 8 * scale),
          HikkaCollapsible(
            collapsedHeight: 190 * scale,
            scale: scale,
            fadeColor: uiTheme.bgPrimary,
            child: HikkaMarkdownView(source: text, scale: scale),
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
        final posterW = hikkaHeaderPosterWidth(scale, wide: wide);
        final poster = SizedBox(width: posterW, child: HikkaPoster(url: p.image, scale: scale, radius: 12, icon: Symbols.person_rounded));
        return Padding(
          padding: EdgeInsets.fromLTRB(pad, 4 * scale, pad, 18 * scale),
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
                      children: [poster, SizedBox(width: 14 * scale), Expanded(child: _names(p, wide: false))],
                    ),
                    _description(p),
                  ],
                ),
        );
      },
    );
  }

  /// "Аніме · N" and "Персонажі · N": shown only when there is something to switch
  Widget _tabs(HikkaPerson p, double pad) {
    final scale = _scale;
    final tabs = <(String, String)>[
      if (p.animeCount > 0 || p.charactersCount == 0) ('anime', 'Аніме${p.animeCount > 0 ? ' · ${HikkaText.count(p.animeCount)}' : ''}'),
      if (p.charactersCount > 0) ('characters', 'Озвучені персонажі · ${HikkaText.count(p.charactersCount)}'),
    ];
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 0, pad, 12 * scale),
      child: Wrap(
        spacing: 8 * scale,
        runSpacing: 8 * scale,
        children: [
          for (final t in tabs) HikkaChip(label: t.$2, scale: scale, selected: _activeTab == t.$1, onTap: () => _pick(t.$1)),
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
