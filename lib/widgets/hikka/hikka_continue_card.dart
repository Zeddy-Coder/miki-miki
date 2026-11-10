import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../models/hikka_models.dart';
import '../../services/continue_watching.dart';
import '../../services/hikka_nav.dart';
import '../../services/hikka_prefs.dart';
import '../../services/quick_play.dart';
import '../../services/ui_theme_service.dart';
import '../../services/watch_store.dart';
import '../../utils/platform_info.dart';
import 'hikka_cards.dart';
import 'hikka_common.dart';

/// Горизонтальна картка «Продовжити перегляд»: мініатюра, назва, серія й коли дивились. Тап одразу відкриває плеєр
/// на тій серії, де людина зупинилась; якщо озвучку не знайдено, відкривається сторінка тайтлу.
class HikkaContinueCard extends StatefulWidget {
  final ContinueItem item;
  final double scale;

  const HikkaContinueCard({super.key, required this.item, required this.scale});

  /// Розміри картки (ширина, висота) для полиці
  static double width(double scale) => AppPlatform.isMobile ? 286 : 320 * scale;
  static double height(double scale) => AppPlatform.isMobile ? 104 : 112 * scale;

  @override
  State<HikkaContinueCard> createState() => _HikkaContinueCardState();
}

class _HikkaContinueCardState extends State<HikkaContinueCard> {
  bool _busy = false;

  Future<void> _open() async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await QuickPlay.resume(widget.item.anime);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) HikkaNav.instance.openAnime(widget.item.anime.slug, seed: widget.item.anime);
  }

  Future<void> _menu(Offset at) async {
    if (await showHikkaRemoveMenu(context, at, widget.scale)) {
      WatchStore.instance.forgetLast('${ContinueWatching.prefix}${widget.item.anime.slug}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.scale;
    final it = widget.item;
    final a = it.anime;
    final title = a.title(HikkaPrefs.instance.titleLang);
    final sub = [
      if (it.episodeLabel != null) it.episodeLabel!,
      HikkaText.dayName(it.at, DateTime.now()),
    ].join(' · ');
    final r = uiTheme.borderRadius(14 * scale);
    return Semantics(
      button: true,
      label: 'Продовжити: $title. $sub',
      excludeSemantics: true,
      child: Material(
        color: uiTheme.bgElevated.withValues(alpha: 0.6),
        shape: RoundedRectangleBorder(borderRadius: r, side: BorderSide(color: uiTheme.borderSubtle)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _open,
          onLongPress: () {
            final box = context.findRenderObject() as RenderBox;
            _menu(box.localToGlobal(Offset(box.size.width / 2, box.size.height / 2)));
          },
          onSecondaryTapDown: (d) => _menu(d.globalPosition),
          splashColor: Colors.transparent,
          highlightColor: uiTheme.touchHighlight,
          hoverColor: uiTheme.hoverOverlay,
          child: Row(
            children: [
              AspectRatio(
                aspectRatio: 0.7,
                child: HikkaPoster(url: a.image, scale: scale, radius: 0, icon: Symbols.movie_rounded),
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(12 * scale, 10 * scale, 8 * scale, 10 * scale),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: hikkaStyle(13.5 * scale, weight: FontWeight.bold, height: 1.25),
                      ),
                      SizedBox(height: 6 * scale),
                      Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: hikkaStyle(12 * scale, color: uiTheme.textMuted)),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.only(right: 12 * scale),
                child: SizedBox(
                  width: 40 * scale,
                  height: 40 * scale,
                  child: DecoratedBox(
                    decoration: BoxDecoration(shape: BoxShape.circle, color: uiTheme.accentColor),
                    child: Center(
                      child: _busy
                          ? SizedBox(
                              width: 18 * scale,
                              height: 18 * scale,
                              child: CircularProgressIndicator(strokeWidth: 2.2, color: uiTheme.onAccent),
                            )
                          : Icon(Symbols.play_arrow_rounded, color: uiTheme.onAccent, size: 26 * scale, fill: 1),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
