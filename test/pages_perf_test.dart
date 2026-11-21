// Speed of every page with a lot of content, on a phone (412 dp, density 2.8) and a PC (1280×720), with data as
// heavy as real cases: the title page with real pictures (Frieren), the profile, 160 collections, a catalog of
// 600 titles, lists of a long-time viewer (840 titles), a busy two-week calendar, a voice actor with 450 works,
// a franchise of 64 titles, a collection of 150 with comments, a long article, 100 notifications, a 1150-episode
// series in "Перегляд", the catalog's search and filters, switching the main tabs.
//
// Each page: opening (the first frame and the frames while the data arrives), a fast scroll down with loading on
// the way, the plain scroll back (everything loaded), then 2 s of stillness. The checks are structural: a still page
// asks for no frames, a scroll frame rebuilds only what moves, nothing outside the page rebuilds, a long list builds
// only the visible rows. Frame times are debug-mode numbers on the CPU: printed for comparison, only a hanging frame fails.
// A table of all pages is printed at the end (and written to the file in PERF_REPORT, when set).
// Run: flutter test test/pages_perf_test.dart
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miki_miki/models/hikka_models.dart';
import 'package:miki_miki/services/episode_alerts.dart';
import 'package:miki_miki/services/hikka_nav.dart';
import 'package:miki_miki/widgets/app_settings_dialog.dart';
import 'package:miki_miki/widgets/design_kit.dart';
import 'package:miki_miki/widgets/hikka/hikka_banner.dart';
import 'package:miki_miki/widgets/hikka/hikka_cards.dart';
import 'package:miki_miki/widgets/hikka/hikka_common.dart';
import 'package:miki_miki/widgets/hikka/hikka_community_cards.dart';
import 'package:miki_miki/widgets/hikka/hikka_paged_list.dart';
import 'package:miki_miki/widgets/hikka/hikka_slate_view.dart';
import 'package:miki_miki/widgets/home_hub.dart';

import 'hikka_lists_ui_test.dart' as lists;
import 'support/fakes.dart';
import 'support/page_perf.dart';

/// One page's numbers for the table at the end
class _Row {
  final String name;
  final PerfFrames open;
  final PerfFrames cold;
  final PerfFrames warm;
  final int idle;
  final String items;
  final List<String> problems;
  final List<PerfFrames> steps;
  final PerfFrames? moving;

  _Row(this.name, this.open, this.cold, this.warm, this.idle, this.items, this.problems, {this.steps = const [], this.moving});
}

