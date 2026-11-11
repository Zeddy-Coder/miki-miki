import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:miki_miki/services/osd_message.dart';
import 'package:media_kit/media_kit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miki_miki/services/video_zoom.dart';
import 'package:miki_miki/widgets/mobile_gesture_layer.dart';

import 'support/fakes.dart';

void main() {
  const view = Size(800, 360);
  final fit = VideoZoomMath.fitSize(view, 16 / 9); // 640×360, по боках чорні смуги

  group('VideoZoomMath', () {
    test('fitSize вписує відео, coverScale заповнює екран', () {
      expect(fit, const Size(640, 360));
      expect(VideoZoomMath.coverScale(view, fit), closeTo(1.25, 1e-9));
    });

    test('масштаб прилипає до 1× і до «на весь екран»', () {
      final cover = VideoZoomMath.coverScale(view, fit);
      expect(VideoZoomMath.snapScale(1.04, cover: cover), 1.0);
      expect(VideoZoomMath.snapScale(0.8, cover: cover), 1.0);
      expect(VideoZoomMath.snapScale(1.28, cover: cover), cover);
      expect(VideoZoomMath.snapScale(2.0, cover: cover), 2.0);
      expect(VideoZoomMath.snapScale(9.0, cover: cover), VideoZoomMath.maxScale);
    });

    test('зображення не виходить за краї, а поблизу краю прилипає', () {
      // 2×: 1280×720 у вікні 800×360 → запас ±240 по x і ±180 по y
      expect(VideoZoomMath.clampOffset(const Offset(500, 500), 2, view, fit), const Offset(240, 180));
      expect(VideoZoomMath.clampOffset(const Offset(-500, -500), 2, view, fit), const Offset(-240, -180));
      expect(VideoZoomMath.clampOffset(const Offset(230, 0), 2, view, fit).dx, 240, reason: 'прилипло до правого краю');
      expect(VideoZoomMath.clampOffset(const Offset(100, 0), 2, view, fit).dx, 100, reason: 'далеко від країв — вільно');
      expect(VideoZoomMath.clampOffset(const Offset(10, 8), 2, view, fit), Offset.zero, reason: 'біля центру прилипає до центру');
    });

    test('якщо відео вужче за екран, воно лишається по центру', () {
      // 1.1×: 704 < 800 по x
      expect(VideoZoomMath.clampOffset(const Offset(60, 0), 1.1, view, fit).dx, 0);
    });

    test('zoomAround тримає точку під пальцями', () {
      final o = VideoZoomMath.zoomAround(
        startOffset: Offset.zero,
        startScale: 1,
        scale: 2,
        startFocal: const Offset(100, 50),
        focal: const Offset(100, 50),
      );
      expect(o, const Offset(-100, -50));
    });
  });

  group('MobileGestureLayer: щипок', () {
    late VideoZoomController zoom;
    late List<double> volumes;

    Future<void> mount(WidgetTester tester) async {
      tester.view.physicalSize = view;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      zoom = VideoZoomController();
      volumes = [];
      await tester.pumpWidget(MaterialApp(
        home: SizedBox(
          width: view.width,
          height: view.height,
          child: Stack(children: [
            MobileGestureLayer(
              player: FakePlayer(),
              osd: (m, {duration}) {},
              zoom: zoom,
              readBrightness: () async => 0.5,
              writeBrightness: (v) async {},
              readVolume: () async => 0.5,
              writeVolume: (v) async => volumes.add(v),
            ),
          ]),
        ),
      ));
    }

    testWidgets('розведення пальців збільшує, відпускання — прилипання до країв; гучність не чіпається', (tester) async {
      await mount(tester);
      final c = Offset(view.width / 2, view.height / 2);
      final a = await tester.startGesture(c + const Offset(-20, 0), pointer: 1);
      final b = await tester.startGesture(c + const Offset(20, 0), pointer: 2);
      expect(zoom.pinching, isTrue);
      for (var i = 1; i <= 10; i++) {
        await a.moveTo(c + Offset(-20 - i * 12.0, i * 2.0));
        await b.moveTo(c + Offset(20 + i * 12.0, -i * 2.0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(zoom.scale, greaterThan(2.0));
      await a.up();
      await b.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(zoom.pinching, isFalse);
      expect(zoom.scale, greaterThan(2.0));
      expect(volumes, isEmpty, reason: 'щипок не змінює гучність');
    });

    testWidgets('стискання нижче 1× повертає звичайний розмір', (tester) async {
      await mount(tester);
      zoom.set(2.0, const Offset(40, 0));
      final c = Offset(view.width / 2, view.height / 2);
      final a = await tester.startGesture(c + const Offset(-200, 0), pointer: 1);
      final b = await tester.startGesture(c + const Offset(200, 0), pointer: 2);
      for (var i = 1; i <= 10; i++) {
        await a.moveTo(c + Offset(-200 + i * 19.0, 0));
        await b.moveTo(c + Offset(200 - i * 19.0, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await a.up();
      await b.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(zoom.scale, 1.0);
      expect(zoom.offset, Offset.zero);
    });

    testWidgets('масштаб завжди від центру, прилипає до «на весь екран» з підписом і вібровідгуком', (tester) async {
      final haptics = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'HapticFeedback.vibrate') haptics.add('${call.arguments}');
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      final msgs = <OsdMessage>[];
      final player = FakePlayer()..current = FakePlayer().current.copyWith(width: 1920, height: 1080);
      tester.view.physicalSize = view;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      zoom = VideoZoomController();
      await tester.pumpWidget(MaterialApp(
        home: Stack(children: [MobileGestureLayer(player: player, osd: (m, {duration}) => msgs.add(m), zoom: zoom)]),
      ));
      final c = Offset(view.width / 2, view.height / 2);
      final a = await tester.startGesture(c + const Offset(-100, 40), pointer: 1);
      final b = await tester.startGesture(c + const Offset(100, 40), pointer: 2);
      // 200 → 250 пікселів між пальцями = ×1.25 (рівно «на весь екран» для 16:9 у 800×360)
      await a.moveTo(c + const Offset(-125, 40));
      await b.moveTo(c + const Offset(125, 40));
      await tester.pump(const Duration(milliseconds: 16));
      expect(zoom.scale, closeTo(1.25, 1e-9));
      expect(zoom.offset, Offset.zero, reason: 'лише від центру, без зсуву');
      expect(msgs.last.detail, 'На весь екран');
      expect(msgs.last.title, startsWith('×1.25'));
      expect(haptics, isNotEmpty, reason: 'клацання при примагнічуванні');
      // рух пальців убік не зсуває зображення
      await a.moveTo(c + const Offset(-125, 140));
      await b.moveTo(c + const Offset(125, 140));
      await tester.pump(const Duration(milliseconds: 16));
      expect(zoom.offset, Offset.zero);
      await a.up();
      await b.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets('один палець без щипка не збільшує', (tester) async {
      await mount(tester);
      final g = await tester.startGesture(const Offset(400, 180));
      await g.moveBy(const Offset(60, 0));
      await g.up();
      await tester.pump(const Duration(milliseconds: 300));
      expect(zoom.scale, 1.0);
    });
  });
}
