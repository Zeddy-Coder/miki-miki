import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../models/hikka_models.dart';
import '../../services/hikka_api.dart';
import '../../services/hikka_nav.dart';
import '../../services/hikka_prefs.dart';
import '../../services/ui_theme_service.dart';
import '../../utils/platform_info.dart';
import '../app_animation_kit.dart';
import '../app_tones.dart';
import '../app_ui_kit.dart';
import '../line_icons.dart';
import 'hikka_cards.dart';
import 'hikka_common.dart';
import 'hikka_community_cards.dart';
import 'hikka_markdown_view.dart';
import 'hikka_page_kit.dart';

/// Collection page: title, author, description and all entries; the author's sections as separate blocks. If the author left
/// comments on the entries, entries go as rows with a comment, otherwise as a poster grid.
class HikkaCollectionPage extends StatefulWidget {
  final HikkaRoute route;
  final double scale;
  final double bottomInset;

  const HikkaCollectionPage({super.key, required this.route, required this.scale, this.bottomInset = 0});

  @override
  State<HikkaCollectionPage> createState() => _HikkaCollectionPageState();
}

class _HikkaCollectionPageState extends State<HikkaCollectionPage> {
  late final ScrollController _scroll = AppSmoothScrollController(initialScrollOffset: widget.route.scroll);
  HikkaCollection? _full;
  Object? _error;
  int _generation = 0;

  HikkaRoute get _route => widget.route;
  HikkaCollection? get _seed => _route.seed is HikkaCollection ? _route.seed as HikkaCollection : null;
  double get _scale => widget.scale;
  bool get _revealed => _route.memo['revealed'] == true;

  @override
  void initState() {
    super.initState();
    final cached = _route.memo['collection'];
    if (cached is HikkaCollection) {
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
    HikkaApi.instance.collection(_route.slug).then<void>((c) {
      if (!mounted || gen != _generation) return;
      _route.memo['collection'] = c;
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

  /// The title, the author with the date, the counters with line icons, marks and tags in grey, the description as on
  /// the title page (its links work once it is open)
  Widget _header(HikkaCollection c, double pad) {
    final scale = _scale;
    final count = c.entries;
    final marks = [if (c.spoiler) 'Спойлери', if (c.nsfw) '18+', for (final t in c.tags.take(8)) '#$t'];
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 4 * scale, pad, 4 * scale),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: hikkaReadableWidth(scale)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(c.title, style: hikkaStyle(22 * scale, weight: FontWeight.bold, height: 1.2)),
            SizedBox(height: 8 * scale),
            HikkaAuthorLine(author: c.author, date: c.createdAt, scale: scale),
            SizedBox(height: 6 * scale),
            Wrap(
              spacing: 14 * scale,
              runSpacing: 6 * scale,
              children: [
                HikkaStat(icon: LineIcon.stack, text: '${HikkaText.count(count)} ${HikkaText.plural(count, 'тайтл', 'тайтли', 'тайтлів')}', scale: scale),
                HikkaStat(icon: LineIcon.arrowUp, text: HikkaText.compact(c.voteScore), scale: scale, tooltip: 'Оцінка'),
                HikkaStat(icon: LineIcon.comment, text: HikkaText.compact(c.commentsCount), scale: scale, tooltip: 'Коментарі'),
              ],
            ),
            if (marks.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(top: 8 * scale),
                child: Text(marks.join('   '), style: hikkaStyle(12.5 * scale, color: uiTheme.textMuted, height: 1.4)),
              ),
            if (c.description != null) ...[
              SizedBox(height: 14 * scale),
              HikkaSynopsis(
                source: c.description!,
                scale: scale,
                fontSize: 14,
                color: AppTones.plateText,
                open: _route.memo['synopsis'] == true,
                onOpen: (v) => _route.memo['synopsis'] = v,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Rows (with the author's comments) or a poster grid; until chosen, rows when the author wrote comments
  bool _rowsOf(HikkaCollection c) {
    final chosen = _route.memo['rows'];
    if (chosen is bool) return chosen;
    return c.items.any((e) => (e.comment ?? '').trim().isNotEmpty);
  }

  /// "50 тайтлів" in grey and the "Сіткою / Списком" toggle, as in "Списки"
  Widget _viewLine(HikkaCollection c, double pad, int shown) {
    final scale = _scale;
    final rows = _rowsOf(c);
    Widget mode(LineIcon icon, bool value, String tip) => Semantics(
          button: true,
          selected: rows == value,
          label: tip,
          excludeSemantics: true,
          child: Tooltip(
            message: tip,
            child: InkResponse(
              onTap: () => setState(() => _route.memo['rows'] = value),
              radius: 20 * scale,
              splashColor: Colors.transparent,
              highlightColor: uiTheme.touchHighlight,
              child: SizedBox.square(
                dimension: AppPlatform.isMobile ? 40.0 : 34 * scale,
                child: Center(
                  child: LineIconView(icon, size: 19 * scale, color: rows == value ? (uiTheme.isLight ? uiTheme.textPrimary : const Color(0xFFEEEEEE)) : uiTheme.textDarkMuted),
                ),
              ),
            ),
          ),
        );
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 10 * scale, pad - 8 * scale, 4 * scale),
      child: Row(
        children: [
          Expanded(child: Text('${HikkaText.count(shown)} ${HikkaText.plural(shown, 'тайтл', 'тайтли', 'тайтлів')}', style: hikkaStyle(13 * scale, color: uiTheme.textMuted))),
          mode(LineIcon.grid, false, 'Сіткою'),
          mode(LineIcon.rows, true, 'Списком'),
        ],
      ),
    );
  }

  Widget _gate(HikkaCollection c, double pad) {
    final scale = _scale;
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 0, pad, 20 * scale),
      child: AppCard(
        scale: scale,
        radius: 14,
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
              'Цю колекцію позначено як 18+. Показ такого контенту вимкнено в налаштуваннях каталогу.',
              style: hikkaStyle(12.5 * scale, color: uiTheme.textMuted, height: 1.4),
            ),
            SizedBox(height: 14 * scale),
            AppSecondaryButton(
              scale: scale,
              expand: false,
              icon: Symbols.visibility_rounded,
              label: 'Показати цю колекцію',
              onTap: () => setState(() => _route.memo['revealed'] = true),
            ),
          ],
        ),
      ),
    );
  }

