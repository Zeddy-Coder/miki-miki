// A preview of the player in the new style with a real video frame: for comparing with the concept П1–П6.
// Not a check: it runs only with PREVIEW=1 and writes test/preview/player_*.png
// (PREVIEW=1 flutter test --update-goldens test/player_preview_test.dart).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/gestures.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:media_kit/media_kit.dart';
import 'package:miki_miki/models/media_models.dart';
import 'package:miki_miki/services/osd_message.dart';
import 'package:miki_miki/services/ui_theme_service.dart';
import 'package:miki_miki/utils/platform_info.dart';
import 'package:miki_miki/widgets/controls_overlay.dart';
import 'package:miki_miki/widgets/mobile_controls.dart';
import 'package:miki_miki/widgets/mobile_sheet.dart';
import 'package:miki_miki/widgets/osd_toast.dart';
import 'package:miki_miki/widgets/settings_drawer.dart';
import 'package:miki_miki/widgets/side_panel.dart';
import 'package:miki_miki/widgets/skip_button.dart';

import 'support/fakes.dart';
import 'support/remote_fakes.dart';

const String frames = '/tmp/concept/player/img';
final bool kPreview = Platform.environment['PREVIEW'] == '1';

Future<ByteData> _bytes(String path) async => ByteData.sublistView(Uint8List.fromList(await File(path).readAsBytes()));

/// Fonts as on a phone: "Arial" falls back to the bundled Liberation Sans
Future<void> _fonts() async {
  for (final family in ['Arial', 'MikiSans']) {
    await (FontLoader(family)
          ..addFont(_bytes('assets/fonts/subtitle.ttf'))
          ..addFont(_bytes('assets/fonts/LiberationSans-Bold.ttf')))
        .load();
  }
  final home = Platform.environment['HOME'] ?? '/root';
  await (FontLoader('packages/material_symbols_icons/MaterialSymbolsRounded')
        ..addFont(_bytes('$home/.pub-cache/hosted/pub.dev/material_symbols_icons-4.2960.0/lib/fonts/MaterialSymbolsRounded.ttf')))
      .load();
}

/// A 24-minute episode with the usual chapters: the gaps fall at 9.6 %, 61 % and 94 %, as in the concept
final List<VideoChapter> _chapters = [
  const VideoChapter(title: 'Opening', startTime: Duration.zero, endTime: Duration(seconds: 138)),
  const VideoChapter(title: 'Частина А', startTime: Duration(seconds: 138), endTime: Duration(seconds: 878)),
  const VideoChapter(title: 'Частина Б', startTime: Duration(seconds: 878), endTime: Duration(seconds: 1354)),
  const VideoChapter(title: 'Анонс', startTime: Duration(seconds: 1354), endTime: Duration(minutes: 24)),
];

