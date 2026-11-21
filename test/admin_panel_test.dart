import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miki_miki/services/admin_api.dart';
import 'package:miki_miki/services/backend_client.dart';
import 'package:miki_miki/services/hikka_api.dart';
import 'package:miki_miki/services/hikka_auth.dart';
import 'package:miki_miki/services/hikka_nav.dart';
import 'package:miki_miki/utils/app_clock.dart';
import 'package:miki_miki/widgets/hikka/hikka_admin_page.dart';

import 'support/hikka_account_fakes.dart';

/// The backend's `admin` function: who asks (by the Hikka token), how many devices, sending and the log
class FakeAdminServer {
  String username = 'ZEDDY';
  int devices = 12;
  int followers = 3;

  /// Every answer with this status (403 — not an admin, 404 — the function is not deployed)
  int? forced;
  String forcedError = 'not_admin';

  final List<Map<String, dynamic>> requests = [];
  final List<String?> tokens = [];
  final List<Map<String, dynamic>> log = [];

  BackendClient client() {
    final store = <String, dynamic>{};
    return BackendClient(
      load: () => store,
      save: (d) => store
        ..clear()
        ..addAll(d),
      fallbackBase: null,
      transport: (method, url, headers, body) async {
        final name = Uri.parse(url).path.split('/').last;
        if (name == 'session') {
          return (200, jsonEncode({'session': 'a' * 48, 'expires': DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch}));
        }
        if (name != 'admin') return (404, '{}');
        tokens.add(headers['x-hikka-auth']);
        final b = jsonDecode(body!) as Map<String, dynamic>;
        requests.add(b);
        final f = forced;
        if (f != null) return (f, jsonEncode({'error': forcedError}));
        switch (b['action']) {
          case 'whoami':
            return (200, jsonEncode({'admin': true, 'username': username, 'devices': devices}));
          case 'push.count':
            return (200, jsonEncode({'devices': b['target'] == 'all' ? devices : followers}));
          case 'push.send':
            final n = b['target'] == 'all' ? devices : followers;
            log.insert(0, {
              ...b,
              'at': DateTime(2026, 11, 4, 11, 30).millisecondsSinceEpoch,
              'by': username,
              'devices': n,
              'sent': n - 1,
              'failed': 1,
            });
            return (200, jsonEncode({'devices': n, 'sent': n - 1, 'failed': 1}));
          case 'push.history':
            return (200, jsonEncode({'items': log}));
        }
        return (400, jsonEncode({'error': 'bad_action'}));
      },
    );
  }
}

HikkaAuth signedIn(String username) => HikkaAuth(
      api: HikkaApi(sender: (r) async => HikkaResponse(404, '{}'), retryDelay: Duration.zero),
      load: () => {'token': 'tok-admin', 'me': {...kMe, 'username': username}},
      save: (_) {},
      loopbackFactory: () async => null,
    );

