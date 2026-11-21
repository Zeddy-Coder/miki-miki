// The titles of the episode list: MyAnimeList's episodes through Tenrai (real answers in test/data/guide: Re:Zero 4,
// Frieren, Gintama's second page), TheMovieDB's Ukrainian titles and stills matched by air date (answers shaped like
// TheMovieDB's: it cannot be reached without a key here, and the Ukrainian titles in them are made up), MoonAnime's
// episode guide as our backend gives it (made from MoonAnime's real answers for Re:Zero 4 and Frieren by the rules of
// tools/backend/guide.ts), Anime Skip's names (its real answers for the two shows of Vinland Saga 2), the sites' own
// titles, the queue's MyAnimeList numbers. No network.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:miki_miki/models/hikka_models.dart';
import 'package:miki_miki/services/episode_check.dart';
import 'package:miki_miki/services/episode_guide.dart';
import 'package:miki_miki/services/skips/anime_skip.dart';
import 'package:miki_miki/services/sources/episode_naming.dart';

import 'support/remote_fakes.dart';

String text(String name) => File('test/data/$name').readAsStringSync();
Object? fixture(String name) => jsonDecode(text(name));

final HikkaAnime rezero = HikkaAnime.fromJson(const {
  'slug': 're-zero-4',
  'title_ja': 'Re:Zero kara Hajimeru Isekai Seikatsu 4th Season',
  'title_en': 'Re:ZERO -Starting Life in Another World- Season 4',
  'title_native': 'Re:ゼロから始める異世界生活 4th season',
  'media_type': 'tv',
  'mal_id': 61316,
  'year': 2026,
});

/// Tenrai and TheMovieDB as the fixtures have them
class FakeWeb {
  final List<Uri> asked = [];
  final List<Map<String, String>?> headers = [];
  bool tenraiDown = false;
  bool tmdbDown = false;
  String search = 'guide/tmdb_search_rezero.json';

  Iterable<Uri> to(String host) => asked.where((u) => u.host == host);

  Future<(int, String)> get(Uri u, {Map<String, String>? headers}) async {
    asked.add(u);
    this.headers.add(headers);
    if (u.host == 'api.tenrai.org') {
      if (tenraiDown) throw const SocketException('offline');
      return switch (u.path) {
        '/v1/anime/61316/episodes' => (200, text('guide/tenrai_rezero4.json')),
        '/v1/anime/52991/episodes' => (200, text('guide/tenrai_frieren.json')),
        '/v1/anime/918/episodes' when u.queryParameters['page'] == '2' => (200, text('guide/tenrai_gintama_p2.json')),
        _ => (404, '{"status":404}'),
      };
    }
    if (u.host == 'api.themoviedb.org') {
      if (tmdbDown) throw const SocketException('offline');
      return switch (u.path) {
        '/3/search/tv' => (200, text(search)),
        '/3/tv/65942' => (200, text('guide/tmdb_tv_rezero.json')),
        '/3/tv/65942/season/4' => (200, text('guide/tmdb_season_rezero4.json')),
        _ => (404, '{"success":false}'),
      };
    }
    throw StateError('unexpected $u');
  }
}

EpisodeGuideService guideOf(
  FakeWeb web, {
  String key = 'v3key',
  String? cache,
  Future<Map<int, String>?> Function(int)? names,
  Future<Map<String, dynamic>?> Function(int)? moon,
}) =>
    EpisodeGuideService(
      get: web.get,
      cachePath: cache,
      persist: cache != null,
      malId: (k) async => switch (k) {
        'hikka:re-zero-4' => 61316,
        'hikka:gintama' => 918,
        'hikka:frieren' => 52991,
        _ => null,
      },
      anime: (k) async => rezero,
      tmdbKey: () => key,
      animeSkipNames: names ?? (_) async => null,
      moon: moon ?? (_) async => null,
      hosting: 'https://hosting.test',
      now: () => DateTime(2026, 11, 20),
    );

