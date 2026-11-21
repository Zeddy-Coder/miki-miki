// A preview of skips without the site's times: the chapters menu with AniSkip's times (safe, then marked by hand),
// with the opening heard and the team's intro, "Пропустити заставку", the setting. Not a check: it runs only with
// PREVIEW=1 and writes test/preview/skips_*.png (PREVIEW=1 flutter test --update-goldens test/skips_preview_test.dart).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:miki_miki/models/media_models.dart';
import 'package:miki_miki/services/network_status.dart';
import 'package:miki_miki/services/remote_playback.dart';
import 'package:miki_miki/services/skips/anime_skip.dart';
import 'package:miki_miki/services/skips/aniskip.dart';
import 'package:miki_miki/services/skips/skip_profiles.dart';
import 'package:miki_miki/services/skips/skip_service.dart';
import 'package:miki_miki/services/ui_theme_service.dart';
import 'package:miki_miki/utils/platform_info.dart';
import 'package:miki_miki/widgets/app_settings_dialog.dart';
import 'package:miki_miki/widgets/mobile_sheet.dart';
import 'package:miki_miki/widgets/settings_drawer.dart';
import 'package:miki_miki/widgets/skip_button.dart';

import 'support/fakes.dart';
import 'support/remote_fakes.dart';

const String frames = '/tmp/concept/player/img';
final bool kPreview = Platform.environment['PREVIEW'] == '1';

