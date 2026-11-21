import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../services/continue_watching.dart';
import '../../services/hikka_nav.dart';
import '../../services/hikka_prefs.dart';
import '../../services/quick_play.dart';
import 'hikka_watch_dialogs.dart';
import '../../services/ui_theme_service.dart';
import '../../services/watch_store.dart';
import '../app_tones.dart';
import '../design_kit.dart' show appRectOf;
import '../line_icons.dart';
import 'hikka_cards.dart';
import 'hikka_common.dart';

/// A horizontal "Продовжити перегляд" card: a thumbnail, title, episode and when watched. A tap opens the player right away
/// on the episode where the person stopped; if the dub is not found, the title page opens.
class HikkaContinueCard extends StatefulWidget {
  final ContinueItem item;
  final double scale;

  const HikkaContinueCard({super.key, required this.item, required this.scale});

  /// Card sizes (width, height) for a shelf
  static double width(double scale) => 262 * scale;
  static double height(double scale) => 96 * scale;

  @override
  State<HikkaContinueCard> createState() => _HikkaContinueCardState();
}

class _HikkaContinueCardState extends State<HikkaContinueCard> {
  bool _busy = false;

  Future<void> _open() async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await QuickPlay.resume(
      widget.item.anime,
      onMissingNext: (plan, next) => mounted ? WatchDialogs.missingNext(context, scale: widget.scale, plan: plan, next: next) : Future.value(null),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) HikkaNav.instance.openAnime(widget.item.anime.slug, seed: widget.item.anime);
  }

  /// The card menu: "Відкрити" (the tap already continues), "Мій список…", "Прибрати з «Продовжити»" in red
  Future<void> _menu({Offset? at}) async {
    final a = widget.item.anime;
    await showHikkaCardMenu(
      context,
      anime: a,
      scale: widget.scale,
      anchor: at != null ? Rect.fromLTWH(at.dx, at.dy, 1, 1) : appRectOf(context),
      lift: at != null ? null : HikkaContinueCard(item: widget.item, scale: widget.scale),
      seen: 0,
      removeLabel: 'Прибрати з «Продовжити»',
      onRemove: () => WatchStore.instance.forgetLast('${ContinueWatching.prefix}${a.slug}'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.scale;
    final it = widget.item;
    final a = it.anime;
    final title = a.title(HikkaPrefs.instance.titleLang);
    final total = a.episodesTotal ?? 0;
    var episode = it.episodeLabel;
    // "Серія 6 з 25": the total only after a plain episode number
    if (episode != null && total > 0 && RegExp(r'^Серія \d+$').hasMatch(episode)) episode = '$episode з $total';
    final sub = [if (episode != null) episode, if (it.dubName.isNotEmpty) it.dubName].join(' · ');
    final tag = it.hasNew ? (it.dubName.isEmpty ? 'Нова серія' : 'Нова серія · ${it.dubName}') : (it.notInList ? 'Не в списку' : null);
    final progress = total > 0 ? (it.watched / total).clamp(0.0, 1.0) : 0.0;
    final r = uiTheme.borderRadius(14 * scale);
    return Semantics(
      button: true,
      label: 'Продовжити: $title. $sub',
      excludeSemantics: true,
      child: Material(
        color: uiTheme.bgSurface,
        shape: RoundedRectangleBorder(borderRadius: r, side: BorderSide(color: uiTheme.borderSubtle)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _open,
          onLongPress: () => unawaited(_menu()),
          onSecondaryTapDown: (d) => unawaited(_menu(at: d.globalPosition)),
          splashColor: Colors.transparent,
          highlightColor: uiTheme.touchHighlight,
          hoverColor: uiTheme.hoverOverlay,
          child: Stack(
            children: [
              Padding(
                padding: EdgeInsets.all(8 * scale),
                child: Row(
                  children: [
                    SizedBox(
                      width: 56 * scale,
                      height: 80 * scale,
                      child: HikkaPoster(url: a.image, malId: a.malId, scale: scale, radius: 9, aspect: 56 / 80, icon: Symbols.movie_rounded, border: false),
                    ),
                    SizedBox(width: 12 * scale),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: hikkaStyle(14 * scale, weight: FontWeight.bold, height: 1.25)),
                          if (sub.isNotEmpty) ...[
                            SizedBox(height: 4 * scale),
                            Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: hikkaStyle(12 * scale, color: uiTheme.textMuted)),
                          ],
                          if (tag != null) ...[
                            SizedBox(height: 3 * scale),
                            Text(tag, maxLines: 1, overflow: TextOverflow.ellipsis, style: hikkaStyle(11.5 * scale, weight: FontWeight.w600, color: it.hasNew ? uiTheme.accentColor : uiTheme.textDarkMuted)),
                          ],
                        ],
                      ),
                    ),
                    SizedBox(width: 8 * scale),
                    Container(
                      width: 36 * scale,
                      height: 36 * scale,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: AppTones.playCircle),
                      alignment: Alignment.center,
                      child: _busy
                          ? SizedBox(width: 16 * scale, height: 16 * scale, child: CircularProgressIndicator(strokeWidth: 2, color: uiTheme.textPrimary))
                          : LineIconView(LineIcon.play, size: 14 * scale, color: uiTheme.isLight ? uiTheme.textPrimary : const Color(0xFFEEEEEE)),
                    ),
                    SizedBox(width: 4 * scale),
                  ],
                ),
              ),
              if (progress > 0)
                Positioned(left: 0, right: 0, bottom: 0, child: HikkaProgressBar(value: progress, height: 3 * scale)),
            ],
          ),
        ),
      ),
    );
  }
}
