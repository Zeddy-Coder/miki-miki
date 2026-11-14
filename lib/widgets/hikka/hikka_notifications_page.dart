import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../models/hikka_models.dart';
import '../../services/episode_alerts.dart';
import '../../services/hikka_nav.dart';
import '../../services/push_notifications.dart';
import '../../services/ui_theme_service.dart';
import '../../utils/app_clock.dart';
import '../app_animation_kit.dart';
import 'hikka_common.dart';
import 'hikka_page_kit.dart';
import 'hikka_watch_dialogs.dart';

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

  void _open(EpisodeAlert a) {
    _alerts.markRead(a.id);
    if (a.slug.isNotEmpty) HikkaNav.instance.openAnime(a.slug);
  }

  Widget _row(EpisodeAlert a, DateTime now, double pad) {
    final scale = _scale;
    return InkWell(
      key: ValueKey('alert-${a.id}'),
      onTap: () => _open(a),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: pad, vertical: 11 * scale),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 50 * scale,
              child: HikkaPoster(
                url: a.image,
                scale: scale,
                radius: 8,
                icon:
                    a.isEpisode
                        ? Symbols.movie_rounded
                        : (a.type == 'update'
                            ? Symbols.system_update_rounded
                            : Symbols.campaign_rounded),
              ),
            ),
            SizedBox(width: 14 * scale),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    a.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: hikkaStyle(
                      14 * scale,
                      weight: FontWeight.w600,
                      height: 1.25,
                    ),
                  ),
                  SizedBox(height: 3 * scale),
                  Text(
                    a.headline,
                    maxLines: a.isEpisode ? 1 : 4,
                    overflow: TextOverflow.ellipsis,
                    style: hikkaStyle(
                      13 * scale,
                      color: uiTheme.accentColor,
                      weight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 2 * scale),
                  Text(
                    '${a.isEpisode ? '${a.dubLine} · ' : (a.type == 'update' ? 'Оновлення · ' : 'Від розробника · ')}${HikkaNotificationsPage.ago(a.at, now)}',
                    style: hikkaStyle(
                      12 * scale,
                      color: uiTheme.textMuted,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            if (!a.read)
              Padding(
                padding: EdgeInsets.only(left: 8 * scale, top: 4 * scale),
                child: Container(
                  key: const ValueKey('alert-unread'),
                  width: 9 * scale,
                  height: 9 * scale,
                  decoration: BoxDecoration(
                    color: uiTheme.accentColor,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _empty(double pad) {
    final scale = _scale;
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 56 * scale, pad, 18 * scale),
      child: Column(
        children: [
          Icon(
            Symbols.notifications_rounded,
            size: 40 * scale,
            color: uiTheme.textDarkMuted,
            weight: 300,
          ),
          SizedBox(height: 12 * scale),
          Text(
            'Поки що тихо',
            style: hikkaStyle(15 * scale, weight: FontWeight.w600),
          ),
          SizedBox(height: 6 * scale),
          Text(
            'Тут з’являтимуться нові серії тайтлів, які ви дивитесь, — в озвученні чи субтитрах, які ви для них обрали. '
            'Вихід в Японії без українського озвучення сповіщень не дає.',
            textAlign: TextAlign.center,
            style: hikkaStyle(
              13 * scale,
              color: uiTheme.textMuted,
              height: 1.45,
            ),
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
    return HikkaPageFrame(
      scale: scale,
      controller: _scroll,
      bottomInset: widget.bottomInset,
      onRefresh: _refresh,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(pad, 4 * scale, pad, 8 * scale),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  items.isEmpty ? 'Сповіщення' : 'Нові серії та повідомлення',
                  style: hikkaStyle(15 * scale, weight: FontWeight.bold),
                ),
              ),
              if (_loading)
                SizedBox(
                  width: 16 * scale,
                  height: 16 * scale,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: uiTheme.accentColor,
                  ),
                )
              else if (_alerts.unread > 0)
                HikkaLinkButton(
                  label: 'Прочитати все',
                  scale: scale,
                  onTap: _alerts.markAllRead,
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
                padding: EdgeInsets.fromLTRB(pad, 0, pad, 10 * scale),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    HikkaToggleRow(
                      scale: scale,
                      title: 'Push про нові серії',
                      subtitle:
                          'Сповіщення на телефоні, навіть коли застосунок закрито. Перевірка раз на 30 хвилин.',
                      value: push.enabled,
                      onChanged: (v) => push.setEnabled(v),
                    ),
                    if (push.problem != null)
                      Padding(
                        padding: EdgeInsets.only(top: 6 * scale),
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
        if (items.isEmpty)
          _empty(pad)
        else
          for (int i = 0; i < items.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                indent: pad,
                endIndent: pad,
                color: uiTheme.borderSubtle,
              ),
            _row(items[i], now, pad),
          ],
      ],
    );
  }
}
