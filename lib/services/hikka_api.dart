/// Клієнт API Hikka (api.hikka.io): каталог (аніме, персонажі, календар) без входу, а з токеном акаунта —
/// профіль, списки перегляду й улюблене (заголовок `auth`).
/// Без сторонніх пакетів — `dart:io`. Відповіді кешуються в памʼяті (TTL), однакові паралельні запити
/// зливаються в один, а при збої мережі віддається застарілий кеш, якщо він є.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../constants/app_identity.dart';
import '../models/hikka_models.dart';
import '../models/hikka_user_models.dart';
import 'app_log.dart';
import 'hikka_disk_cache.dart';

enum HikkaErrorKind { network, timeout, notFound, rateLimited, server, badResponse, unauthorized, forbidden }

class HikkaException implements Exception {
  final HikkaErrorKind kind;
  final int? status;

  /// Код помилки API (`system:validation_error` тощо)
  final String? code;

  /// Технічний опис (для логів)
  final String detail;

  const HikkaException(this.kind, this.detail, {this.status, this.code});

  /// Повідомлення для користувача
  String get message => switch (kind) {
        HikkaErrorKind.network => 'Немає зв’язку з Hikka. Перевірте інтернет.',
        HikkaErrorKind.timeout => 'Hikka довго не відповідає. Спробуйте ще раз.',
        HikkaErrorKind.notFound => 'Нічого не знайдено.',
        HikkaErrorKind.rateLimited => 'Забагато запитів до Hikka. Зачекайте хвилинку.',
        HikkaErrorKind.server => 'Сервер Hikka тимчасово недоступний.',
        HikkaErrorKind.badResponse => 'Hikka надіслала несподівану відповідь.',
        HikkaErrorKind.unauthorized => 'Потрібно увійти в акаунт Hikka.',
        HikkaErrorKind.forbidden => 'Для цієї дії бракує прав. Увійдіть у Hikka заново.',
      };

  @override
  String toString() => 'HikkaException(${kind.name}, status: $status, code: $code, $detail)';
}

class HikkaRequest {
  final String method;
  final Uri url;
  final String? body;

  /// Додаткові заголовки (токен акаунта `auth`)
  final Map<String, String> headers;

  const HikkaRequest(this.method, this.url, [this.body, this.headers = const {}]);
}

class HikkaResponse {
  final int status;
  final String body;
  final Map<String, String> headers;

  const HikkaResponse(this.status, this.body, [this.headers = const {}]);
}

typedef HikkaSender = Future<HikkaResponse> Function(HikkaRequest request);

/// Справжній транспорт на `dart:io`.
///
/// Спільний `HttpClient` тримає пул з'єднань. Після будь-якого збою (обрив, TLS, тайм-аут) клієнт
/// відкидається: у пулі могли лишитись «мертві» з'єднання (мережу змінили, телефон спав, сервер закрив
/// сокет), і кожен наступний запит натрапляв би на них знову. Закриття «м'яке» — запити, що вже йдуть,
/// доробляються на старому клієнті, нові відкриваються на новому.
class _IoTransport {
  static HttpClient? _client;
  static DateTime? _lastProbe;

  static HttpClient _create() => HttpClient()
    ..connectionTimeout = const Duration(seconds: 8)
    ..idleTimeout = const Duration(seconds: 15)
    ..userAgent = AppIdentity.userAgent('Hikka catalog');

  /// Відкидає клієнта, якщо він ще поточний (паралельний збій не скидає вже новий клієнт)
  static void _discard(HttpClient failed) {
    if (identical(_client, failed)) _client = null;
    try {
      failed.close();
    } catch (_) {}
  }

