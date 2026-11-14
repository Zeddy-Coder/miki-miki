import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart' show Color, HSVColor, PaintingBinding;
import 'package:miki_miki/utils/app_clock.dart';
import 'package:miki_miki/models/hikka_models.dart' show HikkaTitleLang;
import 'package:miki_miki/services/banner_art.dart';
import 'package:miki_miki/services/hikka_api.dart';
import 'package:miki_miki/services/hikka_auth.dart';
import 'package:miki_miki/services/hikka_images.dart';
import 'package:miki_miki/services/hikka_lists.dart';
import 'package:miki_miki/services/hikka_nav.dart';
import 'package:miki_miki/services/hikka_prefs.dart';
import 'package:miki_miki/services/source_prefs.dart';
import 'package:miki_miki/services/source_registry.dart';
import 'package:miki_miki/services/watch_service.dart';
import 'package:miki_miki/services/watch_store.dart';

/// Real Hikka API responses saved during development (test/data/hikka_samples).
const String kSamples = 'test/data/hikka_samples';

Object? sample(String name) => jsonDecode(File('$kSamples/$name').readAsStringSync());

Map<String, dynamic> sampleMap(String name) => sample(name) as Map<String, dynamic>;

/// A fake Hikka server: serves recorded responses by method and path, keeping a request log.
/// Lists (catalog, characters) are cut into pages of 100 records of the sample.
class FakeHikka {
  final List<HikkaRequest> log = [];

  /// Simulating the absence of a network
  bool offline = false;

  /// How many of the nearest requests to end with a server error (a retry must survive it)
  int failNext = 0;

  /// Extra responses (account, lists): if it returns non-`null`, the recorded response is not looked up
  HikkaResponse? Function(HikkaRequest r)? interceptor;

  late final List<Map<String, dynamic>> animeList = [
    for (final e in (sampleMap('big_search.json')['list'] as List)) e as Map<String, dynamic>,
  ];

  late final List<Map<String, dynamic>> characters = [
    for (int i = 1; i <= 8; i++) sampleMap('char_$i.json'),
  ];

  /// An anime the server considers "hentai" (for checking the closed 18+ page)
  static const String adultSlug = 'adult-test-rx';

  /// A collection the server marks 18+ (for checking the closed collection page)
  static const String adultCollection = 'adult-collection-test';

  /// Shifts the schedule of an airing title's episodes into the future relative to "now": the recorded snapshot ages,
  /// and the "next episode" test must always work
  bool freshSchedule = false;

  /// Air time of the [i]-th episode in tests: today at 23:30, then weekly: labels do not depend on the weekday the
  /// tests run on. (If the tests run after 23:30, the first episode has already aired and screenshots look different.)
  static int _airing(int i) {
    final n = AppClock.now();
    final d = DateTime(n.year, n.month, n.day + 7 * i, 23, 30);
    return d.millisecondsSinceEpoch ~/ 1000;
  }

  /// The schedule snapshot was recorded in one specific week and ages. All records shift by a whole number of weeks
  /// (weekday and hour stay) so the snapshot's window covers "now": there are episodes today, and the other days are as in the snapshot.
  static List<Map<String, dynamic>> _scheduleNow(List<Map<String, dynamic>> all, {DateTime? now}) {
    if (all.isEmpty) return all;
    const week = 7 * 86400;
    final t = (now ?? AppClock.now()).millisecondsSinceEpoch ~/ 1000;
    final first = all.map((e) => e['airing_at'] as int).reduce((a, b) => a < b ? a : b);
    // The window start is the first record's shift by whole weeks nearest to "now" (not later)
    final shift = ((t - first) ~/ week) * week;
    return [for (final e in all) {...e, 'airing_at': (e['airing_at'] as int) + shift}];
  }

  Map<String, dynamic> _rebased(Map<String, dynamic> a) {
    final sched = a['schedule'];
    if (!freshSchedule || sched is! List || sched.isEmpty) return a;
    return {
      ...a,
      'schedule': [
        for (int i = 0; i < sched.length; i++) {...(sched[i] as Map<String, dynamic>), 'airing_at': _airing(i)},
      ],
    };
  }

  int count(bool Function(HikkaRequest r) test) => log.where(test).length;

  HikkaResponse _json(Object? body, [int status = 200]) => HikkaResponse(status, jsonEncode(body));

