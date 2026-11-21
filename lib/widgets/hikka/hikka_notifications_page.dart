import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../models/hikka_models.dart';
import '../../services/app_updater.dart';
import '../../services/episode_alerts.dart';
import '../../services/hikka_nav.dart';
import '../../services/push_notifications.dart';
import '../../services/ui_theme_service.dart';
import '../../utils/app_clock.dart';
import '../app_animation_kit.dart';
import '../app_tones.dart';
import '../design_kit.dart';
import '../line_icons.dart';
import 'hikka_common.dart';
import 'hikka_page_kit.dart';
import 'hikka_watch_dialogs.dart';
import '../settings_kit.dart';

/// Notifications: new episodes of titles you are watching, in the dub (or subtitles) you chose for them.
/// The source is the Mikai releases feed; a tap opens the title page.
class HikkaNotificationsPage extends StatefulWidget {
  final HikkaRoute route;
  final double scale;
  final double bottomInset;

  /// For tests: a custom set of notifications
  final EpisodeAlerts? alerts;

  const HikkaNotificationsPage({
    super.key,
    required this.route,
    required this.scale,
    this.bottomInset = 0,
    this.alerts,
  });

  /// "щойно", "5 хв тому", "3 год тому", "вчора", "11 листопада"
  static String ago(DateTime at, DateTime now) {
    final d = now.difference(at);
    if (d.inMinutes < 1) return 'щойно';
    if (d.inMinutes < 60) return '${d.inMinutes} хв тому';
    final days =
        DateTime(
          now.year,
          now.month,
          now.day,
        ).difference(DateTime(at.year, at.month, at.day)).inDays;
    if (days == 0) return '${d.inHours} год тому';
    if (days == 1) return 'вчора';
    return HikkaText.dayMonth(at, now: now);
  }

  @override
  State<HikkaNotificationsPage> createState() => _HikkaNotificationsPageState();
}

class _HikkaNotificationsPageState extends State<HikkaNotificationsPage> {
  late final ScrollController _scroll = AppSmoothScrollController(
    initialScrollOffset: widget.route.scroll,
  );
  late final EpisodeAlerts _alerts = widget.alerts ?? EpisodeAlerts.instance;
  bool _loading = false;

  double get _scale => widget.scale;

