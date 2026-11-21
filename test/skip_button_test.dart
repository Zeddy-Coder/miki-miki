import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miki_miki/models/media_models.dart';
import 'package:miki_miki/services/storage_service.dart';
import 'package:miki_miki/widgets/skip_button.dart';

import 'support/fakes.dart';
import 'support/perf_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadTestFonts();
  });

  Future<FakePlayer> pumpAt(WidgetTester t, Duration pos, {List<VideoChapter>? chapters}) async {
    t.view.physicalSize = const Size(1280, 720);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final p = FakePlayer();
    p.current = p.current.copyWith(position: Duration.zero);
    await t.pumpWidget(MaterialApp(
      home: Scaffold(body: Stack(children: [SkipButton(scale: 1, showControls: true, player: p, chapters: chapters ?? sampleChapters(), dismissedChapterStartTime: null)])),
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
    // The same chapter is not skipped a second time
    p.tickPosition(const Duration(minutes: 1, seconds: 38));
    await t.pump(const Duration(milliseconds: 200));
    expect(p.seeks.length, 1);
  });

  testWidgets('приблизні таймкоди (AniSkip без відомого зсуву): лише кнопка, автопропуску немає', (t) async {
    StorageService.saveAutoSkipChapters(true);
    final p = await pumpAt(t, const Duration(seconds: 70), chapters: const [
      VideoChapter(title: 'Episode', startTime: Duration.zero, endTime: Duration(seconds: 65)),
      VideoChapter(title: 'Opening', startTime: Duration(seconds: 65), endTime: Duration(seconds: 125), autoSkip: false),
      VideoChapter(title: 'Episode', startTime: Duration(seconds: 125)),
    ]);
    expect(p.seeks, isEmpty);
    expect(find.text('Пропустити опенінґ'), findsOneWidget);
    await t.tap(find.text('Пропустити опенінґ'));
    await t.pump(const Duration(milliseconds: 200));
    expect(p.seeks, [const Duration(seconds: 125)]);
  });

  testWidgets('заставка команди: «Пропустити заставку»', (t) async {
    await pumpAt(t, const Duration(seconds: 2), chapters: const [
      VideoChapter(title: 'Заставка', startTime: Duration.zero, endTime: Duration(seconds: 8)),
      VideoChapter(title: 'Episode', startTime: Duration(seconds: 8)),
    ]);
    expect(find.text('Пропустити заставку'), findsOneWidget);
  });
}
