import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miki_miki/models/media_models.dart';
import 'package:miki_miki/services/playback_clock.dart';
import 'package:miki_miki/utils/formatters.dart';
import 'package:miki_miki/widgets/app_dock_widgets.dart';
import 'package:miki_miki/widgets/bottom_dock.dart';
import 'package:miki_miki/widgets/skip_button.dart';

import 'support/fakes.dart';
import 'support/perf_harness.dart';

const _s = Duration(seconds: 1);

/// Емуляція потоку mpv: тіки з кроком [step] від поточної позиції на [span]
Future<void> play(WidgetTester tester, FakePlayer p, Duration span, {int hz = 60}) async {
  final dt = Duration(microseconds: (1000000 / hz).ceil());
  final n = (span.inMicroseconds / dt.inMicroseconds).ceil();
  var pos = p.state.position;
  for (var i = 0; i < n; i++) {
    pos += dt;
    p.tickPosition(pos);
    await tester.pump(dt);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadTestFonts();
  });

  group('PlaybackClock', () {
    test('один годинник на плеєр, різні плеєри — різні годинники', () {
      final a = FakePlayer(), b = FakePlayer();
      expect(identical(PlaybackClock.of(a), PlaybackClock.of(a)), isTrue);
      expect(identical(PlaybackClock.of(a), PlaybackClock.of(b)), isFalse);
    });

    test('початкові значення беруться зі стану плеєра', () {
      final p = FakePlayer();
      final c = PlaybackClock.of(p);
      expect(c.position.value, const Duration(minutes: 20));
      expect(c.seconds.value, 1200);
      expect(c.duration.value, const Duration(minutes: 90));
      expect(c.buffer.value, const Duration(minutes: 30));
      expect(c.permille.value, 222); // 20 / 90
      expect(c.playing.value, isFalse);
    });

    test('секунди змінюються раз на секунду, позиція — на кожну подію', () async {
      final p = FakePlayer();
      final c = PlaybackClock.of(p);
      var rawEvents = 0, secEvents = 0;
      c.position.addListener(() => rawEvents++);
      c.seconds.addListener(() => secEvents++);
      var pos = p.state.position;
      for (var i = 0; i < 180; i++) {
        pos += const Duration(microseconds: 16667);
        p.tickPosition(pos);
        await Future<void>.delayed(Duration.zero);
      }
      expect(rawEvents, 180);
      expect(secEvents, inInclusiveRange(2, 3)); // 3 секунди відтворення
    });

    test('проміле перераховується і при зміні тривалості', () async {
      final p = FakePlayer();
      final c = PlaybackClock.of(p);
      p.tickPosition(const Duration(minutes: 45));
      await Future<void>.delayed(Duration.zero);
      expect(c.permille.value, 500);
      p.setDuration(const Duration(minutes: 180));
      await Future<void>.delayed(Duration.zero);
      expect(c.permille.value, 250);
      p.setDuration(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(c.permille.value, 0);
    });

    test('буфер і стан «грає» проходять через годинник', () async {
      final p = FakePlayer();
      final c = PlaybackClock.of(p);
      p.setPlaying(true);
      p.setBuffer(const Duration(minutes: 40));
      await Future<void>.delayed(Duration.zero);
      expect(c.playing.value, isTrue);
      expect(c.buffer.value, const Duration(minutes: 40));
    });

    test('release відписує годинник від потоків', () async {
      final p = FakePlayer();
      final c = PlaybackClock.of(p);
      PlaybackClock.release(p);
      p.tickPosition(const Duration(minutes: 50));
      await Future<void>.delayed(Duration.zero);
      expect(c.position.value, const Duration(minutes: 20), reason: 'після release годинник не оновлюється');
      expect(identical(PlaybackClock.of(p), c), isFalse, reason: 'новий запит дає свіжий годинник');
    });
  });

  group('ClockValue', () {
    test('сповіщає лише при зміні результату', () async {
      final p = FakePlayer();
      final c = PlaybackClock.of(p);
      final v = c.derive<int>((pos, _) => pos.inMinutes ~/ 5);
      var n = 0;
      v.addListener(() => n++);
      var pos = p.state.position; // 20:00 → 4
      expect(v.value, 4);
      for (var i = 0; i < 600; i++) {
        pos += const Duration(milliseconds: 500); // 5 хвилин
        p.tickPosition(pos);
        await Future<void>.delayed(Duration.zero);
      }
      expect(v.value, 5);
      expect(n, 1);
      v.dispose();
      p.tickPosition(const Duration(minutes: 80));
      await Future<void>.delayed(Duration.zero);
      expect(n, 1, reason: 'після dispose слухачі не викликаються');
    });
  });

  group('ClockProgress', () {
    test('перемальовує лише при зсуві на крок (піксель)', () async {
      final p = FakePlayer();
      p.current = p.current.copyWith(position: Duration.zero, duration: const Duration(minutes: 90), buffer: Duration.zero);
      final c = PlaybackClock.of(p);
      final pr = ClockProgress(c, steps: 1000);
      var n = 0;
      pr.addListener(() => n++);
      var pos = Duration.zero;
      for (var i = 0; i < 24 * 60; i++) { // хвилина відтворення, 24 Гц
        pos += const Duration(microseconds: 41667);
        p.tickPosition(pos);
        await Future<void>.delayed(Duration.zero);
      }
      // 90 хв / 1000 кроків = 5,4 с на крок → за хвилину ≈ 11 сповіщень, а не 1440
      expect(n, inInclusiveRange(10, 12));
      expect(pr.played, closeTo(1 / 90, 0.0005));
      pr.dispose();
    });

    test('поки live вимкнено — тиша; при вмиканні один раз «догоняє»', () async {
      final p = FakePlayer();
      final c = PlaybackClock.of(p);
      final pr = ClockProgress(c, steps: 1000, live: false);
      var n = 0;
      pr.addListener(() => n++);
      p.tickPosition(const Duration(minutes: 60));
      await Future<void>.delayed(Duration.zero);
      expect(n, 0);
      expect(pr.played, closeTo(60 / 90, 1e-9), reason: 'значення актуальне, навіть без сповіщень');
      pr.live = true;
      expect(n, 1);
      pr.live = false;
      pr.live = true;
      expect(n, 1, reason: 'без змін повторно не сповіщає');
      pr.dispose();
    });

    test('буфер теж зсуває смужку', () async {
      final p = FakePlayer();
      final c = PlaybackClock.of(p);
      final pr = ClockProgress(c, steps: 1000);
      var n = 0;
      pr.addListener(() => n++);
      p.setBuffer(const Duration(minutes: 60));
      await Future<void>.delayed(Duration.zero);
      expect(n, 1);
      expect(pr.buffered, closeTo(60 / 90, 1e-9));
      pr.dispose();
    });

    test('нульова тривалість — нулі, без ділення на нуль', () {
      final p = FakePlayer();
      p.current = p.current.copyWith(duration: Duration.zero);
      final pr = ClockProgress(PlaybackClock.of(p));
      expect(pr.played, 0);
      expect(pr.buffered, 0);
      pr.dispose();
    });
  });

  group('ChapterMath', () {
    final chapters = sampleChapters();

    test('indexAt: останній розділ, що вже почався', () {
      expect(ChapterMath.indexAt(chapters, Duration.zero), 0);
      expect(ChapterMath.indexAt(chapters, const Duration(minutes: 1, seconds: 29)), 0);
      expect(ChapterMath.indexAt(chapters, const Duration(minutes: 1, seconds: 30)), 1);
      expect(ChapterMath.indexAt(chapters, const Duration(minutes: 100)), 5);
      expect(ChapterMath.indexAt(const [], const Duration(minutes: 1)), -1);
      expect(ChapterMath.indexAt(const [VideoChapter(title: 'x', startTime: Duration(seconds: 10))], const Duration(seconds: 5)), -1);
    });

    // Еталон: точна копія попередньої логіки SkipButton (до оптимізації)
    int oldSkip(List<VideoChapter> chs, Duration pos, Duration total) {
      VideoChapter? found;
      int foundIdx = -1;
      for (int i = 0; i < chs.length; i++) {
        final ch = chs[i];
        final nextStart = (i + 1 < chs.length) ? chs[i + 1].startTime : total;
        if (pos >= ch.startTime && pos < nextStart) {
          final t = AppFormatters.translateChapterTitle(ch.title).toLowerCase();
          if (t.contains('опенінґ') || t.contains('ендінґ') || t.contains('рекап') || t.contains('титри')) {
            found = VideoChapter(title: ch.title, startTime: ch.startTime, endTime: nextStart);
            foundIdx = i;
            break;
          }
        }
      }
      final show = found != null &&
          found.endTime != null &&
          (pos - found.startTime) >= Duration.zero &&
          (pos - found.startTime).inSeconds < 15 &&
          (found.endTime! - pos).inSeconds >= 2;
      return show ? foundIdx : -1;
    }

    test('skipIndexAt збігається зі старою логікою у кожній точці (крок 50 мс)', () {
      final sets = <List<VideoChapter>>[
        chapters,
        const [
          VideoChapter(title: 'OP', startTime: Duration.zero),
          VideoChapter(title: 'Episode', startTime: Duration(seconds: 90)),
          VideoChapter(title: 'Recap', startTime: Duration(minutes: 5)),
          VideoChapter(title: 'Credits', startTime: Duration(minutes: 23, seconds: 40)),
        ],
        const [VideoChapter(title: 'Ending', startTime: Duration(minutes: 1))],
        const [],
      ];
      const total = Duration(minutes: 24);
      for (final chs in sets) {
        final flags = ChapterMath.skippableFlags(chs);
        for (var ms = 0; ms <= total.inMilliseconds + 2000; ms += 50) {
          final pos = Duration(milliseconds: ms);
          expect(ChapterMath.skipIndexAt(chs, flags, pos, total), oldSkip(chs, pos, total), reason: 'pos=$pos');
        }
      }
    });
  });

  group('AppFormatters.translateChapterTitle', () {
    test('результат запам\'ятовується і не змінюється', () {
      expect(AppFormatters.translateChapterTitle('Opening'), 'Опенінґ');
      expect(AppFormatters.translateChapterTitle('Opening'), 'Опенінґ');
      expect(AppFormatters.translateChapterTitle('Chapter 3'), 'Розділ 3');
      expect(AppFormatters.translateChapterTitle('Part 2'), 'Частина 2');
      expect(AppFormatters.translateChapterTitle(''), 'Розділ');
      AppFormatters.clearTrackCache();
      expect(AppFormatters.translateChapterTitle('ED'), 'Ендінґ');
    });
  });

  group('Віджети', () {
    Future<(FakePlayer, ValueNotifier<bool>)> mount(
      WidgetTester tester, {
      bool visible = true,
      Duration at = const Duration(minutes: 10),
      List<VideoChapter>? chapters,
      Duration? dismissed,
    }) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final p = FakePlayer();
      p.current = p.current.copyWith(position: at, playing: true);
      final show = ValueNotifier<bool>(visible);
      addTearDown(show.dispose);
      await tester.pumpWidget(playerOverlayHarness(player: p, showControls: show, chapters: chapters ?? sampleChapters(), dismissed: dismissed));
      await tester.pump(const Duration(milliseconds: 600));
      return (p, show);
    }

    testWidgets('підписи часу: початок, оновлення раз на секунду', (tester) async {
      final (p, _) = await mount(tester, at: const Duration(minutes: 20));
      expect(find.text('20:00'), findsOneWidget);
      expect(find.text('1:30:00'), findsOneWidget);

      await play(tester, p, const Duration(milliseconds: 1100));
      expect(find.text('20:01'), findsOneWidget);
      expect(find.text('20:00'), findsNothing);

      await play(tester, p, const Duration(seconds: 3));
      expect(find.text('20:04'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('тривалість оновлюється, коли файл змінився', (tester) async {
      final (p, _) = await mount(tester);
      expect(find.text('1:30:00'), findsOneWidget);
      p.setDuration(const Duration(minutes: 24, seconds: 5));
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.text('24:05'), findsWidgets); // верхня панель + нижня
      expect(find.text('1:30:00'), findsNothing);
    });

    testWidgets('прихована панель не оновлюється, а при показі одразу показує актуальне', (tester) async {
      final (p, show) = await mount(tester, visible: false, at: const Duration(minutes: 20));
      final counter = RebuildCounter()..start();
      await play(tester, p, const Duration(seconds: 5));
      counter.stop();
      expect(counter.total, 0, reason: 'жодної перебудови, поки панель прихована: ${counter.byType}');

      show.value = true;
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('20:05'), findsOneWidget, reason: 'після показу панель відразу актуальна');
    });

    testWidgets('прихована панель не замовляє жодного кадру від подій позиції', (tester) async {
      final (p, _) = await mount(tester, visible: false);
      var pos = p.state.position;
      var frames = 0;
      for (var i = 0; i < 240; i++) {
        pos += const Duration(milliseconds: 16);
        p.tickPosition(pos);
        await tester.idle();
        if (tester.binding.hasScheduledFrame) frames++;
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(frames, 0);
    });

    testWidgets('смужка прогресу: перемальовується рідко, а прихована — взагалі ні', (tester) async {
      // Рахуємо малювання CustomPaint смужки
      int seekPaints = 0;
      void hook(RenderObject ro) {
        if (ro is RenderCustomPaint && ro.painter.runtimeType.toString() == '_SeekPainter') seekPaints++;
      }

      final (p, show) = await mount(tester, at: const Duration(minutes: 20));
      debugOnProfilePaint = hook;
      try {
        seekPaints = 0;
        await play(tester, p, const Duration(seconds: 6));
        final visiblePaints = seekPaints;
        // 90 хв на ~1000 пікселях → ≈ 5,4 с на піксель: за 6 с — не більше кількох малювань
        expect(visiblePaints, lessThanOrEqualTo(4), reason: 'малювань за 6 с: $visiblePaints');

        show.value = false;
        await tester.pump(const Duration(milliseconds: 600));
        seekPaints = 0;
        await play(tester, p, const Duration(seconds: 20));
        expect(seekPaints, 0, reason: 'прихована смужка не малюється');

        show.value = true;
        await tester.pump(const Duration(milliseconds: 16));
        await tester.pump(const Duration(milliseconds: 400));
        expect(seekPaints, greaterThan(0), reason: 'при показі смужка перемальовується й наздоганяє позицію');
      } finally {
        debugOnProfilePaint = null;
      }
    });

    testWidgets('чип розділу змінюється на межі розділів', (tester) async {
      final chs = const [
        VideoChapter(title: 'Chapter 1', startTime: Duration.zero),
        VideoChapter(title: 'Chapter 2', startTime: Duration(minutes: 5)),
      ];
      final (p, _) = await mount(tester, at: const Duration(minutes: 4, seconds: 58), chapters: chs);
      expect(find.text('Розділ 1'), findsOneWidget);
      expect(find.text('Розділ 2'), findsNothing);
      await play(tester, p, const Duration(seconds: 3));
      expect(find.text('Розділ 2'), findsOneWidget);
      expect(find.text('Розділ 1'), findsNothing);
    });

    testWidgets('без розділів чипа немає', (tester) async {
      await mount(tester, chapters: const []);
      expect(find.byIcon(Icons.chevron_right), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('«Пропустити»: з\'являється на початку опенінґу на 15 с і зникає', (tester) async {
      final (p, _) = await mount(tester, visible: false, at: const Duration(minutes: 1, seconds: 28));
      expect(find.textContaining('Пропустити'), findsNothing);

      await play(tester, p, const Duration(seconds: 3)); // 1:31 — всередині опенінґу
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Пропустити опенінґ'), findsOneWidget);

      await play(tester, p, const Duration(seconds: 12)); // 1:43 — ще в межах 15 с
      expect(find.text('Пропустити опенінґ'), findsOneWidget);

      await play(tester, p, const Duration(seconds: 4)); // 1:47 — вже пізніше 15 с
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.textContaining('Пропустити'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('«Пропустити»: клік перемотує до кінця розділу', (tester) async {
      // Панель прихована: кнопка внизу (при видимій панелі її нижню частину перекриває док)
      final (p, _) = await mount(tester, visible: false, at: const Duration(minutes: 1, seconds: 35));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.text('Пропустити опенінґ'));
      await tester.pump(const Duration(milliseconds: 16));
      expect(p.seeks, [const Duration(minutes: 3)]);
    });

    testWidgets('«Пропустити»: закритий розділ більше не пропонується', (tester) async {
      await mount(tester, visible: false, at: const Duration(minutes: 1, seconds: 35), dismissed: const Duration(minutes: 1, seconds: 30));
      expect(find.textContaining('Пропустити'), findsNothing);
    });

    testWidgets('«Пропустити»: останній розділ — не пропонується за 2 с до кінця', (tester) async {
      final chs = const [
        VideoChapter(title: 'Episode', startTime: Duration.zero),
        VideoChapter(title: 'Credits', startTime: Duration(minutes: 20)),
      ];
      final (p, _) = await mount(tester, visible: false, at: const Duration(minutes: 89, seconds: 40), chapters: chs);
      // 89:40 — це 69 хв після початку «Credits» (>15 с) → кнопки нема
      expect(find.textContaining('Пропустити'), findsNothing);
      p.tickPosition(const Duration(minutes: 20, seconds: 5));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Пропустити ендінґ'), findsOneWidget);
    });

    testWidgets('список розділів змінюється під час перегляду — кнопка реагує', (tester) async {
      final p = FakePlayer();
      p.current = p.current.copyWith(position: const Duration(minutes: 1, seconds: 35));
      final chapters = ValueNotifier<List<VideoChapter>>(const []);
      addTearDown(chapters.dispose);
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<List<VideoChapter>>(
            valueListenable: chapters,
            builder: (_, chs, __) => Stack(children: [
              SkipButton(scale: 1, showControls: false, player: p, chapters: chs, dismissedChapterStartTime: null),
            ]),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.textContaining('Пропустити'), findsNothing);
      chapters.value = sampleChapters();
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Пропустити опенінґ'), findsOneWidget);
      chapters.value = const [];
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.textContaining('Пропустити'), findsNothing);
    });

    testWidgets('AppProgressLine: ширина заливки = частка відтвореного', (tester) async {
      final p = FakePlayer();
      p.current = p.current.copyWith(position: const Duration(minutes: 45));
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 400,
              child: AppProgressLine(player: p, height: 3, trackColor: Colors.grey, fillColor: Colors.red),
            ),
          ),
        ),
      ));
      double fillWidth() {
        final boxes = tester.widgetList<Container>(find.descendant(of: find.byType(AppProgressLine), matching: find.byType(Container))).toList();
        // другий Container — заливка
        return tester.getSize(find.byWidget(boxes[1])).width;
      }

      expect(fillWidth(), closeTo(200, 0.5));
      p.tickPosition(const Duration(minutes: 90));
      await tester.pump(const Duration(milliseconds: 16));
      expect(fillWidth(), closeTo(400, 0.5));
      p.tickPosition(const Duration(minutes: 9));
      await tester.pump(const Duration(milliseconds: 16));
      expect(fillWidth(), closeTo(40, 0.5));
    });

    testWidgets('AppClockBuilder: live=false не будує, але актуальний при перебудові батьком', (tester) async {
      final n = ValueNotifier<int>(1);
      addTearDown(n.dispose);
      var builds = 0;
      final live = ValueNotifier<bool>(true);
      addTearDown(live.dispose);
      await tester.pumpWidget(MaterialApp(
        home: ValueListenableBuilder<bool>(
          valueListenable: live,
          builder: (_, l, __) => AppClockBuilder<int>(
            listenable: n,
            live: l,
            builder: (_, v) {
              builds++;
              return Text('v$v', textDirection: TextDirection.ltr);
            },
          ),
        ),
      ));
      expect(find.text('v1'), findsOneWidget);
      n.value = 2;
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.text('v2'), findsOneWidget);

      live.value = false;
      await tester.pump(const Duration(milliseconds: 16));
      final before = builds;
      n.value = 3;
      n.value = 4;
      await tester.pump(const Duration(milliseconds: 16));
      expect(builds, before, reason: 'поки live=false — жодних побудов');
      expect(find.text('v2'), findsOneWidget);

      live.value = true;
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.text('v4'), findsOneWidget, reason: 'при вмиканні показує актуальне значення');
    });

    testWidgets('BottomDock одразу правильний при ширині 560 (вузьке вікно) під час відтворення', (tester) async {
      tester.view.physicalSize = const Size(560, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final p = FakePlayer();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Stack(children: [
            BottomDock(
              scale: 1.0, player: p, currentSpeed: 1.0, volume: ValueNotifier<VolumeState>(const VolumeState(80, false)), isFullscreen: false,
              drawerOwner: null, isEpisodesOpen: false, chapters: sampleChapters(), anime4kActive: false, anime4kKey: GlobalKey(), onAnime4kTap: () {}, onAnime4kSecondaryTap: () {},
              subsKey: GlobalKey(), audioKey: GlobalKey(), speedKey: GlobalKey(), volumeKey: GlobalKey(),
              onToggleFullscreen: () {}, onMiniPlayer: () {}, onVolumeChanged: (v) {}, onToggleMute: () {},
              onSubsTap: () {}, onAudioTap: () {}, onSpeedTap: () {}, onSpeedSecondaryTap: () {}, onEpisodesTap: () {}, onChaptersTap: () {},
            ),
          ]),
        ),
      ));
      await play(tester, p, const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    });
  });
}
