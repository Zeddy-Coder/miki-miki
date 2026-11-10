/// HTTP для джерел перегляду (аналог `NetworkHelper` / OkHttp в Aniyomi): куки, перенаправлення,
/// форми, повтор при збої. Без сторонніх пакетів — `dart:io`; транспорт один-стрибковий і підміняється в тестах.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'source_log.dart';

enum SourceErrorKind { network, timeout, notFound, blocked, rateLimited, server, badResponse, unsupported }

class SourceException implements Exception {
  final SourceErrorKind kind;
  final int? status;

  /// Технічний опис (для логів)
  final String detail;

  const SourceException(this.kind, this.detail, {this.status});

  /// Повідомлення для користувача
  String get message => switch (kind) {
        SourceErrorKind.network => 'Немає зв’язку із сайтом. Перевірте інтернет.',
        SourceErrorKind.timeout => 'Сайт довго не відповідає. Спробуйте ще раз.',
        SourceErrorKind.notFound => 'Сторінку не знайдено — можливо, сайт змінив адреси.',
        SourceErrorKind.blocked => 'Сайт не пустив запит (захист Cloudflare або обмеження за країною). Спробуйте пізніше чи через інший інтернет / VPN.',
        SourceErrorKind.rateLimited => 'Забагато запитів. Зачекайте хвилинку й спробуйте ще раз.',
        SourceErrorKind.server => 'Сайт тимчасово недоступний.',
        SourceErrorKind.badResponse => 'Сайт віддав несподіману сторінку — можливо, змінилася розмітка.',
        SourceErrorKind.unsupported => 'Це джерело не підтримує такої дії.',
      };

  @override
  String toString() => 'SourceException(${kind.name}, status: $status, $detail)';
}

class SourceRequest {
  final String method;
  final Uri url;
  final Map<String, String> headers;

  /// Тіло запиту (уже закодоване)
  final List<int>? body;

  /// Скільки байтів відповіді читати (решту транспорт відкидає й закриває зʼєднання); `null` — все.
  /// Потрібно, щоб дізнатися кінцеву адресу відео, не завантажуючи сам файл.
  final int? maxBodyBytes;

  const SourceRequest(this.method, this.url, {this.headers = const {}, this.body, this.maxBodyBytes});

  SourceRequest copyWith({String? method, Uri? url, Map<String, String>? headers, List<int>? body, bool dropBody = false}) => SourceRequest(
        method ?? this.method,
        url ?? this.url,
        headers: headers ?? this.headers,
        body: dropBody ? null : (body ?? this.body),
        maxBodyBytes: maxBodyBytes,
      );
}

class SourceResponse {
  final int status;

  /// Адреса, з якої прийшла відповідь (після перенаправлень)
  final Uri url;

  /// Заголовки з малими літерами в назвах; повторні значення через кому (`set-cookie` — окремо в `setCookies`)
  final Map<String, String> headers;
  final List<String> setCookies;
  final List<int> bodyBytes;

  const SourceResponse(this.status, this.url, this.bodyBytes, {this.headers = const {}, this.setCookies = const []});

  String get contentType => headers['content-type'] ?? '';

  String? get location => headers['location'];

  /// Текст відповіді з урахуванням кодування (UTF-8 за замовчуванням, підтримано й windows-1251)
  String get text {
    final m = RegExp(r'charset\s*=\s*"?([\w-]+)', caseSensitive: false).firstMatch(contentType);
    final cs = m?.group(1)?.toLowerCase();
    if (cs == 'windows-1251' || cs == 'cp1251' || cs == 'win-1251') return decodeWindows1251(bodyBytes);
    if (cs == 'iso-8859-1' || cs == 'latin1') return latin1.decode(bodyBytes);
    return utf8.decode(bodyBytes, allowMalformed: true);
  }

  Object? get json {
    try {
      return jsonDecode(text);
    } on FormatException catch (e) {
      throw SourceException(SourceErrorKind.badResponse, 'JSON: ${e.message}', status: status);
    }
  }

