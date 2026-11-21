/// Video extractors from embedded players: player page → direct links (HLS variants / mp4).
/// Source sites (UAKino, Anitube …) only give the player address; the shared code here extracts the stream.
/// Supported: Ashdi (`ashdi.vip`) and Moon (`moonanime.*`).
library;

import 'dart:convert';

import '../../models/source_models.dart';
import '../source_prefs.dart';
import 'hls.dart';
import 'hls_proxy.dart';
import 'html_select.dart';
import 'source_http.dart';
import 'source_log.dart';

/// Headers a browser uses to open the player in an `<iframe>`: some players (Moon) answer 400 without them.
Map<String, String> embedHeaders(String referer) => {
      'Referer': referer,
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'uk,en;q=0.8',
      'Sec-Fetch-Dest': 'iframe',
      'Sec-Fetch-Mode': 'navigate',
      'Sec-Fetch-Site': 'cross-site',
    };

/// `[Name]https://…,[Name2]https://…`: the list format in players (qualities, subtitles)
List<({String label, String url})> parseBracketList(String? s) {
  if (s == null || s.isEmpty || s == 'null') return const [];
  final re = RegExp(r'\[([^\]]*)\]\s*((?:https?:)?//[^,\[\s]+)');
  return [for (final m in re.allMatches(s)) (label: m.group(1)!.trim(), url: m.group(2)!)];
}

/// Subtitle language label → mpv code (the rest stays as is)
String subtitleLang(String label) {
  final l = label.toLowerCase();
  if (l.contains('укр') || l == 'uk' || l == 'ua') return 'uk';
  if (l.contains('англ') || l.contains('eng') || l == 'en') return 'en';
  if (l.contains('япон') || l.contains('jap') || l == 'ja') return 'ja';
  if (l.contains('рос') || l.contains('rus') || l == 'ru') return 'ru';
  return label;
}

abstract class VideoExtractor {
  const VideoExtractor();

  /// Player name for display ("Moon", "Ashdi")
  String get name;

  bool canHandle(Uri url);

  /// `referer`: the site page the player is "embedded" in (some players cut off foreign sources)
  Future<List<Video>> extract(SourceHttp http, String url, {String? referer});
}

class VideoExtractors {
  static const List<VideoExtractor> all = [AshdiExtractor(), MoonExtractor()];

  /// For tests: Moon videos as the player sees them (through the local proxy, if enabled)
  static Future<List<Video>> moonViaProxyForTest(List<Video> videos) => MoonExtractor._viaProxy(videos);

  static VideoExtractor? forUrl(String url) {
    final uri = SourceHttp.parseUrl(url);
    for (final e in all) {
      if (e.canHandle(uri)) return e;
    }
    return null;
  }

  /// Player label by address; `null`: unknown player
  static String? playerName(String url) => forUrl(url)?.name;
}

/// Everything common to HLS players: master → quality variants (for a direct mp4, one video)
Future<List<Video>> videosFromPlaylist(
  SourceHttp http,
  String playlistUrl, {
  required Map<String, String> playHeaders,
  List<Track> subtitles = const [],
  List<Track> audios = const [],
  List<TimeStamp> timestamps = const [],
}) async {
  final lower = playlistUrl.split('?').first.toLowerCase();
  Video plain(String title) => Video(
        url: playlistUrl,
        title: title,
        headers: playHeaders,
        subtitleTracks: subtitles,
        audioTracks: audios,
        timestamps: timestamps,
      );
  if (!lower.endsWith('.m3u8')) return [plain('Відео')];
  final res = await http.get(playlistUrl, headers: playHeaders);
  final master = parseHlsMaster(res.text, res.url);
  if (master == null) return [plain('Авто')];
  return [
    for (final v in videosFromHls(master, SourceHttp.parseUrl(playlistUrl), headers: playHeaders))
      Video(
        url: v.url,
        title: v.title,
        resolution: v.resolution,
        bitrate: v.bitrate,
        headers: v.headers,
        subtitleTracks: subtitles,
        audioTracks: audios,
        timestamps: timestamps,
      ),
  ];
}

// ── Ashdi ──────────────────────────────────────────────────────────────────────

