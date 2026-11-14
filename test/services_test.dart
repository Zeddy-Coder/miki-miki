import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:media_kit/media_kit.dart';
import 'package:miki_miki/models/media_models.dart';
import 'package:miki_miki/services/seek_preview_service.dart';
import 'package:miki_miki/widgets/app_dock_widgets.dart';

import 'support/fakes.dart';
import 'support/perf_harness.dart';

/// Position stream for the background player. Each access gives a separate stream with `onCancel`: for a broadcast
/// stream `cancel()` returns a ready Future from the root zone, and `await` on it does not advance
/// in the test's virtual time (it does not matter in the real app).
class _PreviewStream extends Fake implements PlayerStream {
  final List<StreamController<Duration>> _sinks = [];

  @override
  Stream<Duration> get position {
    final c = StreamController<Duration>(onCancel: () async {});
    _sinks.add(c);
    return c.stream;
  }

  void emit(Duration d) {
    for (final c in _sinks) {
      if (c.hasListener) c.add(d);
    }
  }
}

/// A preview background player without libmpv: counts releases, returns a "frame" after a seek.
class _PreviewPlayer extends Fake implements Player {
  final _PreviewStream s = _PreviewStream();
  Duration pos = Duration.zero;
  int disposed = 0;
  final List<Duration> seeks = [];

  /// If set, the frame is returned only when the test completes this Completer (a long frame)
  Completer<Uint8List?>? gate;

  @override
  PlayerStream get stream => s;

  @override
  PlayerState get state => PlayerState(position: pos);

  @override
  Future<void> seek(Duration d) async {
    seeks.add(d);
    Timer(const Duration(milliseconds: 10), () {
      pos = d;
      s.emit(d);
    });
  }

  @override
  Future<Uint8List?> screenshot({String? format = 'image/jpeg', bool includeLibassSubtitles = false}) async {
    final g = gate;
    if (g != null) return g.future;
    return Uint8List.fromList([1, 2, 3]);
  }

  @override
  Future<void> dispose() async => disposed++;
}

/// Mouse hover: first the frame from `onEnter`, then the reveal animation itself
Future<void> settleHover(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 16));
  await tester.pump(const Duration(milliseconds: 600));
}

