// Живі перевірки джерел (потрібна мережа). Запуск: LIVE=1 flutter test test/sources_live_test.dart
// (PowerShell: $env:LIVE=1; flutter test test/sources_live_test.dart). За звичайного `flutter test` усе пропускається.
// Транспорт — той самий, що в застосунку (`dart:io`); у пісочниці без `dart:io`-доступу ставимо ще й LIVE_CURL=1.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:miki_miki/services/sources/extractors.dart';
import 'package:miki_miki/services/sources/source_http.dart';
import 'package:miki_miki/services/sources/ua/mikai_source.dart';
import 'package:miki_miki/services/sources/ua/uakino_source.dart';
import 'package:miki_miki/services/sources/ua/ufdub_source.dart';

import 'support/curl_sender.dart';

void main() {
  final skip = Platform.environment['LIVE'] == null ? 'потрібен LIVE=1 і мережа' : false;
  SourceHttp newHttp() => Platform.environment['LIVE_CURL'] == null ? SourceHttp() : SourceHttp(sender: curlSender());

  test('UFDub: популярне → сторінка → серії → відео', () async {
    final s = UfDubSource(http: newHttp());
    final page = await s.popular(1);
    // ignore: avoid_print
    print('UFDub popular: ${page.animes.length}, next=${page.hasNextPage}; first=${page.animes.first}');
    expect(page.animes.length, greaterThan(6));
    expect(page.hasNextPage, isTrue);
    final fairy = page.animes.firstWhere((a) => a.url.contains('21-hvist-feji'), orElse: () => page.animes.last);
    final d = await s.details(fairy);
    // ignore: avoid_print
    print('details: ${d.title} | ${d.originalTitle} | ${d.author} | ${d.genres} | ${d.year} | desc=${d.description?.length}');
    expect(d.description, isNotEmpty);
    final eps = await s.episodes(d);
    // ignore: avoid_print
    print('episodes: ${eps.length}; first=${eps.first}; last=${eps.last}');
    expect(eps, isNotEmpty);
    final v = await s.videos(eps.first);
    // ignore: avoid_print
    print('video: ${v.first.url}');
    expect(v.single.url, startsWith('https://'));
    final lat = await s.latest(1);
    expect(lat.animes, isNotEmpty);
    final found = await s.search(1, 'Хвіст Феї');
    // ignore: avoid_print
    print('search: ${found.animes.map((a) => a.title).toList()}');
    expect(found.animes, isNotEmpty);
  }, skip: skip, timeout: const Timeout(Duration(minutes: 4)));

  test('Mikai: Hikka-slug → релізи → серії → відео (Moon/Ashdi) → команда', () async {
    final s = MikaiSource(http: newHttp());
    final a = await s.byHikka('kusuriya-no-hitorigoto-zoku-hen-636673');
    expect(a, isNotNull);
    // ignore: avoid_print
    print('mikai: ${a!.title} id=${a.url} eps=${a.episodesAired}/${a.episodesTotal}');
    final p = await s.player(a);
    // ignore: avoid_print
    print('releases: ${p.releases.map((r) => '${r.label}(${r.episodes.length})').toList()}');
    expect(p.releases, isNotEmpty);
    final eps = s.flatten(p);
    expect(eps, isNotEmpty);
    for (final provider in ['moon', 'ashdi']) {
      final ep = eps.firstWhere((e) => embedsOf(e).any((m) => m.provider == provider && VideoExtractors.forUrl(m.url) != null), orElse: () => eps.first);
      final hs = hostersFor(ep).where((h) => h.name.toLowerCase() == provider).toList();
      if (hs.isEmpty) continue;
      final vids = await hosterVideosOf(s.http, hs.first, referer: 'https://mikai.me/');
      // ignore: avoid_print
      print('$provider → ${vids.map((v) => v.title).toList()}  ${vids.last.url.substring(0, 80)}…');
      expect(vids.length, greaterThanOrEqualTo(2));
      // перший варіант справді відкривається
      final r = await s.http.get(vids[1].url, headers: vids[1].headers);
      expect(r.text, contains('#EXTM3U'));
    }
    final t = await s.teamInfo(p.releases.first.teams.first);
    // ignore: avoid_print
    print('team: ${t.team.name} links=${t.links.keys.toList()} anime=${t.animeCount}');
    expect(t.team.name, isNotEmpty);
    final sr = await s.search(1, 'Монолог травниці');
    expect(sr.animes, isNotEmpty);
    final pop = await s.popular(1);
    expect(pop.animes.length, greaterThan(10));
    expect(await s.byHikka('такого-slug-нема-123'), isNull);
  }, skip: skip, timeout: const Timeout(Duration(minutes: 4)));

  // Єдине джерело, яке не вдалося перевірити наживо під час розробки (сайт за Cloudflare, з пісочниці був недоступний).
  test('UAKino: популярне → картка → серії → відео → пошук', () async {
    final s = UaKinoSource(http: newHttp());
    try {
      final page = await s.popular(1);
      // ignore: avoid_print
      print('UAKino popular: ${page.animes.length}, next=${page.hasNextPage}; first=${page.animes.first}');
      expect(page.animes, isNotEmpty);
      final d = await s.details(page.animes.first);
      // ignore: avoid_print
      print('details: ${d.title} | ${d.originalTitle} | ${d.genres} | ${d.year} | desc=${d.description?.length}');
      final eps = await s.episodes(d);
      // ignore: avoid_print
      print('episodes: ${eps.length}; first=${eps.isEmpty ? null : eps.first}');
      expect(eps, isNotEmpty);
      final v = await s.videos(eps.first);
      // ignore: avoid_print
      print('video: ${v.map((x) => '${x.title} ${x.url}').toList()}');
      expect(v, isNotEmpty);
      final found = await s.search(1, 'Хвіст Феї');
      // ignore: avoid_print
      print('search: ${found.animes.map((a) => a.title).toList()}');
      expect(found.animes, isNotEmpty);
    } on SourceException catch (e) {
      fail('UAKino: ${e.kind.name} (HTTP ${e.status}) — ${e.detail}. Якщо це «blocked», а в браузері сайт просить перевірку, потрібен обхід Cloudflare.');
    }
  }, skip: skip, timeout: const Timeout(Duration(minutes: 4)));
}
