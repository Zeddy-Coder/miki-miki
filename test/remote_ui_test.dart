import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miki_miki/models/source_models.dart';
import 'package:miki_miki/services/episode_check.dart';
import 'package:miki_miki/services/episode_guide.dart';
import 'package:miki_miki/services/hikka_images.dart';
import 'package:miki_miki/services/remote_driver.dart';
import 'package:miki_miki/services/remote_playback.dart';
import 'package:miki_miki/services/ui_theme_service.dart';
import 'package:miki_miki/services/watch_models.dart';
import 'package:miki_miki/utils/platform_info.dart';
import 'package:miki_miki/widgets/app_ui_kit.dart';
import 'package:miki_miki/widgets/line_icons.dart';
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

/// The frame that applies the change and two more with time: animations (appearance, switching, scrolling) finish
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

/// A stand with a long open limit: the watchdog timer does not fire in the middle of a check
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

Widget panelHost(Rig rig, {bool sheet = false, ValueChanged<int>? onEpisode, double width = 380, double height = 560}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  home: Scaffold(
    body: ListenableBuilder(
      listenable: rig.driver,
      builder:
          (context, _) => Align(
            alignment: Alignment.topRight,
            child: SizedBox(
              width: width,
              height: height,
              child: ColoredBox(
                color: uiTheme.bgSurface,
                child: RemotePanelBody(scale: 1, driver: rig.driver, sheet: sheet, onEpisodeSelected: onEpisode ?? (_) {}, onClose: () {}),
              ),
            ),
          ),
    ),
  ),
);

/// A line icon (the panel draws icons with [LineIconView], not font glyphs)
Finder lineIcon(LineIcon icon) => find.byWidgetPredicate((w) => w is LineIconView && w.icon == icon);

/// Titles and stills as [make] gives them for the numbers asked, after [wait] when it is set (titles on their way);
/// what was asked is kept
class FakeGuide extends EpisodeGuideService {
  final EpisodeGuide? Function(int from, int to) make;
  final List<(int, int)> asked = [];
  Future<void>? wait;

  FakeGuide(this.make, {this.wait}) : super(persist: false, malId: (_) async => null);

  @override
  EpisodeGuide? peek(String animeKey, int from, int to) => null;

  @override
  Future<EpisodeGuide?> load(String animeKey, int from, int to) async {
    asked.add((from, to));
    if (wait != null) await wait;
    return make(from, to);
  }
}

