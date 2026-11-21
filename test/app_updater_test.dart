import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miki_miki/services/app_updater.dart';

String release(String tag, {List<Map<String, Object?>> assets = const []}) => jsonEncode({
      'tag_name': tag,
      'body': 'Що нового',
      'html_url': 'https://github.com/Zeddy-Coder/miki-miki/releases/tag/$tag',
      'assets': assets,
    });

Map<String, Object?> asset(String name, [int size = 1000]) =>
    {'name': name, 'size': size, 'browser_download_url': 'https://dl/$name'};

AppUpdater make(Future<(int, String)> Function(String) t, {String v = '1.1.0', bool android = true, Map<String, dynamic>? store}) {
  final saved = store ?? <String, dynamic>{};
  return AppUpdater(transport: t, load: () => saved, save: (d) => saved..clear()..addAll(d), currentVersion: v, isAndroid: () => android);
}

void main() {
  group('завантаження', downloads);

  test('порівняння версій', () {
    expect(AppUpdater.compareVersions('1.2.0', '1.1.9') > 0, true);
    expect(AppUpdater.compareVersions('v1.10.0', '1.9.0') > 0, true);
    expect(AppUpdater.compareVersions('1.1', '1.1.0'), 0);
    expect(AppUpdater.compareVersions('1.0.9', '1.1.0') < 0, true);
    expect(AppUpdater.compareVersions('1.2.0-beta', '1.2.0'), 0);
  });

  test('вибір файлу: Android бере arm64 apk, Windows — zip', () {
    final a = [asset('notes.txt'), asset('miki_miki-v1.2.0-win.zip'), asset('miki_miki-v1.2.0-x86.apk'), asset('miki_miki-v1.2.0-arm64.apk')];
    expect(AppUpdater.pickAsset(a, android: true)!['name'], 'miki_miki-v1.2.0-arm64.apk');
    expect(AppUpdater.pickAsset(a, android: false)!['name'], 'miki_miki-v1.2.0-win.zip');
    expect(AppUpdater.pickAsset([asset('a.txt')], android: true), isNull);
  });

  test('Windows: інсталятор (Setup.exe) важливіший за архів', () {
    final a = [asset('miki_miki-v1.2.0-win.zip'), asset('miki_miki-v1.2.0-arm64.apk'), asset('MikiMiki-Setup-1.2.0.exe')];
    expect(AppUpdater.pickAsset(a, android: false)!['name'], 'MikiMiki-Setup-1.2.0.exe');
    expect(AppUpdater.pickAsset(a, android: true)!['name'], 'miki_miki-v1.2.0-arm64.apk');
  });

  test('контрольна сума з релізу GitHub зберігається', () async {
    final store = <String, dynamic>{};
    final u = make((_) async => (200, release('v1.2.0', assets: [{...asset('m-arm64.apk', 5000), 'digest': 'sha256:abc'}])), store: store);
    await u.check();
    expect((u.state.value as UpdateAvailable).info.digest, 'sha256:abc');
    expect((make((_) async => throw 'x', store: store).state.value as UpdateAvailable).info.digest, 'sha256:abc');
  });

  test('знаходить новішу версію й зберігає її', () async {
    final store = <String, dynamic>{};
    final u = make((_) async => (200, release('v1.2.0', assets: [asset('m-arm64.apk', 5000)])), store: store);
    await u.check();
    final st = u.state.value as UpdateAvailable;
    expect(st.info.version, '1.2.0');
    expect(st.info.target, 'https://dl/m-arm64.apk');
    expect(st.info.size, 5000);
    // After a restart the state is restored without the network
    final again = make((_) async => throw 'no net', store: store);
    expect(again.state.value, isA<UpdateAvailable>());
  });

  test('та сама версія — актуально; без файлу відкривається сторінка релізу', () async {
    final same = make((_) async => (200, release('v1.1.0')));
    await same.check();
    expect(same.state.value, isA<UpdateUpToDate>());
    final noAsset = make((_) async => (200, release('v1.3.0')));
    await noAsset.check();
    final info = (noAsset.state.value as UpdateAvailable).info;
    expect(info.downloadUrl, '');
    expect(info.target, contains('/releases/tag/v1.3.0'));
  });

  test('немає релізів (404) — не помилка', () async {
    final u = make((_) async => (404, '{}'));
    await u.check();
    expect(u.state.value, isA<UpdateUpToDate>());
  });

  test('помилка: ручна показує, тиха мовчить', () async {
    final manual = make((_) async => (500, ''));
    await manual.check();
    expect(manual.state.value, isA<UpdateFailed>());
    final quiet = make((_) async => (500, ''));
    await quiet.check(auto: true);
    expect(quiet.state.value, isA<UpdateIdle>());
  });

  test('тиха перевірка не частіше, ніж раз на 30 хвилин; ручна завжди', () async {
    var calls = 0;
    final store = <String, dynamic>{};
    final u = make((_) async {
      calls++;
      return (200, release('v1.1.0'));
    }, store: store);
    await u.check(auto: true);
    await u.check(auto: true);
    expect(calls, 1);
    await u.check();
    expect(calls, 2);
  });

  test('вікно оновлення: пропущену версію більше не пропонує, а новішу — так', () async {
    final store = <String, dynamic>{};
    final u = make((_) async => (200, release('v1.2.0')), store: store);
    await u.check();
    final info = (u.state.value as UpdateAvailable).info;
    expect(u.shouldPrompt(info), isTrue);
    u.skip('1.2.0');
    expect(u.shouldPrompt(info), isFalse);
    // The skip survives a restart
    expect(make((_) async => throw 'x', store: store).shouldPrompt(info), isFalse);
    expect(u.shouldPrompt(const UpdateInfo(version: '1.3.0', notes: '', pageUrl: 'p')), isTrue, reason: 'ще новіша версія знову пропонується');
    expect(u.shouldPrompt(const UpdateInfo(version: '1.1.0', notes: '', pageUrl: 'p')), isFalse, reason: 'не новіша за поточну');
  });
}

