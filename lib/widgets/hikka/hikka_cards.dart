import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../models/hikka_models.dart';
import '../../services/hikka_lists.dart';
import '../../services/hikka_nav.dart';
import '../../services/hikka_prefs.dart';
import '../../services/quick_play.dart';
import '../../services/ui_theme_service.dart';
import '../../services/watch_service.dart';
import '../app_tones.dart';
import '../design_kit.dart';
import '../line_icons.dart';
import 'hikka_common.dart';
import 'hikka_list_sheet.dart';
import 'hikka_my_list_bar.dart';
import 'hikka_watch_dialogs.dart';

/// How far the person got in a title: the Hikka list counter or the local marks, whichever is larger
int hikkaSeenEpisodes(HikkaAnime a) {
  final mine = HikkaMyList.instance.cached(a.slug)?.episodes ?? 0;
  int local = 0;
  try {
    local = WatchService.instance.store.watched('hikka:${a.slug}').length;
  } catch (_) {
    // The watch service may be missing (tests of other parts): only the list counter then
  }
  return mine > local ? mine : local;
}

/// Plays the title from where the person stopped (as "Продовжити перегляд" does); if that fails, opens the title page
Future<void> hikkaContinue(BuildContext context, HikkaAnime a, double scale) async {
  final ok = await QuickPlay.resume(
    a,
    onMissingNext: (plan, next) => context.mounted ? WatchDialogs.missingNext(context, scale: scale, plan: plan, next: next) : Future.value(null),
  );
  if (!ok) HikkaNav.instance.openAnime(a.slug, seed: a);
}

/// The long-press menu of a title (on a PC, the right button): a dark tile with the title's name, "Продовжити · серія N"
/// when the person has started it (otherwise "Відкрити"), "Мій список…" (the sheet) for a signed-in person and
/// [removeLabel] in red when the card can be removed ([onRemove]). [lift] is the card drawn over the dimmed screen.
Future<void> showHikkaCardMenu(
  BuildContext context, {
  required HikkaAnime anime,
  required double scale,
  required Rect anchor,
  Widget? lift,
  int? seen,
  String removeLabel = 'Прибрати зі списку',
  VoidCallback? onRemove,
  VoidCallback? onOpen,
}) async {
  final a = anime;
  final done = seen ?? hikkaSeenEpisodes(a);
  final total = a.episodesTotal ?? 0;
  final canContinue = done > 0 && (total <= 0 || done < total);
  final signedIn = HikkaMyList.instance.signedIn;
  final status = HikkaMyList.instance.statusOf(a.slug);
  const open = 'open', cont = 'continue', list = 'list', remove = 'remove';
  final picked = await showAppMenu<String>(
    context,
    scale: scale,
    anchor: anchor,
    lift: lift,
    width: 250,
    title: a.title(HikkaPrefs.instance.titleLang),
    entries: [
      if (canContinue)
        AppMenuEntry(cont, 'Продовжити · серія ${done + 1}', icon: (c) => LineIconView(LineIcon.play, size: 18 * scale, color: c))
      else
        AppMenuEntry(open, 'Відкрити', icon: (c) => LineIconView(LineIcon.openOut, size: 19 * scale, color: c)),
      if (signedIn) AppMenuEntry(list, 'Мій список…', icon: (c) => HikkaListMark(status: status, size: 19 * scale, color: c)),
      if (onRemove != null) ...[
        const AppMenuEntry<String>.divider(),
        AppMenuEntry(remove, removeLabel, danger: true, icon: (c) => LineIconView(LineIcon.trash, size: 19 * scale, color: c)),
      ],
    ],
  );
  if (!context.mounted) return;
  switch (picked) {
    case open:
      (onOpen ?? () => HikkaNav.instance.openAnime(a.slug, seed: a))();
    case cont:
      await hikkaContinue(context, a, scale);
    case list:
      await showHikkaListSheet(context, anime: a, scale: scale);
    case remove:
      onRemove?.call();
  }
}

