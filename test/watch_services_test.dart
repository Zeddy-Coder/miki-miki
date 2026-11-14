import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:miki_miki/models/hikka_models.dart';
import 'package:miki_miki/models/source_models.dart';
import 'package:miki_miki/services/episode_check.dart';
import 'package:miki_miki/services/source_prefs.dart';
import 'package:miki_miki/services/source_registry.dart';
import 'package:miki_miki/services/sources/source_http.dart';
import 'package:miki_miki/services/sources/ua/mikai_source.dart';
import 'package:miki_miki/services/sources/ua/ufdub_source.dart';
import 'package:miki_miki/services/stream_resolver.dart';
import 'package:miki_miki/services/watch_models.dart';
import 'package:miki_miki/services/watch_service.dart';
import 'package:miki_miki/services/watch_store.dart';

import 'support/fake_site.dart';

SEpisode ep(num? n, {int? season, String? voice}) => SEpisode(url: 'u$n', name: 'Серія $n', number: n?.toDouble(), season: season, voice: voice);
List<SEpisode> eps(Iterable<num> ns) => [for (final n in ns) ep(n)];

WatchStore memoryStore() {
  var data = <String, dynamic>{};
  return WatchStore(load: () => data, save: (d) => data = jsonDecode(jsonEncode(d)) as Map<String, dynamic>);
}