// ── Download and install ───────────────────────────────────────────────────

/// A fake server for one file: answers `Range` requests (206) or the whole file (200)
class FakeServer {
  final List<int> bytes;

  /// Breaks the body after this many bytes (once)
  int? breakAfter;

  /// Ignores `Range` and sends the whole file
  bool ignoreRange = false;

  /// Holds the body until released (to test cancelling)
  Completer<void>? hold;

  final List<int> froms = [];
  int cancels = 0;

  FakeServer(this.bytes);

  Future<UpdateFetchResponse> fetch(String url, int from) async {
    froms.add(from);
    final start = ignoreRange ? 0 : from;
    final status = from > 0 && !ignoreRange ? 206 : 200;
    final rest = bytes.sublist(start);
    final cut = breakAfter;
    breakAfter = null;
    final gate = hold;
    Stream<List<int>> body() async* {
      var sent = 0;
      for (var i = 0; i < rest.length; i += 1000) {
        if (gate != null && sent > 0) await gate.future;
        final end = i + 1000 > rest.length ? rest.length : i + 1000;
        if (cut != null && sent + (end - i) > cut) {
          yield rest.sublist(i, i + (cut - sent));
          throw const SocketException('Connection reset by peer');
        }
        yield rest.sublist(i, end);
        sent += end - i;
      }
    }

    return UpdateFetchResponse(status, rest.length, body(), () => cancels++);
  }
}

List<int> payload(int n) => List<int>.generate(n, (i) => (i * 31 + 7) % 256);

UpdateInfo fileInfo(List<int> bytes, {String version = '1.2.0', String? digest, String name = 'miki_miki-v1.2.0-arm64.apk'}) => UpdateInfo(
      version: version,
      notes: '',
      pageUrl: 'https://github.com/x/y/releases/tag/v$version',
      downloadUrl: 'https://dl/$name',
      assetName: name,
      size: bytes.length,
      digest: digest ?? 'sha256:${sha256.convert(bytes)}',
    );

