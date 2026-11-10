import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../models/hikka_models.dart';
import '../../services/hikka_api.dart';
import '../../services/hikka_nav.dart';
import '../../services/hikka_prefs.dart';
import '../../services/ui_theme_service.dart';
import '../app_animation_kit.dart';
import '../app_ui_kit.dart';
import 'hikka_cards.dart';
import 'hikka_common.dart';
import 'hikka_community_cards.dart';
import 'hikka_markdown_view.dart';
import 'hikka_page_kit.dart';

/// Сторінка колекції: назва, автор, опис і всі записи; розділи автора — окремими блоками. Якщо автор залишив
/// до записів коментарі, записи йдуть рядками з коментарем, інакше — сіткою постерів.
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

  // ── Шапка ──────────────────────────────────────────────────────────────────

  Widget _header(HikkaCollection c, double pad) {
    final scale = _scale;
    final count = c.entries;
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 6 * scale, pad, 16 * scale),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(c.title, style: hikkaStyle(21 * scale, weight: FontWeight.bold, height: 1.2)),
          SizedBox(height: 6 * scale),
          Text(hikkaByline(c.author, c.createdAt), style: hikkaStyle(12.5 * scale, color: uiTheme.textMuted)),
          SizedBox(height: 12 * scale),
          Wrap(
            spacing: 8 * scale,
            runSpacing: 6 * scale,
            children: [
              HikkaChip(label: '${HikkaText.count(count)} ${HikkaText.plural(count, 'тайтл', 'тайтли', 'тайтлів')}', icon: Symbols.movie_rounded, scale: scale),
              HikkaChip(label: HikkaText.compact(c.voteScore), icon: Symbols.arrow_circle_up_rounded, scale: scale),
              HikkaChip(label: HikkaText.compact(c.commentsCount), icon: Symbols.chat_bubble_rounded, scale: scale),
              if (c.spoiler) HikkaChip(label: 'Спойлери', icon: Symbols.visibility_off_rounded, scale: scale),
              if (c.nsfw) HikkaChip(label: '18+', scale: scale, highlight: true),
              for (final t in c.tags.take(8)) HikkaChip(label: '#$t', scale: scale),
            ],
          ),
          if (c.description != null) ...[
            SizedBox(height: 16 * scale),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: hikkaReadableWidth(scale)),
              child: HikkaCollapsible(
                collapsedHeight: 150 * scale,
                scale: scale,
                fadeColor: uiTheme.bgPrimary,
                child: HikkaMarkdownView(source: c.description, scale: scale),
              ),
            ),
          ],
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

  // ── Записи ─────────────────────────────────────────────────────────────────

  Widget _groupTitle(String label, int count, double pad) {
    final scale = _scale;
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 6 * scale, pad, 10 * scale),
      child: AppSectionHeader(scale: scale, title: label, subtitle: '${HikkaText.count(count)} ${HikkaText.plural(count, 'тайтл', 'тайтли', 'тайтлів')}'),
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
    final withComments = c.items.any((e) => (e.comment ?? '').trim().isNotEmpty);
    final spacing = HikkaLayout.compact(context) ? 12.0 : 14 * scale;
    final textHeight = hikkaCardTextHeight(context, scale);
    final out = <Widget>[];
    for (final (label, items) in groups) {
      if (label != null) out.add(SliverToBoxAdapter(child: _groupTitle(label, items.length, pad)));
      if (withComments) {
        out.add(
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: pad),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => Align(
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: hikkaReadableWidth(scale)),
                    child: Padding(padding: EdgeInsets.only(bottom: spacing), child: _EntryRow(entry: items[i], scale: scale)),
                  ),
                ),
                childCount: items.length,
              ),
            ),
          ),
        );
      } else {
        out.add(
          SliverPadding(
            padding: EdgeInsets.fromLTRB(pad, 0, pad, label != null ? 14 * scale : 0),
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
          SliverToBoxAdapter(child: _header(c, pad)),
          body,
          SliverToBoxAdapter(child: SizedBox(height: 28 * scale + widget.bottomInset)),
        ],
      ),
    );
  }
}

/// Запис колекції з коментарем автора: мініатюра постера, назва, мітки й текст коментаря
class _EntryRow extends StatelessWidget {
  final HikkaCollectionEntry entry;
  final double scale;

  const _EntryRow({required this.entry, required this.scale});

  @override
  Widget build(BuildContext context) {
    final a = entry.anime;
    final comment = entry.comment?.trim() ?? '';
    final meta = [
      if (a.typeLabel.isNotEmpty) a.typeLabel,
      if (a.seasonLabel.isNotEmpty) a.seasonLabel,
      if (a.episodesLabel.isNotEmpty) a.episodesLabel,
    ].join(' · ');
    return AppCard(
      scale: scale,
      radius: 12,
      onTap: () => HikkaNav.instance.openAnime(a.slug, seed: a),
      padding: EdgeInsets.all(10 * scale),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 64 * scale, child: HikkaPoster(url: a.image, scale: scale, radius: 8, icon: Symbols.movie_rounded)),
          SizedBox(width: 12 * scale),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.title(HikkaPrefs.instance.titleLang),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: hikkaStyle(13.5 * scale, weight: FontWeight.w600, height: 1.25),
                ),
                if (meta.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.only(top: 3 * scale),
                    child: Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: hikkaStyle(11.5 * scale, color: uiTheme.textMuted)),
                  ),
                if (a.hasScore)
                  Padding(
                    padding: EdgeInsets.only(top: 4 * scale),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Symbols.star_rounded, color: const Color(0xFFFFC23D), size: 14 * scale, fill: 1),
                        SizedBox(width: 3 * scale),
                        Text(a.score.toStringAsFixed(2), style: hikkaStyle(11.5 * scale, weight: FontWeight.w600)),
                      ],
                    ),
                  ),
                if (comment.isNotEmpty) ...[
                  SizedBox(height: 8 * scale),
                  HikkaCollapsible(
                    collapsedHeight: 96 * scale,
                    scale: scale,
                    fadeColor: uiTheme.bgSurface,
                    child: HikkaMarkdownView(source: comment, scale: scale, fontSize: 12.5),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
