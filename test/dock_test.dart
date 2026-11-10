import 'dart:async';
import 'package:flutter/material.dart';
import 'package:miki_miki/models/media_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/gestures.dart';
import 'package:media_kit/media_kit.dart';
import 'package:miki_miki/services/seek_preview_service.dart';
import 'package:miki_miki/widgets/bottom_dock.dart';
import 'package:miki_miki/widgets/app_dock_widgets.dart';

class FakeStream extends Fake implements PlayerStream {
  final pos = StreamController<Duration>.broadcast();
  final playing_ = StreamController<bool>.broadcast();
  final dur = StreamController<Duration>.broadcast();
  final buf = StreamController<Duration>.broadcast();
  @override Stream<Duration> get position => pos.stream;
  @override Stream<bool> get playing => playing_.stream;
  @override Stream<Duration> get duration => dur.stream;
  @override Stream<Duration> get buffer => buf.stream;
}

class FakePlayer extends Fake implements Player {
  final s = FakeStream();
  @override PlayerStream get stream => s;
  @override PlayerState get state => PlayerState(playlist: Playlist([Media('/tmp/proj/fake.mkv')]), duration: const Duration(minutes: 90), position: const Duration(minutes: 20), buffer: const Duration(minutes: 30), playing: false);
  @override Future<void> seek(Duration d) async { debugPrint('seek $d'); }
  @override Future<void> playOrPause({bool notify = true}) async {}
  @override Future<void> setRate(double r) async { debugPrint('rate $r'); }
}

class _Vol extends ValueNotifier<VolumeState> {
  _Vol() : super(const VolumeState(80, false));
}

void main() {
  testWidgets('dock renders and seekbar paints', (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final p = FakePlayer();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.blueGrey,
        body: Stack(children: [
          BottomDock(
            scale: 1.0, player: p, currentSpeed: 1.0, volume: _Vol(),  isFullscreen: false,
            drawerOwner: null, isEpisodesOpen: false, chapters: const [], anime4kActive: false, anime4kKey: GlobalKey(), onAnime4kTap: () {}, onAnime4kSecondaryTap: () {},
            subsKey: GlobalKey(), audioKey: GlobalKey(), speedKey: GlobalKey(), volumeKey: GlobalKey(),
            onToggleFullscreen: () {}, onMiniPlayer: () {}, onVolumeChanged: (v) => debugPrint('vol $v'), onToggleMute: () {},
            onSubsTap: () {}, onAudioTap: () {}, onSpeedTap: () {}, onSpeedSecondaryTap: () {}, onEpisodesTap: () {}, onChaptersTap: () {},
          ),
        ]),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(10, 10));
    await mouse.moveTo(const Offset(600, 640));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    final bar = tester.getRect(find.byType(AppSeekBar));
    debugPrint('seekbar rect $bar');
    expect(bar.height, 30);
    await mouse.moveTo(Offset(bar.left + bar.width * 0.4, bar.center.dy));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    await mouse.down(Offset(bar.left + bar.width * 0.5, bar.center.dy));
    await mouse.up();
    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(find.byType(Scaffold), matchesGoldenFile('dock_hover.png'));
    // колесо над швидкістю
    final speed = find.text('1x');
    await mouse.moveTo(tester.getCenter(speed));
    await mouse.down(tester.getCenter(speed)); await mouse.up();
    await tester.sendEventToBinding(PointerScrollEvent(position: tester.getCenter(speed), scrollDelta: const Offset(0, -20), kind: PointerDeviceKind.mouse));
    await tester.pump();
    // гучність: навести і клікнути на повзунок
    final vol = find.byType(AppVolumeControl);
    final vr = tester.getRect(vol);
    await mouse.moveTo(vr.center);
    await tester.pump(const Duration(milliseconds: 400));
    final vr2 = tester.getRect(vol);
    debugPrint('vol rect before $vr after $vr2');
    await mouse.down(Offset(vr2.right - 30, vr2.center.dy)); await mouse.up();
    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(find.byType(Scaffold), matchesGoldenFile('dock_vol.png'));
    expect(tester.takeException(), isNull);
    // наведення на смужку запускає фоновий сервіс прев'ю (таймер простою) — зупиняємо його до кінця тесту
    SeekPreviewService.dispose();
  });
}
