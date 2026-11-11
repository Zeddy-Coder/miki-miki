import 'package:flutter_test/flutter_test.dart';
import 'package:miki_miki/services/app_log.dart';
import 'package:miki_miki/models/hikka_models.dart';
import 'package:miki_miki/services/banner_art.dart';
import 'package:miki_miki/services/continue_watching.dart';
import 'package:miki_miki/services/hikka_api.dart';
import 'package:miki_miki/services/watch_store.dart';
import 'package:miki_miki/widgets/hikka/hikka_airing_strip.dart';

import 'support/hikka_fakes.dart';

const String frierenSlug = 'sousou-no-frieren-ad4e3e';
const String ongoingSlug = 'kyouran-reijou-nia-liston-byoujaku-reijou-ni-tensei-shita-kamigoroshi-no-bujin-no-karei-naru-musouroku-d98982';

HikkaAnime anime(int malId, {String? slug, String? mediaType = 'tv', int? year = 2024, String? titleJa = 'Nihongo', String? titleEn = 'English', String? titleNative = 'ネイティブ'}) {
  return HikkaAnime.fromJson({
    'slug': slug ?? 'a$malId',
    'mal_id': malId,
    'media_type': mediaType,
    'year': year,
    'title_ja': titleJa,
    'title_en': titleEn,
    'title_native': titleNative,
  });
}

