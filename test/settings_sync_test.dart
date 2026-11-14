import 'package:flutter_test/flutter_test.dart';
import 'package:miki_miki/services/backend_client.dart';
import 'package:miki_miki/services/settings_sync.dart';

class _MemStore implements SyncStore {
  final Map<String, Object?> values = {};
  Map<String, dynamic> state = {};

  @override
  Object? read(String key) => values[key];
  @override
  void write(String key, Object? value) => value == null ? values.remove(key) : values[key] = value;
  @override
  Iterable<String> dynamicKeys() => values.keys.where((k) => k.startsWith('pos:'));
  @override
  Map<String, dynamic> loadState() => state;
  @override
  void saveState(Map<String, dynamic> s) => state = s;
}

/// A fake server shared by several "devices"
class _Server {
  Map<String, dynamic> data = {};
  int puts = 0;
  int gets = 0;
  int? failWith;
}

class _FakeBackend extends BackendClient {
  final _Server server;
  _FakeBackend(this.server) : super(load: () => {}, save: (_) {}, transport: (m, u, h, b) async => (500, ''));

  @override
  Future<(int, Map<String, dynamic>)> syncGet(String hikkaToken) async {
    server.gets++;
    if (server.failWith != null) return (server.failWith!, <String, dynamic>{});
    return (200, <String, dynamic>{'updated': 1, 'data': Map<String, dynamic>.of(server.data)});
  }

  @override
  Future<(int, Map<String, dynamic>)> syncPut(String hikkaToken, Map<String, dynamic> data) async {
    server.puts++;
    server.data = Map<String, dynamic>.of(data);
    return (200, <String, dynamic>{'updated': 2});
  }
}

void main() {
  late _Server server;
  var clock = 1000;
  int applied = 0;

  SettingsSync device(_MemStore store, {String token = 'tok'}) =>
      SettingsSync(store: store, backend: () => _FakeBackend(server), token: () => token, now: () => clock, onApplied: () => applied++);

  setUp(() {
    server = _Server();
    clock = 1000;
    applied = 0;
  });

  test('first device uploads its explicit settings', () async {
    final pc = _MemStore()..values['theme_mode'] = 'dark';
    final out = await device(pc).sync();
    expect(out.ok, true);
    expect(server.data['theme_mode'], {'v': 'dark', 't': 1});
  });

  test('a fresh phone takes the account settings instead of overwriting them with defaults', () async {
    final pc = _MemStore()..values['theme_mode'] = 'dark';
    await device(pc).sync();
    final phone = _MemStore()..values['accent_color'] = '#112233'; // touched once before the account existed
    final out = await device(phone).sync();
    expect(phone.values['theme_mode'], 'dark');
    expect(out.applied, 1);
    expect(applied, 1);
    expect(server.data['accent_color'], {'v': '#112233', 't': 1}); // a key the server lacked is sent
  });

  test('a later local change wins and reaches the other device', () async {
    final pc = _MemStore()..values['theme_mode'] = 'dark';
    final pcSync = device(pc);
    await pcSync.sync();
    final phone = _MemStore();
    final phoneSync = device(phone);
    await phoneSync.sync();
    clock += 5000;
    phone.values['theme_mode'] = 'light';
    await phoneSync.sync();
    expect(server.data['theme_mode'], {'v': 'light', 't': 6000});
    clock += 5000;
    await pcSync.sync();
    expect(pc.values['theme_mode'], 'light');
  });

  test('older local change does not beat a newer remote one', () async {
    final pc = _MemStore()..values['seek_step'] = 10;
    final pcSync = device(pc);
    await pcSync.sync();
    final phone = _MemStore();
    final phoneSync = device(phone);
    await phoneSync.sync();
    clock += 1000;
    pc.values['seek_step'] = 5; // PC changes first (t = 2000)
    clock += 5000;
    phone.values['seek_step'] = 30; // phone later (t = 7000)
    await phoneSync.sync();
    await pcSync.sync();
    expect(pc.values['seek_step'], 30);
    expect(server.data['seek_step']['v'], 30);
  });

  test('removed position is a removal on the other device', () async {
    final pc = _MemStore()..values['pos:hikka:a#1'] = 1000;
    final pcSync = device(pc);
    await pcSync.sync();
    final phone = _MemStore();
    final phoneSync = device(phone);
    await phoneSync.sync();
    expect(phone.values['pos:hikka:a#1'], 1000);
    clock += 1000;
    phone.values.remove('pos:hikka:a#1'); // episode finished on the phone
    await phoneSync.sync();
    clock += 1000;
    await pcSync.sync();
    expect(pc.values.containsKey('pos:hikka:a#1'), false);
  });

  test('auto run without changes and with a recent contact does not touch the network', () async {
    final pc = _MemStore()..values['theme_mode'] = 'dark';
    final s = device(pc);
    await s.sync();
    final gets = server.gets;
    clock += 1000;
    await s.sync(auto: true);
    expect(server.gets, gets);
    pc.values['theme_mode'] = 'light';
    await s.sync(auto: true);
    expect(server.gets, gets + 1);
  });

  test('signed out, switched off or server error: nothing breaks and nothing is lost', () async {
    final pc = _MemStore()..values['theme_mode'] = 'dark';
    expect((await device(pc, token: '').sync()).ok, true);
    expect(server.gets, 0);
    final s = device(pc);
    server.failWith = 503;
    final out = await s.sync();
    expect(out.ok, false);
    server.failWith = null;
    await s.sync();
    expect(server.data['theme_mode']['v'], 'dark');
    s.enabled = false;
    await s.sync();
    expect(s.enabled, false);
  });
}