  /// Схоже на сторінку захисту Cloudflare (а не на справжню відповідь сайту чи API)
  bool get looksBlocked {
    if (status != 403 && status != 429 && status != 503) return false;
    final head = text.length > 6000 ? text.substring(0, 6000) : text;
    if (head.contains('Attention Required! | Cloudflare') ||
        head.contains('Just a moment...') ||
        head.contains('cf-browser-verification') ||
        head.contains('challenge-platform')) {
      return true;
    }
    // відповідь API (JSON) і «Забагато запитів» — не блокування
    if (contentType.contains('json') || status == 429) return false;
    return (headers['server'] ?? '').toLowerCase().contains('cloudflare');
  }
}

/// Один HTTP-запит без перенаправлень і куків (їх веде `SourceHttp`)
typedef SourceSender = Future<SourceResponse> Function(SourceRequest request);

/// Справжній транспорт на `dart:io`
class IoSourceTransport {
  static HttpClient? _client;

  static Future<SourceResponse> send(SourceRequest r) async {
    final client = _client ??= HttpClient()
      ..connectionTimeout = const Duration(seconds: 12)
      ..idleTimeout = const Duration(seconds: 20)
      ..autoUncompress = true;
    final req = await client.openUrl(r.method, r.url);
    req.followRedirects = false;
    r.headers.forEach((k, v) {
      if (k.toLowerCase() == 'user-agent') {
        req.headers.set(HttpHeaders.userAgentHeader, v);
      } else {
        req.headers.set(k, v);
      }
    });
    if (r.body != null) {
      req.headers.set(HttpHeaders.contentLengthHeader, r.body!.length.toString());
      req.add(r.body!);
    }
    final res = await req.close().timeout(const Duration(seconds: 25));
    final bytes = <int>[];
    final cap = r.maxBodyBytes;
    await for (final chunk in res.timeout(const Duration(seconds: 25))) {
      bytes.addAll(chunk);
      if (cap != null && bytes.length >= cap) break; // вихід із циклу скасовує читання й закриває зʼєднання
    }
    final headers = <String, String>{};
    res.headers.forEach((k, v) {
      if (k.toLowerCase() != 'set-cookie') headers[k.toLowerCase()] = v.join(',');
    });
    return SourceResponse(
      res.statusCode,
      r.url,
      bytes,
      headers: headers,
      setCookies: res.headers[HttpHeaders.setCookieHeader] ?? const [],
    );
  }
}

/// Куки за доменами (спрощено: без шляхів і термінів, окрім явного видалення)
class CookieJar {
  final Map<String, Map<String, String>> _byDomain = {};

  void store(Uri url, List<String> setCookies) {
    for (final raw in setCookies) {
      final parts = raw.split(';');
      final nv = parts.first;
      final eq = nv.indexOf('=');
      if (eq <= 0) continue;
      final name = nv.substring(0, eq).trim();
      final value = nv.substring(eq + 1).trim();
      var domain = url.host.toLowerCase();
      var expired = false;
      for (final p in parts.skip(1)) {
        final kv = p.split('=');
        final key = kv.first.trim().toLowerCase();
        final val = kv.length > 1 ? kv.sublist(1).join('=').trim() : '';
        if (key == 'domain' && val.isNotEmpty) domain = val.toLowerCase().replaceFirst(RegExp(r'^\.'), '');
        if (key == 'max-age' && (int.tryParse(val) ?? 1) <= 0) expired = true;
        if (key == 'expires') {
          final d = _tryParseHttpDate(val);
          if (d != null && d.isBefore(DateTime.now())) expired = true;
        }
      }
      final jar = _byDomain.putIfAbsent(domain, () => {});
      if (expired) {
        jar.remove(name);
      } else {
        jar[name] = value;
      }
    }
  }

  String? headerFor(Uri url) {
    final host = url.host.toLowerCase();
    final pairs = <String>[];
    _byDomain.forEach((domain, cookies) {
      if (host == domain || host.endsWith('.$domain')) {
        cookies.forEach((k, v) => pairs.add('$k=$v'));
      }
    });
    return pairs.isEmpty ? null : pairs.join('; ');
  }

  void clear() => _byDomain.clear();

  String? get(String domain, String name) => _byDomain[domain]?[name];
}

DateTime? _tryParseHttpDate(String s) {
  try {
    return HttpDate.parse(s);
  } catch (_) {
    return null;
  }
}

/// Типовий браузерний User-Agent: більшість сайтів із захистом відсікають «порожні» агенти
const String kBrowserUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

class SourceHttp {
  final SourceSender _send;
  final CookieJar cookies = CookieJar();
  final String userAgent;

