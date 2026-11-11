import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../models/hikka_models.dart';
import '../../models/hikka_user_models.dart';
import '../../services/hikka_lists.dart';
import '../../services/hikka_nav.dart';
import '../../services/hikka_prefs.dart';
import '../../services/ui_theme_service.dart';
import '../app_ui_kit.dart';
import 'hikka_common.dart';
import 'hikka_my_list_bar.dart';

/// Дії контекстного меню тайтла
enum HikkaItemAction { open, markWatched, remove }

/// Контекстне меню тайтла (довгий дотик / права кнопка миші): «Відкрити», «Позначити як переглянуте» (лише коли
/// людина ввійшла) і, якщо [canRemove], «Прибрати зі списку». Повертає вибрану дію або null.
Future<HikkaItemAction?> showHikkaItemMenu(BuildContext context, Offset at, double scale, {bool canRemove = true}) async {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  PopupMenuItem<HikkaItemAction> item(HikkaItemAction v, IconData icon, String text) => PopupMenuItem<HikkaItemAction>(
        value: v,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20 * scale, color: uiTheme.colors.textMuted),
            SizedBox(width: 10 * scale),
            Text(text, style: hikkaStyle(13.5 * scale, color: uiTheme.colors.textPrimary)),
          ],
        ),
      );
  return showMenu<HikkaItemAction>(
    context: context,
    color: uiTheme.colors.drawerBg,
    shape: RoundedRectangleBorder(
      borderRadius: uiTheme.borderRadius(12 * scale),
      side: BorderSide(color: uiTheme.colors.drawerBorder),
    ),
    position: RelativeRect.fromRect(at & const Size(1, 1), Offset.zero & overlay.size),
    items: [
      item(HikkaItemAction.open, Symbols.open_in_new_rounded, 'Відкрити'),
      if (HikkaMyList.instance.signedIn) item(HikkaItemAction.markWatched, Symbols.check_circle_rounded, 'Позначити як переглянуте'),
      if (canRemove) item(HikkaItemAction.remove, Symbols.playlist_remove_rounded, 'Прибрати зі списку'),
    ],
  );
}

/// «Позначити як переглянуте»: статус «Переглянуто», лічильник серій добивається до кінця
Future<void> markHikkaWatched(HikkaAnime a) async {
  try {
    await HikkaMyList.instance.save(a.slug, status: HikkaWatchStatus.completed, total: a.episodesTotal, anime: a);
  } catch (_) {}
}

/// Картка аніме: постер з оцінкою, назва в два рядки, тип і рік. Натискання відкриває сторінку аніме.
class HikkaAnimeCard extends StatelessWidget {
  final HikkaAnime anime;
  final double scale;

  /// Підпис замість «тип · рік» (наприклад «Сьогодні, 18:30»)
  final String? caption;

  /// Плашка у верхньому лівому куті постера (наприклад «Серія 5»)
  final String? pill;

  /// Колір плашки (за замовчуванням акцент)
  final Color? pillColor;
  final VoidCallback? onTap;

  /// Якщо задано, у контекстному меню (довгий дотик / права кнопка миші) є ще «Прибрати зі списку»
  final VoidCallback? onRemove;

  /// Смужка зі статусом зі «Списків» унизу постера (лише коли людина ввійшла й тайтл у її списках)
  final bool showStatus;

  const HikkaAnimeCard({
    super.key,
    required this.anime,
    required this.scale,
    this.caption,
    this.pill,
    this.pillColor,
    this.onTap,
    this.onRemove,
    this.showStatus = true,
  });

  Future<void> _menu(BuildContext context, Offset at) async {
    final pick = await showHikkaItemMenu(context, at, scale, canRemove: onRemove != null);
    switch (pick) {
      case HikkaItemAction.open:
        if (onTap != null) {
          onTap!();
        } else {
          HikkaNav.instance.openAnime(anime.slug, seed: anime);
        }
      case HikkaItemAction.markWatched:
        await markHikkaWatched(anime);
      case HikkaItemAction.remove:
        onRemove?.call();
      case null:
        break;
    }
  }

  Offset _centerOf(BuildContext context) {
    final box = context.findRenderObject() as RenderBox;
    return box.localToGlobal(Offset(box.size.width / 2, box.size.height / 3));
  }

