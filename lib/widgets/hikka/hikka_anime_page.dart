import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../models/hikka_models.dart';
import '../../services/hikka_api.dart';
import '../../services/hikka_franchise.dart';
import '../../services/hikka_nav.dart';
import '../../services/hikka_prefs.dart';
import '../../services/ui_theme_service.dart';
import '../app_animation_kit.dart';
import '../app_ui_kit.dart';
import 'hikka_banner.dart';
import 'hikka_cards.dart';
import 'hikka_common.dart';
import 'hikka_markdown_view.dart';
import 'hikka_my_list_bar.dart';
import 'hikka_page_kit.dart';
import 'hikka_shelf.dart';
import 'hikka_watch_dialogs.dart';
import 'hikka_watch_section.dart';

/// Сторінка аніме: шапка (з даних списку — одразу), опис, інформація, персонажі, франшиза,
/// рекомендації, автори, посилання, відео та музика. Повні дані підвантажуються окремо.
class HikkaAnimePage extends StatefulWidget {
  final HikkaRoute route;
  final double scale;
  final double bottomInset;

  const HikkaAnimePage({super.key, required this.route, required this.scale, this.bottomInset = 0});

  @override
  State<HikkaAnimePage> createState() => _HikkaAnimePageState();
}

class _HikkaAnimePageState extends State<HikkaAnimePage> {
  late final ScrollController _scroll = AppSmoothScrollController(initialScrollOffset: widget.route.scroll);
  HikkaAnime? _full;
  Object? _error;
  int _generation = 0;

  HikkaRoute get _route => widget.route;
  HikkaAnime? get _seed => _route.seed is HikkaAnime ? _route.seed as HikkaAnime : null;