/// Advances virtual time so the service's long waits (seek, the pause before a snapshot) finish
Future<void> settle(WidgetTester tester, {int ms = 1500}) async {
  for (var t = 0; t < ms; t += 50) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadTestFonts();
  });

  group('VolumeState', () {
    test('рівність за значенням', () {
      expect(const VolumeState(50, false), const VolumeState(50, false));
      expect(const VolumeState(50, false) == const VolumeState(51, false), isFalse);
      expect(const VolumeState(50, false) == const VolumeState(50, true), isFalse);
      expect(const VolumeState(50, false).hashCode, const VolumeState(50, false).hashCode);
    });

    test('однакове значення не сповіщає слухачів', () {
      final n = ValueNotifier<VolumeState>(const VolumeState(50, false));
      var calls = 0;
      n.addListener(() => calls++);
      n.value = const VolumeState(50, false);
      expect(calls, 0);
      n.value = const VolumeState(60, false);
      expect(calls, 1);
      n.dispose();
    });
  });

  group('Гучність', () {
    testWidgets('зміна гучності перебудовує лише повзунок, а не весь док і оверлей', (tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final p = FakePlayer();
      final vol = ValueNotifier<VolumeState>(const VolumeState(80, false));
      addTearDown(vol.dispose);
      final show = ValueNotifier<bool>(true);
      addTearDown(show.dispose);
      await tester.pumpWidget(playerOverlayHarness(player: p, showControls: show, chapters: sampleChapters(), volume: vol));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byIcon(Symbols.volume_up_rounded), findsOneWidget);

      final c = RebuildCounter()..start();
      try {
        vol.value = const VolumeState(80, true);
        await tester.pump(const Duration(milliseconds: 16));
        await tester.pump(const Duration(milliseconds: 600));
      } finally {
        c.stop();
      }
      expect(find.byIcon(Symbols.volume_off_rounded), findsOneWidget, reason: 'вимкнений звук показано іконкою');
      expect(c.byType['BottomDock'] ?? 0, 0, reason: 'док не перебудовується: ${c.top()}');
      expect(c.byType['ControlsOverlay'] ?? 0, 0, reason: 'оверлей не перебудовується: ${c.top()}');
      expect(c.byType['AppVolumeControl'] ?? 0, greaterThan(0));

      vol.value = const VolumeState(20, false);
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byIcon(Symbols.volume_down_rounded), findsOneWidget);
      expect(find.byIcon(Symbols.volume_off_rounded), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('кнопка вимикає звук, клік по доріжці задає гучність', (tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final changes = <double>[];
      var mutes = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: AppVolumeControl(
              scale: 1.0,
              volume: 80,
              isMuted: false,
              onVolumeChanged: changes.add,
              onToggleMute: () => mutes++,
            ),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 300));

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(5, 5));
      addTearDown(mouse.removePointer);

      // Hover reveals the slider
      final collapsed = tester.getRect(find.byType(AppVolumeControl));
      await mouse.moveTo(Offset(collapsed.left + 19, collapsed.center.dy));
      await settleHover(tester);
      final open = tester.getRect(find.byType(AppVolumeControl));
      expect(open.width, greaterThan(collapsed.width + 60), reason: 'повзунок розкрився при наведенні');

      // A click on the icon mutes the sound
      await mouse.down(Offset(open.left + 19, open.center.dy));
      await mouse.up();
      await tester.pump(const Duration(milliseconds: 100));
      expect(mutes, 1);
      expect(changes, isEmpty, reason: 'клік по іконці не змінює гучність');

      // The track starts after 1 (border) + 36 (button) + 6 (padding) pixels, length 70
      final trackLeft = open.left + 1 + 36 + 6;
      final y = open.center.dy;
      await mouse.down(Offset(trackLeft + 35, y)); // middle of the track
      await mouse.up();
      await tester.pump(const Duration(milliseconds: 100));
      expect(changes, isNotEmpty);
      expect(changes.last, closeTo(50, 1));

      await mouse.down(Offset(trackLeft + 70, y)); // end of the track
      await mouse.up();
      await tester.pump(const Duration(milliseconds: 100));
      expect(changes.last, closeTo(100, 1));
      expect(tester.takeException(), isNull);
    });
  });

  group('SeekPreviewService', () {
    late Directory tmp;
    late File video;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('seekprev_test');
      video = File('${tmp.path}/clip.mkv')..writeAsBytesSync([0, 1, 2, 3]);
      SeekPreviewService.dispose();
    });

    tearDown(() {
      SeekPreviewService.debugPlayerFactory = null;
      SeekPreviewService.dispose();
      tmp.deleteSync(recursive: true);
    });

    test("supports: результат запам'ятовується для поточного файлу", () {
      expect(SeekPreviewService.supports(video.path), isTrue);
      video.deleteSync();
      expect(SeekPreviewService.supports(video.path), isTrue, reason: 'без повторного звернення до диска');
      SeekPreviewService.dispose(); // cache reset (a new file / screen)
      expect(SeekPreviewService.supports(video.path), isFalse);
    });

    test('supports: мережеві адреси та порожнє значення не підтримуються', () {
      expect(SeekPreviewService.supports('https://example.com/a.mkv'), isFalse);
      expect(SeekPreviewService.supports(''), isFalse);
      expect(SeekPreviewService.supports(null), isFalse);
    });

    test('supports: file:// адреса існуючого файлу підтримується', () {
      expect(SeekPreviewService.supports(Uri.file(video.path).toString()), isTrue);
    });

    testWidgets('фоновий плеєр звільняється після простою, кадри лишаються, потім створюється заново', (tester) async {
      final made = <_PreviewPlayer>[];
      SeekPreviewService.debugPlayerFactory = (uri) async {
        final p = _PreviewPlayer();
        made.add(p);
        return p;
      };
      SeekPreviewService.prepare(video.path, const Duration(minutes: 20));
      SeekPreviewService.request(const Duration(minutes: 5));
      await settle(tester);
      expect(made.length, 1);
      expect(made[0].seeks, isNotEmpty);
      expect(SeekPreviewService.hasExact(const Duration(minutes: 5)), isTrue, reason: 'кадр потрапив у кеш');

      await tester.pump(SeekPreviewService.idleRelease - const Duration(seconds: 2));
      expect(made[0].disposed, 0, reason: 'ще не мине повний час простою');
      await tester.pump(const Duration(seconds: 3));
      expect(made[0].disposed, 1, reason: 'після простою плеєр звільнено');
      expect(SeekPreviewService.hasExact(const Duration(minutes: 5)), isTrue, reason: 'кадри з кешу доступні й без плеєра');

      // A new access creates the player anew
      SeekPreviewService.request(const Duration(minutes: 12));
      await settle(tester);
      expect(made.length, 2);
      expect(SeekPreviewService.hasExact(const Duration(minutes: 12)), isTrue);

      SeekPreviewService.dispose();
      expect(made[1].disposed, 1, reason: 'dispose() звільняє живий плеєр');
    });

    testWidgets('кадри з кешу не продовжують життя плеєра, нові запити — продовжують', (tester) async {
      final made = <_PreviewPlayer>[];
      SeekPreviewService.debugPlayerFactory = (uri) async {
        final p = _PreviewPlayer();
        made.add(p);
        return p;
      };
      SeekPreviewService.prepare(video.path, const Duration(minutes: 20));
      SeekPreviewService.request(const Duration(minutes: 5));
      await settle(tester);

      // New segments every ~20 s: the player is "in use", though more than 30 s passed overall
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(seconds: 20) - const Duration(milliseconds: 1500));
        SeekPreviewService.request(Duration(minutes: 8 + i));
        await settle(tester);
      }
      expect(made.length, 1, reason: 'той самий плеєр увесь час');
      expect(made[0].disposed, 0);

      // Repeated access to already ready frames does not "wake" the player
      await tester.pump(const Duration(seconds: 15));
      SeekPreviewService.request(const Duration(minutes: 5));
      await tester.pump(const Duration(seconds: 16));
      expect(made[0].disposed, 1, reason: 'з останнього знімка минуло понад 30 с');
    });

    testWidgets('довгий знімок не обривається звільненням: таймер чекає завершення роботи', (tester) async {
      final p = _PreviewPlayer()..gate = Completer<Uint8List?>();
      SeekPreviewService.debugPlayerFactory = (uri) async => p;
      SeekPreviewService.prepare(video.path, const Duration(minutes: 20));
      SeekPreviewService.request(const Duration(minutes: 5));
      await settle(tester);

      await tester.pump(const Duration(seconds: 31));
      expect(p.disposed, 0, reason: 'знімок ще триває');
      await tester.pump(const Duration(seconds: 31));
      expect(p.disposed, 0, reason: 'і далі триває');

      p.gate!.complete(Uint8List.fromList([9, 9]));
      await settle(tester);
      expect(SeekPreviewService.hasExact(const Duration(minutes: 5)), isTrue);
      expect(p.disposed, 0, reason: 'щойно закінчили — відлік простою починається знову');
      await tester.pump(const Duration(seconds: 31));
      expect(p.disposed, 1);
    });
  });
}