  // ── Entries ─────────────────────────────────────────────────────────────────

  /// A grey caption of the author's section ("Найкраще · 12")
  Widget _groupTitle(String label, int count, double pad) {
    final scale = _scale;
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 14 * scale, pad, 8 * scale),
      child: Text('$label · ${HikkaText.count(count)}', style: hikkaStyle(13 * scale, color: AppTones.caption, weight: FontWeight.w700)),
    );
  }

  List<Widget> _entries(HikkaCollection c, double pad, {required bool showAdult}) {
    final scale = _scale;
    final groups = c.grouped(allowAdult: showAdult);
    final total = groups.fold<int>(0, (n, g) => n + g.$2.length);
    if (total == 0) {
      return [
        SliverToBoxAdapter(
          child: SizedBox(height: 220, child: AppEmptyState(scale: scale, icon: Symbols.movie_rounded, text: 'У колекції немає тайтлів, доступних для показу')),
        ),
      ];
    }
    final rows = _rowsOf(c);
    final spacing = HikkaLayout.compact(context) ? 12.0 : 14 * scale;
    final textHeight = hikkaCardTextHeight(context, scale);
    final out = <Widget>[SliverToBoxAdapter(child: _viewLine(c, pad, total))];
    for (final (label, items) in groups) {
      if (label != null) out.add(SliverToBoxAdapter(child: _groupTitle(label, items.length, pad)));
      if (rows) {
        out.add(
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) => Align(
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: hikkaReadableWidth(scale) + pad * 2),
                  child: _EntryRow(entry: items[i], scale: scale, pad: pad, route: _route),
                ),
              ),
              childCount: items.length,
            ),
          ),
        );
      } else {
        out.add(
          SliverPadding(
            padding: EdgeInsets.fromLTRB(pad, 6 * scale, pad, label != null ? 14 * scale : 0),
            sliver: SliverGrid(
              gridDelegate: HikkaGridDelegate(maxTileWidth: 150, spacing: spacing, posterAspect: 0.7, textHeight: textHeight),
              delegate: SliverChildBuilderDelegate(
                (context, i) => HikkaAnimeCard(anime: items[i].anime, scale: scale),
                childCount: items.length,
              ),
            ),
          ),
        );
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final scale = _scale;
    final c = _full ?? _seed;
    if (c == null) {
      return _error != null ? HikkaErrorView(scale: scale, error: _error!, onRetry: _retry) : HikkaLoading(scale: scale, height: 320);
    }
    final pad = HikkaLayout.sidePad(context, scale);
    final adult = HikkaPrefs.instance.allowAdult;
    final gated = c.nsfw && !adult && !_revealed;
    final full = _full;

    final Widget body;
    if (gated) {
      body = SliverToBoxAdapter(child: _gate(c, pad));
    } else if (full == null) {
      body = SliverToBoxAdapter(
        child: _error != null
            ? HikkaErrorView(scale: scale, error: _error!, onRetry: _retry, compact: true)
            : HikkaLoading(scale: scale, height: 160),
      );
    } else {
      body = SliverMainAxisGroup(slivers: _entries(full, pad, showAdult: adult || _revealed));
    }

    return AppScrollbar(
      scale: scale,
      controller: _scroll,
      child: CustomScrollView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: SizedBox(height: AppHeaderInset.of(context))), // room under the overlay header
          SliverToBoxAdapter(child: _header(c, pad)),
          body,
          SliverToBoxAdapter(child: SizedBox(height: 28 * scale + widget.bottomInset)),
        ],
      ),
    );
  }
}

