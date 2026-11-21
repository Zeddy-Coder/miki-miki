import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../models/hikka_models.dart';
import '../../services/hikka_api.dart';
import '../../services/hikka_nav.dart';
import '../../services/hikka_pager.dart';
import '../../services/hikka_prefs.dart';
import '../../services/ui_theme_service.dart';
import '../app_animation_kit.dart';
import '../app_ui_kit.dart';
import '../design_kit.dart' show AppMediaRow;
import '../line_icons.dart';
import 'hikka_cards.dart';
import 'hikka_common.dart';
import 'hikka_markdown_view.dart';
import 'hikka_page_kit.dart';

/// Character page: portrait, names, description (with spoilers), voice acting and the anime where they appear.
class HikkaCharacterPage extends StatefulWidget {
  final HikkaRoute route;
  final double scale;
  final double bottomInset;

  const HikkaCharacterPage({super.key, required this.route, required this.scale, this.bottomInset = 0});

  @override
  State<HikkaCharacterPage> createState() => _HikkaCharacterPageState();
}

class _HikkaCharacterPageState extends State<HikkaCharacterPage> {
  late final ScrollController _scroll = AppSmoothScrollController(initialScrollOffset: widget.route.scroll);
  late final HikkaPager<HikkaCharacterAnime> _pager;
  HikkaCharacter? _full;
  Object? _error;
  int _generation = 0;

  HikkaRoute get _route => widget.route;
  HikkaCharacter? get _seed => _route.seed is HikkaCharacter ? _route.seed as HikkaCharacter : null;
  double get _scale => widget.scale;

  @override
  void initState() {
    super.initState();
    final cachedPager = _route.memo['pager'];
    if (cachedPager is HikkaPager<HikkaCharacterAnime>) {
      _pager = cachedPager;
    } else {
      _pager = HikkaPager<HikkaCharacterAnime>(
        (page) => HikkaApi.instance.characterAnime(_route.slug, page: page, size: 30, allowAdult: HikkaPrefs.instance.allowAdult),
        keyOf: (e) => e.anime.slug,
      );
      _route.memo['pager'] = _pager;
    }
    if (_pager.items.isEmpty && !_pager.loading && _pager.error == null) _pager.reload();

    final cached = _route.memo['character'];
    if (cached is HikkaCharacter) {
      _full = cached;
    } else {
      _load();
    }
    _scroll.addListener(_saveScroll);
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
    HikkaApi.instance.character(_route.slug).then<void>((c) {
      if (!mounted || gen != _generation) return;
      _route.memo['character'] = c;
      setState(() {
        _full = c;
        _error = null;
      });
    }, onError: (Object e) {
      if (!mounted || gen != _generation) return;
      setState(() => _error = e);
    });
  }

  void _retry() {
    setState(() => _error = null);
    _load();
  }

  // ── Header ──────────────────────────────────────────────────────────────────

