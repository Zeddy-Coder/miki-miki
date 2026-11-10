import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miki_miki/models/media_models.dart';
import 'package:miki_miki/services/anime4k_controller.dart';
import 'package:miki_miki/widgets/controls_overlay.dart';
import 'package:miki_miki/widgets/skip_button.dart';

import 'fakes.dart';

/// Рахує перебудови елементів (build) за типом віджета — через відладочний хук Flutter.
class RebuildCounter {
  final Map<String, int> byType = {};
  int total = 0;

  void start() {
    debugOnRebuildDirtyWidget = (Element e, bool builtOnce) {
      total++;
      final name = e.widget.runtimeType.toString();
      byType[name] = (byType[name] ?? 0) + 1;
    };
  }

  void stop() => debugOnRebuildDirtyWidget = null;

  void reset() {
    total = 0;
    byType.clear();
  }

  List<MapEntry<String, int>> top([int n = 8]) {
    final list = byType.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return list.take(n).toList();
  }
}

class PerfResult {
  final String name;
  final double seconds;
  final int ticks;
  final int rebuilds;
  final int framesRequested;
  final double msPerFrame;
  final List<MapEntry<String, int>> top;

  PerfResult({
    required this.name,
    required this.seconds,
    required this.ticks,
    required this.rebuilds,
    required this.framesRequested,
    required this.msPerFrame,
    required this.top,
  });

  double get rebuildsPerSec => rebuilds / seconds;
  double get framesPerSec => framesRequested / seconds;

  Map<String, Object> toJson() => {
        'name': name,
        'seconds': seconds,
        'ticks': ticks,
        'rebuilds': rebuilds,
        'rebuildsPerSec': double.parse(rebuildsPerSec.toStringAsFixed(1)),
        'framesRequested': framesRequested,
        'framesPerSec': double.parse(framesPerSec.toStringAsFixed(1)),
        'msPerFrame': double.parse(msPerFrame.toStringAsFixed(3)),
        'top': {for (final e in top) e.key: e.value},
      };

  @override
  String toString() =>
      '$name: перебудов/с=${rebuildsPerSec.toStringAsFixed(1)}  кадрів замовлено/с=${framesPerSec.toStringAsFixed(1)}  '
      'мс/кадр(debug)=${msPerFrame.toStringAsFixed(2)}  топ=${top.take(5).map((e) => '${e.key}×${e.value}').join(', ')}';
}

/// Програє «шторм» подій позиції (як mpv time-pos) і вимірює навантаження на інтерфейс.
Future<PerfResult> runPositionStorm(
  WidgetTester tester,
  FakePlayer player, {
  required String name,
  double seconds = 3,
  int hz = 60,
  Duration? from,
}) async {
  final counter = RebuildCounter();
  final dt = Duration(microseconds: 1000000 ~/ hz);
  var pos = from ?? player.state.position;
  final n = (seconds * hz).round();

  // Прогрів: один кадр, щоб не міряти початкову побудову
  await tester.pump(dt);

  counter.start();
  var frames = 0;
  final sw = Stopwatch();
  for (var i = 0; i < n; i++) {
    pos += dt;
    player.tickPosition(pos);
    await tester.idle();
    if (tester.binding.hasScheduledFrame) frames++;
    sw.start();
    await tester.pump(dt);
    sw.stop();
  }
  counter.stop();

  return PerfResult(
    name: name,
    seconds: seconds,
    ticks: n,
    rebuilds: counter.total,
    framesRequested: frames,
    msPerFrame: sw.elapsedMicroseconds / n / 1000,
    top: counter.top(),
  );
}

/// Зберігає результати у JSON (для порівняння «до/після»)
void saveResults(String tag, List<PerfResult> results) {
  final f = File('/tmp/proj/perf_$tag.json');
  f.writeAsStringSync(const JsonEncoder.withIndent('  ').convert([for (final r in results) r.toJson()]));
}

/// Розділи для тестів: опенінґ і ендінґ — «пропускні»
List<VideoChapter> sampleChapters() => const [
      VideoChapter(title: 'Prologue', startTime: Duration.zero),
      VideoChapter(title: 'Opening', startTime: Duration(minutes: 1, seconds: 30)),
      VideoChapter(title: 'Part A', startTime: Duration(minutes: 3)),
      VideoChapter(title: 'Part B', startTime: Duration(minutes: 12)),
      VideoChapter(title: 'Ending', startTime: Duration(minutes: 20)),
      VideoChapter(title: 'Preview', startTime: Duration(minutes: 22)),
    ];

/// Склад екрана плеєра без самого відео: кнопка пропуску + оверлей керування.
Widget playerOverlayHarness({
  required FakePlayer player,
  required ValueListenable<bool> showControls,
  List<VideoChapter> chapters = const [],
  Duration? dismissed,
  ValueListenable<VolumeState>? volume,
}) {
  final ValueListenable<VolumeState> vol = volume ?? ValueNotifier<VolumeState>(const VolumeState(80, false));
  final a4k = Anime4kController(command: (args) async {}, osd: (message, {duration}) {});
  final scroll = ScrollController();
  void noop() {}
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      backgroundColor: Colors.black,
      body: ValueListenableBuilder<bool>(
        valueListenable: showControls,
        builder: (context, visible, _) => Stack(
          children: [
            const Positioned.fill(child: ColoredBox(color: Color(0xFF101820))),
            SkipButton(
              scale: 1.0,
              showControls: visible,
              player: player,
              chapters: chapters,
              dismissedChapterStartTime: dismissed,
            ),
            ControlsOverlay(
              scale: 1.0,
              showControls: visible,
              isSpeeding: false,
              isDraggingFile: false,
              currentTitle: 'Test episode',
              player: player,
              currentSpeed: 1.0,
              volume: vol,
              isFullscreen: false,
              activeDrawer: null,
              activeDrawerPrev: null,
              drawerOwner: null,
              isEpisodesOpen: false,
              drawerAnchorPixelX: 260,
              drawerIsTop: false,
              chapters: chapters,
              subtitleTracks: const [],
              audioTracks: const [],
              currentHwdec: 'auto',
              drawerScrollController: scroll,
              anime4k: a4k,
              settingsKey: GlobalKey(),
              anime4kKey: GlobalKey(),
              subsKey: GlobalKey(),
              audioKey: GlobalKey(),
              speedKey: GlobalKey(),
              volumeKey: GlobalKey(),
              onMiniPlayer: noop,
              onCollapse: noop,
              onClosePlayer: noop,
              onOpenFile: noop,
              onToggleFullscreen: noop,
              onToggleMute: noop,
              onVolumeChanged: (_) {},
              onSettingsTap: noop,
              onInfoTap: noop,
              onEpisodesTap: noop,
              onChaptersTap: noop,
              onAnime4kTap: noop,
              onAnime4kSecondaryTap: noop,
              onSubsTap: noop,
              onAudioTap: noop,
              onSpeedTap: noop,
              onSpeedSecondaryTap: noop,
              onCloseDrawer: noop,
              onBackDrawer: noop,
              onOpenSubDrawer: (_) {},
              onSpeedSelected: (_) {},
              onSubtitleSelected: (_) {},
              onAudioSelected: (_) {},
              onHwdecSelected: (_) {},
              onOpenStats: noop,
            ),
          ],
        ),
      ),
    ),
  );
}
