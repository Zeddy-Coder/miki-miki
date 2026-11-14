import 'package:flutter_test/flutter_test.dart';
import 'package:miki_miki/services/backend_client.dart';
import 'package:miki_miki/services/push_notifications.dart';

class _Backend extends BackendClient {
  final List<(String, List<String>, bool)> calls = [];
  bool ok = true;
  _Backend() : super(load: () => {}, save: (_) {}, transport: (m, u, h, b) async => (500, ''));

  @override
  Future<bool> pushRegister(String fcmToken, List<String> follows, {required bool enabled}) async {
    calls.add((fcmToken, List.of(follows), enabled));
    return ok;
  }
}

void main() {
  late _Backend backend;
  late Map<String, dynamic> saved;
  var clock = 1000;
  var follows = <String>['b|2', 'a|1'];
  String? token = 'T' * 50;
  var permission = true;

  PushNotifications make({bool supported = true}) => PushNotifications(
        load: () => saved,
        save: (d) => saved = d,
        supported: () => supported,
        token: () async => token,
        permission: () async => permission,
        follows: () => List.of(follows),
        backend: () => backend,
        now: () => clock,
      );

  setUp(() {
    backend = _Backend();
    saved = {};
    clock = 1000;
    follows = ['b|2', 'a|1'];
    token = 'T' * 50;
    permission = true;
  });

  test('off by default and nothing is sent', () async {
    final p = make();
    expect(p.enabled, false);
    await p.sync();
    expect(backend.calls, isEmpty);
  });

  test('turning on asks permission, then sends the sorted followed list', () async {
    final p = make();
    await p.setEnabled(true);
    expect(p.enabled, true);
    expect(backend.calls.single.$2, ['a|1', 'b|2']);
    expect(backend.calls.single.$3, true);
  });

  test('refused permission keeps push off', () async {
    permission = false;
    final p = make();
    await p.setEnabled(true);
    expect(p.enabled, false);
    expect(p.problem, isNotNull);
    expect(backend.calls, isEmpty);
  });

  test('unchanged list is not sent again, a changed one is; stale subscription is renewed', () async {
    final p = make();
    await p.setEnabled(true);
    await p.sync();
    expect(backend.calls.length, 1);
    follows = ['a|1', 'b|2', 'c|3'];
    await p.sync();
    expect(backend.calls.length, 2);
    clock += PushNotifications.refreshEvery.inMilliseconds + 1;
    await p.sync();
    expect(backend.calls.length, 3);
  });

  test('turning off removes the subscription once', () async {
    final p = make();
    await p.setEnabled(true);
    await p.setEnabled(false);
    expect(backend.calls.last.$3, false);
    final n = backend.calls.length;
    await p.sync();
    expect(backend.calls.length, n);
  });

  test('no Firebase in the build: a clear note, no crash; server failure is retried later', () async {
    token = null;
    final p = make();
    await p.setEnabled(true);
    expect(p.problem, contains('токен'));
    token = 'T' * 50;
    backend.ok = false;
    await p.sync(force: true);
    expect(p.problem, isNotNull);
    backend.ok = true;
    await p.sync();
    expect(p.problem, isNull);
  });

  test('not Android: nothing happens', () async {
    final p = make(supported: false);
    await p.setEnabled(true);
    expect(p.enabled, false);
    expect(backend.calls, isEmpty);
  });
}
