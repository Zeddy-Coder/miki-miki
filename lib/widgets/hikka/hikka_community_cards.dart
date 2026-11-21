import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../models/hikka_models.dart';
import '../../services/hikka_nav.dart';
import '../../services/hikka_prefs.dart';
import '../../services/ui_theme_service.dart';
import '../../utils/platform_info.dart';
import '../app_animation_kit.dart';
import '../line_icons.dart';
import 'hikka_common.dart';
import '../../utils/app_clock.dart';

/// A small counter with a line icon ("↑ 12", "💬 3"), all in grey
class HikkaStat extends StatelessWidget {
  final LineIcon icon;
  final String text;
  final double scale;
  final String? tooltip;

  const HikkaStat({super.key, required this.icon, required this.text, required this.scale, this.tooltip});

  @override
  Widget build(BuildContext context) {
    final color = uiTheme.textMuted;
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        LineIconView(icon, size: 14 * scale, color: color),
        SizedBox(width: 4 * scale),
        Text(text, style: hikkaStyle(12 * scale, color: color)),
      ],
    );
    if (tooltip == null) return row;
    // A tooltip is for the mouse; on a phone the label is only read out (a Tooltip in each counter of each row was
    // most of what a row built while a list scrolled)
    if (AppPlatform.isMobile) return Semantics(label: tooltip, child: row);
    return Tooltip(message: tooltip!, child: row);
  }
}

/// A horizontal scrolling row of labels (filters, sections): on a narrow screen it does not break into two rows.
/// If [selectedIndex] is set, the selected label scrolls into view by itself (e.g. after a swipe between tabs).
class HikkaChipRow extends StatefulWidget {
  final double scale;
  final List<Widget> children;
  final int? selectedIndex;

  const HikkaChipRow({super.key, required this.scale, required this.children, this.selectedIndex});

  @override
  State<HikkaChipRow> createState() => _HikkaChipRowState();
}

class _HikkaChipRowState extends State<HikkaChipRow> {
  final List<GlobalKey> _keys = [];

  @override
  void initState() {
    super.initState();
    _reveal(animate: false);
  }

  @override
  void didUpdateWidget(HikkaChipRow old) {
    super.didUpdateWidget(old);
    if (old.selectedIndex != widget.selectedIndex) _reveal(animate: true);
  }

  void _reveal({required bool animate}) {
    final i = widget.selectedIndex;
    if (i == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || i < 0 || i >= _keys.length) return;
      final ctx = _keys[i].currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(ctx, alignment: 0.5, duration: animate ? AppAnim.medium : Duration.zero, curve: AppAnim.easeOut);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.scale;
    final pad = HikkaLayout.sidePad(context, scale);
    while (_keys.length < widget.children.length) {
      _keys.add(GlobalKey());
    }
    return ScrollConfiguration(
      // On PC you can drag with the mouse too
      behavior: ScrollConfiguration.of(context).copyWith(dragDevices: PointerDeviceKind.values.toSet(), scrollbars: false),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: pad, vertical: 4 * scale),
        child: Row(
          children: [
            for (int i = 0; i < widget.children.length; i++) ...[
              if (i > 0) SizedBox(width: 8 * scale),
              KeyedSubtree(key: _keys[i], child: widget.children[i]),
            ],
          ],
        ),
      ),
    );
  }
}

/// The author line of a collection or an article: a round avatar, "@name" and the date in grey, [trailing] on the right
/// (the counters); a tap on the name opens the author's profile
class HikkaAuthorLine extends StatelessWidget {
  final HikkaAuthor author;
  final DateTime? date;
  final double scale;
  final Widget? trailing;

  const HikkaAuthorLine({super.key, required this.author, required this.scale, this.date, this.trailing});

