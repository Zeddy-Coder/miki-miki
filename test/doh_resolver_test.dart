import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:miki_miki/services/backend_client.dart';
import 'package:miki_miki/services/doh_resolver.dart';

void main() {
  tearDown(() => DohResolver.debugFetch = null);

  test('розбір відповіді DoH: лише A-записи з коректними IP', () {
    final body = jsonEncode({
      'Answer': [
        {'type': 5, 'data': 'alias.example.'},
        {'type': 1, 'data': '142.250.1.1'},
        {'type': 1, 'data': 'не-ip'},
      ]
    });
    expect(DohResolver.parse(body), ['142.250.1.1']);
    expect(DohResolver.parse('{}'), isEmpty);
    expect(DohResolver.parse('сміття'), isEmpty);
  });

  test('перший провайдер мовчить — відповідь беруть від іншого, результат кешується', () async {
    var calls = <String>[];
    DohResolver.debugFetch = (ip, path, host) async {
      calls.add(ip);
      if (ip == '1.1.1.1') throw const SocketException('недоступний');
      return jsonEncode({'Answer': [{'type': 1, 'data': '10.1.2.3'}]});
    };
    expect(await DohResolver.resolve('cache-test.example'), ['10.1.2.3']);
    expect(calls, contains('1.1.1.1'));
    expect(calls.length, greaterThan(1), reason: 'провайдери опитуються одночасно');
    calls = [];
    expect(await DohResolver.resolve('cache-test.example'), ['10.1.2.3']);
    expect(calls, isEmpty, reason: 'з кешу');
  });

  test('бекенд: хост не резолвиться системним DNS — з\'єднання за IP із DoH', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((req) async {
      req.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'host': req.headers.host, 'path': req.uri.path}));
      await req.response.close();
    });
    DohResolver.debugFetch = (ip, path, host) async => jsonEncode({'Answer': [{'type': 1, 'data': '127.0.0.1'}]});

    final c = BackendClient(load: () => {}, save: (_) {}, base: 'http://no-such-host.invalid:${server.port}', fallbackBase: null);
    final (status, text) = await c.debugGet('ping');
    expect(status, 200);
    expect(jsonDecode(text)['path'], '/ping');
    expect(jsonDecode(text)['host'], 'no-such-host.invalid', reason: 'запит іде під справжнім іменем хоста');
  });
}