  static Future<HikkaResponse> send(HikkaRequest r) async {
    final client = _client ??= _create();
    HttpClientRequest? req;
    try {
      req = await client.openUrl(r.method, r.url);
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      r.headers.forEach(req.headers.set);
      if (r.body != null) {
        req.headers.contentType = ContentType.json;
        req.add(utf8.encode(r.body!));
      }
      final res = await req.close().timeout(const Duration(seconds: 25));
      final text = await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 25));
      final headers = <String, String>{};
      res.headers.forEach((k, v) => headers[k] = v.join(','));
      return HikkaResponse(res.statusCode, text, headers);
    } catch (e) {
      try {
        req?.abort();
      } catch (_) {}
      _discard(client);
      if (AppLog.on) unawaited(_probeDns(r.url.host));
      rethrow;
    }
  }

  /// Після збою перевіряємо DNS (рідше за раз на 10 с): це швидко відрізняє «немає інтернету» від «не резолвиться»
  static Future<void> _probeDns(String host) async {
    final now = DateTime.now();
    if (_lastProbe != null && now.difference(_lastProbe!) < const Duration(seconds: 10)) return;
    _lastProbe = now;
    final sw = Stopwatch()..start();
    try {
      final list = await InternetAddress.lookup(host).timeout(const Duration(seconds: 6));
      AppLog.d('hikka', 'DNS $host після збою: ${list.map((a) => a.address).join(', ')} (${sw.elapsedMilliseconds} мс)');
    } catch (e) {
      AppLog.w('hikka', 'DNS $host після збою не відповів за ${sw.elapsedMilliseconds} мс: ${HikkaApi.describeError(e)}');
    }
  }
}

class _CacheEntry {
  final Object? json;
  final DateTime expires;
  const _CacheEntry(this.json, this.expires);
}

class HikkaApi {
  /// Спільний екземпляр (у тестах підміняється)
  static HikkaApi instance = HikkaApi();

  static const String defaultBase = 'https://api.hikka.io';

  final String baseUrl;
  final HikkaSender _send;
  final DateTime Function() _now;

  /// Пауза перед повтором після збою (у тестах — нуль)
  final Duration retryDelay;

  final Map<String, _CacheEntry> _cache = {};
  final Map<String, Future<Object?>> _inflight = {};

  /// Кеш на диску (у тестах не підключений). Запис старіший за застарілість [diskServeStale] віддається одразу й
  /// оновлюється у фоні; ще старіший — лише коли мережа недоступна.
  HikkaDiskCache? disk;
  static const Duration diskServeStale = Duration(hours: 6);

  /// Запити, збережені до цього моменту, не віддаються «свіжими» (після ручного оновлення)
  DateTime _freshAfter = DateTime.fromMillisecondsSinceEpoch(0);

  /// Скільки запитів реально пішло в мережу (для тестів і діагностики)
  int networkCalls = 0;

  /// Токен акаунта для запитів із `auth: true`. Зазвичай його дає `HikkaAuth` через [sharedTokenProvider];
  /// власний провайдер потрібен окремим екземплярам API (у тестах).
  String? Function()? tokenProvider;

  /// Сервер відхилив токен (прострочений чи відкликаний): акаунт виходить із сесії
  void Function()? onUnauthorized;

  static String? Function() sharedTokenProvider = _noToken;
  static void Function()? sharedOnUnauthorized;

  static String? _noToken() => null;

  HikkaApi({
    HikkaSender? sender,
    this.baseUrl = defaultBase,
    DateTime Function()? now,
    this.retryDelay = const Duration(milliseconds: 700),
  })  : _send = sender ?? _IoTransport.send,
        _now = now ?? DateTime.now;

  void clearCache() {
    _cache.clear();
    _freshAfter = _now();
  }

  // ── Ядро ────────────────────────────────────────────────────────────────────

  /// Скільки спроб робиться залежно від виду збою
  static const int _maxNetworkAttempts = 3;
  static const int _maxServerAttempts = 2;

  /// Короткий опис винятку транспорту для журналу й `HikkaException.detail`
  static String describeError(Object e) {
    final b = StringBuffer(e.runtimeType.toString());
    if (e is SocketException) {
      b.write(': ${e.message}');
      final os = e.osError;
      if (os != null) b.write(' [os ${os.errorCode}: ${os.message}]');
      if (e.address != null) b.write(' ${e.address!.host}');
      if (e.port != null) b.write(':${e.port}');
    } else if (e is HttpException) {
      b.write(': ${e.message}');
    } else if (e is TlsException) {
      b.write(': ${e.message}');
      if (e.osError != null) b.write(' [os ${e.osError!.errorCode}: ${e.osError!.message}]');
    } else if (e is TimeoutException) {
      b.write(': ${e.message ?? 'час очікування вийшов'}');
    } else {
      b.write(': $e');
    }
    return b.toString();
  }

  Duration _backoff(int attempt) => attempt <= 1 ? retryDelay ~/ 2 : retryDelay * 2;

