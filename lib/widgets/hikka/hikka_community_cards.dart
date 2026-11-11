import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../models/hikka_models.dart';
import '../../services/hikka_nav.dart';
import '../../services/hikka_prefs.dart';
import '../../services/ui_theme_service.dart';
import '../app_animation_kit.dart';
import '../app_ui_kit.dart';
import 'hikka_common.dart';

/// Дрібний лічильник із іконкою («▲ 12», «💬 3»)
class HikkaStat extends StatelessWidget {
  final IconData icon;
  final String text;
  final double scale;
  final String? tooltip;

  const HikkaStat({super.key, required this.icon, required this.text, required this.scale, this.tooltip});

  @override
  Widget build(BuildContext context) {
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14 * scale, color: uiTheme.textDarkMuted, weight: 300),
        SizedBox(width: 3 * scale),
        Text(text, style: hikkaStyle(11.5 * scale, color: uiTheme.textMuted)),
      ],
    );
    return tooltip == null ? row : Tooltip(message: tooltip!, child: row);
  }
}

/// Горизонтальний рядок міток, що прокручується (фільтри, розділи): на вузькому екрані не ламається на два рядки.
/// Якщо задано [selectedIndex], вибрана мітка сама прокручується в поле зору (наприклад, після свайпу між вкладками).
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
      // Тягнути мишкою можна й на ПК
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

/// «@автор · 12 січня»
String hikkaByline(HikkaAuthor author, DateTime when) {
  final date = HikkaText.dayMonth(when, now: DateTime.now());
  return author.username.isEmpty ? date : '@${author.username} · $date';
}

/// Картка колекції: смужка з постерами перших тайтлів, назва, автор і лічильники. Натискання відкриває колекцію.
class HikkaCollectionCard extends StatelessWidget {
  final HikkaCollection collection;
  final double scale;
  final VoidCallback? onTap;

  const HikkaCollectionCard({super.key, required this.collection, required this.scale, this.onTap});

  static const int posters = 4;

  @override
  Widget build(BuildContext context) {
    final c = collection;
    final adult = HikkaPrefs.instance.allowAdult;
    final shown = c.visibleItems(allowAdult: adult).take(posters).toList();
    final gap = 4 * scale;
    final count = c.entries;
    return Semantics(
      button: true,
      label: '${c.title}. ${HikkaText.count(count)} ${HikkaText.plural(count, 'тайтл', 'тайтли', 'тайтлів')}',
      excludeSemantics: true,
      child: AppCard(
        scale: scale,
        radius: 14,
        onTap: onTap ?? () => HikkaNav.instance.openCollection(c.reference, seed: c),
        padding: EdgeInsets.all(10 * scale),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                for (int i = 0; i < posters; i++) ...[
                  if (i > 0) SizedBox(width: gap),
                  Expanded(
                    child: i < shown.length
                        ? HikkaPoster(url: shown[i].anime.image, malId: shown[i].anime.malId, scale: scale, aspect: 0.72, radius: 8, icon: Symbols.movie_rounded)
                        : AspectRatio(
                            aspectRatio: 0.72,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: uiTheme.bgElevated.withValues(alpha: 0.6),
                                borderRadius: uiTheme.borderRadius(8 * scale),
                                border: Border.all(color: uiTheme.borderSubtle),
                              ),
                            ),
                          ),
                  ),
                ],
              ],
            ),
            SizedBox(height: 10 * scale),
            Text(
              c.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: hikkaStyle(14.5 * scale, weight: FontWeight.bold, height: 1.25),
            ),
            SizedBox(height: 4 * scale),
            Text(
              [
                if (c.author.username.isNotEmpty) '@${c.author.username}',
                '${HikkaText.count(count)} ${HikkaText.plural(count, 'тайтл', 'тайтли', 'тайтлів')}',
              ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: hikkaStyle(12 * scale, color: uiTheme.textMuted),
            ),
            SizedBox(height: 8 * scale),
            Wrap(
              spacing: 12 * scale,
              runSpacing: 4 * scale,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                HikkaStat(icon: Symbols.arrow_circle_up_rounded, text: HikkaText.compact(c.voteScore), scale: scale, tooltip: 'Оцінка'),
                HikkaStat(icon: Symbols.chat_bubble_rounded, text: HikkaText.compact(c.commentsCount), scale: scale, tooltip: 'Коментарі'),
                if (c.spoiler) HikkaPill(text: 'Спойлери', scale: scale, background: uiTheme.bgElevated, foreground: uiTheme.textMuted),
                if (c.nsfw) HikkaPill(text: '18+', scale: scale, background: const Color(0xC7C62828)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Картка статті: обкладинка (якщо є), категорія й дата, назва, початок тексту й лічильники
class HikkaArticleCard extends StatelessWidget {
  final HikkaArticle article;
  final double scale;
  final VoidCallback? onTap;

  const HikkaArticleCard({super.key, required this.article, required this.scale, this.onTap});

  @override
  Widget build(BuildContext context) {
    final a = article;
    final cover = a.coverImage;
    final snippet = a.snippet();
    final date = HikkaText.dayMonth(a.createdAt, now: DateTime.now());
    return Semantics(
      button: true,
      label: '${a.categoryLabel}. ${a.title}',
      excludeSemantics: true,
      child: AppCard(
        scale: scale,
        radius: 14,
        onTap: onTap ?? () => HikkaNav.instance.openArticle(a.slug, seed: a),
        padding: EdgeInsets.all(10 * scale),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (cover != null) ...[
              HikkaPoster(url: cover, scale: scale, aspect: 16 / 9, radius: 10, alignment: Alignment.center, icon: Symbols.article_rounded),
              SizedBox(height: 10 * scale),
            ],
            Row(
              children: [
                HikkaPill(text: a.categoryLabel, scale: scale, background: uiTheme.accentWash, foreground: uiTheme.accentColor),
                SizedBox(width: 8 * scale),
                Expanded(
                  child: Text(date, maxLines: 1, overflow: TextOverflow.ellipsis, style: hikkaStyle(11.5 * scale, color: uiTheme.textDarkMuted)),
                ),
              ],
            ),
            SizedBox(height: 7 * scale),
            Text(a.title, maxLines: 3, overflow: TextOverflow.ellipsis, style: hikkaStyle(15 * scale, weight: FontWeight.bold, height: 1.25)),
            if (snippet.isNotEmpty) ...[
              SizedBox(height: 6 * scale),
              Text(snippet, maxLines: 3, overflow: TextOverflow.ellipsis, style: hikkaStyle(12.5 * scale, color: uiTheme.textMuted, height: 1.4)),
            ],
            SizedBox(height: 9 * scale),
            Row(
              children: [
                if (a.author.username.isNotEmpty)
                  Flexible(
                    child: Text('@${a.author.username}', maxLines: 1, overflow: TextOverflow.ellipsis, style: hikkaStyle(11.5 * scale, color: uiTheme.textMuted)),
                  ),
                const Spacer(),
                HikkaStat(icon: Symbols.visibility_rounded, text: HikkaText.compact(a.views), scale: scale, tooltip: 'Перегляди'),
                SizedBox(width: 10 * scale),
                HikkaStat(icon: Symbols.arrow_circle_up_rounded, text: HikkaText.compact(a.voteScore), scale: scale, tooltip: 'Оцінка'),
                SizedBox(width: 10 * scale),
                HikkaStat(icon: Symbols.chat_bubble_rounded, text: HikkaText.compact(a.commentsCount), scale: scale, tooltip: 'Коментарі'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