class AshdiExtractor extends VideoExtractor {
  const AshdiExtractor();

  @override
  String get name => 'Ashdi';

  @override
  bool canHandle(Uri url) => url.host == 'ashdi.vip' || url.host.endsWith('.ashdi.vip');

  static final RegExp _file = RegExp(r'''file\s*:\s*["']((?:https?:)?//[^"']+)["']''');
  static final RegExp _subtitle = RegExp(r'''subtitle\s*:\s*["']([^"']*)["']''');

  @override
  Future<List<Video>> extract(SourceHttp http, String url, {String? referer}) async {
    final uri = SourceHttp.parseUrl(url);
    final origin = '${uri.scheme}://${uri.host}/';
    final playHeaders = {'Referer': origin, 'User-Agent': kBrowserUserAgent};
    var playlist = url;
    var subs = <Track>[];
    if (!uri.path.toLowerCase().endsWith('.m3u8')) {
      final res = await http.get(url, headers: embedHeaders(referer ?? origin));
      final scripts = select(parseHtml(res.text), 'script').map((s) => s.innerHtml).join('\n');
      final m = _file.firstMatch(scripts);
      if (m == null) throw SourceException(SourceErrorKind.badResponse, 'Ashdi: у плеєрі немає file: $url');
      playlist = SourceHttp.parseUrl(m.group(1)!, uri).toString();
      subs = [
        for (final s in parseBracketList(_subtitle.firstMatch(scripts)?.group(1)))
          Track(SourceHttp.parseUrl(s.url, uri).toString(), subtitleLang(s.label)),
      ];
    }
    return videosFromPlaylist(http, playlist, playHeaders: playHeaders, subtitles: subs);
  }
}

// ── Moon ───────────────────────────────────────────────────────────────────────

/// Moon (`moonanime.net` / `.art`): the player page hides the link in two layers of encoding,
/// both reversible with no server-side secret:
///  1) an inline script `atob("…")` → stream XOR (a seed + a 32-byte key inside the block itself) → JS code;
///  2) in it `rawVideo = f("…")`, where `f` is base64 + XOR with a static key string (the key is in the code too).
/// So no JS engine is needed: repeating two arithmetic operations is enough.
class MoonExtractor extends VideoExtractor {
  const MoonExtractor();

  @override
  String get name => 'Moon';

  @override
  bool canHandle(Uri url) => url.host.contains('moonanime.') || url.host.endsWith('.moonanime.net') || url.host.endsWith('.moonanime.art');

  static final RegExp _blob = RegExp(r'''atob\(\s*["']([A-Za-z0-9+/=]{128,})["']\s*\)''');
  static final RegExp _keyDef = RegExp(r'''var\s+k\s*=\s*["']([^"']{4,64})["']\s*;\s*var\s+b\s*=\s*atob''');
  static final RegExp _skipDef = RegExp(r'__skipSegments\s*=\s*(\[[\s\S]*?\])\s*;');

  /// In the PlayerJS template the timestamps are in encoded JSON: `__skipCtx = (… JSON.parse(f("…")) …)`
  static final RegExp _skipEncoded = RegExp(r'''__skipCtx\s*=[\s\S]{0,400}?JSON\.parse\(\s*\w+\(\s*["']([^"']+)["']\s*\)\s*\)''');

  /// The `new Playerjs({ … })` config (the page's second template): from the call to the end of the block
  static String? _playerjsConfig(String js) {
    final i = js.indexOf('new Playerjs(');
    if (i < 0) return null;
    final end = js.indexOf('});', i);
    final stop = end >= 0 ? end : (i + 8000 < js.length ? i + 8000 : js.length);
    return js.substring(i, stop);
  }

  /// Layer 1: the block with `atob(...)` → source code
  static String decodeLayer1(String base64Blob) {
    final b = base64.decode(base64.normalize(base64Blob));
    if (b.length <= 33) throw const SourceException(SourceErrorKind.badResponse, 'Moon: короткий блок');
    var prev = b[0];
    final out = List<int>.filled(b.length - 33, 0);
    for (int i = 0; i < out.length; i++) {
      final k = b[1 + i % 32];
      final c = b[33 + i];
      out[i] = c ^ k ^ prev;
      prev = (c + k) & 255;
    }
    return utf8.decode(out, allowMalformed: true);
  }