  Future<Object?> _request(String method, String path, {Map<String, String>? query, Object? body, bool auth = false}) async {
    final headers = <String, String>{};
    if (auth) {
      final token = (tokenProvider ?? sharedTokenProvider)();
      if (token == null || token.isEmpty) throw const HikkaException(HikkaErrorKind.unauthorized, 'немає токена');
      headers['auth'] = token;
    }
    final url = Uri.parse('$baseUrl$path').replace(queryParameters: query == null || query.isEmpty ? null : query);
    final raw = body == null ? null : jsonEncode(body);
    final label = '$method ${url.path}${url.hasQuery ? '?${url.query}' : ''}';
    HikkaException? last;
    for (int attempt = 1; attempt <= _maxNetworkAttempts; attempt++) {
      final sw = Stopwatch()..start();
      try {
        networkCalls++;
        AppLog.d('hikka', '→ $label (спроба $attempt)');
        final res = await _send(HikkaRequest(method, url, raw, headers));
        if (res.status >= 200 && res.status < 300) {
          AppLog.d('hikka', '← ${res.status} за ${sw.elapsedMilliseconds} мс, ${res.body.length} симв. ($label)${attempt > 1 ? ' — вдалося з спроби $attempt' : ''}');
          try {
            return res.body.trim().isEmpty ? null : jsonDecode(res.body);
          } on FormatException catch (e) {
            throw HikkaException(HikkaErrorKind.badResponse, 'JSON: ${e.message}', status: res.status);
          }
        }
        final err = _errorFor(res);
        AppLog.w('hikka', '← ${res.status} за ${sw.elapsedMilliseconds} мс ($label): ${err.detail}');
        if (auth && err.kind == HikkaErrorKind.unauthorized) (onUnauthorized ?? sharedOnUnauthorized)?.call();
        final retriable = err.kind == HikkaErrorKind.rateLimited || err.kind == HikkaErrorKind.server;
        if (!retriable || attempt >= _maxServerAttempts) throw err;
        last = err;
        await Future<void>.delayed(_retryAfter(res) ?? retryDelay);
      } on HikkaException {
        rethrow;
      } on TimeoutException catch (e) {
        last = HikkaException(HikkaErrorKind.timeout, describeError(e));
        AppLog.w('hikka', 'тайм-аут за ${sw.elapsedMilliseconds} мс ($label), спроба $attempt/$_maxNetworkAttempts: ${last.detail}');
        if (attempt >= _maxServerAttempts) throw last;
        await Future<void>.delayed(_backoff(attempt));
      } on Exception catch (e) {
        // Обрив, DNS, TLS, закрите з'єднання з пулу… Для користувача це «немає зв'язку», але спершу пробуємо ще:
        // нове з'єднання (клієнт уже скинуто) найчастіше проходить одразу.
        last = HikkaException(HikkaErrorKind.network, describeError(e));
        final more = attempt < _maxNetworkAttempts;
        AppLog.w('hikka', 'збій мережі за ${sw.elapsedMilliseconds} мс ($label), спроба $attempt/$_maxNetworkAttempts: ${last.detail}${more ? ' — повторюю' : ''}');
        if (!more) throw last;
        await Future<void>.delayed(_backoff(attempt));
      }
    }
    throw last ?? const HikkaException(HikkaErrorKind.network, 'unknown');
  }

  static Duration? _retryAfter(HikkaResponse res) {
    final v = int.tryParse(res.headers['retry-after'] ?? '');
    if (v == null || v <= 0) return null;
    return Duration(seconds: v.clamp(1, 3));
  }

  static const Set<String> _tokenCodes = {'auth:missing_token', 'auth:invalid_token', 'auth:token_expired', 'auth:user_not_found'};

  static HikkaException _errorFor(HikkaResponse res) {
    String? code;
    String detail = res.body.length > 160 ? res.body.substring(0, 160) : res.body;
    try {
      final j = jsonDecode(res.body);
      if (j is Map<String, dynamic>) {
        code = j['code'] as String?;
        detail = (j['message'] as String?) ?? detail;
      }
    } catch (_) {}
    final s = res.status;
    // Hikka віддає 400 і для «токен відсутній / поганий», тож орієнтуємось на код помилки
    final badToken = s == 401 || (code != null && _tokenCodes.contains(code));
    final kind = badToken
        ? HikkaErrorKind.unauthorized
        : s == 403
            ? HikkaErrorKind.forbidden
            : s == 404
                ? HikkaErrorKind.notFound
                : s == 429
                    ? HikkaErrorKind.rateLimited
                    : s >= 500
                        ? HikkaErrorKind.server
                        : HikkaErrorKind.badResponse;
    return HikkaException(kind, detail, status: s, code: code);
  }