final List<_Row> _rows = [];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    WidgetController.hitTestWarningShouldBeFatal = true;
    await perfFonts();
  });
  tearDownAll(() {
    final b = StringBuffer('\n══ Швидкодія сторінок (debug, CPU): мс медіана / p90 / макс · перебудов медіана / p90 / макс ══\n');
    for (final r in _rows) {
      b.writeln(r.name);
      b.writeln('   відкриття: ${r.open.short}  (перший кадр ${r.open.ms.isEmpty ? 0 : r.open.ms.first.toStringAsFixed(0)} мс, '
          '${r.open.builds.isEmpty ? 0 : r.open.builds.first} перебудов)');
      b.writeln('      найважчий кадр: ${r.open.heaviestText()}');
      b.writeln('      звідки: ${r.open.rootsText()}');
      if (r.cold.ms.isNotEmpty) {
        b.writeln('   прокрутка з довантаженням: ${r.cold.short}');
        b.writeln('      найважчий кадр: ${r.cold.heaviestText()}');
        b.writeln('      звідки: ${r.cold.rootsText()}');
      }
      if (r.warm.ms.isNotEmpty) {
        b.writeln('   прокрутка (усе є): ${r.warm.short}; найчастіше: ${r.warm.topText(5)}');
        b.writeln('      звідки (найважчий): ${r.warm.rootsText(4)}');
      }
      for (final s in r.steps) {
        b.writeln('   ${s.name}: ${s.short}');
        b.writeln('      звідки: ${s.rootsText(4)}');
      }
      b.writeln('   холостий хід: ${r.idle} кадрів із 120; ${r.items}');
      if (r.idle > 0 && r.moving != null) b.writeln('      що рухається: ${r.moving!.topText(6)}; звідки: ${r.moving!.rootsText(3)}');
      if (r.problems.isNotEmpty) b.writeln('   ПРОБЛЕМИ: ${r.problems.join('; ')}');
    }
    debugPrint(b.toString());
    final out = Platform.environment['PERF_REPORT'];
    if (out != null && out.isNotEmpty) File(out).writeAsStringSync(b.toString(), mode: FileMode.append);
  });

  /// Opens a page with [open], scrolls it down [passes] times by [distance] (loading on the way), back up once, and
  /// waits; checks stillness, the rebuilds of a scroll frame and how many [item] widgets live at once ([maxItems])
  Future<void> page(
    WidgetTester tester, {
    required String name,
    required bool phone,
    required Future<void> Function() open,
    required Finder Function() ready,
    double distance = 2400,
    int passes = 4,
    int openRounds = 30,
    int maxScrollBuilds = 120,
    Finder Function()? items,
    int maxItems = 80,
    Future<void> Function(List<String> problems, List<PerfFrames> steps)? after,
  }) async {
    final who = '${phone ? 'телефон' : 'ПК'}: $name';
    final problems = <String>[];
    void check(bool ok, String why) {
      if (!ok) problems.add(why);
    }

    final opening = PerfFrames('$who — відкриття');
    await perfFrame(tester, opening, action: open);
    await perfSettle(tester, opening, rounds: openRounds);
    expect(tester.takeException(), isNull);
    expect(ready(), findsWidgets, reason: '$who: сторінка відкрилася');

    final d = phone ? distance : distance * 0.7;
    final cold = PerfFrames('$who — прокрутка вниз з довантаженням');
    final warm = PerfFrames('$who — прокрутка вгору');
    var idle = 0;
    var itemsText = '';
    if (passes > 0) {
      for (var pass = 0; pass < passes; pass++) {
        await perfScroll(tester, cold, distance: d, frames: 50);
        final pause = PerfFrames('pause');
        await perfSettle(tester, pause, rounds: 6);
        cold.merge(pause);
      }
      expect(tester.takeException(), isNull);
      if (items != null) {
        final n = items().evaluate().length;
        itemsText = 'у дереві зараз $n';
        check(n <= maxItems, 'будується $n елементів списку (дозволено $maxItems): список не лінивий');
      }
      // Back up, short of the top: pulling past it on a phone would start "pull to refresh"
      final back = math.min(d, perfScrollPosition(tester).pixels - 40);
      if (back > 200) {
        await perfScroll(tester, warm, distance: back, frames: 90, up: true);
        await lists.load(tester, rounds: 6);
      }
      check(warm.buildsP90 <= maxScrollBuilds, 'кадр прокрутки перебудовує p90 ${warm.buildsP90} (дозволено $maxScrollBuilds): ${warm.topText(8)}');
      for (final shell in ['HomeHub', 'HikkaHub', 'MaterialApp', 'Scaffold']) {
        check((warm.top[shell] ?? 0) == 0, 'прокрутка перебудовує оболонку ($shell)');
      }
      check(warm.msP90 < 120, 'кадри прокрутки повільні (p90 ${warm.msP90.toStringAsFixed(0)} мс)');
      check(warm.msMax < 400, 'кадр прокрутки завис (${warm.msMax.toStringAsFixed(0)} мс)');
      check(cold.msMax < 1500, 'кадр під час довантаження завис (${cold.msMax.toStringAsFixed(0)} мс)');
    }
    final steps = <PerfFrames>[];
    if (after != null) await after(problems, steps);
    final moving = PerfFrames('$who — холостий хід');
    idle = await perfIdleFrames(tester, moving: moving);
    check(idle == 0, 'нерухома сторінка просить кадри ($idle зі 120): нескінченна анімація чи таймер');
    check(opening.msMax < 1500, 'кадр відкриття завис (${opening.msMax.toStringAsFixed(0)} мс)');
    debugPrint('— $opening');
    if (passes > 0) {
      debugPrint('— $cold');
      debugPrint('— $warm');
    }
    debugPrint('— $who: холостий хід $idle; $itemsText${problems.isEmpty ? '' : '\n   ПРОБЛЕМИ: ${problems.join('; ')}'}');
    _rows.add(_Row(who, opening, cold, warm, idle, itemsText, problems, steps: steps, moving: moving));
    expect(problems, isEmpty);
  }

  /// Taps what [finder] finds after bringing it into view (a tab chip off the edge of its row, a range of episodes)
  Future<void> tapShown(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(finder);
  }

  /// A step measured as one stage of frames (a tap, a switch): its frame and [frames] more
  Future<PerfFrames> step(WidgetTester tester, String name, Future<void> Function() action, {int frames = 24, int settle = 0}) async {
    final f = PerfFrames(name);
    await perfFrame(tester, f, action: action);
    for (var i = 0; i < frames; i++) {
      await perfFrame(tester, f);
    }
    if (settle > 0) await perfSettle(tester, f, rounds: settle);
    debugPrint('— $f');
    return f;
  }

  Future<void> discover(WidgetTester tester, HikkaTab tab) async {
    HikkaNav.instance.setMain(MainTab.discover);
    await lists.load(tester, rounds: 10);
    if (tab != HikkaTab.overview) {
      HikkaNav.instance.setTab(tab);
      await lists.load(tester, rounds: 4);
    }
  }

  for (final phone in [true, false]) {
    final who = phone ? 'телефон' : 'ПК';

    testWidgets('сторінка тайтла: $who', (tester) async {
      await mountPerfHub(tester, phone: phone);
      HikkaNav.instance.setMain(MainTab.discover);
      await lists.load(tester, rounds: 6);
      await page(
        tester,
        name: 'Сторінка тайтла (Фрірен)',
        phone: phone,
        open: () async => HikkaNav.instance.openAnime(perfFrieren),
        ready: () => find.text('Проводжальниця Фрірен'),
        openRounds: 40,
        passes: 1,
        distance: 2600,
        maxScrollBuilds: 40,
        // Opening the description in place: a short animation, not a rebuild of the page
        after: (problems, steps) async {
          perfScrollPosition(tester).jumpTo(0);
          await lists.load(tester, rounds: 4);
          final more = find.text('Читати далі');
          if (more.evaluate().isEmpty) return;
          await tester.ensureVisible(more.first);
          await lists.load(tester, rounds: 2);
          final expand = await step(tester, '$who: розгортання опису', () => tester.tap(more.first), frames: 30);
          steps.add(expand);
          if (expand.buildsMax >= 400) problems.add('розгортання опису перебудовує ${expand.buildsMax}: ${expand.topText(8)}');
        },
      );
    });

    testWidgets('профіль: $who', (tester) async {
      await mountPerfHub(tester, phone: phone);
      await page(
        tester,
        name: 'Профіль',
        phone: phone,
        open: () async => HikkaNav.instance.setMain(MainTab.profile),
        ready: () => find.text('tester'),
        passes: 1,
        distance: 3000,
        maxScrollBuilds: 40,
      );
    });

    testWidgets('колекції: $who', (tester) async {
      await mountPerfHub(tester, phone: phone, data: (h) => PerfData.collections(h, 160));
      await discover(tester, HikkaTab.overview);
      await page(
        tester,
        name: 'Колекції (160)',
        phone: phone,
        open: () async => HikkaNav.instance.setTab(HikkaTab.collections),
        ready: () => find.byType(HikkaCollectionRow),
        passes: 6,
        maxScrollBuilds: 60,
        items: () => find.byType(HikkaCollectionRow),
        maxItems: 40,
        after: (problems, steps) async {
          final list = tester.widget<HikkaPagedList<HikkaCollection>>(find.byType(HikkaPagedList<HikkaCollection>));
          final loaded = list.pager.items.length;
          if (loaded <= 60) problems.add('список не довантажує сторінки під час прокрутки (завантажено $loaded)');
        },
      );
    });

    testWidgets('головна: $who', (tester) async {
      await mountPerfHub(tester, phone: phone, initial: MainTab.profile, data: (h) => PerfData.catalog(h, 600));
      await page(
        tester,
        name: 'Головна',
        phone: phone,
        open: () async => HikkaNav.instance.setMain(MainTab.home),
        ready: () => find.byType(HikkaBannerCarousel),
        passes: 2,
        items: () => find.byType(HikkaAnimeCard),
        maxItems: 70,
        // The banners turn by themselves while in sight; scrolled away they must stand still
        after: (problems, steps) async {
          final p = perfScrollPosition(tester);
          p.jumpTo(p.maxScrollExtent);
          await lists.load(tester, rounds: 4);
        },
      );
    });

    testWidgets('огляд «Усе»: $who', (tester) async {
      await mountPerfHub(tester, phone: phone, data: (h) {
        PerfData.catalog(h, 600);
        PerfData.collections(h, 160);
        PerfData.articles(h, 120);
      });
      await page(
        tester,
        name: 'Огляд · Усе',
        phone: phone,
        open: () async => HikkaNav.instance.setMain(MainTab.discover),
        ready: () => find.byType(HikkaCollectionFanCard),
        passes: 2,
      );
    });

    testWidgets('календар: $who', (tester) async {
      await mountPerfHub(tester, phone: phone, data: (h) => PerfData.schedule(h));
      await discover(tester, HikkaTab.overview);
      await page(
        tester,
        name: 'Календар (36 серій на день)',
        phone: phone,
        open: () async => HikkaNav.instance.setTab(HikkaTab.schedule),
        ready: () => find.textContaining('Серія '),
        passes: 3,
        items: () => find.textContaining('Серія '),
        maxItems: 40,
      );
    });

    testWidgets('каталог: $who', (tester) async {
      await mountPerfHub(tester, phone: phone, data: (h) => PerfData.catalog(h, 600));
      await discover(tester, HikkaTab.overview);
      await page(
        tester,
        name: 'Каталог (700 тайтлів)',
        phone: phone,
        open: () async => HikkaNav.instance.setTab(HikkaTab.anime),
        ready: () => find.byType(HikkaAnimeCard),
        passes: 6,
        items: () => find.byType(HikkaAnimeCard),
        maxItems: 60,
      );
    });

    testWidgets('статті: $who', (tester) async {
      await mountPerfHub(tester, phone: phone, data: (h) => PerfData.articles(h, 120));
      await discover(tester, HikkaTab.overview);
      await page(
        tester,
        name: 'Статті (120)',
        phone: phone,
        open: () async => HikkaNav.instance.setTab(HikkaTab.articles),
        ready: () => find.byType(HikkaArticleRow),
        passes: 5,
        items: () => find.byType(HikkaArticleRow),
        maxItems: 30,
      );
    });

    testWidgets('персонажі: $who', (tester) async {
      await mountPerfHub(tester, phone: phone, data: (h) => PerfData.characters(h, 300));
      await discover(tester, HikkaTab.overview);
      await page(
        tester,
        name: 'Персонажі (300)',
        phone: phone,
        open: () async => HikkaNav.instance.setTab(HikkaTab.characters),
        ready: () => find.byType(HikkaCharacterCard),
        passes: 6,
        items: () => find.byType(HikkaCharacterCard),
        maxItems: 60,
      );
    });

    testWidgets('списки: $who', (tester) async {
      await mountPerfHub(tester, phone: phone, data: (h) {
        PerfData.catalog(h, 900);
        PerfData.lists(h);
      });
      HikkaNav.instance.setMain(MainTab.lists);
      await lists.load(tester, rounds: 20);
      await page(
        tester,
        name: 'Списки · Переглянуто (600), сіткою',
        phone: phone,
        open: () => tapShown(tester, find.byKey(const ValueKey('list-tab-2'))),
        ready: () => find.byType(HikkaAnimeCard),
        passes: 6,
        items: () => find.byType(HikkaAnimeCard),
        maxItems: 60,
        after: (problems, steps) async {
          await perfScrollPosition(tester).moveTo(0);
          await lists.load(tester, rounds: 4);
          await tester.tap(find.byTooltip('Списком'));
          await lists.load(tester, rounds: 10);
          final rows = PerfFrames('$who: списки рядками — прокрутка');
          await perfScroll(tester, rows, distance: phone ? 2400 : 1700, frames: 60);
          await lists.load(tester, rounds: 6);
          await perfScroll(tester, rows, distance: phone ? 2400 : 1700, frames: 60, up: true);
          debugPrint('— $rows');
          if (rows.buildsP90 > 40) problems.add('рядки: кадр прокрутки перебудовує p90 ${rows.buildsP90}: ${rows.topText(8)}');
          await perfScrollPosition(tester).moveTo(0);
          await lists.load(tester, rounds: 4);
          await tester.tap(find.byTooltip('Сіткою'));
          await lists.load(tester, rounds: 6);
          // Switching the status tabs back and forth
          await perfScrollPosition(tester).moveTo(0);
          await lists.load(tester, rounds: 4);
          final tabs = await step(tester, '$who: списки — перемикання на «Дивлюсь»', () => tapShown(tester, find.byKey(const ValueKey('list-tab-0'))), settle: 8);
          steps.add(tabs);
          if (tabs.msMax > 1500) problems.add('перемикання вкладки списку зависло (${tabs.msMax.toStringAsFixed(0)} мс)');
        },
      );
    });

    testWidgets('сповіщення: $who', (tester) async {
      await mountPerfHub(tester, phone: phone, data: (h) {
        PerfData.catalog(h, 100);
        EpisodeAlerts.instance = PerfData.alerts(100);
      });
      await page(
        tester,
        name: 'Сповіщення (100)',
        phone: phone,
        open: () async => HikkaNav.instance.openNotifications(),
        ready: () => find.textContaining('Вийшла серія'),
        passes: 3,
        items: () => find.textContaining('Вийшла серія'),
        maxItems: 30,
      );
    });

    testWidgets('персонаж: $who', (tester) async {
      await mountPerfHub(tester, phone: phone, data: (h) => PerfData.characterPage(h, anime: 60, voices: 40));
      await page(
        tester,
        name: 'Персонаж (60 аніме, 40 озвучень)',
        phone: phone,
        open: () async => HikkaNav.instance.openCharacter('frieren-7f706c'),
        ready: () => find.text('Озвучення'),
        passes: 4,
        items: () => find.byType(AppMediaRow),
        maxItems: 25,
      );
    });

    testWidgets('людина: $who', (tester) async {
      await mountPerfHub(tester, phone: phone, data: (h) => PerfData.personPage(h, anime: 150, characters: 300));
      await page(
        tester,
        name: 'Людина (300 ролей, 150 аніме)',
        phone: phone,
        open: () async => HikkaNav.instance.openPerson('kanehito-yamada-d0a463'),
        ready: () => find.byType(HikkaCharacterCard),
        passes: 6,
        items: () => find.byType(HikkaCharacterCard),
        maxItems: 60,
      );
    });

    testWidgets('персонажі тайтла: $who', (tester) async {
      await mountPerfHub(tester, phone: phone, data: (h) => PerfData.animeCharacters(h, 150));
      await page(
        tester,
        name: 'Персонажі тайтла (150)',
        phone: phone,
        open: () async => HikkaNav.instance.openAnimeCharacters(perfFrieren),
        ready: () => find.byType(HikkaCharacterCard),
        passes: 4,
        items: () => find.byType(HikkaCharacterCard),
        maxItems: 60,
      );
    });

    testWidgets('автори: $who', (tester) async {
      await mountPerfHub(tester, phone: phone, data: (h) => PerfData.animeStaff(h, 120));
      await page(
        tester,
        name: 'Автори (120)',
        phone: phone,
        open: () async => HikkaNav.instance.openAnimeStaff(perfFrieren),
        ready: () => find.byType(AppMediaRow),
        passes: 4,
        items: () => find.byType(AppMediaRow),
        maxItems: 40,
      );
    });

    testWidgets('франшиза: $who', (tester) async {
      await mountPerfHub(tester, phone: phone, data: (h) => PerfData.franchise(h, 60));
      await page(
        tester,
        name: 'Франшиза (64 тайтли)',
        phone: phone,
        open: () async => HikkaNav.instance.openFranchise(perfFrieren),
        ready: () => find.byType(HikkaAnimeRow),
        passes: 4,
        items: () => find.byType(HikkaAnimeRow),
        maxItems: 30,
      );
    });

    testWidgets('колекція: $who', (tester) async {
      await mountPerfHub(tester, phone: phone, data: (h) => PerfData.collection(h, 'gen-big', 150));
      await page(
        tester,
        name: 'Колекція (150 з коментарями), рядками',
        phone: phone,
        open: () async => HikkaNav.instance.openCollection('gen-big'),
        ready: () => find.byType(HikkaPoster),
        passes: 5,
        items: () => find.byType(HikkaPoster),
        maxItems: 40,
        after: (problems, steps) async {
          await perfScrollPosition(tester).moveTo(0);
          await lists.load(tester, rounds: 4);
          final toGrid = await step(tester, '$who: колекція — «Сіткою»', () => tester.tap(find.byTooltip('Сіткою')), settle: 6);
          steps.add(toGrid);
          final grid = PerfFrames('$who: колекція сіткою — прокрутка');
          await perfScroll(tester, grid, distance: phone ? 2400 : 1700, frames: 60);
          await lists.load(tester, rounds: 6);
          await perfScroll(tester, grid, distance: phone ? 2400 : 1700, frames: 60, up: true);
          debugPrint('— $grid');
          if (grid.buildsP90 > 120) problems.add('сітка: кадр прокрутки перебудовує p90 ${grid.buildsP90}: ${grid.topText(8)}');
        },
      );
    });

    testWidgets('стаття: $who', (tester) async {
      await mountPerfHub(tester, phone: phone, data: (h) => PerfData.article(h, 'gen-long', repeats: 7));
      await page(
        tester,
        name: 'Стаття (133 блоки, 21 група картинок)',
        phone: phone,
        open: () async => HikkaNav.instance.openArticle('gen-long'),
        ready: () => find.byType(HikkaSlateView),
        passes: 5,
        items: () => find.byType(HikkaSlateImage),
        maxItems: 12,
      );
    });

    testWidgets('чужий профіль: $who', (tester) async {
      await mountPerfHub(tester, phone: phone, data: (h) => PerfData.catalog(h, 100));
      await page(
        tester,
        name: 'Чужий профіль',
        phone: phone,
        open: () async => HikkaNav.instance.openUser('other'),
        ready: () => find.text('other'),
        passes: 2,
      );
    });

    testWidgets('налаштування: $who', (tester) async {
      await mountPerfHub(tester, phone: phone);
      await page(
        tester,
        name: 'Налаштування · Відтворення',
        phone: phone,
        open: () async {
          if (phone) {
            HikkaNav.instance.openSettings(tab: AppSettingsDialog.tabPlayback);
          } else {
            AppSettingsDialog.show(tester.element(find.byType(HomeHub)), 1.0, FakeController(), initialTab: AppSettingsDialog.tabPlayback);
          }
        },
        ready: () => find.byType(AppSettingsDialog),
        passes: 2,
        distance: 1200,
      );
    });

    testWidgets('«Перегляд» довгого серіалу (1150 серій): $who', (tester) async {
      await mountPerfHub(tester, phone: phone, episodes: 1150);
      HikkaNav.instance.setMain(MainTab.discover);
      await lists.load(tester, rounds: 8);
      HikkaNav.instance.openAnime(perfFrieren);
      await lists.load(tester, rounds: 40);
      await page(
        tester,
        name: '«Перегляд»: 1150 серій',
        phone: phone,
        open: () => tester.tap(find.byTooltip('Ще')),
        ready: () => find.text('Озвучення'),
        passes: 0,
        after: (problems, steps) async {
          final all = find.textContaining('Показати всі');
          await tester.ensureVisible(all.first);
          await lists.load(tester, rounds: 4);
          final more = await step(tester, '$who: «Показати всі 1150»', () => tester.tap(all.first));
          final range = await step(tester, '$who: діапазон «1001–1100»', () => tapShown(tester, find.text('1001–1100').first));
          steps.addAll([more, range]);
          for (final s in [more, range]) {
            if (s.msMax > 1500) problems.add('${s.name}: кадр завис (${s.msMax.toStringAsFixed(0)} мс)');
            if (s.buildsMax > 4000) problems.add('${s.name}: ${s.buildsMax} перебудов за кадр');
          }
          await tester.tap(find.byTooltip('Закрити').last);
          await lists.load(tester, rounds: 8);
        },
      );
    });

    testWidgets('пошук у каталозі: $who', (tester) async {
      await mountPerfHub(tester, phone: phone, data: (h) => PerfData.catalog(h, 600));
      await discover(tester, HikkaTab.anime);
      await lists.load(tester, rounds: 10);
      await page(
        tester,
        name: 'Каталог: набір у пошуку',
        phone: phone,
        open: () => tester.tap(find.byKey(const ValueKey('discover-search'))),
        ready: () => find.byType(HikkaAnimeCard),
        passes: 0,
        openRounds: 4,
        after: (problems, steps) async {
          final typing = PerfFrames('$who: набір «Фрірен» по літері');
          const word = 'Фрірен';
          for (var i = 1; i <= word.length; i++) {
            await perfFrame(tester, typing, action: () => tester.enterText(find.byKey(const ValueKey('discover-search')), word.substring(0, i)));
            await perfFrame(tester, typing);
          }
          debugPrint('— $typing');
          steps.add(typing);
          if (typing.buildsMax > 300) problems.add('літера в пошуку перебудовує ${typing.buildsMax} віджетів: ${typing.topText(8)}');
          final results = await step(tester, '$who: результати пошуку', () async {}, frames: 30, settle: 12);
          steps.add(results);
          if (results.msMax > 1500) problems.add('кадр результатів пошуку завис');
        },
      );
    });

    testWidgets('фільтри каталогу: $who', (tester) async {
      await mountPerfHub(tester, phone: phone, data: (h) => PerfData.catalog(h, 600));
      await discover(tester, HikkaTab.anime);
      await lists.load(tester, rounds: 10);
      await page(
        tester,
        name: 'Каталог: панель фільтрів',
        phone: phone,
        open: () => tester.tap(find.byTooltip('Фільтри')),
        ready: () => find.text('Тип'),
        passes: 2,
        distance: 900,
        openRounds: 12,
      );
    });

    testWidgets('перемикання головних вкладок: $who', (tester) async {
      await mountPerfHub(tester, phone: phone, data: (h) {
        PerfData.catalog(h, 900);
        PerfData.lists(h);
        PerfData.collections(h, 60);
        PerfData.articles(h, 40);
      });
      final problems = <String>[];
      final first = PerfFrames('$who: вкладка вперше');
      final again = PerfFrames('$who: вкладка вдруге');
      for (final (i, tab) in [MainTab.discover, MainTab.lists, MainTab.profile, MainTab.home, MainTab.discover, MainTab.lists, MainTab.home, MainTab.profile].indexed) {
        final f = i < 4 ? first : again;
        await perfFrame(tester, f, action: () async => HikkaNav.instance.setMain(tab));
        await lists.load(tester, rounds: 20);
      }
      debugPrint('— $first');
      debugPrint('— $again');
      if (again.buildsMax > 600) problems.add('повернення на вкладку перебудовує ${again.buildsMax}: ${again.topText(8)}');
      if (first.msMax > 1500) problems.add('перша поява вкладки зависла (${first.msMax.toStringAsFixed(0)} мс)');
      final moving = PerfFrames('$who — холостий хід');
      final idle = await perfIdleFrames(tester, moving: moving);
      if (idle > 0) problems.add('нерухомий профіль просить кадри ($idle)');
      _rows.add(_Row('$who: перемикання вкладок (вперше / вдруге)', first, PerfFrames(''), again, idle, '', problems, moving: moving));
      expect(problems, isEmpty);
    });
  }
}
