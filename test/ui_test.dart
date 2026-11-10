import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:miki_miki/services/anime4k_service.dart';
import 'package:miki_miki/services/osd_message.dart';
import 'package:miki_miki/services/shortcut_catalog.dart';
import 'package:miki_miki/services/ui_theme_service.dart';
import 'package:miki_miki/widgets/app_animation_kit.dart';
import 'package:miki_miki/widgets/app_settings_dialog.dart';
import 'package:miki_miki/widgets/osd_toast.dart';
import 'package:miki_miki/widgets/settings_drawer.dart';
import 'package:miki_miki/widgets/shortcuts_view.dart';

import 'support/fakes.dart';

void setScreen(WidgetTester tester, double w, double h) {
  tester.view.physicalSize = Size(w, h);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Widget host(void Function(BuildContext) opener) => MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF3B4A57),
        body: Builder(builder: (context) => Center(child: ElevatedButton(onPressed: () => opener(context), child: const Text('open')))),
      ),
    );

/// Перший pump будує кадр, другий проганяє анімацію (інакше вона стоїть на нулі)
Future<void> tick(WidgetTester tester, [int ms = 600]) async {
  await tester.pump();
  await tester.pump(Duration(milliseconds: ms));
}

Future<void> shot(WidgetTester tester, String name) =>
    expectLater(find.byType(MaterialApp), matchesGoldenFile('shots/$name.png'));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadTestFonts();
  });

  setUp(() {
    uiTheme.setThemeMode('dark');
  });

  group('OsdToast', () {
    testWidgets('показує заголовок, значення, клавіші й ховається', (tester) async {
      setScreen(tester, 640, 360);
      final msg = ValueNotifier<OsdMessage?>(null);
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: const Color(0xFF3B4A57),
          body: Stack(children: [OsdToast(scale: 1.0, message: msg)]),
        ),
      ));
      expect(find.text('Anime4K'), findsNothing);

      msg.value = const OsdMessage(
        icon: Symbols.auto_awesome_rounded,
        title: 'Anime4K',
        detail: 'Режим A+A (HQ)',
        keys: ['Ctrl', '4'],
      );
      await tester.pump();
      await tick(tester, 400);
      expect(find.text('Anime4K'), findsOneWidget);
      expect(find.text('Режим A+A (HQ)'), findsOneWidget);
      expect(find.text('Ctrl'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
      await shot(tester, 'osd_anime4k');

      msg.value = const OsdMessage(icon: Symbols.volume_up_rounded, title: 'Гучність', detail: '65%', progress: 0.65);
      await tester.pump();
      await tick(tester, 400);
      expect(find.text('Гучність'), findsOneWidget);
      expect(find.text('Anime4K'), findsNothing);
      await shot(tester, 'osd_volume');

      msg.value = const OsdMessage(
        icon: Symbols.error_rounded,
        title: 'Anime4K вимкнено',
        detail: 'Помилка шейдера — перевірте драйвер відеокарти або оберіть режим Fast',
        isError: true,
      );
      await tester.pump();
      await tick(tester, 400);
      await shot(tester, 'osd_error');

      msg.value = null;
      await tester.pump();
      await tick(tester, 600);
      expect(find.text('Anime4K вимкнено'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('ніколи не перехоплює кліки', (tester) async {
      setScreen(tester, 640, 360);
      final msg = ValueNotifier<OsdMessage?>(const OsdMessage(icon: Symbols.info_rounded, title: 'Повідомлення'));
      int taps = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Stack(children: [
            Positioned.fill(child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => taps++)),
            OsdToast(scale: 1.0, message: msg),
          ]),
        ),
      ));
      await tick(tester, 400);
      await tester.tapAt(const Offset(320, 100));
      expect(taps, 1);
    });
  });

  group('ShortcutsView', () {
    test('пошук: слова, клавіші, англійські ідентифікатори', () {
      ShortcutDef def(String id) => ShortcutCatalog.byId[id]!;
      const s = KeyScheme.standard;
      expect(ShortcutsView.matches(def('play_pause'), s, 'пауза'), isTrue);
      expect(ShortcutsView.matches(def('play_pause'), s, 'PAUSE'), isTrue, reason: 'пошук за англійським id');
      expect(ShortcutsView.matches(def('play_pause'), s, 'гучність'), isFalse);
      expect(ShortcutsView.matches(def('a4k_mode_1'), s, 'ctrl 1'), isTrue);
      expect(ShortcutsView.matches(def('a4k_mode_1'), s, 'ctrl 2'), isFalse);
      expect(ShortcutsView.matches(def('seek_back_5'), s, 'seek'), isTrue);
      expect(ShortcutsView.matches(def('audio_delay_down'), s, 'ctrl -'), isTrue);
      expect(ShortcutsView.matches(def('fullscreen'), s, 'повноекран'), isTrue);
      expect(ShortcutsView.matches(def('fullscreen'), s, '   '), isTrue);
    });

    test('пошук комбінації: клавіші збігаються в межах однієї комбінації, «+» і пробіл рівноцінні', () {
      ShortcutDef def(String id) => ShortcutCatalog.byId[id]!;
      const s = KeyScheme.standard;
      // «1» у «0,1 с» не має чіплятися за «ctrl 1»
      expect(ShortcutsView.matches(def('audio_delay_down'), s, 'ctrl 1'), isFalse);
      expect(ShortcutsView.matches(def('audio_delay_up'), s, 'ctrl 1'), isFalse);
      for (final q in ['ctrl 1', 'ctrl+1', 'Ctrl + 1', 'CTRL+1']) {
        expect(ShortcutsView.matches(def('a4k_mode_1'), s, q), isTrue, reason: q);
        expect(ShortcutsView.matches(def('a4k_mode_2'), s, q), isFalse, reason: q);
      }
      // Клавіші мають бути в одній комбінації: у «Пауза» є Space, K, P, але не «k p»
      expect(ShortcutsView.matches(def('play_pause'), s, 'space'), isTrue);
      expect(ShortcutsView.matches(def('play_pause'), s, 'k p'), isFalse);
      // «ctrl++» — Ctrl і клавіша «+», «ctrl+» — ще не дописана комбінація
      expect(ShortcutsView.matches(def('audio_delay_up'), s, 'ctrl++'), isTrue);
      expect(ShortcutsView.matches(def('audio_delay_down'), s, 'ctrl++'), isFalse);
      expect(ShortcutsView.matches(def('audio_delay_down'), s, 'ctrl+'), isTrue);
      expect(ShortcutsView.matches(def('audio_delay_down'), s, 'ctrl −'), isTrue, reason: 'Unicode-мінус');
      expect(ShortcutsView.matches(def('audio_delay_down'), s, 'ctrl -'), isTrue);
      // Початок назви клавіші й псевдоніми
      expect(ShortcutsView.matches(def('a4k_mode_1'), s, 'ctr'), isTrue);
      expect(ShortcutsView.matches(def('play_pause'), s, 'пробіл'), isTrue);
      expect(ShortcutsView.matches(def('next_file'), s, 'ентер'), isTrue);
      expect(ShortcutsView.matches(def('seek_back_5'), s, 'вліво'), isTrue);
      expect(ShortcutsView.matches(def('seek_fwd_5'), s, 'вліво'), isFalse);
      expect(ShortcutsView.matches(def('seek_fwd_5'), s, 'right'), isTrue);
      // Односимвольне слово — лише клавіша
      expect(ShortcutsView.matches(def('mute'), s, 'm'), isTrue);
      expect(ShortcutsView.matches(def('audio_delay_down'), s, '1'), isFalse);
      // Слово з назви + клавіша
      expect(ShortcutsView.matches(def('play_pause'), s, 'пауза k'), isTrue);
      expect(ShortcutsView.matches(def('play_pause'), s, 'пауза z'), isFalse);
      // Список для «ctrl 1»: тільки Anime4K → Режим A
      final found = ShortcutsView.sections(s, 'ctrl 1').expand((e) => e.items).map((d) => d.id).toList();
      expect(found, ['a4k_mode_1']);
    });

    test('queryWords: роздільники й особливі випадки', () {
      expect(ShortcutsView.queryWords('  '), isEmpty);
      expect(ShortcutsView.queryWords('Ctrl+1'), ['ctrl', '1']);
      expect(ShortcutsView.queryWords('ctrl + shift + z'), ['ctrl', 'shift', 'z']);
      expect(ShortcutsView.queryWords('ctrl++'), ['ctrl', '+']);
      expect(ShortcutsView.queryWords('ctrl ++'), ['ctrl', '+']);
      expect(ShortcutsView.queryWords('ctrl +'), ['ctrl', '+'], reason: '«+» наприкінці — клавіша');
      expect(ShortcutsView.queryWords('ctrl + 1'), ['ctrl', '1'], reason: '«+» посередині — роздільник');
      expect(ShortcutsView.queryWords('+'), ['+']);
      expect(ShortcutsView.queryWords('ctrl+'), ['ctrl']);
      expect(ShortcutsView.queryWords('ctrl −'), ['ctrl', '-']);
    });

    test('приховані комбінації не шукаються', () {
      // У каталозі Shift+Q прихована (дублікат Q), у довідці її немає
      expect(ShortcutsView.matches(ShortcutCatalog.byId['quit_video']!, KeyScheme.standard, 'shift q'), isFalse);
      expect(ShortcutsView.matches(ShortcutCatalog.byId['quit_video']!, KeyScheme.standard, 'ctrl w'), isTrue);
    });

    test('розбиття на колонки зберігає порядок і баланс', () {
      final sections = ShortcutsView.sections(KeyScheme.standard, '');
      final split = ShortcutsView.splitIndex(sections);
      expect(split, inInclusiveRange(1, sections.length - 1));
      final left = sections.take(split).fold<int>(0, (s, e) => s + e.weight);
      final right = sections.skip(split).fold<int>(0, (s, e) => s + e.weight);
      expect((left - right).abs(), lessThan(sections.map((e) => e.weight).reduce((a, b) => a > b ? a : b)));
      expect(sections.map((s) => s.group).toList(), ShortcutGroup.values);
    });

    test('splitIndex для однієї й двох груп', () {
      final one = ShortcutsView.sections(KeyScheme.standard, 'anime4k a4k');
      expect(ShortcutsView.splitIndex(one), one.length);
      expect(ShortcutsView.splitIndex(const []), 0);
    });
  });

  group('ShortcutsDialog', () {
    Future<FakeController> open(WidgetTester tester, {double w = 1280, double h = 800, KeyScheme scheme = KeyScheme.standard}) async {
      setScreen(tester, w, h);
      final c = FakeController(scheme: scheme);
      await tester.pumpWidget(host((ctx) => ShortcutsDialog.show(ctx, 1.0, c)));
      await tester.tap(find.text('open'));
      await tester.pump();
      await tick(tester, 500);
      return c;
    }

    testWidgets('показує заголовок, групи, схеми й комбінації', (tester) async {
      await open(tester);
      expect(find.text('Гарячі клавіші'), findsOneWidget);
      expect(find.text('Стандартна'), findsOneWidget);
      expect(find.text('Як у mpv'), findsOneWidget);
      expect(find.text('Відтворення'), findsOneWidget);
      expect(find.text('Пауза / відтворення'), findsOneWidget);
      expect(find.text('Space'), findsWidgets);
      expect(tester.takeException(), isNull);
      await shot(tester, 'shortcuts_dark');
    });

    testWidgets('пошук фільтрує, порожній результат показує підказку', (tester) async {
      await open(tester);
      await tester.enterText(find.byType(TextField), 'ctrl 1');
      await tick(tester, 200);
      expect(find.text('Режим A'), findsOneWidget);
      expect(find.text('Пауза / відтворення'), findsNothing);
      await shot(tester, 'shortcuts_search');

      await tester.enterText(find.byType(TextField), 'ззззз');
      await tick(tester, 200);
      expect(find.textContaining('Нічого не знайдено'), findsOneWidget);
      await shot(tester, 'shortcuts_empty');
    });

    testWidgets('перемикач схеми одразу застосовує схему й змінює список', (tester) async {
      final c = await open(tester);
      expect(find.text('Гучніше на 5%'), findsOneWidget);
      expect(find.text('Назад на 1 хвилину'), findsNothing);

      await tester.tap(find.text('Як у mpv'));
      await tick(tester, 300);
      expect(c.keyScheme, KeyScheme.mpv);
      expect(find.text('Гучніше на 5%'), findsNothing);
      expect(find.text('Назад на 1 хвилину'), findsOneWidget);
      expect(find.text('Цикл A–B: початок → кінець → скинути'), findsOneWidget);
      await shot(tester, 'shortcuts_mpv');

      await tester.tap(find.text('Стандартна'));
      await tick(tester, 300);
      expect(c.keyScheme, KeyScheme.standard);
      expect(find.text('Гучніше на 5%'), findsOneWidget);
    });

    testWidgets('Esc: перший очищає пошук, другий закриває', (tester) async {
      await open(tester);
      await tester.enterText(find.byType(TextField), 'пауза');
      await tick(tester, 200);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tick(tester, 300);
      expect(find.text('Гарячі клавіші'), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tick(tester, 500);
      expect(find.text('Гарячі клавіші'), findsNothing);
    });

    testWidgets('F1 закриває, а «?» поза полем пошуку теж', (tester) async {
      await open(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.f1);
      await tick(tester, 500);
      expect(find.text('Гарячі клавіші'), findsNothing);

      await tester.tap(find.text('open'));
      await tick(tester, 500);
      expect(find.text('Гарячі клавіші'), findsOneWidget);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.slash);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tick(tester, 500);
      expect(find.text('Гарячі клавіші'), findsNothing);
    });

    testWidgets('F1 у полі пошуку не закриває довідку', (tester) async {
      await open(tester);
      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.f1);
      await tick(tester, 500);
      expect(find.text('Гарячі клавіші'), findsOneWidget);
    });

    testWidgets('Ctrl+F переводить фокус у пошук', (tester) async {
      await open(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus, isTrue);
    });

    testWidgets('повторне відкриття не створює другого вікна', (tester) async {
      setScreen(tester, 1280, 800);
      final c = FakeController();
      await tester.pumpWidget(host((ctx) {
        ShortcutsDialog.show(ctx, 1.0, c);
        ShortcutsDialog.show(ctx, 1.0, c);
      }));
      await tester.tap(find.text('open'));
      await tick(tester, 500);
      expect(find.byType(ShortcutsDialog), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tick(tester, 500);
      expect(find.byType(ShortcutsDialog), findsNothing);
    });

    testWidgets('вузьке вікно: одна колонка, елементи керування в стовпчик, без переповнення', (tester) async {
      await open(tester, w: 620, h: 700);
      expect(tester.takeException(), isNull);
      expect(find.text('Гарячі клавіші'), findsOneWidget);
      await shot(tester, 'shortcuts_narrow');
    });

    testWidgets('світла тема', (tester) async {
      uiTheme.setThemeMode('light');
      await open(tester);
      expect(tester.takeException(), isNull);
      await shot(tester, 'shortcuts_light');
    });

    testWidgets('масштаб інтерфейсу 1.4 без переповнення', (tester) async {
      setScreen(tester, 1600, 1000);
      final c = FakeController();
      await tester.pumpWidget(host((ctx) => ShortcutsDialog.show(ctx, 1.4, c)));
      await tester.tap(find.text('open'));
      await tick(tester, 500);
      expect(tester.takeException(), isNull);
      await shot(tester, 'shortcuts_scale14');
    });
  });

  group('Налаштування: Anime4K і гарячі клавіші', () {
    Future<FakeController> openSettings(WidgetTester tester, {double w = 1280, double h = 800}) async {
      setScreen(tester, w, h);
      final c = FakeController();
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(backgroundColor: const Color(0xFF3B4A57), body: Center(child: AppSettingsDialog(scale: 1.0, controller: c))),
      ));
      await tick(tester, 400);
      return c;
    }

    testWidgets('у меню є вкладки Anime4K та Гарячі клавіші', (tester) async {
      await openSettings(tester);
      expect(find.text('Anime4K'), findsOneWidget);
      expect(find.text('Гарячі клавіші'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    Future<void> toggleA4k(WidgetTester tester) async {
      final row = find.ancestor(of: find.text('Увімкнути Anime4K'), matching: find.byType(Row)).first;
      await tester.tap(find.descendant(of: row, matching: find.byType(GestureDetector)).last);
      await tick(tester);
    }

    bool a4kExpanded(WidgetTester tester) =>
        tester.widget<AppSlideDownCollapse>(find.byType(AppSlideDownCollapse).first).isExpanded;

    testWidgets('вкладка Anime4K: вимкнено → є лише перемикач, увімкнено → режими, якість, поріг', (tester) async {
      await openSettings(tester);
      await tester.tap(find.text('Anime4K'));
      await tick(tester);
      expect(find.text('Увімкнути Anime4K'), findsOneWidget);
      expect(a4kExpanded(tester), isFalse);
      expect(find.text('Застосувати'), findsNothing);
      await shot(tester, 'settings_a4k_off');

      await toggleA4k(tester);
      expect(a4kExpanded(tester), isTrue);
      expect(find.text('Режим A  ·  Відновлення та апскейл'), findsOneWidget);
      expect(find.text('Режим C+A  ·  C з додатковим відновленням'), findsOneWidget);
      expect(find.text('Fast · Швидкий'), findsOneWidget);
      expect(find.text('HQ · Висока якість'), findsOneWidget);
      expect(find.text('Не пропускати'), findsOneWidget);
      expect(find.text('Застосувати'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await shot(tester, 'settings_a4k_on');
    });

    testWidgets('вибір режиму вмикає Anime4K; «Застосувати» передає налаштування в рушій', (tester) async {
      final c = await openSettings(tester);
      await tester.tap(find.text('Anime4K'));
      await tick(tester);

      await toggleA4k(tester);
      expect(a4kExpanded(tester), isTrue);
      await tester.ensureVisible(find.text('Режим B+B  ·  B з другим проходом відновлення'));
      await tick(tester);
      await tester.tap(find.text('Режим B+B  ·  B з другим проходом відновлення'));
      await tick(tester);

      await tester.ensureVisible(find.text('HQ · Висока якість'));
      await tick(tester);
      await tester.tap(find.text('HQ · Висока якість'));
      await tick(tester);
      await tester.ensureVisible(find.text('від 1440p'));
      await tick(tester);
      await tester.tap(find.text('від 1440p'));
      await tick(tester);
      await shot(tester, 'settings_a4k_bb_hq');

      // До застосування рушій не чіпали
      expect(c.anime4k.enabled, isFalse);
      await tester.tap(find.text('Застосувати'));
      await settle(tester, () => c.commands.any((a) => a.contains('glsl-shaders')));
      await tick(tester, 200);

      expect(c.anime4k.enabled, isTrue);
      expect(c.anime4k.mode, Anime4kMode.bb);
      expect(c.anime4k.quality, Anime4kQuality.hq);
      expect(c.anime4k.skipHeight, 1440);
      final set = c.commands.lastWhere((a) => a.contains('glsl-shaders'));
      expect(set[3].split(':').map((p) => p.split('/').last).toList(), Anime4kService.chain(Anime4kMode.bb, Anime4kQuality.hq));
      // Кнопки «Застосувати» / «Скасувати» зникли — змін більше немає
      expect(find.text('Застосувати'), findsNothing);
    });

    testWidgets('«Скасувати» повертає початкові значення', (tester) async {
      final c = await openSettings(tester);
      await tester.tap(find.text('Anime4K'));
      await tick(tester);
      await toggleA4k(tester);
      expect(a4kExpanded(tester), isTrue);
      expect(find.text('Скасувати'), findsOneWidget);
      await tester.tap(find.text('Скасувати'));
      await tick(tester);
      expect(find.text('Скасувати'), findsNothing);
      expect(a4kExpanded(tester), isFalse);
      expect(c.anime4k.enabled, isFalse);
      expect(c.commands.where((a) => a.contains('glsl-shaders')), isEmpty);
    });

    testWidgets('«Скинути» на вкладці Anime4K повертає значення за замовчуванням', (tester) async {
      await openSettings(tester);
      await tester.tap(find.text('Anime4K'));
      await tick(tester);
      await toggleA4k(tester);
      expect(a4kExpanded(tester), isTrue);
      await tester.tap(find.text('Скинути'));
      await tick(tester);
      expect(a4kExpanded(tester), isFalse);
      await tick(tester, 2600);
    });

    testWidgets('вкладка Гарячі клавіші: схема, пошук, список, застосування', (tester) async {
      final c = await openSettings(tester);
      await tester.tap(find.text('Гарячі клавіші').first);
      await tick(tester, 500);
      expect(find.text('Схема клавіш'), findsOneWidget);
      expect(find.text('Усі комбінації'), findsOneWidget);
      expect(find.text('Пауза / відтворення'), findsOneWidget);
      await shot(tester, 'settings_hotkeys');

      await tester.tap(find.text('Як у mpv'));
      await tick(tester, 400);
      expect(find.text('Назад на 1 хвилину'), findsOneWidget);
      expect(c.keyScheme, KeyScheme.standard, reason: 'до «Застосувати» схема не змінюється');

      await tester.tap(find.text('Застосувати'));
      await tick(tester, 300);
      await settle(tester, () => c.keyScheme == KeyScheme.mpv);

      await tester.enterText(find.byType(TextField), 'anime');
      await tick(tester, 300);
      expect(find.text('Режим C+A'), findsOneWidget);
      expect(find.text('Пауза / відтворення'), findsNothing);
      await shot(tester, 'settings_hotkeys_search');
    });

    testWidgets('світла тема: обидві нові вкладки', (tester) async {
      uiTheme.setThemeMode('light');
      await openSettings(tester);
      await tester.tap(find.text('Anime4K'));
      await tick(tester, 500);
      await toggleA4k(tester);
      await shot(tester, 'settings_a4k_light');
      await tester.tap(find.text('Гарячі клавіші').first);
      await tick(tester, 500);
      await shot(tester, 'settings_hotkeys_light');
      expect(tester.takeException(), isNull);
    });
  });

  group('Меню Anime4K', () {
    Widget drawer(FakeController c, {String active = 'anime4k', String? prev}) => MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            backgroundColor: const Color(0xFF3B4A57),
            body: Stack(children: [
              SettingsDrawer(
                scale: 1.0,
                screenWidth: 1280,
                drawerAnchorPixelX: 1100,
                drawerIsTop: false,
                activeDrawer: active,
                activeDrawerPrev: prev,
                player: c.fakePlayer,
                currentSpeed: 1.0,
                currentHwdec: 'd3d11va-copy',
                subtitleTracks: const [],
                audioTracks: const [],
                chapters: const [],
                scrollController: ScrollController(),
                onClose: () {},
                onBack: () {},
                onOpenSubDrawer: (_) {},
                onSpeedSelected: (_) {},
                onSubtitleSelected: (_) {},
                onAudioSelected: (_) {},
                onHwdecSelected: (_) {},
                onOpenChaptersSidePanel: () {},
                onOpenStats: () {},
                anime4k: c.anime4k,
              ),
            ]),
          ),
        );

    testWidgets('сторінка Anime4K: режими з комбінаціями, вибір працює', (tester) async {
      setScreen(tester, 1280, 800);
      final c = FakeController();
      await tester.pumpWidget(drawer(c));
      await tick(tester, 500);
      expect(find.text('Anime4K'), findsOneWidget);
      expect(find.text('Режим A'), findsOneWidget);
      expect(find.text('Режим C+A'), findsOneWidget);
      expect(find.text('Вимкнено'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await shot(tester, 'drawer_a4k_off');

      await tester.tap(find.text('Режим B'));
      await settle(tester, () => c.commands.any((a) => a.contains('glsl-shaders')));
      expect(c.anime4k.mode, Anime4kMode.b);
      expect(c.anime4k.enabled, isTrue);
      await tester.pumpWidget(drawer(c));
      await tick(tester, 400);
      await shot(tester, 'drawer_a4k_on');
    });

    testWidgets('головне меню показує рядок Anime4K зі станом', (tester) async {
      setScreen(tester, 1280, 800);
      final c = FakeController();
      await tester.pumpWidget(drawer(c, active: 'settings'));
      await tick(tester, 500);
      expect(find.text('Anime4K'), findsOneWidget);
      expect(find.text('Вимкнено'), findsWidgets);
      expect(tester.takeException(), isNull);
      await shot(tester, 'drawer_main');
    });
  });
}