  @override
  Widget build(BuildContext context) {
    final name = author.username;
    final now = AppClock.now();
    final when = date == null ? null : HikkaText.dayMonth(date!, now: now, withYear: date!.year != now.year);
    final who = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        HikkaAvatar(url: author.avatar, size: 26 * scale, scale: scale),
        SizedBox(width: 8 * scale),
        Flexible(
          child: Text.rich(
            TextSpan(
              children: [
                if (name.isNotEmpty) TextSpan(text: '@$name', style: hikkaStyle(13.5 * scale)),
                if (when != null) TextSpan(text: name.isEmpty ? when : ' · $when', style: hikkaStyle(13 * scale, color: uiTheme.textMuted)),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
    return Row(
      children: [
        Flexible(
          child: name.isEmpty
              ? who
              : Semantics(
                  button: true,
                  label: 'Профіль @$name',
                  child: InkWell(
                    onTap: () => HikkaNav.instance.openUser(name),
                    borderRadius: uiTheme.borderRadius(14 * scale),
                    splashColor: Colors.transparent,
                    highlightColor: uiTheme.touchHighlight,
                    hoverColor: uiTheme.hoverOverlay,
                    child: Padding(padding: EdgeInsets.symmetric(vertical: 4 * scale), child: who),
                  ),
                ),
        ),
        if (trailing != null) ...[SizedBox(width: 12 * scale), trailing!],
      ],
    );
  }
}

/// A collection as a fan of three posters on a dark card: the title, the author with the number of titles, votes and
/// comments in grey ("Огляд" and its shelf). The fan spans the card's whole width (the posters overlap by about a
/// third, the first one on top); with fewer posters they stand in the middle.
class HikkaCollectionFanCard extends StatelessWidget {
  final HikkaCollection collection;
  final double scale;

  const HikkaCollectionFanCard({super.key, required this.collection, required this.scale});

  static const double _pad = 12;
  static const double _width = 232;

  /// A poster of the fan and the step to the next one: three of them fill the card's inner width
  static const double _poster = 86;
  static const double _step = (_width - _pad * 2 - _poster) / 2;
  static const double _posterHeight = _poster * 90 / 64;

  static double width(double scale) => _width * scale;
  static double height(double scale) => (_pad + _posterHeight + 12 + 58 + 14) * scale;

  @override
  Widget build(BuildContext context) {
    final c = collection;
    final adult = HikkaPrefs.instance.allowAdult;
    final shown = c.visibleItems(allowAdult: adult).take(3).toList();
    final count = c.entries;
    final r = uiTheme.borderRadius(16 * scale);
    final bg = uiTheme.bgSurface;
    final n = shown.isEmpty ? 1 : shown.length;
    // Fewer than three posters: the same overlap, the fan in the middle of the card
    final double fanWidth = _poster + _step * (n - 1);
    final double left = _pad + (_width - _pad * 2 - fanWidth) / 2;
    return Semantics(
      button: true,
      label: '${c.title}. ${HikkaText.count(count)} ${HikkaText.plural(count, 'тайтл', 'тайтли', 'тайтлів')}',
      excludeSemantics: true,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(borderRadius: r, side: BorderSide(color: uiTheme.borderSubtle)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => HikkaNav.instance.openCollection(c.reference, seed: c),
          splashColor: Colors.transparent,
          highlightColor: uiTheme.touchHighlight,
          hoverColor: uiTheme.hoverOverlay,
          child: Stack(
            children: [
              // The first poster lies on top; the edge in the card's colour parts them
              for (int i = n - 1; i >= 0; i--)
                Positioned(
                  key: ValueKey('fan-$i'),
                  left: (left + i * _step) * scale,
                  top: _pad * scale,
                  width: _poster * scale,
                  height: _posterHeight * scale,
                  child: DecoratedBox(
                    position: DecorationPosition.foreground,
                    decoration: BoxDecoration(borderRadius: uiTheme.borderRadius(10 * scale), border: Border.all(color: bg, width: 2 * scale)),
                    child: HikkaPoster(
                      url: shown.isEmpty ? null : shown[i].anime.image,
                      malId: shown.isEmpty ? 0 : shown[i].anime.malId,
                      scale: scale,
                      aspect: 64 / 90,
                      radius: 10,
                      border: false,
                      icon: Symbols.movie_rounded,
                    ),
                  ),
                ),
              Positioned(
                left: _pad * scale,
                right: _pad * scale,
                top: (_pad + _posterHeight + 12) * scale,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: hikkaStyle(14 * scale, weight: FontWeight.bold, height: 1.25)),
                    SizedBox(height: 4 * scale),
                    Text(
                      [if (c.author.username.isNotEmpty) '@${c.author.username}', '${HikkaText.count(count)} ${HikkaText.plural(count, 'тайтл', 'тайтли', 'тайтлів')}'].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: hikkaStyle(12 * scale, color: uiTheme.textMuted),
                    ),
                    SizedBox(height: 8 * scale),
                    Row(
                      children: [
                        HikkaStat(icon: LineIcon.arrowUp, text: HikkaText.compact(c.voteScore), scale: scale, tooltip: 'Оцінка'),
                        SizedBox(width: 14 * scale),
                        HikkaStat(icon: LineIcon.comment, text: HikkaText.compact(c.commentsCount), scale: scale, tooltip: 'Коментарі'),
                        if (c.nsfw) ...[SizedBox(width: 14 * scale), HikkaPill(text: '18+', scale: scale, background: const Color(0xC7C62828))],
                      ],
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
}

/// A collection as a row (the "Колекції" section): a fan of three posters, the title, "@author · N тайтлів", votes and
/// comments in grey
class HikkaCollectionRow extends StatelessWidget {
  final HikkaCollection collection;
  final double scale;
  final double pad;

  const HikkaCollectionRow({super.key, required this.collection, required this.scale, required this.pad});

  @override
  Widget build(BuildContext context) {
    final c = collection;
    final shown = c.visibleItems(allowAdult: HikkaPrefs.instance.allowAdult).take(3).toList();
    final count = c.entries;
    final bg = uiTheme.bgPrimary;
    final w = 52 * scale;
    final step = 24 * scale;
    return Semantics(
      button: true,
      label: '${c.title}. ${HikkaText.count(count)} ${HikkaText.plural(count, 'тайтл', 'тайтли', 'тайтлів')}',
      excludeSemantics: true,
      child: InkWell(
        onTap: () => HikkaNav.instance.openCollection(c.reference, seed: c),
        splashColor: Colors.transparent,
        highlightColor: uiTheme.touchHighlight,
        hoverColor: uiTheme.hoverOverlay,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: pad, vertical: 10 * scale),
          child: Row(
            children: [
              SizedBox(
                width: w + step * 2,
                height: 74 * scale,
                child: Stack(
                  children: [
                    // The first poster lies on top; the edge in the page color parts them
                    for (int i = shown.length - 1; i >= 0; i--)
                      Positioned(
                        left: i * step,
                        top: 0,
                        width: w,
                        height: 74 * scale,
                        child: DecoratedBox(
                          position: DecorationPosition.foreground,
                          decoration: BoxDecoration(borderRadius: uiTheme.borderRadius(8 * scale), border: Border.all(color: bg, width: 2 * scale)),
                          child: HikkaPoster(url: shown[i].anime.image, malId: shown[i].anime.malId, scale: scale, aspect: 52 / 74, radius: 8, border: false, icon: Symbols.movie_rounded),
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(width: 14 * scale),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(c.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: hikkaStyle(14.5 * scale, weight: FontWeight.bold, height: 1.25)),
                    SizedBox(height: 4 * scale),
                    Text(
                      [if (c.author.username.isNotEmpty) '@${c.author.username}', '${HikkaText.count(count)} ${HikkaText.plural(count, 'тайтл', 'тайтли', 'тайтлів')}'].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: hikkaStyle(12.5 * scale, color: uiTheme.textMuted),
                    ),
                    SizedBox(height: 6 * scale),
                    Row(
                      children: [
                        HikkaStat(icon: LineIcon.arrowUp, text: HikkaText.compact(c.voteScore), scale: scale, tooltip: 'Оцінка'),
                        SizedBox(width: 14 * scale),
                        HikkaStat(icon: LineIcon.comment, text: HikkaText.compact(c.commentsCount), scale: scale, tooltip: 'Коментарі'),
                        if (c.nsfw) ...[SizedBox(width: 14 * scale), HikkaPill(text: '18+', scale: scale, background: const Color(0xC7C62828))],
                      ],
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
}

/// An article as a row: the category and date in grey, the title, the author with votes and comments, the cover on
/// the right
class HikkaArticleRow extends StatelessWidget {
  final HikkaArticle article;
  final double scale;
  final double pad;

  const HikkaArticleRow({super.key, required this.article, required this.scale, required this.pad});

  @override
  Widget build(BuildContext context) {
    final a = article;
    final cover = a.coverImage;
    final date = HikkaText.dayMonth(a.createdAt, now: AppClock.now());
    return Semantics(
      button: true,
      label: '${a.categoryLabel}. ${a.title}',
      excludeSemantics: true,
      child: InkWell(
        onTap: () => HikkaNav.instance.openArticle(a.slug, seed: a),
        splashColor: Colors.transparent,
        highlightColor: uiTheme.touchHighlight,
        hoverColor: uiTheme.hoverOverlay,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: pad, vertical: 10 * scale),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${a.categoryLabel} · $date', maxLines: 1, overflow: TextOverflow.ellipsis, style: hikkaStyle(12 * scale, color: uiTheme.textMuted)),
                    SizedBox(height: 3 * scale),
                    Text(a.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: hikkaStyle(14.5 * scale, weight: FontWeight.bold, height: 1.25)),
                    SizedBox(height: 6 * scale),
                    Row(
                      children: [
                        if (a.author.username.isNotEmpty) ...[
                          Flexible(child: Text('@${a.author.username}', maxLines: 1, overflow: TextOverflow.ellipsis, style: hikkaStyle(12 * scale, color: uiTheme.textMuted))),
                          SizedBox(width: 12 * scale),
                        ],
                        HikkaStat(icon: LineIcon.arrowUp, text: HikkaText.compact(a.voteScore), scale: scale, tooltip: 'Оцінка'),
                        SizedBox(width: 12 * scale),
                        HikkaStat(icon: LineIcon.comment, text: HikkaText.compact(a.commentsCount), scale: scale, tooltip: 'Коментарі'),
                      ],
                    ),
                  ],
                ),
              ),
              if (cover != null) ...[
                SizedBox(width: 12 * scale),
                SizedBox(
                  width: 96 * scale,
                  height: 64 * scale,
                  child: HikkaPoster(url: cover, scale: scale, aspect: 96 / 64, radius: 10, alignment: Alignment.center, icon: Symbols.article_rounded),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