  /// Name, the other spellings in grey, then quietly "5 аніме" and "6 озвучень" with line icons
  Widget _names(HikkaCharacter c, {required bool wide}) {
    final scale = _scale;
    final others = c.otherNames;
    final synonyms = [
      for (final s in c.synonyms)
        if (s.toLowerCase() != c.name.toLowerCase() && !others.any((o) => o.toLowerCase() == s.toLowerCase())) s,
    ];
    final full = _full;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(c.name, style: hikkaStyle((wide ? 26 : 22) * scale, weight: FontWeight.bold, height: 1.2)),
        if (others.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(top: 5 * scale),
            child: Text(others.join(' · '), style: hikkaStyle(13 * scale, color: uiTheme.textMuted, height: 1.35)),
          ),
        if (synonyms.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(top: 4 * scale),
            child: Text(
              synonyms.take(6).join(', '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: hikkaStyle(12 * scale, color: uiTheme.textDarkMuted, height: 1.35),
            ),
          ),
        if (full != null && (full.animeCount > 0 || full.voicesCount > 0))
          Padding(
            padding: EdgeInsets.only(top: 14 * scale),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (full.animeCount > 0) hikkaCountLine(scale, LineIcon.monitor, '${HikkaText.count(full.animeCount)} аніме'),
                if (full.animeCount > 0 && full.voicesCount > 0) SizedBox(height: 7 * scale),
                if (full.voicesCount > 0)
                  hikkaCountLine(scale, LineIcon.mic, '${HikkaText.count(full.voicesCount)} ${HikkaText.plural(full.voicesCount, 'озвучення', 'озвучення', 'озвучень')}'),
              ],
            ),
          ),
      ],
    );
  }

  /// The description as on the title page: four lines fading out and «Читати далі ⌄»; links work only when it is open
  Widget _description() {
    final scale = _scale;
    final c = _full;
    final Widget body;
    if (c == null) {
      body = _error != null ? HikkaErrorView(scale: scale, error: _error!, onRetry: _retry, compact: true) : HikkaLoading(scale: scale, height: 90);
    } else if (c.descriptionUa == null) {
      body = Text('Опису поки немає.', style: hikkaStyle(13 * scale, color: uiTheme.textMuted, height: 1.5));
    } else {
      body = HikkaSynopsis(
        source: c.descriptionUa!,
        scale: scale,
        open: _route.memo['synopsis'] == true,
        onOpen: (v) => _route.memo['synopsis'] = v,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Опис', style: hikkaStyle(15 * scale, weight: FontWeight.bold)),
        SizedBox(height: 6 * scale),
        body,
      ],
    );
  }

  /// Voice actors one by one: a round photo, the name, the language and the number of anime; a tap opens the person
  Widget _voices(double pad) {
    final scale = _scale;
    return HikkaAsync<HikkaPage<HikkaCharacterVoice>>(
      key: ValueKey('voices-${_route.id}'),
      scale: scale,
      compactError: true,
      load: () => HikkaApi.instance.characterVoices(_route.slug, size: 100, allowAdult: HikkaPrefs.instance.allowAdult),
      loading: (context) => const SizedBox.shrink(),
      builder: (context, page) {
        final actors = HikkaCharacterVoice.actors(page.items);
        if (actors.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: EdgeInsets.only(bottom: 14 * scale),
          child: Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: hikkaReadableWidth(scale) + pad * 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(pad, 0, pad, 4 * scale),
                    child: Text('Озвучення', style: hikkaStyle(15 * scale, weight: FontWeight.bold)),
                  ),
                  for (final a in actors.take(12))
                    AppMediaRow(
                      key: ValueKey('voice-${a.person.slug}-${a.language}'),
                      scale: scale,
                      inset: pad,
                      leading: HikkaAvatar(url: a.person.image, size: 42 * scale, scale: scale),
                      title: a.person.name,
                      subtitle: '${a.language} · ${a.anime} аніме',
                      titleLines: 1,
                      chevron: true,
                      onTap: () => HikkaNav.instance.openPerson(a.person.slug, seed: a.person, roles: true),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _header(HikkaCharacter c, double pad) {
    final scale = _scale;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= hikkaWideBreakpoint;
        final posterW = wide ? hikkaHeaderPosterWidth(scale, wide: true) : 112 * scale;
        final poster = SizedBox(
          width: posterW,
          child: HikkaPoster(url: c.image, scale: scale, radius: 14, aspect: 112 / 158, icon: Symbols.person_rounded),
        );
        return Padding(
          padding: EdgeInsets.fromLTRB(pad, 6 * scale, pad, 20 * scale),
          child: wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    poster,
                    SizedBox(width: 28 * scale),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [_names(c, wide: true), SizedBox(height: 22 * scale), _description()],
                      ),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [poster, SizedBox(width: 16 * scale), Expanded(child: Padding(padding: EdgeInsets.only(top: 4 * scale), child: _names(c, wide: false)))],
                    ),
                    SizedBox(height: 20 * scale),
                    _description(),
                  ],
                ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final scale = _scale;
    final c = _full ?? _seed;
    if (c == null) {
      return _error != null ? HikkaErrorView(scale: scale, error: _error!, onRetry: _retry) : HikkaLoading(scale: scale, height: 320);
    }
    final pad = HikkaLayout.sidePad(context, scale);

    return HikkaPagedGrid<HikkaCharacterAnime>(
      pager: _pager,
      scale: scale,
      controller: _scroll,
      bottomInset: widget.bottomInset,
      maxTileWidth: 150,
      emptyIcon: Symbols.movie_rounded,
      emptyText: 'Аніме з цим персонажем не знайдено',
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(c, pad),
          _voices(pad),
          ListenableBuilder(
            listenable: _pager,
            builder: (context, _) => Padding(
              padding: EdgeInsets.fromLTRB(pad, 0, pad, 10 * scale),
              child: AppSectionHeader(
                scale: scale,
                title: 'Аніме',
                titleSize: 15,
                calm: true,
                subtitle: _pager.total > 0 ? '${HikkaText.count(_pager.total)} ${HikkaText.plural(_pager.total, 'тайтл', 'тайтли', 'тайтлів')}' : null,
              ),
            ),
          ),
        ],
      ),
      itemBuilder: (context, e) => HikkaAnimeCard(
        anime: e.anime,
        scale: scale,
        caption: [
          e.main ? 'Головна' : 'Другорядна',
          if (e.anime.year != null) '${e.anime.year}',
        ].join(' · '),
      ),
    );
  }
}
