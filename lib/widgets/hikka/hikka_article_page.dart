import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../models/hikka_models.dart';
import '../../services/hikka_api.dart';
import '../../services/hikka_nav.dart';
import '../../services/hikka_prefs.dart';
import '../../services/ui_theme_service.dart';
import '../../utils/app_clock.dart';
import '../app_animation_kit.dart';
import '../app_tones.dart';
import '../design_kit.dart' show AppPlate;
import '../line_icons.dart';
import 'hikka_common.dart';
import 'hikka_community_cards.dart';
import 'hikka_page_kit.dart';
import 'hikka_slate_view.dart';

/// Article page: category, title, author and date, counters and the full text with Hikka markup.
class HikkaArticlePage extends StatefulWidget {
  final HikkaRoute route;
  final double scale;
  final double bottomInset;

  const HikkaArticlePage({super.key, required this.route, required this.scale, this.bottomInset = 0});

  @override
  State<HikkaArticlePage> createState() => _HikkaArticlePageState();
}

class _HikkaArticlePageState extends State<HikkaArticlePage> {
  late final ScrollController _scroll = AppSmoothScrollController(initialScrollOffset: widget.route.scroll);
  HikkaArticle? _full;
  Object? _error;
  int _generation = 0;

  HikkaRoute get _route => widget.route;
  HikkaArticle? get _seed => _route.seed is HikkaArticle ? _route.seed as HikkaArticle : null;
  double get _scale => widget.scale;

  @override
  void initState() {
    super.initState();
    final cached = _route.memo['article'];
    if (cached is HikkaArticle) {
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
    HikkaApi.instance.article(_route.slug).then<void>((a) {
      if (!mounted || gen != _generation) return;
      _route.memo['article'] = a;
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

  /// The category and date in grey, the title, the author with the counters on one line, and the title the article is
  /// about as a quiet card
  Widget _header(HikkaArticle a, double pad) {
    final scale = _scale;
    final now = AppClock.now();
    final content = a.content;
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 4 * scale, pad, 8 * scale),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: hikkaReadableWidth(scale)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${a.categoryLabel} · ${HikkaText.dayMonth(a.createdAt, now: now)}',
              style: hikkaStyle(12.5 * scale, color: uiTheme.textMuted),
            ),
            SizedBox(height: 6 * scale),
            Text(a.title, style: hikkaStyle(22 * scale, weight: FontWeight.bold, height: 1.22)),
            SizedBox(height: 10 * scale),
            HikkaAuthorLine(
              author: a.author,
              scale: scale,
              trailing: Wrap(
                spacing: 12 * scale,
                children: [
                  HikkaStat(icon: LineIcon.eye, text: HikkaText.compact(a.views), scale: scale, tooltip: 'Перегляди'),
                  HikkaStat(icon: LineIcon.arrowUp, text: HikkaText.compact(a.voteScore), scale: scale, tooltip: 'Оцінка'),
                  HikkaStat(icon: LineIcon.comment, text: HikkaText.compact(a.commentsCount), scale: scale, tooltip: 'Коментарі'),
                ],
              ),
            ),
            if (content != null) Padding(padding: EdgeInsets.only(top: 12 * scale), child: _AnimeLink(anime: content, scale: scale)),
          ],
        ),
      ),
    );
  }

  /// While the text loads: a spinner (or the error) under the header
  Widget _waiting(double pad) {
    final scale = _scale;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: pad),
      child: _error != null ? HikkaErrorView(scale: scale, error: _error!, onRetry: _retry, compact: true) : HikkaLoading(scale: scale, height: 200),
    );
  }

  /// One piece of the text (see [HikkaSlateView.pieces]) or, after the last one, the tags: in the reading column
  Widget _piece(HikkaArticle full, List<List<SlateNode>> pieces, int i, double pad) {
    final scale = _scale;
    final last = i == pieces.length - (full.tags.isEmpty ? 1 : 0);
    final Widget child = i < pieces.length
        ? HikkaSlateView(nodes: pieces[i], scale: scale)
        : Padding(
            padding: EdgeInsets.only(top: 10 * scale),
            child: Wrap(
              spacing: 8 * scale,
              runSpacing: 8 * scale,
              children: [for (final t in full.tags.take(12)) AppPlate(scale: scale, label: '#$t', height: 30, radius: 15)],
            ),
          );
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, i == 0 ? 8 * scale : 0, pad, last ? 12 * scale : 0),
      child: ConstrainedBox(constraints: BoxConstraints(maxWidth: hikkaReadableWidth(scale)), child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scale = _scale;
    final a = _full ?? _seed;
    if (a == null) {
      return _error != null ? HikkaErrorView(scale: scale, error: _error!, onRetry: _retry) : HikkaLoading(scale: scale, height: 320);
    }
    final pad = HikkaLayout.sidePad(context, scale);
    final full = _full;
    // The text is a lazy list of its blocks: a long article built all at once laid out every paragraph and asked for
    // every picture on opening, and repainted the whole page on every scroll frame
    final pieces = full == null ? const <List<SlateNode>>[] : HikkaSlateView.pieces(full.document);
    return HikkaPageFrame(
      scale: scale,
      controller: _scroll,
      bottomInset: widget.bottomInset,
      itemCount: full == null ? 0 : pieces.length + (full.tags.isEmpty ? 0 : 1),
      itemBuilder: (context, i) => _piece(full!, pieces, i, pad),
      // The reading column in the middle of a wide window, as before
      columnWidth: hikkaReadableWidth(scale) + pad * 2,
      children: [
        _header(full ?? a, pad),
        if (full == null) _waiting(pad),
      ],
    );
  }
}

