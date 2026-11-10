import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:miki_miki/models/hikka_models.dart';
import 'package:miki_miki/services/hikka_images.dart';
import 'package:miki_miki/services/hikka_nav.dart';
import 'package:miki_miki/services/hikka_prefs.dart';
import 'package:miki_miki/services/storage_service.dart';
import 'package:miki_miki/services/watch_store.dart';
import 'package:miki_miki/services/ui_theme_service.dart';
import 'package:miki_miki/utils/platform_info.dart';
import 'package:miki_miki/widgets/app_settings_dialog.dart';
import 'package:miki_miki/widgets/app_ui_kit.dart';
import 'package:miki_miki/widgets/hikka/hikka_airing_strip.dart';
import 'package:miki_miki/widgets/hikka/hikka_banner.dart';
import 'package:miki_miki/widgets/hikka/hikka_cards.dart';
import 'package:miki_miki/widgets/hikka/hikka_common.dart';
import 'package:miki_miki/widgets/hikka/hikka_continue_card.dart';
import 'package:miki_miki/widgets/hikka/hikka_community_cards.dart';
import 'package:miki_miki/widgets/hikka/hikka_hub.dart';
import 'package:miki_miki/widgets/hikka/hikka_page_kit.dart';
import 'package:miki_miki/widgets/home_hub.dart';

import 'support/fakes.dart';
import 'support/hikka_fakes.dart';

const Size kDesktop = Size(1280, 720);
const Size kLandscape = Size(997, 448);
const Size kPortrait = Size(448, 997);
const Size kNarrow = Size(360, 780);

const String frieren = 'sousou-no-frieren-ad4e3e';
const String ongoing = 'kyouran-reijou-nia-liston-byoujaku-reijou-ni-tensei-shita-kamigoroshi-no-bujin-no-karei-naru-musouroku-d98982';

