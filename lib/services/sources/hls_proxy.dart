/// Локальний HLS-проксі: потік тягне застосунок (`dart:io`), а плеєр бере його з `127.0.0.1`.
///
/// Навіщо. Деякі CDN (Moon: `mooncdn.online`, за Cloudflare) не пускають TLS-клієнт libmpv на Android (mbedtls):
/// у журналі `tls: mbedtls_ssl_handshake returned …` і `HTTP error 403`, хоч той самий запит із Dart дає 206.
/// Проксі переписує адреси списків (`#EXT-X-STREAM-INF`, сегменти, `URI="…"`) на локальні й відповідає на них
/// даними з оригінального сервера з потрібними заголовками (Referer, User-Agent). Сам плеєр про сайт нічого не знає.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'source_log.dart';

class HlsProxy {
  HlsProxy._();

  static final HlsProxy instance = HlsProxy._();

  /// Чи пускати відео Moon через проксі. На Android — так (libmpv там не проходить CDN); на ПК плеєр ходить напряму.
  static bool enabled = Platform.isAndroid;

  static const int _maxSessions = 40;

  HttpServer? _server;
  Future<HttpServer>? _starting;
  HttpClient? _client;
  final Map<String, Map<String, String>> _headers = {};
  int _next = 0;
  int _segmentLogs = 0;
  int _errorLogs = 0;
  int _blocked = 0;
  final StreamController<int> _blockedEvents = StreamController<int>.broadcast();

  /// Скільки відповідей на сегменти були відмовою (4xx/5xx) за весь час. Плеєр повторює кожен сегмент по кілька разів,
  /// тож драйвер серій за цим лічильником швидко переходить на інший плеєр, а не чекає 30 с.
  int get blockedCount => _blocked;

  /// Подія при кожній відмові сегмента (значення — новий лічильник)
  Stream<int> get blocked => _blockedEvents.stream;

  /// Порт, на якому слухає проксі (після першого `wrap`)
  int? get port => _server?.port;

  /// Адреса списку відтворення [url], що веде через проксі. `headers` — заголовки до оригінального сервера.
  Future<String> wrap(String url, Map<String, String> headers) async {
    await _ensureStarted();
    final id = (_next++).toString();
    _headers[id] = Map.of(headers);
    while (_headers.length > _maxSessions) {
      _headers.remove(_headers.keys.first);
    }
    return _localUrl(id, Uri.parse(url));
  }

  Future<HttpServer> _ensureStarted() => _starting ??= () async {
        final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        _server = s;
        s.listen(_handle, onError: (Object e) => SourceLog.add('Проксі: помилка сервера $e'));
        SourceLog.add('Проксі HLS слухає 127.0.0.1:${s.port}');
        return s;
      }();

  HttpClient get _http => _client ??= HttpClient()
    ..connectionTimeout = const Duration(seconds: 12)
    ..idleTimeout = const Duration(seconds: 20)
    ..autoUncompress = false;

  String _localUrl(String id, Uri target) {
    final isList = target.path.toLowerCase().endsWith('.m3u8');
    final tail = isList ? 'index.m3u8' : 'seg';
    return 'http://127.0.0.1:${_server!.port}/$id/${isList ? 'm' : 's'}/${base64Url.encode(utf8.encode(target.toString()))}/$tail';
  }

  /// Переписує адреси в тексті списку на локальні. Чиста функція: без мережі.
  static String rewritePlaylist(String text, Uri base, String Function(Uri target) local) {
    final uriAttr = RegExp(r'URI="([^"]+)"');
    final out = <String>[];
    for (final raw in text.split('\n')) {
      final line = raw.endsWith('\r') ? raw.substring(0, raw.length - 1) : raw;
      if (line.trim().isEmpty) {
        out.add(line);
      } else if (line.startsWith('#')) {
        out.add(line.replaceAllMapped(uriAttr, (m) => 'URI="${local(base.resolve(m.group(1)!))}"'));
      } else {
        out.add(local(base.resolve(line.trim())));
      }
    }
    return out.join('\n');
  }

