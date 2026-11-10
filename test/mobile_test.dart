
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:media_kit/media_kit.dart';
import 'package:miki_miki/models/media_models.dart';
import 'package:miki_miki/services/hikka_nav.dart';
import 'package:miki_miki/services/osd_message.dart';
import 'package:miki_miki/services/storage_service.dart';
import 'package:miki_miki/services/system_controls.dart';
import 'package:miki_miki/services/touch_gestures.dart';
import 'package:miki_miki/services/ui_theme_service.dart';
import 'package:miki_miki/utils/platform_info.dart';
import 'package:miki_miki/widgets/app_dock_widgets.dart';
import 'package:miki_miki/widgets/app_settings_dialog.dart';
import 'package:miki_miki/widgets/app_ui_kit.dart';
import 'package:miki_miki/widgets/home_hub.dart';
import 'package:miki_miki/widgets/local_library.dart';
import 'package:miki_miki/widgets/mobile_controls.dart';
import 'package:miki_miki/widgets/mobile_gesture_layer.dart';
import 'package:miki_miki/widgets/mobile_sheet.dart';
import 'package:miki_miki/widgets/osd_toast.dart';
import 'package:miki_miki/widgets/side_panel.dart';
import 'package:miki_miki/widgets/settings_drawer.dart';
import 'package:miki_miki/widgets/skip_button.dart';

import 'support/fakes.dart';
import 'support/hikka_fakes.dart';

// Розміри екрана Pixel 8 Pro у dp (dpr = 1.0): альбомна й портрет
const Size kLandscape = Size(997, 448);
const Size kPortrait = Size(448, 997);
const Size kNarrow = Size(360, 780);

void setScreen(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<void> tick(WidgetTester tester, [int ms = 600]) async {
  await tester.pump();
  await tester.pump(Duration(milliseconds: ms));
}

Future<void> shot(WidgetTester tester, String name) =>
    expectLater(find.byType(MaterialApp), matchesGoldenFile('shots/$name.png'));

/// Вирізи / системні панелі: у MediaQuery підставляємо відступи, як на справжньому телефоні
Widget withInsets(EdgeInsets pad, Widget child) => MaterialApp(
      debugShowCheckedModeBanner: false,
      builder: (context, w) => MediaQuery(
        data: MediaQuery.of(context).copyWith(padding: pad, viewPadding: pad),
        child: w!,
      ),
      home: child,
    );

/// «Відео»: кольоровий кадр, на якому видно прозорість кнопок і градієнтів
class FakeVideo extends StatelessWidget {
  const FakeVideo({super.key});

  @override
  Widget build(BuildContext context) => const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF3D6FA8), Color(0xFFE2A66B), Color(0xFF7B4B8A)],
          ),
        ),
        child: SizedBox.expand(),
      );
}

final List<VideoChapter> kChapters = [
  const VideoChapter(title: 'Opening', startTime: Duration.zero, endTime: Duration(minutes: 2)),
  const VideoChapter(title: 'Episode', startTime: Duration(minutes: 2), endTime: Duration(minutes: 22)),
  const VideoChapter(title: 'Ending', startTime: Duration(minutes: 22), endTime: Duration(minutes: 24)),
  const VideoChapter(title: 'Preview', startTime: Duration(minutes: 24)),
];

/// Збирає той самий стек шарів, що й мобільний плеєр: відео → жести → кнопка «Пропустити» →
/// керування → меню-панелі → сповіщення. Стан (панелі, видимість) живе в самій сцені.
class PhoneScene extends StatefulWidget {
  final FakeController c;
  final bool controls;
  final String? drawer;
  final String? drawerPrev;
  final SidePanelType? side;
  final bool pip;
  final bool locked;
  final int queue;
  final int seekStep;
  final double speed;
  final bool a4k;
  final bool subs;
  final List<CachedSubtitleTrack> subTracks;
  final List<CachedAudioTrack> audioTracks;

  const PhoneScene({
    super.key,
    required this.c,
    this.controls = true,
    this.drawer,
    this.drawerPrev,
    this.side,
    this.pip = true,
    this.locked = false,
    this.queue = 3,
    this.seekStep = 10,
    this.speed = 1.0,
    this.a4k = false,
    this.subs = false,
    this.subTracks = const [],
    this.audioTracks = const [],
  });

  @override
  State<PhoneScene> createState() => PhoneSceneState();
}

class PhoneSceneState extends State<PhoneScene> {
  late bool controls = widget.controls;
  late String? drawer = widget.drawer;
  late String? drawerPrev = widget.drawerPrev;
  late SidePanelType? side = widget.side;
  final osd = ValueNotifier<OsdMessage?>(null);
  final events = <String>[];
  final scroll = ScrollController();
  final brightnessWrites = <double>[];
  final volumeWrites = <double>[];

  FakePlayer get p => widget.c.fakePlayer;

  @override
  void dispose() {
    osd.dispose();
    scroll.dispose();
    super.dispose();
  }

  void _closeDrawer() => setState(() {
        drawer = null;
        drawerPrev = null;
      });

  void _openDrawer(String name) => setState(() {
        drawer = name;
        drawerPrev = null;
        controls = true;
      });

  @override
  Widget build(BuildContext context) {
    const double scale = AppPlatform.mobileScale;
    final pad = MediaQuery.paddingOf(context);
    final panelOpen = drawer != null || side != null;
    final items = [for (var i = 1; i <= widget.queue; i++) Media('/tmp/proj/Episode $i - Some long episode title.mkv')];

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              events.add('video-tap');
              if (drawer != null) {
                _closeDrawer();
              } else {
                setState(() => controls = !controls);
              }
            },
            child: const FakeVideo(),
          ),
          MobileGestureLayer(
            player: p,
            osd: (m, {duration}) => osd.value = m,
            enabled: !panelOpen,
            readBrightness: () async => 0.5,
            writeBrightness: (v) async => brightnessWrites.add(v),
            readVolume: () async => 0.3,
            writeVolume: (v) async => volumeWrites.add(v),
          ),
          SkipButton(
            touch: true,
            scale: scale,
            showControls: controls,
            player: p,
            chapters: kChapters,
            dismissedChapterStartTime: null,
          ),
          MobileControls(
            visible: controls,
            player: p,
            title: 'Frieren: Beyond Journey\'s End',
            subtitle: widget.queue > 1 ? 'Серія 2 з ${widget.queue}' : '',
            chapters: kChapters,
            currentSpeed: widget.speed,
            anime4kActive: widget.a4k,
            subtitlesOn: widget.subs,
            hasQueue: widget.queue > 1,
            pipSupported: widget.pip,
            rotationLocked: widget.locked,
            drawerOwner: drawer,
            isEpisodesOpen: side == SidePanelType.episodes,
            seekStep: widget.seekStep,
            seekButtons: StorageService.getMobileSeekButtons(),
            onBack: () => events.add('back'),
            onInfo: () => setState(() => side = SidePanelType.info),
            onPip: () => events.add('pip'),
            onRotate: () => events.add('rotate'),
            onRotateAuto: () => events.add('rotate-auto'),
            onSettings: () => _openDrawer('settings'),
            onSpeed: () => _openDrawer('speed'),
            onAnime4k: () => _openDrawer('anime4k'),
            onAnime4kToggle: () => events.add('a4k-toggle'),
            onSubs: () => _openDrawer('subs'),
            onAudio: () => _openDrawer('audio'),
            onEpisodes: () => setState(() => side = SidePanelType.episodes),
          ),
          MobileSheetFrame(
            open: drawer != null,
            onDismiss: _closeDrawer,
            child: drawer == null
                ? const SizedBox.shrink()
                : SettingsDrawer(
                    sheet: true,
                    scale: scale,
                    activeDrawer: drawer!,
                    activeDrawerPrev: drawerPrev,
                    player: p,
                    currentSpeed: widget.speed,
                    currentHwdec: 'mediacodec-copy',
                    subtitleTracks: widget.subTracks,
                    audioTracks: widget.audioTracks,
                    chapters: kChapters,
                    scrollController: scroll,
                    onClose: _closeDrawer,
                    onBack: () => setState(() {
                      drawer = drawerPrev;
                      drawerPrev = null;
                    }),
                    onOpenSubDrawer: (n) => setState(() {
                      drawerPrev = drawer;
                      drawer = n;
                    }),
                    onSpeedSelected: (v) => events.add('speed:$v'),
                    onSubtitleSelected: (t) => events.add('sub:${t.id}'),
                    onAudioSelected: (t) => events.add('audio:${t.id}'),
                    onHwdecSelected: (h) => events.add('hwdec:$h'),
                    onOpenChaptersSidePanel: () => setState(() {
                      drawer = null;
                      side = SidePanelType.chapters;
                    }),
                    onOpenStats: () => events.add('stats'),
                    anime4k: widget.c.anime4k,
                  ),
          ),
          MobileSheetFrame(
            open: side != null,
            onDismiss: () => setState(() => side = null),
            child: side == null
                ? const SizedBox.shrink()
                : SidePanel(
                    key: ValueKey(side),
                    sheet: true,
                    scale: scale,
                    type: side!,
                    player: p,
                    playlistItems: items,
                    currentPlaylistIndex: 1,
                    chapters: kChapters,
                    onClose: () => setState(() => side = null),
                    onAddMedia: () => events.add('add-media'),
                    onEpisodeSelected: (i) => events.add('episode:$i'),
                    onChapterSelected: (d) => events.add('chapter:${d.inSeconds}'),
                    onQueueReorder: (a, b) => events.add('reorder:$a>$b'),
                    onQueueRemove: (i) => events.add('remove:$i'),
                    onQueueClear: () => events.add('clear'),
                  ),
          ),
          OsdToast(scale: scale, message: osd, topInset: pad.top),
        ],
      ),
    );
  }
}