/// Episodes [from]–[to] weekly from 8 April: Ukrainian titles for the odd ones, English for all, a still for all but
/// the fifth ([stills]), 24 minutes, the sixth a filler, the third with a description
EpisodeGuide guideFor(int from, int to, {bool stills = true}) => EpisodeGuide(1, {
      for (var n = from; n <= to; n++)
        n: GuideEpisode(
          n,
          uk: n.isOdd ? 'Українська назва $n' : null,
          en: 'English title $n',
          ja: 'タイトル$n',
          aired: DateTime.utc(2026, 4, 8).add(Duration(days: 7 * (n - 1))),
          still: stills && n != 5 ? '${EpisodeGuideService.stills}/s$n.jpg' : null,
          runtime: 24,
          filler: n == 6,
          about: n == 3 ? 'Опис третьої серії.' : null,
        ),
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadTestFonts();
  });

  setUp(() {
    uiTheme.setThemeMode('dark');
    // No titles unless a test gives them: the episodes are plates, and nothing goes to the network
    EpisodeGuideService.instance = EpisodeGuideService(persist: false, malId: (_) async => null);
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
      final rig = Rig(); // short limits (real time)
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
      expect(rig.driver.hoster, 'Sibnet'); // the last one tried

      rig.engine.failOpen = null;
      await tester.tap(find.text('Інший плеєр'));
      await settle(tester);
      expect(rig.engine.lastUrl, startsWith('https://moon/e1/'));
      rig.started();
      rig.driver.stop();
    });

    testWidgets('кінець озвучки без наступної серії: картка з вибором озвучення замість «Це остання серія»', (tester) async {
      setScreen(tester, kDesktop);
      final rig = newRig(episodes: [1, 2, 3, 4, 5]);
      final a = WatchGroup(id: 'a', sourceId: 'src', label: 'Amanogawa', episodes: [ep(1), ep(2), ep(3)]);
      final b = WatchGroup(id: 'b', sourceId: 'src', label: 'Далі Буде', episodes: [ep(4), ep(5)]);
      final title = WatchTitle(animeKey: 'hikka:test', offers: [WatchOffer(source: rig.source, anime: const SAnime(url: 'a', title: 'A'), groups: [a, b])]);
      await tester.pumpWidget(statusHost(rig));
      await tester.runAsync(() => rig.driver.start(RemoteLaunch(title: title, group: a, animeTitle: 'Аніме', epKey: '3')));
      rig.started();
      await settle(tester);
      expect(find.textContaining('немає в цій озвучці'), findsNothing);

      await tester.runAsync(() => rig.driver.onCompleted());
      await settle(tester);
      expect(find.text('Серії 4 немає в цій озвучці'), findsOneWidget);
      expect(find.textContaining('Далі Буде'), findsWidgets);

      await tester.tap(find.text('Закрити'));
      await settle(tester);
      expect(find.textContaining('немає в цій озвучці'), findsNothing);
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
      expect(tester.takeException(), isNull); // the card fits a narrow screen
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

  group('панель «Перегляд» серій із сайту', () {
    Finder plate(String n) => find.descendant(of: find.byKey(const ValueKey('watch-episodes')), matching: find.text(n));

    testWidgets('озвучення рядком, серії плашками: поточна виділена, переглянуті з галочкою, тап обирає серію', (tester) async {
      setScreen(tester, kDesktop);
      final rig = newRig();
      rig.store.setWatched('hikka:test', '2', true);
      final picked = <int>[];
      await tester.pumpWidget(panelHost(rig, onEpisode: picked.add));
      await tester.runAsync(() => rig.driver.start(rig.launch()));
      rig.started();
      await settle(tester);

      expect(find.text('Перегляд'), findsOneWidget);
      expect(find.text('Аніме'), findsOneWidget, reason: 'назва аніме під заголовком');
      expect(find.text('Команда А'), findsOneWidget);
      expect(find.text('1–3 сер.'), findsOneWidget, reason: 'які серії є в озвученні');
      for (final n in ['1', '2', '3']) {
        expect(plate(n), findsOneWidget, reason: n);
      }
      // the current plate is selected, the watched one has a check mark
      final current = tester.widget<Semantics>(find.descendant(of: find.byKey(const ValueKey('ep-0')), matching: find.byType(Semantics)).first);
      expect(current.properties.selected, isTrue);
      expect(find.descendant(of: find.byKey(const ValueKey('ep-1')), matching: lineIcon(LineIcon.check)), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('ep-2')), matching: lineIcon(LineIcon.check)), findsNothing);
      // quality and the site's player as rows with the current value
      expect(find.descendant(of: find.byKey(const ValueKey('watch-quality')), matching: find.text('1080p')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('watch-player')), matching: find.text('Moon')), findsOneWidget);

      await tester.tap(plate('3'));
      expect(picked, [2]);
      await expectLater(find.byType(RemotePanelBody), matchesGoldenFile('shots/remote_panel_desktop.png'));
      rig.driver.stop();
    });

    testWidgets('серії: довге утримання ставить і знімає позначку «Переглянуто»', (tester) async {
      setScreen(tester, kDesktop);
      final rig = newRig();
      rig.store.setWatched('hikka:test', '2', true);
      await tester.pumpWidget(panelHost(rig));
      await tester.runAsync(() => rig.driver.start(rig.launch()));
      rig.started();
      await settle(tester);

      await tester.longPress(plate('3'));
      await settle(tester);
      expect(rig.store.isWatched('hikka:test', '3'), isTrue);
      expect(find.descendant(of: find.byKey(const ValueKey('ep-2')), matching: lineIcon(LineIcon.check)), findsOneWidget);

      await tester.longPress(plate('2'));
      await settle(tester);
      expect(rig.store.isWatched('hikka:test', '2'), isFalse);
      expect(find.descendant(of: find.byKey(const ValueKey('ep-1')), matching: lineIcon(LineIcon.check)), findsNothing);
      rig.driver.stop();
    });

    testWidgets('довгий серіал: діапазони по 100, відкрито той, де поточна серія; решта плашок не будується', (tester) async {
      setScreen(tester, kDesktop);
      final rig = newRig(episodes: [for (var i = 1; i <= 300; i++) i]);
      await tester.runAsync(() => rig.driver.start(rig.launch(epKey: '200')));
      rig.started();
      await tester.pumpWidget(panelHost(rig));
      await settle(tester);
      for (final r in ['1–100', '101–200', '201–300']) {
        expect(find.text(r), findsOneWidget, reason: r);
      }
      expect(plate('200'), findsOneWidget);
      expect(plate('101'), findsOneWidget);
      expect(plate('1'), findsNothing);
      expect(plate('300'), findsNothing);
      expect(tester.getRect(plate('200')).bottom, lessThan(560), reason: 'поточна серія видна одразу');

      // the strip is above the plates: scrolled away while the current episode is in view
      await tester.ensureVisible(find.text('201–300'));
      await settle(tester);
      await tester.tap(find.text('201–300'));
      await settle(tester);
      expect(plate('300'), findsOneWidget);
      expect(plate('200'), findsNothing);
      rig.driver.stop();
    });

    testWidgets('панель стежить за поточною серією: перехід на далеку серію відкриває її діапазон', (tester) async {
      setScreen(tester, kDesktop);
      final rig = newRig(episodes: [for (var i = 1; i <= 300; i++) i]);
      await tester.runAsync(() => rig.driver.start(rig.launch()));
      rig.started();
      await tester.pumpWidget(panelHost(rig));
      await settle(tester);
      expect(plate('1'), findsOneWidget);

      await tester.runAsync(() => rig.driver.open(250));
      rig.started();
      await settle(tester);
      expect(plate('251'), findsOneWidget);
      expect(plate('1'), findsNothing);
      rig.driver.stop();
    });

    testWidgets('озвучення: окрема сторінка з озвученнями й субтитрами; вибір перемикає з тієї ж серії й повертає назад', (tester) async {
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

      await tester.tap(find.byKey(const ValueKey('watch-variant')));
      await settle(tester);
      expect(find.text('Озвучення й субтитри'), findsOneWidget);
      expect(find.text('Озвучення · 1'), findsOneWidget);
      expect(find.text('Субтитри · 1'), findsOneWidget);
      expect(find.text('1–3 сер. · src'), findsOneWidget);
      expect(find.text('1–2 сер. · src'), findsOneWidget);

      await tester.tap(find.text('Команда Б'));
      await settle(tester);
      expect(rig.driver.groupId, 'g2');
      expect(rig.driver.entry!.epKey, '2'); // the same episode in another variant
      expect(rig.driver.session!.entries, hasLength(2));
      expect(find.text('Перегляд'), findsOneWidget, reason: 'після вибору — назад до панелі');
      rig.driver.stop();
    });

    /// Three variants for a title with exactly 12 episodes on Hikka: merged (24), correct (12), incomplete (7)
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
      await tester.tap(find.byKey(const ValueKey('watch-variant')));
      await settle(tester);
      return (rig, merged, exact, part);
    }

    Finder warnIn(String id) => find.byKey(ValueKey('watch-variant-warn-$id'));

    testWidgets('озвучення: розбіжність з Hikka — пояснення над списком, жовта позначка в рядках, підпис про вибір', (tester) async {
      setScreen(tester, kDesktop);
      final (rig, _, _, _) = await mismatchRig(tester);

      expect(find.text('Перемикається з того ж місця. Вибір запамʼятовується'), findsOneWidget);
      // The current variant is merged: an explanation above the list
      expect(find.textContaining('Тут 24 серій, а на Hikka їх лише 12.'), findsOneWidget);
      expect(find.textContaining('передаватимуться на Hikka'), findsNothing, reason: 'за номером серії — і так зрозуміло');
      expect(find.text('1–24 з 12 · src'), findsOneWidget);
      expect(find.text('12 з 12 серій · src'), findsOneWidget);
      expect(find.text('1–7 з 12 · src'), findsOneWidget);
      // A yellow mark by the merged and the incomplete one, the correct variant without it
      expect(warnIn('m'), findsOneWidget);
      expect(warnIn('p'), findsOneWidget);
      expect(warnIn('e'), findsNothing);
      rig.driver.stop();
    });

    testWidgets('озвучення: перехід на правильний варіант прибирає пояснення й запамʼятовує вибір', (tester) async {
      setScreen(tester, kDesktop);
      final (rig, _, exact, _) = await mismatchRig(tester);
      expect(rig.store.favoriteChoices, isEmpty);

      await tester.tap(find.text('Рівно'));
      await settle(tester);
      expect(rig.driver.groupId, 'e');
      expect(rig.driver.session!.entries, hasLength(12));
      // back on the panel: the dub row without the warning
      expect(find.descendant(of: find.byKey(const ValueKey('watch-variant')), matching: lineIcon(LineIcon.warning)), findsNothing);
      expect(rig.store.preferredGroup('hikka:test'), 'e');
      expect(rig.store.favoriteChoices, [choiceKeyOf(exact)]);
      rig.driver.stop();
    });

    testWidgets('телефон: озвучення з поясненням і жовтими позначками — рядки не нижчі за 48 dp, без переповнення', (tester) async {
      AppPlatform.debugMobile = true;
      setScreen(tester, kPhone);
      final (rig, _, _, _) = await mismatchRig(tester, sheet: true);

      expect(find.textContaining('Тут 24 серій, а на Hikka їх лише 12.'), findsOneWidget);
      for (final id in ['m', 'e', 'p']) {
        expect(tester.getSize(find.byKey(ValueKey('watch-variant-$id'))).height, greaterThanOrEqualTo(48), reason: id);
      }
      expect(tester.takeException(), isNull);
      rig.driver.stop();
    });

    testWidgets('якість і плеєр: рядки відкривають вибір, тап вмикає потрібне посилання', (tester) async {
      setScreen(tester, kDesktop);
      final rig = newRig();
      await tester.pumpWidget(panelHost(rig));
      await tester.runAsync(() => rig.driver.start(rig.launch()));
      rig.started();
      await settle(tester);

      await tester.tap(find.byKey(const ValueKey('watch-quality')));
      await settle(tester);
      for (final t in ['Авто', '1080p', '720p']) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
      await tester.tap(find.text('720p'));
      await settle(tester);
      expect(rig.engine.lastUrl, 'https://moon/e1/720.m3u8');
      rig.started();
      await settle(tester);
      expect(find.descendant(of: find.byKey(const ValueKey('watch-quality')), matching: find.text('720p')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('watch-player')));
      await settle(tester);
      expect(find.text('Moon'), findsOneWidget);
      await tester.tap(find.text('Sibnet'));
      await settle(tester);
      expect(rig.engine.lastUrl, 'https://sibnet/e1.m3u8');
      rig.started();
      rig.driver.stop();
    });

    testWidgets('телефон: плашки й рядки не нижчі за 40 / 48 dp, сторінки відкриваються без переповнення', (tester) async {
      AppPlatform.debugMobile = true;
      setScreen(tester, kPhone);
      final rig = newRig(episodes: [for (var i = 1; i <= 28; i++) i]);
      rig.store.setWatched('hikka:test', '1', true);
      await tester.pumpWidget(panelHost(rig, sheet: true, width: kPhone.width, height: 640));
      await tester.runAsync(() => rig.driver.start(rig.launch(epKey: '2')));
      rig.started();
      await settle(tester);
      expect(tester.getSize(find.byKey(const ValueKey('ep-5'))).height, greaterThanOrEqualTo(40));
      for (final k in ['watch-variant', 'watch-quality', 'watch-player']) {
        expect(tester.getSize(find.byKey(ValueKey(k))).height, greaterThanOrEqualTo(48), reason: k);
      }
      await expectLater(find.byType(RemotePanelBody), matchesGoldenFile('shots/remote_panel_phone.png'));
      for (final k in ['watch-quality', 'watch-player']) {
        await tester.tap(find.byKey(ValueKey(k)));
        await settle(tester);
        await tester.tap(find.byKey(const ValueKey('watch-back')));
        await settle(tester);
      }
      expect(tester.takeException(), isNull);
      rig.driver.stop();
    });

    group('список із назвами', () {
      late Directory images;
      late HikkaImageStore store;
      final stills = [for (final c in ['a', 'b', 'c']) File('test/data/guide/still_$c.jpg').readAsBytesSync()];

      setUp(() {
        store = HikkaImageStore.instance;
        images = Directory.systemTemp.createTempSync('stills');
        HikkaImageStore.instance = HikkaImageStore(dir: images, fetcher: (url) async => stills[url.length % 3]);
      });

      tearDown(() {
        HikkaImageStore.instance = store;
        images.deleteSync(recursive: true);
      });

      /// The stills of episodes [numbers] decoded before the panel asks for them (they load outside the test's clock:
      /// one asked for inside it would never come)
      Future<void> precacheStills(WidgetTester tester, Iterable<int> numbers) async {
        await tester.pumpWidget(const MaterialApp(home: SizedBox()));
        final ctx = tester.element(find.byType(SizedBox));
        await tester.runAsync(() async {
          for (final n in numbers) {
            await precacheImage(ResizeImage(HikkaImage('${EpisodeGuideService.stills}/s$n.jpg'), width: 104), ctx);
          }
        });
      }

      testWidgets('з кадрами: кадр із номером, назва (українська, інакше англійська), дата; переглянута з галочкою, поточна з поступом', (tester) async {
        setScreen(tester, kDesktop);
        final guide = FakeGuide((from, to) => guideFor(from, to));
        EpisodeGuideService.instance = guide;
        final rig = newRig(episodes: [for (var n = 1; n <= 12; n++) n]);
        rig.store.setWatched('hikka:test', '1', true);
        final picked = <int>[];
        await precacheStills(tester, [for (var n = 1; n <= 12; n++) if (n != 5) n]);
        await tester.pumpWidget(panelHost(rig, onEpisode: picked.add));
        await tester.runAsync(() => rig.driver.start(rig.launch(epKey: '2')));
        rig.started();
        rig.engine.position = const Duration(minutes: 3);
        await settle(tester);

        expect(guide.asked, [(1, 12)]);
        expect(find.text('Українська назва 1'), findsOneWidget);
        expect(find.text('English title 2'), findsOneWidget, reason: 'української нема — англійська');
        expect(find.text('Українська назва 3'), findsOneWidget);
        expect(plate('3'), findsOneWidget, reason: 'номер на кадрі');
        expect(find.textContaining('22 квітня'), findsOneWidget);
        expect(find.textContaining('філер'), findsOneWidget);
        final current = tester.widget<Semantics>(find.descendant(of: find.byKey(const ValueKey('ep-1')), matching: find.byType(Semantics)).first);
        expect(current.properties.selected, isTrue);
        expect(current.properties.label, 'Серія 2: English title 2');
        expect(find.descendant(of: find.byKey(const ValueKey('ep-0')), matching: lineIcon(LineIcon.check)), findsOneWidget);
        expect(find.descendant(of: find.byKey(const ValueKey('ep-1')), matching: find.byType(LinearProgressIndicator)), findsOneWidget);
        expect(find.descendant(of: find.byKey(const ValueKey('ep-1')), matching: find.textContaining('ще 21 хв')), findsOneWidget);
        await expectLater(find.byType(RemotePanelBody), matchesGoldenFile('shots/remote_panel_list_desktop.png'));

        await tester.tap(find.text('Українська назва 3'));
        expect(picked, [2]);
        await tester.longPress(find.text('Українська назва 3'));
        await settle(tester);
        await tester.tap(find.byKey(const ValueKey('detail-watched')));
        await settle(tester);
        expect(rig.store.isWatched('hikka:test', '3'), isTrue);
        expect(find.descendant(of: find.byKey(const ValueKey('ep-2')), matching: lineIcon(LineIcon.check)), findsOneWidget);
        rig.driver.stop();
      });

      testWidgets('без кадрів: номер, назва, дата й тривалість; на телефоні рядки не нижчі за 56 dp', (tester) async {
        AppPlatform.debugMobile = true;
        setScreen(tester, kPhone);
        EpisodeGuideService.instance = FakeGuide((from, to) => guideFor(from, to, stills: false));
        final rig = newRig(episodes: [for (var n = 1; n <= 28; n++) n]);
        rig.store.setWatched('hikka:test', '1', true);
        await tester.pumpWidget(panelHost(rig, sheet: true, width: kPhone.width, height: 640));
        await tester.runAsync(() => rig.driver.start(rig.launch(epKey: '2')));
        rig.started();
        await settle(tester);
        expect(find.textContaining('15 квітня · ще 24 хв'), findsOneWidget, reason: 'поточна: скільки лишилось');
        expect(find.textContaining('22 квітня · 24 хв'), findsOneWidget);
        expect(tester.getSize(find.byKey(const ValueKey('ep-4'))).height, greaterThanOrEqualTo(56));
        expect(find.descendant(of: find.byKey(const ValueKey('ep-1')), matching: find.byType(LinearProgressIndicator)), findsOneWidget);
        await expectLater(find.byType(RemotePanelBody), matchesGoldenFile('shots/remote_panel_list_phone.png'));
        expect(tester.takeException(), isNull);
        rig.driver.stop();
      });

      testWidgets('довгий серіал: поточна серія в полі зору, далекі рядки не будуються, діапазон перемикається без плашок', (tester) async {
        setScreen(tester, kDesktop);
        final guide = FakeGuide((from, to) => guideFor(from, to, stills: false));
        EpisodeGuideService.instance = guide;
        final rig = newRig(episodes: [for (var i = 1; i <= 300; i++) i]);
        await tester.runAsync(() => rig.driver.start(rig.launch(epKey: '200')));
        rig.started();
        await tester.pumpWidget(panelHost(rig));
        await settle(tester);
        expect(guide.asked, [(101, 200)]);
        final r = tester.getRect(find.text('English title 200'));
        expect((r.top > 0, r.bottom < 560), (true, true), reason: 'поточна серія видна одразу');
        expect(find.text('Українська назва 101'), findsNothing, reason: 'далеко вгорі — не будується');

        await tester.ensureVisible(find.text('201–300', skipOffstage: false));
        await settle(tester);
        await tester.tap(find.text('201–300'));
        await tester.pump();
        expect(find.byKey(const ValueKey('ep-200')), findsOneWidget);
        expect(find.descendant(of: find.byKey(const ValueKey('watch-episodes')), matching: find.byType(Wrap)), findsNothing, reason: 'поки назви йдуть — рядки, а не плашки');
        await settle(tester);
        expect(guide.asked.last, (201, 300));
        expect(find.text('Українська назва 201'), findsOneWidget);
        rig.driver.stop();
      });

      testWidgets('поки назви йдуть — сірі рядки-заготовки на місцях рядків, а не плашки; потім вони заповнюються', (tester) async {
        setScreen(tester, kDesktop);
        final ready = Completer<void>();
        EpisodeGuideService.instance = FakeGuide((from, to) => guideFor(from, to), wait: ready.future);
        final rig = newRig(episodes: [for (var n = 1; n <= 12; n++) n]);
        rig.store.setWatched('hikka:test', '1', true);
        await precacheStills(tester, [for (var n = 1; n <= 12; n++) if (n != 5) n]);
        await tester.pumpWidget(panelHost(rig));
        await tester.runAsync(() => rig.driver.start(rig.launch(epKey: '2')));
        rig.started();
        await settle(tester);
        final episodes = find.byKey(const ValueKey('watch-episodes'));
        expect(find.descendant(of: episodes, matching: find.byType(Wrap)), findsNothing, reason: 'не плашки');
        expect(find.text('Серія 3'), findsNothing, reason: 'замість назви — сіра риска');
        expect(plate('3'), findsOneWidget, reason: 'номер на сірому кадрі');
        expect(find.descendant(of: find.byKey(const ValueKey('ep-0')), matching: lineIcon(LineIcon.check)), findsOneWidget);
        final height = tester.getSize(find.byKey(const ValueKey('ep-3'))).height;

        ready.complete();
        await settle(tester);
        expect(find.text('Українська назва 3'), findsOneWidget);
        expect(tester.getSize(find.byKey(const ValueKey('ep-3'))).height, height, reason: 'рядки на тих самих місцях');
        rig.driver.stop();
      });

      testWidgets('тайтл без назв: плашки лишаються плашками, поки йде інший діапазон', (tester) async {
        setScreen(tester, kDesktop);
        final guide = FakeGuide((from, to) => null);
        EpisodeGuideService.instance = guide;
        final rig = newRig(episodes: [for (var i = 1; i <= 150; i++) i]);
        await tester.pumpWidget(panelHost(rig));
        await tester.runAsync(() => rig.driver.start(rig.launch(epKey: '1')));
        rig.started();
        await settle(tester);
        final wrap = find.descendant(of: find.byKey(const ValueKey('watch-episodes')), matching: find.byType(Wrap));
        expect(wrap, findsOneWidget);

        guide.wait = Completer<void>().future;
        await tester.tap(find.text('101–150'));
        await tester.pump();
        expect(guide.asked.last, (101, 150));
        expect(wrap, findsOneWidget, reason: 'без заготовок: назв у тайтла не було');
        rig.driver.stop();
      });

      testWidgets('телефон вертикально: утримання рядка — картка з описом, «Дивитися» й «Переглянуто»; дотик поза нею закриває', (tester) async {
        AppPlatform.debugMobile = true;
        setScreen(tester, kPhone);
        EpisodeGuideService.instance = FakeGuide((from, to) => guideFor(from, to, stills: false));
        final rig = newRig(episodes: [for (var n = 1; n <= 12; n++) n]);
        final picked = <int>[];
        await tester.pumpWidget(panelHost(rig, sheet: true, width: kPhone.width, height: 640, onEpisode: picked.add));
        await tester.runAsync(() => rig.driver.start(rig.launch(epKey: '2')));
        rig.started();
        await settle(tester);
        final card = find.byKey(const ValueKey('episode-card'));

        await tester.longPress(find.text('Українська назва 3'));
        await settle(tester);
        expect(card, findsOneWidget);
        expect(find.descendant(of: card, matching: find.text('Опис третьої серії.')), findsOneWidget);
        expect(find.descendant(of: card, matching: find.text('English title 3')), findsOneWidget, reason: 'оригінальна назва');
        expect(find.descendant(of: card, matching: find.textContaining('22 квітня')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('detail-watched')));
        await settle(tester);
        expect(rig.store.isWatched('hikka:test', '3'), isTrue);
        expect(card, findsNothing);

        await tester.longPress(find.text('Українська назва 3'));
        await settle(tester);
        expect(find.descendant(of: card, matching: find.text('Зняти позначку')), findsOneWidget);
        expect(rig.driver.panelBack!(), isTrue, reason: '«Назад» закриває картку');
        await settle(tester);
        expect(card, findsNothing);
        expect(rig.driver.panelBack!(), isFalse, reason: 'далі «Назад» закриває саму панель');

        await tester.longPress(find.text('Українська назва 5'));
        await settle(tester);
        await tester.tap(find.byKey(const ValueKey('detail-play')));
        await settle(tester);
        expect(picked, [4]);
        expect(card, findsNothing);

        await tester.longPress(find.text('Українська назва 7'));
        await settle(tester);
        await tester.tapAt(const Offset(40, 160));
        await settle(tester);
        expect(card, findsNothing, reason: 'дотик по затемненому списку закриває картку');
        expect(picked, [4], reason: 'і нічого не вмикає');
        expect(tester.takeException(), isNull);
        rig.driver.stop();
      });

      testWidgets('бічна панель: права кнопка відкриває сторінку серії; «Назад» повертає на те саме місце списку', (tester) async {
        setScreen(tester, kDesktop);
        EpisodeGuideService.instance = FakeGuide((from, to) => guideFor(from, to, stills: false));
        final rig = newRig(episodes: [for (var n = 1; n <= 28; n++) n]);
        final picked = <int>[];
        await tester.pumpWidget(panelHost(rig, onEpisode: picked.add));
        await tester.runAsync(() => rig.driver.start(rig.launch(epKey: '1')));
        rig.started();
        await settle(tester);
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
        await settle(tester);
        double offset() => tester.state<ScrollableState>(find.byType(Scrollable).first).position.pixels;
        final before = offset();
        expect(before, greaterThan(0));

        await tester.tap(find.text('Українська назва 13'), buttons: kSecondaryButton);
        await settle(tester);
        expect(find.text('Серія 13'), findsOneWidget, reason: 'заголовок сторінки');
        expect(find.byKey(const ValueKey('episode-card')), findsNothing);
        expect(find.byKey(const ValueKey('detail-play')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('watch-back')));
        await settle(tester);
        expect(find.text('Українська назва 13'), findsOneWidget);
        expect(offset(), before, reason: 'список на тому ж місці');

        await tester.tap(find.text('Українська назва 13'), buttons: kSecondaryButton);
        await settle(tester);
        await tester.tap(find.byKey(const ValueKey('detail-watched')));
        await settle(tester);
        expect(rig.store.isWatched('hikka:test', '13'), isTrue);
        expect(find.text('Українська назва 13'), findsOneWidget, reason: 'назад до списку');
        expect(picked, isEmpty);
        rig.driver.stop();
      });

      testWidgets('телефон набік (бічна панель): утримання рядка — сторінка, не картка', (tester) async {
        AppPlatform.debugMobile = true;
        setScreen(tester, const Size(997, 448));
        EpisodeGuideService.instance = FakeGuide((from, to) => guideFor(from, to, stills: false));
        final rig = newRig(episodes: [for (var n = 1; n <= 12; n++) n]);
        await tester.pumpWidget(panelHost(rig, sheet: true, height: 448));
        await tester.runAsync(() => rig.driver.start(rig.launch(epKey: '2')));
        rig.started();
        await settle(tester);
        await tester.longPress(find.text('Українська назва 3'));
        await settle(tester);
        expect(find.byKey(const ValueKey('episode-card')), findsNothing);
        expect(find.text('Серія 3'), findsOneWidget);
        expect(find.byKey(const ValueKey('detail-watched')), findsOneWidget);
        expect(rig.driver.panelBack!(), isTrue);
        await settle(tester);
        expect(find.text('Українська назва 3'), findsOneWidget);
        expect(tester.takeException(), isNull);
        rig.driver.stop();
      });

      testWidgets('назви з сайту, без MyAnimeList: список без кадрів', (tester) async {
        setScreen(tester, kDesktop);
        final rig = newRig();
        final named = WatchGroup(
          id: 'n',
          sourceId: 'src',
          label: 'Команда В',
          episodes: [
            const SEpisode(url: 'e1', name: 'Серія 1 - Хвіст Феї', number: 1),
            const SEpisode(url: 'e2', name: 'Серія 2 - Вогняний дракон', number: 2),
          ],
        );
        final title = WatchTitle(
          animeKey: 'hikka:test',
          offers: [
            WatchOffer(source: rig.source, anime: const SAnime(url: 'a', title: 'A'), groups: [named]),
          ],
        );
        await tester.pumpWidget(panelHost(rig));
        await tester.runAsync(() => rig.driver.start(RemoteLaunch(title: title, group: named, animeTitle: 'Аніме')));
        rig.started();
        await settle(tester);
        expect(find.text('Хвіст Феї'), findsOneWidget);
        expect(find.text('Вогняний дракон'), findsOneWidget);
        expect(plate('2'), findsOneWidget);
        rig.driver.stop();
      });
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
