import 'package:flutter_test/flutter_test.dart';
import 'package:miki_miki/services/episode_alerts.dart';
import 'package:miki_miki/services/watch_store.dart';

Map<String, dynamic> _upd(String slug, String release, int ep, {String team = 'Togarashi', String kind = 'voice', String at = '2026-11-14T10:00:00Z'}) => {
      'anime': {
        'ids': {'hikka': slug},
        'titles': {'ua': 'Тайтл $slug'},
        'images': {
          'poster': {
            'medium': {'jpg': 'https://img/$slug.jpg'},
          },
        },
      },
      'releaseId': release,
      'teamName': team,
      'kind': kind,
      'episode': ep,
      'publishedAt': at,
    };

void main() {
  late Map<String, dynamic> alertsData;
  late Map<String, dynamic> storeData;
  late WatchStore store;
  late List<Map<String, dynamic>> feed;
  late List<DateTime> asked;
  final now = DateTime.utc(2026, 11, 14, 12);

  EpisodeAlerts make() => EpisodeAlerts(
        load: () => alertsData,
        save: (d) => alertsData = d,
        now: () => now,
        store: store,
        fetch: (since, page) async {
          asked.add(since);
          return (feed, 1);
        },
      );

  setUp(() {
    alertsData = {};
    storeData = {};
    asked = [];
    feed = [];
    store = WatchStore(load: () => storeData, save: (d) => storeData = d, now: () => now);
    // Дивлюсь two-slug: the Mikai dub t_49:voice (chosen manually), other is another site
    store.setLast('hikka:frieren', '1', 'mikai|frieren|t_49:voice');
    store.setPinnedGroup('hikka:frieren', 'mikai|frieren|t_49:voice');
    store.setLast('hikka:other', '1', 'ufdub|other|Команда');
  });

  test('сповіщає лише про серію в обраній озвучці, а не про вихід у Японії чи чужу команду', () async {
    feed = [
      _upd('frieren', 't_49:voice', 7),
      _upd('frieren', 't_108:voice', 7, team: 'Інша команда'),
      _upd('unknown', 't_49:voice', 3),
      _upd('other', 't_49:voice', 2),
    ];
    final a = make();
    expect(await a.check(force: true), 1);
    expect(a.items.single.slug, 'frieren');
    expect(a.items.single.headline, 'Вийшла серія 7');
    expect(a.items.single.dubLine, 'Озвучення: Togarashi');
    expect(a.items.single.image, 'https://img/frieren.jpg');
    expect(a.unread, 1);
  });

  test('повторна перевірка не дублює; нова серія додається; «прочитано» зберігається', () async {
    feed = [_upd('frieren', 't_49:voice', 7)];
    final a = make();
    await a.check(force: true);
    expect(await a.check(force: true), 0, reason: 'та сама серія вдруге не сповіщає');
    feed = [_upd('frieren', 't_49:voice', 8, at: '2026-11-14T11:00:00Z'), ...feed];
    expect(await a.check(force: true), 1);
    expect(a.items.map((e) => e.episode), [8, 7], reason: 'новіші першими');
    a.markRead(a.items.first.id);
    expect(a.unread, 1);
    final b = make();
    expect(b.items.length, 2, reason: 'переживає перезапуск');
    expect(b.unread, 1);
    b.markAllRead();
    expect(b.unread, 0);
    b.clear();
    expect(b.items, isEmpty);
  });

  test('перша перевірка дивиться на дві доби назад, далі — від попередньої', () async {
    final a = make();
    await a.check(force: true);
    expect(asked.first, now.subtract(EpisodeAlerts.firstLookback));
    await a.check(force: true);
    expect(asked.last.isAfter(asked.first), isTrue, reason: 'наступна — від часу попередньої перевірки');
    expect(asked.last.isBefore(now), isTrue);
  });

  test('без обраної озвучки Mikai стрічку навіть не запитуємо; частота обмежена', () async {
    storeData = {};
    store.reload();
    final a = make();
    expect(await a.check(force: true), 0);
    expect(asked, isEmpty);
    store.setLast('hikka:frieren', '1', 'mikai|frieren|t_49:voice');
    await a.check(force: true);
    final calls = asked.length;
    await a.check();
    expect(asked.length, calls, reason: 'не частіше за раз на 10 хв без force');
  });

  test('озвучка за замовчуванням — остання відкрита, якщо вручну не обирали', () {
    store.clearPinnedGroup('hikka:frieren');
    expect(make().tracked(), {'frieren': 't_49:voice'});
  });

  group('pushes received by the phone (inbox)', () {
    test('a news message and an episode push land in the list; repeats and junk are ignored', () async {
      final a = make();
      final json = '[{"id":"push|1","type":"news","title":"Miki Miki","body":"Привіт з бекенду","slug":"","t":${now.millisecondsSinceEpoch}},'
          '{"id":"frieren|r1|7","type":"episode","title":"Фрірен","body":"Вийшла серія 7","slug":"frieren","episode":"7","team":"Togarashi","kind":"voice","image":"https://img/x.jpg","t":${now.millisecondsSinceEpoch - 1000}},'
          '{"id":"x","type":"news","title":"","t":1}]';
      expect(await a.importInbox(source: () async => json), 2);
      final items = a.items;
      expect(items.first.type, 'news');
      expect(items.first.headline, 'Привіт з бекенду');
      expect(items.first.slug, isEmpty);
      expect(items[1].isEpisode, isTrue);
      expect(items[1].episode, 7);
      expect(items[1].dubLine, 'Озвучення: Togarashi');
      expect(a.unread, 2);
      // The same push again (e.g. the inbox was not emptied in time) adds nothing; saved data survives a reload
      expect(await a.importInbox(source: () async => json), 0);
      expect(make().items.length, 2);
      expect(make().items.first.body, 'Привіт з бекенду');
    });

    test('an empty inbox, a failing channel and broken JSON are harmless', () async {
      final a = make();
      expect(await a.importInbox(source: () async => null), 0);
      expect(await a.importInbox(source: () async => '[]'), 0);
      expect(await a.importInbox(source: () async => 'not json'), 0);
      expect(await a.importInbox(source: () async => throw StateError('no channel')), 0);
      expect(a.items, isEmpty);
    });

    test('a pushed episode and the same one found by the feed check are one entry', () async {
      final a = make();
      final t = now.millisecondsSinceEpoch;
      await a.importInbox(source: () async => '[{"id":"frieren|t_49:voice|7","type":"episode","title":"x","slug":"frieren","episode":"7","t":$t}]');
      feed = [_upd('frieren', 't_49:voice', 7)];
      await a.check(force: true);
      expect(a.items.where((e) => e.slug == 'frieren').length, 1);
    });

    test('a push imported while the feed is being fetched is not lost by the feed check', () async {
      final t = now.millisecondsSinceEpoch;
      late EpisodeAlerts a;
      a = EpisodeAlerts(
        load: () => alertsData,
        save: (d) => alertsData = d,
        now: () => now,
        store: store,
        fetch: (since, page) async {
          await a.importInbox(source: () async => '[{"id":"push|9","type":"news","title":"Miki","body":"hi","t":$t}]');
          return ([_upd('frieren', 't_49:voice', 7)], 1);
        },
      );
      await a.check(force: true);
      expect(a.items.map((e) => e.id), containsAll(['push|9', 'frieren|t_49:voice|7']));
    });
  });
}