  Map<String, dynamic> _page(List<Map<String, dynamic>> all, Uri url) {
    final page = int.tryParse(url.queryParameters['page'] ?? '') ?? 1;
    final size = int.tryParse(url.queryParameters['size'] ?? '') ?? 15;
    final pages = (all.length / size).ceil().clamp(1, 1 << 20);
    final from = ((page - 1) * size).clamp(0, all.length);
    final to = (from + size).clamp(0, all.length);
    return {
      'pagination': {'total': all.length, 'pages': pages, 'page': page},
      'list': all.sublist(from, to),
    };
  }

  Map<String, dynamic>? _animeBySlug(String slug) {
    if (slug == sampleMap('info.json')['slug']) return sampleMap('info.json');
    if (slug == sampleMap('info_ongoing.json')['slug']) return sampleMap('info_ongoing.json');
    if (slug == adultSlug) return {...sampleMap('info.json'), 'slug': adultSlug, 'rating': 'rx', 'nsfw': true, 'title_ua': 'Дорослий тайтл'};
    for (final a in animeList) {
      if (a['slug'] == slug) return a;
    }
    return null;
  }

  Future<HikkaResponse> call(HikkaRequest r) async {
    log.add(r);
    if (offline) throw const SocketException('Failed host lookup: api.hikka.io');
    if (failNext > 0) {
      failNext--;
      return HikkaResponse(500, jsonEncode({'code': 'system:internal', 'message': 'boom'}));
    }
    final path = r.url.path;
    final hooked = interceptor?.call(r);
    if (hooked != null) return hooked;
    final segs = path.split('/').where((s) => s.isNotEmpty).toList();
    final body = r.body == null ? const <String, dynamic>{} : jsonDecode(r.body!) as Map<String, dynamic>;

    HikkaResponse notFound() => _json({'code': 'anime:not_found', 'message': 'Not found'}, 404);

    if (r.method == 'POST' && path == '/anime') {
      final q = (body['query'] as String?)?.toLowerCase();
      var list = animeList;
      if (q != null) {
        list = [
          for (final a in animeList)
            if ('${a['title_ua']} ${a['title_en']} ${a['title_ja']}'.toLowerCase().contains(q)) a,
        ];
      }
      return _json(_page(list, r.url));
    }
    if (r.method == 'POST' && path == '/schedule/anime') {
      final all = (sampleMap('sched_default.json')['list'] as List).cast<Map<String, dynamic>>();
      return _json(_page(_scheduleNow(all), r.url));
    }
    if (r.method == 'POST' && path == '/characters') {
      final q = (body['query'] as String?)?.toLowerCase();
      var list = characters;
      if (q != null) {
        list = [
          for (final c in characters)
            if ('${c['name_ua']} ${c['name_en']} ${c['name_ja']}'.toLowerCase().contains(q)) c,
        ];
      }
      return _json(_page(list, r.url));
    }
    if (r.method == 'GET' && path == '/genres') return _json(sample('genres.json'));

    // Community: collections and articles
    if (r.method == 'POST' && path == '/collections') {
      var all = (sampleMap('collections_list.json')['list'] as List).cast<Map<String, dynamic>>();
      final type = body['content_type'];
      if (type != null) all = [for (final c in all) if (c['content_type'] == type) c];
      final sorted = body['sort'] is List && (body['sort'] as List).first == 'created:desc';
      if (sorted) all = all.reversed.toList();
      return _json(_page(all, r.url));
    }
    if (r.method == 'GET' && segs.length == 2 && segs[0] == 'collections') {
      final detail = sampleMap('collection_detail.json');
      if (segs[1] == adultCollection) return _json({...detail, 'reference': adultCollection, 'nsfw': true, 'title': 'Дорослі добірки'});
      if (segs[1] == detail['reference']) return _json(detail);
      for (final c in (sampleMap('collections_list.json')['list'] as List).cast<Map<String, dynamic>>()) {
        if (c['reference'] == segs[1]) return _json({...c, 'collection': detail['collection'], 'entries': (detail['collection'] as List).length});
      }
      return _json({'code': 'collections:not_found', 'message': 'Not found'}, 404);
    }
    if (r.method == 'POST' && path == '/articles') {
      var all = (sampleMap('articles_list.json')['list'] as List).cast<Map<String, dynamic>>();
      final cats = body['categories'];
      if (cats is List && cats.isNotEmpty) all = [for (final a in all) if (cats.contains(a['category'])) a];
      final top = body['sort'] is List && (body['sort'] as List).first == 'vote_score:desc';
      if (top) all = [...all]..sort((a, b) => (b['vote_score'] as num).compareTo(a['vote_score'] as num));
      return _json(_page(all, r.url));
    }
    if (r.method == 'GET' && segs.length == 2 && segs[0] == 'articles') {
      final detail = sampleMap('article_detail.json');
      if (segs[1] == detail['slug']) return _json(detail);
      for (final a in (sampleMap('articles_list.json')['list'] as List).cast<Map<String, dynamic>>()) {
        if (a['slug'] == segs[1]) return _json({...a, 'document': detail['document']});
      }
      return _json({'code': 'articles:not_found', 'message': 'Not found'}, 404);
    }

    if (r.method == 'GET' && segs.length == 2 && segs[0] == 'anime') {
      final a = _animeBySlug(segs[1]);
      return a == null ? notFound() : _json(_rebased(a));
    }
    if (r.method == 'GET' && segs.length == 3 && segs[0] == 'anime') {
      switch (segs[2]) {
        case 'characters':
          return _json(sample('frieren_chars.json'));
        case 'staff':
          return _json(sample('staff.json'));
        case 'recommendations':
          return _json(sample('recs.json'));
      }
    }
    if (r.method == 'GET' && segs.length == 4 && segs[0] == 'related' && segs[3] == 'franchise') {
      final slugs = [for (final a in (sampleMap('related_franchise.json')['anime'] as List)) (a as Map)['slug']];
      return slugs.contains(segs[2]) ? _json(sample('related_franchise.json')) : notFound();
    }
    // People: we pass the first crew person off as a card with works
    if (r.method == 'GET' && segs.isNotEmpty && segs[0] == 'people') {
      final person = ((sampleMap('staff.json')['list'] as List).first as Map<String, dynamic>)['person'] as Map<String, dynamic>;
      if (segs.length == 2) return _json({...person, 'description_ua': 'Опис людини.', 'anime_count': 2, 'characters_count': 1, 'manga_count': 0});
      if (segs.length == 3 && segs[2] == 'anime') {
        return _json(_page([
          for (final a in animeList.take(2))
            {'anime': a, 'roles': [{'name_ua': 'Режисер', 'name_en': 'Director'}]},
        ], r.url));
      }
      if (segs.length == 3 && segs[2] == 'characters') {
        return _json(_page([
          {'character': characters.first, 'anime': animeList.first},
        ], r.url));
      }
    }
    if (r.method == 'GET' && segs.length == 2 && segs[0] == 'characters') {
      for (final c in characters) {
        if (c['slug'] == segs[1]) return _json(c);
      }
      return notFound();
    }
    if (r.method == 'GET' && segs.length == 3 && segs[0] == 'characters') {
      if (segs[2] == 'anime') return _json(sample('char_anime.json'));
      if (segs[2] == 'voices') return _json(sample('char_voices.json'));
    }
    return notFound();
  }
}

