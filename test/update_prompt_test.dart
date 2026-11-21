import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miki_miki/services/app_updater.dart';
import 'package:miki_miki/widgets/app_ui_kit.dart';
import 'package:miki_miki/widgets/update_prompt.dart';

/// A screen with one button that opens the update window
Widget host(AppUpdater updater, {UpdateInfo? info, bool start = false}) => MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(onPressed: () => UpdatePrompt.show(context, scale: 1, info: info, updater: updater, start: start), child: const Text('go')),
        ),
      ),
    );

AppUpdater fakeUpdater({
  Map<String, dynamic>? store,
  bool android = true,
  bool windows = false,
  UpdateFetch? fetch,
  String? dir,
  List<String>? installs,
  Future<(int, String)> Function(String)? transport,
}) {
  final saved = store ?? <String, dynamic>{};
  return AppUpdater(
    transport: transport ?? (_) async => throw 'no',
    fetch: fetch ?? (_, __) => Completer<UpdateFetchResponse>().future,
    load: () => saved,
    save: (d) => saved
      ..clear()
      ..addAll(d),
    currentVersion: '1.1.0',
    isAndroid: () => android,
    isWindows: () => windows,
    dir: () => dir ?? Directory.systemTemp.path,
    installApk: (p, ask) async {
      installs?.add(p);
      return 'started';
    },
    runSetup: (p) async {
      installs?.add(p);
      return true;
    },
    onNextResume: (_) {},
  );
}

