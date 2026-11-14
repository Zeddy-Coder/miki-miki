import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show ValueNotifier, visibleForTesting;

import 'app_log.dart';
import 'doh_resolver.dart';
import 'storage_service.dart';

/// Error of a request to the app backend
class BackendException implements Exception {
  final int? status;
  final String message;
  const BackendException(this.message, {this.status});

  @override
  String toString() => 'BackendException($status): $message';
}

/// Performs a request: `(method, address, headers, body)` → `(status, response body)`. Replaced in tests.
typedef BackendTransport = Future<(int, String)> Function(String method, String url, Map<String, String> headers, String? body);

/// Miki Miki backend client (Firebase Functions, `europe-west1`): anonymous session, exchange of a Hikka code for a token
/// (the client secret stays on the server) and the Moon key that must not live in the app itself.
/// The session lives in the `backend` store section; the client itself never writes tokens to the log.
class BackendClient {
  /// Shared instance (replaced in tests)
  static BackendClient instance = BackendClient();

  static const String section = 'backend';
  static const String baseUrl = 'https://europe-west1-miki-miki-729d9.cloudfunctions.net';

  /// Fallback address of the same service via Firebase Hosting: some networks, DNS filters and providers do not resolve
  /// `cloudfunctions.net`, while `web.app` stays reachable. Works after `firebase deploy --only hosting`.
  static const String fallbackBaseUrl = 'https://miki-miki-729d9.web.app/api';

  final SectionLoader _load;
  final SectionSaver _save;
  final BackendTransport _transport;
  final String base;
  final String? fallbackBase;
  bool _useFallback = false;

  late final Map<String, dynamic> _data = Map<String, dynamic>.of(_load());
  Future<String>? _sessionInFlight;

  BackendClient({SectionLoader? load, SectionSaver? save, BackendTransport? transport, this.base = baseUrl, this.fallbackBase = fallbackBaseUrl})
      : _load = load ?? (() => StorageService.getSection(section)),
        _save = save ?? ((d) => StorageService.saveSection(section, d)),
        _transport = transport ?? _httpTransport;

  /// Hosts the system DNS does not resolve: from now on go straight through DoH, with no new waiting
  static final Set<String> _dnsBroken = {};

  static Future<(int, String)> _httpTransport(String method, String url, Map<String, String> headers, String? body) async {
    final host = Uri.parse(url).host;
    if (!_dnsBroken.contains(host)) {
      try {
        // Quick DNS check: without it a system resolver failure can drag on for tens of seconds
        await InternetAddress.lookup(host).timeout(const Duration(seconds: 4));
      } on SocketException {
        _dnsBroken.add(host);
        AppLog.w('бекенд', 'системний DNS не знає $host, пробую DoH');
      } on TimeoutException {
        _dnsBroken.add(host);
        AppLog.w('бекенд', 'системний DNS не відповів за 4 с для $host, пробую DoH');
      }
    }
    if (_dnsBroken.contains(host)) {
      for (final ip in await DohResolver.resolve(host)) {
        try {
          return await _request(method, url, headers, body, ip: ip);
        } on SocketException {
          continue;
        }
      }
      throw BackendException('немає зʼєднання з бекендом: DNS не визначив адресу $host (ні системний, ні DoH)');
    }
    try {
      return await _request(method, url, headers, body);
    } on SocketException catch (e) {
      throw BackendException('немає зʼєднання з бекендом: ${e.message}');
    }
  }

