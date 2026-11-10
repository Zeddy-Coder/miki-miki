import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:miki_miki/services/backend_client.dart';
import 'package:miki_miki/services/hikka_api.dart';
import 'package:miki_miki/services/hikka_auth.dart';
import 'package:miki_miki/services/hikka_client_key.dart';

import 'support/hikka_account_fakes.dart';

/// Сирий HTTP-запит до локального сервера входу (без HttpClient: у тестах він підмінений)
Future<String> rawGet(int port, String path, {String? host}) async {
  final s = await Socket.connect(InternetAddress.loopbackIPv4, port);
  s.write('GET $path HTTP/1.1\r\nHost: ${host ?? '127.0.0.1:$port'}\r\nConnection: close\r\n\r\n');
  await s.flush();
  final bytes = await s.fold<List<int>>([], (a, b) => a..addAll(b));
  s.destroy();
  return utf8.decode(bytes, allowMalformed: true);
}

Future<void> until(bool Function() test, {int ms = 3000}) async {
  final end = DateTime.now().add(Duration(milliseconds: ms));
  while (!test()) {
    if (DateTime.now().isAfter(end)) fail('не дочекались умови');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  late FakeAccountApi server;
  late Map<String, dynamic> store;
  late List<String> opened;
  HikkaLoopback? loop;

  late FakeBackend backend;

  setUp(() {
    server = FakeAccountApi();
    backend = FakeBackend();
    BackendClient.instance = backend.client();
    backend.onExchange = (ref) async {
      try {
        final t = await HikkaApi(sender: server.call, retryDelay: Duration.zero).exchangeToken(ref, 'client-secret-1');
        return (200, <String, dynamic>{'secret': t.secret, 'created': t.created, 'expiration': t.expiration});
      } on HikkaException catch (e) {
        return (e.status ?? 500, <String, dynamic>{'code': e.code});
      }
    };
    store = {};
    opened = [];
    loop = null;
    HikkaClientKey.testReference = 'client-ref-1';
  });

  tearDown(() async {
    HikkaClientKey.testReference = null;
    await loop?.close();
  });

  HikkaAuth makeAuth({
    Future<HikkaLoopback?> Function()? loopback,
    Duration timeout = const Duration(minutes: 5),
    Map<String, dynamic>? initial,
  }) {
    if (initial != null) store.addAll(initial);
    return HikkaAuth(
      api: HikkaApi(sender: server.call, retryDelay: Duration.zero),
      load: () => store,
      save: (d) => store = Map<String, dynamic>.of(d),
      urlOpener: (u) async {
        opened.add(u);
        return true;
      },
      loopbackFactory: loopback ?? () async => loop = await HikkaLoopback.start(port: 0),
      loginTimeout: timeout,
    );
  }

  void serveLogin({String token = 'tok-123'}) {
    server.routes['POST /auth/token'] = (r) => FakeAccountApi.ok({'secret': token, 'created': 1, 'expiration': 2});
    server.routes['GET /user/me'] = (r) => FakeAccountApi.ok(kMe);
  }

  group('розбір коду входу', () {
    test('з адреси переспрямування, з кодуванням, без схеми, голий код', () {
      expect(HikkaAuth.parseReference('http://127.0.0.1:47615/auth/confirm?reference=$kRequestRef'), kRequestRef);
      expect(HikkaAuth.parseReference('  http://127.0.0.1:47615/auth/confirm?x=1&reference=$kRequestRef&y=2  '), kRequestRef);
      expect(HikkaAuth.parseReference('127.0.0.1:47615/auth/confirm?reference=$kRequestRef'), kRequestRef);
      expect(HikkaAuth.parseReference('hikka://auth?request_reference=$kRequestRef'), kRequestRef);
      expect(HikkaAuth.parseReference(kRequestRef), kRequestRef);
      expect(HikkaAuth.parseReference('ось мій код: $kRequestRef, дякую'), kRequestRef);
    });

    test('нічого схожого — null', () {
      expect(HikkaAuth.parseReference(''), isNull);
      expect(HikkaAuth.parseReference('   '), isNull);
      expect(HikkaAuth.parseReference('нісенітниця без коду'), isNull);
      expect(HikkaAuth.parseReference('http://127.0.0.1:47615/auth/confirm'), isNull);
    });

    test('адреса сторінки дозволу: клієнт і права', () {
      final auth = makeAuth();
      expect(auth.authorizeUrl, 'https://hikka.io/oauth?reference=client-ref-1&scope=user-details,watchlist,favourite');
      expect(HikkaAuth.redirectUri, 'http://127.0.0.1:47615/auth/confirm');
    });
  });

  group('локальний сервер входу', () {
    test('чужі адреси, чужий Host і запит без коду не завершують вхід', () async {
      final l = loop = (await HikkaLoopback.start(port: 0))!;
      Future<Object?> pending() => Future.any<Object?>([l.reference, Future<Object?>.delayed(const Duration(milliseconds: 120), () => 'очікує')]);

      expect(await rawGet(l.port, '/favicon.ico'), startsWith('HTTP/1.1 404'));
      expect(await rawGet(l.port, '/auth/confirm'), startsWith('HTTP/1.1 400'));
      expect(await rawGet(l.port, '/auth/confirm?reference=$kRequestRef', host: 'evil.example'), startsWith('HTTP/1.1 404'));
      expect(await pending(), 'очікує');

      final ok = await rawGet(l.port, '/auth/confirm?reference=$kRequestRef');
      expect(ok, startsWith('HTTP/1.1 200'));
      expect(ok, contains('Готово'));
      expect(await l.reference, kRequestRef);
    });

    test('порт зайнятий — сервер не піднімається', () async {
      final a = loop = (await HikkaLoopback.start(port: 0))!;
      expect(await HikkaLoopback.start(port: a.port), isNull);
    });

    test('закриття завершує очікування значенням null', () async {
      final l = (await HikkaLoopback.start(port: 0))!;
      unawaited(l.close());
      expect(await l.reference, isNull);
    });
  });

  group('вхід', () {
    test('сайт перекидає на локальну адресу: код міняється на токен, профіль зберігається', () async {
      serveLogin();
      final auth = makeAuth();
      final done = auth.startLogin();
      await until(() => opened.isNotEmpty && loop != null);
      expect(auth.phase, HikkaAuthPhase.waiting);
      expect(auth.loopbackReady, isTrue);
      expect(opened.single, auth.authorizeUrl);

      final page = await rawGet(loop!.port, '/auth/confirm?reference=$kRequestRef');
      expect(page, startsWith('HTTP/1.1 200'));
      await done;

      expect(auth.signedIn, isTrue);
      expect(auth.phase, HikkaAuthPhase.signedIn);
      expect(auth.username, 'tester');
      expect(auth.error, isNull);
      expect(auth.loopbackReady, isFalse, reason: 'сервер входу після завершення закрито');

      final exchange = server.bodyOf(server.of('POST', '/auth/token').single);
      expect(exchange, {'request_reference': kRequestRef, 'client_secret': 'client-secret-1'}, reason: 'секрет додає бекенд');
      expect(backend.exchanges.single, {'request_reference': kRequestRef}, reason: 'застосунок секрету не надсилає');
      expect(server.of('GET', '/user/me').single.headers['auth'], 'tok-123');
      expect(store['token'], 'tok-123');
      expect((store['me'] as Map).containsKey('email'), isFalse, reason: 'пошту не зберігаємо');
    });

    test('запасний шлях: локальна адреса не піднялась, код вставили вручну', () async {
      serveLogin();
      final auth = makeAuth(loopback: () async => null);
      final done = auth.startLogin();
      await until(() => opened.isNotEmpty && auth.phase == HikkaAuthPhase.waiting);
      expect(auth.loopbackReady, isFalse);

      expect(auth.submit('нісенітниця'), isFalse);
      expect(auth.error, contains('Не знайшов'));
      expect(auth.phase, HikkaAuthPhase.waiting);

      expect(auth.submit('http://127.0.0.1:47615/auth/confirm?reference=$kRequestRef'), isTrue);
      await done;
      expect(auth.signedIn, isTrue);
      expect(auth.error, isNull);
    });

    test('вставили код, коли вхід не запущено (застосунок перезапускали): вхід завершується', () async {
      serveLogin();
      final auth = makeAuth();
      expect(auth.submit(kRequestRef), isTrue);
      await until(() => auth.signedIn);
      expect(auth.username, 'tester');
    });

    test('Hikka не прийняла запит: зрозуміле повідомлення, токена немає', () async {
      server.routes['POST /auth/token'] = (r) => FakeAccountApi.fail(400, 'auth:invalid_token_request');
      final auth = makeAuth(loopback: () async => null);
      final done = auth.startLogin();
      await until(() => auth.phase == HikkaAuthPhase.waiting && opened.isNotEmpty);
      auth.submit(kRequestRef);
      await done;
      expect(auth.signedIn, isFalse);
      expect(auth.phase, HikkaAuthPhase.signedOut);
      expect(auth.error, contains('застарів'));
      expect(auth.token, isEmpty);
    });

    test('токен отримано, але профіль не завантажився: нічого не лишається наполовину', () async {
      server.routes['POST /auth/token'] = (r) => FakeAccountApi.ok({'secret': 'tok', 'created': 1, 'expiration': 2});
      server.routes['GET /user/me'] = (r) => FakeAccountApi.fail(500, 'system:internal');
      final auth = makeAuth(loopback: () async => null);
      final done = auth.startLogin();
      await until(() => auth.phase == HikkaAuthPhase.waiting && opened.isNotEmpty);
      auth.submit(kRequestRef);
      await done;
      expect(auth.signedIn, isFalse);
      expect(auth.token, isEmpty);
      expect(store.containsKey('token'), isFalse);
      expect(auth.error, isNotNull);
    });

    test('скасування: без помилки', () async {
      final auth = makeAuth(loopback: () async => null);
      final done = auth.startLogin();
      await until(() => auth.phase == HikkaAuthPhase.waiting && opened.isNotEmpty);
      auth.cancelLogin();
      await done;
      expect(auth.phase, HikkaAuthPhase.signedOut);
      expect(auth.error, isNull);
    });

    test('сайт не відповів до кінця очікування', () async {
      final auth = makeAuth(loopback: () async => null, timeout: const Duration(milliseconds: 80));
      await auth.startLogin();
      expect(auth.phase, HikkaAuthPhase.signedOut);
      expect(auth.error, contains('Не дочекались'));
    });

    test('без клієнта вхід не починається', () async {
      HikkaClientKey.testReference = '';
      final auth = makeAuth();
      await auth.startLogin();
      expect(opened, isEmpty);
      expect(auth.error, contains('клієнта'));
    });

    test('свій клієнт має перевагу над вбудованим', () {
      final auth = makeAuth();
      auth.setCustomClient(' my-ref ', ' my-secret ');
      expect(auth.clientReference, 'my-ref');
      expect(auth.clientSecret, 'my-secret');
      expect(store['client_ref'], 'my-ref');
      auth.setCustomClient('', '');
      expect(auth.clientReference, 'client-ref-1');
      expect(store.containsKey('client_ref'), isFalse);
    });
  });

  group('сесія', () {
    final saved = {
      'token': 'tok-old',
      'me': {'reference': 'u', 'username': 'tester', 'avatar': ''},
    };

    test('збережений токен: застосунок одразу «ввійшов», запити несуть заголовок auth', () async {
      server.routes['GET /user/me'] = (r) => FakeAccountApi.ok(kMe);
      final auth = makeAuth(initial: saved);
      expect(auth.signedIn, isTrue);
      expect(auth.username, 'tester');
      await auth.refresh();
      expect(server.of('GET', '/user/me').single.headers['auth'], 'tok-old');
    });

    test('сервер відхилив токен: тихий вихід із поясненням', () async {
      server.routes['GET /watch/x'] = (r) => FakeAccountApi.fail(400, 'auth:invalid_token');
      final hikka = HikkaApi(sender: server.call, retryDelay: Duration.zero);
      store.addAll(saved);
      final auth = HikkaAuth(api: hikka, load: () => store, save: (d) => store = Map<String, dynamic>.of(d), urlOpener: (_) async => true);
      await expectLater(hikka.myWatch('x'), throwsA(isA<HikkaException>().having((e) => e.kind, 'kind', HikkaErrorKind.unauthorized)));
      expect(auth.signedIn, isFalse);
      expect(auth.error, contains('Сесія Hikka завершилась'));
      expect(store.containsKey('token'), isFalse);
    });

    test('вихід відкликає токен на сервері', () async {
      server.routes['GET /auth/token/info'] = (r) => FakeAccountApi.ok({'reference': 'tok-ref'});
      server.routes['DELETE /auth/token/tok-ref'] = (r) => FakeAccountApi.ok({'success': true});
      final auth = makeAuth(initial: saved);
      await auth.signOut();
      expect(auth.signedIn, isFalse);
      expect(server.of('DELETE', '/auth/token/tok-ref').single.headers['auth'], 'tok-old');
      expect(store.containsKey('token'), isFalse);
      expect(store.containsKey('me'), isFalse);
    });

    test('вихід працює, навіть якщо сервер недоступний', () async {
      server.routes['GET /auth/token/info'] = (r) => FakeAccountApi.fail(500, 'system:internal');
      final auth = makeAuth(initial: saved);
      await auth.signOut();
      expect(auth.signedIn, isFalse);
      expect(auth.error, isNull);
    });

    test('запит без токена не йде в мережу', () async {
      final hikka = HikkaApi(sender: server.call, retryDelay: Duration.zero);
      hikka.tokenProvider = () => null;
      await expectLater(hikka.me(), throwsA(isA<HikkaException>().having((e) => e.kind, 'kind', HikkaErrorKind.unauthorized)));
      expect(server.log, isEmpty);
    });

    test('синхронізація прогресу вмикається й зберігається', () {
      final auth = makeAuth();
      expect(auth.syncProgress, isTrue);
      auth.syncProgress = false;
      expect(store['sync'], false);
      expect(makeAuth().syncProgress, isFalse);
    });
  });
}