void main() {
  const info = UpdateInfo(
    version: '1.2.0',
    notes: '## 1.2.0\n\n**Нове**\n- Список «Дивлюсь»\n- `Пріоритет` команд',
    pageUrl: 'https://github.com/x/y/releases/tag/v1.2.0',
    downloadUrl: 'https://dl/m.apk',
    size: 3 * 1048576,
  );

  test('нотатки релізу очищаються від markdown', () {
    final t = UpdatePrompt.cleanNotes(info.notes);
    expect(t, isNot(contains('##')));
    expect(t, isNot(contains('**')));
    expect(t, isNot(contains('`')));
    expect(t, contains('Список «Дивлюсь»'));
  });

  testWidgets('вікно: версія, нотатки, три кнопки; «Пропустити версію» запам\'ятовує вибір', (t) async {
    final store = <String, dynamic>{};
    final updater = AppUpdater(transport: (_) async => throw 'no', load: () => store, save: (d) => store..clear()..addAll(d), currentVersion: '1.1.0');
    await t.pumpWidget(MaterialApp(
      home: Builder(builder: (context) => Scaffold(body: TextButton(onPressed: () => UpdatePrompt.show(context, scale: 1, info: info, updater: updater), child: const Text('go')))),
    ));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    expect(find.text('Доступне оновлення'), findsOneWidget);
    expect(find.textContaining('Версія 1.2.0'), findsOneWidget);
    expect(find.textContaining('3.0 МБ'), findsOneWidget);
    expect(find.textContaining('Зараз встановлено 1.1.0'), findsOneWidget);
    expect(find.textContaining('Пріоритет команд'), findsOneWidget);
    expect(find.text('Завантажити'), findsOneWidget);
    expect(find.text('Пізніше'), findsOneWidget);

    await t.tap(find.text('Пропустити версію'));
    await t.pumpAndSettle();
    expect(find.text('Доступне оновлення'), findsNothing);
    expect(updater.skippedVersion, '1.2.0');
  });

  testWidgets('Android: «Оновити» завантажує з прогресом і сам відкриває інсталятор', (t) async {
    final dir = Directory.systemTemp.createTempSync('miki_prompt');
    addTearDown(() => dir.deleteSync(recursive: true));
    final bytes = List<int>.generate(3000, (i) => i % 251);
    final gate = Completer<void>();
    final installs = <String>[];
    Stream<List<int>> body() async* {
      yield bytes.sublist(0, 1000);
      await gate.future;
      yield bytes.sublist(1000);
    }

    var fetched = 0;
    final updater = fakeUpdater(
      dir: dir.path,
      installs: installs,
      fetch: (url, from) async {
        fetched++;
        return UpdateFetchResponse(200, bytes.length, body(), () {});
      },
    );
    final apk = UpdateInfo(
      version: '1.2.0',
      notes: 'Нове',
      pageUrl: 'https://github.com/x/y/releases/tag/v1.2.0',
      downloadUrl: 'https://dl/m-arm64.apk',
      assetName: 'm-arm64.apk',
      size: bytes.length,
      digest: 'sha256:${sha256.convert(bytes)}',
    );
    await t.pumpWidget(host(updater, info: apk));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    expect(find.text('Оновити'), findsOneWidget);
    expect(find.text('Пропустити версію'), findsOneWidget);

    final update = t.widget<AppAccentButton>(find.widgetWithText(AppAccentButton, 'Оновити'));
    await t.runAsync(() async {
      update.onTap();
      while (fetched == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    });
    // The bar and the numbers (a big file, so the megabytes are readable)
    updater.download.value = DownloadRunning('1.2.0', 12 * 1048576 + 300000, 36 * 1048576);
    await t.pump();
    expect(find.text('Завантаження… 12.3 з 36.0 МБ · 34%'), findsOneWidget);
    expect(find.text('Скасувати'), findsOneWidget);
    expect(find.text('У фоні'), findsOneWidget);
    expect(find.text('Оновити'), findsNothing);

    await t.runAsync(() async {
      gate.complete();
      while (installs.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    });
    await t.pump();
    expect(installs.single, endsWith('m-arm64.apk'));
    expect(File(installs.single).readAsBytesSync(), bytes);
    // The installer is on top; behind it the window offers to install again
    expect(find.text('Встановити'), findsOneWidget);
    expect(find.textContaining('Залишилось підтвердити встановлення'), findsOneWidget);
  });

  testWidgets('стани вікна: дозвіл Android, помилка, Windows із перезапуском', (t) async {
    final updater = fakeUpdater();
    await t.pumpWidget(host(updater, info: info));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();

    updater.download.value = const DownloadReady('1.2.0', '/x/m.apk', waitingPermission: true);
    await t.pump();
    expect(find.textContaining('Дозволити з цього джерела'), findsOneWidget);
    expect(find.text('Відкрити налаштування'), findsOneWidget);

    updater.download.value = const DownloadFailed('1.2.0', 'Немає зʼєднання. Спробуйте ще: завантаження продовжиться з того ж місця.');
    await t.pump();
    expect(find.textContaining('Немає зʼєднання'), findsOneWidget);
    expect(find.text('Спробувати ще'), findsOneWidget);
    expect(find.text('Сторінка релізу'), findsOneWidget);

    // A file of another version does not count for this one
    updater.download.value = const DownloadReady('1.1.9', '/x/old.apk');
    await t.pump();
    expect(find.text('Пропустити версію'), findsOneWidget);

    final win = fakeUpdater(android: false, windows: true);
    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(host(win, info: info));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    win.download.value = const DownloadReady('1.2.0', r'C:\t\Setup.exe');
    await t.pump();
    expect(find.text('Встановити й перезапустити'), findsOneWidget);
    expect(find.textContaining('закриється й відкриється знову'), findsOneWidget);
  });

  testWidgets('відкрите з повідомлення: спершу перевірка, потім «найновіша»', (t) async {
    final check = Completer<(int, String)>();
    final updater = fakeUpdater(transport: (_) => check.future);
    unawaited(updater.check());
    await t.pumpWidget(host(updater));
    await t.tap(find.text('go'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('Перевіряємо, чи є нова версія…'), findsOneWidget);
    check.complete((404, '{}'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('У вас найновіша версія — 1.1.0.'), findsOneWidget);
    await t.tap(find.text('Гаразд'));
    await t.pumpAndSettle();
    expect(UpdatePrompt.isOpen, isFalse);
  });

  test('рядок стану для профілю', () {
    final u = fakeUpdater();
    expect(UpdatePrompt.statusLine(u), isNull);
    u.state.value = const UpdateAvailable(info);
    expect(UpdatePrompt.statusLine(u), 'Є оновлення: версія 1.2.0');
    u.download.value = const DownloadRunning('1.2.0', 1, 4);
    expect(UpdatePrompt.statusLine(u), 'Завантаження оновлення… 25%');
    u.download.value = const DownloadReady('1.2.0', '/x');
    expect(UpdatePrompt.statusLine(u), 'Оновлення 1.2.0 готове до встановлення');
  });
}