  /// Кешований запит: свіжий кеш → одразу; інакше мережа (з об'єднанням однакових запитів);
  /// при збої мережі — застарілий кеш, якщо є.
  Future<T> _cached<T>(
    String key,
    Duration ttl,
    Future<Object?> Function() fetch,
    T Function(Object? json) parse,
  ) async {
    final now = _now();
    final hit = _cache[key];
    if (hit != null && now.isBefore(hit.expires)) {
      AppLog.d('hikka', 'кеш: ${_shortKey(key)}');
      return parse(hit.json);
    }

    // Диск: свіже — одразу; не надто старе — одразу, а оновлення у фоні; решта — запасний варіант при збої мережі
    DiskHit? saved;
    if (disk != null) {
      saved = await disk!.read(key);
      if (saved != null && saved.at.isAfter(_freshAfter)) {
        final age = now.difference(saved.at);
        if (age < ttl) {
          _cache[key] = _CacheEntry(saved.json, saved.at.add(ttl));
          AppLog.d('hikka', 'диск: ${_shortKey(key)}');
          return parse(saved.json);
        }
        if (age < diskServeStale) {
          AppLog.d('hikka', 'диск (оновлюю у фоні): ${_shortKey(key)}');
          unawaited(_network(key, ttl, fetch).then<void>((_) {}, onError: (_) {}));
          return parse(saved.json);
        }
      }
    }

    try {
      return parse(await _network(key, ttl, fetch));
    } on HikkaException catch (e) {
      final transient = e.kind == HikkaErrorKind.network ||
          e.kind == HikkaErrorKind.timeout ||
          e.kind == HikkaErrorKind.server ||
          e.kind == HikkaErrorKind.rateLimited;
      final fallback = hit?.json ?? saved?.json;
      if (fallback != null && transient) {
        AppLog.w('hikka', 'Hikka недоступна (${e.kind.name}) — показую застарілий кеш: ${_shortKey(key)}');
        return parse(fallback);
      }
      AppLog.w('hikka', 'запит остаточно невдалий (${e.kind.name}${e.status == null ? '' : ', ${e.status}'}): ${_shortKey(key)}');
      rethrow;
    }
  }

  /// Запит у мережу з об'єднанням однакових; успішна відповідь іде в памʼять і на диск
  Future<Object?> _network(String key, Duration ttl, Future<Object?> Function() fetch) async {
    var pending = _inflight[key];
    if (pending == null) {
      pending = fetch();
      _inflight[key] = pending;
      // Прибираємо запис, щойно запит завершився (успіхом чи помилкою)
      // Тіло з фігурними дужками: `remove` повертає Future, а `whenComplete` перебрав би його помилку на себе
      unawaited(pending.then<void>((_) {}, onError: (_) {}).whenComplete(() {
        _inflight.remove(key);
      }));
    }
    final json = await pending;
    final at = _now();
    _cache[key] = _CacheEntry(json, at.add(ttl));
    _trim();
    final d = disk;
    if (d != null) unawaited(d.write(key, json, at));
    return json;
  }

  static String _shortKey(String key) => key.length > 100 ? '${key.substring(0, 100)}…' : key;

  void _trim() {
    if (_cache.length <= 300) return;
    final keys = _cache.keys.toList()
      ..sort((a, b) => _cache[a]!.expires.compareTo(_cache[b]!.expires));
    for (final k in keys.take(_cache.length - 240)) {
      _cache.remove(k);
    }
  }

  static Map<String, String> _paging(int page, int size) => {'page': '$page', 'size': '$size'};
  static String _seg(String slug) => Uri.encodeComponent(slug);

  static const Duration _short = Duration(minutes: 3);
  static const Duration _medium = Duration(minutes: 10);
  static const Duration _long = Duration(minutes: 30);

