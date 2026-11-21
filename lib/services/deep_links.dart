import 'app_log.dart';
import 'app_updater.dart';
import 'hikka_auth.dart';
import 'hikka_nav.dart';

/// `miki://open/…` links that open the app from outside (a browser, a message, another app).
///
/// Supported:
/// - `miki://open`: just open the app (the page redirects here after Hikka sign-in);
/// - `miki://open/anime/<slug>`, `/character/<slug>`, `/collection/<id>`, `/article/<slug>`: open a page;
/// - `miki://open/update`: the "Доступне оновлення" window (a tap on a "new version" notification);
/// - `miki://open/notifications`: the "Сповіщення" page (a tap on an announcement);
/// - `miki://open/downloads`: the "Завантаження" page (a tap on the downloads' notification);
/// - `miki://open/auth?reference=<code>`: finish Hikka sign-in, but only while a sign-in is actually in progress
///   (a foreign link cannot silently sign you in to someone else's account).
class DeepLinks {
  DeepLinks._();

  static const String scheme = 'miki';
  static const String host = 'open';

  static final RegExp _id = RegExp(r'^[A-Za-z0-9._\-]{1,160}$');

  /// Shareable link to a title page
  static String anime(String slug) => '$scheme://$host/anime/$slug';

  /// Handles a link. `true`: recognized and executed (or it is just an open), `false`: ignored.
  static bool handle(String link, {HikkaNav? nav, HikkaAuth? auth, AppUpdater? updater}) {
    final uri = Uri.tryParse(link.trim());
    if (uri == null || uri.scheme != scheme || uri.host != host) return false;
    final seg = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (seg.isEmpty) return true;

    final n = nav ?? HikkaNav.instance;
    switch (seg.first) {
      case 'auth':
        final a = auth ?? HikkaAuth.instance;
        final ref = uri.queryParameters['reference'] ?? uri.queryParameters['request_reference'];
        if (ref == null || ref.isEmpty || a.phase != HikkaAuthPhase.waiting) {
          AppLog.w('посилання', 'код входу проігноровано: вхід не очікується');
          return false;
        }
        return a.submit(ref);
      case 'update':
        (updater ?? AppUpdater.instance).requestPrompt();
        return true;
      case 'notifications':
        n.openNotifications();
        return true;
      case 'downloads':
        n.openDownloads();
        return true;
      case 'anime' || 'character' || 'collection' || 'article':
        if (seg.length < 2 || !_id.hasMatch(seg[1])) return false;
        final id = seg[1];
        switch (seg.first) {
          case 'anime':
            n.openAnime(id);
          case 'character':
            n.openCharacter(id);
          case 'collection':
            n.openCollection(id);
          default:
            n.openArticle(id);
        }
        return true;
    }
    return false;
  }
}