/// The title an article is about: a small poster, the title, type, year and score, a chevron
class _AnimeLink extends StatelessWidget {
  final HikkaAnime anime;
  final double scale;

  const _AnimeLink({required this.anime, required this.scale});

  @override
  Widget build(BuildContext context) {
    final a = anime;
    final grey = AppTones.rowSub;
    final meta = [if (a.typeLabel.isNotEmpty) a.typeLabel, if (a.year != null) '${a.year}'].join(' · ');
    final shape = RoundedRectangleBorder(borderRadius: uiTheme.borderRadius(12 * scale), side: BorderSide(color: uiTheme.borderSubtle));
    return Semantics(
      button: true,
      label: a.title(HikkaPrefs.instance.titleLang),
      excludeSemantics: true,
      child: Material(
        color: AppTones.menu,
        shape: shape,
        child: InkWell(
          key: const ValueKey('article-anime'),
          customBorder: shape,
          splashColor: Colors.transparent,
          highlightColor: uiTheme.touchHighlight,
          hoverColor: uiTheme.hoverOverlay,
          onTap: () => HikkaNav.instance.openAnime(a.slug, seed: a),
          child: Padding(
            padding: EdgeInsets.all(10 * scale),
            child: Row(
              children: [
                SizedBox(width: 40 * scale, child: HikkaPoster(url: a.image, malId: a.malId, scale: scale, radius: 6, aspect: 40 / 56, icon: Symbols.movie_rounded)),
                SizedBox(width: 12 * scale),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(a.title(HikkaPrefs.instance.titleLang), maxLines: 2, overflow: TextOverflow.ellipsis, style: hikkaStyle(14.5 * scale, height: 1.25)),
                      if (meta.isNotEmpty || a.hasScore)
                        Padding(
                          padding: EdgeInsets.only(top: 3 * scale),
                          child: Text.rich(
                            TextSpan(
                              style: hikkaStyle(12.5 * scale, color: grey),
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
                          ),
                        ),
                    ],
                  ),
                ),
                SizedBox(width: 8 * scale),
                LineIconView(LineIcon.chevronRight, size: 18 * scale, color: AppTones.chevron),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