  HikkaPage<T> _filtered<T>(HikkaPage<T> p, bool allowAdult, HikkaAnime Function(T) anime) {
    if (allowAdult) return p;
    return HikkaPage<T>(
      items: p.items.where((e) => !anime(e).isAdult).toList(),
      page: p.page,
      pages: p.pages,
      total: p.total,
    );
  }

  // ── Аніме ───────────────────────────────────────────────────────────────────

  /// Каталог з фільтрами (`POST /anime`)
  Future<HikkaPage<HikkaAnime>> searchAnime(
    HikkaSearchFilters filters, {
    int page = 1,
    int size = 30,
    bool allowAdult = false,
  }) {
    final body = filters.toBody(allowAdult: allowAdult);
    final key = 'anime?$page&$size&${jsonEncode(body)}';
    return _cached(
      key,
      _short,
      () => _request('POST', '/anime', query: _paging(page, size), body: body),
      (j) => HikkaPage.parse(j, HikkaAnime.fromJson),
    );
  }

  /// Повна сторінка аніме
  Future<HikkaAnime> anime(String slug) => _cached(
        'anime/$slug',
        _medium,
        () => _request('GET', '/anime/${_seg(slug)}'),
        (j) => HikkaAnime.fromJson(j is Map<String, dynamic> ? j : const {}),
      );

  Future<HikkaPage<HikkaCharacterRole>> animeCharacters(String slug, {int page = 1, int size = 30}) => _cached(
        'anime/$slug/characters?$page&$size',
        _long,
        () => _request('GET', '/anime/${_seg(slug)}/characters', query: _paging(page, size)),
        (j) => HikkaPage.parse(j, HikkaCharacterRole.fromJson),
      );

  Future<HikkaPage<HikkaStaff>> animeStaff(String slug, {int page = 1, int size = 30}) => _cached(
        'anime/$slug/staff?$page&$size',
        _long,
        () => _request('GET', '/anime/${_seg(slug)}/staff', query: _paging(page, size)),
        (j) => HikkaPage.parse(j, HikkaStaff.fromJson),
      );

  Future<HikkaPage<HikkaAnime>> recommendations(String slug, {int page = 1, int size = 20, bool allowAdult = false}) async {
    final p = await _cached(
      'anime/$slug/recommendations?$page&$size',
      _long,
      () => _request('GET', '/anime/${_seg(slug)}/recommendations', query: _paging(page, size)),
      (j) => HikkaPage.parse(j, HikkaAnime.fromJson),
    );
    return _filtered(p, allowAdult, (a) => a);
  }

  /// Усі аніме франшизи й зв'язки між ними
  Future<HikkaFranchiseData> franchise(String slug) => _cached(
        'franchise/$slug',
        _long,
        () => _request('GET', '/related/anime/${_seg(slug)}/franchise'),
        HikkaFranchiseData.fromJson,
      );

  Future<List<HikkaGenre>> genres() => _cached(
        'genres',
        const Duration(hours: 24),
        () => _request('GET', '/genres'),
        (j) => HikkaPage.parse(j, HikkaGenre.fromJson).items,
      );

  // ── Календар ────────────────────────────────────────────────────────────────

  /// Найближчі серії в порядку виходу (`POST /schedule/anime`)
  Future<HikkaPage<HikkaScheduleEntry>> schedule({int page = 1, int size = 100, bool allowAdult = false}) async {
    final body = <String, dynamic>{
      'status': ['announced', 'ongoing'],
      if (!allowAdult) 'rating': HikkaSearchFilters.safeRatings,
    };
    final p = await _cached(
      'schedule?$page&$size&${jsonEncode(body)}',
      _short,
      () => _request('POST', '/schedule/anime', query: _paging(page, size), body: body),
      (j) => HikkaPage.parse(j, HikkaScheduleEntry.fromJson),
    );
    return _filtered(p, allowAdult, (e) => e.anime);
  }

  // ── Персонажі ───────────────────────────────────────────────────────────────

  Future<HikkaCharacter> character(String slug) => _cached(
        'characters/$slug',
        _long,
        () => _request('GET', '/characters/${_seg(slug)}'),
        (j) => HikkaCharacter.fromJson(j is Map<String, dynamic> ? j : const {}),
      );