  /// Пауза перед повтором після збою (у тестах — нуль)
  final Duration retryDelay;
  final int maxRedirects;

  /// Скільки запитів реально пішло в мережу (для тестів і діагностики)
  int networkCalls = 0;

  SourceHttp({SourceSender? sender, this.userAgent = kBrowserUserAgent, this.retryDelay = const Duration(milliseconds: 600), this.maxRedirects = 8})
      : _send = sender ?? IoSourceTransport.send;

  /// Кодує поля форми як `application/x-www-form-urlencoded` (пробіл → `+`, UTF-8)
  static List<int> encodeForm(Map<String, String> form) =>
      utf8.encode(form.entries.map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}').join('&'));

  /// Розбирає адресу так, як це робить браузер: пропуски й кирилиця в шляху не заважають
  static Uri parseUrl(String s, [Uri? base]) {
    final t = s.trim();
    Uri u;
    try {
      u = Uri.parse(t);
    } on FormatException {
      u = Uri.parse(Uri.encodeFull(t));
    }
    if (base != null) u = base.resolveUri(u);
    return u;
  }

  Future<SourceResponse> get(String url, {Map<String, String>? headers, bool throwOnError = true}) =>
      send(SourceRequest('GET', parseUrl(url), headers: headers ?? const {}), throwOnError: throwOnError);

  Future<SourceResponse> postForm(String url, Map<String, String> form, {Map<String, String>? headers, bool throwOnError = true}) => send(
        SourceRequest('POST', parseUrl(url),
            headers: {'Content-Type': 'application/x-www-form-urlencoded', ...?headers}, body: encodeForm(form)),
        throwOnError: throwOnError,
      );

  /// Кінцева адреса після всіх перенаправлень — без завантаження файлу (читається не більше кількох КБ).
  /// Повертає також код відповіді кінцевої адреси.
  Future<({Uri url, int status, String contentType})> resolve(String url, {Map<String, String>? headers}) async {
    final res = await send(
      SourceRequest('GET', parseUrl(url), headers: {'Range': 'bytes=0-0', ...?headers}, maxBodyBytes: 2048),
      throwOnError: false,
    );
    return (url: res.url, status: res.status, contentType: res.contentType);
  }

  /// Виконує запит: підставляє куки й заголовки, йде за перенаправленнями, повторює при збої.
  /// `throwOnError` — кидати `SourceException` на 4xx/5xx (з розпізнаванням Cloudflare).
  Future<SourceResponse> send(SourceRequest request, {bool throwOnError = true}) async {
    SourceException? last;
    final attempts = request.method == 'GET' || request.method == 'HEAD' ? 2 : 1;
    for (int attempt = 0; attempt < attempts; attempt++) {
      try {
        final res = await _sendFollowing(request);
        if (!throwOnError || (res.status >= 200 && res.status < 400)) return res;
        final err = _errorFor(res);
        if (err.kind != SourceErrorKind.server || attempt == attempts - 1) throw err;
        last = err;
      } on SourceException catch (e) {
        if (e.kind != SourceErrorKind.network && e.kind != SourceErrorKind.timeout) rethrow;
        last = e;
        if (attempt == attempts - 1) rethrow;
      }
      await Future<void>.delayed(retryDelay);
    }
    throw last ?? const SourceException(SourceErrorKind.network, 'unreachable');
  }