  /// Layer 2: base64 + XOR with a key string
  static String decodeXorString(String base64Text, String key) {
    final b = base64.decode(base64.normalize(base64Text));
    final k = utf8.encode(key);
    final out = List<int>.generate(b.length, (i) => b[i] ^ k[i % k.length]);
    return utf8.decode(out, allowMalformed: true);
  }

  /// Value of a field set by a decoder call (`rawVideo = f("…")`, `file: f("…")`) or by a plain string.
  /// `sep` is the separator between name and value: `=` in the Video.js template, `:` in the PlayerJS config.
  static String? _named(String js, String name, String key, {String sep = '='}) {
    final head = '["\']?\\b$name["\']?\\s*$sep\\s*';
    final call = RegExp('$head\\w+\\(\\s*["\']([^"\']*)["\']\\s*\\)').firstMatch(js);
    if (call != null) {
      final v = call.group(1)!;
      return v.isEmpty ? '' : decodeXorString(v, key);
    }
    final lit = RegExp('$head["\']([^"\']*)["\']').firstMatch(js);
    return lit?.group(1);
  }

  /// Parsing the loaded player page: the video link, subtitles, skip timestamps.
  /// Moon serves two templates: Video.js (`var rawVideo = f("…")`) and PlayerJS (`new Playerjs({ file: f("…") })`).
  static ({String video, String subtitle, List<TimeStamp> skips}) parsePage(String html) {
    final blobs = _blob.allMatches(html).map((m) => m.group(1)!).toList()..sort((a, b) => b.length.compareTo(a.length));
    if (blobs.isEmpty) throw const SourceException(SourceErrorKind.badResponse, 'Moon: у сторінці немає блоку плеєра');
    final js = decodeLayer1(blobs.first);
    final key = _keyDef.firstMatch(js)?.group(1);
    if (key == null) throw const SourceException(SourceErrorKind.badResponse, 'Moon: не знайдено ключ посилань');
    var video = _named(js, 'rawVideo', key);
    var subtitle = _named(js, 'rawSubtitle', key) ?? '';
    if (video == null || video.isEmpty) {
      final cfg = _playerjsConfig(js);
      if (cfg != null) {
        video = _named(cfg, 'file', key, sep: ':');
        subtitle = _named(cfg, 'subtitle', key, sep: ':') ?? subtitle;
      }
    }
    if (video == null || video.isEmpty) throw const SourceException(SourceErrorKind.badResponse, 'Moon: порожнє посилання на відео');
    return (video: video, subtitle: subtitle, skips: _parseSkips(js, key));
  }

  static List<TimeStamp> _parseSkips(String js, String key) {
    var raw = _skipDef.firstMatch(js)?.group(1);
    if (raw == null) {
      final enc = _skipEncoded.firstMatch(js)?.group(1);
      if (enc != null) {
        try {
          raw = decodeXorString(enc, key);
        } on FormatException {
          raw = null;
        }
      }
    }
    if (raw == null) return const [];
    try {
      Object? decoded = jsonDecode(raw);
      if (decoded is Map) decoded = decoded['segments'] ?? decoded['skips'];
      if (decoded is! List) return const [];
      final out = <TimeStamp>[];
      for (final e in decoded) {
        if (e is! Map) continue;
        final s = (e['s'] as num?)?.toDouble();
        final en = (e['e'] as num?)?.toDouble();
        if (s == null || en == null || en <= s) continue;
        out.add(_skip(s, en, (e['t'] as String?) ?? '', (e['n'] as String?)));
      }
      return out;
    } on FormatException {
      return const [];
    }
  }


  /// A skip timestamp with a Moon segment type (`opening`, `mixed_ending`, `recap` …)
  static TimeStamp _skip(double s, double e, String t, String? name) {
    final type = switch (t) {
      'opening' => ChapterType.opening,
      'mixed_opening' => ChapterType.mixedOp,
      'ending' || 'mixed_ending' => ChapterType.ending,
      'recap' => ChapterType.recap,
      _ => ChapterType.other,
    };
    final label = switch (t) {
      'opening' || 'mixed_opening' => 'Опенінґ',
      'ending' || 'mixed_ending' => 'Ендінґ',
      'recap' => 'Рекап',
      _ => name ?? 'Пропуск',
    };
    return TimeStamp(s, e, label, type);
  }

