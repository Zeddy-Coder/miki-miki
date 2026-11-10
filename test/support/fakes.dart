import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit/src/player/platform_player.dart';
import 'package:miki_miki/services/anime4k_controller.dart';
import 'package:miki_miki/services/osd_message.dart';
import 'package:miki_miki/services/player_actions.dart';
import 'package:miki_miki/services/player_state_controller.dart';
import 'package:miki_miki/services/shortcut_catalog.dart';
import 'package:miki_miki/services/ui_theme_service.dart';
import 'package:miki_miki/widgets/side_panel.dart';

/// Справжні шрифти для скриншотів: Arial → Roboto, іконки Material Symbols.
Future<void> loadTestFonts() async {
  Future<ByteData> bytes(String path) async => ByteData.sublistView(Uint8List.fromList(await File(path).readAsBytes()));

  const roboto = '/tmp/fl/flutter/bin/cache/artifacts/material_fonts';
  final arial = FontLoader('Arial')
    ..addFont(bytes('$roboto/Roboto-Regular.ttf'))
    ..addFont(bytes('$roboto/Roboto-Medium.ttf'))
    ..addFont(bytes('$roboto/Roboto-Bold.ttf'));
  await arial.load();

  final home = Platform.environment['HOME'] ?? '/root';
  final symbols = FontLoader('packages/material_symbols_icons/MaterialSymbolsRounded')
    ..addFont(bytes('$home/.pub-cache/hosted/pub.dev/material_symbols_icons-4.2960.0/lib/fonts/MaterialSymbolsRounded.ttf'));
  await symbols.load();
}

class FakeStream extends Fake implements PlayerStream {
  final pos = StreamController<Duration>.broadcast();
  final playing_ = StreamController<bool>.broadcast();
  final dur = StreamController<Duration>.broadcast();
  final buf = StreamController<Duration>.broadcast();
  final mode_ = StreamController<PlaylistMode>.broadcast();
  @override
  Stream<PlaylistMode> get playlistMode => mode_.stream;
  @override
  Stream<Duration> get position => pos.stream;
  @override
  Stream<bool> get playing => playing_.stream;
  @override
  Stream<Duration> get duration => dur.stream;
  @override
  Stream<Duration> get buffer => buf.stream;
}

class FakePlayer extends Fake implements Player {
  final s = FakeStream();
  final List<Duration> seeks = [];
  final List<double> rates = [];
  final List<PlaylistMode> modes = [];
  int playPauseCalls = 0;
  final List<double> volumes = [];

  PlayerState current = PlayerState(
    playlist: Playlist([Media('/tmp/proj/fake.mkv')]),
    duration: const Duration(minutes: 90),
    position: const Duration(minutes: 20),
    buffer: const Duration(minutes: 30),
    playing: false,
  );

  /// Імітація тіку mpv `time-pos`: оновлює state і шле подію в потік
  void tickPosition(Duration p) {
    current = current.copyWith(position: p);
    s.pos.add(p);
  }

  void setDuration(Duration d) {
    current = current.copyWith(duration: d);
    s.dur.add(d);
  }

  void setBuffer(Duration b) {
    current = current.copyWith(buffer: b);
    s.buf.add(b);
  }

  void setPlaying(bool v) {
    current = current.copyWith(playing: v);
    s.playing_.add(v);
  }

  @override
  PlatformPlayer? platform;
  @override
  PlayerStream get stream => s;
  @override
  PlayerState get state => current;
  @override
  Future<void> seek(Duration d) async => seeks.add(d);
  @override
  Future<void> playOrPause({bool notify = true}) async => playPauseCalls++;
  @override
  Future<void> setRate(double r) async => rates.add(r);
  @override
  Future<void> setVolume(double v) async => volumes.add(v);
  @override
  Future<void> setPlaylistMode(PlaylistMode mode) async {
    modes.add(mode);
    current = PlayerState(
      playlist: current.playlist,
      duration: current.duration,
      position: current.position,
      buffer: current.buffer,
      playing: current.playing,
      playlistMode: mode,
    );
  }
}

/// Контролер-імітація: записує команди mpv і сповіщення, без справжнього рушія.
class FakeController extends Fake implements PlayerStateController {
  FakeController({KeyScheme scheme = KeyScheme.standard}) : keyScheme = scheme {
    _anime4k = Anime4kController(
      command: (args) async => commands.add(args),
      osd: (message, {duration}) => osdLog.add(message),
    );
  }

  final FakePlayer fakePlayer = FakePlayer();
  final List<List<String>> commands = [];
  final Map<String, String> props = {};
  final List<OsdMessage> osdLog = [];
  final List<double> volumeDeltas = [];
  int interactions = 0;
  int shortcutHelpCalls = 0;
  int screenshots = 0;
  int fullscreenToggles = 0;
  int muteToggles = 0;
  int alwaysOnTopToggles = 0;
  int homeReturns = 0;
  bool home = false;
  final List<String> hwdecChanges = [];

  @override
  String currentHwdec = 'mediacodec-copy';
  @override
  final List<String> mpvLogs = ['[cplayer] test log line'];
  @override
  Future<void> changeHwdec(String newHwdec) async {
    hwdecChanges.add(newHwdec);
    currentHwdec = newHwdec;
  }

  late final Anime4kController _anime4k;

  @override
  Anime4kController get anime4k => _anime4k;
  @override
  KeyScheme keyScheme;
  @override
  late final PlayerActions actions = PlayerActions(this);
  @override
  Player get player => fakePlayer;
  @override
  bool get isHome => home;
  @override
  bool get isFullscreen => false;
  @override
  bool get showStatsOverlay => false;
  @override
  String? get activeDrawer => null;
  @override
  SidePanelType? get activeSidePanel => null;
  @override
  VoidCallback? onShowShortcuts;

  @override
  void handleInteraction() => interactions++;
  @override
  void setKeyScheme(KeyScheme scheme) => keyScheme = scheme;
  @override
  void refreshSettings() {}

  @override
  void refreshOrientationPreference() {}
  @override
  void setVolumeDelta(double delta) => volumeDeltas.add(delta);
  @override
  void toggleMute() => muteToggles++;
  @override
  Future<void> toggleFullscreen() async => fullscreenToggles++;
  @override
  Future<void> toggleAlwaysOnTop() async => alwaysOnTopToggles++;
  @override
  Future<void> takeScreenshot({bool withSubtitles = true}) async => screenshots++;
  @override
  Future<void> returnToHome() async => homeReturns++;

  @override
  Future<void> mpv(List<String> args) async => commands.add(args);
  @override
  Future<String> mpvGet(String property) async => props[property] ?? '';

  @override
  void showOsd(
    String title, {
    IconData icon = Symbols.info_rounded,
    String? detail,
    List<String> keys = const [],
    double? progress,
    bool isError = false,
    Duration? duration,
    bool onlyWhenControlsHidden = false,
  }) {
    osdLog.add(OsdMessage(icon: icon, title: title, detail: detail, keys: keys, progress: progress, isError: isError));
  }
}

/// Скидає тему до стандартної (темна), щоб тести не залежали одне від одного
void resetTheme() {
  uiTheme.setThemeMode('dark');
}

/// Чекає на справжній ввід-вивід (файли, assets), який у FakeAsync сам не просувається
Future<void> settle(WidgetTester tester, bool Function() done, {int maxTries = 150}) async {
  for (var i = 0; i < maxTries && !done(); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
  expect(done(), isTrue, reason: 'асинхронна операція не завершилась');
}
