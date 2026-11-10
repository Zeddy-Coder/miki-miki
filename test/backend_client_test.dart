import 'package:flutter_test/flutter_test.dart';
import 'package:miki_miki/services/backend_client.dart';
import 'package:miki_miki/services/source_prefs.dart';

import 'support/hikka_account_fakes.dart';

void main() {
  backendFallbackTests();
  late FakeBackend fake;
  late Map<String, dynamic> store;
  late BackendClient client;

  setUp(() {
    fake = FakeBackend();
    store = {};
    client = fake.client(store: store);
  });

  test('сесія створюється один раз і зберігається; одночасні виклики ділять один запит', () async {
    final a = await Future.wait([client.ensureSession(), client.ensureSession()]);
    expect(a[0], a[1]);
    expect(fake.calls, ['POST session']);
    await client.ensureSession();
    expect(fake.calls, ['POST session'], reason: 'діюча сесія не оновлюється');
    expect(store['session'], isNotEmpty);
  });

  test('сесія зі сховища використовується після перезапуску', () async {
    await client.ensureSession();
    final again = fake.client(store: store);
    await again.ensureSession();
    expect(fake.calls.where((c) => c == 'POST session'), hasLength(1));
  });

  test('обмін коду Hikka: надсилається лише код і сесія, повертається відповідь сервера', () async {
    final (status, body) = await client.hikkaToken('ref-12345678');
    expect(status, 200);
    expect(body['secret'], 'tok-ui');
    expect(fake.exchanges.single, {'request_reference': 'ref-12345678'});
    expect(fake.sessions.single, 'a' * 48);
  });

  test('сесію не створено: помилка бекенду', () async {
    fake.sessionStatus = 500;
    await expectLater(client.hikkaToken('ref-12345678'), throwsA(isA<BackendException>()));
  });

  test('ключ Moon: завантажується й запамʼятовується; при збої лишається збережений', () async {
    expect(client.cachedMoonKey, isEmpty);
    fake.moonKey = 'server-key';
    expect(await client.refreshMoonKey(), 'server-key');
    expect(store['moon_key'], 'server-key');
    fake.configStatus = 500;
    expect(await client.refreshMoonKey(), 'server-key', reason: 'збій бекенду ключ не стирає');
  });

  test('ключ для Moon: власний > з бекенду; вбудованого немає', () async {
    BackendClient.instance = client;
    final prefs = SourcePrefs.instance;
    final own = prefs.moonKey;
    addTearDown(() => prefs.moonKey = own);
    prefs.moonKey = '';
    expect(prefs.effectiveMoonKey, isEmpty);
    fake.moonKey = 'server-key';
    await client.refreshMoonKey();
    expect(prefs.effectiveMoonKey, 'server-key');
    prefs.moonKey = 'my-key';
    expect(prefs.effectiveMoonKey, 'my-key');
  });
}

void backendFallbackTests() {
  test('основна адреса не резолвиться — запит іде через запасну й запамʼятовується', () async {
    final calls = <String>[];
    final store = <String, dynamic>{};
    final c = BackendClient(
      load: () => store,
      save: (d) => store..clear()..addAll(d),
      transport: (method, url, headers, body) async {
        calls.add(url);
        if (url.contains('cloudfunctions.net')) throw const BackendException('немає зʼєднання з бекендом: Failed host lookup');
        if (url.endsWith('/session')) return (200, '{"session":"${'a' * 48}","expires":${DateTime.now().millisecondsSinceEpoch + 30 * 24 * 3600 * 1000}}');
        return (200, '{"moonKey":"k"}');
      },
    );
    expect(await c.refreshMoonKey(), 'k');
    expect(calls.first, contains('cloudfunctions.net/session'));
    expect(calls.any((u) => u.startsWith('https://miki-miki-729d9.web.app/api/session')), isTrue);
    calls.clear();
    await c.refreshMoonKey();
    expect(calls.every((u) => u.contains('web.app')), isTrue, reason: 'далі одразу запасна адреса, без повторних невдач');
  });

  test('відповідь сервера (навіть помилка) запасну адресу не вмикає', () async {
    var n = 0;
    final c = BackendClient(
      load: () => {},
      save: (_) {},
      transport: (method, url, headers, body) async {
        n++;
        return (500, '{}');
      },
    );
    await expectLater(c.ensureSession(), throwsA(isA<BackendException>()));
    expect(n, 1);
  });
}
