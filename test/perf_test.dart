import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:miki_miki/models/media_models.dart';
import 'package:miki_miki/widgets/bottom_dock.dart';
import 'package:miki_miki/widgets/side_panel.dart';
import 'package:miki_miki/widgets/app_animation_kit.dart';

class FS extends Fake implements PlayerStream {
  @override Stream<Duration> get position => const Stream.empty();
  @override Stream<bool> get playing => const Stream.empty();
  @override Stream<Duration> get duration => const Stream.empty();
  @override Stream<Duration> get buffer => const Stream.empty();
  @override Stream<PlaylistMode> get playlistMode => const Stream.empty();
}
class FP extends Fake implements Player {
  @override PlayerStream get stream => FS();
  @override PlayerState get state => PlayerState(playlist: Playlist([Media('/x.mkv')]), duration: const Duration(minutes: 90), position: const Duration(minutes: 20), buffer: const Duration(minutes: 30));
}

class _Vol extends ValueNotifier<VolumeState> {
  _Vol() : super(const VolumeState(80, false));
}

void main() {
  for (final kind in ['episodes', 'episodes-panel-only', 'episodes-cached']) {
    testWidgets('slide perf $kind', (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final p = FP();
      int builds = 0;
      final k1 = GlobalKey(), k2 = GlobalKey(), k3 = GlobalKey(), k4 = GlobalKey();
      final open = ValueNotifier(false);
      final items = List.generate(30, (i) => Media('/nonexistent/v$i.mkv', extras: {'title': 'Video $i'}));
      final chapters = List.generate(12, (i) => VideoChapter(title: 'Chapter $i', startTime: Duration(minutes: i * 5)));
      final cached = Stack(children: [BottomDock(
                    scale: 1.0, player: p, currentSpeed: 1.0, volume: _Vol(),  isFullscreen: false,
                    drawerOwner: null, isEpisodesOpen: false, chapters: const [], anime4kActive: false, anime4kKey: GlobalKey(), onAnime4kTap: () {}, onAnime4kSecondaryTap: () {},
                    subsKey: k1, audioKey: k2, speedKey: k3, volumeKey: k4,
                    onToggleFullscreen: () {}, onMiniPlayer: () {}, onVolumeChanged: (v) {}, onToggleMute: () {},
                    onSubsTap: () {}, onAudioTap: () {}, onSpeedTap: () {}, onSpeedSecondaryTap: () {}, onEpisodesTap: () {}, onChaptersTap: () {},
                  )]);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: open,
            builder: (_, o, __) => Row(children: [
              Expanded(child: kind.endsWith('only') ? const SizedBox() : kind.endsWith('cached') ? cached : LayoutBuilder(builder: (c, cons) {
                builds++;
                return Stack(children: [
                  BottomDock(
                    scale: 1.0, player: p, currentSpeed: 1.0, volume: _Vol(),  isFullscreen: false,
                    drawerOwner: null, isEpisodesOpen: false, chapters: const [], anime4kActive: false, anime4kKey: GlobalKey(), onAnime4kTap: () {}, onAnime4kSecondaryTap: () {},
                    subsKey: k1, audioKey: k2, speedKey: k3, volumeKey: k4,
                    onToggleFullscreen: () {}, onMiniPlayer: () {}, onVolumeChanged: (v) {}, onToggleMute: () {},
                    onSubsTap: () {}, onAudioTap: () {}, onSpeedTap: () {}, onSpeedSecondaryTap: () {}, onEpisodesTap: () {}, onChaptersTap: () {},
                  ),
                ]);
              })),
              AppSlideReveal(
                isOpen: o,
                extent: 380,
                child: SidePanel(
                  scale: 1.0,
                  type: kind.startsWith('episodes') ? SidePanelType.episodes : SidePanelType.chapters,
                  player: p, playlistItems: items, currentPlaylistIndex: 2, chapters: chapters,
                  onClose: () {}, onAddMedia: () {}, onEpisodeSelected: (_) {}, onChapterSelected: (_) {},
                  onQueueReorder: (a, b) {}, onQueueRemove: (_) {}, onQueueClear: () {},
                ),
              ),
            ]),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 100));
      builds = 0;
      open.value = true;
      await tester.pump();
      final sw = Stopwatch()..start();
      int frames = 0;
      for (int t = 0; t < 400; t += 16) {
        await tester.pump(const Duration(milliseconds: 16));
        frames++;
      }
      sw.stop();
      debugPrint('PERF $kind: frames=$frames layoutBuilder rebuilds=$builds avg ${(sw.elapsedMicroseconds / frames / 1000).toStringAsFixed(2)} ms/frame (debug, headless)');
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    });
  }
}
