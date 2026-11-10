import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:miki_miki/models/source_models.dart';
import 'package:miki_miki/services/sources/extractors.dart';
import 'package:miki_miki/services/sources/source_http.dart';
import 'package:miki_miki/services/sources/ua/mikai_source.dart';

import 'support/fake_site.dart';

void main() {
  const slug = 'kusuriya-no-hitorigoto-zoku-hen-636673';

  group('розбір відповідей', () {
    final player = MikaiSource.playerFromJson(jsonDecode(fixture('mikai_player.json')) as Map<String, dynamic>);

    test('релізи: команди, озвучка/субтитри, кількість серій', () {
      expect(player.licensed, isFalse);
      expect(player.license, isNull);
      expect(player.releases.length, 11);
      expect(player.releases.map((r) => r.label), contains('Inari (суб.)'));
      expect(player.releases.first.label, 'TuTaZaSho');
      expect(player.releases.first.episodes.length, 4);
      expect(player.releases.where((r) => r.isSub).length, 3);
    });

    test('flatten: лише серії з плеєром, який ми вміємо відкрити; озвучка — підпис релізу', () {
      final eps = MikaiSource().flatten(player);
      expect(eps.length, 52); // 53 серій у релізах, одна лише з Fenix
      final first = eps.first;
      expect(first.voice, 'TuTaZaSho');
      expect(first.name, 'Серія 1');
      expect(first.number, 1);
      expect(first.url, startsWith('https://moonanime.'));
      // Fenix лишається у даних (на майбутнє), але плеєром не пропонується
      expect(embedsOf(first).map((e) => e.provider), containsAll(['fenix', 'moon']));
      expect(hostersFor(first).map((h) => h.name), ['Moon']);
    });

    test('порядок плеєрів: Moon раніше за Ashdi', () {
      final eps = MikaiSource().flatten(player);
      final inari = eps.firstWhere((e) => e.voice == 'Inari');
      expect(hostersFor(inari).map((h) => h.name), ['Moon', 'Ashdi']);
    });

    test('ліцензований тайтл: блок ліцензії розбирається без знання точної схеми', () {
      final p = MikaiSource.playerFromJson({
        'ok': true,
        'result': {
          'licensed': true,
          'license': {
            'licensee': 'Sony Pictures',
            'links': [
              {'title': 'Crunchyroll', 'url': 'https://www.crunchyroll.com/series/X'},
              {'name': 'Netflix', 'url': 'https://www.netflix.com/title/1'},
            ],
          },
          'releases': <Object>[],
        },
      });
      expect(p.licensed, isTrue);
      expect(p.license!.holder, 'Sony Pictures');
      expect(p.license!.links.map((l) => l.url), ['https://www.crunchyroll.com/series/X', 'https://www.netflix.com/title/1']);
      expect(p.license!.links.map((l) => l.title), ['Crunchyroll', 'Netflix']);
      expect(p.releases, isEmpty);
    });

    test('картка зі списку', () {
      final j = jsonDecode(fixture('mikai_search.json')) as Map<String, dynamic>;
      final a = MikaiSource.animeFromJson((j['result'] as List).first as Map);
      expect(a.title, 'Монолог травниці');
      expect(a.url, '8');
      expect(a.originalTitle, 'Kusuriya no Hitorigoto');
      expect(a.thumbnailUrl, allOf(startsWith('https://images.mikai.me/'), contains('poster/small/')));
    });
  });

  group('запити', () {
    test('byHikka: запис знайдено → SAnime з зіставленням; нема → null', () async {
      final site = FakeSite({
        '/anime/hikka:$slug': fixture('mikai_detail.json'),
        '/anime/hikka:nope': const Resp('{"ok":false,"error":{"code":"not_found","message":"x"}}', status: 404),
      });
      final s = MikaiSource(http: site.http);
      final a = await s.byHikka(slug);
      expect(a, isNotNull);
      expect(a!.url, '7601');
      expect(a.title, 'Монолог травниці - 3 сезон');
      expect(a.originalTitle, 'Kusuriya no Hitorigoto 3rd Season');
      expect(a.status, SAnimeStatus.ongoing);
      expect(a.year, 2026);
      expect(a.episodesAired, 5);
      expect(a.episodesTotal, 12);
      expect(a.author, 'OLM');
      expect(await s.byHikka('nope'), isNull);
    });

    test('кеш: повторний запит у межах ttl не йде в мережу, після ttl — йде', () async {
      var now = DateTime(2026, 11, 3, 8);
      final site = FakeSite({'/anime/hikka:$slug': fixture('mikai_detail.json')});
      final s = MikaiSource(http: site.http, now: () => now);
      await s.byHikka(slug);
      await s.byHikka(slug);
      expect(site.count('/anime/hikka:'), 1);
      now = now.add(const Duration(minutes: 11));
      await s.byHikka(slug);
      expect(site.count('/anime/hikka:'), 2);
    });

    test('ключ API передається заголовком, а без нього — ні', () async {
      final site = FakeSite({'/anime': fixture('mikai_search.json')});
      await MikaiSource(http: site.http, apiKey: 'secret').popular(1);
      expect(site.log.single.headers['X-API-Key'], 'secret');
      final site2 = FakeSite({'/anime': fixture('mikai_search.json')});
      await MikaiSource(http: site2.http).popular(1);
      expect(site2.log.single.headers.containsKey('X-API-Key'), isFalse);
    });

    test('каталог: сторінки й пошук', () async {
      final site = FakeSite({'/anime?': fixture('mikai_search.json')});
      final s = MikaiSource(http: site.http);
      final page = await s.search(1, 'Монолог');
      expect(page.animes.length, 3);
      expect(page.hasNextPage, isFalse); // pages == 1
      expect(site.log.single.url.queryParameters['search'], 'Монолог');
      expect(site.log.single.url.queryParameters['page'], '1');
    });

    test('ліміт запитів (429) → rateLimited', () async {
      final site = FakeSite({'/anime': const Resp('{"ok":false,"error":{"code":"rate_limited"}}', status: 429)});
      expect(
        MikaiSource(http: site.http).popular(1),
        throwsA(isA<SourceException>().having((e) => e.kind, 'kind', SourceErrorKind.rateLimited)),
      );
    });

    test('команда: опис і посилання на соцмережі', () async {
      final site = FakeSite({'/teams/2': fixture('mikai_team.json')});
      final info = await MikaiSource(http: site.http).teamInfo(const MikaiTeam(2, 'fanvoxua', 'FanVoxUA'));
      expect(info.team.name, 'FanVoxUA');
      expect(info.team.avatarUrl, startsWith('https://images.mikai.me/avatar/small/'));
      expect(info.description, contains('любительського озвучення'));
      expect(info.links.keys, containsAll(['telegram', 'instagram', 'youtube']));
      expect(info.links['telegram'], 'https://t.me/fanvoxua_re');
      expect(info.pageUrl, 'https://mikai.me/team/fanvoxua');
    });

    test('episodes: усі релізи, впорядковано за озвучкою й номером', () async {
      final site = FakeSite({'/anime/7601/player': fixture('mikai_player.json')});
      final eps = await MikaiSource(http: site.http).episodes(const SAnime(url: '7601', title: 'x'));
      expect(eps.length, 52); // 53 серій у релізах, одна лише з Fenix
      for (int i = 1; i < eps.length; i++) {
        final a = eps[i - 1], b = eps[i];
        final c = (a.voice ?? '').compareTo(b.voice ?? '');
        expect(c < 0 || (c == 0 && (a.number ?? 0) <= (b.number ?? 0)), isTrue, reason: '${a.voice} ${a.number} → ${b.voice} ${b.number}');
      }
    });
  });
}
