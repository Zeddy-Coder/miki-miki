import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart' show Color, HSVColor, PaintingBinding;
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

/// Справжні відповіді API Hikka, збережені під час розробки (test/data/hikka_samples).
const String kSamples = 'test/data/hikka_samples';

Object? sample(String name) => jsonDecode(File('$kSamples/$name').readAsStringSync());

Map<String, dynamic> sampleMap(String name) => sample(name) as Map<String, dynamic>;

/// Підставний сервер Hikka: віддає записані відповіді за методом і шляхом, ведучи журнал запитів.
/// Списки (каталог, персонажі) нарізаються по сторінках зі 100 записів вибірки.
class FakeHikka {
  final List<HikkaRequest> log = [];

  /// Імітація відсутності мережі
  bool offline = false;

  /// Скільки найближчих запитів завершити помилкою сервера (повтор має це пережити)
  int failNext = 0;

  /// Додаткові відповіді (акаунт, списки): якщо повертає не `null`, записана відповідь не шукається
  HikkaResponse? Function(HikkaRequest r)? interceptor;

  late final List<Map<String, dynamic>> animeList = [
    for (final e in (sampleMap('big_search.json')['list'] as List)) e as Map<String, dynamic>,
  ];

  late final List<Map<String, dynamic>> characters = [
    for (int i = 1; i <= 8; i++) sampleMap('char_$i.json'),
  ];

  /// Аніме, яке сервер вважає «хентаєм» (для перевірки закритої сторінки 18+)
  static const String adultSlug = 'adult-test-rx';

  /// Колекція, яку сервер позначає 18+ (для перевірки закритої сторінки колекції)
  static const String adultCollection = 'adult-collection-test';

  /// Зсуває розклад серій тайтлу, що виходить, у майбутнє відносно «зараз»: записаний знімок старіє,
  /// а тест «наступна серія» має працювати завжди
  bool freshSchedule = false;

  /// Час виходу [i]-ї серії в тестах: сьогодні о 23:30, далі щотижня — підписи не залежать від дня тижня, у якому
  /// запущено тести. (Якщо тести йдуть після 23:30, перша серія вже вийшла — знімки екрана тоді іншого вигляду.)
  static int _airing(int i) {
    final n = DateTime.now();
    final d = DateTime(n.year, n.month, n.day + 7 * i, 23, 30);
    return d.millisecondsSinceEpoch ~/ 1000;
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
      return _json(_page(all, r.url));
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

    // Спільнота: колекції й статті
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

// ── Підставні картинки ───────────────────────────────────────────────────────

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

/// Кольорове зображення PNG (вертикальний градієнт від відтінку, що залежить від [seed]).
/// Дає змогу бачити на скриншотах різні «постери» без мережі.
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


// ── Усе разом для тестів сторінок ────────────────────────────────────────────

/// Підставні сервіси, які потрібні сторінкам на основі Hikka: мережа Hikka, картинки, банери AniList, перегляд і
/// навігація. Створюється в `setUp`, `dispose()` — у `tearDown`.
class HikkaTestEnv {
  final FakeHikka server = FakeHikka()..freshSchedule = true;
  final Directory imageDir = Directory.systemTemp.createTempSync('hikka_env');

  /// Адреси, які просили відкрити в браузері
  final List<String> opened = [];

  /// Які тайтли мають банер в «AniList» (за MAL-id); решта — без банера, тож показується розмитий постер
  bool Function(int malId) hasBanner = (id) => id.isEven;

  /// Скільки запитів зроблено до «AniList»
  int bannerRequests = 0;

  /// Скільки запитів зроблено до «TMDB»
  int tmdbRequests = 0;

  HikkaTestEnv() {
    // Кеш розкодованих картинок спільний на весь файл: без очищення наступний тест узагалі не питав би сховище
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    HikkaApi.instance = HikkaApi(sender: server.call, retryDelay: Duration.zero);
    // Акаунт: у пам'яті, браузер — лише журнал, локальна адреса входу не піднімається (код вставляють вручну)
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
    // Блок «Дивитись» не ходить у мережу: джерел немає, сховище — у памʼяті
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
    try {
      imageDir.deleteSync(recursive: true);
    } catch (_) {}
  }
}
