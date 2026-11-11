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
import 'backend_client.dart';
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
/// Запит банерів у бекенду (MAL-id → адреса й колір); `null` — бекенд недоступний
typedef BackendBanners = Future<Map<int, (String?, int?)>?> Function(List<Map<String, Object?>> items);

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
        _key = key ?? BackendClient.effectiveTmdbKey;

  bool get enabled => _key().trim().isNotEmpty;

  /// Адреса широкого зображення тайтлу або `null`
  Future<String?> backdropFor(HikkaAnime a) async {
    final key = _key().trim();
    if (key.isEmpty) return null;
    final isMovie = a.mediaType == 'movie';
    final queries = searchQueries(a);
    // Ключ v4 («read access token») починається з eyJ і передається заголовком, v3 — параметром
    final bearer = key.startsWith('eyJ');
    Future<Object?> search(String q, {required bool withYear}) {
      final url = Uri.parse('$api/search/${isMovie ? 'movie' : 'tv'}').replace(queryParameters: {
        if (!bearer) 'api_key': key,
        'query': q,
        'include_adult': 'false',
        if (withYear && a.year != null) (isMovie ? 'primary_release_year' : 'first_air_date_year'): '${a.year}',
      });
      return _fetch('GET', url, headers: bearer ? {'Authorization': 'Bearer $key'} : null);
    }

    // Спершу з роком; далі без нього: наступний сезон давнього серіалу вийшов пізніше за перший, і TMDB знає лише серіал
    for (final withYear in [true, false]) {
      if (!withYear && (isMovie || a.year == null)) break;
      for (final q in queries.take(4)) {
        final path = pickBackdrop(await search(q, withYear: withYear));
        if (path != null) return '$images$path';
      }
    }
    return null;
  }

  /// Назви для пошуку: оригінальні, а також без позначки сезону («2nd Season», «Part 2», «Final Season», «2期»):
  /// банер потрібного сезону беремо від серіалу, тобто від попередніх сезонів
  static List<String> searchQueries(HikkaAnime a) {
    final out = <String>[];
    void add(String? t) {
      final v = t?.trim() ?? '';
      if (v.isNotEmpty && !out.contains(v)) out.add(v);
    }

    final titles = [a.titleNative, a.titleJa, a.titleEn];
    for (final t in titles) {
      add(t);
    }
    for (final t in titles) {
      add(stripSeason(t));
    }
    return out;
  }

  static final RegExp _seasonTail = RegExp(
    r'(\s*[:\-–]?\s*(\d+(st|nd|rd|th)\s+season|season\s*\d+|part\s*\d+|cour\s*\d+|final\s+season|the\s+final\s+season|\d+期|第\d+期|[ⅡⅢⅣ]|\s+(II|III|IV)))\s*$',
    caseSensitive: false,
  );

  static String? stripSeason(String? t) {
    if (t == null) return null;
    var r = t.trim();
    for (var i = 0; i < 3; i++) {
      final n = r.replaceFirst(_seasonTail, '').trim();
      if (n == r) break;
      r = n;
    }
    return r == t.trim() || r.length < 2 ? null : r;
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
  static BannerArt instance = BannerArt(backend: (items) => BackendClient.instance.banners(items));

  /// Знайдений банер вважається актуальним так довго
  static const Duration foundTtl = Duration(days: 14);

  /// «Банера немає» перевіряється частіше: його могли додати згодом
  static const Duration missingTtl = Duration(days: 2);

  static const String section = 'banner_art2';
  static const int _maxEntries = 400;

  final AniListBanners _anilist;
  final TmdbBackdrops _tmdb;
  final BackendBanners? _backend;
  final SectionLoader _load;
  final SectionSaver _save;
  final DateTime Function() _now;
  late final Map<String, dynamic> _data = Map<String, dynamic>.of(_load());

  BannerArt({AniListBanners? anilist, TmdbBackdrops? tmdb, SectionLoader? load, SectionSaver? save, DateTime Function()? now, BackendBanners? backend})
      : _backend = backend,
        _anilist = anilist ?? AniListBanners(),
        _tmdb = tmdb ?? TmdbBackdrops(),
        _load = load ?? (() => StorageService.getSection(section)),
        _save = save ?? ((d) => StorageService.saveSection(section, d)),
        _now = now ?? DateTime.now;

  BannerArtwork? _cached(int malId, {bool allowStale = false}) {
    final e = _data['$malId'];
    if (e is! Map) return null;
    final art = BannerArtwork.fromJson(e.cast<String, dynamic>());
    final t = DateTime.fromMillisecondsSinceEpoch((e['t'] as num?)?.toInt() ?? 0);
    // Запис, зроблений без TMDB (ключа ще не було), перевіряється знову, щойно ключ з'явився
    if (!allowStale && _tmdb.enabled && e['tm'] != true) return null;
    final ttl = art.hasImage ? foundTtl : missingTtl;
    return allowStale || _now().difference(t) < ttl ? art : null;
  }

  void _store(int malId, BannerArtwork art, {required bool viaTmdb}) {
    _data['$malId'] = {...art.toJson(), 't': _now().millisecondsSinceEpoch, 'tm': viaTmdb};
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

    // Спершу бекенд: він кешує адреси для всіх користувачів і сам питає TMDB та AniList
    final backend = _backend;
    if (backend != null) {
      Map<int, (String?, int?)>? got;
      try {
        got = await backend([
          for (final a in missing)
            {
              'mal': a.malId,
              'titles': [for (final t in [a.titleNative, a.titleJa, a.titleEn]) if (t != null && t.trim().isNotEmpty) t.trim()],
              if (a.year != null) 'year': a.year,
              if (a.mediaType == 'movie') 'movie': true,
            }
        ]);
      } catch (e) {
        AppLog.w('banners', 'бекенд банерів не відповів: $e');
      }
      if (got != null) {
        var served = 0;
        for (final a in missing.toList()) {
          final e = got[a.malId];
          if (e == null && !got.containsKey(a.malId)) continue; // бекенд про цей тайтл промовчав — шукаємо самі
          final art = e?.$1 == null ? BannerArtwork.none : BannerArtwork(url: e!.$1, color: e.$2);
          out[a.malId] = art;
          _store(a.malId, art, viaTmdb: true);
          missing.remove(a);
          served++;
        }
        AppLog.i('banners', 'бекенд: $served із ${served + missing.length} тайтлів, з банером ${out.values.where((x) => x.hasImage).length}');
        if (missing.isEmpty) {
          _trim();
          _save(_data);
          return out;
        }
      } else {
        AppLog.w('banners', 'бекенд банерів недоступний — шукаємо напряму');
      }
    }

    // AniList — одним запитом на всіх: колір теми й банер для запасного варіанта
    final fresh = <int, BannerArtwork>{};
    var anilistOk = true;
    try {
      fresh.addAll(await _anilist.load([for (final a in missing) a.malId]));
    } catch (e) {
      anilistOk = false;
      AppLog.w('banners', 'AniList не відповів: $e');
    }

    final tmdbOn = _tmdb.enabled;
    if (!tmdbOn) AppLog.w('banners', 'TMDB: ключа немає (ні власного, ні з бекенду) — беремо банери AniList');
    var tmdbFailed = false;
    for (final a in missing) {
      var art = fresh[a.malId] ?? BannerArtwork.none;
      var tmdbOk = !tmdbOn; // без ключа TMDB «не питали», результат AniList остаточний
      // Основне джерело — TheMovieDB; AniList лише коли TMDB нічого не дав або видав помилку
      if (tmdbOn) {
        try {
          final url = await _tmdb.backdropFor(a);
          if (url != null) {
            art = BannerArtwork(url: url, color: art.color);
            tmdbOk = true;
          } else {
            tmdbOk = true;
            AppLog.i('banners', 'TMDB: для «${a.slug}» банера не знайдено${art.hasImage ? ', беремо AniList' : ''}');
          }
        } catch (e) {
          tmdbFailed = true;
          AppLog.w('banners', 'TMDB помилка для «${a.slug}»: ${e.runtimeType}: $e${art.hasImage ? ' — беремо AniList' : ''}');
        }
      }
      if (!anilistOk && !art.hasImage) {
        final stale = _cached(a.malId, allowStale: true);
        if (stale != null) out[a.malId] = stale;
        continue;
      }
      out[a.malId] = art;
      // Збій TMDB не кешуємо як «банера немає» (наступного разу спробуємо знову)
      // Без ключа «банера немає» теж не запам'ятовуємо: ключ з бекенду може прийти трохи згодом
      if (tmdbOk && (anilistOk || art.hasImage) && (tmdbOn || art.hasImage)) _store(a.malId, art, viaTmdb: tmdbOn && tmdbOk);
    }
    final withImage = out.values.where((x) => x.hasImage).length;
    final viaTmdb = out.values.where((x) => x.url?.contains('image.tmdb.org') ?? false).length;
    AppLog.i('banners', 'банери: ${missing.length} тайтлів без кешу → з банером $withImage (TMDB $viaTmdb, AniList ${withImage - viaTmdb}), без банера ${out.length - withImage}');
    if (tmdbFailed) AppLog.w('banners', 'Були помилки TMDB — такі тайтли перевіримо знову при наступному оновленні');
    _trim();
    _save(_data);
    return out;
  }
}
