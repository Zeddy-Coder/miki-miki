import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'app_log.dart';
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

  final SectionLoader _load;
  final SectionSaver _save;
  final BackendTransport _transport;
  final String base;

  late final Map<String, dynamic> _data = Map<String, dynamic>.of(_load());
  Future<String>? _sessionInFlight;

  BackendClient({SectionLoader? load, SectionSaver? save, BackendTransport? transport, this.base = baseUrl})
      : _load = load ?? (() => StorageService.getSection(section)),
        _save = save ?? ((d) => StorageService.saveSection(section, d)),
        _transport = transport ?? _httpTransport;

  static Future<(int, String)> _httpTransport(String method, String url, Map<String, String> headers, String? body) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.openUrl(method, Uri.parse(url)).timeout(const Duration(seconds: 15));
      headers.forEach(req.headers.set);
      if (body != null) req.add(utf8.encode(body));
      final res = await req.close().timeout(const Duration(seconds: 20));
      final text = await utf8.decodeStream(res).timeout(const Duration(seconds: 20));
      return (res.statusCode, text);
    } on TimeoutException {
      throw const BackendException('бекенд не відповів вчасно');
    } on SocketException catch (e) {
      throw BackendException('немає зʼєднання з бекендом: ${e.message}');
    } finally {
      client.close(force: true);
    }
  }

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
    final (status, text) = await _transport('POST', '$base/session', {'content-type': 'application/json'}, jsonEncode({'app': 'miki'}));
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
      final (status, text) = await _transport(method, '$base/$path', {'x-session': sid, if (body != null) 'content-type': 'application/json'}, body);
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

  // ── Moon ───────────────────────────────────────────────────────

  /// Ключ Moon, збережений після останнього успішного завантаження (порожній, якщо ще не завантажувався)
  String get cachedMoonKey => (_data['moon_key'] as String?) ?? '';

  /// Завантажує ключ Moon із бекенду й запамʼятовує. Помилка не фатальна: далі діє збережений ключ (а без нього Moon розбирає сторінку плеєра).
  Future<String> refreshMoonKey() async {
    try {
      final (status, text) = await _authed('GET', 'config');
      final key = _json(text)['moonKey'];
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