  static String metaOf(HikkaAnime a) {
    final parts = <String>[
      if (a.typeLabel.isNotEmpty) a.typeLabel,
      if (a.year != null) '${a.year}',
    ];
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final title = anime.title(HikkaPrefs.instance.titleLang);
    final sub = caption ?? metaOf(anime);
    final r = uiTheme.borderRadius(10 * scale);
    return Semantics(
      button: true,
      label: sub.isEmpty ? title : '$title. $sub',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap ?? () => HikkaNav.instance.openAnime(anime.slug, seed: anime),
        onLongPress: () => _menu(context, _centerOf(context)),
        onSecondaryTapDown: (d) => _menu(context, d.globalPosition),
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
              icon: Symbols.movie_rounded,
              overlay: ListenableBuilder(
                listenable: HikkaMyList.instance,
                builder: (context, _) {
                  final status = showStatus ? HikkaMyList.instance.statusOf(anime.slug) : null;
                  return Stack(
                children: [
                  if (status != null || pill != null || anime.hasScore)
                    Positioned(
                      left: 6 * scale,
                      right: (anime.isAdult ? 40 : 6) * scale,
                      top: 6 * scale,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (status != null)
                              HikkaPill(text: status.label, scale: scale, background: Color.lerp(hikkaStatusColor(status), Colors.black, 0.22)!.withValues(alpha: 0.84), foreground: Colors.white, weight: FontWeight.w400, size: 11.5),
                            if (pill != null)
                              HikkaPill(
                                text: pill!,
                                scale: scale,
                                background: pillColor != null ? Color.lerp(pillColor, Colors.black, 0.22)!.withValues(alpha: 0.84) : uiTheme.accentColor.withValues(alpha: 0.92),
                                foreground: pillColor != null ? Colors.white : uiTheme.onAccent,
                                weight: pillColor != null ? FontWeight.w400 : FontWeight.bold,
                                size: pillColor != null ? 11.5 : 10.5,
                              ),
                            if ((status != null || pill != null) && anime.hasScore) SizedBox(width: 4 * scale),
                            if (anime.hasScore) HikkaScoreBadge(score: anime.score, scale: scale),
                          ],
                        ),
                      ),
                    ),
                  if (anime.isAdult)
                    Positioned(right: 6 * scale, top: 6 * scale, child: HikkaPill(text: '18+', scale: scale, background: const Color(0xC7C62828))),
                ],
              );
                },
              ),
            ),
            SizedBox(height: 7 * scale),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: 'Arial', color: uiTheme.textPrimary, fontSize: 12.5 * scale, fontWeight: FontWeight.w600, height: 1.25),
            ),
            if (sub.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(top: 3 * scale),
                child: Text(
                  sub,
                  maxLines: 1,
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

/// Картка персонажа: портрет, ім'я в два рядки, підпис (роль чи кількість аніме)
class HikkaCharacterCard extends StatelessWidget {
  final HikkaCharacter character;
  final double scale;
  final String? caption;
  final VoidCallback? onTap;

  const HikkaCharacterCard({super.key, required this.character, required this.scale, this.caption, this.onTap});

  @override
  Widget build(BuildContext context) {
    final r = uiTheme.borderRadius(10 * scale);
    final sub = caption ?? '';
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
            HikkaPoster(url: character.image, scale: scale, icon: Symbols.person_rounded),
            SizedBox(height: 7 * scale),
            Text(
              character.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: 'Arial', color: uiTheme.textPrimary, fontSize: 12.5 * scale, fontWeight: FontWeight.w600, height: 1.25),
            ),
            if (sub.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(top: 3 * scale),
                child: Text(
                  sub,
                  maxLines: 1,
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

/// Рядок списку: мініатюра постера, назва, дрібні мітки й підпис; праворуч за потреби віджет
class HikkaAnimeRow extends StatelessWidget {
  final HikkaAnime anime;
  final double scale;

  /// Мітка над назвою (зв'язок у франшизі: «Сиквел», «Рекап»)
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
    final double posterW = 54 * scale;
    return AppCard(
      scale: scale,
      radius: 10,
      isHighlighted: highlighted,
      onTap: onTap ?? () => HikkaNav.instance.openAnime(anime.slug, seed: anime),
      padding: EdgeInsets.all(10 * scale),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: posterW,
            child: HikkaPoster(url: anime.image, malId: anime.malId, scale: scale, radius: 7, icon: Symbols.movie_rounded),
          ),
          SizedBox(width: 12 * scale),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (label != null)
                  Padding(
                    padding: EdgeInsets.only(bottom: 3 * scale),
                    child: Text(
                      label!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontFamily: 'Arial', color: uiTheme.accentColor, fontSize: 11 * scale, fontWeight: FontWeight.bold),
                    ),
                  ),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: 'Arial', color: uiTheme.textPrimary, fontSize: 13 * scale, fontWeight: FontWeight.w600, height: 1.25),
                ),
                if (meta.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.only(top: 3 * scale),
                    child: Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontFamily: 'Arial', color: uiTheme.textMuted, fontSize: 11.5 * scale),
                    ),
                  ),
                if (anime.hasScore)
                  Padding(
                    padding: EdgeInsets.only(top: 4 * scale),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Symbols.star_rounded, color: const Color(0xFFFFC23D), size: 14 * scale, fill: 1),
                        SizedBox(width: 3 * scale),
                        Text(
                          anime.score.toStringAsFixed(2),
                          style: TextStyle(fontFamily: 'Arial', color: uiTheme.textPrimary, fontSize: 11.5 * scale, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (trailing != null) ...[SizedBox(width: 8 * scale), trailing!],
        ],
      ),
    );
  }
}
