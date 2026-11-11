import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:miki_miki/models/hikka_models.dart';
import 'package:miki_miki/services/hikka_api.dart';
import 'package:miki_miki/services/hikka_images.dart';
import 'package:miki_miki/services/hikka_nav.dart';
import 'package:miki_miki/services/hikka_pager.dart';
import 'package:miki_miki/services/hikka_prefs.dart';

import 'support/hikka_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ── Підписи й дати ─────────────────────────────────────────────────────────

  group('HikkaText', () {
    test('сезони: поточний за правилом сайту й наступний', () {
      // 1 листопада 00:00 ще належить до літа... ні: день, що минув, — 31 жовтня, тобто осінь
      expect(HikkaText.currentSeason(DateTime(2026, 11, 3, 12)), ('fall', 2026));
      // Перший день сезону ще належить попередньому
      expect(HikkaText.currentSeason(DateTime(2026, 10, 1, 8)), ('summer', 2026));
      expect(HikkaText.currentSeason(DateTime(2026, 1, 1, 8)), ('fall', 2025));
      expect(HikkaText.nextSeason('fall', 2026), ('winter', 2027));
      expect(HikkaText.nextSeason('winter', 2026), ('spring', 2026));
      expect(HikkaText.nextSeason('summer', 2026), ('fall', 2026));
    });

    test('число з нерозривними пропусками', () {
      expect(HikkaText.count(0), '0');
      expect(HikkaText.count(999), '999');
      expect(HikkaText.count(1000), '1 000');
      expect(HikkaText.count(657496), '657 496');
      expect(HikkaText.count(-12345), '-12 345');
    });

    test('множина: тайтл / тайтли / тайтлів', () {
      String p(int n) => HikkaText.plural(n, 'тайтл', 'тайтли', 'тайтлів');
      expect([for (final n in [1, 2, 4, 5, 11, 12, 14, 21, 22, 25, 101, 111, 0]) p(n)], [
        'тайтл', 'тайтли', 'тайтли', 'тайтлів', 'тайтлів', 'тайтлів', 'тайтлів', //
        'тайтл', 'тайтли', 'тайтлів', 'тайтл', 'тайтлів', 'тайтлів',
      ]);
    });

    test('день і час виходу серії', () {
      final now = DateTime(2026, 11, 3, 10);
      expect(HikkaText.hhmm(DateTime(2026, 11, 3, 8, 5)), '08:05');
      expect(HikkaText.dayName(DateTime(2026, 11, 3, 23), now), 'Сьогодні');
      expect(HikkaText.dayName(DateTime(2026, 11, 4, 1), now), 'Завтра');
      expect(HikkaText.dayName(DateTime(2026, 11, 2, 1), now), 'Вчора');
      expect(HikkaText.dayName(DateTime(2026, 11, 6, 1), now), 'Пʼятниця');
      expect(HikkaText.dayName(DateTime(2026, 11, 20, 1), now), '20 листопада');
      expect(HikkaText.dayName(DateTime(2027, 1, 5, 1), now), '5 січня 2027');
      expect(HikkaText.airingLabel(DateTime(2026, 11, 3, 18, 30), now), 'Сьогодні, 18:30');
      expect(HikkaText.dayHeader(DateTime(2026, 11, 3, 18), now), 'Сьогодні · 3 листопада');
      expect(HikkaText.dayHeader(DateTime(2026, 11, 20, 18), now), '20 листопада');
    });

    test('значення API мають українські підписи', () {
      expect(HikkaText.mediaType('tv'), 'TV Серіал');
      expect(HikkaText.status('ongoing'), 'Онґоїнґ');
      expect(HikkaText.season('fall'), 'Осінь');
      expect(HikkaText.rating('pg_13'), 'PG-13');
      expect(HikkaText.source('light_novel'), 'Ранобе');
      expect(HikkaText.mediaType('unknown'), 'UNKNOWN');
      expect(HikkaText.mediaType(null), '');
    });
  });

  // ── Моделі ─────────────────────────────────────────────────────────────────

  group('Моделі', () {
    test('повна сторінка аніме з реальної відповіді', () {
      final a = HikkaAnime.fromJson(sampleMap('info.json'));
      expect(a.slug, 'sousou-no-frieren-ad4e3e');
      expect(a.title(HikkaTitleLang.ua), 'Проводжальниця Фрірен');
      expect(a.title(HikkaTitleLang.en), "Frieren: Beyond Journey's End");
      expect(a.title(HikkaTitleLang.ja), 'Sousou no Frieren');
      expect(a.otherTitles(HikkaTitleLang.ua), ["Frieren: Beyond Journey's End", 'Sousou no Frieren', '葬送のフリーレン']);
      // Одна другорядна назва: вибраною мовою, без повтору основної
      expect(a.secondaryTitle(HikkaTitleLang.ua, HikkaTitleLang.en), "Frieren: Beyond Journey's End");
      expect(a.secondaryTitle(HikkaTitleLang.ua, HikkaTitleLang.ja), 'Sousou no Frieren');
      expect(a.secondaryTitle(HikkaTitleLang.ua, HikkaTitleLang.ua), isNull);
      expect(a.secondaryTitle(HikkaTitleLang.en, HikkaTitleLang.en), isNull);
      expect(a.typeLabel, 'TV Серіал');
      expect(a.statusLabel, 'Завершено');
      expect(a.seasonLabel, 'Осінь 2023');
      expect(a.episodesLabel, '28 еп.');
      expect(a.durationLabel, '24 хв.');
      expect(a.hasScore, isTrue);
      expect(a.score, 9.3);
      expect(a.hasFranchise, isTrue);
      expect(a.isAdult, isFalse);
      expect(a.genres, isNotEmpty);
      expect(a.studios, isNotEmpty);
      expect(a.synopsis, isNotNull);
      expect(a.external, isNotEmpty);
      expect(a.videos, isNotEmpty);
      expect(a.ost, isNotEmpty);
      expect(a.stats, isNotNull);
      expect(a.stats!.inLists, greaterThan(0));
    });

    test('те, що виходить зараз: розклад і наступна серія', () {
      final a = HikkaAnime.fromJson(sampleMap('info_ongoing.json'));
      expect(a.isOngoing, isTrue);
      expect(a.schedule, isNotEmpty);
      expect(a.episodesLabel, matches(RegExp(r'^\d+ / \d+ еп\.$')));
      final first = a.schedule.map((s) => s.airingAt).reduce((x, y) => x < y ? x : y);
      final before = DateTime.fromMillisecondsSinceEpoch((first - 1000) * 1000);
      expect(a.nextEpisode(before)!.airingAt, first);
      final after = DateTime.fromMillisecondsSinceEpoch((a.schedule.map((s) => s.airingAt).reduce((x, y) => x > y ? x : y) + 10) * 1000);
      expect(a.nextEpisode(after), isNull);
    });

    test('елемент списку: поля сторінки порожні, але нічого не падає', () {
      final a = HikkaAnime.fromJson(FakeHikka().animeList.first);
      expect(a.slug, isNotEmpty);
      expect(a.duration, isNull);
      expect(a.schedule, isEmpty);
      expect(a.stats, isNull);
      expect(a.title(HikkaTitleLang.ua), isNotEmpty);
    });

    test('порожній JSON не ламає розбір', () {
      final a = HikkaAnime.fromJson(const {});
      expect(a.slug, '');
      expect(a.title(HikkaTitleLang.ua), '');
      expect(a.episodesLabel, '');
      expect(a.hasScore, isFalse);
      final c = HikkaCharacter.fromJson(const {});
      expect(c.name, '');
      expect(HikkaPage.parse(null, HikkaAnime.fromJson).items, isEmpty);
    });

    test('назва: запасний порядок мов', () {
      const only = HikkaAnime(slug: 's', titleJa: 'Romaji');
      expect(only.title(HikkaTitleLang.ua), 'Romaji');
      expect(only.title(HikkaTitleLang.en), 'Romaji');
      const noNames = HikkaAnime(slug: 'only-slug');
      expect(noNames.title(HikkaTitleLang.ja), 'only-slug');
    });

    test('18+: хентай або позначка nsfw', () {
      expect(const HikkaAnime(slug: 'a', rating: 'rx').isAdult, isTrue);
      expect(const HikkaAnime(slug: 'a', nsfw: true).isAdult, isTrue);
      expect(const HikkaAnime(slug: 'a', rating: 'r_plus').isAdult, isFalse);
    });

    test('персонаж, ролі, озвучення', () {
      final c = HikkaCharacter.fromJson(sampleMap('char_info.json'));
      expect(c.slug, 'frieren-7f706c');
      expect(c.name, 'Фрірен');
      expect(c.otherNames, contains('Frieren'));
      expect(c.descriptionUa, isNotNull);
      final roles = HikkaPage.parse(sample('frieren_chars.json'), HikkaCharacterRole.fromJson);
      expect(roles.items.length, 20);
      expect(roles.items.any((r) => r.main), isTrue);
      final voices = HikkaPage.parse(sample('char_voices.json'), HikkaCharacterVoice.fromJson);
      expect(voices.items, isNotEmpty);
      expect(voices.items.first.languageLabel, isNot(''));
      final staff = HikkaPage.parse(sample('staff.json'), HikkaStaff.fromJson);
      expect(staff.items.first.person.name, isNotEmpty);
      expect(staff.items.first.rolesLabel, isNotEmpty);
    });

    test('озвучення: коди мов з API мають українські назви, порядок — японська, українська, англійська', () {
      final voices = HikkaPage.parse(sample('char_voices.json'), HikkaCharacterVoice.fromJson);
      expect({for (final v in voices.items) v.languageLabel}, {'Англійська', 'Японська'});
      final groups = HikkaCharacterVoice.groupByLanguage(voices.items);
      expect([for (final g in groups) g.$1], ['Японська', 'Англійська']);
      // Танедзакі Ацумі озвучила у двох аніме, але названа один раз
      expect(groups.first.$2, ['Танедзакі Ацумі']);

      HikkaCharacterVoice v(String lang, String name) => HikkaCharacterVoice(
            anime: const HikkaAnime(slug: 'a'),
            person: HikkaPerson(slug: name, nameUa: name),
            language: lang,
          );
      final mixed = HikkaCharacterVoice.groupByLanguage([
        v('de', 'Ганс'),
        v('English', 'Еймі'),
        v('ukrainian', 'Оксана'),
        v('ko', 'Мін'),
        v('ja', 'Юко'),
        v('xx', 'Невідомий'),
        v('', 'Без мови'),
      ]);
      // Повні назви зводяться до кодів; решта — за українською абеткою, невідомі коди й «без мови» — наприкінці
      expect([for (final g in mixed) g.$1], ['Японська', 'Українська', 'Англійська', 'Корейська', 'Німецька', 'XX', 'Інша мова']);
      expect(mixed[2].$2, ['Еймі']);
      // «І» стоїть за «Б» в абетці, хоч у Unicode — перед нею
      final alpha = HikkaCharacterVoice.groupByLanguage([v('it', 'А'), v('br', 'Б'), v('fr', 'В')]);
      expect([for (final g in alpha) g.$1], ['Бразильська', 'Італійська', 'Французька']);
    });

    test('календар: серія, час, аніме', () {
      final page = HikkaPage.parse(sample('sched_default.json'), HikkaScheduleEntry.fromJson);
      expect(page.items.length, 100);
      expect(page.hasMore, isTrue);
      final e = page.items.first;
      expect(e.anime.slug, isNotEmpty);
      expect(e.episode, greaterThan(0));
      expect(e.time.millisecondsSinceEpoch, e.airingAt * 1000);
    });

    test('франшиза: лише аніме та зв’язки між ними', () {
      final data = HikkaFranchiseData.fromJson(sample('related_franchise.json'));
      expect(data.anime.length, 4);
      expect(data.relations.length, 7);
    });
  });

  // ── Умови пошуку ───────────────────────────────────────────────────────────

  group('HikkaSearchFilters', () {
    test('за замовчуванням: сортування за оцінкою, лише безпечні рейтинги', () {
      const f = HikkaSearchFilters();
      expect(f.isDefault, isTrue);
      expect(f.activeCount, 0);
      final body = f.toBody(allowAdult: false);
      expect(body['sort'], ['score:desc', 'scored_by:desc']);
      expect(body['rating'], HikkaSearchFilters.safeRatings);
      expect(body.containsKey('query'), isFalse);
    });

    test('хентай прибирається, якщо 18+ вимкнено', () {
      const f = HikkaSearchFilters(ratings: {'rx', 'pg'});
      expect(f.toBody(allowAdult: false)['rating'], ['pg']);
      expect(f.toBody(allowAdult: true)['rating'], ['pg', 'rx']);
      const onlyAdult = HikkaSearchFilters(ratings: {'rx'});
      expect(onlyAdult.toBody(allowAdult: false)['rating'], HikkaSearchFilters.safeRatings);
    });

    test('запит коротший за 2 символи не надсилається', () {
      expect(const HikkaSearchFilters(query: 'a').toBody(allowAdult: false).containsKey('query'), isFalse);
      expect(const HikkaSearchFilters(query: '  ab ').toBody(allowAdult: false)['query'], 'ab');
    });

    test('усі поля потрапляють у тіло запиту, множини впорядковані', () {
      final f = const HikkaSearchFilters().copyWith(
        mediaTypes: {'tv', 'movie'},
        statuses: {'ongoing'},
        seasons: {'fall'},
        genres: {'drama', 'adventure'},
        yearFrom: 2020,
        yearTo: 2026,
        scoreFrom: 7,
        onlyTranslated: true,
        sort: 'start_date',
        ascending: true,
      );
      final b = f.toBody(allowAdult: false);
      expect(b['media_type'], ['movie', 'tv']);
      expect(b['status'], ['ongoing']);
      expect(b['season'], ['fall']);
      expect(b['genres'], ['adventure', 'drama']);
      expect(b['years'], [2020, 2026]);
      expect(b['score'], [7, null]);
      expect(b['only_translated'], isTrue);
      expect(b['sort'], ['start_date:asc']);
      expect(f.activeCount, 7);
      expect(f.isDefault, isFalse);
    });

    test('copyWith вміє скинути рік у null', () {
      final f = const HikkaSearchFilters(yearFrom: 2000, yearTo: 2010);
      final g = f.copyWith(yearFrom: null);
      expect(g.yearFrom, isNull);
      expect(g.yearTo, 2010);
      expect(f.copyWith(sort: 'created').yearFrom, 2000);
    });
  });

  // ── API ────────────────────────────────────────────────────────────────────

  group('HikkaApi', () {
    late FakeHikka server;
    late HikkaApi api;

    setUp(() {
      server = FakeHikka();
      api = HikkaApi(sender: server.call, retryDelay: Duration.zero);
    });

    test('пошук: сторінка, розбір і кеш', () async {
      final p = await api.searchAnime(const HikkaSearchFilters(), size: 30);
      expect(p.items.length, 30);
      expect(p.total, 100);
      expect(p.hasMore, isTrue);
      expect(api.networkCalls, 1);
      await api.searchAnime(const HikkaSearchFilters(), size: 30);
      expect(api.networkCalls, 1, reason: 'друге звернення бере кеш');
      await api.searchAnime(const HikkaSearchFilters(), size: 30, page: 2);
      expect(api.networkCalls, 2);
      api.clearCache();
      await api.searchAnime(const HikkaSearchFilters(), size: 30);
      expect(api.networkCalls, 3);
    });

    test('тіло запиту каталогу містить сортування й безпечні рейтинги', () async {
      await api.searchAnime(const HikkaSearchFilters(query: 'Фрірен'));
      final r = server.log.single;
      expect(r.method, 'POST');
      expect(r.url.path, '/anime');
      expect(r.url.queryParameters, {'page': '1', 'size': '30'});
      final body = jsonDecode(r.body!) as Map<String, dynamic>;
      expect(body['query'], 'Фрірен');
      expect(body['rating'], HikkaSearchFilters.safeRatings);
    });

    test('однакові паралельні запити зливаються в один', () async {
      final results = await Future.wait([api.anime('sousou-no-frieren-ad4e3e'), api.anime('sousou-no-frieren-ad4e3e')]);
      expect(results[0].slug, results[1].slug);
      expect(api.networkCalls, 1);
    });

    test('повтор після помилки сервера', () async {
      server.failNext = 1;
      final a = await api.anime('sousou-no-frieren-ad4e3e');
      expect(a.title(HikkaTitleLang.ua), 'Проводжальниця Фрірен');
      expect(api.networkCalls, 2);
    });

    test('дві помилки поспіль — зрозуміле повідомлення', () async {
      server.failNext = 2;
      await expectLater(
        api.anime('sousou-no-frieren-ad4e3e'),
        throwsA(isA<HikkaException>().having((e) => e.kind, 'kind', HikkaErrorKind.server).having((e) => e.message, 'message', contains('тимчасово'))),
      );
    });

    test('збій мережі повторюється: з другої спроби вдається', () async {
      var calls = 0;
      final flaky = HikkaApi(
        retryDelay: Duration.zero,
        sender: (r) async {
          calls++;
          if (calls == 1) throw const SocketException('Connection reset by peer', osError: OSError('Connection reset by peer', 104));
          return server.call(r);
        },
      );
      final a = await flaky.anime('sousou-no-frieren-ad4e3e');
      expect(a.title(HikkaTitleLang.ua), 'Проводжальниця Фрірен');
      expect(flaky.networkCalls, 2);
    });

    test('закрите сервером з’єднання (HttpException) теж повторюється', () async {
      var calls = 0;
      final flaky = HikkaApi(
        retryDelay: Duration.zero,
        sender: (r) async {
          calls++;
          if (calls <= 2) throw const HttpException('Connection closed before full header was received');
          return server.call(r);
        },
      );
      expect((await flaky.anime('sousou-no-frieren-ad4e3e')).slug, isNotEmpty);
      expect(flaky.networkCalls, 3);
    });

    test('стійкий обрив: «network» після трьох спроб, у деталях — точний тип винятку', () async {
      final down = HikkaApi(
        retryDelay: Duration.zero,
        sender: (r) async => throw const SocketException('Failed host lookup: api.hikka.io', osError: OSError('No address associated with hostname', 7)),
      );
      await expectLater(
        down.anime('x'),
        throwsA(isA<HikkaException>()
            .having((e) => e.kind, 'kind', HikkaErrorKind.network)
            .having((e) => e.detail, 'detail', allOf(contains('SocketException'), contains('os 7'), contains('Failed host lookup')))),
      );
      expect(down.networkCalls, 3);
    });

    test('тайм-аут: дві спроби і вид «timeout»', () async {
      final slow = HikkaApi(retryDelay: Duration.zero, sender: (r) async => throw TimeoutException('вичерпано'));
      await expectLater(
        slow.anime('x'),
        throwsA(isA<HikkaException>().having((e) => e.kind, 'kind', HikkaErrorKind.timeout).having((e) => e.message, 'message', contains('довго'))),
      );
      expect(slow.networkCalls, 2);
    });

    test('вдала спроба після збою не залишає помилки в кеші', () async {
      var calls = 0;
      final flaky = HikkaApi(
        retryDelay: Duration.zero,
        sender: (r) async {
          calls++;
          if (calls <= 3) throw const SocketException('down');
          return server.call(r);
        },
      );
      await expectLater(flaky.anime('sousou-no-frieren-ad4e3e'), throwsA(isA<HikkaException>()));
      // Користувач натиснув «Повторити»: помилка не закешована, запит іде в мережу заново
      expect((await flaky.anime('sousou-no-frieren-ad4e3e')).slug, isNotEmpty);
    });

    test('404 → «нічого не знайдено» без повторів', () async {
      await expectLater(
        api.anime('no-such-anime'),
        throwsA(isA<HikkaException>().having((e) => e.kind, 'kind', HikkaErrorKind.notFound)),
      );
      expect(api.networkCalls, 1);
    });

    test('немає мережі: помилка «network»; із кешу віддається застаріле', () async {
      var clock = DateTime(2026, 11, 3, 10);
      final timed = HikkaApi(sender: server.call, retryDelay: Duration.zero, now: () => clock);
      final fresh = await timed.anime('sousou-no-frieren-ad4e3e');
      server.offline = true;
      // Кеш ще свіжий — мережа взагалі не потрібна
      expect((await timed.anime('sousou-no-frieren-ad4e3e')).slug, fresh.slug);
      // Кеш протух, мережі немає — показуємо те, що було
      clock = clock.add(const Duration(hours: 5));
      expect((await timed.anime('sousou-no-frieren-ad4e3e')).slug, fresh.slug);
      // А для того, чого не було, — зрозуміла помилка
      await expectLater(
        timed.anime('another-one'),
        throwsA(isA<HikkaException>().having((e) => e.kind, 'kind', HikkaErrorKind.network).having((e) => e.message, 'message', contains('Немає зв’язку'))),
      );
    });

    test('18+ відфільтровується зі списків, якщо вимкнено', () async {
      Map<String, dynamic> item(String slug, String rating) => {'slug': slug, 'title_ua': slug, 'rating': rating, 'data_type': 'anime'};
      final listJson = {
        'pagination': {'total': 2, 'pages': 1, 'page': 1},
        'list': [item('ok', 'pg_13'), item('hentai', 'rx')],
      };
      final scheduleJson = {
        'pagination': {'total': 2, 'pages': 1, 'page': 1},
        'list': [
          {'anime': item('ok', 'pg_13'), 'episode': 1, 'airing_at': 1790000000},
          {'anime': item('hentai', 'rx'), 'episode': 1, 'airing_at': 1790000100},
        ],
      };
      final raw = HikkaApi(
        retryDelay: Duration.zero,
        sender: (r) async => HikkaResponse(200, jsonEncode(r.url.path.contains('schedule') ? scheduleJson : listJson)),
      );
      expect((await raw.recommendations('x', allowAdult: false)).items.map((a) => a.slug), ['ok']);
      expect((await raw.recommendations('x', allowAdult: true)).items.map((a) => a.slug), ['ok', 'hentai']);
      expect((await raw.schedule(allowAdult: false)).items.map((e) => e.anime.slug), ['ok']);
      expect((await raw.schedule(allowAdult: true)).items.map((e) => e.anime.slug), ['ok', 'hentai']);
    });

    test('персонажі: сторінка, пошук, аніме й озвучення', () async {
      expect((await api.searchCharacters('')).items.length, 8);
      final found = await api.searchCharacters('Фрірен');
      expect(found.items.map((c) => c.slug), contains('frieren-7f706c'));
      expect((await api.character('frieren-7f706c')).descriptionUa, isNotNull);
      expect((await api.characterAnime('frieren-7f706c')).items, isNotEmpty);
      expect((await api.characterVoices('frieren-7f706c')).items, isNotEmpty);
      expect((await api.animeCharacters('x')).items, isNotEmpty);
      expect((await api.animeStaff('x')).items, isNotEmpty);
      expect((await api.genres()).length, greaterThan(20));
    });

    test('франшиза: відповідь розбирається', () async {
      final data = await api.franchise('sousou-no-frieren-ad4e3e');
      expect(data.anime.length, 4);
    });
  });

  // ── Пагінація ──────────────────────────────────────────────────────────────

  group('HikkaPager', () {
    test('накопичує сторінки й зупиняється наприкінці', () async {
      final server = FakeHikka();
      final api = HikkaApi(sender: server.call, retryDelay: Duration.zero);
      final pager = HikkaPager<HikkaAnime>((page) => api.searchAnime(const HikkaSearchFilters(), page: page, size: 40), keyOf: (a) => a.slug);
      expect(pager.isFresh, isTrue);
      await pager.reload();
      expect(pager.items.length, 40);
      expect(pager.total, 100);
      expect(pager.hasMore, isTrue);
      await pager.loadMore();
      await pager.loadMore();
      expect(pager.items.length, 100);
      expect(pager.hasMore, isFalse);
      await pager.loadMore(); // нічого не робить
      expect(server.count((r) => r.url.path == '/anime'), 3);
      pager.dispose();
    });

    test('порожній результат і помилка з повтором', () async {
      final server = FakeHikka();
      final api = HikkaApi(sender: server.call, retryDelay: Duration.zero);
      final empty = HikkaPager<HikkaAnime>((page) => api.searchAnime(const HikkaSearchFilters(query: 'zzzzqqqq'), page: page));
      await empty.reload();
      expect(empty.isEmpty, isTrue);

      server.offline = true;
      final broken = HikkaPager<HikkaAnime>((page) => api.searchAnime(const HikkaSearchFilters(query: 'abc'), page: page));
      await broken.reload();
      expect(broken.error, isNotNull);
      expect(broken.errorMessage, contains('Немає зв’язку'));
      expect(broken.items, isEmpty);
      server.offline = false;
      await broken.retry();
      expect(broken.error, isNull);
      empty.dispose();
      broken.dispose();
    });

    test('відповідь, що спізнилась після зміни умов, відкидається', () async {
      final slow = Completer<HikkaPage<int>>();
      var phase = 0;
      final pager = HikkaPager<int>((page) {
        phase++;
        if (phase == 1) return slow.future;
        return Future.value(const HikkaPage<int>(items: [7, 8], page: 1, pages: 1, total: 2));
      });
      final first = pager.reload();
      final second = pager.reload();
      await second;
      expect(pager.items, [7, 8]);
      slow.complete(const HikkaPage<int>(items: [1, 2, 3], page: 1, pages: 1, total: 3));
      await first;
      expect(pager.items, [7, 8], reason: 'стара відповідь не має перезаписати нову');
      pager.dispose();
    });

    test('повтори елементів між сторінками відсіюються за ключем', () async {
      final pages = [
        const HikkaPage<int>(items: [1, 2, 3], page: 1, pages: 2, total: 5),
        const HikkaPage<int>(items: [3, 4, 5], page: 2, pages: 2, total: 5),
      ];
      final pager = HikkaPager<int>((page) async => pages[page - 1], keyOf: (n) => n);
      await pager.reload();
      await pager.loadMore();
      expect(pager.items, [1, 2, 3, 4, 5]);
      pager.dispose();
    });
  });

  // ── Навігація ──────────────────────────────────────────────────────────────

  group('HikkaNav', () {
    late HikkaNav nav;
    late List<String> opened;
    int notified = 0;

    setUp(() {
      nav = HikkaNav();
      opened = [];
      nav.urlOpener = (url) async {
        opened.add(url);
        return true;
      };
      notified = 0;
      nav.addListener(() => notified++);
    });

    test('стек сторінок і «Назад»', () {
      expect(nav.canGoBack, isFalse);
      nav.openAnime('a');
      nav.openCharacter('c');
      nav.openFranchise('a');
      expect(nav.routes.map((r) => r.kind), [HikkaRouteKind.anime, HikkaRouteKind.character, HikkaRouteKind.franchise]);
      expect(nav.top!.slug, 'a');
      expect(nav.back(), isTrue);
      expect(nav.top!.kind, HikkaRouteKind.character);
      nav.back();
      nav.back();
      expect(nav.top, isNull);
      expect(nav.back(), isFalse, reason: 'на «Головній» закривати нічого');
    });

    test('подвійний тап по одній і тій самій сторінці не дублює її', () {
      nav.openAnime('a');
      final before = notified;
      nav.openAnime('a');
      expect(nav.routes.length, 1);
      expect(notified, before);
      nav.openAnime('');
      expect(nav.routes.length, 1);
    });

    test('головні вкладки: перемикання закриває сторінки; «Назад» з іншої вкладки веде на «Головну»', () {
      expect(nav.main, MainTab.home);
      nav.setMain(MainTab.lists);
      expect(nav.main, MainTab.lists);
      nav.openAnime('a');
      expect(nav.routes.length, 1);
      nav.setMain(MainTab.profile);
      expect(nav.routes, isEmpty);
      expect(nav.back(), isTrue);
      expect(nav.main, MainTab.home);
      expect(nav.back(), isFalse);
    });

    test('повторний тап по поточній вкладці повертає на її корінь, без сторінок — нічого не робить', () {
      nav.setMain(MainTab.discover);
      final before = notified;
      nav.setMain(MainTab.discover);
      expect(notified, before, reason: 'вкладка вже відкрита й без сторінок');
      nav.openAnime('a');
      nav.setMain(MainTab.discover);
      expect(nav.routes, isEmpty);
    });

    test('розділи «Огляду»: перемикання відкриває «Огляд» і закриває сторінки', () {
      expect(nav.tab, HikkaTab.overview, reason: 'за замовчуванням — загальна сторінка');
      nav.setTab(HikkaTab.characters);
      nav.openCharacter('c');
      expect(nav.main, MainTab.discover);
      expect(nav.tab, HikkaTab.characters);
      nav.setTab(HikkaTab.schedule);
      expect(nav.routes, isEmpty);
      expect(nav.tab, HikkaTab.schedule);
      nav.setMain(MainTab.home);
      nav.setTab(HikkaTab.articles);
      expect(nav.main, MainTab.discover, reason: 'розділ відкриває «Огляд» навіть з іншої вкладки');
      expect(nav.back(), isTrue);
      expect(nav.main, MainTab.home);
    });

    test('каталог із готовими умовами віддає їх один раз', () {
      nav.openAnime('a');
      nav.openCatalog(const HikkaSearchFilters(genres: {'drama'}));
      expect(nav.main, MainTab.discover);
      expect(nav.tab, HikkaTab.anime);
      expect(nav.routes, isEmpty);
      expect(nav.hasPendingFilters, isTrue);
      expect(nav.wantsSearchFocus, isFalse);
      expect(nav.takePendingFilters()!.genres, {'drama'});
      expect(nav.takePendingFilters(), isNull);
    });

    test('пошук із «Головної»: каталог з курсором у полі, прапорець віддається один раз', () {
      nav.openSearch();
      expect(nav.main, MainTab.discover);
      expect(nav.tab, HikkaTab.anime);
      expect(nav.wantsSearchFocus, isTrue);
      expect(nav.takeFocusSearch(), isTrue);
      expect(nav.takeFocusSearch(), isFalse);
    });

    test('колекції й статті відкриваються сторінками зі стеку', () {
      nav.openCollection('abc123');
      nav.openArticle('my-article');
      expect(nav.routes.map((r) => r.kind), [HikkaRouteKind.collection, HikkaRouteKind.article]);
      expect(nav.routes.map((r) => r.slug), ['abc123', 'my-article']);
      nav.openCollection('');
      nav.openArticle('');
      expect(nav.routes.length, 2, reason: 'порожній ідентифікатор нічого не відкриває');
      nav.openArticle('my-article');
      expect(nav.routes.length, 2, reason: 'подвійний тап');
    });

    test('локальна медіатека — сторінка зі стеку, закривається «Назад»', () {
      nav.setMain(MainTab.profile);
      nav.openLocalLibrary();
      expect(nav.top!.kind, HikkaRouteKind.localLibrary);
      nav.openLocalLibrary();
      expect(nav.routes.length, 1);
      expect(nav.back(), isTrue);
      expect(nav.main, MainTab.profile, reason: 'після закриття — та сама вкладка');
    });

    test('стек обмежений за глибиною', () {
      for (int i = 0; i < HikkaNav.maxDepth + 10; i++) {
        nav.openAnime('a$i');
      }
      expect(nav.routes.length, HikkaNav.maxDepth);
      expect(nav.top!.slug, 'a${HikkaNav.maxDepth + 9}');
    });

    test('посилання: сторінки каталогу відкриваються всередині, решта — у браузері', () async {
      await nav.openLink('https://hikka.io/anime/frieren-abc');
      expect(nav.top!.kind, HikkaRouteKind.anime);
      expect(nav.top!.slug, 'frieren-abc');
      await nav.openLink('https://hikka.io/characters/fern-123');
      expect(nav.top!.kind, HikkaRouteKind.character);
      await nav.openLink('https://hikka.io/collections/abc123');
      expect(nav.top!.kind, HikkaRouteKind.collection);
      expect(nav.top!.slug, 'abc123');
      await nav.openLink('https://hikka.io/articles/my-article');
      expect(nav.top!.kind, HikkaRouteKind.article);
      await nav.openLink('https://example.com/page');
      expect(opened, ['https://example.com/page']);
      expect(nav.routes.length, 4);
    });

    test('обробники «Назад» (панель фільтрів) мають пріоритет', () {
      nav.openAnime('a');
      var sheetOpen = true;
      bool guard() {
        if (!sheetOpen) return false;
        sheetOpen = false;
        return true;
      }

      nav.addBackGuard(guard);
      expect(nav.back(), isTrue);
      expect(nav.routes.length, 1, reason: 'перше «Назад» закрило лише панель');
      expect(nav.back(), isTrue);
      expect(nav.routes, isEmpty);
      nav.removeBackGuard(guard);
    });

    test('маршрут пам’ятає прокрутку й довільний стан', () {
      nav.openAnime('a');
      nav.top!
        ..scroll = 420
        ..memo['mode'] = 'groups';
      nav.openAnime('b');
      nav.back();
      expect(nav.top!.scroll, 420);
      expect(nav.top!.memo['mode'], 'groups');
    });
  });

  // ── Налаштування ───────────────────────────────────────────────────────────

  group('HikkaPrefs', () {
    test('зміна сповіщає слухачів один раз; те саме значення — ні', () {
      final p = HikkaPrefs(titleLang: HikkaTitleLang.ua, allowAdult: false);
      var n = 0;
      p.addListener(() => n++);
      p.titleLang = HikkaTitleLang.en;
      p.titleLang = HikkaTitleLang.en;
      p.allowAdult = true;
      p.allowAdult = true;
      expect(n, 2);
      expect(p.titleLang, HikkaTitleLang.en);
      expect(p.allowAdult, isTrue);
    });

    test('мова з імені: невідоме значення дає українську', () {
      expect(HikkaTitleLang.fromName('ja'), HikkaTitleLang.ja);
      expect(HikkaTitleLang.fromName('xx'), HikkaTitleLang.ua);
      expect(HikkaTitleLang.fromName(null), HikkaTitleLang.ua);
    });
  });

  // ── Зображення ─────────────────────────────────────────────────────────────

  group('Зображення', () {
    test('зменшена копія лише для cdn.hikka.io; кроки ширини', () {
      const src = 'https://cdn.hikka.io/content/anime/x/abc.jpg';
      expect(HikkaImages.resized(src, width: 240), 'https://img.hikka.io/insecure/rs:fit:240:0:0:0/plain/$src');
      expect(HikkaImages.resized('https://other.example/a.jpg', width: 240), 'https://other.example/a.jpg');
      expect(HikkaImages.resized(src), src);
      expect(HikkaImages.bucket(100, 1), 160);
      expect(HikkaImages.bucket(100, 2.625), 320);
      expect(HikkaImages.bucket(10, 1), 80);
      expect(HikkaImages.bucket(5000, 3), 960);
      expect(HikkaImages.fileName('a'), isNot(HikkaImages.fileName('b')));
      expect(HikkaImages.fileName('a'), HikkaImages.fileName('a'));
      expect(HikkaImages.fileName('a'), matches(RegExp(r'^[0-9a-f]{16}\.img$')));
    });

    test('диск: одне завантаження на адресу, повторні читаються з кешу', () async {
      final dir = await Directory.systemTemp.createTemp('hikka_img_test');
      addTearDown(() => dir.delete(recursive: true));
      var fetched = 0;
      final store = HikkaImageStore(dir: dir, fetcher: (url) async {
        fetched++;
        return fakePng(url);
      });
      final a = await store.load('https://x/a.jpg');
      final b = await store.load('https://x/a.jpg');
      expect(a, b);
      expect(fetched, 1);
      expect(store.downloads, 1);
      // Інший екземпляр на тій самій теці бере файл із диска
      final again = HikkaImageStore(dir: dir, fetcher: (url) async => throw StateError('мережа не потрібна'));
      expect(await again.load('https://x/a.jpg'), a);
      expect(await store.diskSize(), a.length);
    });

    test('паралельні запити однієї адреси зливаються', () async {
      final dir = await Directory.systemTemp.createTemp('hikka_img_test');
      addTearDown(() => dir.delete(recursive: true));
      var fetched = 0;
      final store = HikkaImageStore(dir: dir, fetcher: (url) async {
        fetched++;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return fakePng(url);
      });
      await Future.wait([for (int i = 0; i < 5; i++) store.load('https://x/p.jpg')]);
      expect(fetched, 1);
    });

    test('запасна адреса, якщо основна не відповіла', () async {
      final dir = await Directory.systemTemp.createTemp('hikka_img_test');
      addTearDown(() => dir.delete(recursive: true));
      final store = HikkaImageStore(dir: dir, fetcher: (url) async {
        if (url.contains('resized')) throw const HttpException('500');
        return fakePng(url);
      });
      final bytes = await store.load('https://x/resized.jpg', fallback: 'https://x/full.jpg');
      expect(bytes, fakePng('https://x/full.jpg'));
      await expectLater(store.load('https://x/resized2.jpg'), throwsA(isA<HttpException>()));
    });

    test('evict і clear звільняють місце', () async {
      final dir = await Directory.systemTemp.createTemp('hikka_img_test');
      addTearDown(() => dir.delete(recursive: true));
      final store = HikkaImageStore(dir: dir, fetcher: (url) async => fakePng(url));
      await store.load('https://x/1.jpg');
      await store.load('https://x/2.jpg');
      final size = await store.diskSize();
      expect(size, greaterThan(0));
      await store.evict('https://x/1.jpg');
      expect(await store.diskSize(), lessThan(size));
      final freed = await store.clear();
      expect(freed, greaterThan(0));
      expect(await store.diskSize(), 0);
      await store.load('https://x/2.jpg');
      expect(store.downloads, 3, reason: 'після очищення картинка качається знову');
    });

    test('мережевий збій без диска не ховається', () async {
      final store = HikkaImageStore(dir: Directory('/definitely/not/writable/hikka'), fetcher: (url) async => throw const SocketException('down'));
      await expectLater(store.load('https://x/q.jpg'), throwsA(isA<SocketException>()));
    });
  });
}
