import 'app_log.dart';
import 'hikka_auth.dart';
import 'hikka_nav.dart';

/// Посилання `miki://open/…`, якими застосунок відкривається ззовні (з браузера, повідомлення, іншого застосунку).
///
/// Підтримується:
/// - `miki://open` — просто відкрити застосунок (на це переспрямовує сторінка після входу в Hikka);
/// - `miki://open/anime/<slug>`, `/character/<slug>`, `/collection/<id>`, `/article/<slug>` — відкрити сторінку;
/// - `miki://open/auth?reference=<код>` — завершити вхід у Hikka, але лише поки вхід справді триває
///   (чуже посилання не може непомітно залогінити вас в чужий акаунт).
class DeepLinks {
  DeepLinks._();

  static const String scheme = 'miki';
  static const String host = 'open';

  static final RegExp _id = RegExp(r'^[A-Za-z0-9._\-]{1,160}$');

  /// Посилання на сторінку тайтлу, яким можна ділитися
  static String anime(String slug) => '$scheme://$host/anime/$slug';

  /// Обробляє посилання. `true` — розпізнано й виконано (або це просто відкриття), `false` — проігноровано.
  static bool handle(String link, {HikkaNav? nav, HikkaAuth? auth}) {
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