  Future<void> _handle(HttpRequest req) async {
    final parts = req.uri.pathSegments; // [id, m|s, base64, tail]
    try {
      if (parts.length < 3) {
        req.response.statusCode = HttpStatus.notFound;
        return await req.response.close();
      }
      final headers = _headers[parts[0]];
      if (headers == null) {
        req.response.statusCode = HttpStatus.gone;
        return await req.response.close();
      }
      final target = Uri.parse(utf8.decode(base64Url.decode(base64Url.normalize(parts[2]))));
      if (parts[1] == 'm') {
        await _servePlaylist(req, parts[0], headers, target);
      } else {
        await _serveSegment(req, headers, target);
      }
    } catch (e) {
      SourceLog.add('Проксі: збій $e');
      try {
        req.response.statusCode = HttpStatus.badGateway;
        await req.response.close();
      } catch (_) {}
    }
  }

  /// Заголовки, без яких CDN Moon (Cloudflare) відповідає 403: і `Accept`, і `Accept-Language` мусять бути в запиті
  /// (браузер їх шле завжди; ffmpeg шле лише `Accept`). Перевірено на живому сервері: без `Accept-Language` — 403,
  /// з обома — 200/206, а `Referer` і `User-Agent` значення не мають.
  static const Map<String, String> browserDefaults = {'Accept': '*/*', 'Accept-Language': 'uk,en;q=0.8'};

  Future<HttpClientResponse> _open(Uri target, Map<String, String> headers, {String? range}) async {
    final up = await _http.getUrl(target);
    browserDefaults.forEach((k, v) => up.headers.set(k, v));
    headers.forEach((k, v) => up.headers.set(k, v));
    up.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
    if (range != null) up.headers.set(HttpHeaders.rangeHeader, range);
    return up.close().timeout(const Duration(seconds: 25));
  }

  Future<void> _servePlaylist(HttpRequest req, String id, Map<String, String> headers, Uri target) async {
    final started = DateTime.now();
    final res = await _open(target, headers);
    final bytes = await res.fold<List<int>>(<int>[], (a, b) => a..addAll(b)).timeout(const Duration(seconds: 25));
    final ms = DateTime.now().difference(started).inMilliseconds;
    SourceLog.add('Проксі: список ${res.statusCode} $ms мс, ${bytes.length} Б ← $target');
    if (res.statusCode != 200) {
      req.response.statusCode = res.statusCode;
      return await req.response.close();
    }
    final body = rewritePlaylist(utf8.decode(bytes, allowMalformed: true), res.redirects.isEmpty ? target : res.redirects.last.location, (t) => _localUrl(id, t));
    req.response.headers.contentType = ContentType('application', 'vnd.apple.mpegurl');
    req.response.write(body);
    await req.response.close();
  }

  Future<void> _serveSegment(HttpRequest req, Map<String, String> headers, Uri target) async {
    final started = DateTime.now();
    final res = await _open(target, headers, range: req.headers.value(HttpHeaders.rangeHeader));
    final ms = DateTime.now().difference(started).inMilliseconds;
    if (res.statusCode >= 400) {
      // Тіло відмови (сторінка захисту) коротко пишемо в журнал: за ним видно, що саме відсікає сервер
      final bytes = await res.fold<List<int>>(<int>[], (a, b) => a.length < 4096 ? (a..addAll(b)) : a).timeout(const Duration(seconds: 15));
      _blocked++;
      if (_errorLogs++ < 3) {
        final text = utf8.decode(bytes, allowMalformed: true).replaceAll(RegExp(r'<[^>]*>|\s+'), ' ').trim();
        SourceLog.add('Проксі: сегмент ${res.statusCode} $ms мс ← $target · ${text.length > 200 ? text.substring(0, 200) : text}');
      } else if (_errorLogs == 4) {
        SourceLog.add('Проксі: відмови сегментів тривають — далі в журнал не пишу');
      }
      req.response.statusCode = res.statusCode;
      await req.response.close();
      _blockedEvents.add(_blocked);
      return;
    }
    if (_segmentLogs++ < 3) {
      SourceLog.add('Проксі: сегмент ${res.statusCode} $ms мс (${res.headers.contentType ?? '?'}, ${res.contentLength} Б) ← $target');
    }
    req.response.statusCode = res.statusCode;
    for (final h in [HttpHeaders.contentTypeHeader, HttpHeaders.contentLengthHeader, HttpHeaders.contentRangeHeader, HttpHeaders.acceptRangesHeader]) {
      final v = res.headers.value(h);
      if (v != null) req.response.headers.set(h, v);
    }
    await req.response.addStream(res);
    await req.response.close();
  }
}
