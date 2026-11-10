import 'dart:convert';

import 'package:miki_miki/services/backend_client.dart';
import 'package:miki_miki/services/hikka_api.dart';

/// Підставний сервер для акаунта Hikka: відповіді задаються за «МЕТОД /шлях», усі запити пишуться в журнал.
class FakeAccountApi {
  final List<HikkaRequest> log = [];
  final Map<String, HikkaResponse Function(HikkaRequest r)> routes = {};

  Future<HikkaResponse> call(HikkaRequest r) async {
    log.add(r);
    final h = routes['${r.method} ${r.url.path}'];
    if (h != null) return h(r);
    return fail(404, 'system:not_found');
  }

  static HikkaResponse ok(Object? body) => HikkaResponse(200, jsonEncode(body));

  static HikkaResponse fail(int status, String code) => HikkaResponse(status, jsonEncode({'code': code, 'message': code}));

  /// Запити за методом і шляхом
  List<HikkaRequest> of(String method, String path) => [
        for (final r in log)
          if (r.method == method && r.url.path == path) r,
      ];

  Map<String, dynamic> bodyOf(HikkaRequest r) => jsonDecode(r.body!) as Map<String, dynamic>;
}

const Map<String, dynamic> kMe = {
  'reference': '94e69306-fd6e-4267-b38b-6e5372918ad3',
  'username': 'tester',
  'avatar': 'https://cdn.hikka.io/uploads/tester/avatar/a.jpg',
  'role': 'user',
  'email': 'tester@example.com',
  'active': true,
  'created': 1,
  'links': [],
};

const String kRequestRef = '3f9a4b1e-7c2d-4e55-9a10-0b6d8c2f1a77';

/// Підроблений бекенд застосунку: сесія, обмін коду Hikka на токен і ключ Moon
class FakeBackend {
  final List<String> calls = [];
  final List<Map<String, dynamic>> exchanges = [];
  final List<String?> sessions = [];
  String moonKey = '';
  int configStatus = 200;
  int sessionStatus = 200;

  /// Що відповість бекенд на обмін коду (за замовчуванням — токен `tok-ui`)
  Future<(int, Map<String, dynamic>)> Function(String ref) onExchange =
      (ref) async => (200, <String, dynamic>{'secret': 'tok-ui', 'created': 1, 'expiration': 2});

  BackendClient client({Map<String, dynamic>? store}) {
    final data = store ?? <String, dynamic>{};
    return BackendClient(
      load: () => data,
      save: (d) {
        if (!identical(d, data)) {
          data
            ..clear()
            ..addAll(d);
        }
      },
      transport: (method, url, headers, body) async {
        final name = Uri.parse(url).path.split('/').last;
        calls.add('$method $name');
        if (name == 'session') {
          if (sessionStatus != 200) return (sessionStatus, '{}');
          return (200, jsonEncode({'session': 'a' * 48, 'expires': DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch}));
        }
        sessions.add(headers['x-session']);
        if (name == 'hikkaToken') {
          final b = jsonDecode(body!) as Map<String, dynamic>;
          exchanges.add(b);
          final (status, j) = await onExchange(b['request_reference'] as String);
          return (status, jsonEncode(j));
        }
        if (name == 'config') return (configStatus, jsonEncode({'moonKey': moonKey}));
        return (404, '{}');
      },
    );
  }
}