  /// Premium API hosts: `.net` is primary, `.art` is the fallback (if one of them is unreachable on the network)
  static const List<String> _apiHosts = ['https://api.moonanime.net', 'https://api.moonanime.art'];

  /// GET to the Premium API: a network error or 5xx → the next host; an answer about the key, quota or a missing title is final
  static Future<Map<String, dynamic>> _apiGet(SourceHttp http, String path, Map<String, String> headers) async {
    SourceException? last;
    for (final host in _apiHosts) {
      try {
        final res = await http.get('$host/premium/api/1.0/$path', headers: headers, throwOnError: false);
        if (res.status >= 500) {
          last = SourceException(SourceErrorKind.server, 'Moon API $host: ${res.status}', status: res.status);
          continue;
        }
        return _apiData(res);
      } on SourceException catch (e) {
        if (e.kind != SourceErrorKind.network && e.kind != SourceErrorKind.timeout) rethrow;
        last = e;
      }
    }
    throw last ?? const SourceException(SourceErrorKind.network, 'Moon API недоступний');
  }

  /// The video slug from the player address `…/iframe/<slug>/`
  static String? slugOf(Uri url) {
    final seg = url.pathSegments;
    final i = seg.indexOf('iframe');
    if (i < 0 || i + 1 >= seg.length || seg[i + 1].isEmpty) return null;
    return seg[i + 1];
  }

  /// Premium API response: `{ok: true, data: …}`; key and quota errors become `SourceException`
  static Map<String, dynamic> _apiData(SourceResponse res) {
    Object? body;
    try {
      body = res.json;
    } on SourceException {
      body = null;
    }
    if (body is Map && body['ok'] == true && body['data'] is Map) return Map<String, dynamic>.from(body['data'] as Map);
    final err = body is Map ? body['error'] : null;
    final code = err is Map ? '${err['code'] ?? ''}' : '';
    final kind = switch (res.status) {
      401 || 403 => SourceErrorKind.blocked,
      404 => SourceErrorKind.notFound,
      429 => SourceErrorKind.rateLimited,
      _ => SourceErrorKind.badResponse,
    };
    throw SourceException(kind, 'Moon API ${res.status} $code', status: res.status);
  }

  static bool _fieldsLogged = false;

  /// The shape of an answer for the log: the keys (a level deeper in braces, a list's length in brackets), and the
  /// short texts of the ones that may name the episode («title», «name», «episode»…); no links or keys
  static String fieldsOf(Map<String, dynamic> data) {
    String one(String k, Object? v, int depth) {
      if (v is Map) return depth > 0 ? '$k{${[for (final e in v.entries) one('${e.key}', e.value, depth - 1)].join(', ')}}' : '$k{…}';
      if (v is List) return '$k[${v.length}]';
      final naming = RegExp(r'title|name|episode|number', caseSensitive: false).hasMatch(k);
      if (naming && v is String && !v.startsWith('http') && v.length <= 80) return '$k=«$v»';
      if (naming && v is num) return '$k=$v';
      return k;
    }

    return [for (final e in data.entries) one(e.key, e.value, 1)].join(', ');
  }