Future<ByteData> _bytes(String path) async => ByteData.sublistView(Uint8List.fromList(await File(path).readAsBytes()));

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (kPreview) await _fonts();
  });

  testWidgets('skips: menu, button, setting', (tester) async {
    if (!kPreview) return;
    final frame = MemoryImage(File('$frames/frame2.jpg').readAsBytesSync());
    final frameWide = MemoryImage(File('$frames/frame3.jpg').readAsBytesSync());
    uiTheme.setThemeMode('dark');

    // AniSkip knows the episode on a 1420 s version; our videos are 1450 s (an 8 s intro + credits)
    final box = <String, dynamic>{};
    final profiles = SkipProfiles(load: () => box, save: (m) => box.addAll(jsonDecode(jsonEncode(m)) as Map<String, dynamic>));
    final dir = Directory.systemTemp.createTempSync('skips_preview');
    addTearDown(() => dir.deleteSync(recursive: true));
    final service = SkipService(
      aniskip: AniSkip(
        persist: false,
        get: (u) async => (
          200,
          jsonEncode({
            'found': true,
            'results': [
              {'interval': {'startTime': 25.0, 'endTime': 85.0}, 'skipType': 'op', 'skipId': 'op', 'episodeLength': 1420.0},
              {'interval': {'startTime': 1330.0, 'endTime': 1410.0}, 'skipType': 'ed', 'skipId': 'ed', 'episodeLength': 1420.0},
            ],
          }),
        ),
      ),
      animeSkip: AnimeSkip(persist: false, post: (u, body, headers) async => (404, '{"data":{"Media":null}}')),
      profiles: profiles,
      malId: (k) async => 52991,
      listenOn: () => false,
      network: () => NetworkStatus()..apply(online: true),
      printsDir: dir.path,
    );
    final rig = Rig(episodes: [for (var i = 1; i <= 28; i++) i], openTimeout: const Duration(seconds: 30), skips: service);
    await tester.runAsync(() => rig.driver.start(rig.launch(epKey: '6')));
    rig.started(dur: const Duration(seconds: 1450));
    await tester.pump();

    FakeController controller(Duration pos) {
      final c = FakeController();
      c.fakePlayer.current = PlayerState(
        playlist: Playlist([Media('remote://frieren-6')]),
        duration: const Duration(seconds: 1450),
        position: pos,
        playing: true,
      );
      return c;
    }

    final scroll = ScrollController();
    Widget drawer(FakeController c, {required bool sheet, double scale = 1}) => ListenableBuilder(
          listenable: rig.driver,
          builder: (context, _) => SettingsDrawer(
            sheet: sheet,
            scale: scale,
            screenWidth: 1280,
            drawerAnchorPixelX: 1180,
            drawerIsTop: true,
            activeDrawer: 'chapters',
            activeDrawerPrev: 'settings',
            player: c.fakePlayer,
            currentSpeed: 1.0,
            currentHwdec: 'auto',
            subtitleTracks: const [],
            audioTracks: const [],
            chapters: rig.driver.chapters,
            scrollController: scroll,
            onClose: () {},
            onBack: () {},
            onOpenSubDrawer: (_) {},
            onSpeedSelected: (_) {},
            onSubtitleSelected: (_) {},
            onAudioSelected: (_) {},
            onHwdecSelected: (_) {},
            onOpenChaptersSidePanel: () {},
            onOpenStats: () {},
            anime4k: c.anime4k,
            remote: rig.driver,
          ),
        );

    Widget video(ImageProvider image) => Positioned.fill(child: Image(image: image, fit: BoxFit.cover));

    Future<void> decode(List<ImageProvider> images) async {
      await tester.runAsync(() async {
        for (final i in images) {
          await precacheImage(i, tester.element(find.byType(Scaffold).first));
        }
      });
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 600));
    }

    Future<void> phone(Widget scene) async {
      const dpr = 2.8;
      tester.view.physicalSize = const Size(866 * dpr, 390 * dpr);
      tester.view.devicePixelRatio = dpr;
      AppPlatform.debugMobile = true;
      const pad = EdgeInsets.fromLTRB(30, 0, 0, 0);
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        builder: (context, w) => MediaQuery(data: MediaQuery.of(context).copyWith(padding: pad, viewPadding: pad), child: w!),
        home: Scaffold(backgroundColor: Colors.black, body: scene),
      ));
    }

    addTearDown(() {
      tester.view.reset();
      AppPlatform.debugMobile = null;
    });

    // С1: the phone, AniSkip's times while the shift is unknown (scrolled to the controls under the chapters)
    var c = controller(const Duration(seconds: 34));
    await phone(Stack(children: [
      video(frame),
      MobileSheetFrame(open: true, onDismiss: () {}, child: drawer(c, sheet: true, scale: AppPlatform.mobileScale)),
    ]));
    await decode([frame]);
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('preview/skips_p1.png'));

    // С2: "Опенінґ почався тут" pressed at 0:34 — exact, by hand, for every episode of the dub
    await tester.tap(find.text('Опенінґ почався тут'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('preview/skips_p2.png'));

    // С3: the PC, the opening and the team's intro heard (exact, from AniSkip + listening)
    await rig.driver.resetSkipShift();
    profiles.observe('hikka:test', rig.driver.group!, 8, 'audio');
    profiles.setIntro('hikka:test', rig.driver.group!, 8);
    profiles.saveEpisode('hikka:test', rig.driver.group!, '6', const EpisodeListen(opStart: 33, opEnd: 93, intro: 8));
    await service.refresh();
    AppPlatform.debugMobile = false;
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    c = controller(const Duration(seconds: 3));
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(children: [video(frameWide), drawer(c, sheet: false)]),
      ),
    ));
    await decode([frameWide]);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('preview/skips_p3.png'));

    // С4: the phone, "Пропустити заставку" in the first seconds
    c = controller(Duration.zero);
    final chapters = chaptersFromTimestamps(service.current.value!.stamps, const Duration(seconds: 1450));
    await phone(Stack(children: [
      video(frame),
      SkipButton(touch: true, scale: AppPlatform.mobileScale, showControls: true, player: c.fakePlayer, chapters: chapters, dismissedChapterStartTime: null),
    ]));
    c.fakePlayer.tickPosition(const Duration(seconds: 2));
    await decode([frame]);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('preview/skips_p4.png'));

    // С5: the setting, on a phone in portrait
    const dpr = 2.8;
    tester.view.physicalSize = const Size(390 * dpr, 866 * dpr);
    tester.view.devicePixelRatio = dpr;
    AppPlatform.debugMobile = true;
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.black,
        body: AppSettingsDialog(scale: AppPlatform.mobileScale, controller: FakeController(), initialTab: AppSettingsDialog.tabPlayback),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.ensureVisible(find.text('Шукати опенінґ за звуком'));
    await tester.pump(const Duration(milliseconds: 600));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('preview/skips_p5.png'));
    // С6: the sound page on a phone (the audio delay row uses the same stepper)
    c = controller(const Duration(seconds: 34));
    AppPlatform.debugMobile = true;
    await phone(Stack(children: [
      video(frame),
      MobileSheetFrame(
        open: true,
        onDismiss: () {},
        child: SettingsDrawer(
          sheet: true,
          scale: AppPlatform.mobileScale,
          activeDrawer: 'audio',
          activeDrawerPrev: 'settings',
          player: c.fakePlayer,
          currentSpeed: 1.0,
          currentHwdec: 'auto',
          subtitleTracks: const [],
          audioTracks: const [CachedAudioTrack(track: AudioTrack('1', 'Stereo', 'ukr'), formattedTitle: 'Українська · Stereo')],
          chapters: const [],
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
          anime4k: c.anime4k,
          audioDelayKey: 'k',
        ),
      ),
    ]));
    await decode([frame]);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('preview/skips_p6.png'));
    rig.driver.stop();
  });
}
