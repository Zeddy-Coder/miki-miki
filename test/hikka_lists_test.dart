import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:miki_miki/models/hikka_models.dart';
import 'package:miki_miki/models/hikka_user_models.dart';
import 'package:miki_miki/services/hikka_api.dart';
import 'package:miki_miki/services/hikka_auth.dart';
import 'package:miki_miki/services/hikka_lists.dart';

import 'support/hikka_account_fakes.dart';
import 'support/hikka_fakes.dart';

const String slug = 'sousou-no-frieren-ad4e3e';

void main() {
  late FakeAccountApi server;
  late HikkaApi api;
  late Map<String, dynamic> store;
  late HikkaAuth auth;
  late HikkaMyList list;
  late Map<String, dynamic> animeJson;

  Map<String, dynamic> watchJson({String status = 'watching', int episodes = 0, int score = 0, String? note, int? start}) => {
        'reference': 'w-1',
        'note': note,
        'updated': 10,
        'created': 5,
        'status': status,
        'rewatches': 0,
        'duration': 0,
        'episodes': episodes,
        'score': score,
        'start_date': start,
        'end_date': null,
        'anime': animeJson,
      };

  /// Сервер «зберігає» те, що йому надіслали
  void serveWatch({Map<String, dynamic>? existing}) {
    server.routes['GET /watch/$slug'] = (r) => existing == null ? FakeAccountApi.fail(404, 'watch:not_found') : FakeAccountApi.ok(existing);
    server.routes['PUT /watch/$slug'] = (r) {
      final b = server.bodyOf(r);
      return FakeAccountApi.ok(watchJson(
        status: b['status'] as String,
        episodes: b['episodes'] as int,
        score: b['score'] as int? ?? 0,
        note: b['note'] as String?,
      ));
    };
    server.routes['DELETE /watch/$slug'] = (r) => FakeAccountApi.ok({'success': true});
  }

  Map<String, dynamic> put() => server.bodyOf(server.of('PUT', '/watch/$slug').single);

  setUp(() {
    animeJson = sampleMap('info.json');
    server = FakeAccountApi();
    api = HikkaApi(sender: server.call, retryDelay: Duration.zero);
    store = {'token': 'tok', 'me': Map<String, dynamic>.of(kMe)};
    auth = HikkaAuth(api: api, load: () => store, save: (d) => store = Map<String, dynamic>.of(d), urlOpener: (_) async => true);
    list = HikkaMyList(auth: auth, api: api);
  });

  group('статуси для позначок', () {
    Map<String, dynamic> page(List<Map<String, dynamic>> items, {int pages = 1}) => {
          'pagination': {'total': items.length, 'pages': pages, 'page': 1},
          'list': items,
        };

    test('проходить усі списки, запам’ятовує статус кожного тайтлу; запис зі збереження важливіший', () async {
      server.routes['POST /watch/tester/list'] = (r) {
        final status = server.bodyOf(r)['watch_status'] as String;
        return FakeAccountApi.ok(page(status == 'completed' ? [watchJson(status: 'completed')] : []));
      };
      expect(list.statusOf(slug), isNull);
      await list.loadIndex();
      expect(list.statusOf(slug), HikkaWatchStatus.completed);
      expect(list.statusOf('other'), isNull);
      expect(server.of('POST', '/watch/tester/list'), hasLength(HikkaWatchStatus.values.length));
      await list.loadIndex();
      expect(server.of('POST', '/watch/tester/list'), hasLength(HikkaWatchStatus.values.length), reason: 'вдруге з памʼяті');

      serveWatch(existing: watchJson(status: 'completed'));
      await list.save(slug, status: HikkaWatchStatus.dropped);
      expect(list.statusOf(slug), HikkaWatchStatus.dropped);
      await list.remove(slug);
      expect(list.statusOf(slug), isNull);
    });

    test('статуси зберігаються на диск: наступний запуск показує позначки одразу й не йде в мережу, поки дані свіжі', () async {
      var disk = <String, dynamic>{};
      HikkaMyList make() => HikkaMyList(auth: auth, api: api, load: () => disk, save: (d) => disk = Map<String, dynamic>.of(d));
      server.routes['POST /watch/tester/list'] = (r) {
        final status = server.bodyOf(r)['watch_status'] as String;
        return FakeAccountApi.ok(page(status == 'completed' ? [watchJson(status: 'completed')] : []));
      };
      final first = make();
      await first.loadIndex();
      expect(first.statusOf(slug), HikkaWatchStatus.completed);
      expect(disk['user'], 'tester');
      final requests = server.of('POST', '/watch/tester/list').length;

      final second = make(); // «новий запуск»
      await second.loadIndex();
      expect(second.statusOf(slug), HikkaWatchStatus.completed, reason: 'з диска');
      expect(server.of('POST', '/watch/tester/list'), hasLength(requests), reason: 'свіжі дані — без запитів');

      // Дані застарілі: позначки є одразу, а мережа оновлює їх
      disk = {...disk, 'at': DateTime.now().subtract(HikkaMyList.indexMaxAge + const Duration(minutes: 1)).millisecondsSinceEpoch};
      final third = make();
      await third.loadIndex();
      expect(third.statusOf(slug), HikkaWatchStatus.completed);
      expect(server.of('POST', '/watch/tester/list').length, greaterThan(requests));

      // Збережене іншого користувача не підхоплюється
      disk = {...disk, 'user': 'someone'};
      final other = make();
      server.routes['POST /watch/tester/list'] = (r) => FakeAccountApi.ok(page([]));
      await other.loadIndex();
      expect(other.statusOf(slug), isNull);
    });

    test('зміна статусу з застосунку одразу потрапляє в збережені', () async {
      var disk = <String, dynamic>{};
      final l = HikkaMyList(auth: auth, api: api, load: () => disk, save: (d) => disk = Map<String, dynamic>.of(d));
      server.routes['POST /watch/tester/list'] = (r) => FakeAccountApi.ok(page([]));
      await l.loadIndex();
      serveWatch();
      await l.save(slug, status: HikkaWatchStatus.planned);
      expect((disk['map'] as Map)[slug], 'planned');
      await l.remove(slug);
      expect((disk['map'] as Map).containsKey(slug), isFalse);
    });

    test('помилка мережі не фатальна, без входу статусів немає', () async {
      server.routes['POST /watch/tester/list'] = (r) => FakeAccountApi.fail(500, 'system:internal');
      await list.loadIndex();
      expect(list.statusOf(slug), isNull);
      await auth.signOut();
      expect(list.statusOf(slug), isNull);
    });
  });

  group('запис про тайтл', () {
    test('якщо тайтлу немає у списках — null, і це запам’ятовується', () async {
      serveWatch();
      expect(list.knows(slug), isFalse);
      expect(await list.entry(slug), isNull);
      expect(list.knows(slug), isTrue);
      await list.entry(slug);
      expect(server.of('GET', '/watch/$slug'), hasLength(1), reason: 'вдруге з пам’яті');
      expect(server.of('GET', '/watch/$slug').single.headers['auth'], 'tok');
    });

    test('збереження не стирає оцінку, нотатку й дату початку, які людина виставила на сайті', () async {
      serveWatch(existing: watchJson(episodes: 5, score: 8, note: 'Ого', start: 1700000000));
      await list.save(slug, status: HikkaWatchStatus.completed, total: 28);
      final b = put();
      expect(b['status'], 'completed');
      expect(b['episodes'], 28, reason: '«Переглянуто» добиває лічильник до кінця');
      expect(b['score'], 8);
      expect(b['note'], 'Ого');
      expect(b['start_date'], '2023-11-14T22:13:20.000Z');
      expect(b.containsKey('end_date'), isFalse);
    });

    test('новий запис: статус і серії, лічильник не перевищує кількість серій', () async {
      serveWatch();
      final e = await list.save(slug, status: HikkaWatchStatus.watching, episodes: 99, total: 28);
      expect(e.status, HikkaWatchStatus.watching);
      expect(put()['episodes'], 28);
      expect(list.cached(slug)?.status, HikkaWatchStatus.watching);
    });

    test('оцінка змінюється окремо від статусу', () async {
      serveWatch(existing: watchJson(episodes: 12, score: 0));
      await list.save(slug, score: 9);
      final b = put();
      expect(b['score'], 9);
      expect(b['status'], 'watching');
      expect(b['episodes'], 12);
    });

    test('видалення: запис зникає з пам’яті, повторне видалення не помилка', () async {
      serveWatch(existing: watchJson(episodes: 3));
      await list.entry(slug);
      await list.remove(slug);
      expect(list.cached(slug), isNull);
      expect(list.knows(slug), isTrue);
      server.routes['DELETE /watch/$slug'] = (r) => FakeAccountApi.fail(404, 'watch:not_found');
      await list.remove(slug);
    });

    test('кожна зміна піднімає версію (за нею оновлюється сторінка «Списки»)', () async {
      serveWatch();
      final v = list.version;
      await list.save(slug, status: HikkaWatchStatus.planned);
      expect(list.version, greaterThan(v));
    });

    test('вихід з акаунта скидає все відоме про списки', () async {
      serveWatch(existing: watchJson(episodes: 3));
      await list.entry(slug);
      expect(list.knows(slug), isTrue);
      await auth.signOut();
      expect(list.knows(slug), isFalse);
      expect(await list.entry(slug), isNull);
    });

    test('улюблене: відсутнє = false, додавання й прибирання', () async {
      server.routes['GET /favourite/anime/$slug'] = (r) => FakeAccountApi.fail(404, 'favourite:not_found');
      server.routes['PUT /favourite/anime/$slug'] = (r) => FakeAccountApi.ok({'reference': 'f', 'created': 1});
      server.routes['DELETE /favourite/anime/$slug'] = (r) => FakeAccountApi.ok({'success': true});
      expect(await list.isFavourite(slug), isFalse);
      await list.setFavourite(slug, true);
      expect(list.favouriteCached(slug), isTrue);
      expect(server.of('PUT', '/favourite/anime/$slug'), hasLength(1));
      await list.setFavourite(slug, false);
      expect(list.favouriteCached(slug), isFalse);
    });

    test('лічильники за статусами беруться з профілю власника', () async {
      server.routes['GET /watch/tester/stats'] = (r) => FakeAccountApi.ok({'duration': 1, 'completed': 40, 'watching': 3, 'planned': 7, 'dropped': 1, 'on_hold': 2});
      final s = await list.stats();
      expect(s.of(HikkaWatchStatus.completed), 40);
      expect(s.of(HikkaWatchStatus.onHold), 2);
      expect(s.total, 53);
    });
  });

  group('передача прогресу з плеєра', () {
    test('серію 3 з 12 у новому тайтлі: додає в «Дивлюсь»', () async {
      serveWatch();
      await list.syncEpisode(slug, 3, total: 12);
      final b = put();
      expect(b['status'], 'watching');
      expect(b['episodes'], 3);
    });

    test('остання серія: «Переглянуто»', () async {
      serveWatch(existing: watchJson(episodes: 11));
      await list.syncEpisode(slug, 12, total: 12);
      final b = put();
      expect(b['status'], 'completed');
      expect(b['episodes'], 12);
    });

    test('прогрес не зменшується: переглянули ранішу серію — нічого не відправляється', () async {
      serveWatch(existing: watchJson(episodes: 5));
      await list.syncEpisode(slug, 3, total: 12);
      expect(server.of('PUT', '/watch/$slug'), isEmpty);
    });

    test('нова серія піднімає лічильник і зберігає оцінку', () async {
      serveWatch(existing: watchJson(episodes: 5, score: 7));
      await list.syncEpisode(slug, 6, total: 12);
      final b = put();
      expect(b['episodes'], 6);
      expect(b['score'], 7);
    });

    test('«У планах» і «Кинуто» переходять у «Дивлюсь»; серії не зменшуються', () async {
      serveWatch(existing: watchJson(status: 'planned', episodes: 0));
      await list.syncEpisode(slug, 1, total: 12);
      expect(put()['status'], 'watching');

      server.log.clear();
      final dropped = HikkaMyList(auth: auth, api: api);
      serveWatch(existing: watchJson(status: 'dropped', episodes: 4));
      await dropped.syncEpisode(slug, 2, total: 12);
      final b = put();
      expect(b['status'], 'watching');
      expect(b['episodes'], 4);
    });

    test('вже переглянуте не чіпає (повторний перегляд)', () async {
      serveWatch(existing: watchJson(status: 'completed', episodes: 12));
      await list.syncEpisode(slug, 12, total: 12);
      expect(server.of('PUT', '/watch/$slug'), isEmpty);
    });

    test('без входу або з вимкненою синхронізацією запитів немає', () async {
      serveWatch();
      auth.syncProgress = false;
      await list.syncEpisode(slug, 3, total: 12);
      expect(server.log, isEmpty);

      auth.syncProgress = true;
      await auth.signOut();
      server.log.clear();
      await list.syncEpisode(slug, 3, total: 12);
      expect(server.log, isEmpty);
    });

    test('збої тихі: сервер падає — перегляд не страждає', () async {
      serveWatch();
      server.routes['PUT /watch/$slug'] = (r) => FakeAccountApi.fail(500, 'system:internal');
      await list.syncEpisode(slug, 3, total: 12);
      expect(auth.signedIn, isTrue);
    });

    test('токен відкликано: синхронізація тихо виходить з акаунта', () async {
      server.routes['GET /watch/$slug'] = (r) => FakeAccountApi.fail(400, 'auth:invalid_token');
      await list.syncEpisode(slug, 3, total: 12);
      expect(auth.signedIn, isFalse);
    });

    test('дві серії підряд не змагаються: другу обробляємо після першої', () async {
      serveWatch();
      await Future.wait([list.syncEpisode(slug, 1, total: 12), list.syncEpisode(slug, 2, total: 12)]);
      final puts = server.of('PUT', '/watch/$slug');
      expect(puts, hasLength(2));
      expect([for (final p in puts) server.bodyOf(p)['episodes']], [1, 2]);
    });

    test('номер серії: цілий номер із джерела, але не наскрізний понад кількість серій', () {
      expect(HikkaMyList.episodeNumber(number: 5, position: 1, total: 12), 5);
      expect(HikkaMyList.episodeNumber(number: 13, position: 1, total: 12), 1, reason: 'наскрізний номер другого сезону');
      expect(HikkaMyList.episodeNumber(number: 2.5, position: 3, total: 12), 3);
      expect(HikkaMyList.episodeNumber(number: null, position: 4, total: null), 4);
      expect(HikkaMyList.episodeNumber(number: 30, position: 9, total: null), 30);
      expect(HikkaMyList.episodeNumber(number: 0, position: 2, total: 12), 2);
    });
  });

  group('моделі', () {
    test('запис списку: розбір відповіді й тіло запиту', () {
      final e = HikkaWatchEntry.fromJson(watchJson(status: 'on_hold', episodes: 7, score: 6, note: 'n', start: 1700000000));
      expect(e.status, HikkaWatchStatus.onHold);
      expect(e.anime?.slug, slug);
      final args = e.toArgs();
      expect(args['status'], 'on_hold');
      expect(args['start_date'], '2023-11-14T22:13:20.000Z');
      expect(jsonEncode(args), isNot(contains('end_date')));
    });

    test('невідомий статус не ламає розбір', () {
      expect(HikkaWatchEntry.fromJson({'status': 'що-завгодно'}).status, HikkaWatchStatus.planned);
      expect(HikkaWatchStatus.fromApi('dropped'), HikkaWatchStatus.dropped);
      expect(HikkaWatchStatus.fromApi(null), isNull);
    });

    test('сторінка списку розбирається в записи з тайтлами', () {
      final page = HikkaPage.parse({
        'pagination': {'total': 1, 'pages': 1, 'page': 1},
        'list': [watchJson(episodes: 2)],
      }, HikkaWatchEntry.fromJson);
      expect(page.items.single.anime?.slug, slug);
    });
  });
}