/// A collection entry as a row: a small poster, the title, type, season and score in grey, and the author's comment
/// (three lines until opened, as a description)
class _EntryRow extends StatelessWidget {
  final HikkaCollectionEntry entry;
  final double scale;
  final double pad;
  final HikkaRoute route;

  const _EntryRow({required this.entry, required this.scale, required this.pad, required this.route});

  @override
  Widget build(BuildContext context) {
    final a = entry.anime;
    final comment = entry.comment?.trim() ?? '';
    final meta = [
      if (a.typeLabel.isNotEmpty) a.typeLabel,
      if (a.seasonLabel.isNotEmpty) a.seasonLabel,
      if (a.episodesLabel.isNotEmpty) a.episodesLabel,
    ].join(' · ');
    final grey = AppTones.rowSub;
    final key = 'comment-${a.slug}';
    return InkWell(
      onTap: () => HikkaNav.instance.openAnime(a.slug, seed: a),
      splashColor: Colors.transparent,
      highlightColor: uiTheme.touchHighlight,
      hoverColor: uiTheme.hoverOverlay,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: pad, vertical: 9 * scale),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 52 * scale, child: HikkaPoster(url: a.image, malId: a.malId, scale: scale, radius: 8, aspect: 52 / 74, icon: Symbols.movie_rounded)),
            SizedBox(width: 12 * scale),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(a.title(HikkaPrefs.instance.titleLang), maxLines: 2, overflow: TextOverflow.ellipsis, style: hikkaStyle(15 * scale, height: 1.25)),
                  if (meta.isNotEmpty || a.hasScore)
                    Padding(
                      padding: EdgeInsets.only(top: 4 * scale),
                      child: Text.rich(
                        TextSpan(
                          style: hikkaStyle(12.5 * scale, color: grey, height: 1.3),
                          children: [
                            TextSpan(text: meta),
                            if (a.hasScore) ...[
                              TextSpan(text: meta.isEmpty ? '' : ' · '),
                              WidgetSpan(
                                alignment: PlaceholderAlignment.middle,
                                child: Padding(padding: EdgeInsets.only(right: 3 * scale), child: LineIconView(LineIcon.star, size: 12 * scale, color: grey, stroke: 1.8)),
                              ),
                              TextSpan(text: a.score.toStringAsFixed(2)),
                            ],
                          ],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  if (comment.isNotEmpty) ...[
                    SizedBox(height: 6 * scale),
                    HikkaSynopsis(
                      source: comment,
                      scale: scale,
                      fontSize: 12.5,
                      lines: 3,
                      open: route.memo[key] == true,
                      onOpen: (v) => route.memo[key] = v,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
