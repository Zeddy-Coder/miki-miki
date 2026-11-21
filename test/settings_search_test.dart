import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miki_miki/services/ui_theme_service.dart';
import 'package:miki_miki/utils/platform_info.dart';
import 'package:miki_miki/widgets/app_settings_dialog.dart';
import 'package:miki_miki/widgets/settings_search.dart';

import 'support/fakes.dart';

Future<void> tick(WidgetTester tester, [int ms = 600]) async {
  await tester.pump();
  await tester.pump(Duration(milliseconds: ms));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async => loadTestFonts());
  setUp(() => uiTheme.setThemeMode('dark'));
  tearDown(() => AppPlatform.debugMobile = null);

  group('searchSettings', () {
    test('порожній запит — нічого; початок назви вище за входження й ключові слова', () {
      expect(searchSettings('  '), isEmpty);
      final r = searchSettings('шрифт');
      expect(r.first.title, 'Шрифт субтитрів', reason: 'назва починається із запиту');
      expect(r.map((e) => e.title), containsAll(['Розмір шрифту', 'Додати свій шрифт']));
      // by a keyword only: "pitch" is not in the title
      expect(searchSettings('pitch').single.title, 'Корекція висоти тону');
      // ґ and г are the same for the search
      expect(searchSettings('опенінг').map((e) => e.title), contains('Кнопка пропуску опенінґу й ендінґу'));
    });

    test('рядки лише для ПК чи лише для телефона не знаходяться на іншій платформі', () {
      AppPlatform.debugMobile = true;
      expect(searchSettings('орієнтація').map((e) => e.title), contains('Орієнтація плеєра'));
      expect(searchSettings('схема клавіш'), isEmpty);
      AppPlatform.debugMobile = false;
      expect(searchSettings('орієнтація'), isEmpty);
      expect(searchSettings('схема клавіш').single.tab, 8);
    });

    test('кількість результатів з правильним відмінком', () {
      expect(settingsResultsLabel(1), '1 результат');
      expect(settingsResultsLabel(3), '3 результати');
      expect(settingsResultsLabel(5), '5 результатів');
      expect(settingsResultsLabel(11), '11 результатів');
      expect(settingsResultsLabel(22), '22 результати');
    });
  });

  // The index is written by hand: every entry must point at a row (or a group caption) that really is on its tab
  for (final mobile in [false, true]) {
    testWidgets('кожен запис пошуку є на своїй вкладці (${mobile ? 'телефон' : 'ПК'})', (tester) async {
      AppPlatform.debugMobile = mobile;
      tester.view.physicalSize = mobile ? const Size(448, 997) : const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final tabs = {for (final e in settingsSearchIndex) if (e.available) e.tab};
      for (final tab in tabs) {
        await tester.pumpWidget(MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(body: AppSettingsDialog(key: ValueKey('tab$tab'), scale: 1.0, controller: FakeController(), initialTab: tab)),
        ));
        await tick(tester);
        for (final e in settingsSearchIndex.where((e) => e.tab == tab && e.available)) {
          final shown = e.spot ?? e.title;
          expect(find.text(shown, skipOffstage: false), findsWidgets, reason: '«${e.title}» → «$shown» на вкладці $tab');
        }
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('телефон: пошук на першому екрані відкриває розділ і показує знайдений рядок', (tester) async {
    AppPlatform.debugMobile = true;
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(body: AppSettingsDialog(scale: AppPlatform.mobileScale, controller: FakeController())),
    ));
    await tick(tester);
    await tester.enterText(find.byType(TextField), 'відступ');
    await tick(tester, 300);
    expect(find.byKey(const ValueKey('settings-menu-1')), findsNothing, reason: 'замість розділів — результати');
    expect(find.text('Субтитри › Вигляд тексту'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('settings-result-1-Відступ знизу')));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
    expect(find.byKey(const ValueKey('settings-menu')), findsNothing);
    final row = tester.getRect(find.text('Відступ знизу'));
    expect(row.bottom, lessThan(915), reason: 'знайдений рядок прокручено у видиму частину');
    expect(row.top, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('ПК: пошук у рядку заголовка замінює вміст вкладки результатами', (tester) async {
    AppPlatform.debugMobile = false;
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(body: AppSettingsDialog(scale: 1.0, controller: FakeController())),
    ));
    await tick(tester);
    expect(find.text('Тема оформлення'), findsOneWidget, reason: 'вікно на ПК одразу відкривається на вкладці');
    await tester.enterText(find.byType(TextField).first, 'декодер');
    await tick(tester, 300);
    expect(find.text('Тема оформлення'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('settings-result-3-Апаратний декодер відео')));
    await tick(tester, 900);
    expect(find.text('Апаратне декодування'), findsWidgets, reason: 'відкрито «Відео & GPU»');
    expect(tester.takeException(), isNull);
  });
}
