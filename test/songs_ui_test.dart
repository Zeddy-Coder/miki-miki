// The song card over the video: in the song's first seconds and with the controls, not under a menu, a tap opens
// «Пісня»; the menu: the song under the opening / ending in «Розділи», where to listen to it.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miki_miki/models/media_models.dart';
import 'package:miki_miki/services/hikka_nav.dart';
import 'package:miki_miki/services/songs/song_service.dart';
import 'package:miki_miki/services/songs/theme_songs.dart';
import 'package:miki_miki/services/storage_service.dart';
import 'package:miki_miki/widgets/settings_drawer.dart';
import 'package:miki_miki/widgets/song_card.dart';

import 'support/fakes.dart';
import 'support/remote_fakes.dart';

const chapters = [
  VideoChapter(title: 'Episode', startTime: Duration.zero, endTime: Duration(seconds: 33)),
  VideoChapter(title: 'Opening', startTime: Duration(seconds: 33), endTime: Duration(seconds: 123)),
  VideoChapter(title: 'Episode', startTime: Duration(seconds: 123), endTime: Duration(seconds: 1300)),
  VideoChapter(title: 'Ending', startTime: Duration(seconds: 1300), endTime: Duration(seconds: 1390)),
  VideoChapter(title: 'Episode', startTime: Duration(seconds: 1390)),
];

final op = const ThemeSong(kind: SongKind.op, title: 'Yuusha', native: '勇者', artists: ['YOASOBI'], sequence: 1)
    .withLinks({MusicApp.spotify: 'https://open.spotify.com/track/x'});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadTestFonts);
  tearDown(() => StorageService.saveShowThemeSongs(true));

  group('The card', () {
    late FakePlayer player;
    late ValueNotifier<EpisodeSongs?> songs;
    final opened = <SongKind>[];

    Future<void> pump(WidgetTester t, {bool controls = false, bool hidden = false}) async {
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(children: [
            SongCard(
              scale: 1,
              showControls: controls,
              hidden: hidden,
              player: player,
              chapters: chapters,
              songs: songs,
              onOpen: (kind, key) => opened.add(kind),
            ),
          ]),
        ),
      ));
      await t.pump(const Duration(milliseconds: 400));
      await t.pump(const Duration(milliseconds: 300)); // the fade out runs from the frame that hid it
    }

    Future<void> at(WidgetTester t, int seconds) async {
      player.tickPosition(Duration(seconds: seconds));
      await t.pump(const Duration(milliseconds: 400));
      await t.pump(const Duration(milliseconds: 300));
    }

    setUp(() {
      player = FakePlayer();
      songs = ValueNotifier(EpisodeSongs(key: 'k', op: op));
      opened.clear();
    });

    testWidgets('the first seconds of the opening, then only with the controls', (t) async {
      t.view.physicalSize = const Size(1280, 720);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await pump(t);
      await at(t, 10);
      expect(find.text('Yuusha'), findsNothing, reason: 'not in the opening yet');
      await at(t, 35);
      expect(find.text('Yuusha'), findsOneWidget);
      expect(find.text('YOASOBI'), findsOneWidget);
      await at(t, 50);
      expect(find.text('Yuusha'), findsNothing, reason: 'after its first seconds the card steps away');
      await pump(t, controls: true);
      expect(find.text('Yuusha'), findsOneWidget, reason: 'with the controls it is back');
      await pump(t, controls: true, hidden: true);
      expect(find.text('Yuusha'), findsNothing, reason: 'not under a menu');
      await pump(t, controls: true);
      await t.tap(find.text('Yuusha'));
      expect(opened, [SongKind.op]);
      // No ending song known: nothing over the ending
      await at(t, 1302);
      expect(find.text('Yuusha'), findsNothing);
      await at(t, 40);
      StorageService.saveShowThemeSongs(false);
      await pump(t, controls: true);
      expect(find.text('Yuusha'), findsNothing, reason: 'turned off in the settings');
    });
  });

  group('The menu', () {
    Future<(Rig, List<String>)> drawer(WidgetTester t, String page) async {
      t.view.physicalSize = const Size(1280, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final service = SongService(persist: false, malId: (k) async => null, enabled: () => true);
      final rig = Rig(songs: service);
      service.current.value = EpisodeSongs(key: 'k', op: op);
      final subs = <String>[];
      final c = FakeController();
      c.fakePlayer.tickPosition(const Duration(seconds: 40));
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Stack(children: [
            SettingsDrawer(
              scale: 1,
              screenWidth: 1280,
              drawerAnchorPixelX: 300,
              activeDrawer: page,
              activeDrawerPrev: null,
              player: c.fakePlayer,
              currentSpeed: 1,
              currentHwdec: 'auto',
              subtitleTracks: const [],
              audioTracks: const [],
              chapters: chapters,
              scrollController: ScrollController(),
              onClose: () {},
              onBack: () {},
              onOpenSubDrawer: subs.add,
              onSpeedSelected: (_) {},
              onSubtitleSelected: (_) {},
              onAudioSelected: (_) {},
              onHwdecSelected: (_) {},
              onOpenChaptersSidePanel: () {},
              onOpenStats: () {},
              anime4k: c.anime4k,
              remote: rig.driver,
            ),
          ]),
        ),
      ));
      await t.pump(const Duration(milliseconds: 400));
      return (rig, subs);
    }

    testWidgets('«Розділи»: the song under the opening, its cover opens «Пісня»', (t) async {
      final (_, subs) = await drawer(t, 'chapters');
      expect(find.text('Yuusha · YOASOBI'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('chapter-song-op')));
      expect(subs, ['song-op']);
    });

    testWidgets('«Пісня»: which one, the title, where to listen (the song itself or a search)', (t) async {
      final urls = <String>[];
      final keep = HikkaNav.instance.urlOpener;
      HikkaNav.instance.urlOpener = (u) async {
        urls.add(u);
        return true;
      };
      addTearDown(() => HikkaNav.instance.urlOpener = keep);
      await drawer(t, 'song-op');
      expect(find.text('Опенінґ 1'), findsOneWidget);
      expect(find.text('Yuusha'), findsOneWidget);
      expect(find.text('YOASOBI'), findsOneWidget);
      for (final name in ['Spotify', 'YouTube Music', 'Apple Music', 'YouTube']) {
        expect(find.text(name), findsOneWidget);
      }
      expect(find.text('пісня'), findsOneWidget, reason: 'Spotify: the song itself');
      expect(find.text('пошук'), findsNWidgets(3));
      await t.tap(find.text('Spotify'));
      await t.tap(find.text('YouTube Music'));
      expect(urls, ['https://open.spotify.com/track/x', 'https://music.youtube.com/search?q=YOASOBI%20%E5%8B%87%E8%80%85']);
    });

    testWidgets('«Пісня» without a song: a word, not an empty menu', (t) async {
      await drawer(t, 'song-ed');
      expect(find.textContaining('не знайдено'), findsOneWidget);
    });
  });
}
