// A preview of the opening's song in the player, with the real widgets: the card over the video (the cover with a
// moving equalizer), «Пісня» on a phone and a PC, the songs in «Розділи». The covers are neutral placeholders (the app
// takes the real ones from the stores). Not a check: it runs only with PREVIEW=1 and writes test/preview/songs_*.png
// (PREVIEW=1 flutter test --update-goldens test/songs_preview_test.dart).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:miki_miki/models/media_models.dart';
import 'package:miki_miki/services/hikka_images.dart';
import 'package:miki_miki/services/songs/song_service.dart';
import 'package:miki_miki/services/songs/theme_songs.dart';
import 'package:miki_miki/services/ui_theme_service.dart';
import 'package:miki_miki/utils/platform_info.dart';
import 'package:miki_miki/widgets/mobile_sheet.dart';
import 'package:miki_miki/widgets/settings_drawer.dart';
import 'package:miki_miki/widgets/skip_button.dart';
import 'package:miki_miki/widgets/song_card.dart';

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
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (kPreview) await _fonts();
  });

  testWidgets('songs: card, «Пісня», «Розділи»', (tester) async {
    if (!kPreview) return;
    uiTheme.setThemeMode('dark');
    final frame = MemoryImage(File('$frames/frame2.jpg').readAsBytesSync());
    final frameWide = MemoryImage(File('$frames/frame3.jpg').readAsBytesSync());
    // The covers come from a store of their own (placeholders instead of the network)
    final covers = {'https://covers/a.jpg': File('$frames/cover_a.png').readAsBytesSync(), 'https://covers/b.jpg': File('$frames/cover_b.png').readAsBytesSync()};
    final dir = Directory.systemTemp.createTempSync('song_covers');
    final keepStore = HikkaImageStore.instance;
    HikkaImageStore.instance = HikkaImageStore(dir: dir, fetcher: (url) async => covers[url]!);
    addTearDown(() {
      HikkaImageStore.instance = keepStore;
      dir.deleteSync(recursive: true);
      tester.view.reset();
      AppPlatform.debugMobile = null;
    });

    final service = SongService(persist: false, malId: (k) async => null, enabled: () => true);
    final rig = Rig(songs: service);
    service.current.value = EpisodeSongs(
      key: 'k',
      op: const ThemeSong(kind: SongKind.op, title: 'Yuusha', artists: ['YOASOBI'], sequence: 1).withLinks({MusicApp.spotify: 'https://open.spotify.com/track/x', MusicApp.youtube: 'https://www.youtube.com/watch?v=y'}),
      ed: const ThemeSong(kind: SongKind.ed, title: 'Anytime Anywhere', artists: ['milet'], sequence: 1),
      art: const {SongKind.op: SongArt(cover: 'https://covers/a.jpg', appleMusic: 'https://music.apple.com/jp/album/a/1?i=2'), SongKind.ed: SongArt(cover: 'https://covers/b.jpg')},
    );
    const chapters = [
      VideoChapter(title: 'Episode', startTime: Duration.zero, endTime: Duration(seconds: 33)),
      VideoChapter(title: 'Opening', startTime: Duration(seconds: 33), endTime: Duration(seconds: 123)),
      VideoChapter(title: 'Episode', startTime: Duration(seconds: 123), endTime: Duration(seconds: 1330)),
      VideoChapter(title: 'Ending', startTime: Duration(seconds: 1330), endTime: Duration(seconds: 1420)),
      VideoChapter(title: 'Episode', startTime: Duration(seconds: 1420)),
    ];
    FakeController controller(Duration pos) {
      final c = FakeController();
      c.fakePlayer.current = PlayerState(playlist: Playlist([Media('remote://frieren-6')]), duration: const Duration(seconds: 1450), position: pos, playing: true);
      return c;
    }

    Future<void> decode(List<ImageProvider> images) async {
      await tester.runAsync(() async {
        for (final i in [...images, const HikkaImage('https://covers/a.jpg'), const HikkaImage('https://covers/b.jpg')]) {
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

    Widget video(ImageProvider image) => Positioned.fill(child: Image(image: image, fit: BoxFit.cover));
    Widget drawer(FakeController c, String page, {required bool sheet}) => SettingsDrawer(
          sheet: sheet,
          scale: sheet ? AppPlatform.mobileScale : 1,
          screenWidth: 1280,
          drawerAnchorPixelX: 120,
          drawerIsTop: false,
          activeDrawer: page,
          activeDrawerPrev: page == 'chapters' ? 'settings' : null,
          player: c.fakePlayer,
          currentSpeed: 1,
          currentHwdec: 'auto',
          subtitleTracks: const [],
          audioTracks: const [],
          chapters: chapters,
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
          remote: rig.driver,
        );

    // П1: the phone, the opening's first seconds: the song on the left, "Пропустити опенінґ" on the right
    var c = controller(Duration.zero);
    await phone(Stack(children: [
      video(frame),
      SkipButton(touch: true, scale: AppPlatform.mobileScale, showControls: false, player: c.fakePlayer, chapters: chapters, dismissedChapterStartTime: null),
      SongCard(touch: true, scale: AppPlatform.mobileScale, showControls: false, player: c.fakePlayer, chapters: chapters, songs: service.current, onOpen: (_, _) {}),
    ]));
    c.fakePlayer.tickPosition(const Duration(seconds: 36));
    c.fakePlayer.s.playing_.add(true);
    await decode([frame]);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('preview/songs_p1.png'));
    // The equalizer moving: frames for an animation
    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 70));
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('preview/songs_eq_${i.toString().padLeft(2, '0')}.png'));
    }

    // П2: the phone, «Пісня» after a tap on the card
    c = controller(const Duration(seconds: 36));
    await phone(Stack(children: [
      video(frame),
      MobileSheetFrame(open: true, onDismiss: () {}, child: drawer(c, 'song-op', sheet: true)),
    ]));
    await decode([frame]);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('preview/songs_p2.png'));

    // П3: the phone, «Розділи»: the songs under the opening and the ending, the playing one with the equalizer
    c = controller(const Duration(seconds: 40));
    c.fakePlayer.s.playing_.add(true);
    await phone(Stack(children: [
      video(frame),
      MobileSheetFrame(open: true, onDismiss: () {}, child: drawer(c, 'chapters', sheet: true)),
    ]));
    await decode([frame]);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('preview/songs_p3.png'));

    // П4: the PC, the card with the controls hidden; П5: «Пісня» from it
    AppPlatform.debugMobile = false;
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    c = controller(Duration.zero);
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(children: [
          video(frameWide),
          SkipButton(scale: 1, showControls: false, player: c.fakePlayer, chapters: chapters, dismissedChapterStartTime: null),
          SongCard(scale: 1, showControls: false, player: c.fakePlayer, chapters: chapters, songs: service.current, onOpen: (_, _) {}),
        ]),
      ),
    ));
    c.fakePlayer.tickPosition(const Duration(seconds: 37));
    await decode([frameWide]);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('preview/songs_p4.png'));

    c = controller(const Duration(seconds: 37));
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(backgroundColor: Colors.black, body: Stack(children: [video(frameWide), drawer(c, 'song-op', sheet: false)])),
    ));
    await decode([frameWide]);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('preview/songs_p5.png'));
  });
}