  /// Video via the Premium API: a direct HLS link, subtitles and timestamps without parsing the player page
  static Future<List<Video>> _viaApi(SourceHttp http, Uri uri, String slug, String key) async {
    final h = {'Authorization': 'Bearer $key', 'Accept': 'application/json'};
    final enc = Uri.encodeComponent(slug);
    final data = await _apiGet(http, 'video/$enc', h);
    // What else the answer has (once a run): whether Moon knows the episodes' titles
    if (!_fieldsLogged) {
      _fieldsLogged = true;
      SourceLog.add('Moon API: поля відповіді — ${fieldsOf(data)}');
    }
    final hls = (data['video'] as Map?)?['hls'] as Map?;
    final url = (hls?['url'] as String?) ?? (hls?['cloud_url'] as String?);
    if (url == null || url.isEmpty) throw const SourceException(SourceErrorKind.badResponse, 'Moon API: у відповіді немає HLS-посилання');
    final subs = <Track>[
      for (final s in (data['subtitles'] as List? ?? const []))
        if (s is Map && (s['url'] as String?)?.isNotEmpty == true) Track(s['url'] as String, subtitleLang('${s['label'] ?? s['lang'] ?? ''}')),
    ];
    final skips = <TimeStamp>[];
    try {
      final sk = await _apiGet(http, 'skips/video/$enc', h);
      for (final e in (sk['skips'] as List? ?? const [])) {
        if (e is! Map) continue;
        final s = (e['start_sec'] as num?)?.toDouble() ?? ((e['start_ms'] as num?)?.toDouble() ?? -1) / 1000;
        final en = (e['end_sec'] as num?)?.toDouble() ?? ((e['end_ms'] as num?)?.toDouble() ?? -1) / 1000;
        if (s < 0 || en <= s) continue;
        skips.add(_skip(s, en, '${e['segment_type'] ?? ''}', null));
      }
    } on SourceException catch (e) {
      SourceLog.add('Moon API: таймкоди недоступні (${e.detail})');
    }
    SourceLog.add('Moon API: $slug, субтитрів ${subs.length}, пропусків ${skips.length}');
    final playHeaders = {'Referer': 'https://${uri.host}/', 'User-Agent': kBrowserUserAgent, ...HlsProxy.browserDefaults};
    final out = await videosFromPlaylist(http, url, playHeaders: playHeaders, subtitles: subs, timestamps: skips);
    return _viaProxy(out);
  }

  @override
  Future<List<Video>> extract(SourceHttp http, String url, {String? referer}) async {
    final uri = SourceHttp.parseUrl(url);
    final key = SourcePrefs.instance.effectiveMoonKey;
    final slug = slugOf(uri);
    if (key.isNotEmpty && slug != null) {
      try {
        return await _viaApi(http, uri, slug, key);
      } on SourceException catch (e) {
        // The key does not work, the quota is exhausted or the API is unavailable: the player still opens by parsing the
        // page. Whose key it was tells what to fix: the settings field or the backend's
        final own = SourcePrefs.instance.moonKey.isNotEmpty;
        SourceLog.add('Moon API не вийшло (${e.detail}; ключ ${own ? 'із налаштувань' : 'з бекенда'}), розбираю сторінку плеєра');
      }
    }
    final res = await http.get(url, headers: embedHeaders(referer ?? 'https://anitube.in.ua/'));
    SourceLog.add('Moon: сторінка плеєра ${res.text.length} символів, блоків atob: ${_blob.allMatches(res.text).length}');
    final page = parsePage(res.text);
    SourceLog.add('Moon: відео ${page.video.length > 160 ? '${page.video.substring(0, 160)}…' : page.video}; субтитри: ${page.subtitle.isEmpty ? 'нема' : 'є'}; пропуски: ${page.skips.length}');
    if (page.video.trimLeft().startsWith('[{') || page.video.trimLeft().startsWith('{')) {
      throw const SourceException(SourceErrorKind.unsupported, 'Moon: це сторінка з плейлистом серіалу, потрібна адреса окремої серії');
    }
    // Moon's CDN answers 403 if the request has no `Accept-Language` (ffmpeg does not send it), so we add browser headers
    final playHeaders = {'Referer': 'https://${uri.host}/', 'User-Agent': kBrowserUserAgent, ...HlsProxy.browserDefaults};
    final subs = [for (final s in parseBracketList(page.subtitle)) Track(s.url, subtitleLang(s.label))];
    final sources = parseBracketList(page.video);
    SourceLog.add('Moon: варіантів якості ${sources.length}');
    final out = <Video>[];
    if (sources.isEmpty) {
      out.addAll(await videosFromPlaylist(http, page.video.trim(), playHeaders: playHeaders, subtitles: subs, timestamps: page.skips));
    } else {
      for (final s in sources) {
        if (s.url.split('?').first.toLowerCase().endsWith('.m3u8')) {
          out.addAll(await videosFromPlaylist(http, s.url, playHeaders: playHeaders, subtitles: subs, timestamps: page.skips));
        } else {
          final h = int.tryParse(s.label.replaceAll(RegExp(r'\D'), ''));
          out.add(Video(
            url: s.url,
            title: h != null ? '${h}p' : s.label,
            resolution: h,
            headers: playHeaders,
            subtitleTracks: subs,
            timestamps: page.skips,
          ));
        }
      }
    }
    return _viaProxy(out);
  }

