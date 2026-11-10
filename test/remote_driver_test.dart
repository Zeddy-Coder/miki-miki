import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:miki_miki/models/source_models.dart';
import 'package:miki_miki/services/episode_check.dart';
import 'package:miki_miki/services/hikka_api.dart';
import 'package:miki_miki/services/hikka_auth.dart';
import 'package:miki_miki/services/hikka_lists.dart';
import 'package:miki_miki/services/remote_driver.dart';
import 'package:miki_miki/services/remote_playback.dart';
import 'package:miki_miki/services/watch_models.dart';

import 'support/hikka_account_fakes.dart';
import 'support/remote_fakes.dart';

void main() {
  group('запуск', () {
    test('перша серія: відео передається плеєру, після тривалості — «йде», розділи з таймкодів', () async {
      final r = Rig();
      await r.driver.start(r.launch());
      expect(r.driver.active, isTrue);
      expect(r.driver.phase, RemotePhase.opening);
      expect(r.engine.opens, hasLength(1));
      expect(r.engine.lastUrl, 'https://moon/e1/1080.m3u8'); // найвища з відомих; «Авто» (без висоти) — лише за ручним вибором
      expect(r.engine.opens.single.start, isNull);
      expect(r.entries, [0]);
      expect(r.sessions, 1);
      expect(r.driver.entry!.key, 'hikka:test#1');

      r.driver.onDuration(const Duration(minutes: 24));
      expect(r.driver.phase, RemotePhase.playing);
    });

    test('стартова серія за ключем; «остання» й обрана озвучка запамʼятовуються', () async {
      final r = Rig();
      await r.driver.start(r.launch(epKey: '3'));
      expect(r.driver.index, 2);
      expect(r.engine.lastUrl, contains('/e3/'));
      expect(r.store.last('hikka:test')!.epKey, '3');
      expect(r.store.last('hikka:test')!.groupId, 'g1');
      expect(r.store.preferredGroup('hikka:test'), 'g1');
    });

    test('продовження з місця: збережена позиція передається плеєру', () async {
      final r = Rig(positions: {'hikka:test#2': 95000});
      await r.driver.start(r.launch(epKey: '2'));
      expect(r.engine.opens.single.start, const Duration(seconds: 95));
    });

    test('розділи з таймкодів Moon з’являються разом із тривалістю', () async {
      final r = Rig(
        hosters: {
          'e1': [
            Hoster(
              name: 'Moon',
              videos: [
                vid('https://moon/e1.m3u8', stamps: const [TimeStamp(90, 180, 'Opening', ChapterType.opening)]),
              ],
            ),
          ],
        },
        episodes: [1],
      );
      await r.driver.start(r.launch());
      expect(r.driver.chapters, isEmpty);
      r.started();
      expect(r.driver.chapters.map((c) => c.title), ['Episode', 'Opening', 'Episode']);
    });
  });

  group('навігація та автоперехід', () {
    test('наступна / попередня серія; на краях — false', () async {
      final r = Rig();
      await r.driver.start(r.launch());
      expect(r.driver.hasPrevious, isFalse);
      expect(await r.driver.previous(), isFalse);
      expect(await r.driver.next(), isTrue);
      expect(r.driver.index, 1);
      expect(r.engine.lastUrl, contains('/e2/'));
      expect(await r.driver.next(), isTrue);
      expect(r.driver.hasNext, isFalse);
      expect(await r.driver.next(), isFalse);
      expect(await r.driver.previous(), isTrue);
      expect(r.driver.index, 1);
    });

    test('серія дограла: позначається переглянутою, наступна відкривається сама', () async {
      final r = Rig();
      await r.driver.start(r.launch());
      r.started();
      r.engine.position = const Duration(minutes: 23, seconds: 59);
      await r.driver.onCompleted();
      expect(r.store.isWatched('hikka:test', '1'), isTrue);
      expect(r.driver.index, 1);
      expect(r.messages, ['Наступна серія']);
      // збережену позицію скинуто: серію можна дивитись спочатку
      expect(r.saved.last.key, 'hikka:test#1');
      expect(r.saved.last.pos, r.saved.last.dur);
    });

    test('автоперехід вимкнено — лишається на місці, але серія переглянута', () async {
      final r = Rig(autoNext: false);
      await r.driver.start(r.launch());
      r.started();
      await r.driver.onCompleted();
      expect(r.driver.index, 0);
      expect(r.store.isWatched('hikka:test', '1'), isTrue);
    });

    test('остання серія: повідомлення, без переходу', () async {
      final r = Rig();
      await r.driver.start(r.launch(epKey: '3'));
      r.started();
      await r.driver.onCompleted();
      expect(r.messages, ['Це остання серія']);
      expect(r.driver.index, 2);
      expect(r.engine.opens, hasLength(1));
    });

    test('відео скінчилося за мить після старту з середини — починаємо спочатку, а не йдемо далі', () async {
      final r = Rig(positions: {'hikka:test#1': 600000});
      await r.driver.start(r.launch());
      expect(r.engine.opens.single.start, const Duration(minutes: 10));
      r.started(dur: const Duration(minutes: 8)); // в іншій озвучці серія коротша за збережене місце
      await r.driver.onCompleted();
      expect(r.driver.index, 0);
      expect(r.engine.opens, hasLength(2));
      expect(r.engine.opens.last.start, Duration.zero);
      expect(r.store.isWatched('hikka:test', '1'), isFalse);
    });
  });

  group('«переглянуто» і збереження місця', () {
    test('tick зберігає позицію; переглянутою серія стає лише після порога', () async {
      final r = Rig();
      await r.driver.start(r.launch());
      r.started();
      r.engine.position = const Duration(minutes: 5);
      r.driver.tick();
      expect(r.saved.last.key, 'hikka:test#1');
      expect(r.saved.last.pos, 300000);
      expect(r.store.isWatched('hikka:test', '1'), isFalse);
      r.engine.position = const Duration(minutes: 21);
      r.driver.tick();
      expect(r.store.isWatched('hikka:test', '1'), isTrue);
    });

    test('поки відео не почалося, tick нічого не зберігає (не затирає збережене місце нулем)', () async {
      final r = Rig(positions: {'hikka:test#1': 120000});
      await r.driver.start(r.launch());
      r.driver.tick();
      expect(r.saved, isEmpty);
      expect(r.positions['hikka:test#1'], 120000);
    });

    test('перехід на іншу серію зберігає місце попередньої', () async {
      final r = Rig();
      await r.driver.start(r.launch());
      r.started();
      r.engine.position = const Duration(minutes: 7);
      await r.driver.next();
      expect(r.saved.first.key, 'hikka:test#1');
      expect(r.saved.first.pos, 420000);
    });

    test('stop зберігає місце й закриває сесію', () async {
      final r = Rig();
      await r.driver.start(r.launch());
      r.started();
      r.engine.position = const Duration(minutes: 3);
      r.driver.stop();
      expect(r.driver.active, isFalse);
      expect(r.driver.phase, RemotePhase.idle);
      expect(r.saved.last.pos, 180000);
    });
  });

  group('невдачі', () {
    test('плеєр мовчить довше за ліміт — пробуємо наступний плеєр серії', () async {
      final r = Rig();
      await r.driver.start(r.launch());
      expect(r.driver.hoster, 'Moon');
      await r.wait(150); // Moon мовчить 100 мс → Sibnet, у якого ще є час запуститися
      expect(r.engine.opens, hasLength(2));
      expect(r.engine.lastUrl, 'https://sibnet/e1.m3u8');
      expect(r.driver.hoster, 'Sibnet');
      expect(r.messages.single, startsWith('!Плеєр Moon не відповідає'));
      r.started();
      expect(r.driver.phase, RemotePhase.playing);
    });

    test('усі плеєри мовчать — помилка з порадою, «спробувати ще» відкриває знову', () async {
      final r = Rig(episodes: [1]);
      await r.driver.start(r.launch());
      await r.wait(400);
      expect(r.driver.phase, RemotePhase.failed);
      expect(r.driver.error, contains('Спробуйте'));
      final before = r.engine.opens.length;
      await r.driver.retry();
      expect(r.driver.phase, RemotePhase.opening);
      expect(r.engine.opens.length, before + 1);
      expect(r.driver.error, isNull);
    });

    test('помилка плеєра до початку відео — не чекаємо весь ліміт', () async {
      final r = Rig(openTimeout: const Duration(seconds: 30));
      await r.driver.start(r.launch());
      r.driver.onPlayerError('Failed to open https://moon/e1/auto.m3u8');
      await r.wait(150);
      expect(r.engine.opens, hasLength(2));
      expect(r.driver.hoster, 'Sibnet');
    });

    test('дрібна помилка, а відео все ж пішло — нічого не перемикається', () async {
      final r = Rig(openTimeout: const Duration(seconds: 30));
      await r.driver.start(r.launch());
      r.driver.onPlayerError('ffmpeg: tcp: щось дрібне');
      r.started();
      await r.wait(150);
      expect(r.engine.opens, hasLength(1));
      expect(r.driver.phase, RemotePhase.playing);
    });

    test('джерело не знайшло серію — повідомлення з джерела', () async {
      final r = Rig(hosters: {});
      await r.driver.start(r.launch());
      expect(r.driver.phase, RemotePhase.failed);
      expect(r.driver.error, isNotEmpty);
      expect(r.engine.opens, isEmpty);
    });

    test('джерело вимкнено / видалено', () async {
      final r = Rig();
      final g = WatchGroup(id: 'gx', sourceId: 'nope', label: 'X', episodes: [ep(1)]);
      await r.driver.start(RemoteLaunch(title: r.title, group: g, animeTitle: 'A'));
      expect(r.driver.phase, RemotePhase.failed);
      expect(r.driver.error, contains('Джерело «nope»'));
    });

    test('плеєр кидає виняток при відкритті — пробуємо інший плеєр', () async {
      final r = Rig();
      r.engine.failOpen = StateError('boom');
      await r.driver.start(r.launch());
      await r.wait(120);
      // обидва плеєри не відкрилися: друга спроба теж кинула виняток → помилка
      expect(r.driver.phase, RemotePhase.failed);
    });

    test('застаріла відповідь: швидко перемкнули серію, поки шукалося посилання', () async {
      final r = Rig();
      r.source.gate = Completer<void>();
      final first = r.driver.start(r.launch());
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final second = r.driver.open(2);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      r.source.gate!.complete();
      await Future.wait([first, second]);
      expect(r.engine.opens, hasLength(1));
      expect(r.engine.lastUrl, contains('/e3/'));
      expect(r.driver.index, 2);
    });
  });

  group('потік протух під час перегляду', () {
    test('помилка + відео стоїть — беремо нове посилання з того самого місця', () async {
      final r = Rig(openTimeout: const Duration(seconds: 30));
      await r.driver.start(r.launch());
      r.started();
      r.engine.position = const Duration(minutes: 9);
      r.driver.onPlayerError('HTTP error 403 Forbidden');
      await r.wait(250);
      expect(r.engine.opens, hasLength(2));
      expect(r.engine.opens.last.start, const Duration(minutes: 9));
      expect(r.messages, contains('Оновлюю посилання на відео…'));
    });

    test('помилка, але відео йде — нічого не робимо', () async {
      final r = Rig(openTimeout: const Duration(seconds: 30));
      await r.driver.start(r.launch());
      r.started();
      r.engine.position = const Duration(minutes: 9);
      r.driver.onPlayerError('ad: dropped audio packet');
      r.engine.position = const Duration(minutes: 9, seconds: 4);
      await r.wait(250);
      expect(r.engine.opens, hasLength(1));
    });

    test('помилка на паузі — не оновлюємо', () async {
      final r = Rig(openTimeout: const Duration(seconds: 30));
      await r.driver.start(r.launch());
      r.started();
      r.engine.playing = false;
      r.driver.onPlayerError('щось');
      await r.wait(250);
      expect(r.engine.opens, hasLength(1));
    });
  });

  group('озвучка, плеєр, якість', () {
    test('інша озвучка: та сама серія з того самого місця, повідомлення про зміну черги', () async {
      final b = WatchGroup(id: 'g2', sourceId: 'src', label: 'Команда Б', episodes: [ep(1), ep(2), ep(3)]);
      final r = Rig();
      final title = WatchTitle(
        animeKey: 'hikka:test',
        offers: [
          WatchOffer(source: r.source, anime: const SAnime(url: 'a', title: 'A'), groups: [r.group, b]),
        ],
      );
      await r.driver.start(RemoteLaunch(title: title, group: r.group, animeTitle: 'Аніме', epKey: '2'));
      r.started();
      r.engine.position = const Duration(minutes: 6);
      await r.driver.switchGroup(b);
      expect(r.driver.groupId, 'g2');
      expect(r.driver.index, 1);
      expect(r.engine.opens, hasLength(2));
      expect(r.engine.opens.last.start, const Duration(minutes: 6));
      expect(r.sessions, 2);
      expect(r.store.preferredGroup('hikka:test'), 'g2');
      expect(r.driver.session!.groupLabel, 'Команда Б');
    });

    test('запуск — не вибір: улюбленою команда стає лише після перемикання в плеєрі', () async {
      final r = Rig();
      await r.driver.start(r.launch());
      expect(r.store.preferredGroup('hikka:test'), 'g1'); // для цього тайтлу — остання озвучка
      expect(r.store.favoriteChoices, isEmpty);
    });

    test('перемикання озвучки запамʼятовує команду для нових тайтлів, повторний вибір не дублюється', () async {
      final b = WatchGroup(id: 'g2', sourceId: 'src', label: 'Команда Б', episodes: [ep(1), ep(2), ep(3)]);
      final r = Rig();
      final title = WatchTitle(
        animeKey: 'hikka:test',
        offers: [
          WatchOffer(source: r.source, anime: const SAnime(url: 'a', title: 'A'), groups: [r.group, b]),
        ],
      );
      await r.driver.start(RemoteLaunch(title: title, group: r.group, animeTitle: 'Аніме'));
      r.started();
      await r.driver.switchGroup(b);
      r.started();
      expect(r.store.favoriteChoices, [choiceKeyOf(b)]);

      // Назад і вдруге: список не росте, найновіший вибір першим
      await r.driver.switchGroup(r.group);
      r.started();
      await r.driver.switchGroup(b);
      r.started();
      expect(r.store.favoriteChoices, [choiceKeyOf(b), choiceKeyOf(r.group)]);
      expect(r.store.preferredGroup('hikka:test'), 'g2');

      // Інший тайтл тієї ж озвучки: «Дивитись» відкриє знайому команду, хоч би яка була першою
      final other = [
        WatchGroup(id: 'x1', sourceId: 'src', label: 'Команда А', episodes: [ep(1), ep(2)]),
        WatchGroup(id: 'x2', sourceId: 'src', label: 'Команда Б', episodes: [ep(1), ep(2)]),
      ];
      expect(pickGroup(other, favorites: r.store.favoriteChoices).label, 'Команда Б');
    });

    test('перемикання на ту саму озвучку нічого не змінює і не відкриває серію знову', () async {
      final r = Rig();
      await r.driver.start(r.launch());
      r.started();
      await r.driver.switchGroup(r.group);
      expect(r.engine.opens, hasLength(1));
      expect(r.store.favoriteChoices, isEmpty);
    });

    test('розбіжність нумерації з Hikka: драйвер оцінює варіанти за відомостями, переданими під час запуску', () async {
      final merged = WatchGroup(id: 'm', sourceId: 'src', label: 'Склеєні', episodes: [for (var n = 1; n <= 24; n++) ep(n)]);
      final exact = WatchGroup(id: 'e', sourceId: 'src', label: 'Рівно', episodes: [for (var n = 1; n <= 12; n++) ep(n)]);
      final r = Rig(episodes: [for (var n = 1; n <= 24; n++) n]);
      final title = WatchTitle(
        animeKey: 'hikka:test',
        offers: [
          WatchOffer(source: r.source, anime: const SAnime(url: 'a', title: 'A'), groups: [merged, exact]),
        ],
      );
      await r.driver.start(
        RemoteLaunch(title: title, group: exact, animeTitle: 'Аніме', hikka: const HikkaEpisodeInfo(released: 12, total: 12, finished: true)),
      );
      expect(r.driver.checkOf(merged).syncSafe, isFalse);
      expect(r.driver.checkOf(merged).level, EpisodeCheckLevel.mismatch);
      expect(r.driver.checkOf(exact).syncSafe, isTrue);
      expect(r.driver.checkOf(exact).summary, '12 з 12');
    });

    test('в іншій озвучці немає такої серії — найближча за порядком', () async {
      final short = WatchGroup(id: 'g2', sourceId: 'src', label: 'Коротка', episodes: [ep(1), ep(2)]);
      final r = Rig();
      final title = WatchTitle(
        animeKey: 'hikka:test',
        offers: [
          WatchOffer(source: r.source, anime: const SAnime(url: 'a', title: 'A'), groups: [r.group, short]),
        ],
      );
      await r.driver.start(RemoteLaunch(title: title, group: r.group, animeTitle: 'Аніме', epKey: '3'));
      await r.driver.switchGroup(short);
      expect(r.driver.index, 1); // 3-ї серії немає — залишаємось у межах черги
      expect(r.driver.entry!.epKey, '2');
    });

    test('ручний вибір плеєра діє й на наступні серії', () async {
      final r = Rig();
      await r.driver.start(r.launch());
      r.started();
      await r.driver.switchHoster('Sibnet');
      expect(r.engine.lastUrl, 'https://sibnet/e1.m3u8');
      r.started();
      await r.driver.next();
      expect(r.engine.lastUrl, 'https://sibnet/e2.m3u8');
    });

    test('інша якість: без нового пошуку посилання, з того самого місця', () async {
      final r = Rig();
      await r.driver.start(r.launch());
      r.started();
      final calls = r.source.hosterCalls;
      r.engine.position = const Duration(minutes: 4);
      final q720 = r.driver.stream!.qualities.firstWhere((v) => v.resolution == 720);
      await r.driver.switchQuality(q720);
      expect(r.source.hosterCalls, calls);
      expect(r.engine.lastUrl, 'https://moon/e1/720.m3u8');
      expect(r.engine.opens.last.start, const Duration(minutes: 4));
      expect(r.driver.phase, RemotePhase.opening);
      // наступна серія теж не вище 720p
      r.started();
      await r.driver.next();
      expect(r.engine.lastUrl, 'https://moon/e2/720.m3u8');
    });

    test('«Авто» після ручної якості повертає налаштування за замовчуванням', () async {
      final r = Rig();
      await r.driver.start(r.launch());
      r.started();
      await r.driver.switchQuality(r.driver.stream!.qualities.firstWhere((v) => v.resolution == 720));
      r.started();
      await r.driver.switchQuality(r.driver.stream!.qualities.firstWhere((v) => v.resolution == null));
      r.started();
      await r.driver.next();
      expect(r.engine.lastUrl, 'https://moon/e2/1080.m3u8'); // знову найвища, а не «Авто»
    });
  });

  group('зовнішні доріжки', () {
    final sub = [const Track('https://s/uk.vtt', 'uk'), const Track('https://s/en.vtt', 'en')];
    final audio = [const Track('https://a/uk.mp3', 'uk')];

    Rig rig() {
      final r = Rig(
        episodes: [1],
        hosters: {
          'e1': [
            Hoster(name: 'Moon', videos: [vid('https://moon/e1.m3u8', subs: sub, audios: audio)]),
          ],
        },
      );
      return r;
    }

    test('озвучення: субтитри додаються, але не вмикаються; окремий звук вмикається', () async {
      final r = rig();
      await r.driver.start(r.launch());
      r.started();
      await r.wait(30);
      expect(r.engine.subs.map((s) => s.select), [false, false]);
      expect(r.engine.audios.map((a) => a.select), [true]);
    });

    test('субтитри (суб.): перша доріжка вмикається', () async {
      final r = rig();
      final g = WatchGroup(id: 'gs', sourceId: 'src', label: 'Суб', isSub: true, episodes: [ep(1)]);
      final t = WatchTitle(
        animeKey: 'hikka:test',
        offers: [
          WatchOffer(source: r.source, anime: const SAnime(url: 'a', title: 'A'), groups: [g]),
        ],
      );
      await r.driver.start(RemoteLaunch(title: t, group: g, animeTitle: 'A'));
      r.started();
      await r.wait(30);
      expect(r.engine.subs.map((s) => s.select), [true, false]);
    });

    Future<Rig> subRig(List<Track> tracks, {List<String> langs = const ['uk', 'ja', 'en'], bool isSub = true}) async {
      final r = Rig(
        episodes: [1],
        subLangs: langs,
        hosters: {
          'e1': [
            Hoster(name: 'Moon', videos: [vid('https://moon/e1.m3u8', subs: tracks)]),
          ],
        },
      );
      final g = WatchGroup(id: 'gs', sourceId: 'src', label: 'Суб', isSub: isSub, episodes: [ep(1)]);
      final t = WatchTitle(
        animeKey: 'hikka:test',
        offers: [
          WatchOffer(source: r.source, anime: const SAnime(url: 'a', title: 'A'), groups: [g]),
        ],
      );
      await r.driver.start(RemoteLaunch(title: t, group: g, animeTitle: 'A'));
      r.started();
      await r.wait(30);
      return r;
    }

    const en = Track('https://s/en.vtt', 'English');
    const uk = Track('https://s/uk.vtt', 'Українська');
    const ja = Track('https://s/ja.vtt', 'jpn');

    test('субтитри (суб.): з кількох доріжок вмикається та, що вища за мовою в налаштуваннях, а не перша', () async {
      final r = await subRig([en, uk]);
      expect(r.engine.subs.map((s) => s.select), [false, true]); // українська попереду англійської
    });

    test('інший пріоритет — інша доріжка; підпис може бути й міткою мови', () async {
      expect((await subRig([en, uk, ja], langs: const ['en', 'uk'])).engine.subs.map((s) => s.select), [true, false, false]);
      expect((await subRig([en, uk, ja], langs: const ['ja', 'uk'])).engine.subs.map((s) => s.select), [false, false, true]);
    });

    test('жодна мова зі списку не знайшлась — вмикається перша: людина обрала саме субтитри', () async {
      final r = await subRig([const Track('https://s/de.vtt', 'Deutsch'), const Track('https://s/fr.vtt', 'Français')], langs: const ['uk', 'en']);
      expect(r.engine.subs.map((s) => s.select), [true, false]);
    });

    test('озвучення: що б не було в пріоритеті, субтитри не вмикаються', () async {
      final r = await subRig([en, uk], isSub: false);
      expect(r.engine.subs.map((s) => s.select), [false, false]);
    });

    test('доріжки додаються один раз, навіть якщо тривалість приходить кілька разів', () async {
      final r = rig();
      await r.driver.start(r.launch());
      r.started();
      r.driver.onDuration(const Duration(minutes: 24));
      await r.wait(30);
      expect(r.engine.subs, hasLength(2));
    });
  });

  group('стан для екрана плеєра', () {
    test('showsStatus: серію готують чи вона не запустилась — так; відео йде або сесію зупинено — ні', () async {
      final r = Rig();
      expect(r.driver.showsStatus, isFalse);
      await r.driver.start(r.launch());
      expect(r.driver.phase, RemotePhase.opening);
      expect(r.driver.showsStatus, isTrue);
      r.started();
      expect(r.driver.showsStatus, isFalse);
      r.driver.stop();
      expect(r.driver.showsStatus, isFalse);

      final f = Rig()..engine.failOpen = Exception('x');
      await f.driver.start(f.launch());
      expect(f.driver.phase, RemotePhase.failed);
      expect(f.driver.showsStatus, isTrue);
    });

    test('alternativeHoster: наступний плеєр по колу; без вибору — null', () async {
      final r = Rig();
      expect(r.driver.alternativeHoster, isNull); // ще нічого не відкрито
      await r.driver.start(r.launch());
      expect(r.driver.hoster, 'Moon');
      expect(r.driver.alternativeHoster, 'Sibnet');
      await r.driver.switchHoster('Sibnet');
      expect(r.driver.alternativeHoster, 'Moon');

      final one = Rig(
        hosters: {
          'e1': [
            Hoster(name: 'Moon', videos: [vid('https://moon/e1.m3u8')]),
          ],
        },
        episodes: [1],
      );
      await one.driver.start(one.launch());
      expect(one.driver.alternativeHoster, isNull);
    });

    test('nowPlaying: озвучка, плеєр і якість одним рядком', () async {
      final r = Rig();
      expect(r.driver.nowPlaying(), '');
      await r.driver.start(r.launch());
      expect(r.driver.nowPlaying(), 'Озвучення: Команда А · Moon · 1080p');
      expect(r.driver.nowPlaying(withKind: false), 'Команда А · Moon · 1080p');
    });

    test('серія стала переглянутою — слухачі дізнаються (у панелі зʼявляється позначка)', () async {
      final r = Rig();
      await r.driver.start(r.launch());
      r.started();
      var calls = 0;
      r.driver.addListener(() => calls++);
      r.engine.position = const Duration(minutes: 5);
      r.driver.tick();
      expect(calls, 0); // ще не переглянуто
      r.engine.position = const Duration(minutes: 21);
      r.driver.tick();
      expect(calls, 1);
      r.driver.tick(); // вдруге вже позначено — зайвих сповіщень немає
      expect(calls, 1);
    });
  });
  group('прогрес у списки Hikka', () {
    late FakeAccountApi server;
    late HikkaAuth auth;
    late Map<String, dynamic> data;

    HikkaAuth makeAuth(HikkaApi api) => HikkaAuth(api: api, load: () => data, save: (d) => data = Map<String, dynamic>.of(d), urlOpener: (_) async => true);

    setUp(() {
      server = FakeAccountApi();
      final api = HikkaApi(sender: server.call, retryDelay: Duration.zero);
      data = {'token': 'tok', 'me': Map<String, dynamic>.of(kMe)};
      auth = makeAuth(api);
      HikkaMyList.instance = HikkaMyList(auth: auth, api: api);
      server.routes['GET /watch/test'] = (r) => FakeAccountApi.fail(404, 'watch:not_found');
      server.routes['PUT /watch/test'] = (r) {
        final b = server.bodyOf(r);
        return FakeAccountApi.ok({'reference': 'w', 'status': b['status'], 'episodes': b['episodes'], 'score': 0});
      };
    });

    tearDown(() {
      HikkaMyList.instance = HikkaMyList();
    });

    Map<String, dynamic> put() => server.bodyOf(server.of('PUT', '/watch/test').single);

    test('переглянута серія: тайтл потрапляє в «Дивлюсь» зі справжнім номером серії', () async {
      final r = Rig();
      await r.driver.start(r.launch(epKey: '2'));
      r.started();
      await r.driver.onCompleted();
      await r.wait(40);
      expect(r.store.isWatched('hikka:test', '2'), isTrue);
      expect(put()['status'], 'watching');
      expect(put()['episodes'], 2);
      expect(server.of('PUT', '/watch/test').single.headers['auth'], 'tok');
    });

    test('остання серія тайтлу: статус «Переглянуто»', () async {
      final r = Rig();
      await r.driver.start(RemoteLaunch(
        title: r.title,
        group: r.group,
        animeTitle: 'Аніме',
        epKey: '3',
        hikka: const HikkaEpisodeInfo(released: 3, total: 3, finished: true),
      ));
      r.started();
      await r.driver.onCompleted();
      await r.wait(40);
      expect(put()['status'], 'completed');
      expect(put()['episodes'], 3);
    });

    test('без входу в Hikka нічого не надсилається, перегляд працює як завжди', () async {
      data.clear();
      HikkaMyList.instance = HikkaMyList(auth: makeAuth(HikkaApi(sender: server.call, retryDelay: Duration.zero)));
      final r = Rig();
      await r.driver.start(r.launch());
      r.started();
      await r.driver.onCompleted();
      await r.wait(40);
      expect(r.store.isWatched('hikka:test', '1'), isTrue);
      expect(server.log, isEmpty);
    });

    test('перемикач «Передавати прогрес у списки» вимкнено — нічого не надсилається', () async {
      auth.syncProgress = false;
      final r = Rig();
      await r.driver.start(r.launch());
      r.started();
      await r.driver.onCompleted();
      await r.wait(40);
      expect(r.store.isWatched('hikka:test', '1'), isTrue);
      expect(server.log, isEmpty);
    });

    test('збій Hikka не заважає перегляду: серія позначена, наступна відкрита, помилки в плеєрі немає', () async {
      server.routes['PUT /watch/test'] = (r) => FakeAccountApi.fail(500, 'system:internal');
      final r = Rig();
      await r.driver.start(r.launch());
      r.started();
      await r.driver.onCompleted();
      await r.wait(60);
      expect(r.store.isWatched('hikka:test', '1'), isTrue);
      expect(r.driver.index, 1);
      expect(r.driver.phase, isNot(RemotePhase.failed));
      expect(r.messages.where((m) => m.startsWith('!')), isEmpty);
    });

    test('серія, що вже відмічена на Hikka вище, не зменшує лічильник', () async {
      server.routes['GET /watch/test'] = (r) => FakeAccountApi.ok({'reference': 'w', 'status': 'watching', 'episodes': 7, 'score': 0});
      final r = Rig();
      await r.driver.start(r.launch(epKey: '2'));
      r.started();
      await r.driver.onCompleted();
      await r.wait(40);
      expect(server.of('PUT', '/watch/test'), isEmpty, reason: 'у списку вже 7 серій — запис не чіпаємо');
    });
  });
}
