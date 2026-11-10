import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'app_log.dart';

/// Запасне визначення IP-адреси хоста через DNS-over-HTTPS, коли системний DNS не відповідає на потрібну адресу
/// (DNS-фільтри, провайдер, налаштований Private DNS). Запит іде на сам IP провайдера (1.1.1.1, 8.8.8.8), тож
/// власного DNS не потребує. Використовується лише як запасний шлях для служб самого застосунку.
class DohResolver {
  DohResolver._();

  /// Провайдери за чергою; `(IP, шлях, потрібен заголовок accept)`
  static const List<(String, String)> providers = [
    ('1.1.1.1', '/dns-query'),
    ('1.0.0.1', '/dns-query'),
    ('8.8.8.8', '/resolve'),
    ('8.8.4.4', '/resolve'),
  ];

  static final Map<String, (DateTime, List<String>)> _cache = {};

  /// Лише для тестів: підміна мережевого виклику `(провайдерIP, шлях, хост) -> тіло відповіді`
  static Future<String> Function(String ip, String path, String host)? debugFetch;

  /// IPv4-адреси хоста; порожній список, якщо жоден провайдер не відповів
  static Future<List<String>> resolve(String host) async {
    final hit = _cache[host];
    if (hit != null && hit.$1.isAfter(DateTime.now())) return hit.$2;
    // Усі провайдери одночасно: перший, хто дасть адресу, виграє (одна мережева перешкода не затримує решту)
    final done = Completer<List<String>>();
    var pending = providers.length;
    for (final (ip, path) in providers) {
      () async {
        try {
          final body = await (debugFetch ?? _fetch)(ip, path, host).timeout(const Duration(seconds: 6));
          final ips = parse(body);
          if (ips.isNotEmpty && !done.isCompleted) {
            _cache[host] = (DateTime.now().add(const Duration(minutes: 10)), ips);
            AppLog.i('dns', 'DoH: $host → ${ips.first} (через $ip)');
            done.complete(ips);
          }
        } catch (e) {
          AppLog.w('dns', 'DoH $ip не відповів для $host: $e');
        } finally {
          if (--pending == 0 && !done.isCompleted) done.complete(const []);
        }
      }();
    }
    final result = await done.future;
    if (result.isNotEmpty) return result;
    return const [];
  }

  /// Дістає A-записи з відповіді формату `application/dns-json`
  static List<String> parse(String body) {
    try {
      final j = jsonDecode(body);
      final answers = j is Map ? j['Answer'] : null;
      if (answers is! List) return const [];
      return [
        for (final a in answers)
          if (a is Map && a['type'] == 1 && a['data'] is String && InternetAddress.tryParse(a['data'] as String) != null) a['data'] as String,
      ];
    } catch (_) {
      return const [];
    }
  }

  static Future<String> _fetch(String ip, String path, String host) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final req = await client.getUrl(Uri.parse('https://$ip$path?name=${Uri.encodeQueryComponent(host)}&type=A'));
      req.headers.set(HttpHeaders.acceptHeader, 'application/dns-json');
      final res = await req.close();
      if (res.statusCode != 200) throw HttpException('DoH ${res.statusCode}');
      return await utf8.decodeStream(res);
    } finally {
      client.close(force: true);
    }
  }
}