void setScreen(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// Дає час мережі (підставній), диску й декодеру зображень: вони живуть у справжньому часі
Future<void> load(WidgetTester tester, {int rounds = 24}) async {
  for (int i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<void> shot(WidgetTester tester, String name) =>
    expectLater(find.byType(MaterialApp), matchesGoldenFile('shots/hikka_$name.png'));

/// Перший вертикальний список на сцені (корінна вкладка під відкритою сторінкою сюди не потрапляє — вона поза сценою)
Finder verticalScrollable() => find
    .byWidgetPredicate((w) => w is Scrollable && (w.axisDirection == AxisDirection.down || w.axisDirection == AxisDirection.up))
    .first;

double pageOffset(WidgetTester tester) => tester.state<ScrollableState>(verticalScrollable()).position.pixels;

Future<void> scrollPage(WidgetTester tester, double dy) async {
  await tester.drag(verticalScrollable(), Offset(0, -dy));
  await load(tester, rounds: 4);
}

/// Широкий банер AniList у карусельці (а не розмитий постер)
bool isWideBanner(Widget w) {
  if (w is! Image) return false;
  final p = w.image;
  final inner = p is ResizeImage ? p.imageProvider : p;
  return inner is HikkaImage && inner.url.startsWith('https://s4.anilist.co/');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late HikkaTestEnv env;
  late FakeHikka server;
  late List<String> opened;
  late List<int?> settingsOpened;

  setUpAll(() async {
    await loadTestFonts();
  });

  setUp(() {
    uiTheme.setThemeMode('dark');
    env = HikkaTestEnv();
    server = env.server;
    opened = env.opened;
    settingsOpened = [];
    HomeHub.debugReset();
  });

  tearDown(() {
    AppPlatform.debugMobile = null;
    StorageService.saveLocalLibrary(false);
    env.dispose();
  });

  Widget app(Widget child, {EdgeInsets pad = EdgeInsets.zero}) => MaterialApp(
        debugShowCheckedModeBanner: false,
        builder: (context, w) => MediaQuery(
          data: MediaQuery.of(context).copyWith(padding: pad, viewPadding: pad),
          child: w!,
        ),
        home: Scaffold(backgroundColor: uiTheme.bgPrimary, body: child),
      );

  HikkaHub hubOf({double scale = 1.0}) => HikkaHub(
        scale: scale,
        onOpenSettings: ({int? tab}) => settingsOpened.add(tab),
        localLibraryBuilder: (_) => const Center(child: Text('Тут медіатека')),
      );

  Widget hub({double scale = 1.0, EdgeInsets pad = EdgeInsets.zero}) => app(hubOf(scale: scale), pad: pad);

  void phone() => AppPlatform.debugMobile = true;

  // ── Десктоп ────────────────────────────────────────────────────────────────

  group('Десктоп 1280×720', () {
    testWidgets('«Продовжити перегляд»: горизонтальна картка; тап шукає озвучку, а не знайшовши — відкриває сторінку тайтлу', (tester) async {
      setScreen(tester, kDesktop);
      final slug = sampleMap('info_ongoing.json')['slug'] as String;
      WatchStore.instance.setLast('hikka:$slug', '3', 'g1');
      addTearDown(() => WatchStore.instance.forgetLast('hikka:$slug'));
      await tester.pumpWidget(hub());
      await load(tester);
      expect(find.text('Продовжити перегляд'), findsOneWidget);
      expect(find.byType(HikkaContinueCard), findsOneWidget);
      expect(find.textContaining('Серія 3'), findsWidgets);
      await tester.tap(find.byType(HikkaContinueCard));
      await load(tester, rounds: 6);
      expect(HikkaNav.instance.top?.kind, HikkaRouteKind.anime, reason: 'джерел немає: падаємо на сторінку тайтлу');
      expect(tester.takeException(), isNull);
    });

    testWidgets('головна: пошук, календар, банери й полиці', (tester) async {
      setScreen(tester, kDesktop);
      await tester.pumpWidget(hub());
      await load(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Пошук аніме…'), findsOneWidget);
      expect(find.byType(HikkaAiringStrip), findsOneWidget);
      expect(find.descendant(of: find.byType(HikkaAiringStrip), matching: find.byIcon(Symbols.calendar_month_rounded)), findsOneWidget);
      expect(find.byType(HikkaBannerCarousel), findsOneWidget);
      expect(find.text('Продовжити перегляд'), findsNothing, reason: 'історії перегляду ще немає');
      expect(find.text('Рекомендації'), findsOneWidget);
      expect(find.text('Найкращі за оцінкою'), findsOneWidget);
      expect(find.text('Зараз виходить'), findsOneWidget);
      expect(find.text('Анонси'), findsOneWidget);
      expect(find.text('Найпопулярніші'), findsOneWidget);
      expect(find.byType(HikkaAnimeCard), findsWidgets);
      await shot(tester, 'home_desktop');
    });

    testWidgets('сторінка аніме за посиланням: шапка, опис, інформація, полиці', (tester) async {
      setScreen(tester, kDesktop);
      await tester.pumpWidget(hub());
      await load(tester, rounds: 4);
      HikkaNav.instance.openAnime(frieren);
      await load(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Проводжальниця Фрірен'), findsWidgets);
      expect(find.text('Опис'), findsOneWidget);
      expect(find.text('Персонажі'), findsWidgets);
      expect(find.text('Франшиза'), findsOneWidget);
      expect(find.text('Рекомендації'), findsOneWidget);
      await shot(tester, 'anime_desktop_top');
      await scrollPage(tester, 560);
      expect(tester.takeException(), isNull);
      await shot(tester, 'anime_desktop_scrolled');
      await scrollPage(tester, 1600);
      await shot(tester, 'anime_desktop_bottom');
    });

    testWidgets('тап по картці відкриває аніме з даних списку; «Назад» повертає і зберігає прокрутку', (tester) async {
      setScreen(tester, kDesktop);
      await tester.pumpWidget(hub());
      await load(tester);
      await scrollPage(tester, 560);
      await tester.pump(const Duration(milliseconds: 500)); // шапка догортає анімацію й зсуває прокрутку
      final before = pageOffset(tester);
      expect(before, greaterThan(100));
      // Перша картка, що справді видна на екрані
      Offset? target;
      for (final e in find.byType(HikkaAnimeCard).evaluate()) {
        final c = tester.getCenter(find.byWidget(e.widget));
        if (c.dy > 120 && c.dy < 650 && c.dx > 60 && c.dx < 1200) {
          target = c;
          break;
        }
      }
      expect(target, isNotNull, reason: 'на екрані має бути хоч одна картка');
      await tester.tapAt(target!);
      await load(tester, rounds: 3);
      expect(HikkaNav.instance.top, isNotNull);
      expect(HikkaNav.instance.top!.kind, HikkaRouteKind.anime);
      await load(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Опис'), findsOneWidget);
      HikkaNav.instance.back();
      await load(tester, rounds: 6);
      expect(HikkaNav.instance.top, isNull);
      expect(find.text('Рекомендації'), findsOneWidget);
      expect(pageOffset(tester), before);
    });

    testWidgets('персонажі аніме, персонаж, франшиза', (tester) async {
      setScreen(tester, kDesktop);
      await tester.pumpWidget(hub());
      await load(tester, rounds: 4);
      HikkaNav.instance.openAnimeCharacters(frieren);
      await load(tester);
      expect(tester.takeException(), isNull);
      expect(find.byType(HikkaCharacterCard), findsWidgets);
      expect(find.text('Головний'), findsWidgets);
      await shot(tester, 'anime_characters_desktop');

      HikkaNav.instance.openCharacter('frieren-7f706c');
      await load(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Фрірен'), findsWidgets);
      expect(find.text('Озвучення'), findsOneWidget);
      expect(find.text('Аніме'), findsWidgets);
      await shot(tester, 'character_desktop');
      await scrollPage(tester, 700);
      await shot(tester, 'character_desktop_scrolled');

      HikkaNav.instance.openFranchise(frieren);
      await load(tester);
      expect(tester.takeException(), isNull);
      expect(find.textContaining('тайтли'), findsWidgets);
      expect(find.byType(HikkaAnimeRow), findsNWidgets(4));
      await shot(tester, 'franchise_years_desktop');
      await tester.tap(find.text('За групами'));
      await load(tester, rounds: 6);
      expect(find.text('Основна історія'), findsWidgets);
      await shot(tester, 'franchise_groups_desktop');
    });

    testWidgets('«Огляд»: поки розділ вантажиться, видно заглушки, а не коло', (tester) async {
      setScreen(tester, kDesktop);
      await tester.pumpWidget(hub());
      await load(tester, rounds: 4);
      HikkaNav.instance.setTab(HikkaTab.collections);
      await tester.pump();
      expect(find.byType(HikkaListSkeleton), findsOneWidget);
      HikkaNav.instance.setTab(HikkaTab.articles);
      await tester.pump();
      expect(find.byType(HikkaListSkeleton), findsOneWidget);
      HikkaNav.instance.setTab(HikkaTab.anime);
      await tester.pump();
      expect(find.byType(HikkaCardSkeleton), findsWidgets);
      await load(tester, rounds: 6);
      expect(find.byType(HikkaCardSkeleton), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('«Огляд»: розділи колекцій, статей, каталогу (пошук і фільтри), персонажів і календаря', (tester) async {
      setScreen(tester, kDesktop);
      await tester.pumpWidget(hub());
      await load(tester, rounds: 4);
      HikkaNav.instance.setMain(MainTab.discover);
      await load(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Огляд'), findsOneWidget);
      for (final t in HikkaTab.values) {
        expect(find.text(t.label), findsWidgets, reason: t.label);
      }
      expect(HikkaNav.instance.tab, HikkaTab.overview, reason: 'першим відкривається загальна сторінка');
      expect(HikkaNav.instance.tab.index, 0);
      expect(find.byType(HikkaAnimeCard), findsWidgets, reason: 'каталог на загальній сторінці');
      await tester.dragUntilVisible(find.byType(HikkaCollectionCard).first, find.byType(SingleChildScrollView).first, const Offset(0, -300));
      expect(find.byType(HikkaCollectionCard), findsWidgets);
      await tester.tap(find.text('Колекції').first);
      await load(tester);
      expect(HikkaNav.instance.tab, HikkaTab.collections);
      expect(find.text('Правило 3-ох Епізодів'), findsWidgets);
      await shot(tester, 'discover_collections_desktop');

      await tester.tap(find.text('Статті').first);
      await load(tester);
      expect(tester.takeException(), isNull);
      expect(find.byType(HikkaArticleCard), findsWidgets);
      expect(find.text('Новини'), findsWidgets);
      await shot(tester, 'discover_articles_desktop');

      await tester.tap(find.text('Каталог').first);
      await load(tester);
      expect(tester.takeException(), isNull);
      expect(find.byType(HikkaAnimeCard), findsWidgets);
      expect(find.textContaining('знайдено'), findsOneWidget);
      await shot(tester, 'catalog_desktop');

      await tester.tap(find.byTooltip('Фільтри'));
      await load(tester, rounds: 8);
      expect(tester.takeException(), isNull);
      expect(find.text('Скинути'), findsNothing, reason: 'доки нічого не вибрано, скидати нічого');
      expect(find.text('Показати результати'), findsOneWidget);
      await shot(tester, 'filters_desktop');
      await tester.tap(find.text('Онґоїнґ'));
      await load(tester, rounds: 4);
      expect(find.text('Скинути'), findsOneWidget);
      expect(find.text('Показати результати · 1'), findsOneWidget);
      await tester.tap(find.text('Скинути'));
      await load(tester, rounds: 4);
      expect(find.text('Скинути'), findsNothing);
      await tester.tap(find.text('Онґоїнґ'));
      await load(tester, rounds: 4);
      // «Показати результати» застосовує вибране й закриває панель
      await tester.tap(find.text('Показати результати · 1'));
      await load(tester);
      expect(find.text('Показати результати · 1'), findsNothing);
      expect(
        server.log.where((r) => r.url.path == '/anime' && r.method == 'POST').last.body,
        contains('"status":["ongoing"]'),
      );
      await shot(tester, 'catalog_filtered_desktop');
      // Вибір лишається: панель відкривається з ним, а «Назад» знову спершу закриває панель
      await tester.tap(find.byTooltip('Фільтри'));
      await load(tester, rounds: 8);
      expect(find.text('Скинути'), findsOneWidget);
      // «Назад» спершу закриває панель фільтрів
      expect(HikkaNav.instance.back(), isTrue);
      await load(tester, rounds: 6);
      expect(find.text('Показати результати'), findsNothing);
      expect(HikkaNav.instance.tab, HikkaTab.anime);

      await tester.tap(find.text('Персонажі').first);
      await load(tester);
      expect(tester.takeException(), isNull);
      expect(find.byType(HikkaCharacterCard), findsWidgets);
      await shot(tester, 'characters_desktop');

      await tester.tap(find.text('Календар').first);
      await load(tester);
      expect(tester.takeException(), isNull);
      expect(find.textContaining('серія'), findsWidgets);
      await shot(tester, 'schedule_desktop');
    });

    testWidgets('колекція: сторінка з тайтлами, посилання на сайт, 18+ закрита до підтвердження', (tester) async {
      setScreen(tester, kDesktop);
      await tester.pumpWidget(hub());
      await load(tester, rounds: 4);
      HikkaNav.instance.setTab(HikkaTab.collections);
      await load(tester);
      await tester.tap(find.byType(HikkaCollectionCard).first);
      await load(tester);
      expect(tester.takeException(), isNull);
      expect(HikkaNav.instance.top!.kind, HikkaRouteKind.collection);
      expect(find.text('Колекція'), findsOneWidget);
      expect(find.text('Правило 3-ох Епізодів'), findsWidgets);
      expect(find.text('12 тайтлів'), findsWidgets);
      expect(find.byType(HikkaAnimeCard), findsWidgets);
      await shot(tester, 'collection_desktop');
      await tester.tap(find.byTooltip('Відкрити на hikka.io'));
      await tester.pump();
      expect(opened.single, startsWith('https://hikka.io/collections/'));

      // Тап по тайтлу колекції відкриває аніме поверх колекції, «Назад» повертає до неї
      await tester.tap(find.byType(HikkaAnimeCard).first);
      await load(tester);
      expect(HikkaNav.instance.top!.kind, HikkaRouteKind.anime);
      HikkaNav.instance.back();
      await load(tester, rounds: 6);
      expect(HikkaNav.instance.top!.kind, HikkaRouteKind.collection);

      HikkaNav.instance.openCollection(FakeHikka.adultCollection);
      await load(tester);
      expect(find.text('Контент 18+ прихований'), findsOneWidget);
      expect(find.byType(HikkaAnimeCard), findsNothing);
      await tester.tap(find.text('Показати цю колекцію'));
      await load(tester);
      expect(find.text('Контент 18+ прихований'), findsNothing);
      expect(find.byType(HikkaAnimeCard), findsWidgets);
    });

    testWidgets('стаття: текст із розміткою, картинки, посилання на сайт', (tester) async {
      setScreen(tester, kDesktop);
      await tester.pumpWidget(hub());
      await load(tester, rounds: 4);
      HikkaNav.instance.setTab(HikkaTab.articles);
      await load(tester);
      await tester.tap(find.byType(HikkaArticleCard).first);
      await load(tester);
      expect(tester.takeException(), isNull);
      expect(HikkaNav.instance.top!.kind, HikkaRouteKind.article);
      expect(find.text('Стаття'), findsOneWidget);
      await shot(tester, 'article_desktop');
      await tester.tap(find.byTooltip('Відкрити на hikka.io'));
      await tester.pump();
      expect(opened.single, startsWith('https://hikka.io/articles/'));

      HikkaNav.instance.back();
      await load(tester, rounds: 6);
      HikkaNav.instance.openArticle('systema-stattey-tak-yak-neyu-korystuvatys-63a557');
      await load(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Система статтей, так як нею користуватись'), findsWidgets);
      await shot(tester, 'article_full_desktop');
      await scrollPage(tester, 900);
      expect(tester.takeException(), isNull);
      await shot(tester, 'article_full_desktop_scrolled');
    });

    testWidgets('«Профіль»: рядки налаштувань, «Про Miki Miki», прихована медіатека з’являється за перемикачем', (tester) async {
      setScreen(tester, kDesktop);
      await tester.pumpWidget(hub());
      await load(tester, rounds: 4);
      HikkaNav.instance.setMain(MainTab.profile);
      await load(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Профіль'), findsOneWidget);
      expect(find.text('Гість'), findsOneWidget);
      expect(find.text('Про Miki Miki'), findsOneWidget);
      expect(find.text('Локальна медіатека'), findsNothing, reason: 'за замовчуванням медіатеку приховано');
      await shot(tester, 'profile_desktop');

      await tester.tap(find.text('Налаштування застосунку'));
      await tester.pump();
      expect(settingsOpened, [null]);
      await tester.tap(find.text('Про Miki Miki'));
      await tester.pump();
      expect(settingsOpened.last, AppSettingsDialog.tabAbout);

      StorageService.saveLocalLibrary(true);
      await load(tester, rounds: 3);
      expect(find.text('Локальна медіатека'), findsOneWidget);
      await tester.tap(find.text('Локальна медіатека'));
      await load(tester, rounds: 6);
      expect(HikkaNav.instance.top!.kind, HikkaRouteKind.localLibrary);
      expect(find.text('Тут медіатека'), findsOneWidget);
      expect(find.byTooltip('Оновити'), findsNothing, reason: 'у медіатеки немає чого оновлювати');
      expect(find.byTooltip('Відкрити на hikka.io'), findsNothing);
      HikkaNav.instance.back();
      await load(tester, rounds: 6);
      expect(find.text('Гість'), findsOneWidget);
    });

    testWidgets('«Списки» для гостя: картка входу й пояснення, що буде після входу в Hikka', (tester) async {
      setScreen(tester, kDesktop);
      await tester.pumpWidget(hub());
      await load(tester, rounds: 4);
      HikkaNav.instance.setMain(MainTab.lists);
      await load(tester, rounds: 6);
      expect(tester.takeException(), isNull);
      expect(find.text('Списки'), findsOneWidget);
      expect(find.text('Гість'), findsOneWidget);
      expect(find.text('Увійти через Hikka'), findsOneWidget);
      expect(find.text('Що з’явиться після входу'), findsOneWidget);
      for (final p in ['Дивлюсь', 'У планах', 'Переглянуто', 'Відкладено', 'Кинуто', 'Улюблене']) {
        expect(find.text(p), findsOneWidget, reason: p);
      }
      await shot(tester, 'lists_desktop');
    });

    testWidgets('сповіщення: вікно з поясненням відкривається й закривається', (tester) async {
      setScreen(tester, kDesktop);
      await tester.pumpWidget(hub());
      await load(tester);
      await tester.tap(find.byTooltip('Сповіщення'));
      await load(tester, rounds: 6);
      expect(tester.takeException(), isNull);
      expect(find.text('Нова серія'), findsOneWidget);
      expect(find.text('Нова озвучка'), findsOneWidget);
      await shot(tester, 'notifications_desktop');
      await tester.tap(find.text('Зрозуміло'));
      await load(tester, rounds: 6);
      expect(find.text('Нова озвучка'), findsNothing);
    });

    testWidgets('пошукова панель «Головної» відкриває каталог із курсором у полі пошуку', (tester) async {
      setScreen(tester, kDesktop);
      await tester.pumpWidget(hub());
      await load(tester);
      await tester.tap(find.text('Пошук аніме…'));
      await load(tester);
      expect(tester.takeException(), isNull);
      expect(HikkaNav.instance.main, MainTab.discover);
      expect(HikkaNav.instance.tab, HikkaTab.anime);
      final field = tester.widget<EditableText>(find.byType(EditableText).first);
      expect(field.focusNode.hasFocus, isTrue, reason: 'курсор одразу в полі пошуку');
      expect(HikkaNav.instance.wantsSearchFocus, isFalse, reason: 'прапорець віддається один раз');
    });

    testWidgets('календар: вкладки Пн–Нд, відкривається на сьогодні, інший день гортається тапом і свайпом', (tester) async {
      setScreen(tester, kDesktop);
      await tester.pumpWidget(hub());
      await load(tester, rounds: 4);
      HikkaNav.instance.setTab(HikkaTab.schedule);
      await load(tester);
      for (final d in ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Нд']) {
        expect(find.text(d), findsOneWidget, reason: d);
      }
      expect(find.textContaining('серія'), findsWidgets, reason: 'сьогодні серії є');
      final other = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Нд'][(DateTime.now().weekday) % 7];
      await tester.tap(find.text(other));
      await load(tester, rounds: 4);
      expect(find.byType(HikkaSwipeTabs), findsWidgets);
      expect(find.textContaining('серія').evaluate().isNotEmpty || find.text('На цей день серій немає').evaluate().isNotEmpty, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('стрічка серій на «Головній»: записи змінюються самі (фейдом), крапка лише в серій цієї години', (tester) async {
      setScreen(tester, kDesktop);
      await tester.pumpWidget(hub());
      await load(tester);
      String label() => tester
          .widgetList<Text>(find.descendant(of: find.byType(HikkaAiringStrip), matching: find.byType(Text)))
          .map((t) => t.data ?? '')
          .join('|');
      final first = label();
      expect(first, isNotEmpty);
      await tester.pump(kAiringTick + const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 600));
      expect(label(), isNot(first), reason: 'через кілька секунд показано іншу серію');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('календар: свайп убік по днях не гортає дні — він для вкладок «Огляду»', (tester) async {
      setScreen(tester, kNarrow);
      await tester.pumpWidget(hub());
      await load(tester, rounds: 4);
      HikkaNav.instance.setMain(MainTab.discover);
      HikkaNav.instance.setTab(HikkaTab.schedule);
      await load(tester);
      await tester.fling(find.textContaining('серія').first, const Offset(-500, 0), 1500);
      await load(tester, rounds: 6);
      expect(HikkaNav.instance.tab, HikkaTab.anime, reason: 'свайп перемкнув вкладку Огляду, а не день');
    });

    testWidgets('календар у стрічці «Головної» відкриває розклад, серія — аніме', (tester) async {
      setScreen(tester, kDesktop);
      await tester.pumpWidget(hub());
      await load(tester);
      await tester.tap(find.descendant(of: find.byType(HikkaAiringStrip), matching: find.byIcon(Symbols.calendar_month_rounded)));
      await load(tester);
      expect(HikkaNav.instance.main, MainTab.discover);
      expect(HikkaNav.instance.tab, HikkaTab.schedule);
      expect(find.textContaining('серія'), findsWidgets);

      HikkaNav.instance.setMain(MainTab.home);
      await load(tester, rounds: 4);
      final chip = find.descendant(of: find.byType(HikkaAiringStrip), matching: find.textContaining('Серія')).first;
      await tester.tap(chip);
      await load(tester, rounds: 4);
      expect(HikkaNav.instance.top?.kind, HikkaRouteKind.anime);
    });

    testWidgets('налаштування каталогу з «Профілю»: мова назв і 18+ застосовуються одразу', (tester) async {
      setScreen(tester, kDesktop);
      await tester.pumpWidget(hub());
      await load(tester, rounds: 4);
      HikkaNav.instance.setMain(MainTab.profile);
      await load(tester, rounds: 6);
      await tester.tap(find.text('Каталог і дані'));
      await load(tester, rounds: 8);
      expect(tester.takeException(), isNull);
      expect(find.text('Налаштування каталогу'), findsOneWidget);
      await shot(tester, 'settings_desktop');

      // «Перегляд»: вхід у налаштування джерел; закриття повертає до налаштувань каталогу
      expect(find.text('Перегляд'), findsOneWidget);
      await tester.tap(find.widgetWithText(AppSecondaryButton, 'Джерела перегляду'));
      await load(tester, rounds: 6);
      expect(find.text('Якість відео'), findsOneWidget);
      expect(find.text('Ключ Mikai API'), findsOneWidget);
      await tester.tap(find.byTooltip('Закрити').last);
      await load(tester, rounds: 6);
      expect(find.text('Якість відео'), findsNothing);
      expect(find.text('Налаштування каталогу'), findsOneWidget);

      await tester.tap(find.text('English'));
      await load(tester, rounds: 4);
      expect(HikkaPrefs.instance.titleLang, HikkaTitleLang.en);
      await tester.tap(find.text('Контент 18+'));
      await load(tester, rounds: 4);
      expect(HikkaPrefs.instance.allowAdult, isTrue);
    });
  });

  // ── Банери ─────────────────────────────────────────────────────────────────

  group('Банери «Головної»', () {
    testWidgets('один запит до AniList на всі банери; широке зображення лише там, де банер є', (tester) async {
      setScreen(tester, kDesktop);
      await tester.pumpWidget(hub());
      await load(tester, rounds: 30);
      expect(tester.takeException(), isNull);
      expect(env.bannerRequests, 1, reason: 'усі тайтли каруселі — одним запитом');
      expect(env.tmdbRequests, 0, reason: 'без ключа TMDB не питаємо');
      expect(find.byWidgetPredicate(isWideBanner), findsWidgets);
      await shot(tester, 'banners_desktop');
    });

    testWidgets('банерів в AniList немає ніде: лишається розмитий постер, запит не повторюється', (tester) async {
      env.hasBanner = (_) => false;
      setScreen(tester, kDesktop);
      await tester.pumpWidget(hub());
      await load(tester, rounds: 30);
      expect(tester.takeException(), isNull);
      expect(find.byWidgetPredicate(isWideBanner), findsNothing);
      expect(find.byType(HikkaBannerCarousel), findsOneWidget);
      expect(env.bannerRequests, 1);
      expect(env.tmdbRequests, 0);
    });

    testWidgets('тап по банеру відкриває сторінку аніме', (tester) async {
      setScreen(tester, kDesktop);
      await tester.pumpWidget(hub());
      await load(tester, rounds: 12);
      await tester.tap(find.text('Дивитись').first);
      await load(tester, rounds: 4);
      expect(HikkaNav.instance.top?.kind, HikkaRouteKind.anime);
    });

    testWidgets('карусель гортається сама', (tester) async {
      setScreen(tester, kDesktop);
      final carousel = find.byType(HikkaBannerCarousel);
      await tester.pumpWidget(app(HikkaBannerCarousel(
        items: [for (final a in server.animeList.take(3)) HikkaAnime.fromJson(a)],
        scale: 1.0,
        pad: 24,
        autoAdvance: const Duration(milliseconds: 1500),
        artLoader: (_) async => const {},
      )));
      expect(carousel, findsOneWidget);
      int page() => tester.widget<PageView>(find.byType(PageView)).controller!.page!.round();
      expect(page(), 0);
      await tester.pump(const Duration(milliseconds: 1600)); // таймер спрацював і запустив анімацію
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 900));
      expect(page(), 1, reason: 'після паузи перейшла на другий банер');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('телефон: карусель безкінечна — після останнього банера знову перший, а не застрягає в кінці', (tester) async {
      phone();
      setScreen(tester, kPortrait);
      await tester.pumpWidget(app(HikkaBannerCarousel(
        items: [for (final a in server.animeList.take(3)) HikkaAnime.fromJson(a)],
        scale: AppPlatform.mobileScale,
        pad: 16,
        autoAdvance: const Duration(milliseconds: 1500),
        artLoader: (_) async => const {},
      )));
      final pager = find.byType(PageView);
      int shown() => tester.widget<PageView>(pager).controller!.page!.round() % 3;
      expect(shown(), 0);
      // Двічі гортаємо пальцем уперед: другий банер, третій
      for (var i = 0; i < 2; i++) {
        await tester.drag(pager, const Offset(-300, 0));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 800));
      }
      expect(shown(), 2, reason: 'це останній банер');
      // Ще раз уперед — знову перший (раніше карусель упиралась в кінець)
      await tester.drag(pager, const Offset(-300, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      expect(shown(), 0);
      // Автогортання (без пальця) теж іде вперед
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(app(HikkaBannerCarousel(
        items: [for (final a in server.animeList.take(3)) HikkaAnime.fromJson(a)],
        scale: AppPlatform.mobileScale,
        pad: 16,
        autoAdvance: const Duration(milliseconds: 1500),
        artLoader: (_) async => const {},
      )));
      final start = tester.widget<PageView>(pager).controller!.page!.round();
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 1600));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 900));
      }
      expect(tester.widget<PageView>(pager).controller!.page!.round(), greaterThan(start), reason: 'автогортання йде вперед, а не назад');
      await tester.pumpWidget(const SizedBox());
    });
  });

  // ── Телефон ────────────────────────────────────────────────────────────────

  group('Телефон', () {
    testWidgets('портрет 448×997: головна', (tester) async {
      phone();
      setScreen(tester, kPortrait);
      await tester.pumpWidget(hub(scale: AppPlatform.mobileScale, pad: const EdgeInsets.fromLTRB(0, 30, 0, 18)));
      await load(tester);
      expect(tester.takeException(), isNull);
      await shot(tester, 'home_portrait');
      await scrollPage(tester, 700);
      expect(tester.takeException(), isNull);
      await shot(tester, 'home_portrait_scrolled');
    });

    testWidgets('вузький 360×780: усі чотири вкладки без переповнення', (tester) async {
      phone();
      setScreen(tester, kNarrow);
      await tester.pumpWidget(hub(scale: AppPlatform.mobileScale, pad: const EdgeInsets.fromLTRB(0, 24, 0, 24)));
      await load(tester);
      expect(tester.takeException(), isNull);
      await shot(tester, 'home_narrow');
      for (final tab in [MainTab.discover, MainTab.lists, MainTab.profile]) {
        HikkaNav.instance.setMain(tab);
        await load(tester, rounds: 10);
        expect(tester.takeException(), isNull, reason: tab.label);
        await shot(tester, '${tab.name}_narrow');
      }
      for (final t in HikkaTab.values) {
        HikkaNav.instance.setTab(t);
        await load(tester, rounds: 10);
        expect(tester.takeException(), isNull, reason: t.label);
        await shot(tester, 'discover_${t.name}_narrow');
      }
    });

    testWidgets('вузький 360×780: сторінка аніме без переповнення', (tester) async {
      phone();
      setScreen(tester, kNarrow);
      await tester.pumpWidget(hub(scale: AppPlatform.mobileScale, pad: const EdgeInsets.fromLTRB(0, 24, 0, 24)));
      await load(tester, rounds: 4);
      HikkaNav.instance.openAnime(ongoing);
      await load(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Наступна серія'), findsOneWidget);
      await shot(tester, 'anime_narrow_top');
      await scrollPage(tester, 700);
      expect(tester.takeException(), isNull);
      await shot(tester, 'anime_narrow_scrolled');
      await scrollPage(tester, 1800);
      expect(tester.takeException(), isNull);
      await shot(tester, 'anime_narrow_bottom');
    });

    testWidgets('альбомна 997×448: головна й сторінка аніме у два стовпці', (tester) async {
      phone();
      setScreen(tester, kLandscape);
      await tester.pumpWidget(hub(scale: AppPlatform.mobileScale, pad: const EdgeInsets.fromLTRB(46, 0, 0, 0)));
      await load(tester, rounds: 8);
      expect(tester.takeException(), isNull);
      await shot(tester, 'home_landscape');
      HikkaNav.instance.openAnime(frieren);
      await load(tester);
      expect(tester.takeException(), isNull);
      await shot(tester, 'anime_landscape');
    });

    testWidgets('персонаж і франшиза на вузькому екрані', (tester) async {
      phone();
      setScreen(tester, kNarrow);
      await tester.pumpWidget(hub(scale: AppPlatform.mobileScale, pad: const EdgeInsets.fromLTRB(0, 24, 0, 24)));
      await load(tester, rounds: 4);
      HikkaNav.instance.openCharacter('frieren-7f706c');
      await load(tester);
      expect(tester.takeException(), isNull);
      await shot(tester, 'character_narrow');
      await scrollPage(tester, 600);
      await shot(tester, 'character_narrow_scrolled');
      HikkaNav.instance.openFranchise(frieren);
      await load(tester);
      expect(tester.takeException(), isNull);
      await shot(tester, 'franchise_narrow');
    });

    testWidgets('колекція й стаття на вузькому екрані', (tester) async {
      phone();
      setScreen(tester, kNarrow);
      await tester.pumpWidget(hub(scale: AppPlatform.mobileScale, pad: const EdgeInsets.fromLTRB(0, 24, 0, 24)));
      await load(tester, rounds: 4);
      HikkaNav.instance.openCollection('ff0f841a-7e7f-4cae-b61f-db123dcbab8b');
      await load(tester);
      expect(tester.takeException(), isNull);
      await shot(tester, 'collection_narrow');
      await scrollPage(tester, 500);
      expect(tester.takeException(), isNull);
      HikkaNav.instance.openArticle('systema-stattey-tak-yak-neyu-korystuvatys-63a557');
      await load(tester);
      expect(tester.takeException(), isNull);
      await shot(tester, 'article_narrow');
      await scrollPage(tester, 800);
      expect(tester.takeException(), isNull);
      await shot(tester, 'article_narrow_scrolled');
    });

    testWidgets('фільтри відкриваються нижньою панеллю', (tester) async {
      phone();
      setScreen(tester, kNarrow);
      await tester.pumpWidget(hub(scale: AppPlatform.mobileScale, pad: const EdgeInsets.fromLTRB(0, 24, 0, 24)));
      await load(tester, rounds: 4);
      HikkaNav.instance.setTab(HikkaTab.anime);
      await load(tester);
      await shot(tester, 'catalog_narrow');
      await tester.tap(find.byTooltip('Фільтри'));
      await load(tester, rounds: 8);
      expect(tester.takeException(), isNull);
      await shot(tester, 'filters_narrow');
    });

    testWidgets('налаштування каталогу з «Профілю» на телефоні', (tester) async {
      phone();
      setScreen(tester, kNarrow);
      await tester.pumpWidget(hub(scale: AppPlatform.mobileScale, pad: const EdgeInsets.fromLTRB(0, 24, 0, 24)));
      await load(tester, rounds: 4);
      HikkaNav.instance.setMain(MainTab.profile);
      await load(tester, rounds: 6);
      // Рядки меню — зона дотику не менша за 48 dp
      final row = find.ancestor(of: find.text('Каталог і дані'), matching: find.byType(InkWell)).first;
      expect(tester.getSize(row).height, greaterThanOrEqualTo(AppPlatform.touchTarget));
      await tester.tap(find.text('Каталог і дані'));
      await load(tester, rounds: 8);
      expect(tester.takeException(), isNull);
      await shot(tester, 'settings_narrow');

      // Вхід у «Джерела перегляду» з телефона: зона дотику 48 dp, вікно вміщується
      final entry = find.widgetWithText(AppSecondaryButton, 'Джерела перегляду');
      expect(tester.getSize(entry).height, greaterThanOrEqualTo(AppPlatform.touchTarget));
      await tester.tap(entry);
      await load(tester, rounds: 6);
      expect(tester.takeException(), isNull);
      expect(find.text('Якість відео'), findsOneWidget);
    });

    testWidgets('потяг вниз оновлює головну: кеш скидається, полиці перезавантажуються', (tester) async {
      phone();
      setScreen(tester, kNarrow);
      await tester.pumpWidget(hub(scale: AppPlatform.mobileScale, pad: const EdgeInsets.fromLTRB(0, 24, 0, 24)));
      await load(tester);
      final before = server.count((r) => r.url.path == '/anime' && r.method == 'POST');
      expect(before, greaterThan(0));
      await tester.fling(find.byType(Scrollable).first, const Offset(0, 500), 1000);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await load(tester);
      expect(tester.takeException(), isNull);
      expect(server.count((r) => r.url.path == '/anime' && r.method == 'POST'), greaterThan(before));
    });
  });

  // ── У складі головного екрана ──────────────────────────────────────────────

  group('Оболонка HomeHub', () {
    Widget home({EdgeInsets pad = EdgeInsets.zero}) => app(
          HomeHub(
            scale: AppPlatform.isMobile ? AppPlatform.mobileScale : 1.0,
            onOpenFile: (_) {},
            onOpenMultipleFiles: (_) {},
            onOpenQueue: (_, __) {},
            onOpenSettings: ({int? tab}) => settingsOpened.add(tab),
          ),
          pad: pad,
        );

    testWidgets('телефон: чотири пункти нижньої навігації; вкладки відкриваються ліниво; «Назад» веде на «Головну»', (tester) async {
      phone();
      setScreen(tester, kNarrow);
      await tester.pumpWidget(home(pad: const EdgeInsets.fromLTRB(0, 24, 0, 24)));
      await load(tester);
      expect(tester.takeException(), isNull);
      for (final label in ['Головна', 'Огляд', 'Списки', 'Профіль']) {
        expect(find.text(label), findsWidgets, reason: label);
      }
      for (final old in ['Історія', 'Плейлисти', 'Каталог', 'Налаштування']) {
        expect(find.text(old), findsNothing, reason: 'старих пунктів у навігації вже немає: $old');
      }
      // «Огляд» не відкривали — його запитів ще немає
      expect(server.count((r) => r.url.path == '/collections' || r.url.path == '/articles'), 0);
      await shot(tester, 'homehub_narrow_home');

      await tester.tap(find.text('Огляд'));
      await load(tester);
      expect(tester.takeException(), isNull);
      expect(HikkaNav.instance.main, MainTab.discover);
      expect(server.count((r) => r.url.path == '/collections'), greaterThan(0));
      await shot(tester, 'homehub_narrow_discover');

      HikkaNav.instance.openAnime(frieren);
      await load(tester);
      expect(find.text('Опис'), findsOneWidget);
      await shot(tester, 'homehub_narrow_anime');

      // Кнопка «Назад» системи: спершу закриває сторінку, потім з іншої вкладки ведемо на «Головну»…
      expect(HomeHub.backHandler!(), isTrue);
      await load(tester, rounds: 6);
      expect(HikkaNav.instance.top, isNull);
      expect(HikkaNav.instance.main, MainTab.discover);
      expect(HomeHub.backHandler!(), isTrue);
      await load(tester, rounds: 6);
      expect(HikkaNav.instance.main, MainTab.home);
      // …а з «Головної» вже виходимо із застосунку (обробник каже «нічого не закрито»)
      expect(HomeHub.backHandler!(), isFalse);

      // Повернення до «Огляду» зберігає його стан
      await tester.tap(find.text('Огляд'));
      await load(tester, rounds: 6);
      expect(find.byType(HikkaCollectionCard), findsWidgets);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Списки'));
      await load(tester, rounds: 6);
      expect(find.text('Що з’явиться після входу'), findsOneWidget);
      await tester.tap(find.text('Профіль'));
      await load(tester, rounds: 6);
      expect(find.text('Гість'), findsOneWidget);
      await shot(tester, 'homehub_narrow_profile');
    });

    testWidgets('повторний тап по вкладці повертає на її корінь', (tester) async {
      phone();
      setScreen(tester, kNarrow);
      await tester.pumpWidget(home(pad: const EdgeInsets.fromLTRB(0, 24, 0, 24)));
      await load(tester, rounds: 6);
      HikkaNav.instance.openAnime(frieren);
      await load(tester, rounds: 8);
      expect(find.text('Опис'), findsOneWidget);
      await tester.tap(find.text('Головна'));
      await load(tester, rounds: 8);
      expect(HikkaNav.instance.top, isNull);
      expect(find.text('Опис'), findsNothing);
      expect(find.text('Пошук аніме…'), findsOneWidget);
    });

    testWidgets('нижня навігація: зони дотику ≥ 48 dp, вибрана вкладка підсвічена', (tester) async {
      phone();
      setScreen(tester, kNarrow);
      await tester.pumpWidget(home(pad: const EdgeInsets.fromLTRB(0, 24, 0, 24)));
      await load(tester, rounds: 4);
      for (final tab in MainTab.values) {
        final item = find.ancestor(of: find.text(tab.label), matching: find.byType(InkWell)).first;
        final size = tester.getSize(item);
        expect(size.height, greaterThanOrEqualTo(AppPlatform.touchTarget), reason: tab.label);
        expect(size.width, greaterThanOrEqualTo(AppPlatform.touchTarget), reason: tab.label);
      }
      final semantics = tester.ensureSemantics();
      await tester.pump();
      expect(tester.getSemantics(find.bySemanticsLabel('Головна').first), containsSemantics(isButton: true, isSelected: true));
      expect(tester.getSemantics(find.bySemanticsLabel('Огляд').first), containsSemantics(isButton: true, isSelected: false));
      semantics.dispose();
    });

    testWidgets('десктоп: бічне меню з назвою, чотирма вкладками, налаштуваннями й версією', (tester) async {
      setScreen(tester, kDesktop);
      await tester.pumpWidget(home());
      await load(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Miki Miki'), findsOneWidget);
      expect(find.text('M'), findsOneWidget, reason: 'тимчасова монограма замість маскота');
      for (final label in ['Головна', 'Огляд', 'Списки', 'Профіль', 'Налаштування']) {
        expect(find.text(label), findsWidgets, reason: label);
      }
      expect(find.text('v1.1.0'), findsOneWidget);
      expect(find.text('MyPlayer'), findsNothing);
      expect(find.text('YouTube Mobile Fork'), findsNothing);
      await shot(tester, 'homehub_desktop_home');

      await tester.tap(find.text('Огляд').first);
      await load(tester);
      expect(HikkaNav.instance.main, MainTab.discover);
      expect(find.byType(HikkaCollectionCard), findsWidgets);
      await shot(tester, 'homehub_desktop_discover');
      await tester.tap(find.text('Головна').first);
      await load(tester, rounds: 6);
      expect(find.text('Пошук аніме…'), findsOneWidget);

      await tester.tap(find.text('Налаштування').first);
      await tester.pump();
      expect(settingsOpened, [null]);
    });

    testWidgets('після відтворення (HomeHub перебудовано) людина лишається на тій самій сторінці', (tester) async {
      phone();
      setScreen(tester, kNarrow);
      await tester.pumpWidget(home(pad: const EdgeInsets.fromLTRB(0, 24, 0, 24)));
      await load(tester, rounds: 6);
      await tester.tap(find.text('Огляд'));
      await load(tester);
      HikkaNav.instance.openCharacter('frieren-7f706c');
      await load(tester);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await tester.pumpWidget(home(pad: const EdgeInsets.fromLTRB(0, 24, 0, 24)));
      await load(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Персонаж'), findsOneWidget);
      expect(find.text('Озвучення'), findsOneWidget);
    });
  });

  // ── Стани й крайні випадки ─────────────────────────────────────────────────

  group('Стани', () {
    testWidgets('сторінка 18+ закрита, доки її не відкрито вручну', (tester) async {
      setScreen(tester, kDesktop);
      await tester.pumpWidget(hub());
      await load(tester, rounds: 4);
      HikkaNav.instance.openAnime(FakeHikka.adultSlug);
      await load(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Контент 18+ прихований'), findsOneWidget);
      expect(find.text('Опис'), findsNothing);
      expect(find.text('Персонажі'), findsNothing);
      await shot(tester, 'adult_gate');
      await tester.tap(find.text('Показати цю сторінку'));
      await load(tester);
      expect(find.text('Контент 18+ прихований'), findsNothing);
      expect(find.text('Опис'), findsOneWidget);
    });

    testWidgets('18+ дозволено в налаштуваннях — сторінка відкрита одразу', (tester) async {
      HikkaPrefs.instance.allowAdult = true;
      setScreen(tester, kDesktop);
      await tester.pumpWidget(hub());
      await load(tester, rounds: 4);
      HikkaNav.instance.openAnime(FakeHikka.adultSlug);
      await load(tester);
      expect(find.text('Контент 18+ прихований'), findsNothing);
      expect(find.text('Опис'), findsOneWidget);
    });

    testWidgets('без мережі: зрозуміла помилка, «Повторити» піднімає полицю', (tester) async {
      setScreen(tester, kDesktop);
      server.offline = true;
      await tester.pumpWidget(hub());
      await load(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Немає зв’язку з Hikka. Перевірте інтернет.'), findsWidgets);
      await shot(tester, 'offline_home');
      // Кнопок кілька (стрічка, банери, полиці): беремо ту, що біля першої полиці — вона на екрані
      final retry = find.text('Повторити');
      expect(retry, findsNWidgets(7));
      server.offline = false;
      await tester.tap(retry.at(2));
      await load(tester);
      expect(find.byType(HikkaAnimeCard), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('аніме, якого немає: помилка «Нічого не знайдено»', (tester) async {
      setScreen(tester, kDesktop);
      await tester.pumpWidget(hub());
      await load(tester, rounds: 4);
      HikkaNav.instance.openAnime('there-is-no-such-anime');
      await load(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Нічого не знайдено.'), findsOneWidget);
    });

    testWidgets('колекції чи статті, якої немає: помилка «Нічого не знайдено»', (tester) async {
      setScreen(tester, kDesktop);
      await tester.pumpWidget(hub());
      await load(tester, rounds: 4);
      HikkaNav.instance.openCollection('нема-такої');
      await load(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Нічого не знайдено.'), findsOneWidget);
      HikkaNav.instance.openArticle('нема-такої');
      await load(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Нічого не знайдено.'), findsOneWidget);
    });

    testWidgets('«Оновити» скидає кеш і перезавантажує відкриту сторінку', (tester) async {
      setScreen(tester, kDesktop);
      await tester.pumpWidget(hub());
      await load(tester, rounds: 4);
      HikkaNav.instance.openAnime(frieren);
      await load(tester);
      final before = server.count((r) => r.url.path == '/anime/$frieren');
      expect(before, 1);
      final rootBefore = server.count((r) => r.url.path == '/schedule/anime' || r.url.path == '/anime' && r.method == 'POST');
      await tester.tap(find.byTooltip('Оновити'));
      await load(tester);
      expect(server.count((r) => r.url.path == '/anime/$frieren'), 2);
      expect(find.text('Опис'), findsOneWidget);
      // Вкладки під сторінкою не перезавантажуються: це зайвий трафік
      expect(server.count((r) => r.url.path == '/schedule/anime' || r.url.path == '/anime' && r.method == 'POST'), rootBefore);
      expect(tester.takeException(), isNull);
    });

    testWidgets('«Оновити» на ПК: кнопка поруч зі сповіщеннями перезавантажує «Головну»', (tester) async {
      setScreen(tester, kDesktop);
      await tester.pumpWidget(hub());
      await load(tester);
      final before = server.count((r) => r.url.path == '/schedule/anime');
      expect(before, greaterThan(0));
      await tester.tap(find.byTooltip('Оновити'));
      await load(tester);
      expect(server.count((r) => r.url.path == '/schedule/anime'), greaterThan(before));
      expect(tester.takeException(), isNull);
    });

    testWidgets('«Оновити» не закриває сторінку 18+, яку вже відкрили', (tester) async {
      setScreen(tester, kDesktop);
      await tester.pumpWidget(hub());
      await load(tester, rounds: 4);
      HikkaNav.instance.openAnime(FakeHikka.adultSlug);
      await load(tester);
      await tester.tap(find.text('Показати цю сторінку'));
      await load(tester);
      expect(find.text('Опис'), findsOneWidget);
      await tester.tap(find.byTooltip('Оновити'));
      await load(tester);
      expect(find.text('Контент 18+ прихований'), findsNothing);
      expect(find.text('Опис'), findsOneWidget);
    });

    testWidgets('мова назв: англійська змінює шапку сторінки та картки', (tester) async {
      setScreen(tester, kDesktop);
      HikkaPrefs.instance.titleLang = HikkaTitleLang.en;
      await tester.pumpWidget(hub());
      await load(tester, rounds: 4);
      HikkaNav.instance.openAnime(frieren);
      await load(tester);
      expect(find.text("Frieren: Beyond Journey's End"), findsWidgets);
      HikkaPrefs.instance.titleLang = HikkaTitleLang.ja;
      await load(tester, rounds: 4);
      expect(find.text('Sousou no Frieren'), findsWidgets);
    });

    testWidgets('пошук у каталозі й у персонажах: запит іде після паузи', (tester) async {
      setScreen(tester, kDesktop);
      await tester.pumpWidget(hub());
      await load(tester, rounds: 4);
      HikkaNav.instance.setTab(HikkaTab.anime);
      await load(tester);
      final calls = server.count((r) => r.url.path == '/anime' && r.body!.contains('"query"'));
      await tester.enterText(find.byType(TextField).first, 'Фрірен');
      await tester.pump(const Duration(milliseconds: 200));
      expect(server.count((r) => r.url.path == '/anime' && r.body!.contains('"query"')), calls, reason: 'до паузи запиту немає');
      await load(tester);
      expect(server.count((r) => r.url.path == '/anime' && r.body!.contains('"query"')), calls + 1);

      HikkaNav.instance.setTab(HikkaTab.characters);
      await load(tester);
      await tester.enterText(find.byType(TextField).first, 'Фрірен');
      await load(tester);
      expect(find.byType(HikkaCharacterCard), findsWidgets);
      expect(find.text('Персонажів не знайдено'), findsNothing);
    });

    testWidgets('жанр на сторінці аніме відкриває каталог із цим жанром', (tester) async {
      setScreen(tester, kDesktop);
      await tester.pumpWidget(hub());
      await load(tester, rounds: 4);
      HikkaNav.instance.openAnime(frieren);
      await load(tester);
      await tester.tap(find.text('Пригоди').first);
      await load(tester);
      expect(HikkaNav.instance.main, MainTab.discover);
      expect(HikkaNav.instance.tab, HikkaTab.anime);
      expect(HikkaNav.instance.top, isNull);
      final body = server.log.where((r) => r.url.path == '/anime' && r.method == 'POST').last.body!;
      expect(body, contains('"genres":["adventure"]'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('посилання на сайт у шапці сторінки відкриваються в браузері', (tester) async {
      setScreen(tester, kDesktop);
      await tester.pumpWidget(hub());
      await load(tester, rounds: 4);
      HikkaNav.instance.openAnime(frieren);
      await load(tester);
      await tester.tap(find.byTooltip('Відкрити на hikka.io'));
      await tester.pump();
      expect(opened, ['https://hikka.io/anime/$frieren']);
    });

    testWidgets('картинки: перший показ качає, повторний береться з диска', (tester) async {
      setScreen(tester, kDesktop);
      await tester.pumpWidget(hub());
      await load(tester, rounds: 30);
      final first = HikkaImageStore.instance;
      expect(first.downloads, greaterThan(5));
      final size = await tester.runAsync(first.diskSize);
      expect(size, greaterThan(0));
      expect(PaintingBinding.instance.imageCache.currentSize, greaterThan(0), reason: 'картинки розкодовані й показані');

      // «Новий запуск»: інший екземпляр сховища на тій самій теці й сервер зображень, що мовчить
      await tester.pumpWidget(const SizedBox());
      PaintingBinding.instance.imageCache.clear();
      final second = HikkaImageStore(dir: env.imageDir, fetcher: (url) async => throw Exception('offline'));
      HikkaImageStore.instance = second;
      await tester.pumpWidget(hub());
      await load(tester, rounds: 30);
      expect(second.downloads, 0, reason: 'усе береться з диска');
      expect(PaintingBinding.instance.imageCache.currentSize, greaterThan(0));
      expect(tester.takeException(), isNull);

      // Очищення кешу звільняє місце
      final freed = await tester.runAsync(second.clear);
      expect(freed, greaterThanOrEqualTo(size!));
      expect(await tester.runAsync(second.diskSize), 0);
    });
  });

  // ── Вузьке вікно на десктопі ───────────────────────────────────────────────

  group('Вузьке вікно десктопу', () {
    for (final size in const [Size(700, 700), Size(520, 700)]) {
      final w = size.width.toInt();
      testWidgets('$w px: головна, розділи «Огляду» і сторінки без переповнення', (tester) async {
        setScreen(tester, size);
        await tester.pumpWidget(hub());
        await load(tester);
        expect(tester.takeException(), isNull);
        expect(find.text('Пошук аніме…'), findsOneWidget);
        await shot(tester, 'home_win$w');

        HikkaNav.instance.setMain(MainTab.discover);
        await load(tester, rounds: 8);
        for (final t in HikkaTab.values) {
          expect(find.text(t.label), findsWidgets, reason: t.label);
        }
        await shot(tester, 'discover_win$w');
        for (final tab in HikkaTab.values) {
          HikkaNav.instance.setTab(tab);
          await load(tester, rounds: 10);
          expect(tester.takeException(), isNull, reason: tab.label);
        }
        for (final tab in [MainTab.lists, MainTab.profile]) {
          HikkaNav.instance.setMain(tab);
          await load(tester, rounds: 6);
          expect(tester.takeException(), isNull, reason: tab.label);
        }

        HikkaNav.instance.openAnime(frieren);
        await load(tester);
        expect(tester.takeException(), isNull);
        expect(find.text('Опис'), findsOneWidget);
        await shot(tester, 'anime_win$w');
        await scrollPage(tester, 500);
        expect(tester.takeException(), isNull);

        HikkaNav.instance.openCharacter('frieren-7f706c');
        await load(tester);
        expect(tester.takeException(), isNull);
        HikkaNav.instance.openFranchise(frieren);
        await load(tester);
        expect(tester.takeException(), isNull);
        expect(find.byType(HikkaAnimeRow), findsNWidgets(4));
        HikkaNav.instance.openCollection('ff0f841a-7e7f-4cae-b61f-db123dcbab8b');
        await load(tester);
        expect(tester.takeException(), isNull);
        HikkaNav.instance.openArticle('systema-stattey-tak-yak-neyu-korystuvatys-63a557');
        await load(tester);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('вікно розтягується й стискається: заголовок перебудовується без втрат стану', (tester) async {
      setScreen(tester, kDesktop);
      await tester.pumpWidget(hub());
      await load(tester, rounds: 6);
      HikkaNav.instance.setTab(HikkaTab.characters);
      await load(tester, rounds: 6);
      tester.view.physicalSize = const Size(560, 700);
      await load(tester, rounds: 4);
      expect(tester.takeException(), isNull);
      expect(HikkaNav.instance.tab, HikkaTab.characters);
      expect(find.byType(HikkaCharacterCard), findsWidgets);
      tester.view.physicalSize = kDesktop;
      await load(tester, rounds: 4);
      expect(tester.takeException(), isNull);
      expect(find.byType(HikkaCharacterCard), findsWidgets);
    });
  });
}
