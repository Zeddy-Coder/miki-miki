// Блок «Дивитись» на сторінці аніме: одна дія «Дивитись / Продовжити» з миттєвим запуском плеєра, озвучка за замовчуванням,
// застереження про ліцензію й розбіжність нумерації, вікно «Джерела». Мережі й диска немає: джерела — підроблений сайт
// на справжніх зліпках відповідей Mikai.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:miki_miki/models/hikka_models.dart';
import 'package:miki_miki/services/hikka_images.dart';
import 'package:miki_miki/services/hikka_nav.dart';
import 'package:miki_miki/services/hikka_prefs.dart';
import 'package:miki_miki/services/remote_playback.dart';
import 'package:miki_miki/services/source_prefs.dart';
import 'package:miki_miki/services/source_registry.dart';
import 'package:miki_miki/services/sources/source_http.dart';
import 'package:miki_miki/services/sources/ua/mikai_source.dart';
import 'package:miki_miki/services/sources/ua/ufdub_source.dart';
import 'package:miki_miki/services/ui_theme_service.dart';
import 'package:miki_miki/services/watch_service.dart';
import 'package:miki_miki/services/watch_store.dart';
import 'package:miki_miki/utils/platform_info.dart';
import 'package:miki_miki/widgets/app_ui_kit.dart';
import 'package:miki_miki/widgets/hikka/hikka_common.dart';
import 'package:miki_miki/widgets/hikka/hikka_watch_dialogs.dart';
import 'package:miki_miki/widgets/hikka/hikka_watch_section.dart';

import 'support/fake_site.dart';
import 'support/fakes.dart';
import 'support/hikka_fakes.dart';
import 'support/remote_fakes.dart';

const Size kDesktop = Size(1280, 900);
const Size kPhone = Size(448, 997);
const Size kNarrow = Size(360, 780);

const String slug = 'kusuriya-no-hitorigoto-zoku-hen-636673';
const String animeKey = 'hikka:$slug';
const Color amber = Color(0xFFFFC23D);