void downloads() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('miki_upd'));
  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  AppUpdater updater(
    FakeServer server, {
    Map<String, dynamic>? store,
    String v = '1.1.0',
    bool android = true,
    bool windows = false,
    bool installed = true,
    Future<String> Function(String path, bool ask)? installApk,
    Future<bool> Function(String path)? runSetup,
    void Function(void Function())? onNextResume,
  }) {
    final saved = store ?? <String, dynamic>{};
    return AppUpdater(
      transport: (_) async => throw 'no',
      fetch: server.fetch,
      load: () => saved,
      save: (d) => saved
        ..clear()
        ..addAll(d),
      currentVersion: v,
      isAndroid: () => android,
      isWindows: () => windows,
      installedCopy: () => installed,
      dir: () => dir.path,
      installApk: installApk ?? (_, __) async => 'started',
      runSetup: runSetup ?? (_) async => true,
      onNextResume: onNextResume ?? (_) {},
    );
  }

  test('завантажує файл, звіряє SHA-256, а після перезапуску він лишається готовим', () async {
    final bytes = payload(4500);
    final server = FakeServer(bytes);
    final store = <String, dynamic>{};
    final u = updater(server, store: store);
    final seen = <UpdateDownload>[];
    u.download.addListener(() => seen.add(u.download.value));
    final done = u.startDownload(fileInfo(bytes));
    expect(u.download.value, isA<DownloadRunning>());
    await done;
    final ready = u.download.value as DownloadReady;
    expect(ready.version, '1.2.0');
    expect(File(ready.path).readAsBytesSync(), bytes);
    expect(File('${ready.path}.part').existsSync(), isFalse);
    expect(seen.whereType<DownloadRunning>().last.received, 4500);
    expect(server.froms, [0]);

    // Started again: nothing loads, the file is ready
    await u.startDownload(fileInfo(bytes));
    expect(server.froms, [0]);

    final again = updater(FakeServer(bytes), store: store);
    expect(again.download.value, isA<DownloadReady>());
    expect(again.readyFor('1.2.0'), isNotNull);
    expect(again.readyFor('1.3.0'), isNull);
  });

  test('обірване завантаження продовжується з того ж місця (Range)', () async {
    final bytes = payload(5000);
    final server = FakeServer(bytes)..breakAfter = 2500;
    final u = updater(server);
    await u.startDownload(fileInfo(bytes));
    final failed = u.download.value as DownloadFailed;
    expect(failed.message, contains('продовжиться'));

    await u.startDownload(fileInfo(bytes));
    expect(server.froms, [0, 2500]);
    final ready = u.download.value as DownloadReady;
    expect(File(ready.path).readAsBytesSync(), bytes);
  });

  test('сервер без Range віддає файл цілком — він пишеться заново', () async {
    final bytes = payload(3000);
    final server = FakeServer(bytes)..breakAfter = 1200;
    final u = updater(server);
    await u.startDownload(fileInfo(bytes));
    expect(u.download.value, isA<DownloadFailed>());
    server.ignoreRange = true;
    await u.startDownload(fileInfo(bytes));
    expect(server.froms, [0, 1200]);
    expect(File((u.download.value as DownloadReady).path).readAsBytesSync(), bytes);
  });

  test('чужа контрольна сума: файл відкидається', () async {
    final bytes = payload(2000);
    final u = updater(FakeServer(bytes));
    await u.startDownload(fileInfo(bytes, digest: 'sha256:${'0' * 64}'));
    final failed = u.download.value as DownloadFailed;
    expect(failed.message, contains('контрольна сума'));
    expect(dir.listSync(recursive: true).whereType<File>(), isEmpty, reason: 'пошкоджений файл видалено');
  });

  test('скасування рве зʼєднання; наступний запуск продовжує', () async {
    final bytes = payload(6000);
    final server = FakeServer(bytes)..hold = Completer<void>();
    final u = updater(server);
    final run = u.startDownload(fileInfo(bytes));
    // The first piece is written, the rest waits for the gate
    while (server.froms.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    await Future<void>.delayed(const Duration(milliseconds: 60));
    u.cancelDownload();
    expect(u.download.value, isA<DownloadIdle>());
    expect(server.cancels, greaterThan(0));
    server.hold!.complete();
    await run;
    expect(u.download.value, isA<DownloadIdle>(), reason: 'скасоване не стає ні готовим, ні помилкою');

    server.hold = null;
    await u.startDownload(fileInfo(bytes));
    expect(server.froms.last, greaterThan(0));
    expect(File((u.download.value as DownloadReady).path).readAsBytesSync(), bytes);
  });

  test('нова версія прибирає файли старої', () async {
    final old = payload(1000);
    final u = updater(FakeServer(old));
    await u.startDownload(fileInfo(old, version: '1.2.0', name: 'm-1.2.0.apk'));
    final first = (u.download.value as DownloadReady).path;
    final fresh = payload(1500);
    final u2 = updater(FakeServer(fresh));
    await u2.startDownload(fileInfo(fresh, version: '1.3.0', name: 'm-1.3.0.apk'));
    expect(File(first).existsSync(), isFalse);
    expect(File((u2.download.value as DownloadReady).path).existsSync(), isTrue);
  });

  test('після встановлення (версія вже поточна) файл видаляється', () async {
    final bytes = payload(1000);
    final store = <String, dynamic>{};
    final u = updater(FakeServer(bytes), store: store);
    await u.startDownload(fileInfo(bytes));
    final path = (u.download.value as DownloadReady).path;
    final updated = updater(FakeServer(bytes), store: store, v: '1.2.0');
    expect(updated.download.value, isA<DownloadIdle>());
    expect(File(path).existsSync(), isFalse);
    expect(store.containsKey('file'), isFalse);
  });

  test('Android: без дозволу відкриваються налаштування, а після повернення — інсталятор', () async {
    final bytes = payload(1000);
    final calls = <(String, bool)>[];
    var allowed = false;
    void Function()? resume;
    final u = updater(
      FakeServer(bytes),
      installApk: (path, ask) async {
        calls.add((path, ask));
        if (allowed) return 'started';
        return ask ? 'permission' : 'denied';
      },
      onNextResume: (cb) => resume = cb,
    );
    expect(await u.install(), UpdateInstall.unavailable, reason: 'файлу ще немає');
    await u.startDownload(fileInfo(bytes));
    final path = (u.download.value as DownloadReady).path;

    expect(await u.install(), UpdateInstall.needsPermission);
    expect((u.download.value as DownloadReady).waitingPermission, isTrue);
    expect(resume, isNotNull);

    // Came back without allowing: no second trip to the settings, a hint instead
    resume!();
    await Future<void>.delayed(Duration.zero);
    final denied = u.download.value as DownloadReady;
    expect(denied.waitingPermission, isFalse);
    expect(denied.error, contains('Дозволити з цього джерела'));

    allowed = true;
    expect(await u.install(), UpdateInstall.started);
    expect(calls, [(path, true), (path, false), (path, true)]);
    expect((u.download.value as DownloadReady).error, isNull);
  });

  test('Windows: інсталятор запускається; збій видно у вікні', () async {
    final bytes = payload(1000);
    final runs = <String>[];
    var ok = false;
    final u = updater(FakeServer(bytes), android: false, windows: true, runSetup: (p) async {
      runs.add(p);
      return ok;
    });
    final info = fileInfo(bytes, name: 'MikiMiki-Setup-1.2.0.exe');
    expect(u.canInstallInApp(info), isTrue);
    expect(u.installRestartsApp, isTrue);
    await u.startDownload(info);
    expect(await u.install(), UpdateInstall.failed);
    expect((u.download.value as DownloadReady).error, contains('Інсталятор не запустився'));
    ok = true;
    expect(await u.install(), UpdateInstall.started);
    expect(runs.length, 2);
    expect(runs.first, endsWith('MikiMiki-Setup-1.2.0.exe'));
  });

  test('що можна встановити із застосунку', () {
    final apk = fileInfo(payload(10));
    final exe = fileInfo(payload(10), name: 'MikiMiki-Setup-1.2.0.exe');
    final zip = fileInfo(payload(10), name: 'miki-win.zip');
    final android = updater(FakeServer(const []));
    final win = updater(FakeServer(const []), android: false, windows: true);
    final portable = updater(FakeServer(const []), android: false, windows: true, installed: false);
    expect(android.canInstallInApp(apk), isTrue);
    expect(android.canInstallInApp(exe), isFalse);
    expect(win.canInstallInApp(exe), isTrue);
    expect(win.canInstallInApp(zip), isFalse);
    expect(portable.canInstallInApp(exe), isFalse, reason: 'копія з теки оновлюється вручну');
    expect(android.canInstallInApp(const UpdateInfo(version: '1.2.0', notes: '', pageUrl: 'p')), isFalse);
  });

  test('скрипт тихого встановлення: лапки в шляхах подвоєні', () {
    final s = AppUpdater.windowsScript(r"C:\Users\O'Neil\Temp\Setup.exe", r'C:\Apps\Miki Miki\miki_miki.exe');
    expect(s, contains(r"-FilePath 'C:\Users\O''Neil\Temp\Setup.exe'"));
    expect(s, contains("'/SILENT','/SP-','/SUPPRESSMSGBOXES','/NORESTART','/CLOSEAPPLICATIONS' -Wait"));
    expect(s, endsWith(r"Start-Process -FilePath 'C:\Apps\Miki Miki\miki_miki.exe'"));
  });

  test('запит показати вікно: перевіряє, якщо версія ще невідома', () async {
    var calls = 0;
    final u = make((_) async {
      calls++;
      return (200, release('v1.2.0'));
    });
    u.requestPrompt();
    expect(u.promptRequests.value, 1);
    expect(u.state.value, isA<UpdateChecking>());
    while (u.state.value is UpdateChecking) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    expect(calls, 1);
    expect(u.state.value, isA<UpdateAvailable>());
    u.requestPrompt();
    expect(u.promptRequests.value, 2);
    expect(calls, 1, reason: 'версія відома — без нової перевірки');
  });
}