// ── Fake images ───────────────────────────────────────────────────────────

int _crc(List<int> bytes) {
  var c = 0xFFFFFFFF;
  for (final b in bytes) {
    c ^= b;
    for (int k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? (c >> 1) ^ 0xEDB88320 : c >> 1;
    }
  }
  return c ^ 0xFFFFFFFF;
}

List<int> _chunk(String type, List<int> data) {
  final head = [...type.codeUnits, ...data];
  final out = BytesBuilder();
  out.add(_be32(data.length));
  out.add(head);
  out.add(_be32(_crc(head)));
  return out.toBytes();
}

List<int> _be32(int v) => [(v >> 24) & 255, (v >> 16) & 255, (v >> 8) & 255, v & 255];

/// A colored PNG image (a vertical gradient from a hue that depends on [seed]).
/// Lets screenshots show different "posters" without a network.
Uint8List fakePng(String seed, {int w = 42, int h = 60}) {
  final hue = (seed.hashCode.abs() % 360).toDouble();
  final top = HSVColor.fromAHSV(1, hue, 0.55, 0.88).toColor();
  final bottom = HSVColor.fromAHSV(1, (hue + 40) % 360, 0.75, 0.38).toColor();
  final raw = BytesBuilder();
  for (int y = 0; y < h; y++) {
    raw.addByte(0);
    final c = Color.lerp(top, bottom, y / (h - 1))!;
    for (int x = 0; x < w; x++) {
      raw.add([(c.r * 255).round(), (c.g * 255).round(), (c.b * 255).round()]);
    }
  }
  final out = BytesBuilder();
  out.add([137, 80, 78, 71, 13, 10, 26, 10]);
  out.add(_chunk('IHDR', [..._be32(w), ..._be32(h), 8, 2, 0, 0, 0]));
  out.add(_chunk('IDAT', zlib.encode(raw.toBytes())));
  out.add(_chunk('IEND', const []));
  return out.toBytes();
}