  Future<SourceResponse> _sendFollowing(SourceRequest first) async {
    var req = first;
    for (int hop = 0; hop <= maxRedirects; hop++) {
      final headers = <String, String>{
        'User-Agent': userAgent,
        'Accept': '*/*',
        'Accept-Language': 'uk,en;q=0.8',
        ...req.headers,
      };
      final cookie = cookies.headerFor(req.url);
      if (cookie != null && !headers.keys.any((k) => k.toLowerCase() == 'cookie')) headers['Cookie'] = cookie;
      networkCalls++;
      final SourceResponse res;
      final started = DateTime.now();
      int ms() => DateTime.now().difference(started).inMilliseconds;
      SourceLog.add('→ ${req.method} ${req.url}${hop > 0 ? ' (перенаправлення $hop)' : ''}');
      try {
        res = await _send(req.copyWith(headers: headers));
      } on SourceException catch (e) {
        SourceLog.add('✗ ${ms()} мс ${e.kind.name}: ${e.detail}');
        rethrow;
      } on TimeoutException catch (e) {
        SourceLog.add('✗ ${ms()} мс таймаут: ${e.message ?? ''}');
        throw SourceException(SourceErrorKind.timeout, '${req.url}: ${e.message ?? 'timeout'}');
      } on SocketException catch (e) {
        SourceLog.add('✗ ${ms()} мс мережа: ${e.message} ${e.osError?.message ?? ''}');
        throw SourceException(SourceErrorKind.network, '${req.url}: ${e.message}');
      } on HandshakeException catch (e) {
        SourceLog.add('✗ ${ms()} мс TLS: ${e.message}');
        throw SourceException(SourceErrorKind.network, '${req.url}: TLS ${e.message}');
      } on HttpException catch (e) {
        SourceLog.add('✗ ${ms()} мс HTTP: ${e.message}');
        throw SourceException(SourceErrorKind.network, '${req.url}: ${e.message}');
      }
      SourceLog.add('← ${res.status} ${ms()} мс, ${res.bodyBytes.length} Б${res.location != null ? ', Location: ${res.location}' : ''}');
      cookies.store(req.url, res.setCookies);
      final loc = res.location;
      if (res.status >= 300 && res.status < 400 && loc != null && loc.isNotEmpty && res.status != 304) {
        if (hop == maxRedirects) throw SourceException(SourceErrorKind.badResponse, 'забагато перенаправлень: ${first.url}');
        final next = parseUrl(loc, req.url);
        final toGet = res.status == 303 || ((res.status == 301 || res.status == 302) && req.method == 'POST');
        final nextHeaders = Map<String, String>.of(req.headers)..removeWhere((k, _) => k.toLowerCase() == 'cookie');
        if (toGet) nextHeaders.removeWhere((k, _) => k.toLowerCase() == 'content-type');
        req = req.copyWith(method: toGet ? 'GET' : req.method, url: next, headers: nextHeaders, dropBody: toGet);
        continue;
      }
      return SourceResponse(res.status, req.url, res.bodyBytes, headers: res.headers, setCookies: res.setCookies);
    }
    throw SourceException(SourceErrorKind.badResponse, 'забагато перенаправлень: ${first.url}');
  }

  SourceException _errorFor(SourceResponse res) {
    final detail = '${res.url} → ${res.status}';
    if (res.looksBlocked) return SourceException(SourceErrorKind.blocked, detail, status: res.status);
    if (res.status == 404 || res.status == 410) return SourceException(SourceErrorKind.notFound, detail, status: res.status);
    if (res.status == 403 || res.status == 401) return SourceException(SourceErrorKind.blocked, detail, status: res.status);
    if (res.status == 429) return SourceException(SourceErrorKind.rateLimited, detail, status: res.status);
    if (res.status >= 500) return SourceException(SourceErrorKind.server, detail, status: res.status);
    return SourceException(SourceErrorKind.badResponse, detail, status: res.status);
  }
}

// ── windows-1251 ───────────────────────────────────────────────────────────────

const List<int> _cp1251High = [
  0x0402, 0x0403, 0x201A, 0x0453, 0x201E, 0x2026, 0x2020, 0x2021, 0x20AC, 0x2030, 0x0409, 0x2039, 0x040A, 0x040C, 0x040B, 0x040F, //
  0x0452, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014, 0x0098, 0x2122, 0x0459, 0x203A, 0x045A, 0x045C, 0x045B, 0x045F,
  0x00A0, 0x040E, 0x045E, 0x0408, 0x00A4, 0x0490, 0x00A6, 0x00A7, 0x0401, 0x00A9, 0x0404, 0x00AB, 0x00AC, 0x00AD, 0x00AE, 0x0407,
  0x00B0, 0x00B1, 0x0406, 0x0456, 0x0491, 0x00B5, 0x00B6, 0x00B7, 0x0451, 0x2116, 0x0454, 0x00BB, 0x0458, 0x0405, 0x0455, 0x0457,
];

String decodeWindows1251(List<int> bytes) {
  final out = StringBuffer();
  for (final b in bytes) {
    if (b < 0x80) {
      out.writeCharCode(b);
    } else if (b < 0xC0) {
      out.writeCharCode(_cp1251High[b - 0x80]);
    } else {
      out.writeCharCode(0x0410 + (b - 0xC0));
    }
  }
  return out.toString();
}
