import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miki_miki/models/hikka_user_models.dart';
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
import 'package:miki_miki/widgets/hikka/hikka_user_profile.dart';
import 'package:miki_miki/widgets/home_hub.dart';

import 'support/fakes.dart';
import 'support/hikka_account_fakes.dart';
import 'support/hikka_fakes.dart';

const Size kDesktop = Size(1280, 720);
const Size kNarrow = Size(360, 780);

const String frieren = 'sousou-no-frieren-ad4e3e';
const String aot = 'shingeki-no-kyojin-0cf69a'; // 25 episodes
const String deathNote = 'death-note-e967c4'; // 37 episodes
const String onePunch = 'one-punch-man-fccb30'; // 12 episodes
const String kimetsu = 'kimetsu-no-yaiba-6d4c98';

void setScreen(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// Gives time to the (fake) network, the disk and the image decoder: they live in real time
Future<void> load(WidgetTester tester, {int rounds = 12}) async {
  for (int i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<void> shot(WidgetTester tester, String name) =>
    expectLater(find.byType(MaterialApp), matchesGoldenFile('shots/hikka_$name.png'));

/// The "tester" account on the fake Hikka server: lists, favorites, sign-in. It changes with requests like a real one.
class FakeAccountServer {
  final FakeHikka server;
  final Map<String, Map<String, dynamic>> mine = {};
  final Set<String> favourites = {};

  /// "METHOD /path" of all account requests in order
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

  /// November 12, 2025 (Wednesday), UTC midnight: activity days and history are counted from it so screenshots do not depend on the date
  static const int profileDay = 1762905600;

  /// Public profile: `/user/{u}`, `/user/{u}/stats`, `/user/{u}/activity`, `/follow/{u}/stats`, `/history/user/{u}`,
  /// favorite characters. For unknown users, 404.
  HikkaResponse? _profile(HikkaRequest r, List<String> segs) {
    if (segs.isEmpty || segs.first == 'auth') return null;
    final known = {'tester', 'other'};
    String? name;
    if (segs.first == 'user' && segs.length >= 2 && segs[1] != 'me') name = segs[1];
    if (segs.first == 'follow' && segs.length == 3 && segs[2] == 'stats') name = segs[1];
    if (segs.first == 'history' && segs.length == 3 && segs[1] == 'user') name = segs[2];
    if (segs.first == 'favourite' && segs.length == 4 && segs[1] == 'character') name = segs[2];
    if (name == null) return null;
    calls.add('${r.method} ${r.url.path}');
    if (!known.contains(name)) return _err(404, 'user:not_found');
    if (segs.first == 'user' && segs.length == 2) {
      return _ok({
        ...kMe,
        'username': name,
        'created': 1705190224,
        'description': name == 'tester' ? 'Дивлюсь усе, що виходить' : null,
        'cover': null,
        'role': name == 'tester' ? 'moderator' : 'user',
        'links': [
          {'url': 'https://t.me/tester', 'text': 'Telegram', 'icon': 'telegram'},
        ],
      });
    }
    if (segs.first == 'user' && segs[2] == 'stats') {
      return _ok({
        'favourites_count': {'anime': favourites.length, 'character': 1, 'collection': 0, 'manga': 2},
        'comments_count': 741,
        'reviews_count': 2,
        'edits_count': 5552,
      });
    }
    if (segs.first == 'user' && segs[2] == 'activity') {
      return _ok([
        for (int i = 364; i >= 0; i--) {'timestamp': profileDay - i * 86400, 'actions': (i * 7) % 11 == 0 ? 0 : (i * 13) % 37},
      ]);
    }
    if (segs.first == 'follow') return _ok({'followers': 42, 'following': 60});
    if (segs.first == 'favourite') {
      return _ok(_page([
        {'slug': 'afghanis-tan-6d7b4b', 'name_ua': 'Афганіс-тан', 'name_en': 'Afghanis-tan', 'image': null, 'synonyms': []},
      ]));
    }
    // History: two events "today" (November 12, 2025) and two a day earlier; one is about manga (not shown)
    Map<String, dynamic> h(String ref, int time, String type, Map<String, dynamic> before, Map<String, dynamic> after, {Map<String, dynamic>? content, bool isNew = false}) => {
          'reference': ref,
          'created': time,
          'updated': time,
          'history_type': type,
          'user': kMe,
          'content': content,
          'data': {'before': before, 'after': after, if (type == 'watch') 'new_watch': isNew},
        };
    final day = profileDay - 3600; // November 11, 2025, 23:00 UTC
    return _ok({
      'pagination': {'total': 5, 'pages': 1, 'page': 1},
      'list': [
        h('h1', profileDay + 13 * 3600, 'watch', {'episodes': 4}, {'episodes': 5}, content: animeJson(aot)),
        h('h2', profileDay + 9 * 3600, 'watch', {'status': 'watching', 'episodes': 26}, {'status': 'completed', 'episodes': 28}, content: animeJson(frieren)),
        h('h3', day - 2 * 3600, 'read_manga', {'chapters': 1}, {'chapters': 2}, content: {'data_type': 'manga', 'slug': 'm', 'title_ua': 'Манґа'}),
        h('h4', day - 3 * 3600, 'watch', {}, {'status': 'planned', 'episodes': 0}, content: animeJson(onePunch), isNew: true),
        h('h5', day - 5 * 3600, 'favourite_anime_add', {}, {}, content: animeJson(kimetsu)),
      ],
    });
  }
  HikkaResponse _err(int status, String code) => HikkaResponse(status, jsonEncode({'code': code, 'message': code}));

  Map<String, dynamic> _page(List<Map<String, dynamic>> items) => {
        'pagination': {'total': items.length, 'pages': 1, 'page': 1},
        'list': items,
      };

  HikkaResponse? _handle(HikkaRequest r) {
    final p = r.url.path;
    final segs = p.split('/').where((s) => s.isNotEmpty).toList();
    final body = r.body == null ? const <String, dynamic>{} : jsonDecode(r.body!) as Map<String, dynamic>;
    final profile = _profile(r, segs);
    if (profile != null) return profile;
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

  /// The person is already signed in (the token and profile are saved)
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
          body: HikkaHub(scale: scale, onOpenSettings: ({int? tab}) {}, localLibraryBuilder: (_) => const SizedBox(), settingsBuilder: (_) => const Center(child: Text('НАЛАШТУВАННЯ'))),
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
    testWidgets('профіль як на hikka.io: шапка, «Список», «Активність», улюблене, «Історія»; акаунт і вихід', (tester) async {
      signIn();
      await openTab(tester, MainTab.profile);
      await load(tester, rounds: 10);
      expect(find.text('tester'), findsOneWidget);
      expect(find.text('Модератор'), findsOneWidget);
      expect(find.text('Дивлюсь усе, що виходить'), findsOneWidget);
      expect(find.textContaining('стежать'), findsOneWidget);
      expect(find.text('На Hikka з січня 2024'), findsOneWidget);
      expect(find.text('Telegram'), findsOneWidget);
      expect(find.text('Список'), findsOneWidget);
      expect(find.text('Час перегляду'), findsOneWidget);
      expect(find.text('Активність'), findsOneWidget);
      expect(find.byType(HikkaActivityHeatmap), findsOneWidget);
      expect(find.text('Правки'), findsOneWidget);
      expect(find.text('5\u00a0552'), findsOneWidget);
      expect(account.calls, containsAll(['GET /user/tester', 'GET /user/tester/stats', 'GET /follow/tester/stats', 'GET /user/tester/activity']));

      // Status counters come from `GET /watch/tester/stats`
      final summary = find.byType(HikkaWatchSummary);
      expect(find.descendant(of: summary, matching: find.text('4')), findsOneWidget, reason: 'усього 4 тайтли — у центрі кільця');
      expect(find.descendant(of: summary, matching: find.text('2')), findsOneWidget, reason: 'дивлюсь 2 — у легенді');
      expect(find.descendant(of: summary, matching: find.textContaining('%')), findsNothing, reason: 'відсотків у легенді немає');
      await shot(tester, 'profile_signed_in_desktop');

      // Below: favorites, "Історія" (manga dropped), "Акаунт"
      await tester.scrollUntilVisible(find.text('Історія'), 300, scrollable: find.byType(Scrollable).first);
      await load(tester, rounds: 6);
      expect(find.text('Улюблені аніме'), findsOneWidget);
      expect(find.text('Переглянуто епізод 5 з 25'), findsOneWidget);
      expect(find.text('Завершено'), findsOneWidget);
      expect(find.text('Додано до списку «У планах»'), findsOneWidget);
      expect(find.text('Додано до улюблених'), findsOneWidget);
      expect(find.text('Манґа'), findsNothing);
      expect(find.text('Акаунт Hikka підключено'), findsNothing, reason: 'імʼя й аватар уже в шапці профілю');

      // Account, settings and "Про застосунок" are icons in the header, not at the bottom of the page
      expect(find.text('Передавати прогрес у списки'), findsNothing);
      expect(find.text('Налаштування застосунку'), findsNothing);
      expect(find.byTooltip('Налаштування застосунку'), findsOneWidget);
      expect(find.byTooltip('Про Miki Miki'), findsNothing, reason: '«Про застосунок» — у налаштуваннях');
      // The header hides on scrolling down: we scroll up
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 4000));
      await load(tester, rounds: 6);
      await tester.tap(find.byTooltip('Акаунт'));
      await load(tester, rounds: 6);
      await tester.tap(find.text('Передавати прогрес у списки'));
      await load(tester, rounds: 3);
      expect(HikkaAuth.instance.syncProgress, isFalse);

      await tester.tap(find.text('Вийти з акаунта'));
      await load(tester, rounds: 8);
      expect(HikkaAuth.instance.signedIn, isFalse);
      expect(account.calls, containsAllInOrder(['GET /auth/token/info', 'DELETE /auth/token/token-ref-1']));
      expect(find.text('Гість'), findsOneWidget);
      expect(find.text('Увійти через Hikka'), findsOneWidget);
      expect(find.byType(HikkaWatchSummary), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('лічильник статусу в профілі відкриває «Списки» на цьому статусі', (tester) async {
      signIn();
      await openTab(tester, MainTab.profile);
      await load(tester, rounds: 10);
      await tester.tap(find.descendant(of: find.byType(HikkaWatchSummary), matching: find.text('У планах')));
      await load(tester, rounds: 8);
      expect(HikkaNav.instance.main, MainTab.lists);
      expect(account.listBodies.last['watch_status'], 'planned');
      expect(tester.takeException(), isNull);
    });

    testWidgets('«Список»: кільце з усіма статусами (дрібні — краплі), натискання на дугу й центр', (tester) async {
      setScreen(tester, kNarrow);
      AppPlatform.debugMobile = true;
      addTearDown(() => AppPlatform.debugMobile = null);
      final tapped = <HikkaWatchStatus?>[];
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(),
        home: Scaffold(
          backgroundColor: uiTheme.bgPrimary,
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                HikkaWatchSummary(
                scale: 1,
                stats: const HikkaWatchStats(completed: 488, watching: 21, planned: 69, dropped: 77, onHold: 18, duration: 215108),
                onStatus: tapped.add,
              ),
              ],
            ),
          ),
        ),
      ));
      await tester.pump();
      await shot(tester, 'profile_donut_zeddy');
      final donut = tester.widget<HikkaStatusDonut>(find.byType(HikkaStatusDonut));
      final origin = tester.getTopLeft(find.byType(HikkaStatusDonut));
      final l = donut.layout;
      final r = (donut.size - donut.thickness) / 2;
      Offset at(int j) {
        final a = l.starts[j] + l.lengths[j] / 2;
        return origin + Offset(donut.size / 2 + math.cos(a) * r, donut.size / 2 + math.sin(a) * r);
      }

      await tester.tapAt(at(1)); // "Дивлюсь", 21: a drop
      await tester.tapAt(at(4)); // "Відкладено", 18
      await tester.tapAt(origin + Offset(donut.size / 2, donut.size / 2));
      await tester.tap(find.text('Кинуто'));
      await tester.pump();
      expect(tapped, [HikkaWatchStatus.watching, HikkaWatchStatus.onHold, null, HikkaWatchStatus.dropped]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('аватар профілю: кільце навколо слідує за налаштуванням заокруглення (без заокруглення — квадрат)', (tester) async {
      final old = uiTheme.radiusKey;
      addTearDown(() => uiTheme.setRadiusKey(old));
      uiTheme.setRadiusKey(UiThemeService.radiusMultipliers.entries.firstWhere((e) => e.value == 0).key);
      signIn();
      await openTab(tester, MainTab.profile);
      await load(tester, rounds: 10);
      final ring = tester.widget<Container>(find.byWidgetPredicate(
        (w) => w is Container && w.decoration is BoxDecoration && (w.decoration! as BoxDecoration).color == uiTheme.bgPrimary && w.padding != null,
      ).first);
      final deco = ring.decoration! as BoxDecoration;
      expect(deco.shape, BoxShape.rectangle);
      expect((deco.borderRadius! as BorderRadius).topLeft, Radius.zero);
      await shot(tester, 'profile_avatar_square');
      expect(tester.takeException(), isNull);
    });

    testWidgets('повернення з налаштувань (рядок «Назад» зникає): вміст вкладки не підстрибує', (tester) async {
      setScreen(tester, kNarrow);
      AppPlatform.debugMobile = true;
      addTearDown(() => AppPlatform.debugMobile = null);
      signIn();
      await openTab(tester, MainTab.profile, size: kNarrow);
      await load(tester, rounds: 10);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -700));
      await load(tester, rounds: 6);
      final before = tester.getTopLeft(find.text('Історія')).dy;
      final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first).position.pixels;
      HikkaNav.instance.openSettings();
      await load(tester, rounds: 10);
      HikkaNav.instance.back();
      final trace = <String>[];
      for (int i = 0; i < 16; i++) {
        await tester.pump(const Duration(milliseconds: 40));
        final f = find.text('Улюблені аніме');
        final h = find.text('Профіль');
        final g = find.text('Улюблені персонажі');
        trace.add('${f.evaluate().isEmpty ? '-' : tester.getTopLeft(f.first).dy.toStringAsFixed(0)}/${h.evaluate().isEmpty ? '-' : tester.getTopLeft(h.first).dy.toStringAsFixed(0)}');
      }
      // ignore: avoid_print
      print('before=$before scroll=$scroll trace=$trace');
      await load(tester, rounds: 6);
      final after = tester.getTopLeft(find.text('Історія')).dy;
      expect(after, closeTo(before, 1));
    });

    testWidgets('телефон: профіль без переповнень', (tester) async {
      setScreen(tester, kNarrow);
      AppPlatform.debugMobile = true;
      addTearDown(() => AppPlatform.debugMobile = null);
      signIn();
      await openTab(tester, MainTab.profile, size: kNarrow);
      await load(tester, rounds: 10);
      expect(find.text('tester'), findsOneWidget);
      expect(find.byType(HikkaActivityHeatmap), findsOneWidget);
      await shot(tester, 'profile_signed_in_narrow');
      await tester.scrollUntilVisible(find.text('Улюблені аніме'), 300, scrollable: find.byType(Scrollable).first);
      await load(tester, rounds: 4);
      await shot(tester, 'profile_favourites_narrow');
      await tester.scrollUntilVisible(find.text('Історія'), 300, scrollable: find.byType(Scrollable).first);
      await load(tester, rounds: 4);
      await shot(tester, 'profile_history_narrow');
      expect(tester.takeException(), isNull);
    });

    testWidgets('профіль іншого користувача: автор статті веде на його сторінку', (tester) async {
      await openTab(tester, MainTab.home);
      HikkaNav.instance.openUser('other');
      await load(tester, rounds: 10);
      expect(find.text('Користувач'), findsOneWidget);
      expect(find.text('@other'), findsOneWidget);
      expect(find.text('other'), findsOneWidget);
      expect(find.text('Модератор'), findsNothing);
      expect(find.text('Час перегляду'), findsOneWidget);
      // Other users' status counters are not clickable
      await tester.tap(find.descendant(of: find.byType(HikkaWatchSummary), matching: find.text('Дивлюсь')));
      await load(tester, rounds: 3);
      expect(HikkaNav.instance.main, MainTab.home);
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
      expect(find.text('Серії…'), findsOneWidget, reason: 'випадне меню, а не вікно');
      expect(find.text('Видалити зі списку'), findsNothing, reason: 'запису ще немає');
      await tester.tap(find.text('Дивлюсь'));
      await load(tester, rounds: 10);

      expect(account.mine[frieren]?['status'], 'watching');
      expect(find.text('Дивлюсь'), findsOneWidget, reason: 'тепер на сторінці плитка зі статусом');
      expect(find.textContaining('серій'), findsNothing, reason: 'кількість серій на кнопці статусу не показуємо');
      await shot(tester, 'anime_my_list_watching_desktop');

      // Heart
      await tester.tap(find.byTooltip('В улюблене'));
      await load(tester, rounds: 6);
      expect(account.favourites, contains(frieren));
      expect(find.byTooltip('Прибрати з улюбленого'), findsOneWidget);

      // The score badge has its own menu and does not open the status one
      await tester.tap(find.text('Оцінити'));
      await load(tester, rounds: 10);
      expect(find.text('Видалити зі списку'), findsNothing, reason: 'меню оцінки не змішане зі статусами');
      expect(find.text('Серії…'), findsNothing);
      await tester.tap(find.text('8'));
      await load(tester, rounds: 10);
      expect(account.mine[frieren]?['score'], 8);
      expect(account.mine[frieren]?['status'], 'watching', reason: 'оцінка не чіпає статус');

      // Change: "Переглянуто" tops up the counter to the end, score 9
      await tester.tap(find.text('Дивлюсь'));
      await load(tester, rounds: 12);
      await tester.tap(find.text('Серії…'));
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

      // Remove
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
