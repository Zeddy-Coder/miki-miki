// «Продовжити перегляд» як список «Дивлюсь»: порядок за переглядом, тайтли поза списком, «Нова серія» лише в обраній
// озвучці; пріоритет команд для кнопки «Дивитись».
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:miki_miki/models/hikka_models.dart';
import 'package:miki_miki/models/source_models.dart';
import 'package:miki_miki/services/continue_watching.dart';
import 'package:miki_miki/services/hikka_api.dart';
import 'package:miki_miki/services/hikka_auth.dart';
import 'package:miki_miki/services/hikka_lists.dart';
import 'package:miki_miki/services/storage_service.dart';
import 'package:miki_miki/services/watch_models.dart';
import 'package:miki_miki/services/episode_check.dart';
import 'package:miki_miki/services/watch_service.dart';
import 'package:miki_miki/services/watch_store.dart';

import 'support/hikka_account_fakes.dart';
import 'support/remote_fakes.dart';
import 'support/hikka_fakes.dart';

const String ongoingSlug = 'kyouran-reijou-nia-liston-byoujaku-reijou-ni-tensei-shita-kamigoroshi-no-bujin-no-karei-naru-musouroku-d98982';

SEpisode ep(int n) => SEpisode(url: 'u$n', name: 'Серія $n', number: n.toDouble());
WatchGroup vg(String id, String label, int count) =>
    WatchGroup(id: id, sourceId: 'mikai', label: label, episodes: [for (var i = 1; i <= count; i++) ep(i)]);