  /// Пошук персонажів; без запиту — найпопулярніші
  Future<HikkaPage<HikkaCharacter>> searchCharacters(String query, {int page = 1, int size = 30}) {
    final q = query.trim();
    final body = <String, dynamic>{if (q.length >= 2) 'query': q};
    return _cached(
      'characters?$page&$size&${jsonEncode(body)}',
      _medium,
      () => _request('POST', '/characters', query: _paging(page, size), body: body),
      (j) => HikkaPage.parse(j, HikkaCharacter.fromJson),
    );
  }

  Future<HikkaPage<HikkaCharacterAnime>> characterAnime(String slug, {int page = 1, int size = 30, bool allowAdult = false}) async {
    final p = await _cached(
      'characters/$slug/anime?$page&$size',
      _long,
      () => _request('GET', '/characters/${_seg(slug)}/anime', query: _paging(page, size)),
      (j) => HikkaPage.parse(j, HikkaCharacterAnime.fromJson),
    );
    return _filtered(p, allowAdult, (e) => e.anime);
  }

  Future<HikkaPage<HikkaCharacterVoice>> characterVoices(String slug, {int page = 1, int size = 30, bool allowAdult = false}) async {
    final p = await _cached(
      'characters/$slug/voices?$page&$size',
      _long,
      () => _request('GET', '/characters/${_seg(slug)}/voices', query: _paging(page, size)),
      (j) => HikkaPage.parse(j, HikkaCharacterVoice.fromJson),
    );
    return _filtered(p, allowAdult, (e) => e.anime);
  }
  // ── Колекції ────────────────────────────────────────────────────────────────

  /// Публічні колекції (`POST /collections`). [sort]: `popular` — за рейтингом сайту (типово), `new` — найновіші.
  /// Колекції з позначкою 18+ ховаються, якщо [allowAdult] вимкнено.
  Future<HikkaPage<HikkaCollection>> collections({
    String? contentType = 'anime',
    String sort = 'popular',
    int page = 1,
    int size = 20,
    bool allowAdult = false,
  }) async {
    final body = <String, dynamic>{
      if (contentType != null) 'content_type': contentType,
      if (sort == 'new') 'sort': ['created:desc'],
    };
    final p = await _cached(
      'collections?$page&$size&${jsonEncode(body)}',
      _short,
      () => _request('POST', '/collections', query: _paging(page, size), body: body),
      (j) => HikkaPage.parse(j, HikkaCollection.fromJson),
    );
    if (allowAdult) return p;
    return HikkaPage<HikkaCollection>(items: [for (final c in p.items) if (!c.nsfw) c], page: p.page, pages: p.pages, total: p.total);
  }

  /// Колекція з усіма записами (`GET /collections/{reference}`)
  Future<HikkaCollection> collection(String reference) => _cached(
        'collections/$reference',
        _medium,
        () => _request('GET', '/collections/${_seg(reference)}'),
        (j) => HikkaCollection.fromJson(j is Map<String, dynamic> ? j : const {}),
      );

  // ── Статті ──────────────────────────────────────────────────────────────────

  /// Статті спільноти (`POST /articles`). [category]: `news`, `reviews`, `original` або `null` — усі.
  /// [sort]: `new` (типово) чи `top` — за оцінками читачів.
  Future<HikkaPage<HikkaArticle>> articles({String? category, String sort = 'new', int page = 1, int size = 20}) {
    final body = <String, dynamic>{
      if (category != null) 'categories': [category],
      'sort': [sort == 'top' ? 'vote_score:desc' : 'created:desc'],
    };
    return _cached(
      'articles?$page&$size&${jsonEncode(body)}',
      _short,
      () => _request('POST', '/articles', query: _paging(page, size), body: body),
      (j) => HikkaPage.parse(j, HikkaArticle.fromJson),
    );
  }

  /// Повний текст статті (`GET /articles/{slug}`)
  Future<HikkaArticle> article(String slug) => _cached(
        'articles/$slug',
        _medium,
        () => _request('GET', '/articles/${_seg(slug)}'),
        (j) => HikkaArticle.fromJson(j is Map<String, dynamic> ? j : const {}),
      );

  // ── Акаунт і списки (потрібен вхід) ──────────────────────────────

  static Map<String, dynamic> _asMap(Object? j) => j is Map<String, dynamic> ? j : const {};

  /// «Запису немає»: Hikka віддає 404 з кодом `…:not_found`
  static bool _isMissing(HikkaException e) => e.kind == HikkaErrorKind.notFound || (e.code?.endsWith(':not_found') ?? false);

