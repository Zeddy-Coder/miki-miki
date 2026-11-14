import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'app_log.dart';

/// Fallback host IP lookup via DNS-over-HTTPS when the system DNS does not answer for the needed address
/// (DNS filters, the provider, a configured Private DNS). The request goes to the provider's IP itself (1.1.1.1, 8.8.8.8), so it
/// needs no DNS of its own. Used only as a fallback path for the app's own services.
class DohResolver {
  DohResolver._();

  /// Providers in queue order; `(IP, path, whether the accept header is needed)`
  static const List<(String, String)> providers = [
    ('1.1.1.1', '/dns-query'),
    ('1.0.0.1', '/dns-query'),
    ('8.8.8.8', '/resolve'),
    ('8.8.4.4', '/resolve'),
  ];

  static final Map<String, (DateTime, List<String>)> _cache = {};

  /// Tests only: replaces the network call `(providerIP, path, host) -> response body`
  static Future<String> Function(String ip, String path, String host)? debugFetch;

  /// IPv4 addresses of the host; an empty list if no provider answered
  static Future<List<String>> resolve(String host) async {
    final hit = _cache[host];
    if (hit != null && hit.$1.isAfter(DateTime.now())) return hit.$2;
    // All providers at once: the first to give an address wins (one network obstacle does not delay the rest)
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

  /// Extracts A records from a response in `application/dns-json` format
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
