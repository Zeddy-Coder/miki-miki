/// Широкі зображення для банерів «Головної». Hikka віддає лише вертикальні постери, тому банер шукається
/// за MAL-id тайтлу в AniList (`bannerImage`), а якщо там його немає — у TheMovieDB (потрібен безкоштовний
/// ключ; без ключа цей крок пропускається). Результат (і «банера немає») кешується на диску: AniList
/// просять не частіше за 90 запитів на хвилину, а банери змінюються рідко.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../constants/app_identity.dart';
import '../models/hikka_models.dart';
import 'app_log.dart';
import 'storage_service.dart';

/// Знайдений банер тайтлу
class BannerArtwork {
  /// Адреса широкого зображення; `null` — банера не знайшлось
  final String? url;

  /// Домінантний колір обкладинки (ARGB) — підкладка, поки зображення вантажиться
  final int? color;

  const BannerArtwork({this.url, this.color});

  static const BannerArtwork none = BannerArtwork();

  bool get hasImage => url != null;

  Map<String, dynamic> toJson() => {if (url != null) 'u': url, if (color != null) 'c': color};

  factory BannerArtwork.fromJson(Map<String, dynamic> j) => BannerArtwork(
        url: j['u'] is String ? j['u'] as String : null,
        color: j['c'] is num ? (j['c'] as num).toInt() : null,
      );

  /// «#e49335» → 0xFFE49335
  static int? parseHexColor(Object? v) {
    if (v is! String) return null;
    final m = RegExp(r'^#?([0-9a-fA-F]{6})$').firstMatch(v.trim());
    return m == null ? null : (0xFF000000 | int.parse(m.group(1)!, radix: 16));
  }
}

/// Запит JSON-API: повертає розібране тіло або кидає виняток (мережа, не 2xx)
typedef JsonFetcher = Future<Object?> Function(String method, Uri url, {Object? body, Map<String, String>? headers});

/// Справжній `JsonFetcher` на `dart:io`
Future<Object?> ioJsonFetch(String method, Uri url, {Object? body, Map<String, String>? headers}) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8)
    ..userAgent = AppIdentity.userAgent('banners');
  try {
    final req = await client.openUrl(method, url);
    req.headers.set(HttpHeaders.acceptHeader, 'application/json');
    headers?.forEach(req.headers.set);
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.add(utf8.encode(jsonEncode(body)));
    }
    final res = await req.close().timeout(const Duration(seconds: 15));
    final text = await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 15));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw HttpException('HTTP ${res.statusCode}', uri: url);
    }
    return jsonDecode(text);
  } finally {
    client.close(force: true);
  }
}

/// Банери з AniList (GraphQL, без ключа): один запит на всі тайтли за списком MAL-id
class AniListBanners {
  static final Uri endpoint = Uri.parse('https://graphql.anilist.co');

  /// Скільки id AniList дозволяє в одному запиті сторінки
  static const int maxPerRequest = 50;

  static const String query =
      r'query($ids:[Int]){Page(perPage:50){media(idMal_in:$ids,type:ANIME){idMal bannerImage coverImage{color}}}}';

  final JsonFetcher _fetch;

  AniListBanners({JsonFetcher? fetch}) : _fetch = fetch ?? ioJsonFetch;

  /// MAL-id → банер. Тайтли, яких AniList не знає, у відповіді відсутні; без банера — `BannerArtwork.none`.
  Future<Map<int, BannerArtwork>> load(List<int> malIds) async {
    final out = <int, BannerArtwork>{};
    final ids = malIds.toSet().where((i) => i > 0).toList();
    for (var i = 0; i < ids.length; i += maxPerRequest) {
      final chunk = ids.sublist(i, i + maxPerRequest > ids.length ? ids.length : i + maxPerRequest);
      final json = await _fetch('POST', endpoint, body: {'query': query, 'variables': {'ids': chunk}}, headers: const {'Accept': 'application/json'});
      out.addAll(parse(json));
    }
    return out;
  }

  /// Розбір відповіді GraphQL
  static Map<int, BannerArtwork> parse(Object? json) {
    final out = <int, BannerArtwork>{};
    if (json is! Map) return out;
    final data = json['data'];
    final page = data is Map ? data['Page'] : null;
    final media = page is Map ? page['media'] : null;
    if (media is! List) return out;
    for (final m in media) {
      if (m is! Map) continue;
      final id = m['idMal'];
      if (id is! num) continue;
      final banner = m['bannerImage'];
      final cover = m['coverImage'];
      out[id.toInt()] = BannerArtwork(
        url: banner is String && banner.startsWith('http') ? banner : null,
        color: BannerArtwork.parseHexColor(cover is Map ? cover['color'] : null),
      );
    }
    return out;
  }
}

/// Запасний пошук банера в TheMovieDB: за японською чи ромаджі назвою й роком. Без ключа нічого не робить.
class TmdbBackdrops {
  static const String api = 'https://api.themoviedb.org/3';
  static const String images = 'https://image.tmdb.org/t/p/w1280';

  final JsonFetcher _fetch;
  final String Function() _key;

  TmdbBackdrops({JsonFetcher? fetch, String Function()? key})
      : _fetch = fetch ?? ioJsonFetch,
        _key = key ?? StorageService.getTmdbKey;

  bool get enabled => _key().trim().isNotEmpty;