  /// Обмінює дозвіл користувача на токен (`POST /auth/token`)
  Future<HikkaToken> exchangeToken(String requestReference, String clientSecret) async {
    final j = await _request('POST', '/auth/token', body: {'request_reference': requestReference, 'client_secret': clientSecret});
    final t = HikkaToken.fromJson(_asMap(j));
    if (t.secret.isEmpty) throw const HikkaException(HikkaErrorKind.badResponse, 'порожній токен');
    return t;
  }

  /// Профіль власника токена (`GET /user/me`)
  Future<HikkaMe> me() async => HikkaMe.fromJson(_asMap(await _request('GET', '/user/me', auth: true)));

  /// Ідентифікатор поточного токена: потрібен, щоб відкликати його при виході (`GET /auth/token/info`)
  Future<String?> tokenReference() async => _asMap(await _request('GET', '/auth/token/info', auth: true))['reference'] as String?;

  Future<void> revokeToken(String reference) => _request('DELETE', '/auth/token/${_seg(reference)}', auth: true);

  /// Мій запис про тайтл; `null`, якщо його немає в жодному зі списків (`GET /watch/{slug}`)
  Future<HikkaWatchEntry?> myWatch(String slug) async {
    try {
      return HikkaWatchEntry.fromJson(_asMap(await _request('GET', '/watch/${_seg(slug)}', auth: true)));
    } on HikkaException catch (e) {
      if (_isMissing(e)) return null;
      rethrow;
    }
  }

  /// Додає тайтл у список або змінює запис (`PUT /watch/{slug}`)
  Future<HikkaWatchEntry> saveWatch(String slug, HikkaWatchEntry entry) async =>
      HikkaWatchEntry.fromJson(_asMap(await _request('PUT', '/watch/${_seg(slug)}', body: entry.toArgs(), auth: true)));

  /// Прибирає тайтл зі списків (`DELETE /watch/{slug}`)
  Future<void> removeWatch(String slug) async {
    try {
      await _request('DELETE', '/watch/${_seg(slug)}', auth: true);
    } on HikkaException catch (e) {
      if (!_isMissing(e)) rethrow;
    }
  }

  /// Список користувача за статусом (`POST /watch/{username}/list`); списки публічні, вхід не потрібен
  Future<HikkaPage<HikkaWatchEntry>> watchList(
    String username, {
    HikkaWatchStatus? status,
    int page = 1,
    int size = 30,
    String sort = 'watch_updated:desc',
    HikkaSearchFilters? filters,
  }) async {
    final body = filters != null
        ? (filters.toBody(allowAdult: true)..remove('query'))
        : <String, dynamic>{'sort': [sort]};
    if (status != null) body['watch_status'] = status.api;
    final j = await _request('POST', '/watch/${_seg(username)}/list', query: _paging(page, size), body: body);
    return HikkaPage.parse(j, HikkaWatchEntry.fromJson);
  }

  /// Скільки тайтлів у кожному статусі (`GET /watch/{username}/stats`)
  Future<HikkaWatchStats> watchStats(String username) async =>
      HikkaWatchStats.fromJson(_asMap(await _request('GET', '/watch/${_seg(username)}/stats')));

  /// Чи в улюбленому (`GET /favourite/anime/{slug}`)
  Future<bool> isFavourite(String slug) async {
    try {
      await _request('GET', '/favourite/anime/${_seg(slug)}', auth: true);
      return true;
    } on HikkaException catch (e) {
      if (_isMissing(e)) return false;
      rethrow;
    }
  }

  /// Додає в улюблене або прибирає з нього
  Future<void> setFavourite(String slug, bool value) async {
    try {
      await _request(value ? 'PUT' : 'DELETE', '/favourite/anime/${_seg(slug)}', auth: true);
    } on HikkaException catch (e) {
      if (value || !_isMissing(e)) rethrow;
    }
  }

  /// Улюблені аніме користувача (`POST /favourite/anime/{username}/list`)
  Future<HikkaPage<HikkaAnime>> favourites(String username, {int page = 1, int size = 30}) async {
    final j = await _request('POST', '/favourite/anime/${_seg(username)}/list', query: _paging(page, size));
    return HikkaPage.parse(j, HikkaAnime.fromJson);
  }
}
