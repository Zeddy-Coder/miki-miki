// The "Дивитись" block on the anime page: a single "Дивитись / Продовжити" action with an instant player start, a default dub,
// license and numbering-mismatch warnings, the "Джерела" window. No network or disk: the sources are a fake site
// built on real Mikai response snapshots.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:miki_miki/services/storage_service.dart';
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

/// Gives time to the fake network (it runs on microtasks), the disk and the image decoder
Future<void> load(WidgetTester tester, {int rounds = 12}) async {
  for (int i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
    await tester.pump(const Duration(milliseconds: 60));
  }
}

/// The frame that applies the change and two more with time: dialogs and animations finish appearing
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

/// Snapshots for manual visual checks (they verify nothing by themselves):
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

/// A Mikai `/player` response from a snapshot, with the ability to tweak releases
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

/// Sets the release's episodes with numbers [numbers]
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

  /// The "Дивитись" service is assembled from the fake site: Mikai (and UFDub if needed)
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
    StorageService.clearKnownTeams();
    StorageService.saveWatchTeamPriority([]);
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

  /// The "⋮" menu to the right of the main button and an item in it
  Future<void> menuItem(WidgetTester tester, String label) async {
    await tester.tap(find.byTooltip('Ще'));
    await settle(tester);
    await tester.tap(find.text(label));
    await settle(tester);
  }

  /// The episode list lives in the "Серії" modal (the "⋮" menu); most episode checks open it
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

  /// The "Дивитись · серія N" / "Продовжити · серія N" button
  /// Label of the selected variant chip
  String selectedChip(WidgetTester tester) => tester.widget<AppDropdown<String>>(find.byType(AppDropdown<String>)).options.firstWhere((o) => o.value == tester.widget<AppDropdown<String>>(find.byType(AppDropdown<String>)).value).label;

  Finder accent(String label) => find.widgetWithText(AppAccentButton, label);

  /// Color of text containing [text] (the dub line is glued from several parts, so an exact match will not do)
  Color? colorContaining(WidgetTester tester, String text) => tester.widget<Text>(find.textContaining(text).first).style?.color;

  /// Source registry settings from the test (assembled by `useSite`)
  SourcePrefs prefsOf() => WatchService.instance.registry.prefs;

  /// A site with two sources: Mikai (main) and UFDub, which finds nothing
  FakeSite twoSources() => FakeSite({
    '/anime/hikka:$slug': fixture('mikai_detail.json'),
    '/anime/7601/player': jsonEncode(playerDoc()),
    '/teams/2': fixture('mikai_team.json'),
    'POST https://ufdub.com/index.php?do=search': '<html><body><div id="dle-content"></div></body></html>',
  });

  /// The "Джерела" button in the block header
  Finder sourcesLink() => find.byTooltip('Ще'); // "Джерела" is now in the "⋮" menu

  Future<void> openSources(WidgetTester tester) async {
    await menuItem(tester, 'Джерела, якість і плеєр');
    expect(find.text('Джерела перегляду'), findsOneWidget);
  }

  Future<void> closeDialog(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Закрити'));
    await settle(tester);
  }

  /// The block's current search: after a repeated search (`_restart`) it is a different object
  Object? searchOf(HikkaRoute route) => route.memo['watch'];

  // ── One action instead of choosing a dub ─────────────────────────────────────

  group('Одна дія замість вибору озвучки', () {
    testWidgets('кнопка «Дивитись», озвучка за замовчуванням і чипи вибору всіх варіантів перед стартом', (tester) async {
      StorageService.saveWatchTeamPriority(['Inari']); // fixtures assume Inari as the default dub
      await mount(tester);

      expect(find.text('Дивитись'), findsOneWidget); // block heading
      expect(find.text('Українські озвучки та субтитри'), findsOneWidget);
      expect(accent('Дивитись · серія 1'), findsOneWidget);
      expect(find.text('Inari'), findsWidgets);
      expect(find.textContaining('1–5 сер.'), findsWidgets);
      // All 11 variants are visible as chips at once; the chosen one is highlighted
      expect(tester.widget<AppDropdown<String>>(find.byType(AppDropdown<String>)).options.length, 11);
      for (final name in ['TuTaZaSho', '4UA', 'FanVoxUA', 'Рідний Голос', 'Glass Moon', 'Amanogawa', 'Далі Буде']) {
        expect(find.textContaining(name), findsWidgets, reason: name);
      }
      expect(selectedChip(tester), 'Озвучення: Inari');
      expect(find.byType(AppCard), findsNothing);
      // The episode is still airing: at least as many are dubbed as have aired, no yellow flag
      expect(find.byIcon(Symbols.warning_rounded), findsNothing);
      await shot(tester, 'desktop_default');
    });

    testWidgets('«Дивитись» одразу відкриває плеєр: ні вікон, ні вибору озвучки; усі варіанти передано в плеєр', (tester) async {
      StorageService.saveWatchTeamPriority(['Inari']); // fixtures assume Inari as the default dub
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
      // The person switches the remaining variants in the player, so all of them must be there
      expect(l.title.groups, hasLength(11));
      await settle(tester);
      expect(find.text('Тричі подумайте'), findsNothing);
      expect(find.byType(Dialog), findsNothing);
    });

    testWidgets('озвучка, яку обрали в плеєрі раніше, стає озвучкою за замовчуванням', (tester) async {
      store.setPinnedGroup(animeKey, 'mikai|7601|t_2:voice');
      await mount(tester);

      expect(selectedChip(tester), 'Озвучення: FanVoxUA');
      await tester.tap(accent('Дивитись · серія 1'));
      await tester.pump();
      expect(launches.single.group.label, 'FanVoxUA');
    });

    testWidgets('улюблена команда з інших тайтлів підставляється сама, а вибір для цього тайтлу сильніший', (tester) async {
      store.setFavoriteChoice('v:2'); // FanVoxUA (dub) was chosen in another title
      await mount(tester);
      expect(selectedChip(tester), 'Озвучення: FanVoxUA');

      store.setPinnedGroup(animeKey, 'mikai|7601|t_3:voice');
      await tester.pump();
      expect(selectedChip(tester), 'Озвучення: Glass Moon');
    });

    testWidgets('улюблені субтитри відкриваються як субтитри, а не підмінюються озвученням тієї ж команди', (tester) async {
      store.setFavoriteChoice('s:3'); // Glass Moon subtitles
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

      // The player remembers the choice in the store; the page listens to it
      store.setPinnedGroup(animeKey, 'mikai|7601|t_102:voice');
      await tester.pump();

      expect(find.text('TuTaZaSho'), findsWidgets);
      expect(find.textContaining('1–4 сер.'), findsWidgets);
      expect(find.textContaining('Озвучено 4 з 5 вийшлих серій'), findsNothing, reason: 'дисклеймер прибрано: кількість видно в рядку озвучки');
      await openEpisodes(tester);
      expect(find.text('5'), findsNothing); // the fifth episode is not in this variant yet
      expect(find.text('4'), findsOneWidget);
    });

    testWidgets('чипи варіантів узгоджуються з числом: жодного, два, п’ять; вибір чипа запамʼятовується', (tester) async {
      // One variant: no hint
      useSite(mikaiSite(playerDoc(edit: (r) => r.removeWhere((x) => x['id'] != 't_2:voice'))));
      await mount(tester);
      expect(find.text('FanVoxUA'), findsWidgets);
      expect(find.textContaining('1–5 сер.'), findsWidgets);
      expect(tester.widget<AppDropdown<String>>(find.byType(AppDropdown<String>)).options.length, 1);

      // One team's dub and subtitles: a list of two
      useSite(mikaiSite(playerDoc(edit: (r) => r.removeWhere((x) => !(x['id'] as String).startsWith('t_121:')))));
      await mount(tester);
      expect(find.text('Inari'), findsWidgets);
      expect(find.textContaining('1–5 сер.'), findsWidgets);
      expect(tester.widget<AppDropdown<String>>(find.byType(AppDropdown<String>)).options.length, 2);
      await tester.tap(find.text('Inari').first); // expand the list
      await settle(tester);
      await tester.tap(find.text('Inari').last); // the last item is subtitles
      await settle(tester);
      expect(store.preferredGroup(animeKey), contains('t_121:sub'));
      expect(accent('Дивитись · серія 1'), findsOneWidget);

      // Five variants, five items
      useSite(
        mikaiSite(
          playerDoc(edit: (r) => r.removeWhere((x) => !const {'t_121:voice', 't_121:sub', 't_2:voice', 't_3:voice', 't_3:sub'}.contains(x['id']))),
        ),
      );
      await mount(tester);
      expect(find.textContaining('1–5 сер.'), findsWidgets);
      expect(tester.widget<AppDropdown<String>>(find.byType(AppDropdown<String>)).options.length, 5);
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
      store.setPinnedGroup(animeKey, 'mikai|7601|t_2:voice');
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

  // ── Mismatches with Hikka ────────────────────────────────────────────────────

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

      expect(find.textContaining('1–24 сер.'), findsWidgets);
      expect(colorContaining(tester, '1–24 сер.'), amber);
      expect(find.textContaining('Тут 24 серій, а на Hikka їх лише 12.'), findsOneWidget);
      expect(find.textContaining('об’єднано 2 частини підряд'), findsOneWidget);
      expect(find.textContaining('передаватимуться на Hikka за номером серії'), findsOneWidget);
      expect(find.byIcon(Symbols.warning_rounded), findsWidgets);
      await shot(tester, 'desktop_merged_parts');
    });

    testWidgets('є варіант із правильною нумерацією — «Дивитись» відкриває його, а склеєний не нав’язується', (tester) async {
      useSite(
        mikaiSite(
          playerDoc(
            edit: (r) {
              setEpisodes(r[0], upTo(24)); // TuTaZaSho: two parts merged, they have the most, so they come first in the list
              setEpisodes(r[1], upTo(12)); // Inari: exactly 12
            },
          ),
        ),
      );
      await mount(tester, a: anime(released: 12, total: 12, status: 'finished'));

      expect(find.text('Inari'), findsWidgets);
      expect(find.textContaining('1–12 сер.'), findsWidgets);
      expect(colorContaining(tester, '1–12 сер.'), isNot(amber));
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
      store.setPinnedGroup(animeKey, 'mikai|7601|t_102:voice');
      await mount(tester, a: anime(released: 12, total: 12, status: 'finished'));

      expect(find.text('TuTaZaSho'), findsWidgets);
      expect(colorContaining(tester, '1–24 сер.'), amber);
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
              // The 13th episode is named "OVA"
              ((r[0]['episodes'] as List).last as Map<String, dynamic>)['label'] = 'OVA 1';
              setEpisodes(r[1], upTo(12));
            },
          ),
        ),
      );
      await mount(tester, a: anime(released: 12, total: 12, status: 'finished'));

      // The thirteenth episode is named "OVA 1" and stands at the end: the main 12 match Hikka, we do not sync the extra one
      expect(find.text('TuTaZaSho'), findsWidgets);
      expect(find.textContaining('1–12 сер.'), findsWidgets);
      expect(find.textContaining('Останні 1 серія схожа на OVA або спецвипуск (OVA 1)'), findsOneWidget);
      expect(find.textContaining('передаватимуться на Hikka'), findsNothing);
      await openEpisodes(tester);
      expect(find.text('13'), findsOneWidget); // the episode button is labeled with the number, the name "OVA 1" is in the hint
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
      expect(accent('Дивитись'), findsOneWidget); // the button is always there, but there is nothing to watch yet
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
      expect(colorContaining(tester, '1–7 сер.'), amber);
      expect(find.textContaining('У цього озвучення є відсутні серії: 7/12'), findsNothing, reason: 'плашку прибрано: застереження вже є в рядку озвучки');
      // This is not a numbering failure: something can still be synced (level incomplete, not mismatch)
      expect(find.textContaining('передаватимуться на Hikka'), findsNothing);
    });
  });

  // ── License ───────────────────────────────────────────────────────────────

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
      // We show no dubs or episodes and do not open the player until the person confirms the choice
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

      // The dialog's main action is legal viewing. It closes the dialog, opens the link, the player does not start
      await tester.tap(find.widgetWithText(AppAccentButton, 'Дивитись легально'));
      await settle(tester);
      expect(opened, ['https://www.crunchyroll.com/series/X']);
      expect(launches, isEmpty);
      expect(find.text('Тричі подумайте'), findsNothing);
      expect(find.text('Inari'), findsNothing);
      expect(find.text('Ліцензовано в Україні'), findsOneWidget);
    });

    testWidgets('підтвердження в діалозі одразу відкриває плеєр; на сторінці лишається нагадування з посиланнями', (tester) async {
      StorageService.saveWatchTeamPriority(['Inari']); // fixtures assume Inari as the default dub
      await mount(tester);
      await tester.tap(find.text('Все одно дивитись'));
      await settle(tester);
      await tester.tap(find.text('Все одно дивитись').last);
      await settle(tester);

      // The player opens without any extra step
      expect(find.text('Тричі подумайте'), findsNothing);
      expect(launches, hasLength(1));
      expect(launches.single.group.label, 'Inari');
      expect(launches.single.epKey, '1');

      // The page is now ordinary, with a reminder on top
      expect(find.text('Ліцензовано в Україні. Якщо можете, дивіться легально.'), findsOneWidget);
      expect(accent('Дивитись · серія 1'), findsOneWidget);
      expect(find.text('Inari'), findsWidgets);
      expect(find.text('Crunchyroll'), findsOneWidget); // the rights holder's links stay at hand as chips
      await shot(tester, 'desktop_licensed_acknowledged');

      // Launching again no longer asks: the person confirmed the choice on this showing of the page
      await tester.tap(accent('Дивитись · серія 1'));
      await tester.pump();
      expect(launches, hasLength(2));
      expect(find.text('Тричі подумайте'), findsNothing);

      // The choice is not saved: a new page (a new route) shows the card again
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

  // ── Empty and errors ─────────────────────────────────────────────────────

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
      expect(find.textContaining('Mikai:'), findsOneWidget); // a source error is in the "Ще" menu
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

    testWidgets('єдине джерело вимкнути не можна: стара позначка «вимкнено» ігнорується', (tester) async {
      prefsOf().setEnabled('mikai', false);
      await mount(tester);
      expect(find.text('Усі джерела вимкнено'), findsNothing);
      expect(find.text('Inari'), findsWidgets);
    });
  });

  // ── The "Джерела" window ────────────────────────────────────────────────────

  group('Вікно «Джерела»', () {
    testWidgets('відкривається з шапки блоку: сайти з поясненнями, якість, плеєр за замовчуванням, ключ', (tester) async {
      useSite(twoSources(), ufdub: true);
      await mount(tester);
      await openSources(tester);

      expect(find.text('Сайти'), findsOneWidget);
      expect(find.text('Mikai'), findsOneWidget);
      expect(find.text('UFDub'), findsOneWidget);
      expect(find.textContaining('Основне джерело: знає команди озвучення й серії.'), findsOneWidget);
      expect(find.text('Максимальна якість відео'), findsOneWidget);
      for (final q in ['Найвища', '1080p', '720p', '480p']) {
        expect(find.text(q), findsOneWidget, reason: q);
      }
      expect(find.text('Плеєр за замовчуванням'), findsOneWidget);
      for (final h in ['Авто', 'Moon']) {
        expect(find.text(h), findsOneWidget, reason: h);
      }
      expect(find.text('Ashdi'), findsNothing, reason: 'умова Moon: Ashdi у виборі плеєра не пропонується');
      expect(find.text('Ключ Mikai API'), findsNothing, reason: 'ключі API — у «Розробник»');
      await shot(tester, 'desktop_sources');

      await closeDialog(tester);
      expect(find.text('Джерела перегляду'), findsNothing);
    });

    testWidgets('пріоритет команд: додавання зі списку, що випадає, і власної назви без повторів', (tester) async {
      StorageService.saveWatchTeamPriority([]);
      addTearDown(() => StorageService.saveWatchTeamPriority([]));
      await mount(tester);
      await openSources(tester);

      final field = find.text('Команди озвучення');
      await tester.ensureVisible(field);
      await tester.pump();
      await tester.tap(field);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.enterText(find.byType(TextField).last, 'Nova Team');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Додати «Nova Team»'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(StorageService.getWatchTeamPriority(), ['Nova Team']);

      // the list stays open; the same name is not offered a second time as new
      await tester.enterText(find.byType(TextField).last, 'nova team');
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Додати «nova team»'), findsNothing);
      expect(StorageService.getWatchTeamPriority(), ['Nova Team'], reason: 'та сама назва вдруге не додається');
      expect(tester.takeException(), isNull);
    });

    testWidgets('телефон: список команд із прапорцями не закривається після вибору, закривається торканням поза блоком (знімки)', (tester) async {
      phone();
      StorageService.saveWatchTeamPriority(['Inari', 'Amanogawa']);
      addTearDown(() => StorageService.saveWatchTeamPriority([]));
      StorageService.rememberTeams(['Inari', 'Amanogawa', 'FanVoxUA', 'Clan Kaizoku']);
      addTearDown(StorageService.clearKnownTeams);
      await mount(tester, size: kNarrow);
      await openSources(tester);

      Finder inList(String t) => find.descendant(of: find.byType(AppSearchDropdown<String>), matching: find.text(t));
      final field = find.text('Команди озвучення');
      await tester.ensureVisible(field);
      await tester.pump(const Duration(milliseconds: 300));
      await shot(tester, 'phone_team_dropdown_closed');
      await tester.tap(field);
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await shot(tester, 'phone_team_dropdown_open');

      await tester.tap(inList('FanVoxUA'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(StorageService.getWatchTeamPriority(), ['Inari', 'Amanogawa', 'FanVoxUA']);
      expect(inList('Glass Moon'), findsOneWidget, reason: 'список лишається відкритим після вибору');
      await tester.ensureVisible(inList('FanVoxUA'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(inList('FanVoxUA'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(StorageService.getWatchTeamPriority(), ['Inari', 'Amanogawa'], reason: 'повторне торкання знімає прапорець');

      await tester.tapAt(const Offset(20, 60));
      await tester.pump(const Duration(milliseconds: 500));
      expect(inList('Glass Moon'), findsNothing, reason: 'торкання поза блоком закриває список');
      expect(tester.takeException(), isNull);
    });

    testWidgets('телефон: з клавіатурою сторінка підіймає поле пошуку, і список команд лишається видимим', (tester) async {
      phone();
      StorageService.rememberTeams(['Inari', 'Amanogawa', 'FanVoxUA', 'Clan Kaizoku']);
      addTearDown(StorageService.clearKnownTeams);
      await mount(tester, size: kNarrow);
      await openSources(tester);
      final field = find.text('Команди озвучення');
      await tester.ensureVisible(field);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(field);
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      // the keyboard narrows the page's visible area
      tester.view.physicalSize = Size(tester.view.physicalSize.width, tester.view.physicalSize.height - 300 * tester.view.devicePixelRatio);
      tester.view.viewInsets = FakeViewPadding(bottom: 300 * tester.view.devicePixelRatio);
      addTearDown(() => tester.view.resetViewInsets());
      for (var i = 0; i < 80; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final search = tester.getTopLeft(find.byType(TextField).last).dy;
      final item = tester.getTopLeft(find.descendant(of: find.byType(AppSearchDropdown<String>), matching: find.byType(ListView))).dy;
      final screenH = tester.view.physicalSize.height / tester.view.devicePixelRatio;
      expect(search, lessThan(screenH * 0.3), reason: 'поле пошуку піднялося вгору');
      expect(item, lessThan(screenH - 60), reason: 'початок списку видно над клавіатурою');
      expect(tester.takeException(), isNull);
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

    testWidgets('продовження йде тією озвучкою, яку обрано: серії інші, номер той самий', (tester) async {
      store.setWatched(animeKey, '1', true);
      store.setWatched(animeKey, '2', true);
      store.setPinnedGroup(animeKey, 'mikai|7601|t_102:voice'); // this variant has only 4 episodes
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
      expect(launches, isEmpty); // a long press does not start playback

      await tester.longPress(find.text('3'));
      await tester.pump();
      expect(store.watched(animeKey), isEmpty);

      await tester.tap(find.text('4'), buttons: kSecondaryButton);
      await tester.pump();
      expect(store.watched(animeKey), {'4'});
      expect(launches, isEmpty);
    });

    testWidgets('натискання на номер серії запускає саме її', (tester) async {
      StorageService.saveWatchTeamPriority(['Inari']); // fixtures assume Inari as the default dub
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
      store.setPinnedGroup(animeKey, 'mikai|7601|t_3:voice'); // chosen in the player
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
      store.setPinnedGroup(animeKey, 'mikai|7601|t_102:voice');
      await mount(tester, a: anime(released: 120, total: 120, status: 'finished'));

      expect(accent('Продовжити · серія 61'), findsOneWidget);
      await openEpisodes(tester);
      expect(find.text('Показати всі (120)'), findsOneWidget);
      expect(find.textContaining('Показано серії'), findsOneWidget);
      expect(find.text('61'), findsOneWidget);
      expect(find.text('1'), findsNothing); // the first episodes are outside the window

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

  // ── Phone ────────────────────────────────────────────────────────────────

  group('Телефон', () {
    /// Touch zone at least 48 dp
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

    });
  });

  // ── Theme ───────────────────────────────────────────────────────────────────

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