void setScreen(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// Дає час підробленій мережі (вона на мікрозадачах), диску й декодеру зображень
Future<void> load(WidgetTester tester, {int rounds = 12}) async {
  for (int i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
    await tester.pump(const Duration(milliseconds: 60));
  }
}

/// Кадр, що застосовує зміну, і ще два з часом: поява діалогів та анімації завершуються
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

/// Знімки для ручної перевірки вигляду (самі по собі нічого не перевіряють):
/// `SHOTS=1 flutter test --update-goldens test/hikka_watch_ui_test.dart` → `test/shots/hikka_watch_*.png`
final bool kShots = Platform.environment['SHOTS'] == '1';

Future<void> shot(WidgetTester tester, String name) async {
  if (!kShots) return;
  await expectLater(find.byType(MaterialApp), matchesGoldenFile('shots/hikka_watch_$name.png'));
}

HikkaAnime anime({int released = 5, int? total = 12, String status = 'ongoing'}) => HikkaAnime(
  slug: slug,
  titleUa: 'Монолог травниці — 3 сезон',
  titleEn: 'The Apothecary Diaries Season 3',
  titleJa: 'Kusuriya no Hitorigoto 3rd Season',
  status: status,
  year: 2026,
  episodesReleased: released,
  episodesTotal: total,
  malId: 59177,
);

/// Відповідь `/player` у Mikai зі зліпка, з можливістю підправити релізи
Map<String, dynamic> playerDoc({Map<String, dynamic>? license, void Function(List<Map<String, dynamic>> releases)? edit}) {
  final doc = jsonDecode(fixture('mikai_player.json')) as Map<String, dynamic>;
  final r = doc['result'] as Map<String, dynamic>;
  if (license != null) {
    r['licensed'] = true;
    r['license'] = license;
  }
  if (edit != null) edit((r['releases'] as List).cast<Map<String, dynamic>>());
  return doc;
}

/// Задає серії релізу номерами [numbers]
void setEpisodes(Map<String, dynamic> release, List<int> numbers) {
  release['episodes'] = [
    for (final n in numbers)
      {
        'number': n,
        'label': '$n',
        'addedAt': '2026-10-05T06:48:37Z',
        'sources': [
          {'provider': 'moon', 'embedUrl': 'https://moonanime.art/iframe/v$n/'},
        ],
      },
  ];
  release['episodesCount'] = numbers.length;
  release['lastEpisode'] = numbers.isEmpty ? 0 : numbers.last;
}

List<int> upTo(int n) => [for (int i = 1; i <= n; i++) i];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory imgDir;
  late List<String> opened;
  late List<RemoteLaunch> launches;
  late Future<void> Function(RemoteLaunch) launcher;
  late WatchStore store;
  late FakeSite site;

  setUpAll(() async {
    await loadTestFonts();
  });

  /// Службу «Дивитись» збирають із підробленого сайту: Mikai (та за потреби UFDub)
  void useSite(FakeSite s, {bool ufdub = false}) {
    site = s;
    final reg = SourceRegistry(
      sources: [MikaiSource(http: s.http), if (ufdub) UfDubSource(http: s.http)],
      prefs: SourcePrefs(load: () => {}, save: (_) {}),
      http: s.http,
    );
    WatchService.instance = WatchService(registry: reg, store: store);
  }

  FakeSite mikaiSite([Map<String, dynamic>? player]) => FakeSite({
    '/anime/hikka:$slug': fixture('mikai_detail.json'),
    '/anime/7601/player': jsonEncode(player ?? playerDoc()),
    '/teams/2': fixture('mikai_team.json'),
  });

  setUp(() {
    uiTheme.setThemeMode('dark');
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    imgDir = Directory.systemTemp.createTempSync('hikka_watch_ui');
    HikkaImageStore.instance = HikkaImageStore(dir: imgDir, fetcher: (url) async => fakePng(url));
    HikkaPrefs.instance = HikkaPrefs(titleLang: HikkaTitleLang.ua, allowAdult: false);
    opened = [];
    HikkaNav.instance =
        HikkaNav()
          ..urlOpener = (url) async {
            opened.add(url);
            return true;
          };
    store = memoryStore();
    launches = [];
    launcher = (l) async => launches.add(l);
    WatchLauncher.attach(launcher);
    useSite(mikaiSite());
  });

  tearDown(() {
    WatchLauncher.detach(launcher);
    AppPlatform.debugMobile = null;
    try {
      imgDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Widget app(Widget child) =>
      MaterialApp(debugShowCheckedModeBanner: false, home: Scaffold(backgroundColor: uiTheme.bgPrimary, body: SingleChildScrollView(child: child)));

  HikkaRoute newRoute() => HikkaRoute(HikkaRouteKind.anime, slug);

  /// Меню «⋮» праворуч від головної кнопки і пункт у ньому
  Future<void> menuItem(WidgetTester tester, String label) async {
    await tester.tap(find.byTooltip('Ще'));
    await settle(tester);
    await tester.tap(find.text(label));
    await settle(tester);
  }

  /// Список серій живе в модалці «Серії» (меню «⋮»); більшість перевірок серій її відкривають
  Future<void> openEpisodes(WidgetTester tester) => menuItem(tester, 'Серії');

  Future<void> mount(WidgetTester tester, {HikkaAnime? a, HikkaRoute? route, Size size = kDesktop, double scale = 1.0, bool episodes = false}) async {
    setScreen(tester, size);
    final pad = AppPlatform.isMobile ? 16.0 : 28.0;
    await tester.pumpWidget(app(HikkaWatchSection(key: UniqueKey(), anime: a ?? anime(), route: route ?? newRoute(), scale: scale, pad: pad)));
    await load(tester);
    await settle(tester);
    if (episodes) await openEpisodes(tester);
  }

  void phone() => AppPlatform.debugMobile = true;

  /// Кнопка «Дивитись · серія N» / «Продовжити · серія N»
  /// Підпис обраного чипа варіанта
  String selectedChip(WidgetTester tester) => tester.widget<AppDropdown<String>>(find.byType(AppDropdown<String>)).options.firstWhere((o) => o.value == tester.widget<AppDropdown<String>>(find.byType(AppDropdown<String>)).value).label;

  Finder accent(String label) => find.widgetWithText(AppAccentButton, label);

  /// Колір тексту, що містить [text] (рядок озвучки склеєно з кількох частин, тож точний збіг не годиться)
  Color? colorContaining(WidgetTester tester, String text) => tester.widget<Text>(find.textContaining(text).first).style?.color;

  /// Налаштування реєстру джерел із тесту (його складає `useSite`)
  SourcePrefs prefsOf() => WatchService.instance.registry.prefs;

  /// Сайт із двома джерелами: Mikai (основне) і UFDub, що нічого не знаходить
  FakeSite twoSources() => FakeSite({
    '/anime/hikka:$slug': fixture('mikai_detail.json'),
    '/anime/7601/player': jsonEncode(playerDoc()),
    '/teams/2': fixture('mikai_team.json'),
    'POST https://ufdub.com/index.php?do=search': '<html><body><div id="dle-content"></div></body></html>',
  });

  /// Кнопка «Джерела» в шапці блоку
  Finder sourcesLink() => find.byTooltip('Ще'); // «Джерела» тепер у меню «⋮»

  Future<void> openSources(WidgetTester tester) async {
    await menuItem(tester, 'Джерела, якість і плеєр');
    expect(find.text('Джерела перегляду'), findsOneWidget);
  }

  Future<void> closeDialog(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Закрити'));
    await settle(tester);
  }

  /// Поточний пошук блоку: після повторного пошуку (`_restart`) це інший обʼєкт
  Object? searchOf(HikkaRoute route) => route.memo['watch'];

  // ── Одна дія замість вибору озвучки ─────────────────────────────────────────

  group('Одна дія замість вибору озвучки', () {
    testWidgets('кнопка «Дивитись», озвучка за замовчуванням і чипи вибору всіх варіантів перед стартом', (tester) async {
      await mount(tester);

      expect(find.text('Дивитись'), findsOneWidget); // заголовок блоку
      expect(find.text('Українські озвучки та субтитри'), findsOneWidget);
      expect(accent('Дивитись · серія 1'), findsOneWidget);
      expect(find.text('Inari'), findsWidgets);
      expect(find.textContaining('5 з 5 сер.'), findsWidgets);
      // Усі 11 варіантів видно чипами одразу; обраний — підсвічений
      expect(tester.widget<AppDropdown<String>>(find.byType(AppDropdown<String>)).options.length, 11);
      for (final name in ['TuTaZaSho', '4UA', 'FanVoxUA', 'Рідний Голос', 'Glass Moon', 'Amanogawa', 'Далі Буде']) {
        expect(find.textContaining(name), findsWidgets, reason: name);
      }
      expect(selectedChip(tester), 'Озвучення: Inari');
      expect(find.byType(AppCard), findsNothing);
      // Серія ще виходить: озвучено не менше, ніж вийшло, жовтого прапорця нема
      expect(find.byIcon(Symbols.warning_rounded), findsNothing);
      await shot(tester, 'desktop_default');
    });

    testWidgets('«Дивитись» одразу відкриває плеєр: ні вікон, ні вибору озвучки; усі варіанти передано в плеєр', (tester) async {
      await mount(tester);
      await tester.tap(accent('Дивитись · серія 1'));
      await tester.pump();

      expect(launches, hasLength(1));
      final l = launches.single;
      expect(l.epKey, '1');
      expect(l.group.label, 'Inari');
      expect(l.group.id, 'mikai|7601|t_121:voice');
      expect(l.title.animeKey, animeKey);
      expect(l.animeTitle, 'Монолог травниці — 3 сезон');
      expect(l.session.entries.length, 5);
      expect(l.startIndex, 0);
      expect(l.hikka, isNotNull);
      // Решту варіантів людина перемикає в плеєрі, тому там мають бути всі
      expect(l.title.groups, hasLength(11));
      await settle(tester);
      expect(find.text('Тричі подумайте'), findsNothing);
      expect(find.byType(Dialog), findsNothing);
    });

    testWidgets('озвучка, яку обрали в плеєрі раніше, стає озвучкою за замовчуванням', (tester) async {
      store.setPreferredGroup(animeKey, 'mikai|7601|t_2:voice');
      await mount(tester);

      expect(selectedChip(tester), 'Озвучення: FanVoxUA');
      await tester.tap(accent('Дивитись · серія 1'));
      await tester.pump();
      expect(launches.single.group.label, 'FanVoxUA');
    });

    testWidgets('улюблена команда з інших тайтлів підставляється сама, а вибір для цього тайтлу сильніший', (tester) async {
      store.setFavoriteChoice('v:2'); // FanVoxUA (озвучення) обирали в іншому тайтлі
      await mount(tester);
      expect(selectedChip(tester), 'Озвучення: FanVoxUA');

      store.setPreferredGroup(animeKey, 'mikai|7601|t_3:voice');
      await tester.pump();
      expect(selectedChip(tester), 'Озвучення: Glass Moon');
    });

    testWidgets('улюблені субтитри відкриваються як субтитри, а не підмінюються озвученням тієї ж команди', (tester) async {
      store.setFavoriteChoice('s:3'); // субтитри Glass Moon
      await mount(tester);

      expect(find.text('Glass Moon'), findsWidgets);
      await tester.tap(accent('Дивитись · серія 1'));
      await tester.pump();
      expect(launches.single.group.isSub, isTrue);
      expect(launches.single.group.id, 'mikai|7601|t_3:sub');
    });

    testWidgets('вибір, зроблений у плеєрі, одразу видно на сторінці під ним', (tester) async {
      await mount(tester);
      expect(find.text('Inari'), findsWidgets);
      await openEpisodes(tester);
      expect(find.text('5'), findsOneWidget);
      await closeDialog(tester);

      // Плеєр запамʼятовує вибір у сховищі; сторінка його слухає
      store.setPreferredGroup(animeKey, 'mikai|7601|t_102:voice');
      await tester.pump();

      expect(find.text('TuTaZaSho'), findsWidgets);
      expect(find.textContaining('4 з 5 сер.'), findsWidgets);
      expect(find.textContaining('Озвучено 4 з 5 вийшлих серій, решта зʼявиться пізніше.'), findsOneWidget);
      await openEpisodes(tester);
      expect(find.text('5'), findsNothing); // п’ятої серії в цьому варіанті ще нема
      expect(find.text('4'), findsOneWidget);
    });

    testWidgets('чипи варіантів узгоджуються з числом: жодного, два, п’ять; вибір чипа запамʼятовується', (tester) async {
      // Один варіант — підказки нема
      useSite(mikaiSite(playerDoc(edit: (r) => r.removeWhere((x) => x['id'] != 't_2:voice'))));
      await mount(tester);
      expect(find.text('FanVoxUA'), findsWidgets);
      expect(find.textContaining('5 з 5 сер.'), findsWidgets);
      expect(tester.widget<AppDropdown<String>>(find.byType(AppDropdown<String>)).options.length, 1);

      // Озвучення й субтитри однієї команди — список із двох
      useSite(mikaiSite(playerDoc(edit: (r) => r.removeWhere((x) => !(x['id'] as String).startsWith('t_121:')))));
      await mount(tester);
      expect(find.text('Inari'), findsWidgets);
      expect(find.textContaining('5 з 5 сер.'), findsWidgets);
      expect(tester.widget<AppDropdown<String>>(find.byType(AppDropdown<String>)).options.length, 2);
      await tester.tap(find.text('Inari').first); // розкрити список
      await settle(tester);
      await tester.tap(find.text('Inari').last); // останній пункт — субтитри
      await settle(tester);
      expect(store.preferredGroup(animeKey), contains('t_121:sub'));
      expect(accent('Дивитись · серія 1'), findsOneWidget);

      // П’ять варіантів — п’ять пунктів
      useSite(
        mikaiSite(
          playerDoc(edit: (r) => r.removeWhere((x) => !const {'t_121:voice', 't_121:sub', 't_2:voice', 't_3:voice', 't_3:sub'}.contains(x['id']))),
        ),
      );
      await mount(tester);
      expect(find.textContaining('5 з 5 сер.'), findsWidgets);
      expect(tester.widget<AppDropdown<String>>(find.byType(AppDropdown<String>)).options.length, 5);
    });

    testWidgets('джерела вимкнено: «Дивитись» є з початку, а натискання відкриває модалку з попередженням і кнопкою «Відкрити джерела»', (tester) async {
      prefsOf().setEnabled('mikai', false);
      await mount(tester);
      expect(accent('Дивитись'), findsOneWidget);
      await tester.tap(accent('Дивитись'));
      await settle(tester);
      expect(find.text('Немає джерел перегляду'), findsOneWidget);
      await tester.tap(find.widgetWithText(AppAccentButton, 'Відкрити джерела'));
      await settle(tester);
      expect(find.text('Джерела перегляду'), findsOneWidget);
    });

    testWidgets('телефон: головна кнопка на всю ширину, список озвучок, серії згорнуто (знімки)', (tester) async {
      phone();
      await mount(tester, size: kNarrow, scale: AppPlatform.mobileScale, episodes: false);
      expect(accent('Дивитись · серія 1'), findsOneWidget);
      expect(find.byTooltip('Ще'), findsOneWidget);
      await shot(tester, 'phone_collapsed');
      await tester.tap(find.byTooltip('Ще'));
      await settle(tester);
      await shot(tester, 'phone_menu');
      await closeDialog(tester);
      await tester.tap(find.text('Inari').first);
      await settle(tester);
      await shot(tester, 'phone_dropdown_open');
      prefsOf().setEnabled('mikai', false);
      await mount(tester, size: kNarrow, scale: AppPlatform.mobileScale, episodes: false);
      await shot(tester, 'phone_all_off');
    });

    testWidgets('«Про команду»: відомості з Mikai, посилання відкриваються назовні', (tester) async {
      store.setPreferredGroup(animeKey, 'mikai|7601|t_2:voice');
      await mount(tester);

      await menuItem(tester, 'Про команду');
      await load(tester, rounds: 4);
      await settle(tester);

      expect(find.text('Команда'), findsOneWidget);
      expect(find.textContaining('Студія любительського озвучення'), findsOneWidget);
      expect(find.text('Telegram'), findsOneWidget);
      await shot(tester, 'team_dialog');

      await tester.tap(find.text('Telegram'));
      await tester.pump();
      expect(opened, ['https://t.me/fanvoxua_re']);

      await tester.tap(find.byIcon(Symbols.close_rounded));
      await settle(tester);
      expect(find.text('Команда'), findsNothing);
    });

    testWidgets('«На сайті» веде на сторінку тайтлу в джерелі', (tester) async {
      await mount(tester);
      await menuItem(tester, 'Відкрити на сайті');
      expect(opened.single, startsWith('https://mikai.me/'));
    });
  });

  // ── Розбіжності з Hikka ────────────────────────────────────────────────────

  group('Розбіжність кількості й нумерації з Hikka', () {
    testWidgets('«24 з 12» в усіх варіантах: жовте застереження, відмітки не синхронізуватимуться', (tester) async {
      useSite(
        mikaiSite(
          playerDoc(
            edit: (r) {
              for (final rel in r) {
                setEpisodes(rel, upTo(24));
              }
            },
          ),
        ),
      );
      await mount(tester, a: anime(released: 12, total: 12, status: 'finished'));

      expect(find.textContaining('24 з 12 сер.'), findsWidgets);
      expect(colorContaining(tester, '24 з 12 сер.'), amber);
      expect(find.textContaining('Тут 24 серій, а на Hikka їх лише 12.'), findsOneWidget);
      expect(find.textContaining('об’єднано 2 частини підряд'), findsOneWidget);
      expect(find.textContaining('не синхронізуватимуться з Hikka автоматично'), findsOneWidget);
      expect(find.byIcon(Symbols.warning_rounded), findsWidgets);
      await shot(tester, 'desktop_merged_parts');
    });

    testWidgets('є варіант із правильною нумерацією — «Дивитись» відкриває його, а склеєний не нав’язується', (tester) async {
      useSite(
        mikaiSite(
          playerDoc(
            edit: (r) {
              setEpisodes(r[0], upTo(24)); // TuTaZaSho: склеєні дві частини, їх найбільше, тому вони першими в списку
              setEpisodes(r[1], upTo(12)); // Inari: рівно 12
            },
          ),
        ),
      );
      await mount(tester, a: anime(released: 12, total: 12, status: 'finished'));

      expect(find.text('Inari'), findsWidgets);
      expect(find.textContaining('12 з 12 сер.'), findsWidgets);
      expect(colorContaining(tester, '12 з 12 сер.'), isNot(amber));
      expect(find.textContaining('Тут 24 серій'), findsNothing);

      await tester.tap(accent('Дивитись · серія 1'));
      await tester.pump();
      expect(launches.single.group.label, 'Inari');
      expect(launches.single.session.entries.length, 12);
    });

    testWidgets('але якщо людина сама обрала склеєний варіант у плеєрі — це її вибір, і сторінка про нього попереджає', (tester) async {
      useSite(
        mikaiSite(
          playerDoc(
            edit: (r) {
              setEpisodes(r[0], upTo(24));
              setEpisodes(r[1], upTo(12));
            },
          ),
        ),
      );
      store.setPreferredGroup(animeKey, 'mikai|7601|t_102:voice');
      await mount(tester, a: anime(released: 12, total: 12, status: 'finished'));

      expect(find.text('TuTaZaSho'), findsWidgets);
      expect(colorContaining(tester, '24 з 12 сер.'), amber);
      expect(find.textContaining('Тут 24 серій, а на Hikka їх лише 12.'), findsOneWidget);
      await tester.tap(accent('Дивитись · серія 1'));
      await tester.pump();
      expect(launches.single.group.label, 'TuTaZaSho');
    });

    testWidgets('OVA останньою серією: основні збігаються, зайва не потрапляє в синхронізацію', (tester) async {
      useSite(
        mikaiSite(
          playerDoc(
            edit: (r) {
              setEpisodes(r[0], upTo(13));
              // 13-та серія названа «OVA»
              ((r[0]['episodes'] as List).last as Map<String, dynamic>)['label'] = 'OVA 1';
              setEpisodes(r[1], upTo(12));
            },
          ),
        ),
      );
      await mount(tester, a: anime(released: 12, total: 12, status: 'finished'));

      // Тринадцята серія названа «OVA 1» і стоїть у кінці: основні 12 збігаються з Hikka, зайву не синхронізуємо
      expect(find.text('TuTaZaSho'), findsWidgets);
      expect(find.textContaining('12 з 12 сер.'), findsWidgets);
      expect(find.textContaining('Останні 1 серія схожа на OVA або спецвипуск (OVA 1)'), findsOneWidget);
      expect(find.textContaining('не синхронізуватимуться'), findsNothing);
      await openEpisodes(tester);
      expect(find.text('13'), findsOneWidget); // кнопка серії підписана номером, назва «OVA 1» — у підказці
    });

    testWidgets('жодної серії при відомих 12: поясняє, що їх могли додати на іншу частину; «Джерела» під рукою', (tester) async {
      useSite(
        mikaiSite(
          playerDoc(
            edit: (r) {
              for (final rel in r) {
                setEpisodes(rel, const []);
              }
            },
          ),
        ),
      );
      await mount(tester, a: anime(released: 12, total: 12, status: 'finished'));

      expect(find.text('Не знайшли, де це дивитись українською'), findsOneWidget);
      expect(find.textContaining('Можливо, їх додано на сторінку іншої частини сезону.'), findsOneWidget);
      expect(find.widgetWithText(AppSecondaryButton, 'Спробувати ще'), findsOneWidget);
      expect(find.widgetWithText(AppSecondaryButton, 'Джерела'), findsOneWidget);
      expect(find.text('Серії'), findsNothing);
      expect(accent('Дивитись'), findsOneWidget); // кнопка є завжди, але дивитись ще нема чого
    });

    testWidgets('тайтл завершено, а в озвучці не всі серії — теж жовтий прапорець, але нумерація чесна', (tester) async {
      useSite(
        mikaiSite(
          playerDoc(
            edit: (r) {
              setEpisodes(r[0], upTo(7));
            },
          ),
        ),
      );
      await mount(tester, a: anime(released: 12, total: 12, status: 'finished'));

      expect(find.text('TuTaZaSho'), findsWidgets);
      expect(colorContaining(tester, '7 з 12 сер.'), amber);
      expect(find.textContaining('Не всі серії: тут 7 з 12'), findsOneWidget);
      // Це не збій нумерації: хоч щось, а синхронізувати можна (рівень incomplete, не mismatch)
      expect(find.textContaining('не синхронізуватимуться'), findsNothing);
    });
  });

  // ── Ліцензія ───────────────────────────────────────────────────────────────

  group('Ліцензований тайтл', () {
    final license = {
      'licensee': 'Sony Pictures',
      'links': [
        {'title': 'Crunchyroll', 'url': 'https://www.crunchyroll.com/series/X'},
        {'title': 'Netflix', 'url': 'https://www.netflix.com/title/1'},
      ],
    };

    setUp(() => useSite(mikaiSite(playerDoc(license: license))));

    testWidgets('спершу картка з легальними посиланнями; кнопки «Дивитись» і озвучок ще нема', (tester) async {
      await mount(tester);

      expect(find.text('Ліцензовано в Україні'), findsOneWidget);
      expect(find.textContaining('Правовласник: Sony Pictures.'), findsOneWidget);
      expect(find.widgetWithText(AppAccentButton, 'Crunchyroll'), findsOneWidget);
      expect(find.widgetWithText(AppSecondaryButton, 'Netflix'), findsOneWidget);
      expect(find.text('Все одно дивитись'), findsOneWidget);
      // Озвучок і серій не показуємо, а плеєр не відкриваємо, поки людина не підтвердила вибір
      expect(accent('Дивитись · серія 1'), findsNothing);
      expect(find.text('Серії'), findsNothing);
      expect(find.text('Inari'), findsNothing);
      await shot(tester, 'desktop_licensed');

      await tester.tap(find.widgetWithText(AppAccentButton, 'Crunchyroll'));
      await tester.pump();
      expect(opened, ['https://www.crunchyroll.com/series/X']);
      expect(launches, isEmpty);
    });

    testWidgets('«Все одно дивитись» питає ще раз; «Дивитись легально» у діалозі веде до правовласника, плеєр не відкривається', (tester) async {
      await mount(tester);

      await tester.tap(find.text('Все одно дивитись'));
      await settle(tester);
      expect(find.text('Тричі подумайте'), findsOneWidget);
      expect(find.textContaining('відбирає хліб'), findsOneWidget);
      expect(find.textContaining('гальмує ліцензування аніме в Україні'), findsOneWidget);
      await shot(tester, 'desktop_licensed_dialog');

      // Головна дія діалогу — легальний перегляд. Закриває діалог, відкриває посилання, плеєр не запускається
      await tester.tap(find.widgetWithText(AppAccentButton, 'Дивитись легально'));
      await settle(tester);
      expect(opened, ['https://www.crunchyroll.com/series/X']);
      expect(launches, isEmpty);
      expect(find.text('Тричі подумайте'), findsNothing);
      expect(find.text('Inari'), findsNothing);
      expect(find.text('Ліцензовано в Україні'), findsOneWidget);
    });

    testWidgets('підтвердження в діалозі одразу відкриває плеєр; на сторінці лишається нагадування з посиланнями', (tester) async {
      await mount(tester);
      await tester.tap(find.text('Все одно дивитись'));
      await settle(tester);
      await tester.tap(find.text('Все одно дивитись').last);
      await settle(tester);

      // Плеєр відкрито без жодного додаткового кроку
      expect(find.text('Тричі подумайте'), findsNothing);
      expect(launches, hasLength(1));
      expect(launches.single.group.label, 'Inari');
      expect(launches.single.epKey, '1');

      // Сторінка тепер звичайна, з нагадуванням зверху
      expect(find.text('Ліцензовано в Україні. Якщо можете, дивіться легально.'), findsOneWidget);
      expect(accent('Дивитись · серія 1'), findsOneWidget);
      expect(find.text('Inari'), findsWidgets);
      expect(find.text('Crunchyroll'), findsOneWidget); // посилання правовласника лишаються під рукою як чипи
      await shot(tester, 'desktop_licensed_acknowledged');

      // Повторно запускати вже не питає: людина підтвердила вибір на цьому показі сторінки
      await tester.tap(accent('Дивитись · серія 1'));
      await tester.pump();
      expect(launches, hasLength(2));
      expect(find.text('Тричі подумайте'), findsNothing);

      // Вибір не зберігається: нова сторінка (новий маршрут) показує картку знову
      await mount(tester);
      expect(find.text('Ліцензовано в Україні'), findsOneWidget);
      expect(find.text('Inari'), findsNothing);
    });

    testWidgets('ліцензія без даних про правовласника: текст без імені й одна кнопка «Зрозуміло» в діалозі', (tester) async {
      useSite(mikaiSite(playerDoc(license: {'licensee': '', 'links': []})));
      await mount(tester);

      expect(find.text('Ліцензовано в Україні'), findsOneWidget);
      expect(find.textContaining('Правовласник:'), findsNothing);
      expect(find.widgetWithText(AppAccentButton, 'Дивитись легально'), findsNothing);

      await tester.tap(find.text('Все одно дивитись'));
      await settle(tester);
      expect(find.widgetWithText(AppAccentButton, 'Зрозуміло'), findsOneWidget);
      await tester.tap(find.widgetWithText(AppAccentButton, 'Зрозуміло'));
      await settle(tester);
      expect(find.text('Inari'), findsNothing);
      expect(launches, isEmpty);
    });

    testWidgets('ліцензований, але джерела нічого не знайшли: лише посилання правовласника, «Все одно дивитись» не потрібне', (tester) async {
      useSite(
        mikaiSite(
          playerDoc(
            license: license,
            edit: (r) {
              for (final rel in r) {
                setEpisodes(rel, const []);
              }
            },
          ),
        ),
      );
      await mount(tester);

      expect(find.text('Ліцензовано в Україні'), findsOneWidget);
      expect(find.widgetWithText(AppAccentButton, 'Crunchyroll'), findsOneWidget);
      expect(find.text('Все одно дивитись'), findsNothing);
      expect(launches, isEmpty);
    });
  });

  // ── Порожньо й помилки ─────────────────────────────────────────────────────

  group('Порожні стани й помилки', () {
    testWidgets('нічого не знайшли: пояснення й «Спробувати ще», що справді шукає наново', (tester) async {
      const notFound = Resp('{"ok":false,"error":{"code":"not_found","message":"x"}}', status: 404);
      useSite(FakeSite({'/anime/hikka:': notFound, '/anime/mal:': notFound}));
      await mount(tester);

      expect(find.text('Не знайшли, де це дивитись українською'), findsOneWidget);
      final before = site.count('/anime/hikka:');
      expect(before, greaterThan(0));

      await tester.tap(find.text('Спробувати ще'));
      await load(tester);
      await settle(tester);
      expect(site.count('/anime/hikka:'), greaterThan(before));
      expect(find.text('Не знайшли, де це дивитись українською'), findsOneWidget);
    });

    testWidgets('помилка Mikai показана рядком, а решта джерел (UFDub) працює', (tester) async {
      useSite(
        FakeSite({
          'api.mikai.me': const Resp('boom', status: 500),
          'POST https://ufdub.com/index.php?do=search': fixture('ufdub_search_fairytail.html'),
          'video.ufdub.com': fixture('ufdub_player21.html'),
          'ufdub.com/anime/21-': fixture('ufdub_anime21.html'),
        }),
        ufdub: true,
      );
      await mount(
        tester,
        a: const HikkaAnime(
          slug: 'fairy-tail-abc',
          titleUa: 'Хвіст Феї',
          titleEn: 'Fairy Tail',
          titleJa: 'Fairy Tail',
          status: 'finished',
          year: 2009,
          episodesReleased: 12,
          episodesTotal: 12,
        ),
      );

      expect(find.textContaining('UFDub'), findsWidgets);
      expect(accent('Дивитись · серія 1'), findsOneWidget);
      await tester.tap(find.byTooltip('Ще'));
      await settle(tester);
      expect(find.textContaining('Mikai:'), findsOneWidget); // помилка джерела — у меню «Ще»
      expect(find.byIcon(Symbols.cloud_off_rounded), findsOneWidget);
      await closeDialog(tester);
      await shot(tester, 'desktop_source_error');
    });

    testWidgets('поки джерело відповідає — спінер з його назвою, без «Оновити», але «Джерела» під рукою; потім усе зʼявляється', (tester) async {
      final gate = Completer<void>();
      final inner = mikaiSite();
      final http = SourceHttp(
        sender: (r) async {
          await gate.future;
          return inner.sender(r);
        },
      );
      final reg = SourceRegistry(sources: [MikaiSource(http: http)], prefs: SourcePrefs(load: () => {}, save: (_) {}), http: http);
      WatchService.instance = WatchService(registry: reg, store: store);
      await mount(tester);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.textContaining('Шукаю озвучки: Mikai'), findsOneWidget);
      expect(find.text('Оновити'), findsNothing);
      expect(sourcesLink(), findsOneWidget);
      await shot(tester, 'desktop_searching');

      gate.complete();
      await load(tester);
      await settle(tester);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byTooltip('Ще'), findsOneWidget);
      expect(find.text('Inari'), findsWidgets);
    });

    testWidgets('усі джерела вимкнено: пояснення без «Спробувати ще»; увімкнення в «Джерелах» запускає пошук', (tester) async {
      prefsOf().setEnabled('mikai', false);
      await mount(tester);

      expect(find.text('Усі джерела вимкнено'), findsOneWidget);
      expect(find.text('Увімкніть хоча б одне джерело перегляду.'), findsOneWidget);
      expect(find.text('Спробувати ще'), findsNothing);
      expect(find.text('Оновити'), findsNothing); // оновлювати нічого
      expect(sourcesLink(), findsOneWidget);
      expect(site.log, isEmpty); // нічого не опитується
      await shot(tester, 'desktop_all_off');

      await tester.tap(find.widgetWithText(AppSecondaryButton, 'Джерела'));
      await settle(tester);
      await tester.tap(find.text('Mikai'));
      await tester.pump();
      await closeDialog(tester);
      await load(tester);
      await settle(tester);

      expect(find.text('Усі джерела вимкнено'), findsNothing);
      expect(find.text('Inari'), findsWidgets);
      expect(accent('Дивитись · серія 1'), findsOneWidget);
    });
  });

  // ── Вікно «Джерела» ────────────────────────────────────────────────────────

  group('Вікно «Джерела»', () {
    testWidgets('відкривається з шапки блоку: сайти з поясненнями, якість, плеєр за замовчуванням, ключ', (tester) async {
      useSite(twoSources(), ufdub: true);
      await mount(tester);
      await openSources(tester);

      expect(find.text('Сайти'), findsOneWidget);
      expect(find.text('Mikai'), findsOneWidget);
      expect(find.text('UFDub'), findsOneWidget);
      expect(find.textContaining('Основне джерело: знає команди озвучення й серії.'), findsOneWidget);
      expect(find.text('Якість відео'), findsOneWidget);
      for (final q in ['Найвища', '1080p', '720p', '480p']) {
        expect(find.text(q), findsOneWidget, reason: q);
      }
      expect(find.text('Плеєр за замовчуванням'), findsOneWidget);
      for (final h in ['Авто', 'Moon']) {
        expect(find.text(h), findsOneWidget, reason: h);
      }
      expect(find.text('Ashdi'), findsNothing, reason: 'умова Moon: Ashdi у виборі плеєра не пропонується');
      expect(find.text('Ключ Mikai API'), findsOneWidget);
      expect(find.text('Вставте ключ, якщо він є'), findsOneWidget);
      await shot(tester, 'desktop_sources');

      await closeDialog(tester);
      expect(find.text('Джерела перегляду'), findsNothing);
    });

    testWidgets('вимкнення сайту діє одразу, а закриття вікна повторює пошук уже без нього', (tester) async {
      useSite(twoSources(), ufdub: true);
      final route = newRoute();
      await mount(tester, route: route);
      expect(find.text('Inari'), findsWidgets);
      final first = searchOf(route);
      expect(first, isNotNull);

      await openSources(tester);
      expect(prefsOf().isEnabled('ufdub'), isTrue);
      await tester.tap(find.text('UFDub'));
      await tester.pump();
      expect(prefsOf().isEnabled('ufdub'), isFalse);
      expect(WatchService.instance.registry.enabled.map((s) => s.id), ['mikai']);
      expect(searchOf(route), same(first), reason: 'поки вікно відкрите, шукати наново не треба');
      await closeDialog(tester);
      await load(tester);
      await settle(tester);

      expect(searchOf(route), isNot(same(first)), reason: 'змінилося, де шукати, — пошук почато наново');
      expect(find.text('Inari'), findsWidgets);
    });

    testWidgets('якість і плеєр за замовчуванням зберігаються, а пошуку не повторюють', (tester) async {
      useSite(twoSources(), ufdub: true);
      final route = newRoute();
      await mount(tester, route: route);
      final first = searchOf(route);

      await openSources(tester);
      expect(prefsOf().maxHeight, 0);
      expect(prefsOf().hoster, '');
      await tester.tap(find.text('720p'));
      await tester.pump();
      await tester.tap(find.text('Moon'));
      await tester.pump();
      expect(prefsOf().maxHeight, 720);
      expect(prefsOf().hoster, 'Moon');

      await tester.tap(find.text('Авто'));
      await tester.tap(find.text('Найвища'));
      await tester.pump();
      expect(prefsOf().hoster, '');
      expect(prefsOf().maxHeight, 0);

      await tester.tap(find.text('1080p'));
      await tester.pump();
      await closeDialog(tester);
      await load(tester);
      expect(prefsOf().maxHeight, 1080);
      expect(searchOf(route), same(first), reason: 'якість і плеєр не впливають на пошук, тож повторювати його не треба');
    });

    testWidgets('ключ Mikai: зберігається після паузи в наборі, одразу діє в джерелі, пошук повторюється', (tester) async {
      final route = newRoute();
      await mount(tester, route: route);
      final first = searchOf(route);

      await openSources(tester);
      await tester.enterText(find.byType(TextField).first, '  abc-key  ');
      await tester.pump(const Duration(milliseconds: 200));
      expect(prefsOf().mikaiKey, '', reason: 'ще набирають, чекаємо паузи');
      await tester.pump(const Duration(milliseconds: 600));
      expect(prefsOf().mikaiKey, 'abc-key');
      expect(WatchService.instance.registry.mikai?.apiKey, 'abc-key');

      await closeDialog(tester);
      await load(tester);
      await settle(tester);
      expect(searchOf(route), isNot(same(first)), reason: 'з ключем інший ліміт запитів — шукаємо наново');
      expect(find.text('Inari'), findsWidgets);
    });

    testWidgets('ключ не втрачається, якщо закрити вікно одразу після введення; порожнє поле прибирає ключ', (tester) async {
      await mount(tester);
      await openSources(tester);
      await tester.enterText(find.byType(TextField).first, 'quick-key');
      await closeDialog(tester);
      expect(prefsOf().mikaiKey, 'quick-key');
      expect(WatchService.instance.registry.mikai?.apiKey, 'quick-key');

      await load(tester);
      await openSources(tester);
      expect(tester.widget<TextField>(find.byType(TextField).first).controller?.text, 'quick-key');
      await tester.enterText(find.byType(TextField).first, '');
      await closeDialog(tester);
      expect(prefsOf().mikaiKey, '');
      expect(WatchService.instance.registry.mikai?.apiKey, isNull);
  
  });
  });

  // ── Перегляд ───────────────────────────────────────────────────────────────

  group('Продовження й відмітки', () {
    testWidgets('є історія: «Продовжити» з наступної непереглянутої, «З першої серії», лічильник', (tester) async {
      store.setWatched(animeKey, '1', true);
      store.setWatched(animeKey, '2', true);
      store.setLast(animeKey, '2', 'mikai|7601|t_121:voice');
      await mount(tester);

      expect(accent('Продовжити · серія 3'), findsOneWidget);
      expect(find.widgetWithText(AppSecondaryButton, 'З першої серії'), findsOneWidget);
      expect(find.text('Переглянуто 2 з 5'), findsOneWidget);
      await openEpisodes(tester);
      expect(find.byIcon(Symbols.check_rounded), findsNWidgets(3)); // дві переглянуті серії + позначка обраного пункту у (закритому) списку озвучок
      await closeDialog(tester);

      await tester.tap(accent('Продовжити · серія 3'));
      await tester.pump();
      expect(launches.single.epKey, '3');
      expect(launches.single.startIndex, 2);

      await tester.tap(find.widgetWithText(AppSecondaryButton, 'З першої серії'));
      await tester.pump();
      expect(launches.last.epKey, '1');
      await shot(tester, 'desktop_continue');
    });

    testWidgets('Premium-ключ Moon: окреме поле, зберігається й прибирається порожнім', (tester) async {
      await mount(tester);
      await openSources(tester);
      expect(find.byType(TextField), findsNWidgets(2));
      await tester.enterText(find.byType(TextField).last, '  moon-key ');
      await closeDialog(tester);
      expect(prefsOf().moonKey, 'moon-key');
      expect(prefsOf().mikaiKey, '', reason: 'поля не змішуються');

      await load(tester);
      await openSources(tester);
      expect(tester.widget<TextField>(find.byType(TextField).last).controller?.text, 'moon-key');
      await tester.enterText(find.byType(TextField).last, '');
      await closeDialog(tester);
      expect(prefsOf().moonKey, '');
    });

    testWidgets('продовження йде тією озвучкою, яку обрано: серії інші, номер той самий', (tester) async {
      store.setWatched(animeKey, '1', true);
      store.setWatched(animeKey, '2', true);
      store.setPreferredGroup(animeKey, 'mikai|7601|t_102:voice'); // у цьому варіанті лише 4 серії
      await mount(tester);

      expect(accent('Продовжити · серія 3'), findsOneWidget);
      await tester.tap(accent('Продовжити · серія 3'));
      await tester.pump();
      expect(launches.single.group.label, 'TuTaZaSho');
      expect(launches.single.epKey, '3');
      expect(launches.single.session.entries.length, 4);
    });

    testWidgets('усе переглянуто → «Дивитись знову»', (tester) async {
      for (final k in ['1', '2', '3', '4', '5']) {
        store.setWatched(animeKey, k, true);
      }
      await mount(tester);
      expect(accent('Дивитись знову'), findsOneWidget);
      expect(find.text('Переглянуто 5 з 5'), findsOneWidget);
    });

    testWidgets('утримання й права кнопка миші позначають серію переглянутою й знімають позначку', (tester) async {
      await mount(tester);
      await openEpisodes(tester);
      expect(find.text('Переглянуто 1 з 5'), findsNothing);

      await tester.longPress(find.text('3'));
      await tester.pump();
      expect(store.watched(animeKey), {'3'});
      expect(find.text('Переглянуто 1 з 5'), findsOneWidget);
      expect(launches, isEmpty); // довге натиснення не запускає відтворення

      await tester.longPress(find.text('3'));
      await tester.pump();
      expect(store.watched(animeKey), isEmpty);

      await tester.tap(find.text('4'), buttons: kSecondaryButton);
      await tester.pump();
      expect(store.watched(animeKey), {'4'});
      expect(launches, isEmpty);
    });

    testWidgets('натискання на номер серії запускає саме її', (tester) async {
      await mount(tester);
      await openEpisodes(tester);
      await tester.tap(find.text('4'));
      await tester.pump();
      expect(launches.single.epKey, '4');
      expect(launches.single.startIndex, 3);
      expect(launches.single.group.label, 'Inari');
    });

    testWidgets('плеєр ще не готовий: підказка замість мовчання', (tester) async {
      WatchLauncher.detach(launcher);
      await mount(tester);
      await tester.tap(accent('Дивитись · серія 1'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Плеєр ще не готовий. Спробуйте за мить.'), findsOneWidget);
    });

    testWidgets('повернення на сторінку: вибір озвучки й дані ті самі, без нового пошуку', (tester) async {
      final route = newRoute();
      await mount(tester, route: route);
      store.setPreferredGroup(animeKey, 'mikai|7601|t_3:voice'); // обрали в плеєрі
      await tester.pump();
      final calls = site.count('/anime/');

      await mount(tester, route: route);
      expect(site.count('/anime/'), calls);
      expect(find.text('Glass Moon'), findsWidgets);
    });

    testWidgets('багато серій: показано вікно навколо поточної, «Показати всі» розгортає, «Згорнути» повертає', (tester) async {
      useSite(
        mikaiSite(
          playerDoc(
            edit: (r) {
              setEpisodes(r[0], upTo(120));
            },
          ),
        ),
      );
      for (int i = 1; i <= 60; i++) {
        store.setWatched(animeKey, '$i', true);
      }
      store.setLast(animeKey, '60', 'mikai|7601|t_102:voice');
      store.setPreferredGroup(animeKey, 'mikai|7601|t_102:voice');
      await mount(tester, a: anime(released: 120, total: 120, status: 'finished'));

      expect(accent('Продовжити · серія 61'), findsOneWidget);
      await openEpisodes(tester);
      expect(find.text('Показати всі (120)'), findsOneWidget);
      expect(find.textContaining('Показано серії'), findsOneWidget);
      expect(find.text('61'), findsOneWidget);
      expect(find.text('1'), findsNothing); // перші серії поза вікном

      await tester.tap(find.text('Показати всі (120)'));
      await settle(tester);
      expect(find.text('Згорнути'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('120'), findsOneWidget);

      await tester.tap(find.text('Згорнути'));
      await settle(tester);
      expect(find.text('Показати всі (120)'), findsOneWidget);
    });
  });

  // ── Телефон ────────────────────────────────────────────────────────────────

  group('Телефон', () {
    /// Зона дотику не менша за 48 dp
    void expectTouchTarget(WidgetTester tester, Finder f, String reason) {
      final s = tester.getSize(f.first);
      expect(s.height, greaterThanOrEqualTo(AppPlatform.touchTarget), reason: '$reason: висота');
    }

    testWidgets('цілі натискання не менші за 48 dp, нічого не вилазить за екран', (tester) async {
      phone();
      store.setWatched(animeKey, '1', true);
      store.setLast(animeKey, '1', 'mikai|7601|t_121:voice');
      await mount(tester, size: kNarrow);

      expectTouchTarget(tester, accent('Продовжити · серія 2'), 'головна кнопка');
      expectTouchTarget(tester, find.widgetWithText(AppSecondaryButton, 'З першої серії'), '«З першої серії»');
      expectTouchTarget(tester, find.byTooltip('Ще'), 'меню «⋮»');
      await openEpisodes(tester);
      for (final n in ['1', '2', '3', '4', '5']) {
        final size = tester.getSize(find.ancestor(of: find.text(n), matching: find.byType(InkWell)).first);
        expect(size.width, greaterThanOrEqualTo(AppPlatform.touchTarget), reason: 'ширина серії $n');
        expect(size.height, greaterThanOrEqualTo(AppPlatform.touchTarget), reason: 'висота серії $n');
      }
      expect(tester.takeException(), isNull);
      await closeDialog(tester);
      for (final f in [
        find.text('Продовжити · серія 2'),
        find.text('Inari'),
        sourcesLink(),
      ]) {
        final r = tester.getRect(f.first);
        expect(r.right, lessThanOrEqualTo(kNarrow.width + 0.5), reason: '$f');
        expect(r.left, greaterThanOrEqualTo(0), reason: '$f');
      }
      await shot(tester, 'phone_default');
    });

    testWidgets('довга назва команди й підказка про варіанти не ламають рядок озвучки на вузькому екрані', (tester) async {
      phone();
      useSite(
        mikaiSite(
          playerDoc(
            edit: (r) {
              final team = ((r[1]['teams'] as List).first as Map<String, dynamic>);
              team['name'] = 'Дуже довга назва команди озвучення, що не вміщається в рядок';
            },
          ),
        ),
      );
      await mount(tester, size: kNarrow);
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Дуже довга назва'), findsWidgets);
      await shot(tester, 'phone_long_name');
    });

    testWidgets('ліцензована картка й жовте застереження на вузькому екрані без переповнення', (tester) async {
      phone();
      useSite(
        mikaiSite(
          playerDoc(
            license: {
              'licensee': 'Дуже довга назва правовласника — Тестова Розважальна Компанія Україна',
              'links': [
                {'title': 'Crunchyroll', 'url': 'https://www.crunchyroll.com/series/X'},
                {'title': 'Netflix', 'url': 'https://www.netflix.com/title/1'},
                {'title': 'Megogo', 'url': 'https://megogo.net/x'},
              ],
            },
            edit: (r) {
              for (final rel in r) {
                setEpisodes(rel, upTo(24));
              }
            },
          ),
        ),
      );
      await mount(tester, a: anime(released: 12, total: 12, status: 'finished'), size: kNarrow);
      expect(tester.takeException(), isNull);
      expect(find.text('Ліцензовано в Україні'), findsOneWidget);
      expectTouchTarget(tester, find.byType(QuietAction), '«Все одно дивитись» на картці');
      await shot(tester, 'phone_licensed');

      await tester.tap(find.text('Все одно дивитись'));
      await settle(tester);
      expect(tester.takeException(), isNull);
      await shot(tester, 'phone_licensed_dialog');
      await tester.tap(find.text('Все одно дивитись').last);
      await settle(tester);

      expect(launches, hasLength(1));
      expect(find.textContaining('Тут 24 серій'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await shot(tester, 'phone_merged_parts');
    });

    testWidgets('вікно «Джерела»: перемикачі, сегменти й поле ключа не нижчі за 48 dp, нічого не переповнюється', (tester) async {
      phone();
      useSite(twoSources(), ufdub: true);
      await mount(tester, size: kNarrow);
      await openSources(tester);

      for (final name in ['Mikai', 'UFDub']) {
        final row = find.ancestor(of: find.text(name), matching: find.byType(GestureDetector)).first;
        expectTouchTarget(tester, row, 'перемикач $name');
      }
      for (final bar in [find.byType(AppSegmentedBar<int>), find.byType(AppSegmentedBar<String>)]) {
        expectTouchTarget(tester, bar, 'сегменти');
      }
      expect(tester.takeException(), isNull);
      await shot(tester, 'phone_sources');

      // Нижня частина вікна з полем ключа прокручується й доступна
      for (final field in [find.byType(TextField).first, find.byType(TextField).last]) {
        await tester.ensureVisible(field);
        await tester.pump();
        expect(tester.takeException(), isNull);
        final r = tester.getRect(field);
        expect(r.left, greaterThanOrEqualTo(0));
        expect(r.right, lessThanOrEqualTo(kNarrow.width + 0.5));
      }
    });
  });

  // ── Тема ───────────────────────────────────────────────────────────────────

  group('Світла тема', () {
    testWidgets('читається й не ламається', (tester) async {
      uiTheme.setThemeMode('light');
      addTearDown(() => uiTheme.setThemeMode('dark'));
      useSite(
        mikaiSite(
          playerDoc(
            edit: (r) {
              for (final rel in r) {
                setEpisodes(rel, upTo(24));
              }
            },
          ),
        ),
      );
      await mount(tester, a: anime(released: 12, total: 12, status: 'finished'));
      expect(tester.takeException(), isNull);
      await shot(tester, 'light_merged_parts');

      await openSources(tester);
      expect(tester.takeException(), isNull);
      await shot(tester, 'light_sources');
    });
  });
}
