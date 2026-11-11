import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miki_miki/services/backend_client.dart';
import 'package:miki_miki/services/hikka_api.dart';
import 'package:miki_miki/services/hikka_auth.dart';
import 'package:miki_miki/services/hikka_client_key.dart';
import 'package:miki_miki/services/hikka_lists.dart';
import 'package:miki_miki/services/hikka_nav.dart';
import 'package:miki_miki/services/ui_theme_service.dart';
import 'package:miki_miki/utils/platform_info.dart';
import 'package:miki_miki/widgets/hikka/hikka_cards.dart';
import 'package:miki_miki/widgets/hikka/hikka_common.dart';
import 'package:miki_miki/widgets/hikka/hikka_hub.dart';
import 'package:miki_miki/widgets/hikka/hikka_page_kit.dart';
import 'package:miki_miki/widgets/home_hub.dart';

import 'support/fakes.dart';
import 'support/hikka_account_fakes.dart';
import 'support/hikka_fakes.dart';

const Size kDesktop = Size(1280, 720);
const Size kNarrow = Size(360, 780);

const String frieren = 'sousou-no-frieren-ad4e3e';
const String aot = 'shingeki-no-kyojin-0cf69a'; // 25 серій
const String deathNote = 'death-note-e967c4'; // 37 серій
const String onePunch = 'one-punch-man-fccb30'; // 12 серій
const String kimetsu = 'kimetsu-no-yaiba-6d4c98';

