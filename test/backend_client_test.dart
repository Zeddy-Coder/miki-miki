import 'package:flutter_test/flutter_test.dart';
import 'package:miki_miki/services/backend_client.dart';
import 'package:miki_miki/services/source_prefs.dart';

import 'support/hikka_account_fakes.dart';

void main() {
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
