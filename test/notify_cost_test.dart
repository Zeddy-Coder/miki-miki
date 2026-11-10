import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miki_miki/models/media_models.dart';
import 'package:miki_miki/services/anime4k_controller.dart';
import 'package:miki_miki/widgets/controls_overlay.dart';
import 'package:miki_miki/widgets/skip_button.dart';

import 'support/fakes.dart';
import 'support/perf_harness.dart';

/// Вартість подій керування: загальне сповіщення контролера (перебудова оверлею) проти
/// окремого нотифікатора гучності. Запуск: flutter test test/notify_cost_test.dart
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadTestFonts();
  });

  Future<void> run(WidgetTester tester, String name, {required bool volumeOnly}) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final p = FakePlayer();
    final tick = ValueNotifier<int>(0); // стандартне сповіщення контролера → перебудова екрана
    addTearDown(tick.dispose);
    final volState = ValueNotifier<VolumeState>(const VolumeState(50, false));
    addTearDown(volState.dispose);
    final a4k = Anime4kController(command: (args) async {}, osd: (message, {duration}) {});
    final scroll = ScrollController();
    void noop() {}
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ValueListenableBuilder<int>(
          valueListenable: tick,
          builder: (context, v, _) => Stack(children: [
            SkipButton(scale: 1, showControls: true, player: p, chapters: sampleChapters(), dismissedChapterStartTime: null),
            ControlsOverlay(
              scale: 1.0, showControls: true, isSpeeding: false, isDraggingFile: false, currentTitle: 'T', player: p,
              currentSpeed: v.isEven ? 1.0 : 1.25, volume: volState, isFullscreen: false, activeDrawer: null, activeDrawerPrev: null,
              drawerOwner: null, isEpisodesOpen: false, drawerAnchorPixelX: 260, drawerIsTop: false, chapters: sampleChapters(),
              subtitleTracks: const [], audioTracks: const [], currentHwdec: 'auto', drawerScrollController: scroll, anime4k: a4k,
              settingsKey: GlobalKey(), anime4kKey: GlobalKey(), subsKey: GlobalKey(), audioKey: GlobalKey(), speedKey: GlobalKey(), volumeKey: GlobalKey(),
              onMiniPlayer: noop, onCollapse: noop, onClosePlayer: noop, onOpenFile: noop, onToggleFullscreen: noop, onToggleMute: noop,
              onVolumeChanged: (_) {}, onSettingsTap: noop, onInfoTap: noop, onEpisodesTap: noop, onChaptersTap: noop, onAnime4kTap: noop,
              onAnime4kSecondaryTap: noop, onSubsTap: noop, onAudioTap: noop, onSpeedTap: noop, onSpeedSecondaryTap: noop, onCloseDrawer: noop,
              onBackDrawer: noop, onOpenSubDrawer: (_) {}, onSpeedSelected: (_) {}, onSubtitleSelected: (_) {}, onAudioSelected: (_) {},
              onHwdecSelected: (_) {}, onOpenStats: noop,
            ),
          ]),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 600));
    final c = RebuildCounter()..start();
    final sw = Stopwatch();
    for (var i = 0; i < 60; i++) {
      if (volumeOnly) {
        volState.value = VolumeState(50 + i + 1.0, false);
      } else {
        tick.value++;
      }
      await tester.idle();
      sw.start();
      await tester.pump(const Duration(milliseconds: 16));
      sw.stop();
    }
    c.stop();
    // ignore: avoid_print
    print('NOTIFY [$name]: перебудов елементів на подію = ${(c.total / 60).toStringAsFixed(1)}, '
        'мс/кадр(debug) = ${(sw.elapsedMicroseconds / 60 / 1000).toStringAsFixed(2)}; топ: ${c.top(4)}');
    expect(tester.takeException(), isNull);
  }

  testWidgets('загальне сповіщення контролера (перебудова оверлею)', (tester) => run(tester, 'загальне', volumeOnly: false));
  testWidgets('зміна гучності (окремий нотифікатор)', (tester) => run(tester, 'гучність', volumeOnly: true));
}
