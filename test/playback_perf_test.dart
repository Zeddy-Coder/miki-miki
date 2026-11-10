import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/perf_harness.dart';

/// Вимірювання навантаження на інтерфейс під час відтворення (позиція 60 разів/с).
/// Запуск: PERF_TAG=before flutter test test/playback_perf_test.dart
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadTestFonts();
  });

  final tag = Platform.environment['PERF_TAG'] ?? 'run';
  final results = <PerfResult>[];

  tearDownAll(() {
    saveResults(tag, results);
    // ignore: avoid_print
    print('\n===== PERF [$tag] =====\n${results.join('\n')}\n');
  });

  Future<FakePlayer> mount(WidgetTester tester, {required bool visible, Duration at = const Duration(minutes: 10)}) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final p = FakePlayer();
    p.current = p.current.copyWith(position: at, playing: true);
    final show = ValueNotifier<bool>(visible);
    addTearDown(show.dispose);
    await tester.pumpWidget(playerOverlayHarness(player: p, showControls: show, chapters: sampleChapters()));
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.takeException(), isNull);
    return p;
  }

  testWidgets('відтворення, панель керування видно (60 Гц)', (tester) async {
    final p = await mount(tester, visible: true);
    final r = await runPositionStorm(tester, p, name: 'видно, 60 Гц');
    results.add(r);
    expect(tester.takeException(), isNull);
  });

  testWidgets('відтворення, панель керування прихована (60 Гц)', (tester) async {
    final p = await mount(tester, visible: false);
    final r = await runPositionStorm(tester, p, name: 'приховано, 60 Гц');
    results.add(r);
    expect(tester.takeException(), isNull);
  });

  testWidgets('відтворення, панель керування прихована (24 Гц, типове аніме)', (tester) async {
    final p = await mount(tester, visible: false);
    final r = await runPositionStorm(tester, p, name: 'приховано, 24 Гц', hz: 24);
    results.add(r);
    expect(tester.takeException(), isNull);
  });
}