// ── Everything together for page tests ────────────────────────────────────────

/// Fake services that Hikka-based pages need: the Hikka network, images, AniList banners, watching and
/// navigation. Created in `setUp`, `dispose()` in `tearDown`.
class HikkaTestEnv {
  final FakeHikka server = FakeHikka()..freshSchedule = true;
  final Directory imageDir = Directory.systemTemp.createTempSync('hikka_env');

  /// Addresses that were asked to open in a browser
  final List<String> opened = [];

  /// Which titles have a banner in "AniList" (by MAL id); the rest have none, so a blurred poster is shown
  bool Function(int malId) hasBanner = (id) => id.isEven;

  /// How many requests were made to "AniList"
  int bannerRequests = 0;

  /// How many requests were made to "TMDB"
  int tmdbRequests = 0;

  /// A fixed "now" for screens with days and hours: Wednesday, November 4, 2026, 12:00: the schedule snapshot's window
  static final DateTime fixedNow = DateTime(2026, 11, 4, 12);

  HikkaTestEnv() {
    AppClock.now = () => fixedNow;
    // The decoded image cache is shared across the whole file: without clearing, the next test would not ask the store at all
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    HikkaApi.instance = HikkaApi(sender: server.call, retryDelay: Duration.zero);
    // Account: in memory, the browser is only a log, the local sign-in address is not brought up (the code is pasted manually)
    HikkaAuth.instance = HikkaAuth(
      load: () => {},
      save: (_) {},
      urlOpener: (url) async {
        opened.add(url);
        return true;
      },
      loopbackFactory: () async => null,
    );
    HikkaMyList.instance = HikkaMyList();
    HikkaImageStore.instance = HikkaImageStore(dir: imageDir, fetcher: (url) async => fakePng(url));
    HikkaPrefs.instance = HikkaPrefs(titleLang: HikkaTitleLang.ua, allowAdult: false);
    // The "Дивитись" block does not go to the network: there are no sources, the store is in memory
    WatchService.instance = WatchService(
      registry: SourceRegistry(sources: const [], prefs: SourcePrefs(load: () => {}, save: (_) {})),
      store: WatchStore(load: () => {}, save: (_) {}),
    );
    BannerArt.instance = BannerArt(
      anilist: AniListBanners(fetch: _anilist),
      tmdb: TmdbBackdrops(
        fetch: (method, url, {body, headers}) async {
          tmdbRequests++;
          return const {'results': []};
        },
        key: () => '',
      ),
      load: () => {},
      save: (_) {},
    );
    HikkaNav.instance = HikkaNav()
      ..urlOpener = (url) async {
        opened.add(url);
        return true;
      };
  }

  Future<Object?> _anilist(String method, Uri url, {Object? body, Map<String, String>? headers}) async {
    bannerRequests++;
    final ids = (((body as Map)['variables'] as Map)['ids'] as List).cast<int>();
    return {
      'data': {
        'Page': {
          'media': [
            for (final id in ids)
              {
                'idMal': id,
                'bannerImage': hasBanner(id) ? 'https://s4.anilist.co/file/anilistcdn/media/anime/banner/$id.jpg' : null,
                'coverImage': {'color': hasBanner(id) ? '#e49335' : null},
              },
          ],
        },
      },
    };
  }

  void dispose() {
    AppClock.now = DateTime.now;
    try {
      imageDir.deleteSync(recursive: true);
    } catch (_) {}
  }
}
