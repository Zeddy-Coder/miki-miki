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
import 'hikka_cards.dart';
import 'hikka_common.dart';
import 'hikka_markdown_view.dart';
import 'hikka_page_kit.dart';

/// Сторінка персонажа: портрет, імена, опис (зі спойлерами), озвучення й аніме, де він з'являється.
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

  // ── Шапка ──────────────────────────────────────────────────────────────────

  Widget _names(HikkaCharacter c, {required bool wide}) {
    final scale = _scale;
    final others = c.otherNames;
    final synonyms = [
      for (final s in c.synonyms)
        if (s.toLowerCase() != c.name.toLowerCase() && !others.any((o) => o.toLowerCase() == s.toLowerCase())) s,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(c.name, style: hikkaStyle((wide ? 24 : 19) * scale, weight: FontWeight.bold, height: 1.2)),
        if (others.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(top: 6 * scale),
            child: Text(others.join('\n'), style: hikkaStyle(12.5 * scale, color: uiTheme.textMuted, height: 1.35)),
          ),
        if (synonyms.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(top: 6 * scale),
            child: Text(
              synonyms.take(6).join(', '),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: hikkaStyle(11.5 * scale, color: uiTheme.textDarkMuted, height: 1.35),
            ),
          ),
        if (_full != null && (_full!.animeCount > 0 || _full!.voicesCount > 0))
          Padding(
            padding: EdgeInsets.only(top: 12 * scale),
            child: Wrap(
              spacing: 8 * scale,
              runSpacing: 6 * scale,
              children: [
                if (_full!.animeCount > 0) HikkaChip(label: 'Аніме: ${HikkaText.count(_full!.animeCount)}', scale: scale),
                if (_full!.voicesCount > 0) HikkaChip(label: 'Озвучень: ${HikkaText.count(_full!.voicesCount)}', scale: scale),
              ],
            ),
          ),
      ],
    );
  }

  Widget _description() {
    final scale = _scale;
    final c = _full;
    final Widget body;
    if (c == null) {
      body = _error != null ? HikkaErrorView(scale: scale, error: _error!, onRetry: _retry, compact: true) : HikkaLoading(scale: scale, height: 90);
    } else if (c.descriptionUa == null) {
      body = Text('Опису поки немає.', style: hikkaStyle(13 * scale, color: uiTheme.textMuted));
    } else {
      body = HikkaCollapsible(
        collapsedHeight: 190 * scale,
        scale: scale,
        fadeColor: uiTheme.bgPrimary,
        child: HikkaMarkdownView(source: c.descriptionUa, scale: scale),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Опис', style: hikkaStyle(13.5 * scale, weight: FontWeight.bold)),
        SizedBox(height: 8 * scale),
        body,
      ],
    );
  }

  /// Озвучення за мовами: японська, українська, англійська, далі за абеткою; люди без повторів
  Widget _voices(double pad) {
    final scale = _scale;
    return HikkaAsync<HikkaPage<HikkaCharacterVoice>>(
      key: ValueKey('voices-${_route.id}'),
      scale: scale,
      compactError: true,
      load: () => HikkaApi.instance.characterVoices(_route.slug, size: 100, allowAdult: HikkaPrefs.instance.allowAdult),
      loading: (context) => const SizedBox.shrink(),
      builder: (context, page) {
        final groups = HikkaCharacterVoice.groupByLanguage(page.items);
        if (groups.isEmpty) return const SizedBox.shrink();
        return HikkaSection(
          scale: scale,
          pad: pad,
          title: 'Озвучення',
          child: Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: hikkaReadableWidth(scale)),
              child: AppCard(
                scale: scale,
                radius: 12,
                padding: EdgeInsets.symmetric(horizontal: 14 * scale, vertical: 6 * scale),
                child: Column(
                  children: [
                    for (int i = 0; i < groups.length; i++) ...[
                      if (i > 0) Divider(height: 1, color: uiTheme.borderSubtle),
                      _voiceRow(groups[i].$1, groups[i].$2),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _voiceRow(String language, List<String> people) {
    final scale = _scale;
    const limit = 10;
    final text = people.length > limit ? '${people.take(limit).join(', ')} та ще ${people.length - limit}' : people.join(', ');
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 9 * scale),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 108 * scale, child: Text(language, style: hikkaStyle(12 * scale, color: uiTheme.textDarkMuted, height: 1.35))),
          Expanded(child: Text(text, style: hikkaStyle(12.5 * scale, height: 1.35))),
        ],
      ),
    );
  }

  Widget _header(HikkaCharacter c, double pad) {
    final scale = _scale;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= hikkaWideBreakpoint;
        final posterW = hikkaHeaderPosterWidth(scale, wide: wide);
        final poster = SizedBox(
          width: posterW,
          child: HikkaPoster(url: c.image, scale: scale, radius: 12, icon: Symbols.person_rounded),
        );
        return Padding(
          padding: EdgeInsets.fromLTRB(pad, 4 * scale, pad, 22 * scale),
          child: wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    poster,
                    SizedBox(width: 28 * scale),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [_names(c, wide: true), SizedBox(height: 18 * scale), _description()],
                      ),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [poster, SizedBox(width: 14 * scale), Expanded(child: _names(c, wide: false))],
                    ),
                    SizedBox(height: 18 * scale),
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
                subtitle: _pager.total > 0 ? 'Усього: ${HikkaText.count(_pager.total)}' : null,
              ),
            ),
          ),
        ],
      ),
      itemBuilder: (context, e) => HikkaAnimeCard(
        anime: e.anime,
        scale: scale,
        caption: [
          e.main ? 'Головний' : 'Другорядний',
          if (e.anime.year != null) '${e.anime.year}',
        ].join(' · '),
      ),
    );
  }
}