/// MoonAnime's guide as the backend gives it, for the title asked
Future<Map<String, dynamic>?> moonOf(int mal) async => switch (mal) {
      61316 => fixture('guide/moon_guide_rezero4.json') as Map<String, dynamic>,
      52991 => fixture('guide/moon_guide_frieren.json') as Map<String, dynamic>,
      _ => {'mal': mal, 'eps': <String, dynamic>{}},
    };

DateTime day(int y, int m, int d) => DateTime.utc(y, m, d);

void main() {
  group('відповіді', () {
    test('Tenrai: назви MyAnimeList, дати, позначки; заглушки — не назви', () {
      final (eps, more) = malEpisodesOf(fixture('guide/tenrai_rezero4.json'));
      expect(eps, hasLength(19));
      expect(more, isFalse);
      final e14 = eps.firstWhere((e) => e.number == 14);
      expect((e14.title, e14.aired, e14.filler, e14.recap), ('Five Obstacles', day(2026, 8, 26), false, false));
      expect(e14.japanese, isNotNull);
      // Frieren: four episodes on the first day
      final (frieren, _) = malEpisodesOf(fixture('guide/tenrai_frieren.json'));
      expect([for (final e in frieren.take(5)) e.aired], [day(2023, 9, 29), day(2023, 9, 29), day(2023, 9, 29), day(2023, 9, 29), day(2023, 10, 6)]);
      // Gintama: the second page, 101–200, and more after it
      final (gintama, next) = malEpisodesOf(fixture('guide/tenrai_gintama_p2.json'));
      expect((gintama.first.number, gintama.last.number, next), (101, 200, true));
      final (standIn, _) = malEpisodesOf({
        'data': [
          {'mal_id': 3, 'title': 'Episode 3', 'aired': null},
        ],
      });
      expect(standIn.single.title, isNull);
    });

    test('TheMovieDB: лише українські назви — без заглушок, інших мов і російських', () {
      for (final yes in ['П’ять перешкод', 'Рам', 'Re:Zero. Життя з нуля в іншому світі', 'Шаула / Герой']) {
        expect(isUkrainianTitle(yes), isTrue, reason: yes);
      }
      for (final no in ['Епізод 17', 'Серія 5', 'Episode 5', 'Five Obstacles', 'Пятый эпизод', 'Ещё один', '', null]) {
        expect(isUkrainianTitle(no), isFalse, reason: '$no');
      }
      final eps = tmdbEpisodesOf(fixture('guide/tmdb_season_rezero4.json'));
      final e14 = eps.firstWhere((e) => e.number == 14);
      expect((e14.season, e14.uk, e14.still, e14.aired, e14.runtime), (4, 'П’ять перешкод', '/rz4e14.jpg', day(2026, 8, 26), 24));
      expect(eps.firstWhere((e) => e.number == 17).uk, isNull, reason: '«Епізод 17» — заглушка');
      expect(eps.firstWhere((e) => e.number == 19).still, isNull);
    });

    test('шоу й сезони: японське шоу з пошуку; сезони, що покривають дати; без спецвипусків', () {
      expect(tmdbShowsOf(fixture('guide/tmdb_search_rezero.json')), [65942]);
      expect(
        tmdbShowsOf({
          'results': [
            {'id': 1, 'original_language': 'en', 'genre_ids': [18]},
            {'id': 2, 'original_language': 'en', 'genre_ids': [16]},
          ],
        }),
        [2],
        reason: 'японського нема — анімаційне',
      );
      final seasons = tmdbSeasonsOf(fixture('guide/tmdb_tv_rezero.json'));
      expect(seasons.map((s) => s.$1), [1, 2, 3, 4]);
      expect(seasonsBetween(seasons, day(2026, 6, 10), day(2026, 9, 30)), [4]);
      expect(seasonsBetween(seasons, day(2024, 12, 20), day(2026, 4, 20)), [3, 4]);
      expect(seasonsBetween(seasons, day(2015, 1, 1), day(2015, 3, 1)), isEmpty);
    });

    test('зіставлення за датою: кілька серій за день — по черзі, день різниці — те саме, зайва з одного боку — без пари', () {
      final mal = [
        for (final n in [1, 2, 3, 4]) MalEpisode(n, aired: day(2023, 9, 29)),
        MalEpisode(5, aired: day(2023, 10, 6)),
        MalEpisode(6, aired: day(2023, 10, 13), recap: true),
        MalEpisode(7, aired: day(2023, 10, 20)),
        const MalEpisode(8),
      ];
      final tmdb = [
        for (final n in [4, 3, 2, 1]) TmdbEpisode(1, n, aired: day(2023, 9, 29)),
        TmdbEpisode(1, 5, aired: day(2023, 10, 7)),
        TmdbEpisode(1, 6, aired: day(2023, 10, 20)),
        const TmdbEpisode(1, 7),
      ];
      final m = matchByDate(mal, tmdb);
      expect({for (final e in m.entries) e.key: e.value.number}, {1: 1, 2: 2, 3: 3, 4: 4, 5: 5, 7: 6});
    });
  });

  group('сервіс', () {
    test('«Переродження» 4, 10–19: українські з TheMovieDB, англійські де їх нема, кадри, дати; запамʼятовується', () async {
      final web = FakeWeb();
      final dir = Directory.systemTemp.createTempSync('guide');
      addTearDown(() => dir.deleteSync(recursive: true));
      final first = guideOf(web, cache: '${dir.path}/g.json');
      final g = (await first.load('hikka:re-zero-4', 10, 19))!;
      expect(g.malId, 61316);
      final e14 = g[14]!;
      expect((e14.uk, e14.en, e14.aired, e14.runtime), ('П’ять перешкод', 'Five Obstacles', day(2026, 8, 26), 24));
      expect(e14.stillUrl, 'https://image.tmdb.org/t/p/w300/rz4e14.jpg');
      expect((g[17]!.uk, g[17]!.en), (null, 'Good Loser'), reason: 'у TheMovieDB лише «Епізод 17»');
      expect(g[19]!.still, isNull);
      expect(g[9], isNull, reason: 'поза межами');
      expect(web.to('api.tenrai.org'), hasLength(1));
      expect(web.to('api.themoviedb.org').map((u) => u.path), ['/3/search/tv', '/3/tv/65942', '/3/tv/65942/season/4']);
      // The v3 key goes as a parameter, the season in Ukrainian
      final season = web.asked.last;
      expect((season.queryParameters['api_key'], season.queryParameters['language'], web.headers.last), ('v3key', 'uk-UA', null));

      // Remembered: offline, a new run has the same
      await first.save();
      final offline = FakeWeb()
        ..tenraiDown = true
        ..tmdbDown = true;
      final service = guideOf(offline, cache: '${dir.path}/g.json');
      final again = (await service.load('hikka:re-zero-4', 10, 19))!;
      expect((again[14]!.uk, again[14]!.still, again[17]!.en), ('П’ять перешкод', 'https://image.tmdb.org/t/p/w300/rz4e14.jpg', 'Good Loser'));
      expect(offline.asked, isEmpty);
      expect(service.peek('hikka:re-zero-4', 10, 19), same(again));
    });

    test('MoonAnime: українські назви й кадри там, де TheMovieDB їх не має; тривалість до секунди', () async {
      final web = FakeWeb();
      final asked = <int>[];
      final g = (await guideOf(web, moon: (mal) {
        asked.add(mal);
        return moonOf(mal);
      }).load('hikka:re-zero-4', 1, 19))!;
      expect(asked, [61316]);
      // TheMovieDB has only «Епізод 2» for the second: MoonAnime's title
      expect((g[2]!.uk, g[2]!.en), ('Подолати піщаний час', 'Overcome Sand Time'));
      // Both have the 14th: TheMovieDB's title and still come first
      expect((g[14]!.uk, g[14]!.still), ('П’ять перешкод', 'https://image.tmdb.org/t/p/w300/rz4e14.jpg'));
      // TheMovieDB has no still of the 19th: MoonAnime's, made small by our backend
      expect(g[19]!.still, startsWith('https://hosting.test/api/guideThumb?u=https%3A%2F%2Fs2.mooncdn.wtf%2F'));
      // «Серія 17» is a stand-in at MoonAnime too: MyAnimeList's English
      expect((g[17]!.uk, g[17]!.en), (null, 'Good Loser'));
      expect((g[2]!.seconds, g[14]!.seconds), (1420, null), reason: 'не для кожної серії MoonAnime знає довжину');
    });

    test('MoonAnime без TheMovieDB: «Фрірен» українською, з описами й кадрами', () async {
      final g = (await guideOf(FakeWeb(), key: '', moon: moonOf).load('hikka:frieren', 1, 28))!;
      expect(g[1]!.uk, 'Кінець пригод');
      expect(g[1]!.en, "The Journey's End");
      expect(g[1]!.about, startsWith('Перемігши Короля Демонів'));
      // MoonAnime has «Серія 6» … «Серія 12» and «Серія 17»: those are MyAnimeList's English
      expect([for (var n = 1; n <= 28; n++) g[n]!.uk].whereType<String>(), hasLength(20));
      expect((g[6]!.uk, g[6]!.en), (null, 'The Hero of the Village'));
      expect([for (var n = 1; n <= 28; n++) g[n]!.still].every((u) => u!.startsWith('https://hosting.test/api/guideThumb?')), isTrue);
    });

    test('бекенд без MoonAnime — те саме, що й без нього', () async {
      final g = (await guideOf(FakeWeb(), moon: (_) async => null).load('hikka:re-zero-4', 1, 19))!;
      expect((g[2]!.uk, g[19]!.still), (null, null));
    });

    test('відповідь бекенду: заглушки й не-кирилиця — не назви, кадр — лише наш шлях, позначки', () {
      final m = moonEpisodesOf({
        'eps': {
          '1': {'t': 'Кінець пригод', 'd': 1559, 'a': 'Опис', 'i': '/api/guideThumb?u=x&s=y', 'f': 1},
          '2': {'t': 'Серія 2', 'i': 'https://elsewhere.test/a.webp'},
          '3': {'t': 'Overcome Sand Time', 'r': 1},
          'x': {'t': 'Не номер'},
        },
      });
      expect(m.keys, [1, 2, 3]);
      expect((m[1]!.uk, m[1]!.seconds, m[1]!.about, m[1]!.still, m[1]!.filler), ('Кінець пригод', 1559, 'Опис', '/api/guideThumb?u=x&s=y', true));
      expect((m[2]!.uk, m[2]!.still), (null, null));
      expect((m[3]!.uk, m[3]!.recap), (null, true));
    });

    test('ключ v4 («read access token») — заголовком, не параметром', () async {
      final web = FakeWeb();
      await guideOf(web, key: 'eyJabc').load('hikka:re-zero-4', 10, 19);
      final i = web.asked.lastIndexWhere((u) => u.host == 'api.themoviedb.org');
      expect(web.asked[i].queryParameters.containsKey('api_key'), isFalse);
      expect(web.headers[i], {'Authorization': 'Bearer eyJabc'});
    });

    test('без ключа TMDB — англійські назви, TheMovieDB не питаємо', () async {
      final web = FakeWeb();
      final g = (await guideOf(web, key: '').load('hikka:re-zero-4', 10, 19))!;
      expect((g[14]!.uk, g[14]!.en, g[14]!.still), (null, 'Five Obstacles', null));
      expect(web.to('api.themoviedb.org'), isEmpty);
    });

    test('Tenrai недоступний — назви з Anime Skip', () async {
      final web = FakeWeb()..tenraiDown = true;
      final asked = <int>[];
      final g = (await guideOf(web, names: (mal) async {
        asked.add(mal);
        return {14: 'Five Obstacles'};
      }).load('hikka:re-zero-4', 10, 19))!;
      expect(asked, [61316]);
      expect(g[14]!.en, 'Five Obstacles');
      expect(g[15], isNull);
    });

    test('довгий серіал: сторінка Tenrai діапазону (Ґінтама, 101–200 — друга)', () async {
      final web = FakeWeb();
      final g = (await guideOf(web, key: '').load('hikka:gintama', 101, 200))!;
      expect(web.to('api.tenrai.org').single.queryParameters['page'], '2');
      expect(g[101]!.en, 'Rules Are Made To Be Broken');
      expect(g.episodes, hasLength(100));
    });

    test('тайтл без MyAnimeList id — нічого й нікого не питаємо', () async {
      final web = FakeWeb();
      expect(await guideOf(web).load('local:file', 1, 12), isNull);
      expect(web.asked, isEmpty);
    });

    test('шоу TheMovieDB не знайдено — це запамʼятовується, пошук не повторюється', () async {
      final web = FakeWeb()..search = 'guide/tmdb_tv_rezero.json'; // (no «results»: nothing found)
      final service = guideOf(web);
      final g = (await service.load('hikka:re-zero-4', 10, 19))!;
      expect(g[14]!.uk, isNull);
      final searches = web.to('api.themoviedb.org').length;
      expect(searches, greaterThan(0));
      await service.load('hikka:re-zero-4', 1, 9);
      expect(web.to('api.themoviedb.org'), hasLength(searches));
    });
  });

  group('Anime Skip', () {
    test('назви серій: перша дана для кожного номера, без заглушок «Episode 3»', () {
      final names = animeSkipNames(fixture('skips/animeskip_vinland2_names.json'));
      expect(names[1], 'Slave');
      expect(names[3], 'Snake', reason: 'у першого шоу — «Episode 3»');
      expect(names[11], 'Kings and Swords');
      expect(names.values.where((n) => n.startsWith('Episode')), isEmpty);
    });

    test('назви приходять із таймкодами й запамʼятовуються разом', () async {
      final bodies = <String>[];
      Future<(int, String)> post(Uri u, String body, Map<String, String> headers) async {
        bodies.add(body);
        if (u.host == 'graphql.anilist.co') return (200, '{"data":{"Media":{"id":136430}}}');
        return (200, text('skips/animeskip_vinland2_names.json'));
      }

      final a = AnimeSkip(post: post, persist: false);
      expect((await a.names(49387))![4], 'Awakening');
      expect(bodies.last, contains('number name baseDuration'));
      expect(await a.times(49387, 11), isNotEmpty);
      expect(bodies, hasLength(2), reason: 'одне шоу на назви й таймкоди');
    });
  });

  test('назва серії з сайту: після номера, українська, не позначка OVA', () {
    expect(siteEpisodeTitle('Серія 13 - Нацу проти Юкі'), 'Нацу проти Юкі');
    expect(siteEpisodeTitle('Серія 1 - Хвіст Феї (Макао)'), 'Хвіст Феї (Макао)');
    expect(siteEpisodeTitle('5 серія. Битва'), 'Битва');
    for (final no in ['Серія 5', '11', 'Сезон 1 · Серія 1', 'Серія 13 (OVA)', 'Серія 12. Special Training', 'Серія 3 - Спешл', 'Серія 2 —  ']) {
      expect(siteEpisodeTitle(no), isNull, reason: no);
    }
  });

  group('номери MyAnimeList у черзі', () {
    test('озвучка з середини сезону: її номери (10–19), коли інша озвучка сайту йде з 1', () async {
      final rig = Rig(episodes: [for (var n = 10; n <= 19; n++) n], others: [for (var n = 1; n <= 19; n++) n]);
      await rig.driver.start(rig.launch(hikka: const HikkaEpisodeInfo(released: 19, total: 19, finished: true)));
      expect(rig.driver.malNumbers, [for (var n = 10; n <= 19; n++) n]);
      expect(identical(rig.driver.malNumbers, rig.driver.malNumbers), isTrue, reason: 'не перераховується');
      rig.driver.stop();
    });

    test('злиті частини (24 з 12) — жодного номера', () async {
      final rig = Rig(episodes: [for (var n = 1; n <= 24; n++) n]);
      await rig.driver.start(rig.launch(hikka: const HikkaEpisodeInfo(released: 12, total: 12, finished: true)));
      expect(rig.driver.malNumbers.whereType<int>(), isEmpty);
      rig.driver.stop();
    });
  });
}