  @override
  void initState() {
    super.initState();
    _alerts.addListener(_onChange);
    _scroll.addListener(_saveScroll);
    // setState is not allowed during build: we start the check after the first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refresh();
    });
  }

  @override
  void dispose() {
    _alerts.removeListener(_onChange);
    _scroll.removeListener(_saveScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _saveScroll() {
    if (_scroll.hasClients) widget.route.scroll = _scroll.offset;
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  /// Opening the page and pull-down are human actions, so we do not limit the frequency
  Future<void> _refresh() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      await _alerts.importInbox(); // pushes the phone has received (Android)
      await _alerts.check(force: true);
    } catch (_) {
      // No network or Mikai did not respond: what already exists stays
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Where the last press landed: the long-press menu opens there
  Offset _lastTap = Offset.zero;

  /// Long press (or right click): pin / unpin and delete, in the shared menu tile
  Future<void> _actions(EpisodeAlert a, Offset at) async {
    final scale = _scale;
    final picked = await showAppMenu<String>(
      context,
      scale: scale,
      anchor: Rect.fromLTWH(at.dx, at.dy, 1, 1),
      width: 220,
      entries: [
        AppMenuEntry('pin', a.pinned ? 'Відкріпити' : 'Закріпити', icon: (c) => LineIconView(LineIcon.pin, size: 19 * scale, color: c)),
        const AppMenuEntry<String>.divider(),
        AppMenuEntry('delete', 'Видалити', danger: true, icon: (c) => LineIconView(LineIcon.trash, size: 19 * scale, color: c)),
      ],
    );
    if (!mounted) return;
    if (picked == 'pin') _alerts.togglePin(a.id);
    if (picked == 'delete') _alerts.remove(a.id);
  }

  void _open(EpisodeAlert a) {
    _alerts.markRead(a.id);
    if (a.type == 'update') {
      // "New version": the update window (it checks first when the version is not known yet)
      AppUpdater.instance.requestPrompt();
    } else if (a.slug.isNotEmpty) {
      HikkaNav.instance.openAnime(a.slug);
    }
  }

  /// A notification: a small poster (a grey tile with a line glyph for a message from the developer), the title (bold
  /// while unread), what happened and, in grey, the dub and when; an accent dot marks the unread
  Widget _row(EpisodeAlert a, DateTime now, double pad) {
    final scale = _scale;
    final Widget picture = a.isEpisode
        ? SizedBox(width: 44 * scale, child: HikkaPoster(url: a.image, scale: scale, radius: 8, aspect: 44 / 62, icon: Symbols.movie_rounded))
        : Container(
            width: 44 * scale,
            height: 44 * scale,
            decoration: BoxDecoration(color: AppTones.plate, borderRadius: uiTheme.borderRadius(12 * scale)),
            child: Center(child: LineIconView(a.type == 'update' ? LineIcon.download : LineIcon.megaphone, size: 22 * scale, color: AppTones.rowIcon)),
          );
    final foot = '${a.isEpisode ? '${a.dubLine} · ' : (a.type == 'update' ? 'Оновлення · ' : 'Від розробника · ')}${HikkaNotificationsPage.ago(a.at, now)}';
    return InkWell(
      key: ValueKey('alert-${a.id}'),
      splashColor: Colors.transparent,
      highlightColor: uiTheme.isLight ? Colors.black.withValues(alpha: 0.06) : Colors.white.withValues(alpha: 0.07),
      hoverColor: uiTheme.hoverOverlay,
      onTap: () => _open(a),
      onTapDown: (d) => _lastTap = d.globalPosition,
      onLongPress: () => unawaited(_actions(a, _lastTap)),
      onSecondaryTapUp: (d) => unawaited(_actions(a, d.globalPosition)),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: pad, vertical: 9 * scale),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            picture,
            SizedBox(width: 12 * scale),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (a.pinned)
                        Padding(
                          padding: EdgeInsets.only(right: 4 * scale, top: 2 * scale),
                          child: LineIconView(LineIcon.pin, key: const ValueKey('alert-pinned'), size: 15 * scale, color: AppTones.rowSub),
                        ),
                      Expanded(
                        child: Text(
                          a.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: hikkaStyle(14.5 * scale, weight: a.read ? FontWeight.normal : FontWeight.bold, height: 1.3),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 3 * scale),
                  Text(
                    a.headline,
                    maxLines: a.isEpisode ? 1 : 4,
                    overflow: TextOverflow.ellipsis,
                    style: hikkaStyle(13.5 * scale, color: AppTones.plateText, height: 1.4),
                  ),
                  SizedBox(height: 3 * scale),
                  Text(foot, style: hikkaStyle(12 * scale, color: uiTheme.textMuted, height: 1.3)),
                ],
              ),
            ),
            if (!a.read)
              Padding(
                padding: EdgeInsets.only(left: 10 * scale, top: 6 * scale),
                child: Container(
                  key: const ValueKey('alert-unread'),
                  width: 8 * scale,
                  height: 8 * scale,
                  decoration: BoxDecoration(color: uiTheme.accentColor, shape: BoxShape.circle),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// The caption an entry stands under: pinned ones first, then by day
  static String _group(EpisodeAlert a, DateTime now) {
    if (a.pinned) return 'Закріплені';
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(a.at.year, a.at.month, a.at.day);
    final diff = today.difference(day).inDays;
    if (diff <= 0) return 'Сьогодні';
    if (diff == 1) return 'Учора';
    if (diff < 7) return 'Цього тижня';
    return 'Раніше';
  }

  Widget _empty(double pad) {
    final scale = _scale;
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 56 * scale, pad, 18 * scale),
      child: Column(
        children: [
          LineIconView(LineIcon.bell, size: 40 * scale, color: AppTones.chevron, stroke: 1.4),
          SizedBox(height: 14 * scale),
          Text('Поки що тихо', style: hikkaStyle(17 * scale, weight: FontWeight.bold)),
          SizedBox(height: 8 * scale),
          Text(
            'Тут з’являтимуться нові серії тайтлів, які ви дивитесь, — в озвученні чи субтитрах, які ви для них обрали. '
            'Вихід в Японії без українського озвучення сповіщень не дає.',
            textAlign: TextAlign.center,
            style: hikkaStyle(13.5 * scale, color: uiTheme.textMuted, height: 1.45),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scale = _scale;
    final pad = HikkaLayout.sidePad(context, scale);
    final items = _alerts.items;
    final now = AppClock.now();
    final unread = items.any((a) => !a.read);
    // Flat rows grouped by day under muted captions (as the groups in the settings); a caption is a piece of its own
    // in the lazy list, so only the rows near the screen are built (a hundred posters at once made opening heavy)
    final pieces = <Object>[];
    for (int i = 0; i < items.length; i++) {
      final group = _group(items[i], now);
      if (i == 0 || group != _group(items[i - 1], now)) pieces.add(group);
      pieces.add(items[i]);
    }
    return HikkaPageFrame(
      scale: scale,
      controller: _scroll,
      bottomInset: widget.bottomInset,
      onRefresh: _refresh,
      itemCount: pieces.length,
      itemBuilder: (context, i) {
        final piece = pieces[i];
        if (piece is EpisodeAlert) return _row(piece, now, pad);
        return Padding(
          padding: EdgeInsets.fromLTRB(pad, (i == 0 ? 6 : 16) * scale, pad, 4 * scale),
          child: Text(piece as String, style: hikkaStyle(13 * scale, color: AppTones.caption, weight: FontWeight.w700)),
        );
      },
      children: [
        // What is here in grey, "Прочитати все" on the right while something is unread
        Padding(
          padding: EdgeInsets.fromLTRB(pad, 0, pad - 6 * scale, 2 * scale),
          child: Row(
            children: [
              Expanded(child: Text('Нові серії та повідомлення', style: hikkaStyle(13 * scale, color: uiTheme.textMuted))),
              if (_loading)
                Padding(
                  padding: EdgeInsets.all(8 * scale),
                  child: SizedBox(
                    width: 16 * scale,
                    height: 16 * scale,
                    child: CircularProgressIndicator(strokeWidth: 2, color: uiTheme.accentColor),
                  ),
                )
              else if (unread)
                Semantics(
                  button: true,
                  child: InkWell(
                    onTap: _alerts.markAllRead,
                    borderRadius: uiTheme.borderRadius(8 * scale),
                    splashColor: Colors.transparent,
                    highlightColor: uiTheme.touchHighlight,
                    hoverColor: uiTheme.hoverOverlay,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6 * scale, vertical: 10 * scale),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          LineIconView(LineIcon.checks, size: 18 * scale, color: AppTones.plateText),
                          SizedBox(width: 6 * scale),
                          Text('Прочитати все', style: hikkaStyle(13.5 * scale, color: AppTones.plateText)),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (PushNotifications.instance.supported)
          ListenableBuilder(
            listenable: PushNotifications.instance,
            builder: (context, _) {
              final push = PushNotifications.instance;
              return Padding(
                padding: EdgeInsets.fromLTRB(pad - 12 * scale, 0, pad - 12 * scale, 4 * scale),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SettingsToggleRow(
                      scale: scale,
                      icon: Symbols.notifications_active_rounded,
                      title: 'Push про нові серії',
                      subtitle:
                          'Сповіщення на телефоні, навіть коли застосунок закрито. Перевірка раз на 30 хвилин.',
                      value: push.enabled,
                      onChanged: (v) => push.setEnabled(v),
                    ),
                    if (push.problem != null)
                      Padding(
                        padding: EdgeInsets.fromLTRB(12 * scale, 6 * scale, 12 * scale, 0),
                        child: Text(
                          push.problem!,
                          style: hikkaStyle(
                            12 * scale,
                            color: uiTheme.textSecondary,
                          ),
                        ),
                      ),
                    if (push.problem?.contains('токен') ?? false) ...[
                      Padding(
                        padding: EdgeInsets.only(top: 6 * scale),
                        child: SelectableText(
                          PushNotifications.requiredDomains.join('\n'),
                          style: hikkaStyle(
                            11.5 * scale,
                            color: uiTheme.textSecondary,
                          ),
                        ),
                      ),
                      QuietAction(
                        label: 'Копіювати домени',
                        scale: scale,
                        onTap:
                            () => Clipboard.setData(
                              ClipboardData(
                                text: PushNotifications.requiredDomains.join(
                                  '\n',
                                ),
                              ),
                            ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        if (items.isEmpty) _empty(pad),
      ],
    );
  }
}
