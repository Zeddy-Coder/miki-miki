import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show ValueNotifier, visibleForTesting;

import 'app_log.dart';
import 'doh_resolver.dart';
import 'storage_service.dart';

/// Помилка запиту до бекенду застосунку
class BackendException implements Exception {
  final int? status;
  final String message;
  const BackendException(this.message, {this.status});

  @override
  String toString() => 'BackendException($status): $message';
}

/// Виконує запит: `(метод, адреса, заголовки, тіло)` → `(статус, тіло відповіді)`. У тестах підміняється.
typedef BackendTransport = Future<(int, String)> Function(String method, String url, Map<String, String> headers, String? body);

/// Клієнт бекенду Miki Miki (Firebase Functions, `europe-west1`): анонімна сесія, обмін коду Hikka на токен
/// (секрет клієнта лишається на сервері) і ключ Moon, якого не має бути в самому застосунку.
/// Сесія живе в розділі `backend` сховища; сам клієнт ніколи не пише токени в лог.
class BackendClient {
  /// Спільний екземпляр (у тестах підміняється)
  static BackendClient instance = BackendClient();

  static const String section = 'backend';
  static const String baseUrl = 'https://europe-west1-miki-miki-729d9.cloudfunctions.net';

  /// Запасна адреса тієї ж служби через Firebase Hosting: деякі мережі, DNS-фільтри й провайдери не резолвлять
  /// `cloudfunctions.net`, а `web.app` лишається доступним. Працює після `firebase deploy --only hosting`.
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

  /// Хости, які системний DNS не резолвить: далі одразу йдемо через DoH, без нових очікувань
  static final Set<String> _dnsBroken = {};

  static Future<(int, String)> _httpTransport(String method, String url, Map<String, String> headers, String? body) async {
    final host = Uri.parse(url).host;
    if (!_dnsBroken.contains(host)) {
      try {
        // Швидка перевірка DNS: без неї збій системного резолвера може тягнутись десятки секунд
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
      // Сертифікат і SNI лишаються для справжнього хоста: підміняється лише адреса, куди йде TCP
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

  /// Запит до служби: спершу основна адреса, а якщо до неї не достукатись (DNS, мережа) — запасна через Hosting.
  /// Запасна, що спрацювала, запамʼятовується до кінця роботи застосунку.
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

  /// Лише для тестів: простий GET без сесії через той самий транспорт і запасні адреси
  @visibleForTesting
  Future<(int, String)> debugGet(String path) => _send('GET', path, const {}, null);

  // ── Сесія ──────────────────────────────────────────────────────

  String get _session => (_data['session'] as String?) ?? '';
  int get _expires => (_data['expires'] as num?)?.toInt() ?? 0;

  bool get _sessionValid => _session.isNotEmpty && _expires - DateTime.now().millisecondsSinceEpoch > 24 * 3600 * 1000;

  /// Діюча сесія (за потреби створюється нова; одночасні виклики ділять один запит)
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

  /// Запит із сесією; якщо сервер її не визнав — одна спроба з новою
  Future<(int, String)> _authed(String method, String path, {String? body}) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final sid = await ensureSession(renew: attempt > 0);
      final (status, text) = await _send(method, path, {'x-session': sid, if (body != null) 'content-type': 'application/json'}, body);
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

  /// Обмінює код входу на токен Hikka. Повертає відповідь Hikka як є (`secret`, `expiration`…) і статус.
  Future<(int, Map<String, dynamic>)> hikkaToken(String requestReference) async {
    final (status, text) = await _authed('POST', 'hikkaToken', body: jsonEncode({'request_reference': requestReference}));
    return (status, _json(text));
  }

  // ── Банери ─────────────────────────────────────────────────────

  /// Банери тайтлів від бекенду (він кешує адреси CDN TMDB / AniList): MAL-id → (адреса, колір); `null` у значенні —
  /// банера немає. Сам `null` замість мапи — бекенд недоступний (тоді застосунок шукає банери сам).
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

  /// Ключ Moon, збережений після останнього успішного завантаження (порожній, якщо ще не завантажувався)
  String get cachedMoonKey => (_data['moon_key'] as String?) ?? '';

  /// Збільшується, коли з бекенду прийшов новий ключ TMDB: екрани, що вже завантажили дані без нього, перезавантажуються
  static final ValueNotifier<int> keyEpoch = ValueNotifier<int>(0);

  /// Ключ TheMovieDB, що діє зараз: власний із налаштувань, а якщо його немає — з бекенду
  static String effectiveTmdbKey() {
    final own = StorageService.getTmdbKey().trim();
    return own.isNotEmpty ? own : BackendClient.instance.cachedTmdbKey;
  }

  /// Ключ TheMovieDB з бекенду (постери й банери); власний ключ із налаштувань має перевагу
  String get cachedTmdbKey => (_data['tmdb_key'] as String?) ?? '';

  /// Завантажує ключ Moon із бекенду й запамʼятовує. Помилка не фатальна: далі діє збережений ключ (а без нього Moon розбирає сторінку плеєра).
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