  /// Адреса широкого зображення тайтлу або `null`
  Future<String?> backdropFor(HikkaAnime a) async {
    final key = _key().trim();
    if (key.isEmpty) return null;
    final isMovie = a.mediaType == 'movie';
    final queries = <String>[
      for (final t in [a.titleNative, a.titleJa, a.titleEn])
        if (t != null && t.trim().isNotEmpty) t.trim(),
    ];
    // Ключ v4 («read access token») починається з eyJ і передається заголовком, v3 — параметром
    final bearer = key.startsWith('eyJ');
    for (final q in queries.take(2)) {
      final url = Uri.parse('$api/search/${isMovie ? 'movie' : 'tv'}').replace(queryParameters: {
        if (!bearer) 'api_key': key,
        'query': q,
        'include_adult': 'false',
        if (a.year != null) (isMovie ? 'primary_release_year' : 'first_air_date_year'): '${a.year}',
      });
      final json = await _fetch('GET', url, headers: bearer ? {'Authorization': 'Bearer $key'} : null);
      final path = pickBackdrop(json);
      if (path != null) return '$images$path';
    }
    return null;
  }

  /// Перший результат із банером (результати вже впорядковані за релевантністю)
  static String? pickBackdrop(Object? json) {
    final results = json is Map ? json['results'] : null;
    if (results is! List) return null;
    for (final r in results) {
      final p = r is Map ? r['backdrop_path'] : null;
      if (p is String && p.startsWith('/')) return p;
    }
    return null;
  }
}

/// Джерело банерів із дисковим кешем
class BannerArt {
  /// Спільний екземпляр (у тестах підміняється)
  static BannerArt instance = BannerArt();

  /// Знайдений банер вважається актуальним так довго
  static const Duration foundTtl = Duration(days: 14);

  /// «Банера немає» перевіряється частіше: його могли додати згодом
  static const Duration missingTtl = Duration(days: 2);

  static const String section = 'banner_art';
  static const int _maxEntries = 400;

  final AniListBanners _anilist;
  final TmdbBackdrops _tmdb;
  final SectionLoader _load;
  final SectionSaver _save;
  final DateTime Function() _now;
  late final Map<String, dynamic> _data = Map<String, dynamic>.of(_load());

  BannerArt({AniListBanners? anilist, TmdbBackdrops? tmdb, SectionLoader? load, SectionSaver? save, DateTime Function()? now})
      : _anilist = anilist ?? AniListBanners(),
        _tmdb = tmdb ?? TmdbBackdrops(),
        _load = load ?? (() => StorageService.getSection(section)),
        _save = save ?? ((d) => StorageService.saveSection(section, d)),
        _now = now ?? DateTime.now;

  BannerArtwork? _cached(int malId, {bool allowStale = false}) {
    final e = _data['$malId'];
    if (e is! Map) return null;
    final art = BannerArtwork.fromJson(e.cast<String, dynamic>());
    final t = DateTime.fromMillisecondsSinceEpoch((e['t'] as num?)?.toInt() ?? 0);
    final ttl = art.hasImage ? foundTtl : missingTtl;
    return allowStale || _now().difference(t) < ttl ? art : null;
  }

  void _store(int malId, BannerArtwork art) {
    _data['$malId'] = {...art.toJson(), 't': _now().millisecondsSinceEpoch};
  }

  void _trim() {
    if (_data.length <= _maxEntries) return;
    final byAge = _data.entries.toList()..sort((a, b) => ((a.value as Map)['t'] as num).compareTo((b.value as Map)['t'] as num));
    for (final e in byAge.take(_data.length - _maxEntries)) {
      _data.remove(e.key);
    }
  }

  /// Банери для тайтлів: MAL-id → результат. Тайтли без MAL-id пропускаються. Збій мережі не кидає виняток:
  /// повертається те, що вдалося дізнатись (і застарілі записи кешу).
  Future<Map<int, BannerArtwork>> load(List<HikkaAnime> anime) async {
    final out = <int, BannerArtwork>{};
    final missing = <HikkaAnime>[];
    for (final a in anime) {
      if (a.malId <= 0 || out.containsKey(a.malId)) continue;
      final c = _cached(a.malId);
      if (c != null) {
        out[a.malId] = c;
      } else {
        missing.add(a);
      }
    }
    if (missing.isEmpty) return out;

    final fresh = <int, BannerArtwork>{};
    var anilistOk = true;
    try {
      fresh.addAll(await _anilist.load([for (final a in missing) a.malId]));
    } catch (e) {
      anilistOk = false;
      AppLog.w('banners', 'AniList не відповів: $e');
      for (final a in missing) {
        final stale = _cached(a.malId, allowStale: true);
        if (stale != null) out[a.malId] = stale;
      }
    }

    if (anilistOk) {
      // Запасний варіант для тих, у кого в AniList немає банера
      for (final a in missing) {
        var art = fresh[a.malId] ?? BannerArtwork.none;
        if (!art.hasImage && _tmdb.enabled) {
          try {
            final url = await _tmdb.backdropFor(a);
            if (url != null) art = BannerArtwork(url: url, color: art.color);
          } catch (e) {
            AppLog.w('banners', 'TMDB не відповів для «${a.slug}»: $e');
          }
        }
        out[a.malId] = art;
        _store(a.malId, art);
      }
      _trim();
      _save(_data);
    }
    return out;
  }
}