  bool get _revealed => _route.memo['revealed'] == true;
  bool get _staffExpanded => _route.memo['staff'] == true;
  bool get _ostExpanded => _route.memo['ost'] == true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_saveScroll);
    final cached = _route.memo['anime'];
    if (cached is HikkaAnime) {
      _full = cached;
    } else {
      _load();
    }
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
    HikkaApi.instance.anime(_route.slug).then<void>((a) {
      if (!mounted || gen != _generation) return;
      _route.memo['anime'] = a;
      setState(() {
        _full = a;
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

  void _toggle(String key) => setState(() => _route.memo[key] = _route.memo[key] != true);

  // ── Шапка ──────────────────────────────────────────────────────────────────

  double get _scale => widget.scale;

  Widget _poster(HikkaAnime a) => HikkaPoster(url: a.image, malId: a.malId, scale: _scale, radius: 12, icon: Symbols.movie_rounded);

  Widget _titleBlock(HikkaAnime a, {required bool wide}) {
    final scale = _scale;
    final lang = HikkaPrefs.instance.titleLang;
    final prefs = HikkaPrefs.instance;
    final second = prefs.showSecondary ? a.secondaryTitle(lang, prefs.secondaryLang) : null;
    final meta = [a.typeLabel, a.seasonLabel, a.episodesLabel].where((s) => s.isNotEmpty).join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(a.title(lang), style: hikkaStyle((wide ? 24 : 19) * scale, weight: FontWeight.bold, height: 1.2)),
        if (second != null)
          Padding(
            padding: EdgeInsets.only(top: 6 * scale),
            child: Text(second, maxLines: 2, overflow: TextOverflow.ellipsis, style: hikkaStyle(12.5 * scale, color: uiTheme.textMuted, height: 1.35)),
          ),
        SizedBox(height: 10 * scale),
        Wrap(
          spacing: 8 * scale,
          runSpacing: 6 * scale,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (a.statusLabel.isNotEmpty) HikkaChip(label: a.statusLabel, scale: scale, highlight: a.isOngoing),
            if (a.isAdult) HikkaPill(text: '18+', scale: scale * 1.1, background: const Color(0xE6C62828)),
            if (meta.isNotEmpty) Text(meta, style: hikkaStyle(12.5 * scale, color: uiTheme.textMuted)),
          ],
        ),
      ],
    );
  }

  Widget _genres(HikkaAnime a) {
    final adult = HikkaPrefs.instance.allowAdult;
    final genres = a.genres.where((g) => adult || !g.isExplicit).toList();
    if (genres.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(bottom: 14 * _scale),
      child: Wrap(
        spacing: 8 * _scale,
        runSpacing: 8 * _scale,
        children: [
          for (final g in genres)
            HikkaChip(
              label: g.name,
              scale: _scale,
              onTap: () => HikkaNav.instance.openCatalog(HikkaSearchFilters(genres: {g.slug})),
            ),
        ],
      ),
    );
  }

  Widget _scoreTile(String label, double score, int votes) {
    final scale = _scale;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(Symbols.star_rounded, color: const Color(0xFFFFC23D), size: 18 * scale, fill: 1),
        SizedBox(width: 4 * scale),
        Text(score.toStringAsFixed(2), style: hikkaStyle(14 * scale, weight: FontWeight.bold)),
        SizedBox(width: 6 * scale),
        Text('$label · ${HikkaText.count(votes)}', style: hikkaStyle(11 * scale, color: uiTheme.textDarkMuted)),
      ],
    );
  }

  Widget _scores(HikkaAnime a) {
    final tiles = <Widget>[
      if (a.hasScore) _scoreTile('MAL', a.score, a.scoredBy),
      if (a.nativeScore > 0 && a.nativeScoredBy > 0) _scoreTile('Hikka', a.nativeScore, a.nativeScoredBy),
    ];
    if (tiles.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(bottom: 12 * _scale),
      child: Wrap(spacing: 18 * _scale, runSpacing: 6 * _scale, children: tiles),
    );
  }

  Widget _nextEpisode(HikkaAnime a) {
    final now = DateTime.now();
    final slot = a.nextEpisode(now);
    if (slot == null) return const SizedBox.shrink();
    final scale = _scale;
    return Padding(
      padding: EdgeInsets.only(bottom: 14 * scale),
      child: Align(
        alignment: Alignment.centerLeft,
        child: AppCard(
          scale: scale,
          radius: 10,
          padding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 9 * scale),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Symbols.schedule_rounded, color: uiTheme.accentColor, size: 22 * scale, weight: 300),
              SizedBox(width: 10 * scale),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Наступна серія', style: hikkaStyle(11.5 * scale, color: uiTheme.textDarkMuted)),
                    Text(
                      '${slot.episode} · ${HikkaText.airingLabel(slot.time, now)}',
                      style: hikkaStyle(13.5 * scale, weight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _synopsis(HikkaAnime a) {
    final scale = _scale;
    final text = a.synopsis;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Опис', style: hikkaStyle(13.5 * scale, weight: FontWeight.bold)),
        SizedBox(height: 8 * scale),
        if (text == null)
          Text('Опису поки немає.', style: hikkaStyle(13 * scale, color: uiTheme.textMuted))
        else ...[
          HikkaCollapsible(
            collapsedHeight: 170 * scale,
            scale: scale,
            fadeColor: uiTheme.bgPrimary,
            child: HikkaMarkdownView(source: text, scale: scale),
          ),
          if (a.synopsisUa == null)
            Padding(
              padding: EdgeInsets.only(top: 6 * scale),
              child: Text('Опис англійською: українського поки немає.', style: hikkaStyle(11.5 * scale, color: uiTheme.textDarkMuted)),
            ),
        ],
      ],
    );
  }

  static String _dates(HikkaAnime a) {
    DateTime? at(int? s) => s == null || s <= 0 ? null : DateTime.fromMillisecondsSinceEpoch(s * 1000);
    final start = at(a.startDate);
    final end = at(a.endDate);
    if (start == null) return '';
    String f(DateTime t) => HikkaText.dayMonth(t, withYear: true);
    if (end == null) return a.isOngoing || a.isAnnounced ? 'з ${f(start)}' : f(start);
    final same = start.year == end.year && start.month == end.month && start.day == end.day;
    return same ? f(start) : '${f(start)} — ${f(end)}';
  }

  List<(String, String)> _infoRows(HikkaAnime a) {
    final rating = a.rating;
    final hint = rating == null ? null : HikkaText.ratingHints[rating];
    return [
      ('Тип', a.typeLabel),
      ('Статус', a.statusLabel),
      ('Сезон', a.seasonLabel),
      ('Серії', a.episodesLabel),
      ('Тривалість', a.durationLabel),
      ('Вихід', _dates(a)),
      ('Джерело', HikkaText.source(a.source)),
      (a.studios.length > 1 ? 'Студії' : 'Студія', a.studios.map((s) => s.name).join(', ')),
      ('Вікова категорія', rating == null ? '' : (hint == null ? HikkaText.rating(rating) : '${HikkaText.rating(rating)}: $hint')),
    ];
  }

  Widget _info(HikkaAnime a) => HikkaInfoTable(scale: _scale, rows: _infoRows(a));

  /// Блок «Опис» і, на вузькому екрані, «Інформація»; поки повні дані не прийшли — індикатор або помилка
  List<Widget> _details({required bool wide}) {
    final scale = _scale;
    final a = _full;
    if (a == null) {
      return [
        _error != null
            ? HikkaErrorView(scale: scale, error: _error!, onRetry: _retry)
            : HikkaLoading(scale: scale, height: 140),
      ];
    }
    return [
      _nextEpisode(a),
      _synopsis(a),
      if (!wide) ...[
        SizedBox(height: 18 * scale),
        Text('Інформація', style: hikkaStyle(13.5 * scale, weight: FontWeight.bold)),
        SizedBox(height: 4 * scale),
        _info(a),
      ],
    ];
  }

  Widget _gate(HikkaAnime a) {
    final scale = _scale;
    return AppCard(
      scale: scale,
      radius: 12,
      padding: EdgeInsets.all(18 * scale),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Symbols.lock_rounded, color: uiTheme.textMuted, size: 22 * scale, weight: 300),
              SizedBox(width: 10 * scale),
              Expanded(child: Text('Контент 18+ прихований', style: hikkaStyle(14 * scale, weight: FontWeight.bold))),
            ],
          ),
          SizedBox(height: 8 * scale),
          Text(
            'Це аніме позначене як 18+. Показ такого контенту вимкнено в налаштуваннях каталогу.',
            style: hikkaStyle(12.5 * scale, color: uiTheme.textMuted, height: 1.4),
          ),
          SizedBox(height: 14 * scale),
          AppSecondaryButton(
            scale: scale,
            expand: false,
            icon: Symbols.visibility_rounded,
            label: 'Показати цю сторінку',
            onTap: () => _toggle('revealed'),
          ),
        ],
      ),
    );
  }

  /// «Мій список» (статус, серії, оцінка, улюблене) над кнопкою «Дивитись»
  Widget _myList(HikkaAnime a) => HikkaMyListBar(key: ValueKey('mylist-${a.slug}'), anime: a, scale: _scale);

  /// «Дивитись» одразу під шапкою (поля задає сама сторінка, тож тут 0)
  Widget _watch() {
    final f = _full;
    if (f == null) return const SizedBox.shrink();
    return HikkaWatchSection(key: ValueKey('watch-${_route.id}'), anime: f, route: _route, scale: _scale, pad: 0);
  }

  Widget _top(HikkaAnime a, {required bool wide, required bool gated}) {
    final scale = _scale;
    if (gated) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(a.title(HikkaPrefs.instance.titleLang), style: hikkaStyle((wide ? 24 : 19) * scale, weight: FontWeight.bold, height: 1.2)),
          SizedBox(height: 16 * scale),
          _gate(a),
        ],
      );
    }
    final posterW = hikkaHeaderPosterWidth(scale, wide: wide);
    final shown = _full ?? a;
    final pad = HikkaLayout.sidePad(context, scale);
    // Банер лише під постером і назвою (до рядка оцінок), а не під усією шапкою: до країв екрана й трохи вище, під панель
    // Також лізе вгору під шапку-накладку: коли вона сховалась, на її місці не лишається порожнього тла
    final inset = AppHeaderInset.of(context);
    Widget backdrop({double? height}) => Positioned(
          left: -pad,
          right: -pad,
          top: -(4 * scale + inset),
          height: height == null ? null : height + inset,
          bottom: height == null ? -12 * scale : null,
          child: HikkaTitleBackdrop(anime: shown),
        );
    if (wide) {
      return Stack(
        clipBehavior: Clip.none,
        children: [
          backdrop(height: posterW / 0.7 + 16 * scale),
          Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: posterW,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _poster(shown),
                if (_full != null) ...[SizedBox(height: 16 * scale), _info(_full!)],
              ],
            ),
          ),
          SizedBox(width: 28 * scale),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _titleBlock(shown, wide: true),
                SizedBox(height: 14 * scale),
                _scores(shown),
                _myList(shown),
                _watch(),
                _genres(shown),
                ..._details(wide: true),
              ],
            ),
          ),
        ],
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            backdrop(),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: posterW, child: _poster(shown)),
                    SizedBox(width: 14 * scale),
                    Expanded(child: _titleBlock(shown, wide: false)),
                  ],
                ),
                SizedBox(height: 16 * scale),
                _scores(shown),
              ],
            ),
          ],
        ),
        _myList(shown),
        _watch(),
        _genres(shown),
        ..._details(wide: false),
      ],
    );
  }

  // ── Секції під шапкою ──────────────────────────────────────────────────────

  Widget Function(BuildContext, Widget) _frame(String title, double pad) =>
      (context, child) => HikkaSection(scale: _scale, pad: pad, title: title, child: child);

  Widget _staff(HikkaAnime a, double pad) {
    final scale = _scale;
    return HikkaAsync<HikkaPage<HikkaStaff>>(
      key: ValueKey('staff-${_route.id}'),
      scale: scale,
      compactError: true,
      load: () => HikkaApi.instance.animeStaff(a.slug, size: 30),
      stateFrame: _frame('Автори', pad),
      loading: (context) => HikkaLoading(scale: scale, height: 80),
      builder: (context, page) {
        final all = page.items;
        if (all.isEmpty) return const SizedBox.shrink();
        final shown = _staffExpanded ? all : all.take(8).toList();
        return HikkaSection(
          scale: scale,
          pad: pad,
          title: 'Автори',
          subtitle: 'Знімальна група',
          trailing: all.length > 8
              ? HikkaLinkButton(label: _staffExpanded ? 'Згорнути' : 'Показати всіх', scale: scale, onTap: () => _toggle('staff'))
              : null,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 780 * (HikkaLayout.compact(context) ? 1 : scale)),
            child: AppCard(
              scale: scale,
              radius: 12,
              padding: EdgeInsets.symmetric(horizontal: 14 * scale, vertical: 4 * scale),
              child: Column(
                children: [
                  for (int i = 0; i < shown.length; i++) ...[
                    if (i > 0) Divider(height: 1, color: uiTheme.borderSubtle),
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 9 * scale),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(shown[i].person.name, style: hikkaStyle(13 * scale, weight: FontWeight.w600)),
                                if (shown[i].rolesLabel.isNotEmpty)
                                  Padding(
                                    padding: EdgeInsets.only(top: 2 * scale),
                                    child: Text(shown[i].rolesLabel, style: hikkaStyle(11.5 * scale, color: uiTheme.textMuted, height: 1.3)),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _links(HikkaAnime a, double pad) {
    final scale = _scale;
    final usable = [for (final l in a.external) if (l.url.isNotEmpty && l.type != 'read') l];
    if (usable.isEmpty) return const SizedBox.shrink();
    // Спершу «Де дивитися», потім решта
    usable.sort((x, y) => (y.isWatch ? 1 : 0).compareTo(x.isWatch ? 1 : 0));
    // Самі посилання будуються лише при відкритті вікна: на сторінці лишається одна кнопка
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 0, pad, 22 * scale),
      child: Align(
        alignment: Alignment.centerLeft,
        child: AppSecondaryButton(
          scale: scale,
          expand: false,
          icon: Symbols.link_rounded,
          label: 'Посилання · ${usable.length}',
          onTap: () => unawaited(AppDialogs.show<void>(
            context,
            builder: (_) => HikkaLinksDialog(links: usable, scale: scale),
          )),
        ),
      ),
    );
  }

  Widget _videos(HikkaAnime a, double pad) {
    final scale = _scale;
    final videos = [for (final v in a.videos) if (v.url.isNotEmpty) v];
    if (videos.isEmpty) return const SizedBox.shrink();
    return HikkaSection(
      scale: scale,
      pad: pad,
      title: 'Відео',
      child: Wrap(
        spacing: 8 * scale,
        runSpacing: 8 * scale,
        children: [
          for (final v in videos.take(8))
            HikkaChip(
              label: v.title ?? (v.type == 'video_music' ? 'Музичне відео' : 'Трейлер'),
              scale: scale,
              icon: Symbols.smart_display_rounded,
              onTap: () => HikkaNav.instance.openLink(v.url),
            ),
        ],
      ),
    );
  }

  Widget _ost(HikkaAnime a, double pad) {
    final scale = _scale;
    final items = [...a.ost]..sort((x, y) {
        if (x.isOpening != y.isOpening) return x.isOpening ? -1 : 1;
        return x.index.compareTo(y.index);
      });
    if (items.isEmpty) return const SizedBox.shrink();
    final shown = _ostExpanded ? items : items.take(6).toList();
    return HikkaSection(
      scale: scale,
      pad: pad,
      title: 'Музика',
      subtitle: 'Опенінґи та ендінґи',
      trailing: items.length > 6
          ? HikkaLinkButton(label: _ostExpanded ? 'Згорнути' : 'Показати всі', scale: scale, onTap: () => _toggle('ost'))
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final o in shown)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 5 * scale),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 96 * scale,
                    child: Text(
                      '${o.isOpening ? 'Опенінґ' : 'Ендінґ'}${o.index > 0 ? ' ${o.index}' : ''}',
                      style: hikkaStyle(12 * scale, color: uiTheme.textDarkMuted, height: 1.35),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      [if (o.title != null) o.title!, if (o.author != null) o.author!].join(' — '),
                      style: hikkaStyle(12.5 * scale, height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _sections(HikkaAnime a, double pad) {
    final scale = _scale;
    final api = HikkaApi.instance;
    final adult = HikkaPrefs.instance.allowAdult;
    final id = _route.id;
    bool visible(HikkaAnime x) => adult || !x.isAdult;

    return [
      HikkaLazy(height: HikkaShelfMetrics.height(context, scale) + 70 * scale, builder: (_) => HikkaShelfAsync<HikkaCharacterRole>(
        scale: scale,
        pad: pad,
        title: 'Персонажі',
        token: id,
        load: () async => (await api.animeCharacters(a.slug, size: 20)).items,
        onMore: () => HikkaNav.instance.openAnimeCharacters(a.slug, seed: a),
        itemBuilder: (context, r) => HikkaCharacterCard(
          character: r.character,
          scale: scale,
          caption: r.main ? 'Головний' : 'Другорядний',
        ),
      )),
      if (a.hasFranchise)
        HikkaLazy(height: HikkaShelfMetrics.height(context, scale) + 70 * scale, builder: (_) => HikkaShelfAsync<FranchiseDirect>(
          scale: scale,
          pad: pad,
          title: 'Франшиза',
          subtitle: 'Пов’язані тайтли',
          token: id,
          load: () async {
            final model = FranchiseModel.build(await api.franchise(a.slug), a.slug);
            if (model == null) return const [];
            final direct = model.direct.where((d) => visible(d.node.anime)).toList();
            if (direct.isNotEmpty) return direct;
            // Прямих зв'язків немає — показуємо решту франшизи в порядку виходу
            return [
              for (final n in model.nodes)
                if (n.id != model.current.id && visible(n.anime)) FranchiseDirect(n, model.relationText(n), n.group),
            ];
          },
          onMore: () => HikkaNav.instance.openFranchise(a.slug, seed: a),
          itemBuilder: (context, d) => HikkaAnimeCard(anime: d.node.anime, scale: scale, caption: d.label),
        )),
      HikkaLazy(
        height: HikkaShelfMetrics.height(context, scale) + 70 * scale,
        builder: (_) =>
        HikkaShelfAsync<HikkaAnime>(
        scale: scale,
        pad: pad,
        title: 'Рекомендації',
        subtitle: 'Схоже на це аніме',
        token: id,
        load: () async => (await api.recommendations(a.slug, size: 20, allowAdult: adult)).items,
        itemBuilder: (context, x) => HikkaAnimeCard(anime: x, scale: scale),
      )),
      HikkaLazy(height: 150 * scale, builder: (_) => _staff(a, pad)),
      _links(a, pad),
      _videos(a, pad),
      _ost(a, pad),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final scale = _scale;
    final a = _full ?? _seed;
    if (a == null) {
      // Сторінку відкрито за посиланням: даних для шапки ще немає
      return _error != null ? HikkaErrorView(scale: scale, error: _error!, onRetry: _retry) : HikkaLoading(scale: scale, height: 320);
    }
    final pad = HikkaLayout.sidePad(context, scale);
    final gated = a.isAdult && !HikkaPrefs.instance.allowAdult && !_revealed;
    final full = _full;

    return HikkaPageFrame(
      scale: scale,
      controller: _scroll,
      bottomInset: widget.bottomInset,
      children: [
        LayoutBuilder(
          builder: (context, c) {
            final wide = c.maxWidth >= hikkaWideBreakpoint;
            return Padding(
              padding: EdgeInsets.fromLTRB(pad, 4 * scale, pad, 22 * scale),
              child: _top(a, wide: wide, gated: gated),
            );
          },
        ),
        if (!gated && full != null) ..._sections(full, pad),
      ],
    );
  }
}

/// Вікно «Посилання»: спершу «Де дивитися», потім решта. Вміст будується лише при відкритті.
class HikkaLinksDialog extends StatelessWidget {
  final List<HikkaLink> links;
  final double scale;

  const HikkaLinksDialog({super.key, required this.links, required this.scale});

  @override
  Widget build(BuildContext context) {
    return WatchDialogFrame(
      scale: scale,
      title: 'Посилання',
      icon: Symbols.link_rounded,
      body: Wrap(
        spacing: 8 * scale,
        runSpacing: 8 * scale,
        children: [
          for (final l in links)
            HikkaChip(
              label: l.text.isEmpty ? (Uri.tryParse(l.url)?.host ?? l.url) : l.text,
              scale: scale,
              icon: l.isWatch ? Symbols.play_circle_rounded : Symbols.open_in_new_rounded,
              onTap: () => HikkaNav.instance.openLink(l.url),
            ),
        ],
      ),
    );
  }
}