void main() {
  // ── Дрібні помічники ───────────────────────────────────────────────────────

  group('HikkaText.compact', () {
    test('до тисячі — як є, далі тисячі й мільйони з одним знаком', () {
      expect(HikkaText.compact(0), '0');
      expect(HikkaText.compact(950), '950');
      expect(HikkaText.compact(1000), '1 тис.');
      expect(HikkaText.compact(1250), '1,3 тис.');
      expect(HikkaText.compact(9999), '10 тис.');
      expect(HikkaText.compact(48000), '48 тис.');
      expect(HikkaText.compact(999999), '999 тис.');
      expect(HikkaText.compact(2400000), '2,4 млн');
      expect(HikkaText.compact(-1500), '-1,5 тис.');
    });
  });

  group('HikkaAiring: підпис серії у стрічці календаря', () {
    final now = DateTime(2026, 11, 3, 12, 0);
    final base = FakeHikka().animeList.first;

    HikkaScheduleEntry entry(Duration fromNow) => HikkaScheduleEntry(
          anime: HikkaAnime.fromJson(base),
          episode: 5,
          airingAt: now.add(fromNow).millisecondsSinceEpoch ~/ 1000,
        );

    test('щойно вийшла, вийшла хвилини тому — акцент', () {
      final a = HikkaAiring.of(entry(const Duration(seconds: -20)), now);
      expect(a.text, 'вийшла щойно');
      expect(a.live, isTrue);
      final b = HikkaAiring.of(entry(const Duration(minutes: -20)), now);
      expect(b.text, 'вийшла 20 хв тому');
      expect(b.live, isTrue);
    });

    test('вийшла годину-дві тому — час виходу, ще акцент; давно — без акценту', () {
      final a = HikkaAiring.of(entry(const Duration(hours: -2)), now);
      expect(a.text, 'вийшла о 10:00');
      expect(a.live, isTrue);
      final b = HikkaAiring.of(entry(const Duration(hours: -6)), now);
      expect(b.text, 'вийшла о 06:00');
      expect(b.live, isFalse);
    });

    test('скоро вийде: за хвилини; далі — «Сьогодні, 17:00» чи «Завтра, …»', () {
      expect(HikkaAiring.of(entry(const Duration(minutes: 30)), now).text, 'через 30 хв');
      expect(HikkaAiring.of(entry(const Duration(seconds: 90)), now).text, 'через 1 хв');
      final today = HikkaAiring.of(entry(const Duration(hours: 5)), now);
      expect(today.text, 'Сьогодні, 17:00');
      expect(today.live, isFalse);
      expect(HikkaAiring.of(entry(const Duration(hours: 20)), now).text, 'Завтра, 08:00');
    });
  });

  // ── Продовжити перегляд ────────────────────────────────────────────────────

  group('ContinueWatching', () {
    test('підписи серій: звичайна, порядкова, сезонна, порожня', () {
      expect(ContinueWatching.episodeCaption('3'), 'Серія 3');
      expect(ContinueWatching.episodeCaption('3.5'), 'Серія 3.5');
      expect(ContinueWatching.episodeCaption('i7'), 'Серія 7');
      expect(ContinueWatching.episodeCaption('s2e5'), 'Сезон 2 · серія 5');
      expect(ContinueWatching.episodeCaption(''), isNull);
      expect(ContinueWatching.episodeShort('3'), 'Серія 3');
      expect(ContinueWatching.episodeShort('s2e5'), 'С2 · Е5');
      expect(ContinueWatching.episodeShort('i7'), 'Серія 7');
      expect(ContinueWatching.episodeShort(''), isNull);
    });

    late int clock;
    late WatchStore store;

    setUp(() {
      clock = 1000;
      store = WatchStore(load: () => {}, save: (_) {}, now: () => DateTime.fromMillisecondsSinceEpoch(clock += 1000));
    });

    test('recent: лише тайтли Hikka, найновіші першими, ліміт', () {
      store
        ..setLast('hikka:one', '1', 'g')
        ..setLast('other:site', '4', 'g')
        ..setLast('hikka:two', 's1e2', 'g')
        ..setLast('hikka:', '1', 'g')
        ..setLast('hikka:three', '', 'g');
      final all = ContinueWatching.recent(store: store);
      expect(all.map((e) => e.$1), ['three', 'two', 'one']);
      expect(all.map((e) => e.$2), [isNull, 's1e2', '1'], reason: 'порожній номер серії — null');
      expect(ContinueWatching.recent(store: store, limit: 2).map((e) => e.$1), ['three', 'two']);
      store.setLast('hikka:one', '2', 'g');
      final first = ContinueWatching.recent(store: store).first;
      expect((first.$1, first.$2), ('one', '2'), reason: 'щойно відкритий — першим');
    });

    test('load: підтягує тайтли, пропускає збійні, 18+ і повністю переглянуті завершені', () async {
      final server = FakeHikka();
      final api = HikkaApi(sender: server.call, retryDelay: Duration.zero);
      store
        ..setLast('hikka:$frierenSlug', '28', 'g') // завершений, усі 28 серій позначено
        ..setLast('hikka:$ongoingSlug', '3', 'g') // виходить: лишається
        ..setLast('hikka:${FakeHikka.adultSlug}', '1', 'g') // 18+
        ..setLast('hikka:there-is-no-such-anime', '1', 'g'); // сервер не знає
      for (var i = 1; i <= 28; i++) {
        store.setWatched('hikka:$frierenSlug', '$i', true);
      }

      final items = await ContinueWatching.load(store: store, api: api);
      expect(items.map((i) => i.anime.slug), [ongoingSlug]);
      expect(items.single.episodeKey, '3');
      expect(items.single.episodeLabel, 'Серія 3');
      expect(items.single.episodeShort, 'Серія 3');

      api.clearCache();
      final withAdult = await ContinueWatching.load(store: store, api: api, allowAdult: true);
      expect(withAdult.map((i) => i.anime.slug), [FakeHikka.adultSlug, ongoingSlug], reason: 'з дозволом 18+ дорослий тайтл повертається (відкривали пізніше — тому першим)');
    });

    test('load: завершений, але не дивлений до кінця, лишається в списку', () async {
      final server = FakeHikka();
      final api = HikkaApi(sender: server.call, retryDelay: Duration.zero);
      store.setLast('hikka:$frierenSlug', '5', 'g');
      for (var i = 1; i <= 5; i++) {
        store.setWatched('hikka:$frierenSlug', '$i', true);
      }
      final items = await ContinueWatching.load(store: store, api: api);
      expect(items.map((i) => i.anime.slug), [frierenSlug]);
    });

    test('load: порожня історія — жодного запиту', () async {
      final server = FakeHikka();
      final api = HikkaApi(sender: server.call, retryDelay: Duration.zero);
      expect(await ContinueWatching.load(store: store, api: api), isEmpty);
      expect(server.log, isEmpty);
    });
  });

  // ── Банери ─────────────────────────────────────────────────────────────────

  group('AniListBanners', () {
    test('розбір відповіді: банер і колір; без банера — лише колір; чужі записи ігноруються', () {
      final parsed = AniListBanners.parse({
        'data': {
          'Page': {
            'media': [
              {'idMal': 1, 'bannerImage': 'https://s4.anilist.co/b/1.jpg', 'coverImage': {'color': '#e49335'}},
              {'idMal': 2, 'bannerImage': null, 'coverImage': {'color': '#fff'}},
              {'idMal': 3, 'bannerImage': 'not-a-url', 'coverImage': {}},
              {'idMal': null, 'bannerImage': 'https://x/y.jpg'},
              'мотлох',
            ],
          },
        },
      });
      expect(parsed.keys, [1, 2, 3]);
      expect(parsed[1]!.url, 'https://s4.anilist.co/b/1.jpg');
      expect(parsed[1]!.color, 0xFFE49335);
      expect(parsed[1]!.hasImage, isTrue);
      expect(parsed[2]!.hasImage, isFalse);
      expect(parsed[2]!.color, isNull, reason: 'короткий #fff не підходить');
      expect(parsed[3]!.url, isNull);
    });

    test('зіпсована відповідь не падає', () {
      expect(AniListBanners.parse(null), isEmpty);
      expect(AniListBanners.parse('x'), isEmpty);
      expect(AniListBanners.parse({'data': null}), isEmpty);
      expect(AniListBanners.parse({'data': {'Page': {'media': 5}}}), isEmpty);
    });

    test('кольори: #rrggbb і rrggbb, решта — null', () {
      expect(BannerArtwork.parseHexColor('#000000'), 0xFF000000);
      expect(BannerArtwork.parseHexColor('ff8800'), 0xFFFF8800);
      expect(BannerArtwork.parseHexColor('#12345'), isNull);
      expect(BannerArtwork.parseHexColor(null), isNull);
      expect(BannerArtwork.parseHexColor(42), isNull);
    });

    test('load: id діляться на запити по 50, дублі й нулі відкидаються', () async {
      final bodies = <Map<String, dynamic>>[];
      final api = AniListBanners(fetch: (method, url, {body, headers}) async {
        expect(method, 'POST');
        expect(url, AniListBanners.endpoint);
        bodies.add((body as Map).cast<String, dynamic>());
        final ids = ((body['variables'] as Map)['ids'] as List).cast<int>();
        return {
          'data': {
            'Page': {
              'media': [for (final id in ids) {'idMal': id, 'bannerImage': 'https://s4.anilist.co/$id.jpg'}],
            },
          },
        };
      });
      final ids = [...List.generate(120, (i) => i + 1), 5, 5, 0, -3];
      final out = await api.load(ids);
      expect(bodies.length, 3);
      expect([for (final b in bodies) ((b['variables'] as Map)['ids'] as List).length], [50, 50, 20]);
      expect(bodies.first['query'], AniListBanners.query);
      expect(out.length, 120);
      expect(out[77]!.url, 'https://s4.anilist.co/77.jpg');
    });

    test('load: порожній список — жодного запиту', () async {
      var calls = 0;
      final api = AniListBanners(fetch: (method, url, {body, headers}) async {
        calls++;
        return null;
      });
      expect(await api.load(const []), isEmpty);
      expect(calls, 0);
    });
  });

  group('TmdbBackdrops', () {
    test('без ключа нічого не питає', () async {
      var calls = 0;
      final t = TmdbBackdrops(key: () => '  ', fetch: (m, u, {body, headers}) async {
        calls++;
        return null;
      });
      expect(t.enabled, isFalse);
      expect(await t.backdropFor(anime(1)), isNull);
      expect(calls, 0);
    });

    test('stripSeason прибирає позначку сезону з назви', () {
      expect(TmdbBackdrops.stripSeason('Kekkai Sensen 2nd Season'), 'Kekkai Sensen');
      expect(TmdbBackdrops.stripSeason('Spy x Family Season 3'), 'Spy x Family');
      expect(TmdbBackdrops.stripSeason('Attack on Titan: The Final Season'), 'Attack on Titan');
      expect(TmdbBackdrops.stripSeason('Mob Psycho 100 Part 2'), 'Mob Psycho 100');
      expect(TmdbBackdrops.stripSeason('Просто назва'), isNull);
      expect(TmdbBackdrops.stripSeason(null), isNull);
    });

    test('якщо з роком нічого немає — пошук без року (наступний сезон давнього серіалу)', () async {
      final calls = <Uri>[];
      final t = TmdbBackdrops(
        key: () => 'abc',
        fetch: (m, u, {body, headers}) async {
          calls.add(u);
          return u.queryParameters.containsKey('first_air_date_year')
              ? {'results': []}
              : {'results': [{'backdrop_path': '/old.jpg'}]};
        },
      );
      final url = await t.backdropFor(anime(5, year: 2026, titleEn: 'Show 2nd Season'));
      expect(url, 'https://image.tmdb.org/t/p/w1280/old.jpg');
      expect(calls.any((u) => u.queryParameters.containsKey('first_air_date_year')), isTrue);
      expect(calls.last.queryParameters.containsKey('first_air_date_year'), isFalse);
    });

    test('ключ v3 іде параметром; шукає за рідною назвою, тоді за японською; рік і тип у запиті', () async {
      final urls = <Uri>[];
      final t = TmdbBackdrops(
        key: () => 'abc123',
        fetch: (method, url, {body, headers}) async {
          urls.add(url);
          expect(method, 'GET');
          expect(headers, isNull, reason: 'v3-ключ не потребує заголовка');
          // Перший запит нічого не дає, другий — банер
          return urls.length == 1
              ? {'results': [{'backdrop_path': null}]}
              : {'results': [{'backdrop_path': null}, {'backdrop_path': '/wide.jpg'}]};
        },
      );
      final url = await t.backdropFor(anime(7, year: 2023));
      expect(url, 'https://image.tmdb.org/t/p/w1280/wide.jpg');
      expect(urls.length, 2);
      expect(urls[0].path, '/3/search/tv');
      expect(urls[0].queryParameters['api_key'], 'abc123');
      expect(urls[0].queryParameters['query'], 'ネイティブ');
      expect(urls[0].queryParameters['first_air_date_year'], '2023');
      expect(urls[0].queryParameters['include_adult'], 'false');
      expect(urls[1].queryParameters['query'], 'Nihongo');
    });

    test('фільми шукаються як movie з роком випуску; токен v4 іде заголовком', () async {
      Uri? seen;
      Map<String, String>? seenHeaders;
      final t = TmdbBackdrops(
        key: () => 'eyJhbGciOi.token',
        fetch: (method, url, {body, headers}) async {
          seen = url;
          seenHeaders = headers;
          return {'results': [{'backdrop_path': '/m.jpg'}]};
        },
      );
      expect(await t.backdropFor(anime(9, mediaType: 'movie', year: 2016)), 'https://image.tmdb.org/t/p/w1280/m.jpg');
      expect(seen!.path, '/3/search/movie');
      expect(seen!.queryParameters['primary_release_year'], '2016');
      expect(seen!.queryParameters.containsKey('api_key'), isFalse);
      expect(seenHeaders, {'Authorization': 'Bearer eyJhbGciOi.token'});
    });

    test('нічого не знайдено — null; назви без тексту пропускаються', () async {
      var calls = 0;
      final t = TmdbBackdrops(key: () => 'k', fetch: (m, u, {body, headers}) async {
        calls++;
        return {'results': []};
      });
      expect(await t.backdropFor(anime(3)), isNull);
      expect(calls, 6, reason: 'за рік і без року — по три назви (рідна, японська, англійська)');
      calls = 0;
      expect(await t.backdropFor(anime(4, titleJa: null, titleEn: ' ', titleNative: null)), isNull);
      expect(calls, 0);
    });

    test('вибір банера: перший результат із шляхом', () {
      expect(TmdbBackdrops.pickBackdrop({'results': [{'backdrop_path': 'без слеша'}, {'backdrop_path': '/ok.jpg'}]}), '/ok.jpg');
      expect(TmdbBackdrops.pickBackdrop(null), isNull);
      expect(TmdbBackdrops.pickBackdrop({'results': 'x'}), isNull);
    });
  });

  group('BannerArt: кеш і запасний пошук', () {
    late DateTime now;
    late Map<String, dynamic> disk;
    late int anilistCalls;
    late int tmdbCalls;
    late Map<int, String?> anilistBanners; // MAL-id → банер (null — немає)
    late bool anilistDown;
    late String tmdbKey;

    BannerArt make({Map<String, dynamic>? preload}) {
      disk = {...?preload};
      return BannerArt(
        now: () => now,
        load: () => disk,
        save: (d) => disk = {...d},
        anilist: AniListBanners(fetch: (method, url, {body, headers}) async {
          anilistCalls++;
          if (anilistDown) throw Exception('AniList недоступний');
          final ids = (((body as Map)['variables'] as Map)['ids'] as List).cast<int>();
          return {
            'data': {
              'Page': {
                'media': [
                  for (final id in ids)
                    if (anilistBanners.containsKey(id)) {'idMal': id, 'bannerImage': anilistBanners[id], 'coverImage': {'color': '#336699'}},
                ],
              },
            },
          };
        }),
        tmdb: TmdbBackdrops(
          key: () => tmdbKey,
          fetch: (method, url, {body, headers}) async {
            tmdbCalls++;
            return {'results': [{'backdrop_path': '/tmdb.jpg'}]};
          },
        ),
      );
    }

    setUp(() {
      now = DateTime(2026, 11, 3, 12);
      anilistCalls = 0;
      tmdbCalls = 0;
      anilistBanners = {1: 'https://s4.anilist.co/1.jpg', 2: null};
      anilistDown = false;
      tmdbKey = '';
    });

    test('знайдений банер кешується на 14 днів; повторний запит мережі не робить', () async {
      final art = make();
      final first = await art.load([anime(1)]);
      expect(first[1]!.url, 'https://s4.anilist.co/1.jpg');
      expect(first[1]!.color, 0xFF336699);
      expect(anilistCalls, 1);
      await art.load([anime(1)]);
      expect(anilistCalls, 1);
      now = now.add(const Duration(days: 13));
      await art.load([anime(1)]);
      expect(anilistCalls, 1, reason: 'тринадцять днів — ще свіжий');
      now = now.add(const Duration(days: 2));
      await art.load([anime(1)]);
      expect(anilistCalls, 2, reason: 'п’ятнадцять — застарів');
    });

    test('без ключа TMDB «банера немає» не кешується, а знайдений банер підхоплюється', () async {
      final art = make();
      final out = await art.load([anime(2)]);
      expect(out[2]!.hasImage, isFalse);
      await art.load([anime(2)]);
      expect(anilistCalls, 2, reason: 'без ключа TMDB «банера немає» не запам’ятовується: ключ з бекенду може прийти згодом');
      now = now.add(const Duration(days: 3));
      anilistBanners[2] = 'https://s4.anilist.co/2.jpg';
      final later = await art.load([anime(2)]);
      expect(anilistCalls, 3);
      expect(later[2]!.url, 'https://s4.anilist.co/2.jpg', reason: 'банер з’явився — підхопили');
    });

    test('у запит ідуть лише тайтли без свіжого запису; без MAL-id пропускаються', () async {
      final art = make();
      await art.load([anime(1)]);
      final seen = <List<int>>[];
      anilistBanners[3] = 'https://s4.anilist.co/3.jpg';
      final out = await BannerArt(
        now: () => now,
        load: () => disk,
        save: (d) => disk = {...d},
        anilist: AniListBanners(fetch: (m, u, {body, headers}) async {
          final ids = (((body as Map)['variables'] as Map)['ids'] as List).cast<int>();
          seen.add(ids);
          return {'data': {'Page': {'media': [for (final id in ids) {'idMal': id, 'bannerImage': 'https://s4.anilist.co/$id.jpg'}]}}};
        }),
        tmdb: TmdbBackdrops(key: () => '', fetch: (m, u, {body, headers}) async => null),
      ).load([anime(1), anime(3), anime(0, slug: 'без-mal')]);
      expect(seen, [
        [3]
      ]);
      expect(out.keys.toSet(), {1, 3});
    });

    test('TMDB: лише для тайтлів без банера в AniList і лише з ключем', () async {
      final noKey = await make().load([anime(1), anime(2)]);
      expect(tmdbCalls, 0);
      expect(noKey[2]!.hasImage, isFalse);

      tmdbKey = 'key';
      now = now.add(const Duration(days: 3)); // негативний запис з минулого кроку застарів
      final art = make(preload: disk);
      final withKey = await art.load([anime(1), anime(2)]);
      expect(tmdbCalls, 2, reason: 'записи, зроблені без TMDB, перевіряються знову, щойно з’явився ключ');
      expect(withKey[1]!.url, 'https://image.tmdb.org/t/p/w1280/tmdb.jpg', reason: 'TMDB — основне джерело');
      expect(withKey[2]!.url, 'https://image.tmdb.org/t/p/w1280/tmdb.jpg');
      expect(withKey[2]!.color, 0xFF336699, reason: 'колір обкладинки лишається з AniList');
      // Результат TMDB теж кешується
      await art.load([anime(2)]);
      expect(tmdbCalls, 2);
    });

    BannerArt build(Object? Function(Uri) tmdb, {String? anilistBanner}) => BannerArt(
          now: () => now,
          load: () => {},
          save: (_) {},
          anilist: AniListBanners(fetch: (m, u, {body, headers}) async => {
                'data': {'Page': {'media': [{'idMal': 2, 'bannerImage': anilistBanner, 'coverImage': {'color': '#336699'}}]}}
              }),
          tmdb: TmdbBackdrops(key: () => 'key', fetch: (m, u, {body, headers}) async => tmdb(u)),
        );

    test('бекенд банерів — перше джерело: його відповіді вистачає, TMDB і AniList не питаються', () async {
      var direct = 0;
      final art = BannerArt(
        now: () => now,
        load: () => {},
        save: (_) {},
        backend: (items) async => {
          for (final i in items) i['mal'] as int: ('https://image.tmdb.org/t/p/w1280/${i['mal']}.jpg', 0xFF112233),
        },
        anilist: AniListBanners(fetch: (m, u, {body, headers}) async {
          direct++;
          return {'data': {'Page': {'media': []}}};
        }),
        tmdb: TmdbBackdrops(key: () => 'key', fetch: (m, u, {body, headers}) async {
          direct++;
          return {'results': []};
        }),
      );
      final out = await art.load([anime(2), anime(3)]);
      expect(out[2]!.url, 'https://image.tmdb.org/t/p/w1280/2.jpg');
      expect(out[3]!.color, 0xFF112233);
      expect(direct, 0);
    });

    test('бекенд банерів недоступний — працює прямий пошук', () async {
      final art = BannerArt(
        now: () => now,
        load: () => {},
        save: (_) {},
        backend: (items) async => null,
        anilist: AniListBanners(fetch: (m, u, {body, headers}) async => {
              'data': {'Page': {'media': [{'idMal': 2, 'bannerImage': 'https://s4.anilist.co/2.jpg', 'coverImage': {'color': '#336699'}}]}}
            }),
        tmdb: TmdbBackdrops(key: () => '', fetch: (m, u, {body, headers}) async => null),
      );
      final out = await art.load([anime(2)]);
      expect(out[2]!.url, 'https://s4.anilist.co/2.jpg');
    });

    test('TMDB — основне джерело: його банер важливіший за банер AniList', () async {
      final art = build((u) => {'results': [{'backdrop_path': '/tmdb.jpg'}]}, anilistBanner: 'https://s4.anilist.co/2.jpg');
      final out = await art.load([anime(2)]);
      expect(out[2]!.url, 'https://image.tmdb.org/t/p/w1280/tmdb.jpg');
    });

    test('TMDB нічого не дав або видав помилку — береться банер AniList, а помилка потрапляє в журнал', () async {
      final prev = AppLog.instance;
      AppLog.instance = AppLog();
      addTearDown(() => AppLog.instance = prev);
      final empty = await build((u) => {'results': []}, anilistBanner: 'https://s4.anilist.co/2.jpg').load([anime(2)]);
      expect(empty[2]!.url, 'https://s4.anilist.co/2.jpg');
      final broken = await build((u) => throw Exception('HTTP 401'), anilistBanner: 'https://s4.anilist.co/2.jpg').load([anime(2)]);
      expect(broken[2]!.url, 'https://s4.anilist.co/2.jpg');
      final warnings = [for (final e in AppLog.instance.entries) if (e.tag == 'banners') e.message];
      expect(warnings.any((w) => w.contains('TMDB помилка') && w.contains('HTTP 401')), isTrue, reason: 'помилку видно в журналі: $warnings');
    });

    test('збій TMDB не псує відповідь AniList', () async {
      tmdbKey = 'key';
      final art = BannerArt(
        now: () => now,
        load: () => {},
        save: (_) {},
        anilist: AniListBanners(fetch: (m, u, {body, headers}) async => {
              'data': {'Page': {'media': [{'idMal': 2, 'bannerImage': null}]}}
            }),
        tmdb: TmdbBackdrops(key: () => 'key', fetch: (m, u, {body, headers}) async => throw Exception('TMDB лежить')),
      );
      final out = await art.load([anime(2)]);
      expect(out[2]!.hasImage, isFalse);
    });

    test('AniList недоступний: виняток не кидається, повертаються лише застарілі записи й нічого не пишеться', () async {
      final art = make();
      await art.load([anime(1)]);
      final savedBefore = Map<String, dynamic>.of(disk);
      now = now.add(const Duration(days: 20));
      anilistDown = true;
      final out = await art.load([anime(1), anime(2)]);
      expect(out[1]!.url, 'https://s4.anilist.co/1.jpg', reason: 'застарілий банер краще за порожнє місце');
      expect(out.containsKey(2), isFalse);
      expect(disk, savedBefore, reason: 'збій не затирає кеш');
      anilistDown = false;
      final recovered = await art.load([anime(1), anime(2)]);
      expect(recovered.keys.toSet(), {1, 2});
    });

    test('кеш переживає перезапуск: новий екземпляр читає збережене', () async {
      await make().load([anime(1)]);
      final saved = Map<String, dynamic>.of(disk);
      final fresh = make(preload: saved);
      final out = await fresh.load([anime(1)]);
      expect(out[1]!.url, 'https://s4.anilist.co/1.jpg');
      expect(anilistCalls, 1, reason: 'другий екземпляр мережі не чіпав');
    });

    test('розмір кешу обмежений: найстаріші записи відкидаються', () async {
      final preload = {
        for (var i = 1000; i < 1450; i++) '$i': {'u': 'https://x/$i.jpg', 't': now.subtract(Duration(minutes: 1450 - i)).millisecondsSinceEpoch},
      };
      anilistBanners = {1: 'https://s4.anilist.co/1.jpg'};
      final art = make(preload: preload);
      await art.load([anime(1)]);
      expect(disk.length, lessThanOrEqualTo(400));
      expect(disk.containsKey('1'), isTrue, reason: 'свіжий запис лишається');
      expect(disk.containsKey('1000'), isFalse, reason: 'найстаріший пішов');
    });
  });
}