void main() {
  late int clock;
  late WatchStore store;

  setUp(() {
    clock = 1000;
    store = WatchStore(load: () => {}, save: (_) {}, now: () => DateTime.fromMillisecondsSinceEpoch(clock += 1000));
  });

  group('кількість серій у обраній озвучці', () {
    test('зберігається, а для іншої озвучки не береться', () {
      store.setLast('hikka:a', '3', 'mikai|x|1');
      store.setAvailable('hikka:a', 'mikai|x|1', 'Inari', 5);
      expect(ContinueWatching.dubOf(store, 'hikka:a'), (5, 'Inari', 5));
      store.setLast('hikka:a', '3', 'mikai|x|2'); // перейшов на іншу команду
      expect(ContinueWatching.dubOf(store, 'hikka:a').$1, isNull, reason: 'дані попередньої команди не підходять');
      expect(ContinueWatching.dubOf(store, 'hikka:none').$1, isNull);
    });

    final base = HikkaAnime.fromJson(sampleMap('info.json'));
    HikkaAnime withStatus(String st) => HikkaAnime.fromJson({...sampleMap('info.json'), 'status': st});
    ContinueItem item({String status = 'ongoing', required int watched, int? count, int? prev}) =>
        ContinueItem(anime: withStatus(status), episodeKey: '1', at: DateTime(2026), watched: watched, dubCount: count, dubPrev: prev);

    test('«Нова серія»: лише коли озвучку обрано, лише онґоїнг і лише якщо глядач був наздогнаний', () {
      expect(base, isNotNull);
      expect(item(watched: 3).hasNew, isFalse, reason: 'озвучку не обирали');
      expect(item(watched: 5, count: 6, prev: 5).hasNew, isTrue, reason: 'дивився до кінця, вийшла 6-та');
      expect(item(watched: 5, count: 5, prev: 5).hasNew, isFalse, reason: 'нічого нового');
      expect(item(watched: 3, count: 6, prev: 5).hasNew, isFalse, reason: 'не додивився попередні (3 з 5): нова не показується');
      expect(item(watched: 3, count: 5, prev: 5).hasNew, isFalse, reason: 'є що доглядати, але це не «нова»');
      expect(item(watched: 5, count: 7, prev: 6).hasNew, isFalse, reason: 'вийшли дві: 6-ту не бачив');
      expect(item(status: 'finished', watched: 5, count: 6, prev: 5).hasNew, isFalse, reason: 'не онґоїнг');
    });

    test('prev у сховищі: перший запис, збільшення, повтор і зміна озвучки', () {
      store.setAvailable('hikka:a', 'g1', 'X', 5);
      expect(store.available('hikka:a')!.prev, 5);
      store.setAvailable('hikka:a', 'g1', 'X', 6);
      expect(store.available('hikka:a')!.prev, 5, reason: 'до збільшення було 5');
      store.setAvailable('hikka:a', 'g1', 'X', 6);
      expect(store.available('hikka:a')!.prev, 5, reason: 'повтор не зсуває');
      store.setAvailable('hikka:a', 'g1', 'X', 7);
      expect(store.available('hikka:a')!.prev, 6);
      store.setAvailable('hikka:a', 'g2', 'Y', 7);
      expect(store.available('hikka:a')!.prev, 7, reason: 'інша озвучка: відлік заново');
    });

    test('запис не сповіщає, поки нічого не змінилось', () {
      var n = 0;
      store.addListener(() => n++);
      store.setAvailable('hikka:a', 'g', 'Inari', 5);
      store.setAvailable('hikka:a', 'g', 'Inari', 5);
      expect(n, 1);
      store.setAvailable('hikka:a', 'g', 'Inari', 6);
      expect(n, 2);
    });
  });

  test('знайомі команди запам\'ятовуються без повторів, найновіші першими', () {
    StorageService.rememberTeams(['Inari', 'FanVoxUA']);
    StorageService.rememberTeams(['inari', ' ', 'Glass Moon']);
    expect(StorageService.getKnownTeams().take(3), ['Glass Moon', 'inari', 'FanVoxUA']);
  });

  group('«Дивитись»/продовження: озвучка, де є наступна серія', () {
    WatchGroup g(String id, String label, int n, {int from = 1}) =>
        WatchGroup(id: id, sourceId: 'mikai', label: label, episodes: [for (var i = from; i < from + n; i++) ep(i)]);
    WatchLoad load(List<WatchGroup> groups) {
      final l = WatchLoad(animeKey: 'hikka:a', hikka: const HikkaEpisodeInfo(), order: const [], store: store);
      l.addOfferForTest(WatchOffer(source: FakeSource('mikai', const {}), anime: const SAnime(url: 'a', title: 'A'), groups: groups));
      return l;
    }

    test('озвучка без наступної серії не береться, якщо є повніша', () {
      store.setPinnedGroup('hikka:a', 'short');
      final l = load([g('short', 'Amanogawa', 9), g('full', 'Рідний Голос', 19)]);
      expect(l.defaultGroup(store)!.id, 'short', reason: 'нічого не дивились — лишається обрана');
      expect(l.defaultGroup(store, seen: 11)!.id, 'full', reason: 'на Hikka переглянуто 11, а в обраній лише 9');
      expect(l.defaultGroup(store, seen: 5)!.id, 'short', reason: '6-та в обраній є');
    });

    test('серед тих, де є наступна серія, вибір за пріоритетом, а не просто перший зі знайдених', () {
      StorageService.saveWatchTeamPriority(['Glass Moon', 'Inari']);
      final l = load([g('a', 'Amanogawa', 9), g('i', 'Inari', 19), g('m', 'Glass Moon', 15), g('f', 'FanVoxUA', 19)]);
      store.setPinnedGroup('hikka:a', 'a'); // обрана раніше, але в ній лише 9 серій
      expect(l.defaultGroup(store, seen: 11)!.id, 'm', reason: 'Glass Moon першою в пріоритеті й має 12-ту');
      expect(l.defaultGroup(store, seen: 16)!.id, 'i', reason: 'у Glass Moon лише 15 серій: наступна за пріоритетом — Inari');
      expect(l.defaultGroup(store, seen: 3)!.id, 'a', reason: 'у обраній для тайтлу 4-та є, тож лишається вона');
      StorageService.saveWatchTeamPriority([]);
    });

    test('перевіряється номер серії, а не кількість: «10 з 19» може містити 12-ту', () {
      final l = load([g('part', 'Далі Буде', 10, from: 3), g('full', 'Clan Kaizoku', 19)]);
      expect(g('part', 'x', 10, from: 3).hasEpisode(12), isTrue);
      expect(g('part', 'x', 10).hasEpisode(12), isFalse);
      StorageService.saveWatchTeamPriority(['Далі Буде']);
      expect(l.defaultGroup(store, seen: 11)!.id, 'part', reason: '12-та є в «Далі Буде» (серії 3–12, нумерація з ⚠), а він першим у пріоритеті: свідомий вибір сильніший за позначку');
      final l2 = load([g('part', 'Далі Буде', 10), g('full', 'Clan Kaizoku', 19)]);
      expect(l2.defaultGroup(store, seen: 11)!.id, 'full', reason: 'у «Далі Буде» серії 1–10: 12-ї немає');
      StorageService.saveWatchTeamPriority([]);
    });

    test('продовження за номерами: у озвучці з серіями 3–12 після 11 відкривається 12-та', () {
      final keys = ['3', '4', '5', '6', '7', '8', '9', '10', '11', '12'];
      expect(continuePoint(keys, <String>{}, null, hikkaEpisodes: 11).epKey, '12');
      expect(continuePoint(keys, <String>{}, '3', hikkaEpisodes: 11).epKey, '12', reason: 'остання відкрита (3) уже переглянута');
    });

    test('якщо наступної серії немає ніде — лишається звичайний вибір', () {
      final l = load([g('a', 'A', 9), g('b', 'B', 12)]);
      expect(l.defaultGroup(store, seen: 19), isNotNull);
    });
  });

  group('порядок озвучок у списках', () {
    WatchGroup g(String id, String label, int n, {bool sub = false}) =>
        WatchGroup(id: id, sourceId: 'mikai', label: label, isSub: sub, episodes: [for (var i = 1; i <= n; i++) ep(i)]);

    test('спершу пріоритет за порядком, далі озвучення, кількість серій, алфавіт', () {
      final gs = [g('1', 'Бета', 10), g('2', 'Алфа', 10), g('3', 'Inari', 5), g('4', 'FanVox', 12), g('5', 'Субтитри X (суб.)', 19, sub: true), g('6', 'Glass Moon', 3)];
      final sorted = sortGroups(gs, priority: ['glass moon', 'inari']).map((x) => x.id).toList();
      expect(sorted, ['6', '3', '4', '2', '1', '5'], reason: 'пріоритет 1-2, далі 12 → 10 (алфавіт: Алфа, Бета) → субтитри');
      expect(sortGroups(gs).map((x) => x.id), ['4', '2', '1', '3', '6', '5']);
    });

    test('сортування стабільне для повністю рівних', () {
      final gs = [g('a', 'Same', 5), g('b', 'Same', 5)];
      expect(sortGroups(gs).map((x) => x.id), ['a', 'b']);
    });
  });

  group('пріоритет команд', () {
    final groups = [vg('a', 'FanVoxUA', 12), vg('b', 'Inari', 12), vg('c', 'Glass Moon', 12)];

    test('береться перша за списком команда, що озвучила тайтл', () {
      expect(pickGroup(groups, priority: ['glass moon', 'inari']).id, 'c');
      expect(pickGroup(groups, priority: ['ніхто', 'INARI']).id, 'b');
    });

    test('вибір для тайтлу важливіший, а без збігів — як раніше', () {
      expect(pickGroup(groups, preferredId: 'a', priority: ['inari']).id, 'a');
      expect(pickGroup(groups, priority: ['ніхто']).id, 'a');
      expect(pickGroup(groups, priority: ['inari'], favorites: ['v:mikai:glass moon']).id, 'b', reason: 'список пріоритетів над «улюбленими»');
    });
  });

  group('load: список «Дивлюсь» + перегляди поза списком', () {
    test('порядок за останнім переглядом, позначка «не в списку», онґоїнг без нових серій лишається', () async {
      final animeJson = sampleMap('info.json');
      final slug = animeJson['slug'] as String;
      final server = FakeAccountApi();
      final api = HikkaApi(sender: server.call, retryDelay: Duration.zero);
      var disk = <String, dynamic>{'token': 'tok', 'me': Map<String, dynamic>.of(kMe)};
      final auth = HikkaAuth(api: api, load: () => disk, save: (d) => disk = Map<String, dynamic>.of(d), urlOpener: (_) async => true);
      Map<String, dynamic> entry(Map<String, dynamic> a, int eps, int updated) => {
            'reference': 'w',
            'note': null,
            'updated': updated,
            'created': 1,
            'status': 'watching',
            'rewatches': 0,
            'duration': 0,
            'episodes': eps,
            'score': 0,
            'start_date': null,
            'end_date': null,
            'anime': a,
          };
      server.routes['POST /watch/tester/list'] = (r) {
        final status = server.bodyOf(r)['watch_status'] as String;
        return FakeAccountApi.ok({
          'pagination': {'total': 1, 'pages': 1, 'page': 1},
          'list': status == 'watching' ? [entry(animeJson, 2, 50)] : [],
        });
      };
      final lists = HikkaMyList(auth: auth, api: api);
      final fake = FakeHikka();
      final catalog = HikkaApi(sender: fake.call, retryDelay: Duration.zero);

      // Локально дивились ще й інший тайтл, якого немає в списках, — пізніше за «Дивлюсь»
      store
        ..setLast('hikka:$slug', '2', 'mikai|x|1') // раніше
        ..setLast('hikka:$ongoingSlug', '3', 'g'); // пізніше, поза списком
      final items = await ContinueWatching.load(store: store, api: HikkaApi(sender: (r) async {
        final path = r.url.path;
        if (path.contains('/watch/')) return server.call(r);
        return fake.call(r);
      }, retryDelay: Duration.zero), auth: auth, lists: lists);
      expect(items.map((i) => i.anime.slug), [ongoingSlug, slug], reason: 'свіжіший перегляд попереду');
      expect(items.first.notInList, isTrue);
      expect(items.last.notInList, isFalse);
      expect(items.last.hasNew, isFalse, reason: 'озвучку ще не обирали — «нової серії» не вигадуємо');
      expect(catalog, isNotNull);
      expect(jsonEncode(items.length), '2');
    });
  });

  group('охоплення серій і неповні озвучки', () {
    WatchGroup rg(String id, String label, List<int> nums) =>
        WatchGroup(id: id, sourceId: 'mikai', label: label, episodes: [for (final n in nums) ep(n)]);

    test('діапазони: 1–10, 10–19, 1–5, 7–19', () {
      expect(rg('a', 'A', [for (var i = 1; i <= 10; i++) i]).coverage, '1–10');
      expect(rg('a', 'A', [for (var i = 10; i <= 19; i++) i]).coverage, '10–19');
      expect(rg('a', 'A', [1, 2, 3, 4, 5, ...[for (var i = 7; i <= 19; i++) i]]).coverage, '1–5, 7–19');
      expect(rg('a', 'A', [3]).coverage, '3');
      expect(rg('a', 'A', [1, 2]).isPartial, isFalse);
      expect(rg('a', 'A', [10, 11]).isPartial, isTrue);
      expect(rg('a', 'A', [1, 2, 4]).isPartial, isTrue);
    });

    WatchLoad mk(List<WatchGroup> gs, {int? total}) {
      final l = WatchLoad(animeKey: 'hikka:a', hikka: HikkaEpisodeInfo(total: total, released: total, finished: total != null), order: const [], store: store);
      l.addOfferForTest(WatchOffer(source: FakeSource('mikai', const {}), anime: const SAnime(url: 'a', title: 'A'), groups: gs));
      return l;
    }

    List<int> r(int a, int b) => [for (var i = a; i <= b; i++) i];

    test('за пріоритетом: неповна озвучка змінюється на наступну, щойно в ній є потрібна серія; повна без пріоритету — остання', () {
      StorageService.saveWatchTeamPriority(['Далі Буде', 'Amanogawa']);
      StorageService.savePreferFullDub(false);
      final db = rg('db', 'Далі Буде', r(10, 19));
      final am = rg('am', 'Amanogawa', r(1, 9));
      final ck = rg('ck', 'Clan Kaizoku', r(1, 19));
      final l = mk([ck, am, db]);
      expect(l.title.groups.map((g) => g.id), ['db', 'am', 'ck']);
      expect(l.defaultGroup(store, seen: 0)!.id, 'am');
      expect(l.defaultGroup(store, seen: 5)!.id, 'am');
      expect(l.defaultGroup(store, seen: 9)!.id, 'db', reason: '10-та є лише в Далі Буде (і в повній, але вона нижча в пріоритеті)');
      StorageService.saveWatchTeamPriority([]);
    });

    test('«Спершу повні озвучення»: повна вище за неповні, хоч би де вони були в пріоритеті', () {
      StorageService.saveWatchTeamPriority(['Далі Буде', 'Amanogawa']);
      StorageService.savePreferFullDub(true);
      final db = rg('db', 'Далі Буде', r(10, 19));
      final am = rg('am', 'Amanogawa', r(1, 9));
      final ck = rg('ck', 'Clan Kaizoku', r(1, 19));
      final l = mk([ck, am, db]);
      expect(l.title.groups.map((g) => g.id), ['ck', 'db', 'am']);
      expect(l.defaultGroup(store, seen: 5)!.id, 'ck');
      StorageService.savePreferFullDub(false);
      StorageService.saveWatchTeamPriority([]);
    });

    test('обрана вручну озвучка сильніша за пріоритет, але без наступної серії — попередження з варіантами', () {
      StorageService.saveWatchTeamPriority(['Далі Буде', 'Amanogawa']);
      StorageService.savePreferFullDub(false);
      final db = rg('db', 'Далі Буде', r(10, 19));
      final am = rg('am', 'Amanogawa', r(1, 9));
      final ck = rg('ck', 'Clan Kaizoku', r(1, 19));
      final l = mk([ck, am, db]);
      store.setPinnedGroup('hikka:a', 'ck');
      expect(l.defaultGroup(store, seen: 5)!.id, 'ck', reason: 'ручний вибір');
      expect(l.missingNext(store, seen: 5), isNull);
      store.setPinnedGroup('hikka:a', 'am');
      expect(l.defaultGroup(store, seen: 5)!.id, 'am');
      expect(l.defaultGroup(store, seen: 9)!.id, 'db', reason: 'в Amanogawa немає 10-ї');
      final plan = l.missingNext(store, seen: 9)!;
      expect(plan.pinned.id, 'am');
      expect(plan.byPriority.id, 'db');
      expect(plan.full!.id, 'ck');
      store.clearPinnedGroup('hikka:a');
      expect(l.missingNext(store, seen: 9), isNull);
      StorageService.saveWatchTeamPriority([]);
    });

    test('зайва серія (OVA, номер більший за кількість на Hikka) не робить інші озвучки неповними', () {
      final plain = rg('p', 'A', r(1, 12));
      final ova = WatchGroup(id: 'o', sourceId: 'mikai', label: 'B', episodes: [for (final n in r(1, 12)) ep(n), const SEpisode(url: 'x', name: 'OVA 1', number: 13)]);
      final over = rg('v', 'C', r(1, 14));
      expect(plain.isIncomplete(maxEpisodeOf([plain, ova], limit: 12)), isFalse);
      expect(ova.isIncomplete(maxEpisodeOf([plain, ova], limit: 12)), isFalse, reason: 'OVA не в рахунку');
      expect(plain.isIncomplete(maxEpisodeOf([plain, over], limit: 12)), isFalse, reason: 'ліміт Hikka — 12');
      expect(plain.isIncomplete(maxEpisodeOf([plain, ova])), isFalse, reason: 'без ліміту OVA за назвою теж не рахується');
      expect(plain.coverage, '1–12');
      expect(ova.coverage, '1–12');
    });
  });
}
