import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:miki_miki/models/source_models.dart';
import 'package:miki_miki/services/episode_check.dart';
import 'package:miki_miki/services/remote_driver.dart';
import 'package:miki_miki/services/remote_playback.dart';
import 'package:miki_miki/services/ui_theme_service.dart';
import 'package:miki_miki/services/watch_models.dart';
import 'package:miki_miki/utils/platform_info.dart';
import 'package:miki_miki/widgets/app_ui_kit.dart';
import 'package:miki_miki/widgets/remote_panel.dart';
import 'package:miki_miki/widgets/remote_status_overlay.dart';

import 'support/fakes.dart';
import 'support/remote_fakes.dart';

const Size kDesktop = Size(1280, 720);
const Size kPhone = Size(448, 997);

void setScreen(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// Кадр, що застосовує зміну, і ще два з часом — анімації (поява, перемикання, прокрутка) встигають завершитись
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

/// Стенд із довгим лімітом на відкриття: таймер-сторож не спрацьовує посеред перевірки
Rig newRig({List<int> episodes = const [1, 2, 3]}) => Rig(episodes: episodes, openTimeout: const Duration(seconds: 30));

Widget statusHost(Rig rig, {VoidCallback? onClose, VoidCallback? onPanel}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  home: Scaffold(
    body: ListenableBuilder(
      listenable: rig.driver,
      builder:
          (context, _) =>
              Stack(children: [RemoteStatusOverlay(scale: 1, driver: rig.driver, onOpenPanel: onPanel ?? () {}, onClose: onClose ?? () {})]),
    ),
  ),
);

Widget panelHost(Rig rig, {bool sheet = false, ValueChanged<int>? onEpisode}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  home: Scaffold(
    body: ListenableBuilder(
      listenable: rig.driver,
      builder:
          (context, _) => Align(
            alignment: Alignment.topRight,
            child: SizedBox(
              width: 380,
              height: 560,
              child: RemotePanelBody(scale: 1, driver: rig.driver, sheet: sheet, onEpisodeSelected: onEpisode ?? (_) {}),
            ),
          ),
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadTestFonts();
  });

  setUp(() {
    uiTheme.setThemeMode('dark');
  });

  tearDown(() {
    AppPlatform.debugMobile = null;
  });

  group('екран стану серії', () {
    testWidgets('готування: «Шукаю відео…» → «Запускаю Moon…»; коли відео йде, екран зникає', (tester) async {
      setScreen(tester, kDesktop);
      final rig = newRig();
      rig.source.gate = Completer<void>();
      await tester.pumpWidget(statusHost(rig));
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await tester.runAsync(() async {
        unawaited(rig.driver.start(rig.launch()));
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await settle(tester);
      expect(find.text('Шукаю відео…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.runAsync(() async {
        rig.source.gate!.complete();
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      await settle(tester);
      expect(find.text('Запускаю Moon…'), findsOneWidget);

      rig.started();
      await settle(tester);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Запускаю Moon…'), findsNothing);
      rig.driver.stop();
    });

    testWidgets('плеєр не відповів — підпис «Пробую інший плеєр — Sibnet…»', (tester) async {
      setScreen(tester, kDesktop);
      final rig = Rig(); // короткі ліміти (справжній час)
      await tester.pumpWidget(statusHost(rig));
      await tester.runAsync(() async {
        await rig.driver.start(rig.launch());
        rig.driver.onPlayerError('Failed to open');
        await Future<void>.delayed(const Duration(milliseconds: 120));
      });
      await settle(tester);
      expect(rig.driver.hoster, 'Sibnet');
      expect(find.text('Пробую інший плеєр — Sibnet…'), findsOneWidget);
      rig.driver.stop();
    });

    testWidgets('невдача: картка з діями; «Спробувати ще» відкриває знову, «Закрити» і «Озвучки та плеєри» кличуть обробники', (tester) async {
      setScreen(tester, kDesktop);
      final rig = newRig()..engine.failOpen = Exception('boom');
      var closed = 0, panel = 0;
      await tester.pumpWidget(statusHost(rig, onClose: () => closed++, onPanel: () => panel++));
      await tester.runAsync(() => rig.driver.start(rig.launch()));
      await settle(tester);

      expect(rig.driver.phase, RemotePhase.failed);
      expect(find.text('Не вдалося запустити серію'), findsOneWidget);
      expect(find.textContaining('Спробуйте іншу озвучку чи плеєр'), findsOneWidget);
      for (final label in ['Спробувати ще', 'Інший плеєр', 'Озвучки та плеєри', 'Наступна серія', 'Закрити']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }

      await tester.tap(find.text('Закрити'));
      await tester.tap(find.text('Озвучки та плеєри'));
      expect((closed, panel), (1, 1));

      rig.engine.failOpen = null;
      await tester.tap(find.text('Спробувати ще'));
      await settle(tester);
      expect(rig.driver.phase, RemotePhase.opening);
      expect(find.text('Не вдалося запустити серію'), findsNothing);
      rig.started();
      rig.driver.stop();
    });

    testWidgets('«Інший плеєр» відкриває серію в наступному плеєрі; на останній серії «Наступна серія» немає', (tester) async {
      setScreen(tester, kDesktop);
      final rig = newRig(episodes: [1])..engine.failOpen = Exception('boom');
      await tester.pumpWidget(statusHost(rig));
      await tester.runAsync(() => rig.driver.start(rig.launch()));
      await settle(tester);
      expect(find.text('Наступна серія'), findsNothing);
      expect(rig.driver.hoster, 'Sibnet'); // останній спробуваний

      rig.engine.failOpen = null;
      await tester.tap(find.text('Інший плеєр'));
      await settle(tester);
      expect(rig.engine.lastUrl, startsWith('https://moon/e1/'));
      rig.started();
      rig.driver.stop();
    });

    testWidgets('телефон: кнопки дій не нижчі за 48 dp', (tester) async {
      AppPlatform.debugMobile = true;
      setScreen(tester, kPhone);
      final rig = newRig()..engine.failOpen = Exception('boom');
      await tester.pumpWidget(statusHost(rig));
      await tester.runAsync(() => rig.driver.start(rig.launch()));
      await settle(tester);

      expect(tester.getSize(find.byType(AppAccentButton)).height, greaterThanOrEqualTo(48));
      final secondary = find.byType(AppSecondaryButton);
      expect(secondary, findsWidgets);
      for (final e in secondary.evaluate()) {
        expect(tester.getSize(find.byWidget(e.widget)).height, greaterThanOrEqualTo(48));
      }
      expect(tester.takeException(), isNull); // картка вміщується у вузький екран
      rig.driver.stop();
    });

    testWidgets('поки відео йде, екран не перехоплює дотики', (tester) async {
      setScreen(tester, kDesktop);
      final rig = newRig();
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: rig.driver,
              builder:
                  (context, _) => Stack(
                    children: [
                      Positioned.fill(child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => taps++)),
                      RemoteStatusOverlay(scale: 1, driver: rig.driver, onOpenPanel: () {}, onClose: () {}),
                    ],
                  ),
            ),
          ),
        ),
      );
      await tester.runAsync(() => rig.driver.start(rig.launch()));
      rig.started();
      await settle(tester);
      await tester.tapAt(const Offset(640, 360));
      expect(taps, 1);
      rig.driver.stop();
    });
  });

  group('панель серій із сайту', () {
    testWidgets('серії: поточна виділена, переглянуті позначені, тап обирає серію', (tester) async {
      setScreen(tester, kDesktop);
      final rig = newRig();
      rig.store.setWatched('hikka:test', '2', true);
      final picked = <int>[];
      await tester.pumpWidget(panelHost(rig, onEpisode: picked.add));
      await tester.runAsync(() => rig.driver.start(rig.launch()));
      rig.started();
      await settle(tester);

      for (final t in ['Серія 1', 'Серія 2', 'Серія 3']) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
      expect(find.text('Зараз відтворюється'), findsOneWidget);
      expect(find.text('Переглянуто'), findsOneWidget);
      expect(find.textContaining('Команда А · Moon · 1080p'), findsOneWidget); // що зараз грає

      await tester.tap(find.text('Серія 3'));
      expect(picked, [2]);
      rig.driver.stop();
    });

    testWidgets('довгий список: при відкритті поточна серія вже видна, решта будується ліниво', (tester) async {
      setScreen(tester, kDesktop);
      final rig = newRig(episodes: [for (var i = 1; i <= 300; i++) i]);
      await tester.runAsync(() => rig.driver.start(rig.launch(epKey: '200')));
      rig.started();
      await tester.pumpWidget(panelHost(rig));
      await settle(tester);
      expect(find.text('Серія 200'), findsOneWidget);
      expect(find.text('Серія 1'), findsNothing);
      expect(find.text('Серія 300'), findsNothing);
      rig.driver.stop();
    });

    testWidgets('список стежить за поточною серією: перехід на далеку серію прокручує до неї', (tester) async {
      setScreen(tester, kDesktop);
      final rig = newRig(episodes: [for (var i = 1; i <= 300; i++) i]);
      await tester.runAsync(() => rig.driver.start(rig.launch()));
      rig.started();
      await tester.pumpWidget(panelHost(rig));
      await settle(tester);
      expect(find.text('Серія 1'), findsOneWidget);

      await tester.runAsync(() => rig.driver.open(250));
      rig.started();
      await settle(tester);
      expect(find.text('Серія 251'), findsOneWidget);
      expect(find.text('Серія 1'), findsNothing);
      rig.driver.stop();
    });

    testWidgets('озвучка: усі варіанти з підписами, тап перемикає з тієї ж серії', (tester) async {
      setScreen(tester, kDesktop);
      final rig = newRig();
      final g2 = WatchGroup(id: 'g2', sourceId: 'src', label: 'Команда Б', isSub: true, episodes: [ep(1), ep(2)]);
      final title = WatchTitle(
        animeKey: 'hikka:test',
        offers: [
          WatchOffer(source: rig.source, anime: const SAnime(url: 'a', title: 'A'), groups: [rig.group, g2]),
        ],
      );
      await tester.pumpWidget(panelHost(rig));
      await tester.runAsync(() => rig.driver.start(RemoteLaunch(title: title, group: rig.group, animeTitle: 'Аніме', epKey: '2')));
      rig.started();
      await settle(tester);

      await tester.tap(find.text('Озвучка'));
      await settle(tester);
      expect(find.text('Команда А'), findsOneWidget);
      expect(find.text('Команда Б'), findsOneWidget);
      expect(find.text('Озвучення · 3 з ? сер. · src'), findsOneWidget);
      expect(find.text('Субтитри · 2 з ? сер. · src'), findsOneWidget);

      await tester.tap(find.text('Команда Б'));
      await settle(tester);
      expect(rig.driver.groupId, 'g2');
      expect(rig.driver.entry!.epKey, '2'); // та сама серія в іншому варіанті
      expect(rig.driver.session!.entries, hasLength(2));
      rig.driver.stop();
    });

    /// Три варіанти для тайтлу, де на Hikka рівно 12 серій: склеєний (24), правильний (12), неповний (7)
    Future<(Rig, WatchGroup, WatchGroup, WatchGroup)> mismatchRig(WidgetTester tester, {bool sheet = false}) async {
      final rig = newRig(episodes: [for (var n = 1; n <= 24; n++) n]);
      final merged = WatchGroup(id: 'm', sourceId: 'src', label: 'Склеєні', episodes: [for (var n = 1; n <= 24; n++) ep(n)]);
      final exact = WatchGroup(id: 'e', sourceId: 'src', label: 'Рівно', episodes: [for (var n = 1; n <= 12; n++) ep(n)]);
      final part = WatchGroup(id: 'p', sourceId: 'src', label: 'Неповна', episodes: [for (var n = 1; n <= 7; n++) ep(n)]);
      final title = WatchTitle(
        animeKey: 'hikka:test',
        offers: [
          WatchOffer(source: rig.source, anime: const SAnime(url: 'a', title: 'A'), groups: [merged, exact, part]),
        ],
      );
      await tester.pumpWidget(panelHost(rig, sheet: sheet));
      await tester.runAsync(
        () => rig.driver.start(
          RemoteLaunch(title: title, group: merged, animeTitle: 'Аніме', hikka: const HikkaEpisodeInfo(released: 12, total: 12, finished: true)),
        ),
      );
      rig.started();
      await settle(tester);
      await tester.tap(find.text('Озвучка'));
      await settle(tester);
      return (rig, merged, exact, part);
    }

    Finder warnIn(String label) => find.descendant(of: find.widgetWithText(AppSelectableTile, label), matching: find.byIcon(Symbols.warning_rounded));

    testWidgets('озвучка: розбіжність з Hikka — пояснення над списком, жовта позначка в рядках, підпис про вибір', (tester) async {
      setScreen(tester, kDesktop);
      final (rig, _, _, _) = await mismatchRig(tester);

      expect(find.text('Перемикається з того ж місця. Вибір запамʼятовується'), findsOneWidget);
      // Поточний варіант склеєний: пояснення над списком
      expect(find.textContaining('Тут 24 серій, а на Hikka їх лише 12.'), findsOneWidget);
      expect(find.textContaining('не синхронізуватимуться з Hikka автоматично'), findsOneWidget);
      expect(find.text('Озвучення · 24 з 12 сер. · src'), findsOneWidget);
      expect(find.text('Озвучення · 12 з 12 сер. · src'), findsOneWidget);
      expect(find.text('Озвучення · 7 з 12 сер. · src'), findsOneWidget);
      // Жовта позначка біля склеєного й неповного, правильний варіант — без неї
      expect(warnIn('Склеєні'), findsOneWidget);
      expect(warnIn('Неповна'), findsOneWidget);
      expect(warnIn('Рівно'), findsNothing);
      rig.driver.stop();
    });

    testWidgets('озвучка: перехід на правильний варіант прибирає пояснення й запамʼятовує вибір', (tester) async {
      setScreen(tester, kDesktop);
      final (rig, _, exact, _) = await mismatchRig(tester);
      expect(rig.store.favoriteChoices, isEmpty);

      await tester.tap(find.text('Рівно'));
      await settle(tester);
      expect(rig.driver.groupId, 'e');
      expect(rig.driver.session!.entries, hasLength(12));
      expect(find.textContaining('Тут 24 серій'), findsNothing);
      expect(rig.store.preferredGroup('hikka:test'), 'e');
      expect(rig.store.favoriteChoices, [choiceKeyOf(exact)]);
      rig.driver.stop();
    });

    testWidgets('телефон: озвучка з поясненням і жовтими позначками — рядки не нижчі за 48 dp, без переповнення', (tester) async {
      AppPlatform.debugMobile = true;
      setScreen(tester, kPhone);
      final (rig, _, _, _) = await mismatchRig(tester, sheet: true);

      expect(find.textContaining('Тут 24 серій, а на Hikka їх лише 12.'), findsOneWidget);
      for (final label in ['Склеєні', 'Рівно', 'Неповна']) {
        final tile = find.widgetWithText(AppSelectableTile, label);
        expect(tester.getSize(tile).height, greaterThanOrEqualTo(48), reason: label);
      }
      expect(tester.takeException(), isNull);
      rig.driver.stop();
    });

    testWidgets('плеєр і якість: тап по плеєру й по якості відкриває потрібне посилання', (tester) async {
      setScreen(tester, kDesktop);
      final rig = newRig();
      await tester.pumpWidget(panelHost(rig));
      await tester.runAsync(() => rig.driver.start(rig.launch()));
      rig.started();
      await settle(tester);

      await tester.tap(find.text('Плеєр'));
      await settle(tester);
      for (final t in ['Moon', 'Sibnet', 'Авто', '1080p', '720p']) {
        expect(find.text(t), findsOneWidget, reason: t);
      }

      await tester.tap(find.text('720p'));
      await settle(tester);
      expect(rig.engine.lastUrl, 'https://moon/e1/720.m3u8');
      rig.started();

      await tester.tap(find.text('Sibnet'));
      await settle(tester);
      expect(rig.engine.lastUrl, 'https://sibnet/e1.m3u8');
      rig.started();
      rig.driver.stop();
    });

    testWidgets('телефон: рядки й вкладки не нижчі за 48 dp, нічого не переповнює екран', (tester) async {
      AppPlatform.debugMobile = true;
      setScreen(tester, kPhone);
      final rig = newRig();
      await tester.pumpWidget(panelHost(rig, sheet: true));
      await tester.runAsync(() => rig.driver.start(rig.launch()));
      rig.started();
      await settle(tester);
      expect(tester.getSize(find.byWidgetPredicate((w) => w is AppSegmentedBar)).height, greaterThanOrEqualTo(48));
      expect(tester.getSize(find.byType(AppSelectableSurface).first).height, greaterThanOrEqualTo(48));
      for (final tab in ['Озвучка', 'Плеєр', 'Серії']) {
        await tester.tap(find.text(tab));
        await settle(tester);
      }
      expect(tester.takeException(), isNull);
      rig.driver.stop();
    });

    testWidgets('сесію зупинено, а панель ще на екрані — порожній стан без помилок', (tester) async {
      setScreen(tester, kDesktop);
      final rig = newRig();
      await tester.pumpWidget(panelHost(rig));
      await tester.runAsync(() => rig.driver.start(rig.launch()));
      rig.started();
      rig.driver.stop();
      await settle(tester);
      expect(find.text('Серій немає'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