void setScreen(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// Дає час мережі (підставній), диску й декодеру зображень: вони живуть у справжньому часі
Future<void> load(WidgetTester tester, {int rounds = 12}) async {
  for (int i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<void> shot(WidgetTester tester, String name) =>
    expectLater(find.byType(MaterialApp), matchesGoldenFile('shots/hikka_$name.png'));

/// Акаунт «tester» на підставному сервері Hikka: списки, улюблене, вхід. Змінюється запитами, як справжній.
class FakeAccountServer {
  final FakeHikka server;
  final Map<String, Map<String, dynamic>> mine = {};
  final Set<String> favourites = {};

  /// «МЕТОД /шлях» усіх запитів до акаунта за порядком
  final List<String> calls = [];
  final List<Map<String, dynamic>> tokenBodies = [];
  final List<Map<String, dynamic>> listBodies = [];
  final List<String?> authHeaders = [];

  FakeAccountServer(this.server) {
    server.interceptor = _handle;
  }

  Map<String, dynamic> animeJson(String slug) {
    if (slug == frieren) return sampleMap('info.json');
    return server.animeList.firstWhere((a) => a['slug'] == slug);
  }

  Map<String, dynamic> watchJson(String slug, {required String status, int episodes = 0, int score = 0}) => {
        'reference': 'w-$slug',
        'note': null,
        'updated': 10,
        'created': 5,
        'status': status,
        'rewatches': 0,
        'duration': 0,
        'episodes': episodes,
        'score': score,
        'start_date': null,
        'end_date': null,
        'anime': animeJson(slug),
      };

  void seed() {
    mine
      ..clear()
      ..[aot] = watchJson(aot, status: 'watching', episodes: 5, score: 8)
      ..[deathNote] = watchJson(deathNote, status: 'watching', episodes: 3)
      ..[onePunch] = watchJson(onePunch, status: 'planned')
      ..[frieren] = watchJson(frieren, status: 'completed', episodes: 28, score: 9);
    favourites
      ..clear()
      ..add(kimetsu);
  }

  HikkaResponse _ok(Object? body) => HikkaResponse(200, jsonEncode(body));
  HikkaResponse _err(int status, String code) => HikkaResponse(status, jsonEncode({'code': code, 'message': code}));

  Map<String, dynamic> _page(List<Map<String, dynamic>> items) => {
        'pagination': {'total': items.length, 'pages': 1, 'page': 1},
        'list': items,
      };

  HikkaResponse? _handle(HikkaRequest r) {
    final p = r.url.path;
    final segs = p.split('/').where((s) => s.isNotEmpty).toList();
    final body = r.body == null ? const <String, dynamic>{} : jsonDecode(r.body!) as Map<String, dynamic>;
    final isAccount = p == '/auth/token' || p.startsWith('/auth/') || p == '/user/me' || segs.firstOrNull == 'watch' || segs.firstOrNull == 'favourite';
    if (!isAccount) return null;
    calls.add('${r.method} $p');
    if (segs.firstOrNull == 'watch' || segs.firstOrNull == 'favourite') authHeaders.add(r.headers['auth']);

    if (r.method == 'POST' && p == '/auth/token') {
      tokenBodies.add(body);
      return _ok({'secret': 'tok-ui', 'created': 1, 'expiration': 2});
    }
    if (r.method == 'GET' && p == '/user/me') return _ok(kMe);
    if (r.method == 'GET' && p == '/auth/token/info') return _ok({'reference': 'token-ref-1'});
    if (r.method == 'DELETE' && segs.length == 3 && segs[0] == 'auth' && segs[1] == 'token') return _ok({'success': true});

    if (segs.firstOrNull == 'watch') {
      if (r.method == 'POST' && segs.length == 3 && segs[2] == 'list') {
        listBodies.add(body);
        final status = body['watch_status'];
        return _ok(_page([
          for (final e in mine.values)
            if (e['status'] == status) e,
        ]));
      }
      if (r.method == 'GET' && segs.length == 3 && segs[2] == 'stats') {
        int n(String s) => mine.values.where((e) => e['status'] == s).length;
        return _ok({'duration': 0, 'watching': n('watching'), 'planned': n('planned'), 'completed': n('completed'), 'on_hold': n('on_hold'), 'dropped': n('dropped')});
      }
      if (segs.length == 2) {
        final slug = segs[1];
        switch (r.method) {
          case 'GET':
            return mine[slug] == null ? _err(404, 'watch:not_found') : _ok(mine[slug]);
          case 'PUT':
            return _ok(mine[slug] = watchJson(slug, status: body['status'] as String, episodes: body['episodes'] as int, score: (body['score'] as int?) ?? 0));
          case 'DELETE':
            mine.remove(slug);
            return _ok({'success': true});
        }
      }
    }
    if (segs.firstOrNull == 'favourite' && segs.length >= 3 && segs[1] == 'anime') {
      if (r.method == 'POST' && segs.length == 4 && segs[3] == 'list') {
        return _ok(_page([for (final s in favourites) animeJson(s)]));
      }
      if (segs.length == 3) {
        final slug = segs[2];
        switch (r.method) {
          case 'GET':
            return favourites.contains(slug) ? _ok({'success': true}) : _err(404, 'favourite:not_found');
          case 'PUT':
            favourites.add(slug);
            return _ok({'success': true});
          case 'DELETE':
            favourites.remove(slug);
            return _ok({'success': true});
        }
      }
    }
    return null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late HikkaTestEnv env;
  late FakeAccountServer account;
  late FakeBackend backend;

  setUpAll(() async {
    await loadTestFonts();
  });

  setUp(() {
    uiTheme.setThemeMode('dark');
    env = HikkaTestEnv();
    account = FakeAccountServer(env.server)..seed();
    HikkaClientKey.testReference = 'ui-client';
    backend = FakeBackend();
    BackendClient.instance = backend.client();
    HomeHub.debugReset();
  });

  tearDown(() {
    HikkaClientKey.testReference = null;
    AppPlatform.debugMobile = null;
    env.dispose();
  });

  /// Людина вже ввійшла (токен і профіль збережені)
  void signIn({bool sync = true}) {
    HikkaAuth.instance = HikkaAuth(
      load: () => {'token': 'tok-ui', 'me': Map<String, dynamic>.of(kMe), if (!sync) 'sync': false},
      save: (_) {},
      urlOpener: (url) async {
        env.opened.add(url);
        return true;
      },
      loopbackFactory: () async => null,
    );
    HikkaMyList.instance = HikkaMyList();
  }

  Widget hub({double scale = 1.0}) => MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: uiTheme.bgPrimary,
          body: HikkaHub(scale: scale, onOpenSettings: ({int? tab}) {}, localLibraryBuilder: (_) => const SizedBox()),
        ),
      );

  Future<void> openTab(WidgetTester tester, MainTab tab, {Size size = kDesktop}) async {
    setScreen(tester, size);
    await tester.pumpWidget(hub());
    await load(tester, rounds: 4);
    HikkaNav.instance.setMain(tab);
    await load(tester, rounds: 8);
    expect(tester.takeException(), isNull);
  }

  String pill(String slug, int episodes) {
    final total = account.animeJson(slug)['episodes_total'];
    return '$episodes/${total is int && total > 0 ? total : '?'}';
  }

  group('списки: фільтр і оновлення', () {
    testWidgets('телефон: кнопки «Оновити» немає, є фільтр; сортування за замовчуванням — нещодавно оновлені; потяг вниз оновлює', (tester) async {
      AppPlatform.debugMobile = true;
      signIn();
      await openTab(tester, MainTab.lists, size: kNarrow);
      expect(find.byTooltip('Оновити'), findsNothing);
      expect(find.byTooltip('Фільтри й сортування'), findsOneWidget);
      expect(account.listBodies.last['sort'], ['watch_updated:desc']);
      expect(account.listBodies.last['watch_status'], 'watching');

      final before = account.listBodies.length;
      await tester.fling(find.byType(HikkaAnimeCard).first, const Offset(0, 500), 1500);
      await load(tester, rounds: 10);
      expect(account.listBodies.length, greaterThan(before), reason: 'потяг вниз перезавантажив список');
      expect(tester.takeException(), isNull);
    });

    testWidgets('фільтр відкривається, застосування перезавантажує список із новим тілом запиту', (tester) async {
      signIn();
      await openTab(tester, MainTab.lists, size: kNarrow);
      final before = account.listBodies.length;
      await tester.tap(find.byTooltip('Фільтри й сортування'));
      await load(tester, rounds: 6);
      expect(find.text('Сортування'), findsOneWidget);
      expect(find.text('Нещодавно оновлені'), findsWidgets);
      await tester.tap(find.text('Показати результати'));
      await load(tester, rounds: 8);
      expect(find.text('Сортування'), findsNothing);
      expect(account.listBodies.length, greaterThan(before));
      expect(tester.takeException(), isNull);
    });

    testWidgets('ПК: кнопка «Оновити» лишається', (tester) async {
      signIn();
      await openTab(tester, MainTab.lists);
      expect(find.byTooltip('Оновити'), findsOneWidget);
      expect(find.byTooltip('Фільтри й сортування'), findsOneWidget);
    });
  });

  group('позначки статусу', () {
    testWidgets('каталог: статус пігулкою зверху ліворуч, оцінка поруч', (tester) async {
      signIn();
      await HikkaMyList.instance.loadIndex();
      HikkaNav.instance.setTab(HikkaTab.anime);
      await openTab(tester, MainTab.discover, size: kNarrow);
      await load(tester, rounds: 10);
      expect(find.text('Дивлюсь'), findsWidgets);
      await shot(tester, 'catalog_status_pill_narrow');
    });
  });

  group('«Списки» після входу', () {
    testWidgets('вкладки з лічильниками, картки з прогресом і оцінкою, порожня вкладка', (tester) async {
      signIn();
      await openTab(tester, MainTab.lists);

      expect(find.text('Списки'), findsOneWidget);
      expect(find.text('tester'), findsOneWidget, reason: 'під заголовком — імʼя користувача');
      expect(find.text('Гість'), findsNothing);
      for (final t in ['Дивлюсь · 2', 'У планах · 1', 'Переглянуто · 1', 'Відкладено · 0', 'Кинуто · 0', 'Улюблене']) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
      expect(find.byType(HikkaAnimeCard), findsNWidgets(2));
      expect(find.text(pill(aot, 5)), findsOneWidget);
      expect(find.text(pill(deathNote, 3)), findsOneWidget);
      expect(find.textContaining('★ 8'), findsOneWidget, reason: 'оцінка в підписі картки');
      await shot(tester, 'lists_signed_in_desktop');

      await tester.tap(find.text('У планах · 1'));
      await load(tester, rounds: 6);
      expect(find.byType(HikkaAnimeCard), findsOneWidget);
      expect(find.text(pill(onePunch, 0)), findsNothing, reason: 'у «У планах» лічильника серій немає');

      await tester.tap(find.text('Відкладено · 0'));
      await load(tester, rounds: 6);
      expect(find.byType(HikkaAnimeCard), findsNothing);
      expect(find.text('Тут поки порожньо. Додайте тайтл зі сторінки аніме.'), findsOneWidget);

      await tester.tap(find.text('Улюблене'));
      await load(tester, rounds: 6);
      expect(find.byType(HikkaAnimeCard), findsOneWidget);
      expect(account.calls, contains('POST /favourite/anime/tester/list'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('довге натискання на картці прибирає тайтл зі списку, лічильник зменшується', (tester) async {
      signIn();
      await openTab(tester, MainTab.lists);
      expect(find.byType(HikkaAnimeCard), findsNWidgets(2));

      await tester.longPress(find.byType(HikkaAnimeCard).first);
      await load(tester, rounds: 4);
      expect(find.text('Прибрати зі списку'), findsOneWidget);
      await tester.tap(find.text('Прибрати зі списку'));
      await load(tester, rounds: 10);

      expect(account.calls, contains('DELETE /watch/$aot'));
      expect(account.mine.containsKey(aot), isFalse);
      expect(find.byType(HikkaAnimeCard), findsOneWidget);
      expect(find.text('Дивлюсь · 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('поки вкладка вантажиться, видно сітку-заглушку, а не порожнечу чи коло', (tester) async {
      signIn();
      AppPlatform.debugMobile = true;
      await openTab(tester, MainTab.lists, size: kNarrow);
      await tester.tap(find.textContaining('Переглянуто'));
      await tester.pump();
      expect(find.byType(HikkaCardSkeleton), findsWidgets);
      await load(tester, rounds: 6);
      expect(find.byType(HikkaCardSkeleton), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('свайп по вмісту перемикає вкладку з анімацією, чип вкладки лишається в полі зору', (tester) async {
      signIn();
      AppPlatform.debugMobile = true;
      await openTab(tester, MainTab.lists, size: kNarrow);
      expect(find.byType(HikkaAnimeCard), findsNWidgets(2));
      await tester.fling(find.byType(HikkaAnimeCard).first, const Offset(-400, 0), 1500);
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.byType(HikkaSwipeTabs), findsOneWidget);
      final mid = tester.widget<Opacity>(find.descendant(of: find.byType(HikkaSwipeTabs), matching: find.byType(Opacity)).first).opacity;
      expect(mid, lessThan(1), reason: 'під час переходу вміст ще з’являється');
      await load(tester, rounds: 6);
      final done = tester.widget<Opacity>(find.descendant(of: find.byType(HikkaSwipeTabs), matching: find.byType(Opacity)).first).opacity;
      expect(done, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('вузький екран: вкладки прокручуються, переповнення немає', (tester) async {
      signIn();
      AppPlatform.debugMobile = true;
      await openTab(tester, MainTab.lists, size: kNarrow);
      expect(find.byType(HikkaAnimeCard), findsNWidgets(2));
      await shot(tester, 'lists_signed_in_narrow');
      expect(tester.getTopLeft(find.text('Улюблене')).dx, greaterThan(kNarrow.width), reason: 'остання вкладка поза екраном, її видно лише після прокрутки');
      await tester.drag(find.text('Дивлюсь · 2'), const Offset(-700, 0));
      await load(tester, rounds: 3);
      expect(tester.getTopLeft(find.text('Улюблене')).dx, lessThan(kNarrow.width));
      await tester.tap(find.text('Улюблене'));
      await load(tester, rounds: 6);
      expect(find.byType(HikkaAnimeCard), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('вхід', () {
    testWidgets('телефон: вікно входу має «Копіювати посилання» і не переповнюється', (tester) async {
      AppPlatform.debugMobile = true;
      await openTab(tester, MainTab.lists, size: kNarrow);
      await tester.tap(find.text('Увійти через Hikka'));
      await load(tester, rounds: 6);
      expect(find.text('Вхід у Hikka'), findsOneWidget);
      expect(find.text('Відкрити знову'), findsOneWidget);
      expect(find.text('Копіювати посилання'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await shot(tester, 'login_dialog_phone');
    });

    testWidgets('вікно входу: сторінка дозволу відкривається, вставлена адреса завершує вхід і відкриває списки', (tester) async {
      await openTab(tester, MainTab.lists);
      expect(find.text('Гість'), findsOneWidget);

      await tester.tap(find.text('Увійти через Hikka'));
      await load(tester, rounds: 6);
      expect(find.text('Вхід у Hikka'), findsOneWidget);
      expect(find.text('Чекаю на підтвердження в браузері…'), findsOneWidget);
      expect(env.opened, hasLength(1));
      expect(env.opened.single, startsWith('https://hikka.io/oauth?reference=ui-client&scope=user-details,watchlist,favourite'));
      expect(find.text('Адреса або код входу'), findsOneWidget, reason: 'локальна адреса не піднялась — лишається вставити код');
      await shot(tester, 'login_dialog_desktop');

      await tester.enterText(find.byType(TextField), 'http://127.0.0.1:47615/auth/confirm?reference=$kRequestRef');
      await tester.tap(find.text('Підтвердити'));
      await load(tester, rounds: 14);

      expect(find.text('Вхід у Hikka'), findsNothing, reason: 'після входу вікно закривається саме');
      expect(HikkaAuth.instance.signedIn, isTrue);
      expect(HikkaAuth.instance.username, 'tester');
      expect(backend.exchanges.single, {'request_reference': kRequestRef}, reason: 'секрет клієнта до бекенду не передається застосунком');
      expect(find.text('Дивлюсь · 2'), findsOneWidget, reason: 'списки відкрились без перезапуску');
      expect(account.authHeaders.every((h) => h == null || h == 'tok-ui'), isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('«Скасувати» закриває вікно й лишає гостем; сторінка дозволу не вимагає нічого вводити', (tester) async {
      await openTab(tester, MainTab.profile);
      await tester.tap(find.text('Увійти через Hikka'));
      await load(tester, rounds: 6);
      expect(find.text('Вхід у Hikka'), findsOneWidget);
      await tester.tap(find.text('Скасувати'));
      await load(tester, rounds: 6);
      expect(find.text('Вхід у Hikka'), findsNothing);
      expect(HikkaAuth.instance.signedIn, isFalse);
      expect(HikkaAuth.instance.phase, HikkaAuthPhase.signedOut);
      expect(find.text('Гість'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('сміття замість адреси: зрозуміла підказка, вікно лишається', (tester) async {
      await openTab(tester, MainTab.profile);
      await tester.tap(find.text('Увійти через Hikka'));
      await load(tester, rounds: 6);
      await tester.enterText(find.byType(TextField), 'привіт');
      await tester.tap(find.text('Підтвердити'));
      await load(tester, rounds: 3);
      expect(HikkaAuth.instance.error, isNotNull);
      expect(HikkaAuth.instance.signedIn, isFalse);
      expect(find.text('Вхід у Hikka'), findsOneWidget);
      expect(backend.exchanges, isEmpty, reason: 'на сервер нічого не пішло');
      await tester.tap(find.text('Скасувати'));
      await load(tester, rounds: 4);
    });
  });

  group('профіль', () {
    testWidgets('картка акаунта: імʼя, перемикач синхронізації, вихід відкликає токен', (tester) async {
      signIn();
      await openTab(tester, MainTab.profile);
      expect(find.text('tester'), findsOneWidget);
      expect(find.text('Акаунт Hikka підключено'), findsOneWidget);
      expect(find.text('Увійти через Hikka'), findsNothing);
      expect(HikkaAuth.instance.syncProgress, isTrue);
      await shot(tester, 'profile_signed_in_desktop');

      await tester.tap(find.text('Передавати прогрес у списки'));
      await load(tester, rounds: 3);
      expect(HikkaAuth.instance.syncProgress, isFalse);

      await tester.tap(find.text('Вийти з акаунта'));
      await load(tester, rounds: 8);
      expect(HikkaAuth.instance.signedIn, isFalse);
      expect(account.calls, containsAllInOrder(['GET /auth/token/info', 'DELETE /auth/token/token-ref-1']));
      expect(find.text('Гість'), findsOneWidget);
      expect(find.text('Увійти через Hikka'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('сторінка аніме: «Мій список»', () {
    Future<void> openAnime(WidgetTester tester) async {
      await openTab(tester, MainTab.home);
      HikkaNav.instance.openAnime(frieren);
      await load(tester, rounds: 16);
      expect(tester.takeException(), isNull);
    }

    testWidgets('гість: «Додати в список» веде до входу', (tester) async {
      await openAnime(tester);
      expect(find.text('Додати в список'), findsOneWidget);
      expect(find.byTooltip('В улюблене'), findsNothing, reason: 'серце лише для тих, хто ввійшов');
      await tester.tap(find.text('Додати в список'));
      await load(tester, rounds: 6);
      expect(find.text('Вхід у Hikka'), findsOneWidget);
      await tester.tap(find.text('Скасувати'));
      await load(tester, rounds: 4);
    });

    testWidgets('додати зі статусом, змінити, поставити серце, прибрати', (tester) async {
      signIn();
      account.mine.clear();
      account.favourites.clear();
      await openAnime(tester);

      expect(find.text('Додати в список'), findsOneWidget);
      await shot(tester, 'anime_my_list_empty_desktop');
      await tester.tap(find.text('Додати в список'));
      await load(tester, rounds: 4);
      expect(find.text('Серії та оцінка…'), findsOneWidget, reason: 'випадне меню, а не вікно');
      expect(find.text('Видалити зі списку'), findsNothing, reason: 'запису ще немає');
      await tester.tap(find.text('Дивлюсь'));
      await load(tester, rounds: 10);

      expect(account.mine[frieren]?['status'], 'watching');
      expect(find.text('Дивлюсь'), findsOneWidget, reason: 'тепер на сторінці плитка зі статусом');
      expect(find.textContaining('серій'), findsNothing, reason: 'кількість серій на кнопці статусу не показуємо');
      await shot(tester, 'anime_my_list_watching_desktop');

      // Серце
      await tester.tap(find.byTooltip('В улюблене'));
      await load(tester, rounds: 6);
      expect(account.favourites, contains(frieren));
      expect(find.byTooltip('Прибрати з улюбленого'), findsOneWidget);

      // Змінити: «Переглянуто» добиває лічильник до кінця, оцінка 9
      await tester.tap(find.text('Дивлюсь'));
      await load(tester, rounds: 12);
      await tester.tap(find.text('Серії та оцінка…'));
      await load(tester, rounds: 10);
      expect(find.text('Мій список'), findsOneWidget);
      await tester.tap(find.text('Переглянуто'));
      await tester.pump();
      await tester.tap(find.text('9'));
      await tester.pump();
      await tester.tap(find.text('Зберегти'));
      await load(tester, rounds: 10);
      expect(account.mine[frieren]?['status'], 'completed');
      expect(account.mine[frieren]?['episodes'], 28);
      expect(account.mine[frieren]?['score'], 9);
      expect(find.text('Переглянуто'), findsOneWidget);
      expect(find.textContaining('серій'), findsNothing);

      // Прибрати
      await tester.tap(find.text('Переглянуто'));
      await load(tester, rounds: 12);
      await tester.tap(find.text('Видалити зі списку'));
      await load(tester, rounds: 10);
      expect(account.mine.containsKey(frieren), isFalse);
      expect(find.text('Додати в список'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('уже в списку: плитка показує статус, прогрес і оцінку', (tester) async {
      signIn();
      await openAnime(tester);
      expect(find.text('Переглянуто'), findsOneWidget);
      expect(find.textContaining('серій'), findsNothing);
      expect(find.text('9'), findsOneWidget, reason: 'оцінка окремою плашкою зі зіркою');
      expect(find.text('Додати в список'), findsNothing);
    });

    testWidgets('збій мережі при виборі статусу: запису немає, кнопка лишається; потім спрацьовує', (tester) async {
      signIn();
      account.mine.clear();
      await openAnime(tester);
      await tester.tap(find.text('Додати в список'));
      await load(tester, rounds: 12);
      env.server.offline = true;
      await tester.tap(find.text('У планах'));
      await load(tester, rounds: 10);
      expect(account.mine, isEmpty);
      expect(find.text('Додати в список'), findsOneWidget);
      env.server.offline = false;
      await tester.tap(find.text('Додати в список'));
      await load(tester, rounds: 12);
      await tester.tap(find.text('У планах'));
      await load(tester, rounds: 10);
      expect(account.mine[frieren]?['status'], 'planned');
      expect(tester.takeException(), isNull);
    });
  });
}
