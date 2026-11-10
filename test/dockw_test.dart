import 'dart:async';
import 'package:flutter/material.dart';
import 'package:miki_miki/models/media_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/gestures.dart';
import 'package:media_kit/media_kit.dart';
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
  for (final w in [1280.0, 760.0, 560.0]) {
    testWidgets('dock width $w', (tester) async {
      tester.view.physicalSize = Size(w, 200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final p = FakePlayer();
      await tester.pumpWidget(MaterialApp(home: Scaffold(backgroundColor: Colors.blueGrey, body: Stack(children: [
        BottomDock(
          scale: 1.0, player: p, currentSpeed: 1.0, volume: _Vol(),  isFullscreen: false,
          drawerOwner: null, isEpisodesOpen: false, chapters: const [], anime4kActive: false, anime4kKey: GlobalKey(), onAnime4kTap: () {}, onAnime4kSecondaryTap: () {},
          subsKey: GlobalKey(), audioKey: GlobalKey(), speedKey: GlobalKey(), volumeKey: GlobalKey(),
          onToggleFullscreen: () {}, onMiniPlayer: () {}, onVolumeChanged: (v) {}, onToggleMute: () {},
          onSubsTap: () {}, onAudioTap: () {}, onSpeedTap: () {}, onSpeedSecondaryTap: () {}, onEpisodesTap: () {}, onChaptersTap: () {},
        ),
      ]))));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('dock_w${w.toInt()}.png'));
    });
  }
}