class _Vol extends ValueNotifier<VolumeState> {
  _Vol() : super(const VolumeState(65, false));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_fonts);

  late MemoryImage frame;
  late MemoryImage frameWide;
  setUpAll(() {
    frame = MemoryImage(File('$frames/frame2.jpg').readAsBytesSync());
    frameWide = MemoryImage(File('$frames/frame3.jpg').readAsBytesSync());
  });

  Future<void> decode(WidgetTester tester, List<ImageProvider> images) async {
    await tester.runAsync(() async {
      for (final i in images) {
        await precacheImage(i, tester.element(find.byType(Scaffold).first));
      }
    });
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 600));
  }

  FakeController controller({Duration pos = const Duration(seconds: 72), Duration buf = const Duration(seconds: 200), bool playing = true}) {
    final c = FakeController();
    c.fakePlayer.current = PlayerState(
      playlist: Playlist([Media('remote://frieren-6')]),
      duration: const Duration(minutes: 24),
      position: pos,
      buffer: buf,
      playing: playing,
    );
    return c;
  }

  Widget video(ImageProvider image, {double? height}) => Positioned.fill(
        child: ColoredBox(
          color: Colors.black,
          child: Center(child: SizedBox(height: height, width: double.infinity, child: Image(image: image, fit: BoxFit.cover))),
        ),
      );

  SettingsDrawer drawer(FakeController c, {required bool sheet, String active = 'settings', double scale = 1, double width = 0, double anchor = 0, Rig? rig}) => SettingsDrawer(
        sheet: sheet,
        scale: scale,
        screenWidth: width,
        drawerAnchorPixelX: anchor,
        drawerIsTop: true,
        activeDrawer: active,
        activeDrawerPrev: null,
        player: c.fakePlayer,
        currentSpeed: 1.0,
        currentHwdec: 'd3d11va-copy',
        subtitleTracks: const [
          CachedSubtitleTrack(track: SubtitleTrack('1', 'Повні', 'ukr'), formattedTitle: 'Українська · Повні'),
        ],
        audioTracks: const [
          CachedAudioTrack(track: AudioTrack('1', 'Stereo', 'jpn'), formattedTitle: 'Японська · Stereo'),
        ],
        chapters: _chapters,
        scrollController: ScrollController(),
        onClose: () {},
        onBack: () {},
        onOpenSubDrawer: (_) {},
        onSpeedSelected: (_) {},
        onSubtitleSelected: (_) {},
        onAudioSelected: (_) {},
        onHwdecSelected: (_) {},
        onOpenChaptersSidePanel: () {},
        onOpenStats: () {},
        onOpenAppSettings: () {},
        anime4k: c.anime4k,
        remote: rig?.driver,
      );

  MobileControls phoneControls(FakeController c) => MobileControls(
        visible: true,
        player: c.fakePlayer,
        title: 'Проводжальниця Фрірен',
        subtitle: 'Серія 6 з 28 · Inari',
        chapters: _chapters,
        currentSpeed: 1.0,
        anime4kActive: true,
        subtitlesOn: false,
        hasQueue: true,
        pipSupported: true,
        rotationLocked: false,
        drawerOwner: null,
        isEpisodesOpen: false,
        seekStep: 10,
        onBack: () {},
        onInfo: () {},
        onPip: () {},
        onRotate: () {},
        onRotateAuto: () {},
        onSettings: () {},
        onSpeed: () {},
        onAnime4k: () {},
        onAnime4kToggle: () {},
        onSubs: () {},
        onAudio: () {},
        onEpisodes: () {},
      );

  /// A phone at the person's density; [size] in dp
  Future<void> phone(WidgetTester tester, Size size, EdgeInsets pad, Widget scene) async {
    const dpr = 2.8;
    tester.view.physicalSize = Size(size.width * dpr, size.height * dpr);
    tester.view.devicePixelRatio = dpr;
    addTearDown(tester.view.reset);
    AppPlatform.debugMobile = true;
    addTearDown(() => AppPlatform.debugMobile = null);
    uiTheme.setThemeMode('dark');
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      builder: (context, w) => MediaQuery(data: MediaQuery.of(context).copyWith(padding: pad, viewPadding: pad), child: w!),
      home: Scaffold(backgroundColor: Colors.black, body: scene),
    ));
  }

  testWidgets('П1–П4: телефон', (tester) async {
    if (!kPreview) return;
    const land = Size(866, 390);
    const landPad = EdgeInsets.fromLTRB(30, 0, 0, 0);

    // П1: the controls and "Пропустити опенінг"
    var c = controller();
    await phone(tester, land, landPad, Stack(children: [
      video(frame),
      SkipButton(touch: true, scale: AppPlatform.mobileScale, showControls: true, player: c.fakePlayer, chapters: _chapters, dismissedChapterStartTime: null),
      phoneControls(c),
    ]));
    // "Пропустити опенінг" is offered in the first 15 s of the opening
    c.fakePlayer.tickPosition(const Duration(seconds: 8));
    await decode(tester, [frame]);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('preview/player_p1.png'));

    // П2: the settings sheet on the right (site episodes: "Якість" first)
    c = controller();
    final rig = Rig(episodes: [for (var i = 1; i <= 28; i++) i], openTimeout: const Duration(seconds: 30));
    await tester.runAsync(() => rig.driver.start(rig.launch(epKey: '6')));
    rig.started();
    await phone(tester, land, landPad, Stack(children: [
      video(frame),
      phoneControls(c),
      MobileSheetFrame(open: true, onDismiss: () {}, child: drawer(c, sheet: true, scale: AppPlatform.mobileScale, rig: rig)),
    ]));
    await decode(tester, [frame]);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('preview/player_p2.png'));

    // П3: "Перегляд" (episodes 1–5 watched, the 6th playing)
    for (var i = 1; i <= 5; i++) {
      rig.store.setWatched('hikka:test', '$i', true);
    }
    await phone(tester, land, landPad, Stack(children: [
      video(frame),
      phoneControls(c),
      MobileSheetFrame(
        open: true,
        onDismiss: () {},
        child: SidePanel(
          sheet: true,
          scale: AppPlatform.mobileScale,
          type: SidePanelType.episodes,
          player: c.fakePlayer,
          playlistItems: const [],
          currentPlaylistIndex: 5,
          chapters: _chapters,
          onClose: () {},
          onAddMedia: () {},
          onEpisodeSelected: (_) {},
          onChapterSelected: (_) {},
          onQueueReorder: (a, b) {},
          onQueueRemove: (_) {},
          onQueueClear: () {},
          remote: rig.driver,
        ),
      ),
    ]));
    await decode(tester, [frame]);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('preview/player_p3.png'));
    rig.driver.stop();

    // П4: portrait, the video in the middle
    c = controller(pos: const Duration(seconds: 492), buf: const Duration(seconds: 662));
    await phone(tester, const Size(390, 866), const EdgeInsets.fromLTRB(0, 34, 0, 18), Stack(children: [
      video(frame, height: 219),
      phoneControls(c),
    ]));
    await decode(tester, [frame]);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('preview/player_p4.png'));
  });

  testWidgets('П5–П6: ПК', (tester) async {
    if (!kPreview) return;
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    uiTheme.setThemeMode('dark');
    final c = controller(pos: const Duration(seconds: 492), buf: const Duration(seconds: 662));
    final osd = ValueNotifier<OsdMessage?>(null);
    final settingsKey = GlobalKey();

    Widget desktop({String? menu}) => MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            backgroundColor: Colors.black,
            body: Stack(children: [
              video(frameWide),
              ControlsOverlay(
                scale: 1.0,
                showControls: true,
                isSpeeding: false,
                isDraggingFile: false,
                currentTitle: 'Проводжальниця Фрірен',
                currentSubtitle: 'Серія 6 з 28 · Inari · 1080p',
                player: c.fakePlayer,
                currentSpeed: 1.0,
                volume: _Vol(),
                isFullscreen: false,
                activeDrawer: menu,
                activeDrawerPrev: null,
                drawerOwner: menu,
                isEpisodesOpen: false,
                drawerAnchorPixelX: 1180,
                drawerIsTop: true,
                chapters: _chapters,
                subtitleTracks: const [
                  CachedSubtitleTrack(track: SubtitleTrack('1', 'Повні', 'ukr'), formattedTitle: 'Українська'),
                ],
                audioTracks: const [
                  CachedAudioTrack(track: AudioTrack('1', 'Stereo', 'jpn'), formattedTitle: 'Японська'),
                ],
                currentHwdec: 'd3d11va-copy',
                drawerScrollController: ScrollController(),
                anime4k: c.anime4k,
                settingsKey: settingsKey,
                anime4kKey: GlobalKey(),
                subsKey: GlobalKey(),
                audioKey: GlobalKey(),
                speedKey: GlobalKey(),
                volumeKey: GlobalKey(),
                onMiniPlayer: () {},
                onCollapse: () {},
                onClosePlayer: () {},
                onOpenFile: () {},
                onToggleFullscreen: () {},
                onToggleMute: () {},
                onVolumeChanged: (_) {},
                onSettingsTap: () {},
                onInfoTap: () {},
                onEpisodesTap: () {},
                onChaptersTap: () {},
                onAnime4kTap: () {},
                onAnime4kSecondaryTap: () {},
                onSubsTap: () {},
                onAudioTap: () {},
                onSpeedTap: () {},
                onSpeedSecondaryTap: () {},
                onCloseDrawer: () {},
                onBackDrawer: () {},
                onOpenSubDrawer: (_) {},
                onSpeedSelected: (_) {},
                onSubtitleSelected: (_) {},
                onAudioSelected: (_) {},
                onHwdecSelected: (_) {},
                onOpenStats: () {},
                onOpenAppSettings: () {},
              ),
              OsdToast(scale: 1.0, message: osd),
            ]),
          ),
        );

    // П5: the controls, the cursor over the bar (the frame preview needs a local file: a time and a chapter here)
    await tester.pumpWidget(desktop());
    await decode(tester, [frameWide]);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(640, 300));
    final bar = tester.getRect(find.byKey(const ValueKey('dock-time')));
    await mouse.moveTo(Offset(24 + (1232 - 24) * 0.36, bar.top - 30));
    await tester.pump(const Duration(milliseconds: 400));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('preview/player_p5.png'));
    await mouse.moveTo(const Offset(640, 300));
    await tester.pump(const Duration(milliseconds: 400));

    // П6: the menu from the gear and the volume OSD
    osd.value = const OsdMessage(icon: Symbols.volume_up_rounded, title: 'Гучність', detail: '65%', progress: 0.65);
    await tester.pumpWidget(desktop(menu: 'settings'));
    await decode(tester, [frameWide]);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('preview/player_p6.png'));
    await mouse.removePointer();
  });
}