  /// On Android libmpv cannot get through Moon's CDN (TLS/403): we serve the video through a local proxy (`HlsProxy`)
  static Future<List<Video>> _viaProxy(List<Video> videos) async {
    if (!HlsProxy.enabled) return videos;
    try {
      return [
        for (final v in videos) v.copyWith(url: await HlsProxy.instance.wrap(v.url, v.headers), headers: const {}),
      ];
    } catch (e) {
      SourceLog.add('Moon: проксі не запустився ($e), відкриваю напряму');
      return videos;
    }
  }
}

// ── An episode with several players ──────────────────────────────────────────────────────

/// The player an episode lives in: name (`moon`, `ashdi` …) and address
class EmbedLink {
  final String provider;
  final String url;

  const EmbedLink(this.provider, this.url);
}

/// Player selection order: the first to give a video wins. Fenix and Tortuga are not supported yet.
const List<String> kProviderOrder = ['moon', 'ashdi'];

/// Player name by address (`moon`, `ashdi`) or an empty string
String providerOf(String url) => VideoExtractors.playerName(url)?.toLowerCase() ?? '';

/// Episodes with several players put them in `SEpisode.data` as `{"e": [["moon","https://…"], …]}`
String encodeEmbeds(Iterable<EmbedLink> embeds, {Map<String, Object?> extra = const {}}) => jsonEncode({
      'e': [for (final m in embeds) [m.provider, m.url]],
      ...extra,
    });

/// Episode players: from `data`, and if there is none, the single `url` address
List<EmbedLink> embedsOf(SEpisode ep) {
  final d = ep.data;
  if (d != null && d.isNotEmpty) {
    try {
      final j = jsonDecode(d);
      if (j is Map && j['e'] is List) {
        final list = [for (final x in j['e'] as List) if (x is List && x.length >= 2) EmbedLink('${x[0]}', '${x[1]}')];
        if (list.isNotEmpty) return list;
      }
    } on FormatException {
      // fall back to url
    }
  }
  return [EmbedLink(providerOf(ep.url), ep.url)];
}

/// Players we can open, in the order of [kProviderOrder] (the rest by the presence of an extractor)
List<Hoster> hostersFor(SEpisode ep) {
  final out = <Hoster>[];
  for (final m in embedsOf(ep)) {
    final ex = VideoExtractors.forUrl(m.url);
    if (ex == null) continue;
    out.add(Hoster(name: ex.name, url: m.url));
  }
  int rank(Hoster h) {
    final i = kProviderOrder.indexOf(h.name.toLowerCase());
    return i < 0 ? kProviderOrder.length : i;
  }

  out.sort((a, b) => rank(a).compareTo(rank(b)));
  return out;
}

/// Video of a player (hoster)
Future<List<Video>> hosterVideosOf(SourceHttp http, Hoster h, {String? referer}) async {
  if (h.videos != null) return h.videos!;
  final ex = VideoExtractors.forUrl(h.url);
  if (ex == null) throw const SourceException(SourceErrorKind.unsupported, 'невідомий плеєр');
  return ex.extract(http, h.url, referer: referer);
}

/// Tries the episode's players in turn; the first to give a video wins
Future<List<Video>> videosOfEpisode(SourceHttp http, SEpisode ep, {String? referer}) async {
  final hs = hostersFor(ep);
  if (hs.isEmpty) {
    throw const SourceException(SourceErrorKind.unsupported, 'для цієї серії немає плеєра, який підтримується (Fenix, Tortuga)');
  }
  SourceException? last;
  for (final h in hs) {
    try {
      final v = await hosterVideosOf(http, h, referer: referer);
      if (v.isNotEmpty) return v;
    } on SourceException catch (e) {
      last = e;
    }
  }
  throw last ?? const SourceException(SourceErrorKind.badResponse, 'жоден плеєр не віддав відео');
}