void main() {
  group('звірка серій з Hikka', () {
    const ongoing = HikkaEpisodeInfo(released: 5, total: 12);
    const finished = HikkaEpisodeInfo(released: 12, total: 12, finished: true);

    test('збігається: тайтл виходить, озвучено рівно стільки, скільки вийшло', () {
      final c = checkEpisodes(eps([1, 2, 3, 4, 5]), ongoing);
      expect(c.level, EpisodeCheckLevel.match);
      expect(c.hasNote, isFalse);
      expect(c.syncSafe, isTrue);
    });

    test('відставання озвучки — м’яка примітка, синхронізація безпечна', () {
      final c = checkEpisodes(eps([1, 2, 3, 4]), ongoing);
      expect(c.level, EpisodeCheckLevel.lag);
      expect(c.hasNote, isTrue);
      expect(c.note, contains('4 з 5'));
      expect(c.summary, '4 з 5');
      expect(c.syncSafe, isTrue);
      expect(c.isWarning, isFalse);
    });

    test('завершений тайтл, не всі серії → incomplete', () {
      final c = checkEpisodes(eps(List.generate(10, (i) => i + 1)), finished);
      expect(c.level, EpisodeCheckLevel.incomplete);
      expect(c.note, contains('10/12'));
      expect(c.syncSafe, isTrue);
    });

    test('більше серій, ніж «всього» на Hikka → розбіжність нумерації', () {
      final c = checkEpisodes(eps(List.generate(14, (i) => i + 1)), finished);
      expect(c.level, EpisodeCheckLevel.mismatch);
      expect(c.note, contains('14'));
      expect(c.note, contains('12'));
      expect(c.syncSafe, isFalse);
    });

    test('наскрізна нумерація (13–24 для другого сезону)', () {
      final c = checkEpisodes(eps(List.generate(12, (i) => i + 13)), finished);
      expect(c.level, EpisodeCheckLevel.mismatch);
      expect(c.note, contains('починається з 13'));
      expect(c.syncSafe, isFalse);
    });

    test('пропуски в нумерації', () {
      final c = checkEpisodes(eps([1, 2, 4, 5, 7]), const HikkaEpisodeInfo(released: 7, total: 12));
      expect(c.level, EpisodeCheckLevel.mismatch);
      expect(c.note, contains('3, 6'));
    });

    test('серії без номерів → порівняти неможливо', () {
      final c = checkEpisodes([ep(null), ep(null)], finished);
      expect(c.level, EpisodeCheckLevel.mismatch);
      expect(c.note, contains('номери серій'));
    });

    test('кілька сезонів в одному варіанті', () {
      final c = checkEpisodes([ep(1, season: 1), ep(2, season: 1), ep(1, season: 2)], finished);
      expect(c.level, EpisodeCheckLevel.mismatch);
      expect(c.note, contains('кілька сезонів'));
    });

    test('Hikka ще не знає про нові серії → lead, але без блокування синхронізації', () {
      final c = checkEpisodes(eps([1, 2, 3, 4, 5, 6]), ongoing);
      expect(c.level, EpisodeCheckLevel.lead);
      expect(c.hasNote, isTrue);
      expect(c.syncSafe, isTrue);
    });

    test('дробові номери (позасюжетні) в основний рахунок не входять', () {
      final c = checkEpisodes([...eps([1, 2, 3, 4, 5]), ep(2.5)], ongoing);
      expect(c.level, EpisodeCheckLevel.match);
    });

    test('на Hikka кількість невідома → нічого порівнювати', () {
      final c = checkEpisodes(eps([1, 2, 3]), const HikkaEpisodeInfo());
      expect(c.level, EpisodeCheckLevel.unknown);
      expect(c.hasNote, isFalse);
    });

    test('фільм: 1 з 1', () {
      final c = checkEpisodes(eps([1]), const HikkaEpisodeInfo(released: 1, total: 1, finished: true));
      expect(c.level, EpisodeCheckLevel.match);
    });

    // ── Кілька частин сезону в одній купі ───────────────────────────────────────

    test('дві частини злито: «24 з 12» — розбіжність із підказкою про об’єднання', () {
      final c = checkEpisodes(eps(List.generate(24, (i) => i + 1)), finished);
      expect(c.level, EpisodeCheckLevel.mismatch);
      expect(c.count, 24);
      expect(c.summary, '24 з 12');
      expect(c.note, contains('об’єднано 2 частини'));
      expect(c.note, contains('передаватимуться на Hikka'));
      expect(c.syncSafe, isFalse);
      expect(c.isWarning, isTrue);
    });

    test('три частини по 8: «24 з 8»', () {
      final c = checkEpisodes(eps(List.generate(24, (i) => i + 1)), const HikkaEpisodeInfo(released: 8, total: 8, finished: true));
      expect(c.level, EpisodeCheckLevel.mismatch);
      expect(c.note, contains('об’єднано 3 частини'));
    });

    test('злито, але 25 з 12 — кратності немає, підказки про частини не буде', () {
      final c = checkEpisodes(eps(List.generate(25, (i) => i + 1)), finished);
      expect(c.level, EpisodeCheckLevel.mismatch);
      expect(c.note, isNot(contains('об’єднано')));
    });

    test('друга частина: на сторінці «0 з 12» — жодної серії', () {
      final c = checkEpisodes(const [], finished);
      expect(c.level, EpisodeCheckLevel.incomplete);
      expect(c.count, 0);
      expect(c.summary, '0 з 12');
      expect(c.note, contains('немає жодної серії'));
      expect(c.note, contains('іншої частини'));
      expect(c.syncSafe, isTrue); // синхронізувати нічого — плутанини не буде
    });

    test('порожній варіант для тайтлу, що виходить, — «поки немає»', () {
      final c = checkEpisodes(const [], ongoing);
      expect(c.level, EpisodeCheckLevel.lag);
      expect(c.summary, '0 з 5');
      expect(c.note, contains('поки немає'));
    });

    test('порожній варіант, а Hikka кількості не знає — без дисклеймера', () {
      final c = checkEpisodes(const [], const HikkaEpisodeInfo());
      expect(c.level, EpisodeCheckLevel.unknown);
      expect(c.hasNote, isFalse);
    });

    test('номери починаються знову: 1–12 і ще раз 1–12 → повтори', () {
      final c = checkEpisodes([...eps(List.generate(12, (i) => i + 1)), ...eps(List.generate(12, (i) => i + 1))], finished);
      expect(c.level, EpisodeCheckLevel.mismatch);
      expect(c.note, contains('повторюються'));
      expect(c.syncSafe, isFalse);
    });

    test('наскрізна нумерація: підказка, що 13–24 відповідають 1–12', () {
      final c = checkEpisodes(eps(List.generate(12, (i) => i + 13)), finished);
      expect(c.level, EpisodeCheckLevel.mismatch);
      expect(c.note, contains('13–24'));
      expect(c.note, contains('1–12'));
    });

    // ── OVA / спешл ──────────────────────────────────────────────────────────────

    SEpisode named(num n, String name) => SEpisode(url: 'u$n$name', name: name, number: n.toDouble());

    test('OVA додано останньою серією: основні 12 збігаються, зайва ігнорується', () {
      final c = checkEpisodes([...eps(List.generate(12, (i) => i + 1)), named(13, 'OVA')], finished);
      expect(c.level, EpisodeCheckLevel.extra);
      expect(c.count, 12);
      expect(c.syncLimit, 12);
      expect(c.syncSafe, isTrue);
      expect(c.hasNote, isTrue);
      expect(c.note, contains('OVA'));
      expect(c.note, contains('враховуватись не будуть'));
    });

    test('кілька OVA в кінці: «OVA 1», «Спеціальний випуск»', () {
      final c = checkEpisodes([...eps(List.generate(12, (i) => i + 1)), named(13, 'OVA 1'), named(14, 'Спеціальний випуск')], finished);
      expect(c.level, EpisodeCheckLevel.extra);
      expect(c.syncLimit, 12);
      expect(c.note, contains('Останні 2 серії'));
    });

    test('OVA в дужках після номера: «Серія 13 (OVA)»', () {
      final c = checkEpisodes([...eps(List.generate(12, (i) => i + 1)), named(13, 'Серія 13 (OVA)')], finished);
      expect(c.level, EpisodeCheckLevel.extra);
      expect(c.syncLimit, 12);
    });

    test('OVA останньою, а основних менше: відставання + примітка про OVA', () {
      final c = checkEpisodes([...eps([1, 2, 3, 4]), named(5, 'OVA')], ongoing);
      expect(c.level, EpisodeCheckLevel.lag);
      expect(c.count, 4);
      expect(c.syncLimit, 4);
      expect(c.note, contains('OVA'));
    });

    test('звичайна серія з номером 13 без позначки OVA → більше за «всього» → розбіжність', () {
      final c = checkEpisodes(eps(List.generate(13, (i) => i + 1)), finished);
      expect(c.level, EpisodeCheckLevel.mismatch);
      expect(c.note, contains('13'));
    });

    test('OVA посеред сезону зсуває нумерацію → розбіжність', () {
      final list = [...eps([1, 2, 3, 4, 5, 6]), named(7, 'OVA'), ...eps([8, 9, 10, 11, 12, 13])];
      final c = checkEpisodes(list, finished);
      expect(c.level, EpisodeCheckLevel.mismatch);
      expect(c.note, contains('OVA'));
      expect(c.syncSafe, isFalse);
    });

    test('слово «special» усередині довільної назви серії не робить її OVA', () {
      final list = [...eps(List.generate(11, (i) => i + 1)), named(12, 'Серія 12. Special Training')];
      final c = checkEpisodes(list, finished);
      expect(c.level, EpisodeCheckLevel.match);
      expect(c.syncLimit, isNull);
    });

    test('looksLikeExtra: позначки й не-позначки', () {
      for (final yes in ['OVA', 'OVA 2', '[OVA] Серія 1', 'Спешл', 'Спеціальний випуск 1', 'Фільм', 'Серія 13 (OVA)', 'Сезон 1 · OVA', '13 [Special]', 'Movie']) {
        expect(looksLikeExtra(yes), isTrue, reason: yes);
      }
      for (final no in ['Серія 5', '5 серія', 'Episode 5', 'Серія 12. Special Training', 'Ovaltine', 'Новий фільмовий світ', 'Сезон 2 · Серія 3', '']) {
        expect(looksLikeExtra(no), isFalse, reason: no);
      }
    });
  });

  group('ключі серій', () {
    test('ціле, дробове, сезон, без номера', () {
      expect(episodeKey(ep(3), 0), '3');
      expect(episodeKey(ep(3.5), 0), '3.5');
      expect(episodeKey(ep(5, season: 2), 0), 's2e5');
      expect(episodeKey(ep(null), 6), 'i7');
    });
  });

  group('сховище переглянутого', () {
    test('позначки, остання серія, обрана озвучка, зіставлення — і все це переживає перезавантаження', () {
      var now = DateTime(2026, 11, 3, 8);
      var data = <String, dynamic>{};
      WatchStore make() => WatchStore(load: () => data, save: (d) => data = jsonDecode(jsonEncode(d)) as Map<String, dynamic>, now: () => now);
      final s = make();
      s.setWatched('hikka:a', '1', true);
      s.setWatched('hikka:a', '2', true);
      s.setWatched('hikka:a', '1', false);
      s.setLast('hikka:a', '2', 'mikai|1|t_1:voice');
      s.setPreferredGroup('hikka:a', 'g1');
      s.setLink('slug', 'ufdub', const SAnime(url: '/anime/21-x.html', title: 'Хвіст Феї'));

      final r = make();
      expect(r.watched('hikka:a'), {'2'});
      expect(r.isWatched('hikka:a', '2'), isTrue);
      expect(r.last('hikka:a')!.epKey, '2');
      expect(r.last('hikka:a')!.groupId, 'mikai|1|t_1:voice');
      expect(r.preferredGroup('hikka:a'), 'g1');
      expect(r.link('slug', 'ufdub')!.title, 'Хвіст Феї');
      expect(r.link('slug', 'uakino'), isNull);
      r.setLink('slug', 'ufdub', null);
      expect(r.link('slug', 'ufdub'), isNull);
    });

    test('markUpTo позначає всі серії до вказаної', () {
      final s = memoryStore();
      s.markUpTo('k', ['1', '2', '3', '4'], '3');
      expect(s.watched('k'), {'1', '2', '3'});
    });

    test('недавні тайтли — найновіші першими', () {
      var now = DateTime(2026, 11, 3, 8);
      var data = <String, dynamic>{};
      final s = WatchStore(load: () => data, save: (d) => data = d, now: () => now);
      s.setLast('a', '1', 'g');
      now = now.add(const Duration(hours: 1));
      s.setLast('b', '1', 'g');
      now = now.add(const Duration(hours: 1));
      s.setLast('a', '2', 'g');
      expect(s.recentTitles(), ['a', 'b']);
    });
  });

  group('налаштування джерел', () {
    test('ввімкнення, ключ, якість зберігаються й повідомляють слухачів', () {
      var data = <String, dynamic>{};
      final p = SourcePrefs(load: () => data, save: (d) => data = jsonDecode(jsonEncode(d)) as Map<String, dynamic>);
      var n = 0;
      p.addListener(() => n++);
      expect(p.isEnabled('uakino'), isTrue);
      p.setEnabled('uakino', false);
      p.mikaiKey = '  abc ';
      p.maxHeight = 720;
      p.hoster = 'Ashdi';
      expect(n, 4);
      final q = SourcePrefs(load: () => data, save: (d) => data = d);
      expect(q.isEnabled('uakino'), isFalse);
      expect(q.isEnabled('mikai'), isTrue);
      expect(q.mikaiKey, 'abc');
      expect(q.maxHeight, 720);
      expect(q.hoster, 'Ashdi');
      q.setEnabled('uakino', true);
      expect(q.isEnabled('uakino'), isTrue);
    });
  });

  group('черга серій', () {
    test('однакові номери в одному варіанті отримують різні ключі', () {
      final g = WatchGroup(id: 'g', sourceId: 's', label: 'x', episodes: [ep(1), ep(2), ep(1), ep(2), ep(1)]);
      final s = RemoteSession.fromGroup(animeKey: 'hikka:a', animeTitle: 'A', group: g);
      expect(s.entries.map((e) => e.epKey), ['1', '2', '1~2', '2~2', '1~3']);
      expect(s.entries.map((e) => e.key).toSet().length, 5);
      expect(s.indexOfKey('1~2'), 2);
      expect(s.displayTitle(0), 'A · Серія 1');
    });
  });

  group('пошук по джерелах', () {
    const slug = 'kusuriya-no-hitorigoto-zoku-hen-636673';
    const kusuriya = HikkaAnime(
      slug: slug,
      titleUa: 'Монолог травниці — 3 сезон',
      titleEn: 'The Apothecary Diaries Season 3',
      titleJa: 'Kusuriya no Hitorigoto 3rd Season',
      status: 'ongoing',
      year: 2026,
      episodesReleased: 5,
      episodesTotal: 12,
      malId: 59177,
    );
    const fairy = HikkaAnime(
      slug: 'fairy-tail-abc',
      titleUa: 'Хвіст Феї',
      titleEn: 'Fairy Tail',
      titleJa: 'Fairy Tail',
      status: 'finished',
      year: 2009,
      episodesReleased: 12,
      episodesTotal: 12,
    );
    const notFound = Resp('{"ok":false,"error":{"code":"not_found","message":"x"}}', status: 404);

    WatchService service(FakeSite site, {WatchStore? store, SourcePrefs? prefs}) {
      final reg = SourceRegistry(
        sources: [MikaiSource(http: site.http), UfDubSource(http: site.http)],
        prefs: prefs ?? SourcePrefs(load: () => {}, save: (_) {}),
        http: site.http,
      );
      return WatchService(registry: reg, store: store ?? memoryStore());
    }

    Future<WatchLoad> settle(WatchLoad load) async {
      if (!load.busy) return load;
      final done = Completer<void>();
      void check() {
        if (!load.busy && !done.isCompleted) done.complete();
      }

      load.addListener(check);
      await done.future.timeout(const Duration(seconds: 5));
      load.removeListener(check);
      return load;
    }

    FakeSite ufdubSite({Map<String, Object> extra = const {}}) => FakeSite({
          ...extra,
          'POST https://ufdub.com/index.php?do=search': fixture('ufdub_search_fairytail.html'),
          'video.ufdub.com': fixture('ufdub_player21.html'),
          'ufdub.com/anime/21-': fixture('ufdub_anime21.html'),
        });

    test('Mikai за slug Hikka: озвучення перед субтитрами, у межах виду — де серій більше', () async {
      final site = FakeSite({'/anime/hikka:$slug': fixture('mikai_detail.json'), '/anime/7601/player': fixture('mikai_player.json')});
      final load = await settle(service(site).start(kusuriya, searchOthers: false));
      final t = load.title;
      expect(t.offers.single.source.id, 'mikai');
      expect(t.errors, isEmpty);
      expect(t.licensed, isFalse);
      final groups = t.offers.single.groups;
      expect(groups.length, 11);
      final firstSub = groups.indexWhere((g) => g.isSub);
      expect(firstSub, greaterThan(0));
      expect(groups.sublist(firstSub).every((g) => g.isSub), isTrue);
      for (final part in [groups.sublist(0, firstSub), groups.sublist(firstSub)]) {
        final counts = [for (final g in part) g.episodes.length];
        expect(counts, [...counts]..sort((a, b) => b.compareTo(a)));
      }
      // у фікстурі нумерація 1..N і N ≤ 5: розбіжності нумерації бути не повинно
      expect(groups.every((g) => load.checkOf(g).syncSafe), isTrue);
      // у кожної групи є команди для аватарок / опису
      expect(groups.first.teams, isNotEmpty);
    });

    test('Mikai не знає slug, але знає MAL-id → запасний шлях', () async {
      final site = FakeSite({
        '/anime/hikka:': notFound,
        '/anime/mal:59177': fixture('mikai_detail.json'),
        '/anime/7601/player': fixture('mikai_player.json'),
      });
      final load = await settle(service(site).start(kusuriya, searchOthers: false));
      expect(load.title.offers.single.groups, isNotEmpty);
      expect(site.count('/anime/mal:59177'), 1);
    });

    test('Mikai не знає тайтл зовсім → порожньо й без помилки', () async {
      final site = FakeSite({'/anime/hikka:': notFound, '/anime/mal:': notFound});
      final load = await settle(service(site).start(kusuriya, searchOthers: false));
      expect(load.title.offers, isEmpty);
      expect(load.title.errors, isEmpty);
      expect(load.title.isEmpty, isTrue);
      expect(load.busy, isFalse);
    });

    test('помилка Mikai потрапляє в errors, а решта джерел працює', () async {
      final site = ufdubSite(extra: {'api.mikai.me': const Resp('boom', status: 500)});
      final load = await settle(service(site).start(fairy));
      expect(load.title.errors.keys, ['mikai']);
      expect(load.title.errors['mikai'], isNotEmpty);
      expect(load.title.offers.map((o) => o.source.id), ['ufdub']);
    });

    test('ліцензований тайтл: прапорець і дані ліцензіата доходять до підсумку', () async {
      final player = jsonDecode(fixture('mikai_player.json')) as Map<String, dynamic>;
      (player['result'] as Map<String, dynamic>)['licensed'] = true;
      (player['result'] as Map<String, dynamic>)['license'] = {
        'licensee': 'Sony Pictures',
        'links': [
          {'title': 'Crunchyroll', 'url': 'https://www.crunchyroll.com/series/X'}
        ],
      };
      final site = FakeSite({'/anime/hikka:$slug': fixture('mikai_detail.json'), '/anime/7601/player': jsonEncode(player)});
      final load = await settle(service(site).start(kusuriya, searchOthers: false));
      expect(load.title.licensed, isTrue);
      expect(load.title.license, isNotNull);
      expect(load.title.license!.holder, 'Sony Pictures');
      expect(load.title.license!.links.single.url, 'https://www.crunchyroll.com/series/X');
    });

    test('UFDub: знаходить за назвою, запамʼятовує зіставлення й вдруге не шукає', () async {
      final site = ufdubSite();
      final store = memoryStore();
      final svc = service(site, store: store);
      final ufdub = svc.registry.byId('ufdub')!;
      final offer = await svc.searchOffer(ufdub, fairy);
      expect(offer, isNotNull);
      expect(offer!.anime.url, contains('/anime/21-'));
      expect(offer.groups.single.label, 'UFDub');
      expect(offer.groups.single.episodes.length, 12);
      expect(store.link(fairy.slug, 'ufdub')!.url, contains('21-hvist'));
      final searches = site.count('do=search');
      expect(searches, greaterThan(0));
      final again = await svc.searchOffer(ufdub, fairy);
      expect(again!.groups.single.episodes.length, 12);
      expect(site.count('do=search'), searches);
    });

    test('зіставлення, що зникло (404), перебудовується пошуком', () async {
      final site = ufdubSite(extra: {'ufdub.com/anime/999-': const Resp('нема', status: 404)});
      final store = memoryStore();
      store.setLink(fairy.slug, 'ufdub', const SAnime(url: '/anime/999-gone.html', title: 'Старе'));
      final svc = service(site, store: store);
      final offer = await svc.searchOffer(svc.registry.byId('ufdub')!, fairy);
      expect(offer!.anime.url, contains('/anime/21-'));
      expect(store.link(fairy.slug, 'ufdub')!.url, contains('/anime/21-'));
    });

    test('інший сезон не підставляється: «2 сезон» не збігається зі сторінкою «1 сезон»', () async {
      const second = HikkaAnime(slug: 'fairy-tail-2', titleUa: 'Хвіст Феї 2 сезон', titleEn: 'Fairy Tail 2nd Season', status: 'finished', episodesReleased: 12, episodesTotal: 12);
      final site = ufdubSite();
      final svc = service(site);
      final offer = await svc.searchOffer(svc.registry.byId('ufdub')!, second);
      expect(offer, isNull);
      expect(svc.store.link(second.slug, 'ufdub'), isNull);
    });

    test('searchOthers: false — пошук за назвою не запускається', () async {
      final site = ufdubSite(extra: {'/anime/hikka:': notFound, '/anime/mal:': notFound});
      await settle(service(site).start(kusuriya, searchOthers: false));
      expect(site.count('do=search'), 0);
    });

    test('вимкнене джерело не опитується', () async {
      var data = <String, dynamic>{};
      final prefs = SourcePrefs(load: () => data, save: (d) => data = d);
      prefs.setEnabled('ufdub', false);
      final site = ufdubSite(extra: {'/anime/hikka:': notFound, '/anime/mal:': notFound});
      final load = await settle(service(site, prefs: prefs).start(fairy));
      expect(site.count('do=search'), 0);
      expect(load.title.offers, isEmpty);
    });

    test('групування за озвучкою: порядок з джерела, серії за номером; без озвучки — під назвою сайту', () {
      final site = FakeSite({});
      final src = UfDubSource(http: site.http);
      final groups = WatchService.groupEpisodes(src, const SAnime(url: '/x', title: 'x'), [
        ep(2, voice: 'B'),
        ep(1, voice: 'B'),
        ep(1, voice: 'A'),
        ep(1),
      ]);
      expect(groups.map((g) => g.label), ['B', 'A', src.name]);
      expect(groups.first.episodes.map((e) => e.number), [1, 2]);
    });

    test('назви для зіставлення: укр., англ., ромаджі, оригінал і синоніми без повторів', () {
      const a = HikkaAnime(slug: 's', titleUa: 'Хвіст Феї', titleEn: 'Fairy Tail', titleJa: 'Fairy Tail', titleNative: 'フェアリーテイル', synonyms: ['fairy tail', 'FT']);
      expect(WatchService.titlesOf(a), ['Хвіст Феї', 'Fairy Tail', 'フェアリーテイル', 'FT']);
      expect(WatchService.queriesOf(a), ['Хвіст Феї', 'Fairy Tail']);
    });
  });

  group('вибір відео', () {
    final master = fixture('moon_master.m3u8');

    test('Moon першим, і якість за налаштуванням', () async {
      // сторінка плеєра Moon (шаблон PlayerJS) + майстер-плейлист
      final site = FakeSite({
        'moonanime.art/iframe/': fixture('moon_playerjs.html'),
        'hls:manifest.m3u8': master,
      });
      final src = MikaiSource(http: site.http);
      final e = SEpisode(
        url: 'https://moonanime.art/iframe/vp3fbhr2xrf1/',
        name: 'Серія 1',
        number: 1,
        data: '{"e":[["moon","https://moonanime.art/iframe/vp3fbhr2xrf1/"],["fenix","https://fenix.example/1"]]}',
      );
      final best = await const StreamResolver().resolve(src, e);
      expect(best.hoster, 'Moon');
      expect(best.video.title, '1080p');
      expect(best.qualities.map((v) => v.title), ['Авто', '1080p', '720p', '480p']);
      expect(best.timestamps.map((t) => t.type.name), ['opening', 'ending']);
      final low = await StreamResolver(maxHeight: () => 720).resolve(src, e);
      expect(low.video.title, '720p');
      final forced = await const StreamResolver().resolve(src, e, height: 480);
      expect(forced.video.title, '480p');
    });

    test('умова Moon: де є Moon, Ashdi не пропонується й не підставляється замість нього', () async {
      final site = FakeSite({
        'moonanime.art/iframe/': const Resp('boom', status: 500),
        'ashdi.vip/vod/': fixture('ashdi_vod.html'),
        'index.m3u8': fixture('ashdi_master.m3u8'),
      });
      final src = MikaiSource(http: site.http);
      final e = SEpisode(
        url: 'https://moonanime.art/iframe/x/',
        name: 'Серія 1',
        number: 1,
        data: '{"e":[["moon","https://moonanime.art/iframe/x/"],["ashdi","https://ashdi.vip/vod/292003"]]}',
      );
      expect([for (final h in StreamResolver.withoutAshdiWhereMoon(await src.hosters(e))) h.name], ['Moon']);
      await expectLater(
        StreamResolver(preferredHoster: () => 'Ashdi').resolve(src, e),
        throwsA(isA<SourceException>().having((x) => x.detail, 'detail', isNot(contains('Ashdi')))),
      );
    });

    test('Moon немає — Ashdi лишається єдиним плеєром', () async {
      final site = FakeSite({'ashdi.vip/vod/': fixture('ashdi_vod.html'), 'index.m3u8': fixture('ashdi_master.m3u8')});
      final src = MikaiSource(http: site.http);
      final e = SEpisode(url: 'https://ashdi.vip/vod/292003', name: 'Серія 1', number: 1, data: '{"e":[["ashdi","https://ashdi.vip/vod/292003"]]}');
      final r = await const StreamResolver().resolve(src, e);
      expect(r.hoster, 'Ashdi');
      expect(r.hosters, ['Ashdi']);
    });

    test('Moon не відкрився — зрозуміла помилка тільки про Moon', () async {
      final site = FakeSite({'moonanime.art/iframe/': const Resp('boom', status: 500), 'ashdi.vip': const Resp('boom', status: 500)});
      final src = MikaiSource(http: site.http);
      final e = SEpisode(
        url: 'https://moonanime.art/iframe/x/',
        name: 'Серія 1',
        data: '{"e":[["moon","https://moonanime.art/iframe/x/"],["ashdi","https://ashdi.vip/vod/1"]]}',
      );
      await expectLater(
        const StreamResolver().resolve(src, e),
        throwsA(isA<SourceException>()),
      );
    });
  });
}
