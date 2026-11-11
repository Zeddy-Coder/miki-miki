import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miki_miki/services/storage_service.dart';
import 'package:miki_miki/widgets/skip_button.dart';

import 'support/fakes.dart';
import 'support/perf_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadTestFonts();
  });

  Future<FakePlayer> pumpAt(WidgetTester t, Duration pos) async {
    t.view.physicalSize = const Size(1280, 720);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final p = FakePlayer();
    p.current = p.current.copyWith(position: Duration.zero);
    await t.pumpWidget(MaterialApp(
      home: Scaffold(body: Stack(children: [SkipButton(scale: 1, showControls: true, player: p, chapters: sampleChapters(), dismissedChapterStartTime: null)])),
    ));
    await t.pump(const Duration(milliseconds: 100));
    p.tickPosition(pos);
    await t.pump(const Duration(milliseconds: 400));
    return p;
  }

  tearDown(() {
    StorageService.saveAutoSkipChapters(false);
    StorageService.saveShowSkipButton(true);
  });

  testWidgets('типово: кнопка є, автопропуск вимкнено — перемотки немає', (t) async {
    expect(StorageService.getAutoSkipChapters(), isFalse);
    final p = await pumpAt(t, const Duration(minutes: 1, seconds: 35));
    expect(find.textContaining('Пропустити'), findsOneWidget);
    expect(p.seeks, isEmpty);
  });

  testWidgets('кнопку можна вимкнути в налаштуваннях', (t) async {
    StorageService.saveShowSkipButton(false);
    await pumpAt(t, const Duration(minutes: 1, seconds: 35));
    expect(find.textContaining('Пропустити'), findsNothing);
  });

  testWidgets('автопропуск: на опенінгу перемотує до його кінця', (t) async {
    StorageService.saveAutoSkipChapters(true);
    final p = await pumpAt(t, const Duration(minutes: 1, seconds: 35));
    expect(p.seeks, [const Duration(minutes: 3)]);
    // Той самий розділ вдруге не пропускається
    p.tickPosition(const Duration(minutes: 1, seconds: 38));
    await t.pump(const Duration(milliseconds: 200));
    expect(p.seeks.length, 1);
  });
}
