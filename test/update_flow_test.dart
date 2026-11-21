import 'package:flutter_test/flutter_test.dart';
import 'package:miki_miki/services/app_updater.dart';
import 'package:miki_miki/services/deep_links.dart';
import 'package:miki_miki/widgets/update_prompt.dart';

import 'support/page_perf.dart';

const info = UpdateInfo(
  version: '1.2.0',
  notes: 'Нове',
  pageUrl: 'https://github.com/Zeddy-Coder/miki-miki/releases/tag/v1.2.0',
  downloadUrl: 'https://dl/m-arm64.apk',
  assetName: 'm-arm64.apk',
  size: 1000,
);

/// An updater that knows of 1.2.0; the version is "skipped", so only the cases under test open the window
AppUpdater knownUpdate() {
  final store = <String, dynamic>{'skip': '1.2.0'};
  final u = AppUpdater(
    transport: (_) async => throw 'no',
    fetch: (_, __) => Future.error('no'),
    load: () => store,
    save: (_) {},
    currentVersion: '1.1.0',
    isAndroid: () => true,
    isWindows: () => false,
    dir: () => '/tmp',
    installApk: (_, __) async => 'started',
    runSetup: (_) async => true,
    onNextResume: (_) {},
  );
  u.state.value = const UpdateAvailable(info);
  return u;
}

void main() {
  late AppUpdater saved;
  setUp(() => saved = AppUpdater.instance);
  tearDown(() => AppUpdater.instance = saved);

  testWidgets('дотик по «нова версія» до появи головного екрана: вікно відкривається, щойно він є', (t) async {
    final u = AppUpdater.instance = knownUpdate();
    expect(DeepLinks.handle('miki://open/update', updater: u), isTrue);
    await mountPerfHub(t, phone: true);
    await t.pumpAndSettle();
    expect(find.text('Доступне оновлення'), findsOneWidget);
    expect(find.text('Оновити'), findsOneWidget);
  });

  testWidgets('завантаження «у фоні» скінчилося, поки екран був закритий (плеєр): вікно пропонує встановити', (t) async {
    final u = AppUpdater.instance = knownUpdate();
    u.download.value = const DownloadReady('1.2.0', '/tmp/m-arm64.apk');
    u.downloadsDone.value++;
    await mountPerfHub(t, phone: true);
    await t.pumpAndSettle();
    expect(find.text('Встановити'), findsOneWidget);
    expect(UpdatePrompt.isOpen, isTrue);
    // Closed: the same finished download is not offered again
    await t.tap(find.text('Пізніше'));
    await t.pumpAndSettle();
    expect(UpdatePrompt.isOpen, isFalse);
  });

  testWidgets('завантаження скінчилося на відкритому екрані без вікна: вікно зʼявляється саме', (t) async {
    final u = AppUpdater.instance = knownUpdate();
    await mountPerfHub(t, phone: true);
    await t.pumpAndSettle();
    expect(find.text('Доступне оновлення'), findsNothing, reason: 'версію пропущено — саме вікно не відкривається');
    u.download.value = const DownloadReady('1.2.0', '/tmp/m-arm64.apk');
    u.downloadsDone.value++;
    await t.pumpAndSettle();
    expect(find.text('Встановити'), findsOneWidget);
  });
}