/// A grey line under a card title: parts joined by " · "; every "★" becomes the line star
class HikkaMetaLine extends StatelessWidget {
  final String text;
  final double scale;
  final double size;
  final Color? color;
  final int maxLines;

  const HikkaMetaLine({super.key, required this.text, required this.scale, this.size = 12, this.color, this.maxLines = 1});

  @override
  Widget build(BuildContext context) {
    final c = color ?? uiTheme.textMuted;
    final style = TextStyle(fontFamily: 'Arial', color: c, fontSize: size * scale, height: 1.25);
    final parts = text.split('★');
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          for (int i = 0; i < parts.length; i++) ...[
            if (i > 0)
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Padding(
                  padding: EdgeInsets.only(bottom: 1 * scale),
                  child: LineIconView(LineIcon.star, size: size * scale, color: c, stroke: 1.8),
                ),
              ),
            TextSpan(text: parts[i]),
          ],
        ],
      ),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// Anime card: a clean poster (a thin progress bar at its bottom when given), the title on two lines and a grey line
/// "2013 · ★ 8.58". A tap opens the anime page; a long press (on a PC, the right button) opens the card menu.
class HikkaAnimeCard extends StatelessWidget {
  final HikkaAnime anime;
  final double scale;

  /// The grey line instead of "year · ★ score" (e.g. "6 з 25 · ★ 8"); "★" is drawn as the line star
  final String? caption;

  /// Watched share 0…1: a thin accent bar at the bottom of the poster
  final double? progress;
  final VoidCallback? onTap;

  /// If set, the card menu also has [removeLabel] in red
  final VoidCallback? onRemove;
  final String removeLabel;

  /// Episodes watched, for "Продовжити · серія N" in the menu (by default from the list and local marks)
  final int? seen;

  const HikkaAnimeCard({
    super.key,
    required this.anime,
    required this.scale,
    this.caption,
    this.progress,
    this.onTap,
    this.onRemove,
    this.removeLabel = 'Прибрати зі списку',
    this.seen,
  });

  /// The default grey line: the year and the score
  static String metaOf(HikkaAnime a) => [
        if (a.year != null) '${a.year}',
        if (a.hasScore) '★ ${a.score.toStringAsFixed(2)}',
      ].join(' · ');

  /// "TV Серіал · 2023" (lists)
  static String typeYearOf(HikkaAnime a) => [
        if (a.typeLabel.isNotEmpty) a.typeLabel,
        if (a.year != null) '${a.year}',
      ].join(' · ');

  Future<void> _menu(BuildContext context, {Offset? at}) async {
    final rect = at != null ? Rect.fromLTWH(at.dx, at.dy, 1, 1) : appRectOf(context);
    await showHikkaCardMenu(
      context,
      anime: anime,
      scale: scale,
      anchor: rect,
      seen: seen,
      // A long press lifts the card over the dimmed screen; the right button just opens the menu at the cursor
      lift: at != null ? null : HikkaAnimeCard(anime: anime, scale: scale, caption: caption, progress: progress),
      onRemove: onRemove,
      removeLabel: removeLabel,
      onOpen: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = anime.title(HikkaPrefs.instance.titleLang);
    final sub = caption ?? metaOf(anime);
    final r = uiTheme.borderRadius(12 * scale);
    final p = progress;
    return Semantics(
      button: true,
      label: sub.isEmpty ? title : '$title. ${sub.replaceAll('★', 'оцінка')}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap ?? () => HikkaNav.instance.openAnime(anime.slug, seed: anime),
        onLongPress: () => unawaited(_menu(context)),
        onSecondaryTapDown: (d) => unawaited(_menu(context, at: d.globalPosition)),
        borderRadius: r,
        splashColor: Colors.transparent,
        highlightColor: uiTheme.touchHighlight,
        hoverColor: uiTheme.hoverOverlay,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            HikkaPoster(
              url: anime.image,
              malId: anime.malId,
              scale: scale,
              radius: 12,
              icon: Symbols.movie_rounded,
              overlay: Stack(
                children: [
                  if (anime.isAdult)
                    Positioned(right: 6 * scale, top: 6 * scale, child: HikkaPill(text: '18+', scale: scale, background: const Color(0xC7C62828))),
                  if (p != null && p > 0)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: HikkaProgressBar(value: p, height: 4 * scale, track: const Color(0xD9141416)),
                    ),
                ],
              ),
            ),
            SizedBox(height: 7 * scale),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: 'Arial', color: uiTheme.textPrimary, fontSize: 13 * scale, height: 1.25),
            ),
            if (sub.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(top: 3 * scale),
                child: HikkaMetaLine(text: sub, scale: scale),
              ),
          ],
        ),
      ),
    );
  }
}

