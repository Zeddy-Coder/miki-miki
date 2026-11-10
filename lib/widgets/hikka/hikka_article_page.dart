import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../models/hikka_models.dart';
import '../../services/hikka_api.dart';
import '../../services/hikka_nav.dart';
import '../../services/ui_theme_service.dart';
import '../app_animation_kit.dart';
import 'hikka_common.dart';
import 'hikka_community_cards.dart';
import 'hikka_page_kit.dart';
import 'hikka_slate_view.dart';

/// Сторінка статті: категорія, назва, автор і дата, лічильники та повний текст із розміткою Hikka.
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

  Widget _header(HikkaArticle a, double pad) {
    final scale = _scale;
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 6 * scale, pad, 16 * scale),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: hikkaReadableWidth(scale)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                HikkaPill(text: a.categoryLabel, scale: scale, background: uiTheme.accentWash, foreground: uiTheme.accentColor),
                SizedBox(width: 8 * scale),
                Expanded(
                  child: Text(hikkaByline(a.author, a.createdAt), maxLines: 1, overflow: TextOverflow.ellipsis, style: hikkaStyle(12 * scale, color: uiTheme.textMuted)),
                ),
              ],
            ),
            SizedBox(height: 10 * scale),
            Text(a.title, style: hikkaStyle(22 * scale, weight: FontWeight.bold, height: 1.22)),
            SizedBox(height: 12 * scale),
            Wrap(
              spacing: 14 * scale,
              runSpacing: 4 * scale,
              children: [
                HikkaStat(icon: Symbols.visibility_rounded, text: HikkaText.compact(a.views), scale: scale, tooltip: 'Перегляди'),
                HikkaStat(icon: Symbols.arrow_circle_up_rounded, text: HikkaText.compact(a.voteScore), scale: scale, tooltip: 'Оцінка'),
                HikkaStat(icon: Symbols.chat_bubble_rounded, text: HikkaText.compact(a.commentsCount), scale: scale, tooltip: 'Коментарі'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(HikkaArticle? full, double pad) {
    final scale = _scale;
    if (full == null) {
      return _error != null
          ? HikkaErrorView(scale: scale, error: _error!, onRetry: _retry, compact: true)
          : HikkaLoading(scale: scale, height: 200);
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 0, pad, 12 * scale),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: hikkaReadableWidth(scale)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            HikkaSlateView(nodes: full.document, scale: scale),
            if (full.tags.isNotEmpty) ...[
              SizedBox(height: 8 * scale),
              Wrap(
                spacing: 8 * scale,
                runSpacing: 6 * scale,
                children: [for (final t in full.tags.take(12)) HikkaChip(label: '#$t', scale: scale)],
              ),
            ],
          ],
        ),
      ),
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
    return HikkaPageFrame(
      scale: scale,
      controller: _scroll,
      bottomInset: widget.bottomInset,
      children: [
        _header(_full ?? a, pad),
        _body(_full, pad),
      ],
    );
  }
}