void main() {
  setUp(() => AppClock.now = () => DateTime(2026, 11, 4, 12));
  tearDown(() => AppClock.now = DateTime.now);

  test('панель бачить лише ZEDDY (без огляду на регістр) і лише після входу', () {
    expect(AdminApi.isAdminName('ZEDDY'), isTrue);
    expect(AdminApi.isAdminName(' zeddy '), isTrue);
    expect(AdminApi.isAdminName('tester'), isFalse);
    expect(AdminApi(auth: () => signedIn('ZEDDY')).visible, isTrue);
    expect(AdminApi(auth: () => signedIn('tester')).visible, isFalse);
    final guest = HikkaAuth(api: HikkaApi(sender: (r) async => HikkaResponse(404, '{}')), load: () => {}, save: (_) {});
    expect(AdminApi(auth: () => guest).visible, isFalse);
  });

  test('тайтл: slug або посилання hikka.io', () {
    expect(AdminApi.slugOf('sousou-no-frieren-ad4e3e'), 'sousou-no-frieren-ad4e3e');
    expect(AdminApi.slugOf(' https://hikka.io/anime/sousou-no-frieren-ad4e3e?tab=1 '), 'sousou-no-frieren-ad4e3e');
    expect(AdminApi.slugOf('a b'), isNull);
    expect(AdminApi.slugOf('../etc'), isNull, reason: 'крапка й дефіс дозволені, але не слеш');
    expect(AdminApi.slugOf(''), isNull);
  });

  test('що йде на сервер: оновлення без тайтла, «кому» за тайтлом', () {
    const update = AdminPush(type: AdminPushType.update, title: ' Вийшла 1.2 ', body: 'Тисніть', slug: 'x');
    expect(update.toJson(), {'type': 'update', 'title': 'Вийшла 1.2', 'body': 'Тисніть', 'target': 'all'});
    const news = AdminPush(type: AdminPushType.news, title: 'T', body: 'B', slug: 'frieren', audienceSlug: 'frieren', image: 'https://i/p.jpg');
    expect(news.toJson(), {'type': 'news', 'title': 'T', 'body': 'B', 'target': 'slug:frieren', 'slug': 'frieren', 'image': 'https://i/p.jpg'});
  });

  test('відповіді сервера — словами; токен Hikka йде в заголовку', () async {
    final server = FakeAdminServer();
    final api = AdminApi(backend: server.client, auth: () => signedIn('ZEDDY'));
    expect(await api.whoami(), ('ZEDDY', 12));
    expect(server.tokens.single, 'tok-admin');
    expect(await api.count(audienceSlug: 'frieren'), 3);
    expect(server.requests.last, {'action': 'push.count', 'target': 'slug:frieren'});

    server.forced = 403;
    await expectLater(api.whoami(), throwsA(isA<AdminException>().having((e) => e.message, 'message', contains('не має доступу'))));
    server.forced = 404;
    await expectLater(api.whoami(), throwsA(isA<AdminException>().having((e) => e.message, 'message', contains('admin.ts'))));
    expect(AdminApi.describe(400, 'slug_required'), contains('Нової серії'));
    expect(AdminApi.describe(429, null), contains('Зачекайте'));

    final guest = AdminApi(backend: server.client, auth: () => HikkaAuth(api: HikkaApi(sender: (r) async => HikkaResponse(404, '{}')), load: () => {}, save: (_) {}));
    await expectLater(guest.whoami(), throwsA(isA<AdminException>().having((e) => e.message, 'message', contains('Увійдіть'))));
  });

  Future<FakeAdminServer> open(WidgetTester t, {FakeAdminServer? server}) async {
    final s = server ?? FakeAdminServer();
    final api = AdminApi(backend: s.client, auth: () => signedIn('ZEDDY'));
    t.view.physicalSize = const Size(900, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      home: Scaffold(body: HikkaAdminPage(route: HikkaRoute(HikkaRouteKind.admin, 'admin'), scale: 1, api: api)),
    ));
    await t.pumpAndSettle();
    return s;
  }

  testWidgets('надсилання: перевірки, підтвердження, результат і журнал', (t) async {
    final server = await open(t);
    expect(find.textContaining('сповіщення отримують 12 пристроїв'), findsOneWidget);
    expect(find.text('Ще нічого не надсилали з панелі.'), findsOneWidget);

    // Empty form: nothing goes out, the reason is shown
    await t.tap(find.byKey(const ValueKey('admin-send')));
    await t.pumpAndSettle();
    expect(find.text('Напишіть заголовок.'), findsOneWidget);
    expect(server.requests.where((r) => r['action'] == 'push.send'), isEmpty);

    await t.enterText(find.descendant(of: find.byKey(const ValueKey('admin-title')), matching: find.byType(TextField)), 'Вийшла 1.2');
    await t.enterText(find.descendant(of: find.byKey(const ValueKey('admin-body')), matching: find.byType(TextField)), 'Нові списки й швидші сторінки');
    await t.pump();
    // The preview follows the text; the counter shows the length
    expect(find.descendant(of: find.byKey(const ValueKey('admin-preview')), matching: find.text('Вийшла 1.2')), findsOneWidget);
    expect(find.text('10/120'), findsOneWidget);

    // A title for the followers only
    await t.enterText(find.descendant(of: find.byKey(const ValueKey('admin-slug')), matching: find.byType(TextField)), 'https://hikka.io/anime/sousou-no-frieren-ad4e3e');
    await t.pump();
    expect(find.text('Дотик відкриє тайтл sousou-no-frieren-ad4e3e'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('admin-to-followers')));
    await t.pump();

    await t.tap(find.byKey(const ValueKey('admin-send')));
    await t.pumpAndSettle();
    expect(find.text('Надіслати сповіщення?'), findsOneWidget);
    expect(find.textContaining('отримають 3 пристрої'), findsOneWidget);
    await t.tap(find.text('Надіслати').last);
    await t.pumpAndSettle();

    final sent = server.requests.lastWhere((r) => r['action'] == 'push.send');
    expect(sent, {
      'action': 'push.send',
      'type': 'news',
      'title': 'Вийшла 1.2',
      'body': 'Нові списки й швидші сторінки',
      'target': 'slug:sousou-no-frieren-ad4e3e',
      'slug': 'sousou-no-frieren-ad4e3e',
    });
    expect(find.textContaining('Надіслано: 2 з 3'), findsOneWidget);
    // The text is cleared so it does not go twice; the log shows the send
    expect(find.text('0/120'), findsOneWidget);
    expect(find.textContaining('Новина · хто стежить за sousou-no-frieren-ad4e3e · отримали 2 з 3 · 4 листопада, 11:30'), findsOneWidget);
  });

  testWidgets('оновлення: без поля тайтла; «Нова серія» вимагає тайтл', (t) async {
    await open(t);
    await t.tap(find.byKey(const ValueKey('admin-type-update')));
    await t.pump();
    expect(find.byKey(const ValueKey('admin-slug')), findsNothing);
    expect(find.text('Дотик відкриє вікно оновлення'), findsOneWidget);

    await t.tap(find.byKey(const ValueKey('admin-type-episode')));
    await t.pump();
    await t.enterText(find.descendant(of: find.byKey(const ValueKey('admin-title')), matching: find.byType(TextField)), 'Тест');
    await t.enterText(find.descendant(of: find.byKey(const ValueKey('admin-body')), matching: find.byType(TextField)), 'Серія 5');
    await t.tap(find.byKey(const ValueKey('admin-send')));
    await t.pumpAndSettle();
    expect(find.textContaining('потрібен тайтл'), findsOneWidget);
  });

  testWidgets('чужий акаунт: лише пояснення, без форми', (t) async {
    await open(t, server: FakeAdminServer()..forced = 403);
    expect(find.text('Цей акаунт Hikka не має доступу до адмін-панелі.'), findsOneWidget);
    expect(find.byKey(const ValueKey('admin-send')), findsNothing);
    expect(find.text('Спробувати ще'), findsOneWidget);
  });
}