/// A thin progress bar: the accent part over a dark track
class HikkaProgressBar extends StatelessWidget {
  final double value;
  final double height;
  final Color? track;

  const HikkaProgressBar({super.key, required this.value, required this.height, this.track});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: track ?? AppTones.track),
          FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: value.clamp(0.0, 1.0),
            child: ColoredBox(color: uiTheme.accentColor),
          ),
        ],
      ),
    );
  }
}

/// Character card: a portrait, the name on two lines, a label (role or number of anime)
class HikkaCharacterCard extends StatelessWidget {
  final HikkaCharacter character;
  final double scale;
  final String? caption;
  final VoidCallback? onTap;

  /// The title page's look: a rounder portrait and only the name in one quiet line
  final bool plain;

  const HikkaCharacterCard({super.key, required this.character, required this.scale, this.caption, this.onTap, this.plain = false});

  @override
  Widget build(BuildContext context) {
    final r = uiTheme.borderRadius(12 * scale);
    final sub = plain ? '' : (caption ?? '');
    return Semantics(
      button: true,
      label: sub.isEmpty ? character.name : '${character.name}. $sub',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap ?? () => HikkaNav.instance.openCharacter(character.slug, seed: character),
        borderRadius: r,
        splashColor: Colors.transparent,
        highlightColor: uiTheme.touchHighlight,
        hoverColor: uiTheme.hoverOverlay,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            HikkaPoster(url: character.image, scale: scale, icon: Symbols.person_rounded, radius: 12, aspect: plain ? 84 / 118 : 0.7),
            SizedBox(height: (plain ? 5 : 7) * scale),
            // The name in a regular face, as under an anime card; the anime (a voiced role) in a grey line
            Text(
              character.name,
              maxLines: plain ? 1 : 2,
              overflow: TextOverflow.ellipsis,
              style: plain
                  ? TextStyle(fontFamily: 'Arial', color: Color.lerp(uiTheme.textSecondary, uiTheme.textPrimary, 0.5), fontSize: 12 * scale, height: 1.2)
                  : hikkaStyle(13 * scale, height: 1.25),
            ),
            if (sub.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(top: 3 * scale),
                child: Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: hikkaStyle(12 * scale, color: uiTheme.textMuted, height: 1.3)),
              ),
          ],
        ),
      ),
    );
  }
}

/// Crew member or actor card: a portrait, name, roles; a tap opens the person's page
class HikkaPersonCard extends StatelessWidget {
  final HikkaPerson person;
  final double scale;
  final String? caption;

  const HikkaPersonCard({super.key, required this.person, required this.scale, this.caption});