/// Усі кнопки-«скло» на екрані: їхній розмір — це зона дотику
List<Size> overlayButtonSizes(WidgetTester tester) => [
      for (final e in find.byType(AppOverlayButton).evaluate()) tester.getSize(find.byWidget(e.widget)),
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadTestFonts();
  });

  setUp(() {
    uiTheme.setThemeMode('dark');
    AppPlatform.debugMobile = true;
  });

  tearDown(() {
    AppPlatform.debugMobile = null;
    SystemControls.debugEnabled = false;
    SystemControls.userBrightness = null;
  });

  // ── Чиста математика жестів ────────────────────────────────────────────────

  group('TouchGestureMath', () {
    test('діапазон перемотки: 10 % тривалості, 60…240 с, не далі за кінець короткого відео', () {
      expect(TouchGestureMath.seekSpanSeconds(const Duration(minutes: 24)), closeTo(144, 0.001));
      expect(TouchGestureMath.seekSpanSeconds(const Duration(minutes: 5)), 60);
      expect(TouchGestureMath.seekSpanSeconds(const Duration(hours: 5)), 240);
      expect(TouchGestureMath.seekSpanSeconds(const Duration(seconds: 20)), 20);
    });

    test('seekTarget: вправо — вперед, вліво — назад, у межах 0…тривалість', () {
      const total = Duration(minutes: 24); // 144 с на всю ширину
      const start = Duration(minutes: 10);
      final half = TouchGestureMath.seekTarget(start: start, total: total, dx: 500, width: 1000);
      expect(half, start + const Duration(seconds: 72));
      final back = TouchGestureMath.seekTarget(start: start, total: total, dx: -250, width: 1000);
      expect(back, start - const Duration(seconds: 36));
      expect(TouchGestureMath.seekTarget(start: start, total: total, dx: -99999, width: 1000), Duration.zero);
      expect(TouchGestureMath.seekTarget(start: start, total: total, dx: 99999, width: 1000), total);
      // немає тривалості (потік) — позиція не змінюється
      expect(TouchGestureMath.seekTarget(start: start, total: Duration.zero, dx: 400, width: 1000), start);
    });

    test('levelAfterDrag: вгору збільшує, вниз зменшує, 85 % висоти = увесь діапазон', () {
      expect(TouchGestureMath.levelAfterDrag(start: 0.5, dy: -425, height: 1000), closeTo(0.5 + 0.5, 0.001));
      expect(TouchGestureMath.levelAfterDrag(start: 0.5, dy: 212.5, height: 1000), closeTo(0.25, 0.001));
      expect(TouchGestureMath.levelAfterDrag(start: 0.9, dy: -900, height: 1000), 1.0);
      expect(TouchGestureMath.levelAfterDrag(start: 0.1, dy: 900, height: 1000), 0.0);
      expect(TouchGestureMath.levelAfterDrag(start: 0.4, dy: -50, height: 0), 0.4);
    });

    test('ліва половина — яскравість, права — гучність', () {
      expect(TouchGestureMath.isBrightnessSide(100, 448), isTrue);
      expect(TouchGestureMath.isBrightnessSide(223.9, 448), isTrue);
      expect(TouchGestureMath.isBrightnessSide(224, 448), isFalse);
      expect(TouchGestureMath.isBrightnessSide(400, 448), isFalse);
    });

    test('краї екрана — системні жести, їх не чіпаємо', () {
      const size = Size(448, 997);
      expect(TouchGestureMath.inSystemEdge(const Offset(5, 500), size), isTrue); // ліво
      expect(TouchGestureMath.inSystemEdge(const Offset(440, 500), size), isTrue); // право
      expect(TouchGestureMath.inSystemEdge(const Offset(200, 10), size), isTrue); // шторка
      expect(TouchGestureMath.inSystemEdge(const Offset(200, 990), size), isTrue); // «додому»
      expect(TouchGestureMath.inSystemEdge(const Offset(200, 500), size), isFalse);
    });

    test('підпис зсуву перемотки', () {
      expect(TouchGestureMath.deltaLabel(const Duration(seconds: 23)), '+0:23');
      expect(TouchGestureMath.deltaLabel(const Duration(seconds: -65)), '−1:05');
      expect(TouchGestureMath.deltaLabel(const Duration(seconds: 3723)), '+1:02:03');
    });
  });

  group('AppPlatform / AppLayout', () {
    test('перевизначення для тестів і класи розкладки', () {
      expect(AppPlatform.isMobile, isTrue);
      expect(AppPlatform.isDesktop, isFalse);
      AppPlatform.debugMobile = false;
      expect(AppPlatform.isMobile, isFalse);
      expect(AppPlatform.isDesktop, isTrue);
      AppPlatform.debugMobile = true;

      final portrait = AppLayout(kPortrait);
      expect(portrait.isPortrait, isTrue);
      expect(portrait.isLandscape, isFalse);
      expect(portrait.isCompactWidth, isTrue); // 448 < 640
      final land = AppLayout(kLandscape);
      expect(land.isLandscape, isTrue);
      expect(land.isCompactWidth, isFalse);
      expect(land.isShortHeight, isTrue); // 448 < 520
      expect(AppPlatform.touchTarget, greaterThanOrEqualTo(48));
    });
  });

  // ── Канал Android ──────────────────────────────────────────────────────────

  group('SystemControls (канал miki_miki/system)', () {
    const channel = MethodChannel('miki_miki/system');
    final calls = <MethodCall>[];
    bool throwing = false;

    setUp(() {
      calls.clear();
      throwing = false;
      SystemControls.debugEnabled = true;
      SystemControls.userBrightness = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (throwing) throw PlatformException(code: 'boom');
        switch (call.method) {
          case 'pipSupported':
          case 'pipEnter':
            return true;
          case 'getBrightness':
            return 0.4;
          case 'getVolume':
            return 0.7;
        }
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    });

    test('PiP: підтримка, вхід із пропорціями, автоматичний вхід', () async {
      expect(await SystemControls.pipSupported(), isTrue);
      expect(await SystemControls.enterPip(width: 1920, height: 1080), isTrue);
      await SystemControls.setPipAuto(true, width: 4, height: 3);
      await SystemControls.setPipAuto(false);
      expect(calls.map((c) => c.method), ['pipSupported', 'pipEnter', 'pipAuto', 'pipAuto']);
      expect(calls[1].arguments, {'w': 1920, 'h': 1080});
      expect(calls[2].arguments, {'enabled': true, 'w': 4, 'h': 3});
      expect(calls[3].arguments, {'enabled': false, 'w': 16, 'h': 9});
    });

    test('яскравість: запам\'ятовує вибір користувача, скидає й відновлює', () async {
      expect(await SystemControls.getBrightness(), 0.4);
      expect(SystemControls.userBrightness, isNull);

      await SystemControls.restoreBrightness(); // нічого не вибирали — нічого й не шлемо
      expect(calls.where((c) => c.method == 'setBrightness'), isEmpty);

      await SystemControls.setBrightness(0.8);
      expect(SystemControls.userBrightness, 0.8);
      await SystemControls.resetBrightness(); // вийшли на головну: системна яскравість
      expect(calls.last.method, 'setBrightness');
      expect(calls.last.arguments, {'value': -1.0});
      expect(SystemControls.userBrightness, 0.8); // вибір не губиться
      await SystemControls.restoreBrightness(); // знову у плеєрі
      expect(calls.last.arguments, {'value': 0.8});
    });

    test('гучність читається й записується', () async {
      expect(await SystemControls.getVolume(), 0.7);
      await SystemControls.setVolume(0.25);
      expect(calls.last.method, 'setVolume');
      expect(calls.last.arguments, {'value': 0.25});
    });

    test('помилка Android не ламає застосунок: повертаються безпечні значення', () async {
      throwing = true;
      expect(await SystemControls.pipSupported(), isFalse);
      expect(await SystemControls.enterPip(), isFalse);
      expect(await SystemControls.getVolume(), isNull);
      await SystemControls.setBrightness(0.3); // не кидає
    });

    test('подія pipChanged від Android оновлює inPip', () async {
      SystemControls.init();
      SystemControls.inPip.value = false;
      Future<void> fromNative(bool v) => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
            'miki_miki/system',
            const StandardMethodCodec().encodeMethodCall(MethodCall('pipChanged', v)),
            (_) {},
          );
      await fromNative(true);
      expect(SystemControls.inPip.value, isTrue);
      await fromNative(false);
      expect(SystemControls.inPip.value, isFalse);
    });

    test('поза Android і без тестового ввімкнення канал не чіпається', () async {
      SystemControls.debugEnabled = false;
      expect(await SystemControls.pipSupported(), isFalse);
      expect(await SystemControls.getBrightness(), isNull);
      await SystemControls.setVolume(0.5);
      expect(calls, isEmpty);
    });
  });

  // ── Жести на відео ─────────────────────────────────────────────────────────

  group('MobileGestureLayer', () {
    late FakePlayer p;
    late List<OsdMessage> osd;
    late List<double> bright, vol;

    Future<void> mount(WidgetTester tester, Size size, {bool enabled = true, Duration? duration, EdgeInsets gestureInsets = EdgeInsets.zero}) async {
      setScreen(tester, size);
      p = FakePlayer();
      if (duration != null) p.current = p.current.copyWith(duration: duration);
      osd = [];
      bright = [];
      vol = [];
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(systemGestureInsets: gestureInsets), child: w!),
        home: Scaffold(
          body: SizedBox.expand(
            child: MobileGestureLayer(
              player: p,
              osd: (m, {duration}) => osd.add(m),
              enabled: enabled,
              readBrightness: () async => 0.5,
              writeBrightness: (v) async => bright.add(v),
              readVolume: () async => 0.3,
              writeVolume: (v) async => vol.add(v),
            ),
          ),
        ),
      ));
    }

    Future<void> drag(WidgetTester tester, Offset from, Offset step, int n) async {
      final g = await tester.startGesture(from);
      for (var i = 0; i < n; i++) {
        await g.moveBy(step);
        await tester.pump(const Duration(milliseconds: 50));
      }
      await g.up();
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('вертикально ліворуч — яскравість; вгору збільшує', (tester) async {
      await mount(tester, kPortrait);
      await drag(tester, const Offset(100, 600), const Offset(0, -40), 6); // усього 240 px вгору
      expect(vol, isEmpty);
      expect(bright, isNotEmpty);
      expect(bright.last, closeTo(0.5 + 240 / (997 * 0.85), 0.02));
      expect(osd.last.title, 'Яскравість');
      expect(osd.last.detail, endsWith('%'));
      for (var i = 1; i < bright.length; i++) {
        expect(bright[i], greaterThanOrEqualTo(bright[i - 1]));
      }
    });

    testWidgets('вертикально праворуч — системна гучність; вниз зменшує, не нижче 0', (tester) async {
      await mount(tester, kPortrait);
      await drag(tester, const Offset(330, 200), const Offset(0, 90), 10);
      expect(bright, isEmpty);
      expect(vol, isNotEmpty);
      expect(vol.last, 0.0);
      expect(osd.last.title, 'Гучність');
      expect(osd.last.icon, Symbols.volume_off_rounded);
    });

    testWidgets('записи в систему прорідженні: не кожен піксель', (tester) async {
      await mount(tester, kPortrait);
      final g = await tester.startGesture(const Offset(330, 700));
      for (var i = 0; i < 60; i++) {
        await g.moveBy(const Offset(0, -3));
        await tester.pump(const Duration(milliseconds: 5)); // 300 мс усього
      }
      await g.up();
      await tester.pump(const Duration(milliseconds: 100));
      expect(vol.length, lessThan(25));
      expect(vol.length, greaterThan(1));
      expect(vol.last, greaterThan(0.3)); // останнє значення дійшло
    });

    testWidgets('жест із краю екрана (системний) ігнорується', (tester) async {
      await mount(tester, kPortrait);
      await drag(tester, const Offset(8, 600), const Offset(0, -40), 6);
      await drag(tester, const Offset(200, 8), const Offset(0, 40), 6);
      expect(bright, isEmpty);
      expect(vol, isEmpty);
      expect(osd, isEmpty);
    });

    testWidgets('зони системних жестів Android розширюють «мертві» краї', (tester) async {
      await mount(tester, kPortrait, gestureInsets: const EdgeInsets.fromLTRB(48, 0, 48, 0));
      await drag(tester, const Offset(40, 600), const Offset(0, -40), 6); // у зоні жесту «назад»
      expect(bright, isEmpty);
      await drag(tester, const Offset(60, 600), const Offset(0, -40), 6); // за її межами
      expect(bright, isNotEmpty);
    });

    testWidgets('горизонтально — перемотка застосовується, коли палець відпущено', (tester) async {
      await mount(tester, kPortrait, duration: const Duration(minutes: 90));
      final g = await tester.startGesture(const Offset(80, 500));
      for (var i = 0; i < 6; i++) {
        await g.moveBy(const Offset(40, 0));
        await tester.pump(const Duration(milliseconds: 30));
      }
      expect(p.seeks, isEmpty); // поки тримаємо — лише підказка
      expect(osd, isNotEmpty);
      await g.up();
      await tester.pump();
      expect(p.seeks, hasLength(1));
      // 240 px із 448 при 240 с на ширину ≈ +129 с до 20:00
      final expectedMs = const Duration(minutes: 20).inMilliseconds + (240 / 448 * 240 * 1000);
      expect(p.seeks.single.inMilliseconds, closeTo(expectedMs, 1500));
      expect(osd.last.title, '+2:08');
      expect(osd.last.detail, contains('/ 1:30:00'));
    });

    testWidgets('перемотка вліво — назад, але не раніше за початок', (tester) async {
      await mount(tester, kPortrait, duration: const Duration(minutes: 90));
      p.current = p.current.copyWith(position: const Duration(seconds: 30));
      await drag(tester, const Offset(400, 500), const Offset(-60, 0), 7);
      expect(p.seeks.single, Duration.zero);
    });

    testWidgets('без тривалості (потік) перемотка недоступна', (tester) async {
      await mount(tester, kPortrait, duration: Duration.zero);
      await drag(tester, const Offset(80, 500), const Offset(40, 0), 6);
      expect(p.seeks, isEmpty);
      expect(osd, isEmpty);
    });

    testWidgets('вимкнений шар (відкрите меню) жестів не обробляє', (tester) async {
      await mount(tester, kPortrait, enabled: false);
      await drag(tester, const Offset(100, 600), const Offset(0, -40), 6);
      await drag(tester, const Offset(80, 500), const Offset(40, 0), 6);
      expect(bright, isEmpty);
      expect(p.seeks, isEmpty);
    });
  });

  // ── Керування: розкладка, цілі дотику, дії ─────────────────────────────────

  group('MobileControls', () {
    Future<PhoneSceneState> mount(
      WidgetTester tester,
      Size size, {
      EdgeInsets pad = EdgeInsets.zero,
      FakeController? c,
      bool pip = true,
      bool locked = false,
      int queue = 3,
      bool controls = true,
      int seekStep = 10,
      double speed = 1.0,
      bool a4k = false,
      bool subs = false,
    }) async {
      setScreen(tester, size);
      final key = GlobalKey<PhoneSceneState>();
      await tester.pumpWidget(withInsets(
        pad,
        PhoneScene(
          key: key,
          c: c ?? FakeController(),
          pip: pip,
          locked: locked,
          queue: queue,
          controls: controls,
          seekStep: seekStep,
          speed: speed,
          a4k: a4k,
          subs: subs,
        ),
      ));
      await tick(tester, 500);
      return key.currentState!;
    }

    testWidgets('усі кнопки ≥ 48 dp, повзунок має зону ≥ 48 dp (портрет / альбомна / вузький)', (tester) async {
      for (final size in [kPortrait, kLandscape, kNarrow]) {
        await mount(tester, size, pad: const EdgeInsets.fromLTRB(0, 28, 0, 16));
        final sizes = overlayButtonSizes(tester);
        expect(sizes.length, greaterThanOrEqualTo(10), reason: 'кнопки є ($size)');
        for (final s in sizes) {
          expect(s.width, greaterThanOrEqualTo(48), reason: 'ширина $s на $size');
          expect(s.height, greaterThanOrEqualTo(48), reason: 'висота $s на $size');
        }
        expect(tester.getSize(find.byType(AppSeekBar)).height, greaterThanOrEqualTo(48));
        expect(tester.takeException(), isNull, reason: 'без переповнення на $size');
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('кнопки перемотки ±крок вимикаються налаштуванням; пауза й перемикання серій лишаються', (tester) async {
      StorageService.saveMobileSeekButtons(false);
      addTearDown(() => StorageService.saveMobileSeekButtons(true));
      await mount(tester, kPortrait);
      expect(find.byIcon(Symbols.replay_10_rounded), findsNothing);
      expect(find.byIcon(Symbols.forward_10_rounded), findsNothing);
      expect(find.byIcon(Symbols.play_arrow_rounded), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('кнопка паузи — по центру екрана, найбільша; перемотка й перемикання серій навколо неї', (tester) async {
      for (final size in [kPortrait, kLandscape]) {
        await mount(tester, size);
        final play = tester.getRect(find.byIcon(Symbols.play_arrow_rounded));
        expect((play.center.dx - size.width / 2).abs(), lessThan(2), reason: 'по горизонталі $size');
        expect((play.center.dy - size.height / 2).abs(), lessThan(2), reason: 'по вертикалі $size');
        final back = tester.getRect(find.byIcon(Symbols.replay_10_rounded));
        final fwd = tester.getRect(find.byIcon(Symbols.forward_10_rounded));
        final prev = tester.getRect(find.byIcon(Symbols.skip_previous_rounded));
        final next = tester.getRect(find.byIcon(Symbols.skip_next_rounded));
        expect(prev.center.dx, lessThan(back.center.dx));
        expect(back.center.dx, lessThan(play.center.dx));
        expect(play.center.dx, lessThan(fwd.center.dx));
        expect(fwd.center.dx, lessThan(next.center.dx));
        expect(prev.left, greaterThan(0));
        expect(next.right, lessThan(size.width));
        // повзунок і швидкі кнопки — під центром, у нижній частині
        final seek = tester.getRect(find.byType(AppSeekBar));
        expect(seek.center.dy, greaterThan(size.height * 0.62), reason: 'повзунок унизу ($size)');
        // верхня панель — угорі
        expect(tester.getRect(find.byIcon(Symbols.arrow_back_rounded)).center.dy, lessThan(80));
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('дії: пауза, перемотка на крок, попередня / наступна, повернення, налаштування', (tester) async {
      final c = FakeController();
      final s = await mount(tester, kPortrait, c: c);
      await tester.tap(find.byIcon(Symbols.play_arrow_rounded));
      await tick(tester, 100);
      expect(c.fakePlayer.playPauseCalls, 1);

      await tester.tap(find.byIcon(Symbols.forward_10_rounded));
      await tick(tester, 100);
      expect(c.fakePlayer.seeks.last, const Duration(minutes: 20, seconds: 10));
      await tester.tap(find.byIcon(Symbols.replay_10_rounded));
      await tick(tester, 100);
      expect(c.fakePlayer.seeks.last, const Duration(minutes: 20) - const Duration(seconds: 10));

      await tester.tap(find.byIcon(Symbols.arrow_back_rounded));
      await tester.tap(find.byIcon(Symbols.picture_in_picture_alt_rounded));
      await tester.tap(find.byIcon(Symbols.screen_rotation_rounded));
      expect(s.events, ['back', 'pip', 'rotate']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('довге утримання повороту повертає автоповорот, Anime4K — перемикається', (tester) async {
      final s = await mount(tester, kPortrait, locked: true);
      expect(find.byIcon(Symbols.screen_lock_rotation_rounded), findsOneWidget);
      expect(find.byIcon(Symbols.screen_rotation_rounded), findsNothing);
      await tester.longPress(find.byIcon(Symbols.screen_lock_rotation_rounded));
      await tick(tester, 100);
      await tester.longPress(find.byIcon(Symbols.auto_awesome_rounded));
      await tick(tester, 100);
      expect(s.events, ['rotate-auto', 'a4k-toggle']);
    });

    testWidgets('PiP-кнопки немає там, де пристрій її не підтримує; серії неактивні без черги', (tester) async {
      final c = FakeController();
      await mount(tester, kPortrait, pip: false, queue: 1, c: c);
      expect(find.byIcon(Symbols.picture_in_picture_alt_rounded), findsNothing);
      await tester.tap(find.byIcon(Symbols.skip_next_rounded));
      await tester.tap(find.byIcon(Symbols.skip_previous_rounded));
      await tick(tester, 100);
      expect(c.fakePlayer.seeks, isEmpty);
      // назва без підпису серії
      expect(find.textContaining('Серія'), findsNothing);
      expect(find.text('Frieren: Beyond Journey\'s End'), findsOneWidget);
    });

    testWidgets('нестандартний крок перемотки: стрілки з числом', (tester) async {
      final c = FakeController();
      await mount(tester, kPortrait, seekStep: 15, c: c);
      expect(find.text('15'), findsNWidgets(2));
      await tester.tap(find.byIcon(Symbols.fast_forward_rounded));
      await tick(tester, 100);
      expect(c.fakePlayer.seeks.last, const Duration(minutes: 20, seconds: 15));
    });

    testWidgets('сховані панелі не ловлять дотики; тап по відео показує їх назад', (tester) async {
      final c = FakeController();
      final s = await mount(tester, kPortrait, controls: false, c: c);
      await tester.tap(find.byIcon(Symbols.play_arrow_rounded), warnIfMissed: false);
      await tick(tester, 100);
      // тап пройшов у відео, а не в кнопку паузи
      expect(c.fakePlayer.playPauseCalls, 0);
      expect(s.events, contains('video-tap'));
      expect(s.controls, isTrue);
    });

    testWidgets('тап по порожньому відео ховає панелі, тап по кнопці — ні', (tester) async {
      final s = await mount(tester, kLandscape);
      await tester.tapAt(const Offset(300, 200)); // порожнє місце між кнопками
      await tick(tester, 100);
      expect(s.events.last, 'video-tap');
      expect(s.controls, isFalse);
      await tester.tapAt(const Offset(300, 200));
      await tick(tester, 100);
      expect(s.controls, isTrue);
      s.events.clear();
      await tester.tap(find.byIcon(Symbols.play_arrow_rounded));
      await tick(tester, 100);
      expect(s.events, isEmpty);
      expect(s.controls, isTrue);
    });

    testWidgets('швидкість, Anime4K, субтитри, звук і епізоди відкривають свої меню', (tester) async {
      final s = await mount(tester, kPortrait, speed: 1.25);
      expect(find.text('1.25x'), findsOneWidget);
      await tester.tap(find.text('1.25x'));
      await tick(tester);
      expect(s.drawer, 'speed');
      expect(find.text('Швидкість відтворення'), findsWidgets);
      await tester.tapAt(const Offset(224, 80)); // затемнення над панеллю
      await tick(tester);
      expect(s.drawer, isNull);

      await tester.tap(find.byIcon(Symbols.video_library_rounded));
      await tick(tester);
      expect(s.side, SidePanelType.episodes);
      expect(tester.takeException(), isNull);
    });

    testWidgets('знімки: портрет, альбомна, вузький, виріз', (tester) async {
      await mount(tester, kPortrait, pad: const EdgeInsets.fromLTRB(0, 30, 0, 18), a4k: true, subs: true, speed: 1.5);
      await shot(tester, 'm_controls_portrait');
      await mount(tester, kLandscape, pad: const EdgeInsets.fromLTRB(46, 0, 0, 0), a4k: true, locked: true);
      await shot(tester, 'm_controls_landscape');
      await mount(tester, kNarrow, pad: const EdgeInsets.fromLTRB(0, 24, 0, 24));
      await shot(tester, 'm_controls_narrow');
      expect(tester.takeException(), isNull);
    });
  });

  // ── Меню-панелі ────────────────────────────────────────────────────────────

  group('MobileSheetFrame + меню', () {
    final subs = [
      const CachedSubtitleTrack(track: SubtitleTrack('1', 'Signs & Songs', 'eng'), formattedTitle: 'English — Signs & Songs'),
      const CachedSubtitleTrack(track: SubtitleTrack('2', 'Full', 'ukr'), formattedTitle: 'Українська — Full'),
      const CachedSubtitleTrack(track: SubtitleTrack('3', 'Dialogue', 'jpn'), formattedTitle: '日本語 — Dialogue'),
    ];
    final audio = [
      const CachedAudioTrack(track: AudioTrack('1', 'Stereo', 'jpn'), formattedTitle: '日本語 — Stereo'),
      const CachedAudioTrack(track: AudioTrack('2', 'Dub', 'ukr'), formattedTitle: 'Українська — Dub 5.1'),
    ];

    Future<PhoneSceneState> open(
      WidgetTester tester,
      Size size, {
      String? drawer,
      String? prev,
      SidePanelType? side,
      EdgeInsets pad = EdgeInsets.zero,
    }) async {
      setScreen(tester, size);
      final key = GlobalKey<PhoneSceneState>();
      await tester.pumpWidget(withInsets(
        pad,
        PhoneScene(key: key, c: FakeController(), drawer: drawer, drawerPrev: prev, side: side, subTracks: subs, audioTracks: audio, speed: 1.25, a4k: true, subs: true),
      ));
      await tick(tester, 700);
      return key.currentState!;
    }

    testWidgets('портрет: нижня панель не вища за 68 % екрана, у стилі «ручка + список»', (tester) async {
      for (final d in ['settings', 'speed', 'subs', 'audio', 'anime4k']) {
        await open(tester, kPortrait, drawer: d, pad: const EdgeInsets.only(top: 30, bottom: 18));
        final surface = tester.getRect(find.byType(MobileSheetFrame).first);
        expect(surface.height, closeTo(kPortrait.height, 1)); // рамка на весь екран
        final drawer = find.byType(SettingsDrawer);
        expect(drawer, findsOneWidget);
        final r = tester.getRect(drawer);
        expect(r.height, lessThanOrEqualTo(kPortrait.height * MobileSheetFrame.portraitHeightFactor + 1), reason: d);
        expect(r.bottom, lessThanOrEqualTo(kPortrait.height + 0.5));
        expect(r.width, closeTo(kPortrait.width, 1));
        expect(tester.takeException(), isNull, reason: d);
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('альбомна: бічна панель справа 340…440 dp на всю висоту', (tester) async {
      for (final d in ['settings', 'speed', 'subs', 'audio', 'anime4k']) {
        await open(tester, kLandscape, drawer: d);
        final r = tester.getRect(find.byType(SettingsDrawer));
        expect(r.right, closeTo(kLandscape.width, 1));
        expect(r.width, inInclusiveRange(340, 440), reason: d);
        expect(r.height, closeTo(kLandscape.height, 1));
        expect(tester.takeException(), isNull, reason: d);
        await tester.pumpWidget(const SizedBox());
      }
      expect(MobileSheetFrame.sideWidth(997), closeTo(398.8, 0.1));
      expect(MobileSheetFrame.sideWidth(2000), 440);
      expect(MobileSheetFrame.sideWidth(600), 340);
    });

    testWidgets('рядки меню ≥ 48 dp заввишки, кнопки «Назад» / «Закрити» ≥ 48 dp', (tester) async {
      final s = await open(tester, kPortrait, drawer: 'settings', pad: const EdgeInsets.only(top: 30, bottom: 18));
      final closeIcon = find.descendant(of: find.byType(SettingsDrawer), matching: find.byIcon(Symbols.close_rounded));
      final box = tester.getSize(find.ancestor(of: closeIcon, matching: find.byType(SizedBox)).first);
      expect(box.width, greaterThanOrEqualTo(48));
      expect(box.height, greaterThanOrEqualTo(48));
      // рядки пунктів: знаходимо за підписами
      for (final label in ['Швидкість', 'Субтитри', 'Аудіо']) {
        final t = find.descendant(of: find.byType(SettingsDrawer), matching: find.text(label));
        if (t.evaluate().isEmpty) continue;
        final row = find.ancestor(of: t.first, matching: find.byType(InkWell));
        if (row.evaluate().isEmpty) continue;
        expect(tester.getSize(row.first).height, greaterThanOrEqualTo(48), reason: label);
      }
      s.drawer = null;
    });

    testWidgets('тап по затемненню закриває; «Назад» повертає до головного меню', (tester) async {
      final s = await open(tester, kPortrait, drawer: 'settings');
      await tester.tap(find.text('Швидкість відтворення').first);
      await tick(tester, 500);
      expect(s.drawer, 'speed');
      expect(s.drawerPrev, 'settings');
      await tester.tap(find.byIcon(Symbols.arrow_back_rounded).last);
      await tick(tester, 500);
      expect(s.drawer, 'settings');
      await tester.tapAt(const Offset(224, 60));
      await tick(tester, 500);
      expect(s.drawer, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('вибір швидкості, субтитрів і звуку доходить до обробників', (tester) async {
      final s = await open(tester, kLandscape, drawer: 'speed');
      await tester.tap(find.text('1.5x').first);
      await tick(tester, 200);
      expect(s.events, contains('speed:1.5'));
      s.events.clear();
      await tester.pumpWidget(const SizedBox());
      final s2 = await open(tester, kLandscape, drawer: 'subs');
      await tester.tap(find.text('Українська — Full'));
      await tick(tester, 200);
      expect(s2.events, contains('sub:2'));
      await tester.pumpWidget(const SizedBox());
      final s3 = await open(tester, kLandscape, drawer: 'audio');
      await tester.tap(find.text('Українська — Dub 5.1'));
      await tick(tester, 200);
      expect(s3.events, contains('audio:2'));
    });

    testWidgets('боковий список: епізоди, інформація, розділи (портрет і альбомна)', (tester) async {
      for (final size in [kPortrait, kLandscape]) {
        for (final type in SidePanelType.values) {
          await open(tester, size, side: type, pad: size == kPortrait ? const EdgeInsets.only(top: 30, bottom: 18) : EdgeInsets.zero);
          final r = tester.getRect(find.byType(SidePanel));
          if (size == kPortrait) {
            expect(r.height, lessThanOrEqualTo(size.height * MobileSheetFrame.portraitHeightFactor + 1), reason: '$type');
          } else {
            expect(r.width, inInclusiveRange(340, 440), reason: '$type');
          }
          expect(tester.takeException(), isNull, reason: '$type $size');
          await tester.pumpWidget(const SizedBox());
        }
      }
    });

    testWidgets('епізоди: вибір серії, закриття, додавання файлів', (tester) async {
      final s = await open(tester, kPortrait, side: SidePanelType.episodes, pad: const EdgeInsets.only(top: 30, bottom: 18));
      await tester.tap(find.textContaining('Episode 3').first);
      await tick(tester, 200);
      expect(s.events, contains('episode:2'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('знімки меню: портрет та альбомна', (tester) async {
      const portraitPad = EdgeInsets.only(top: 30, bottom: 18);
      await open(tester, kPortrait, drawer: 'settings', pad: portraitPad);
      await shot(tester, 'm_sheet_settings_portrait');
      await open(tester, kPortrait, drawer: 'speed', pad: portraitPad);
      await shot(tester, 'm_sheet_speed_portrait');
      await open(tester, kPortrait, drawer: 'anime4k', pad: portraitPad);
      await shot(tester, 'm_sheet_anime4k_portrait');
      await open(tester, kPortrait, drawer: 'subs', pad: portraitPad);
      await shot(tester, 'm_sheet_subs_portrait');
      await open(tester, kPortrait, side: SidePanelType.episodes, pad: portraitPad);
      await shot(tester, 'm_sheet_episodes_portrait');
      await open(tester, kPortrait, side: SidePanelType.info, pad: portraitPad);
      await shot(tester, 'm_sheet_info_portrait');
      await open(tester, kPortrait, side: SidePanelType.chapters, pad: portraitPad);
      await shot(tester, 'm_sheet_chapters_portrait');

      const landPad = EdgeInsets.fromLTRB(46, 0, 0, 0);
      await open(tester, kLandscape, drawer: 'settings', pad: landPad);
      await shot(tester, 'm_sheet_settings_landscape');
      await open(tester, kLandscape, drawer: 'anime4k', pad: landPad);
      await shot(tester, 'm_sheet_anime4k_landscape');
      await open(tester, kLandscape, side: SidePanelType.episodes, pad: landPad);
      await shot(tester, 'm_sheet_episodes_landscape');
      expect(tester.takeException(), isNull);
    });
  });

  // ── Кнопка «Пропустити» і сповіщення ───────────────────────────────────────

  group('SkipButton / OsdToast на телефоні', () {
    testWidgets('«Пропустити» стоїть над нижньою панеллю, має висоту ≥ 48 dp і перемотує на кінець розділу', (tester) async {
      for (final size in [kPortrait, kLandscape]) {
        setScreen(tester, size);
        final c = FakeController();
        c.fakePlayer.current = c.fakePlayer.current.copyWith(position: const Duration(seconds: 5)); // початок «Опенінґу»
        await tester.pumpWidget(withInsets(
          size == kPortrait ? const EdgeInsets.fromLTRB(0, 30, 0, 18) : const EdgeInsets.fromLTRB(46, 0, 0, 0),
          PhoneScene(c: c),
        ));
        c.fakePlayer.tickPosition(const Duration(seconds: 6));
        await tick(tester, 800);
        final label = find.textContaining('Пропустити');
        expect(label, findsOneWidget, reason: '$size');
        final button = find.ancestor(of: label, matching: find.byType(InkWell)).first;
        expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
        final r = tester.getRect(button);
        final seek = tester.getRect(find.byType(AppSeekBar));
        expect(r.bottom, lessThan(seek.top), reason: 'кнопка вище повзунка ($size)');
        expect(r.right, lessThanOrEqualTo(size.width - 16));
        await shot(tester, size == kPortrait ? 'm_skip_portrait' : 'm_skip_landscape');
        await tester.tap(label);
        await tick(tester, 100);
        expect(c.fakePlayer.seeks.last, const Duration(minutes: 2)); // кінець розділу «Opening»
        await tester.pumpWidget(const SizedBox());
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('сповіщення про гучність / яскравість не заходить під виріз', (tester) async {
      setScreen(tester, kPortrait);
      final c = FakeController();
      final key = GlobalKey<PhoneSceneState>();
      await tester.pumpWidget(withInsets(const EdgeInsets.fromLTRB(0, 40, 0, 18), PhoneScene(key: key, c: c, controls: false)));
      key.currentState!.osd.value = const OsdMessage(icon: Symbols.volume_up_rounded, title: 'Гучність', detail: '65%', progress: 0.65);
      await tick(tester, 500);
      final r = tester.getRect(find.text('Гучність'));
      expect(r.top, greaterThan(40));
      await shot(tester, 'm_osd_portrait');
    });
  });

  // ── Головна ────────────────────────────────────────────────────────────────

  group('HomeHub на телефоні', () {
    late HikkaTestEnv env;

    setUp(() => env = HikkaTestEnv());
    tearDown(() {
      StorageService.saveLocalLibrary(false);
      env.dispose();
    });

    /// Дає час підставній мережі, диску й декодеру зображень: вони живуть у справжньому часі
    Future<void> loadHikka(WidgetTester tester, {int rounds = 14}) async {
      for (int i = 0; i < rounds; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump(const Duration(milliseconds: 60));
      }
    }

    Widget home(Size size, {EdgeInsets pad = EdgeInsets.zero, double reserve = 0}) => withInsets(
          pad,
          Scaffold(
            backgroundColor: Colors.black,
            body: HomeHub(
              scale: AppPlatform.mobileScale,
              reserveBottom: reserve,
              onOpenFile: (_) {},
              onOpenMultipleFiles: (_) {},
              onOpenQueue: (_, __) {},
              onOpenSettings: ({int? tab}) {},
            ),
          ),
        );

    testWidgets('портрет: нижня навігація з чотирьох вкладок, без переповнення', (tester) async {
      setScreen(tester, kPortrait);
      await tester.pumpWidget(home(kPortrait, pad: const EdgeInsets.fromLTRB(0, 30, 0, 18)));
      await loadHikka(tester);
      expect(HomeHub.isCompact(tester.element(find.byType(HomeHub))), isTrue);
      expect(tester.takeException(), isNull);
      for (final tab in MainTab.values) {
        expect(find.text(tab.label), findsWidgets, reason: tab.label);
      }
      await shot(tester, 'm_home_portrait');
    });

    testWidgets('альбомна: бічна навігація, без переповнення', (tester) async {
      setScreen(tester, kLandscape);
      await tester.pumpWidget(home(kLandscape, pad: const EdgeInsets.fromLTRB(46, 0, 0, 0)));
      await loadHikka(tester);
      expect(HomeHub.isCompact(tester.element(find.byType(HomeHub))), isFalse);
      expect(tester.takeException(), isNull);
      expect(find.text('Miki Miki'), findsOneWidget);
      await shot(tester, 'm_home_landscape');
    });

    testWidgets('вузький 360 dp: усі вкладки без переповнення', (tester) async {
      setScreen(tester, kNarrow);
      await tester.pumpWidget(home(kNarrow, pad: const EdgeInsets.fromLTRB(0, 24, 0, 24)));
      await loadHikka(tester);
      expect(tester.takeException(), isNull);
      await shot(tester, 'm_home_narrow');
      for (final tab in [MainTab.discover, MainTab.lists, MainTab.profile]) {
        await tester.tap(find.text(tab.label).last);
        await loadHikka(tester, rounds: 8);
        expect(tester.takeException(), isNull, reason: tab.label);
      }
    });

    testWidgets('згорнутий плеєр не закриває кінець списку: відступ знизу', (tester) async {
      setScreen(tester, kNarrow);
      await tester.pumpWidget(home(kNarrow, pad: const EdgeInsets.fromLTRB(0, 24, 0, 24), reserve: 104));
      await loadHikka(tester);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Профіль').last);
      await loadHikka(tester, rounds: 6);
      expect(tester.takeException(), isNull);
    });

    testWidgets('локальна медіатека: з «Профілю» (коли ввімкнена), у складі оболонки з кнопкою «Назад»', (tester) async {
      StorageService.addRecentFile('/tmp/proj/Frieren - 01.mkv');
      addTearDown(StorageService.clearRecentFiles);
      setScreen(tester, kPortrait);
      await tester.pumpWidget(home(kPortrait, pad: const EdgeInsets.fromLTRB(0, 30, 0, 18)));
      await loadHikka(tester, rounds: 6);
      await tester.tap(find.text('Профіль').last);
      await loadHikka(tester, rounds: 6);
      expect(find.text('Локальна медіатека'), findsNothing);
      StorageService.saveLocalLibrary(true);
      await loadHikka(tester, rounds: 3);
      await tester.tap(find.text('Локальна медіатека'));
      await loadHikka(tester, rounds: 6);
      expect(tester.takeException(), isNull);
      expect(find.text('Локальні файли'), findsOneWidget);
      expect(find.textContaining('Історія · '), findsOneWidget);
      await shot(tester, 'm_home_portrait_library');
      expect(HomeHub.backHandler!(), isTrue);
      await loadHikka(tester, rounds: 6);
      expect(find.text('Локальні файли'), findsNothing);
      expect(find.text('Гість'), findsOneWidget);
    });
  });

  group('LocalLibrary на телефоні', () {
    Widget library(Size size, {EdgeInsets pad = EdgeInsets.zero}) => withInsets(
          pad,
          Scaffold(
            backgroundColor: Colors.black,
            body: LocalLibrary(
              scale: AppPlatform.mobileScale,
              onOpenFile: (_) {},
              onOpenMultipleFiles: (_) {},
              onOpenQueue: (_, __) {},
            ),
          ),
        );

    testWidgets('порожня: огляд без переповнення', (tester) async {
      setScreen(tester, kNarrow);
      await tester.pumpWidget(library(kNarrow, pad: const EdgeInsets.fromLTRB(0, 24, 0, 24)));
      await tick(tester, 800);
      expect(tester.takeException(), isNull);
      await shot(tester, 'm_library_narrow');
    });

    testWidgets('з історією: рядки, вкладки «Історія» та «Плейлисти»', (tester) async {
      StorageService.addRecentFile('/tmp/proj/Frieren - 01.mkv');
      StorageService.addRecentFile('/tmp/proj/Dungeon Meshi - 12.mkv');
      StorageService.addRecentFile('https://example.com/stream/live.m3u8');
      StorageService.createPlaylist('Вечірній перегляд', [
        {'path': '/tmp/proj/Frieren - 01.mkv', 'title': 'Frieren - 01'},
        {'path': '/tmp/proj/Frieren - 02.mkv', 'title': 'Frieren - 02'},
      ]);
      addTearDown(() {
        StorageService.clearRecentFiles();
        for (final p in StorageService.getPlaylists()) {
          StorageService.deletePlaylist(p['id'] as String);
        }
      });
      setScreen(tester, kPortrait);
      await tester.pumpWidget(library(kPortrait, pad: const EdgeInsets.fromLTRB(0, 30, 0, 18)));
      await tick(tester, 800);
      expect(tester.takeException(), isNull);
      await shot(tester, 'm_library_portrait_history');

      await tester.tap(find.textContaining('Історія · ').first);
      await tick(tester, 700);
      await shot(tester, 'm_library_portrait_history_tab');
      await tester.tap(find.textContaining('Плейлисти · ').first);
      await tick(tester, 700);
      await shot(tester, 'm_library_portrait_playlists_tab');
      expect(tester.takeException(), isNull);
    });
  });

  // ── Налаштування на весь екран ─────────────────────────────────────────────

  group('AppSettingsDialog на телефоні', () {
    Future<void> openDialog(WidgetTester tester, Size size, EdgeInsets pad) async {
      setScreen(tester, size);
      await tester.pumpWidget(withInsets(
        pad,
        Scaffold(backgroundColor: Colors.black, body: AppSettingsDialog(scale: AppPlatform.mobileScale, controller: FakeController())),
      ));
      await tick(tester, 600);
    }

    // Кожна вкладка — окремий тест, щоб одне переповнення не ховало решту
    const tabs = [
      ('Вигляд', 'look'),
      ('Субтитри', 'subs'),
      ('Відтворення', 'playback'),
      ('Відео & GPU', 'video'),
      ('Anime4K', 'anime4k'),
      ('Звук', 'audio'),
      ('Розробник', 'dev'),
      ('Про програму', 'about'),
    ];

    /// Вкладка може бути поза екраном: рядок вкладок (портрет) і бічне меню (альбомна) прокручуються
    Future<void> goTab(WidgetTester tester, String label) async {
      if (label == 'Вигляд') return;
      if (find.text(label).evaluate().isEmpty) {
        final scrollable = find.descendant(of: find.byType(ListView).first, matching: find.byType(Scrollable)).first;
        final horizontal = tester.widget<Scrollable>(scrollable).axis == Axis.horizontal;
        for (var i = 0; i < 14 && find.text(label).evaluate().isEmpty; i++) {
          await tester.drag(scrollable, horizontal ? const Offset(-150, 0) : const Offset(0, -120));
          await tester.pump(const Duration(milliseconds: 100));
        }
      }
      await tester.ensureVisible(find.text(label).first);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text(label).first);
      await tick(tester, 600);
    }

    testWidgets('портрет: вкладки рядком, без бічного меню й «Гарячих клавіш»', (tester) async {
      await openDialog(tester, kPortrait, const EdgeInsets.fromLTRB(0, 30, 0, 18));
      expect(find.text('Налаштування'), findsNothing);
      expect(find.text('Гарячі клавіші'), findsNothing);
    });

    for (final (label, name) in tabs) {
      testWidgets('портрет 448: вкладка «$label» без переповнень', (tester) async {
        await openDialog(tester, kPortrait, const EdgeInsets.fromLTRB(0, 30, 0, 18));
        await goTab(tester, label);
        expect(tester.takeException(), isNull);
        await shot(tester, 'm_settings_portrait_$name');
      });

      testWidgets('вузький 360: вкладка «$label» без переповнень', (tester) async {
        await openDialog(tester, kNarrow, const EdgeInsets.fromLTRB(0, 24, 0, 24));
        await goTab(tester, label);
        expect(tester.takeException(), isNull);
      });

      testWidgets('альбомна 997×448: вкладка «$label» без переповнень', (tester) async {
        await openDialog(tester, kLandscape, const EdgeInsets.fromLTRB(46, 0, 0, 0));
        await goTab(tester, label);
        expect(tester.takeException(), isNull);
        await shot(tester, 'm_settings_landscape_$name');
      });
    }

    testWidgets('кнопки шапки й підвалу ≥ 48 dp', (tester) async {
      await openDialog(tester, kPortrait, const EdgeInsets.fromLTRB(0, 30, 0, 18));
      final close = find.byIcon(Symbols.close_rounded);
      final box = tester.getSize(find.ancestor(of: close, matching: find.byType(IconButton)).first);
      expect(box.width, greaterThanOrEqualTo(48));
      expect(box.height, greaterThanOrEqualTo(48));
      final done = tester.getSize(find.ancestor(of: find.text('Готово'), matching: find.byType(ElevatedButton)).first);
      expect(done.height, greaterThanOrEqualTo(48));
      final tab = tester.getSize(find.ancestor(of: find.text('Субтитри').first, matching: find.byType(InkWell)).first);
      expect(tab.height, greaterThanOrEqualTo(48));
    });

    testWidgets('«Розробник»: перемикач локальної медіатеки й ключ TheMovieDB одразу зберігаються', (tester) async {
      StorageService.saveLocalLibrary(false);
      StorageService.saveTmdbKey('');
      final seen = <bool>[];
      void listener() => seen.add(StorageService.localLibraryListenable.value);
      StorageService.localLibraryListenable.addListener(listener);
      addTearDown(() {
        StorageService.localLibraryListenable.removeListener(listener);
        StorageService.saveLocalLibrary(false);
        StorageService.saveTmdbKey('');
      });

      await openDialog(tester, kPortrait, const EdgeInsets.fromLTRB(0, 30, 0, 18));
      await goTab(tester, 'Розробник');

      final library = find.text('Локальна медіатека');
      await tester.ensureVisible(library);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(library);
      await tick(tester, 300);
      expect(StorageService.getLocalLibrary(), isTrue);
      expect(seen, [true], reason: '«Профіль» дізнається одразу, без перезапуску');
      await tester.tap(library);
      await tick(tester, 300);
      expect(StorageService.getLocalLibrary(), isFalse);
      expect(seen, [true, false]);

      final keyField = find.descendant(
        of: find.ancestor(of: find.byIcon(Symbols.key_rounded), matching: find.byType(AppSearchField)).first,
        matching: find.byType(TextField),
      );
      await tester.ensureVisible(keyField);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.enterText(keyField, '  abc123  ');
      await tester.pump();
      expect(StorageService.getTmdbKey(), 'abc123', reason: 'ключ зберігається без пробілів і без кнопки «Застосувати»');
      expect(tester.takeException(), isNull);
    });

    testWidgets('альбомна: бічне меню зліва, область вмісту праворуч', (tester) async {
      await openDialog(tester, kLandscape, const EdgeInsets.fromLTRB(46, 0, 0, 0));
      expect(find.text('Налаштування'), findsOneWidget);
      expect(find.text('Гарячі клавіші'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('рядок-перемикач на телефоні перемикається тапом по всьому рядку (≥ 48 dp)', (tester) async {
      await openDialog(tester, kPortrait, const EdgeInsets.fromLTRB(0, 30, 0, 18));
      await tester.tap(find.text('Відтворення').first);
      await tick(tester, 600);
      expect(find.text('Застосувати'), findsNothing);
      final title = find.text('Автовідтворення наступного епізоду');
      final row = find.ancestor(of: title, matching: find.byType(GestureDetector)).first;
      expect(tester.getSize(row).height, greaterThanOrEqualTo(48));
      await tester.tap(title); // не по самому перемикачу, а по підпису
      await tick(tester, 400);
      expect(find.text('Застосувати'), findsOneWidget);
    });

    testWidgets('вузький 360 dp: «Скасувати / Застосувати / Готово» вміщуються', (tester) async {
      await openDialog(tester, kNarrow, const EdgeInsets.fromLTRB(0, 24, 0, 24));
      await tester.tap(find.text('Відтворення').first);
      await tick(tester, 600);
      // змінюємо значення, щоб з'явились усі три кнопки
      await tester.tap(find.text('Автовідтворення наступного епізоду'));
      await tick(tester, 400);
      expect(tester.takeException(), isNull);
      expect(find.text('Скасувати'), findsOneWidget);
      expect(find.text('Застосувати'), findsOneWidget);
      final cancel = tester.getRect(find.text('Скасувати'));
      final done = tester.getRect(find.text('Готово'));
      expect(cancel.left, greaterThanOrEqualTo(0));
      expect(done.right, lessThanOrEqualTo(360));
      for (final t in ['Скасувати', 'Застосувати', 'Готово']) {
        final b = tester.getSize(find.ancestor(of: find.text(t), matching: find.byType(ElevatedButton)).first);
        expect(b.height, greaterThanOrEqualTo(40), reason: t); // після стиснення рядка: ≥ 48 × масштаб
      }
      await shot(tester, 'm_settings_narrow');
    });
  });

  group('Десктоп не зачеплено', () {
    late HikkaTestEnv env;

    setUp(() => env = HikkaTestEnv());
    tearDown(() => env.dispose());

    testWidgets('без перевизначення платформи розкладка десктопна', (tester) async {
      AppPlatform.debugMobile = false;
      expect(AppPlatform.isMobile, isFalse);
      setScreen(tester, const Size(1280, 800));
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: Colors.black,
          body: HomeHub(
            scale: 1.0,
            onOpenFile: (_) {},
            onOpenMultipleFiles: (_) {},
            onOpenQueue: (_, __) {},
            onOpenSettings: ({int? tab}) {},
          ),
        ),
      ));
      await tick(tester, 800);
      expect(HomeHub.isCompact(tester.element(find.byType(HomeHub))), isFalse);
      expect(tester.takeException(), isNull);
    });
  });
}