  static Future<(int, String)> _request(String method, String url, Map<String, String> headers, String? body, {String? ip}) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    if (ip != null) {
      // The certificate and SNI stay for the real host: only the address the TCP connection goes to is replaced
      client.connectionFactory = (uri, proxyHost, proxyPort) => Socket.startConnect(InternetAddress(ip), uri.port);
    }
    try {
      final req = await client.openUrl(method, Uri.parse(url)).timeout(const Duration(seconds: 15));
      headers.forEach(req.headers.set);
      if (body != null) req.add(utf8.encode(body));
      final res = await req.close().timeout(const Duration(seconds: 20));
      final text = await utf8.decodeStream(res).timeout(const Duration(seconds: 20));
      return (res.statusCode, text);
    } on TimeoutException {
      throw const BackendException('бекенд не відповів вчасно');
    } on HandshakeException catch (e) {
      throw BackendException('захищене зʼєднання з бекендом не встановилось: ${e.message}');
    } finally {
      client.close(force: true);
    }
  }

  /// Request to the service: first the main address, and if it cannot be reached (DNS, network), the fallback via Hosting.
  /// A fallback that worked is remembered until the app exits.
  Future<(int, String)> _send(String method, String path, Map<String, String> headers, String? body) async {
    final fb = fallbackBase;
    final order = _useFallback && fb != null ? [fb, base] : [base, if (fb != null) fb];
    BackendException? last;
    for (final b in order) {
      try {
        final r = await _transport(method, '$b/$path', headers, body);
        if (b == fb) _useFallback = true;
        return r;
      } on BackendException catch (e) {
        if (e.status != null) rethrow;
        last = e;
        AppLog.w('бекенд', 'адреса недоступна (${Uri.parse(b).host}): ${e.message}');
      }
    }
    throw last!;
  }

  /// Tests only: a plain GET without a session through the same transport and fallback addresses
  @visibleForTesting
  Future<(int, String)> debugGet(String path) => _send('GET', path, const {}, null);

  // ── Session ──────────────────────────────────────────────────────

  String get _session => (_data['session'] as String?) ?? '';
  int get _expires => (_data['expires'] as num?)?.toInt() ?? 0;

  bool get _sessionValid => _session.isNotEmpty && _expires - DateTime.now().millisecondsSinceEpoch > 24 * 3600 * 1000;

  /// The active session (a new one is created if needed; concurrent calls share one request)
  Future<String> ensureSession({bool renew = false}) {
    if (!renew && _sessionValid) return Future.value(_session);
    return _sessionInFlight ??= _newSession().whenComplete(() => _sessionInFlight = null);
  }

  Future<String> _newSession() async {
    final (status, text) = await _send('POST', 'session', {'content-type': 'application/json'}, jsonEncode({'app': 'miki'}));
    final j = _json(text);
    if (status != 200 || j['session'] is! String) throw BackendException('сесію не створено', status: status);
    _data['session'] = j['session'];
    _data['expires'] = (j['expires'] as num?)?.toInt() ?? 0;
    _save(_data);
    AppLog.i('бекенд', 'нову сесію створено');
    return j['session'] as String;
  }

  /// Request with a session; if the server did not recognize it, one retry with a new one
  Future<(int, String)> _authed(String method, String path, {String? body, Map<String, String> extra = const {}}) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final sid = await ensureSession(renew: attempt > 0);
      final (status, text) = await _send(method, path, {'x-session': sid, ...extra, if (body != null) 'content-type': 'application/json'}, body);
      if (status == 401 && attempt == 0) continue;
      return (status, text);
    }
    throw const BackendException('сесію не визнано', status: 401);
  }

  static Map<String, dynamic> _json(String text) {
    try {
      final j = jsonDecode(text);
      return j is Map<String, dynamic> ? j : const {};
    } catch (_) {
      return const {};
    }
  }

  // ── Hikka ──────────────────────────────────────────────────────

  /// Exchanges the sign-in code for a Hikka token. Returns Hikka's response as is (`secret`, `expiration`…) and the status.
  Future<(int, Map<String, dynamic>)> hikkaToken(String requestReference) async {
    final (status, text) = await _authed('POST', 'hikkaToken', body: jsonEncode({'request_reference': requestReference}));
    return (status, _json(text));
  }

  // ── Settings sync ───────────────────────────────────────────────

  /// Stored settings of the Hikka account: `updated` (ms, 0 = nothing yet) and `data` (`key → {v, t}`).
  /// The server learns who the person is from the Hikka token (it is not stored there).
  Future<(int, Map<String, dynamic>)> syncGet(String hikkaToken) async {
    final (status, text) = await _authed('GET', 'syncGet', extra: {'x-hikka-auth': hikkaToken});
    return (status, _json(text));
  }

  /// Saves the merged settings map; returns the server time of the save
  Future<(int, Map<String, dynamic>)> syncPut(String hikkaToken, Map<String, dynamic> data) async {
    final (status, text) = await _authed('POST', 'syncPut', body: jsonEncode({'app': 'miki', 'data': data}), extra: {'x-hikka-auth': hikkaToken});
    return (status, _json(text));
  }

  // ── Push ───────────────────────────────────────────────────────

  /// Tells the server which releases (`slug|release id`) this phone follows. With `enabled: false` or an empty list the
  /// subscription is removed. Returns true on success.
  Future<bool> pushRegister(String fcmToken, List<String> follows, {required bool enabled}) async {
    final (status, _) = await _authed('POST', 'pushRegister', body: jsonEncode({'token': fcmToken, 'follows': follows, 'enabled': enabled}));
    return status == 200;
  }

  // ── Banners ─────────────────────────────────────────────────────

  /// Title banners from the backend (it caches TMDB / AniList CDN addresses): MAL id → (address, color); `null` as a value means
  /// there is no banner. A `null` instead of the map means the backend is unavailable (then the app looks for banners itself).
  Future<Map<int, (String?, int?)>?> banners(List<Map<String, Object?>> items) async {
    if (items.isEmpty) return const {};
    try {
      final out = <int, (String?, int?)>{};
      for (var i = 0; i < items.length; i += 30) {
        final chunk = items.sublist(i, i + 30 > items.length ? items.length : i + 30);
        final (status, text) = await _authed('POST', 'banners', body: jsonEncode({'items': chunk}));
        final map = _json(text)['banners'];
        if (status != 200 || map is! Map) {
          AppLog.w('бекенд', 'банери: відповідь $status');
          return null;
        }
        map.forEach((k, v) {
          final id = int.tryParse('$k');
          if (id == null) return;
          if (v is Map && v['url'] is String) {
            out[id] = (v['url'] as String, (v['color'] as num?)?.toInt());
          } else {
            out[id] = (null, null);
          }
        });
      }
      return out;
    } on BackendException catch (e) {
      AppLog.w('бекенд', 'банери: ${e.message}');
      return null;
    } catch (e) {
      AppLog.w('бекенд', 'банери: ${e.runtimeType}: $e');
      return null;
    }
  }

  // ── Moon ───────────────────────────────────────────────────────

  /// The Moon key saved after the last successful load (empty if never loaded)
  String get cachedMoonKey => (_data['moon_key'] as String?) ?? '';

  /// Incremented when a new TMDB key arrives from the backend: screens that already loaded data without it reload
  static final ValueNotifier<int> keyEpoch = ValueNotifier<int>(0);

  /// The TheMovieDB key in effect now: the user's own from settings, or from the backend if there is none
  static String effectiveTmdbKey() {
    final own = StorageService.getTmdbKey().trim();
    return own.isNotEmpty ? own : BackendClient.instance.cachedTmdbKey;
  }

  /// TheMovieDB key from the backend (posters and banners); the user's own key from settings takes priority
  String get cachedTmdbKey => (_data['tmdb_key'] as String?) ?? '';

  /// Loads the Moon key from the backend and remembers it. An error is not fatal: the saved key stays in effect (and without it Moon parses the player page).
  Future<String> refreshMoonKey() async {
    try {
      final (status, text) = await _authed('GET', 'config');
      final body = _json(text);
      final key = body['moonKey'];
      final tmdb = body['tmdbKey'];
      if (status == 200) {
        if (tmdb is String && tmdb.isNotEmpty) {
          if (tmdb != cachedTmdbKey) {
            final hadKey = cachedTmdbKey.isNotEmpty;
            _data['tmdb_key'] = tmdb;
            _save(_data);
            if (!hadKey) keyEpoch.value++;
          }
          AppLog.i('бекенд', 'ключ TMDB отримано (${tmdb.length} симв.)');
        } else {
          AppLog.w('бекенд', 'бекенд не віддав ключ TMDB — секрет TMDB_KEY не задано чи функцію config не розгорнуто');
        }
      }
      if (status == 200 && key is String && key.isNotEmpty) {
        if (key != cachedMoonKey) {
          _data['moon_key'] = key;
          _save(_data);
        }
        return key;
      }
      AppLog.w('бекенд', 'ключ Moon не отримано (статус $status)');
    } on BackendException catch (e) {
      AppLog.w('бекенд', 'ключ Moon не отримано: ${e.message}');
    }
    return cachedMoonKey;
  }
}