  @override
  Widget build(BuildContext context) {
    final r = uiTheme.borderRadius(10 * scale);
    final sub = caption ?? '';
    return Semantics(
      button: true,
      label: sub.isEmpty ? person.name : '${person.name}. $sub',
      excludeSemantics: true,
      child: InkWell(
        onTap: () => HikkaNav.instance.openPerson(person.slug, seed: person),
        borderRadius: r,
        splashColor: Colors.transparent,
        highlightColor: uiTheme.touchHighlight,
        hoverColor: uiTheme.hoverOverlay,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            HikkaPoster(url: person.image, scale: scale, icon: Symbols.person_rounded),
            SizedBox(height: 7 * scale),
            Text(
              person.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: 'Arial', color: uiTheme.textPrimary, fontSize: 12.5 * scale, fontWeight: FontWeight.w600, height: 1.25),
            ),
            if (sub.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(top: 3 * scale),
                child: Text(
                  sub,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: 'Arial', color: uiTheme.textMuted, fontSize: 11 * scale, height: 1.25),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// List row: a poster thumbnail, title, small marks and a label; on the right a widget if needed
class HikkaAnimeRow extends StatelessWidget {
  final HikkaAnime anime;
  final double scale;

  /// Label above the title (a franchise relation: "Сиквел", "Рекап")
  final String? label;
  final bool highlighted;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const HikkaAnimeRow({
    super.key,
    required this.anime,
    required this.scale,
    this.label,
    this.highlighted = false,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final title = anime.title(HikkaPrefs.instance.titleLang);
    final meta = subtitle ??
        [
          if (anime.typeLabel.isNotEmpty) anime.typeLabel,
          if (anime.seasonLabel.isNotEmpty) anime.seasonLabel,
          if (anime.episodesLabel.isNotEmpty) anime.episodesLabel,
        ].join(' · ');
    final grey = AppTones.rowSub;
    // The title one came from sits in a frame with "Ви тут"; the others are flat rows
    final shape = RoundedRectangleBorder(
      borderRadius: uiTheme.borderRadius(14 * scale),
      side: highlighted ? BorderSide(color: AppTones.plateOutline) : BorderSide.none,
    );
    return Semantics(
      button: true,
      selected: highlighted,
      child: Material(
        color: highlighted ? AppTones.menu : Colors.transparent,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          splashColor: Colors.transparent,
          highlightColor: uiTheme.touchHighlight,
          hoverColor: uiTheme.hoverOverlay,
          onTap: onTap ?? () => HikkaNav.instance.openAnime(anime.slug, seed: anime),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 10 * scale),
            child: Row(
              children: [
                SizedBox(
                  width: 52 * scale,
                  child: HikkaPoster(url: anime.image, malId: anime.malId, scale: scale, radius: 8, aspect: 52 / 74, icon: Symbols.movie_rounded),
                ),
                SizedBox(width: 12 * scale),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (label != null || highlighted)
                        Padding(
                          padding: EdgeInsets.only(bottom: 3 * scale),
                          child: Row(
                            children: [
                              if (label != null) Flexible(child: Text(label!, maxLines: 1, overflow: TextOverflow.ellipsis, style: hikkaStyle(12 * scale, color: uiTheme.textMuted))),
                              if (highlighted)
                                Container(
                                  key: const ValueKey('franchise-here'),
                                  margin: EdgeInsets.only(left: label != null ? 6 * scale : 0),
                                  padding: EdgeInsets.symmetric(horizontal: 7 * scale, vertical: 2 * scale),
                                  decoration: BoxDecoration(color: AppTones.plateOn, borderRadius: uiTheme.borderRadius(6 * scale)),
                                  child: Text('Ви тут', style: hikkaStyle(11.5 * scale, color: AppTones.plateText)),
                                ),
                            ],
                          ),
                        ),
                      Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: hikkaStyle(15 * scale, weight: FontWeight.bold, height: 1.25)),
                      if (meta.isNotEmpty || anime.hasScore)
                        Padding(
                          padding: EdgeInsets.only(top: 4 * scale),
                          child: Text.rich(
                            TextSpan(
                              style: hikkaStyle(12.5 * scale, color: grey, height: 1.3),
                              children: [
                                TextSpan(text: meta),
                                if (anime.hasScore) ...[
                                  TextSpan(text: meta.isEmpty ? '' : ' · '),
                                  WidgetSpan(
                                    alignment: PlaceholderAlignment.middle,
                                    child: Padding(
                                      padding: EdgeInsets.only(right: 3 * scale),
                                      child: LineIconView(LineIcon.star, size: 12 * scale, color: grey, stroke: 1.8),
                                    ),
                                  ),
                                  TextSpan(text: anime.score.toStringAsFixed(2)),
                                ],
                              ],
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                ),
                if (trailing != null) ...[SizedBox(width: 8 * scale), trailing!],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
