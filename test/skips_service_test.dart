// The skip service with fakes (AniSkip answers, synthetic sound instead of a decoder): the site's own times teach the
// dub's shift; an unknown dub gets safe times, then exact ones after listening (the team's intro gets a skip of its
// own); mobile data is not spent; corrections by hand; downloads; the driver's chapters follow the plan, and the
// chapters menu shows the shift and where the times come from.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miki_miki/models/source_models.dart';
import 'package:miki_miki/services/app_log.dart';
import 'package:miki_miki/services/episode_check.dart';
import 'package:miki_miki/services/downloads/download_models.dart';
import 'package:miki_miki/services/network_status.dart';
import 'package:miki_miki/services/skips/anime_skip.dart';
import 'package:miki_miki/services/skips/aniskip.dart';
import 'package:miki_miki/services/skips/skip_align.dart';
import 'package:miki_miki/services/skips/skip_profiles.dart';
import 'package:miki_miki/services/skips/skip_service.dart';
import 'package:miki_miki/services/watch_models.dart';
import 'package:miki_miki/widgets/settings_drawer.dart';

import 'support/fakes.dart';
import 'support/remote_fakes.dart';
import 'support/skip_sounds.dart';

/// Our videos: 1420 s of the episode + an 8 s team intro + 22 s of credits
const double ours = 1450;

/// AniSkip's opening of episode [n] (on its 1420 s version): 60 s from 20 + 5n
double opAt(int n) => 20.0 + 5 * n;

final _song = music(2, 60);
final _intro = music(1, 8);

/// The first 150 s of episode [n] of the dub: the intro, talk, the opening (8 s later than AniSkip's), talk
Int16List firstMinutes(int n) {
  final before = opAt(n);
  return pcmEpisode([_intro, speech(10 * n, before), _song, speech(10 * n + 1, 150 - 8 - before - 60)], noise: n, gain: n.isEven ? 0.85 : 1);
}

int epOf(String url) => int.parse(RegExp(r'e(\d+)').allMatches(url).last.group(1)!);

class Fx {
  Fx({bool listen = true}) {
    service = SkipService(
      aniskip: AniSkip(
        persist: false,
        get: (u) async {
          asked.add(u);
          final n = int.parse(u.pathSegments.last);
          return (
            200,
            jsonEncode({
              'found': true,
              'results': [
                {'interval': {'startTime': opAt(n), 'endTime': opAt(n) + 60}, 'skipType': 'op', 'skipId': 'op$n', 'episodeLength': 1420.0},
                {'interval': {'startTime': 1330.0, 'endTime': 1410.0}, 'skipType': 'ed', 'skipId': 'ed$n', 'episodeLength': 1420.0},
              ],
            }),
          );
        },
      ),
      // Anime Skip knows none of these titles
      animeSkip: AnimeSkip(
        persist: false,
        post: (u, body, headers) async => u.host == 'graphql.anilist.co'
            ? (404, '{"errors":[{"message":"Not Found.","status":404}],"data":{"Media":null}}')
            : (200, '{"data":{"findShowsByExternalId":[]}}'),
      ),
      profiles: profiles,
      decode: (url, {headers = const {}, start = 0, length = 240}) async {
        decoded.add(url);
        return firstMinutes(epOf(url));
      },
      malId: (k) async => 52991,
      videoOf: (sourceId, e) async => Video(url: 'https://moon/${e.url}/1080.m3u8', title: '480p'),
      network: () => net,
      listenOn: () => listen,
      printsDir: dir.path,
      listenDelay: Duration.zero,
      listenLength: 150,
      run: <M, R>(R Function(M) fn, M message) async => fn(message),
    );
  }

  final box = <String, dynamic>{};
  late final SkipProfiles profiles = SkipProfiles(load: () => box, save: (m) => box.addAll(jsonDecode(jsonEncode(m)) as Map<String, dynamic>));
  final List<Uri> asked = [];
  final List<String> decoded = [];
  final Directory dir = Directory.systemTemp.createTempSync('skips');
  final NetworkStatus net = NetworkStatus()..apply(online: true, metered: false);
  late final SkipService service;

  static const group = WatchGroup(id: 'src|a|1', sourceId: 'src', label: 'Команда А', episodes: [
    SEpisode(url: 'e1', name: '1', number: 1),
    SEpisode(url: 'e2', name: '2', number: 2),
    SEpisode(url: 'e3', name: '3', number: 3),
  ]);

  SkipRequest req(int n, {List<TimeStamp> site = const []}) => SkipRequest(
        animeKey: 'hikka:frieren',
        group: group,
        index: n - 1,
        epKey: '$n',
        number: n,
        duration: ours,
        video: Video(url: 'https://moon/e$n/1080.m3u8', title: '1080p', timestamps: site),
      );

  TimeStamp? stamp(ChapterType t) => service.current.value?.stamps.where((s) => s.type == t).firstOrNull;
  TimeStamp? named(String name) => service.current.value?.stamps.where((s) => s.name == name).firstOrNull;

  Future<void> until(bool Function() ok, {int ms = 20000}) async {
    final sw = Stopwatch()..start();
    while (!ok()) {
      if (sw.elapsedMilliseconds > ms) fail('не дочекалися');
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  void dispose() {
    dir.deleteSync(recursive: true);
    net.dispose();
  }
}

void main() {
  setUpAll(loadTestFonts);

  test("the site's own times are used as they are and teach the dub's shift for episodes without them", () async {
    final f = Fx(listen: false);
    addTearDown(f.dispose);
    final site = [const TimeStamp(33, 93, 'Опенінґ', ChapterType.opening)];
    await f.service.attach(f.req(1, site: site));
    expect(f.service.current.value!.source, 'сайт');
    expect(f.service.current.value!.stamps, site);
    await f.until(() => f.profiles.shiftFor('hikka:frieren', Fx.group) != null);
    expect(f.profiles.shiftFor('hikka:frieren', Fx.group)!.mid, 8);
    expect(f.profiles.shiftFor('hikka:frieren', Fx.group)!.source, 'site');

    await f.service.attach(f.req(2));
    final op = f.stamp(ChapterType.opening)!;
    expect((op.start, op.end, op.exact), (38, 98, true));
    expect(f.stamp(ChapterType.ending)!.start, 1338);
    expect(f.service.current.value!.source, 'AniSkip');
    expect(f.asked.map((u) => u.queryParameters['episodeLength']).toSet(), {'0', '1450'});
  });

  test('an unknown dub: safe times at first, exact after listening; the intro gets its own skip', () async {
    final f = Fx();
    addTearDown(f.dispose);
    await f.service.attach(f.req(1));
    // 30 s longer than AniSkip's version: only where the opening surely is
    final safe = f.stamp(ChapterType.opening)!;
    expect((safe.start, safe.end, safe.exact), (55, 85, false));
    expect(f.service.current.value!.adjustable, isTrue);

    await f.until(() => f.service.current.value?.exact == true);
    final plan = f.service.current.value!;
    expect(plan.source, 'AniSkip + аналіз звуку');
    final op = f.stamp(ChapterType.opening)!;
    expect(op.start, closeTo(33 + SkipService.edgeIn, 0.35));
    expect(op.end, closeTo(93 - SkipService.edgeOut, 0.35));
    final intro = f.named('Заставка')!;
    expect(intro.start, 0);
    expect(intro.end, closeTo(8 - SkipService.edgeOut, 0.35));
    expect(intro.exact, isTrue);
    expect(f.stamp(ChapterType.ending)!.start, closeTo(1338, 0.35), reason: 'the ending moves by the heard shift too');
    expect(f.decoded.map(epOf), [1, 2], reason: 'this episode and the next one');
    expect(f.profiles.shiftFor('hikka:frieren', Fx.group)!.mid, closeTo(8, 0.3));
    expect(f.profiles.introFor('hikka:frieren', Fx.group), closeTo(8, 0.3));
    expect(f.profiles.episode('hikka:frieren', Fx.group, '2')!.opStart, closeTo(38, 0.3));
    expect(f.dir.listSync().length, 2, reason: 'fingerprints are kept for the next comparisons');

    // The next episode: its opening was heard already (as the neighbour); nothing is decoded again
    await f.service.attach(f.req(2));
    expect(f.stamp(ChapterType.opening)!.start, closeTo(38 + SkipService.edgeIn, 0.35));
    // An episode not heard: AniSkip moved by the heard shift, exact; the dub's intro as a button only
    await f.service.attach(f.req(3));
    final op3 = f.stamp(ChapterType.opening)!;
    expect(op3.start, closeTo(43, 0.3));
    expect(op3.exact, isTrue);
    expect(f.named('Заставка')!.exact, isFalse);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(f.decoded.length, 2, reason: 'the shift is known: no need to listen again');
  });

  test('the log says what AniSkip had and what came of it — and why nothing', () async {
    final keep = AppLog.instance;
    final log = AppLog.instance = AppLog();
    addTearDown(() => AppLog.instance = keep);
    final f = Fx(listen: false);
    addTearDown(f.dispose);
    List<String> lines() => [for (final e in log.entries) if (e.tag == 'пропуск' && !e.message.startsWith('аналіз звуку')) e.message];

    await f.service.attach(f.req(1));
    expect(lines().single, 'Команда А · 1, відео 1450 с; AniSkip 52991/1: оп 0:25–1:25 на версії 1420 с (+30 с); '
        'ед 22:10–23:30 на версії 1420 с (+30 с); Anime Skip: нічого не позначено → Опенінґ 0:55–1:25 (безпечно), Ендінґ 22:40–23:30 (безпечно); '
        'зсув 0.0…30.0 с (length) [AniSkip]');
    expect(log.entries.where((e) => e.message.startsWith('аналіз звуку')).map((e) => e.message), ['аналіз звуку: вимкнено в налаштуваннях'],
        reason: 'why it is not listened to');
    await f.service.refresh();
    expect(lines(), hasLength(1), reason: 'the same plan is not written again');

    // Another version (a double episode): nothing fits, and the log says so
    final long = SkipRequest(animeKey: 'hikka:frieren', group: Fx.group, index: 1, epKey: '2', number: 2, duration: 2866, video: const Video(url: 'https://moon/e2/1080.m3u8', title: '1080p'));
    await f.service.attach(long);
    expect(lines().last, contains('(+1446 с: інша версія)'));
    expect(lines().last, endsWith('→ пропусків нема'));

    // Our numbering may not be MyAnimeList's
    final unknown = SkipRequest(animeKey: 'hikka:frieren', group: Fx.group, index: 2, epKey: '3', number: null, duration: ours, video: const Video(url: 'https://moon/e3/1080.m3u8', title: '1080p'));
    await f.service.attach(unknown);
    expect(lines().last, 'Команда А · 3, відео 1450 с; AniSkip: номер серії невідомий → пропусків нема');
  });

  test('mobile data is not spent on listening', () async {
    final f = Fx();
    addTearDown(f.dispose);
    f.net.apply(online: true, metered: true);
    await f.service.attach(f.req(1));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(f.decoded, isEmpty);
    expect(f.stamp(ChapterType.opening)!.exact, isFalse);
  });

  test('a hand correction moves every episode of the dub; the opening can be marked where it starts', () async {
    final f = Fx(listen: false);
    addTearDown(f.dispose);
    await f.service.attach(f.req(1));
    expect(f.service.current.value!.opBase, opAt(1));
    await f.service.openingAt(33);
    var op = f.stamp(ChapterType.opening)!;
    expect((op.start, op.end, op.exact), (33, 93, true));
    expect(f.service.current.value!.shift!.source, 'user');

    await f.service.shiftBy(0.5);
    expect(f.stamp(ChapterType.opening)!.start, 33.5);
    await f.service.attach(f.req(2));
    op = f.stamp(ChapterType.opening)!;
    expect((op.start, op.exact), (38.5, true));

    await f.service.resetShift();
    expect(f.stamp(ChapterType.opening)!.exact, isFalse);
    f.service.detach();
    expect(f.service.current.value, isNull);
  });

  test('a finished download gets AniSkip for offline and is listened to with the dub\'s other download', () async {
    final f = Fx();
    addTearDown(f.dispose);
    f.net.apply(online: true, metered: true); // local files cost nothing
    DownloadItem item(int n) => DownloadItem(
          id: 'd$n',
          animeKey: 'hikka:frieren',
          animeTitle: 'Фрірен',
          groupId: Fx.group.id,
          groupLabel: Fx.group.label,
          sourceId: 'src',
          episode: Fx.group.episodes[n - 1],
          epKey: '$n',
          title: 'Серія $n',
          order: n - 1,
          count: 3,
          addedAt: DateTime(2026),
          state: DownloadState.done,
          duration: ours,
          file: 'e$n.mp4',
        );
    final dub = [item(1), item(3)];
    await f.service.onDownloaded(item(3), dub: dub, videoOf: (i) => Video(url: '/downloads/${i.file}', title: 'Завантажено'));
    expect(f.asked.map((u) => u.pathSegments.last).toSet(), {'3'});
    expect(f.decoded, ['/downloads/e3.mp4', '/downloads/e1.mp4']);
    expect(f.profiles.episode('hikka:frieren', Fx.group, '3')!.opStart, closeTo(43, 0.3));
    expect(f.profiles.episode('hikka:frieren', Fx.group, '1')!.opStart, closeTo(33, 0.3));
  });

  test("the driver's chapters follow the plan; leaving the episode drops it", () async {
    final f = Fx(listen: false);
    addTearDown(f.dispose);
    final r = Rig(skips: f.service);
    await r.driver.start(r.launch());
    r.started(dur: const Duration(seconds: 1450));
    await f.until(() => r.driver.chapters.isNotEmpty);
    final op = r.driver.chapters.firstWhere((c) => c.title == 'Opening');
    expect((op.startTime, op.endTime, op.autoSkip), (const Duration(seconds: 55), const Duration(seconds: 85), false));
    expect(r.driver.skipPlan!.source, 'AniSkip');
    expect(f.service.request!.number, 1);

    await r.driver.skipOpeningAt(const Duration(seconds: 33));
    await f.until(() => r.driver.chapters.any((c) => c.title == 'Opening' && c.autoSkip));
    expect(r.driver.chapters.firstWhere((c) => c.title == 'Opening').startTime, const Duration(seconds: 33));

    r.driver.stop();
    expect(f.service.current.value, isNull);
    expect(r.driver.skipPlan, isNull);
  });

  test('a gap in the dub\'s numbering (Gintama: 1, 3, 4…) keeps AniSkip; numbers that are not Hikka\'s do not', () async {
    final f = Fx(listen: false);
    addTearDown(f.dispose);
    final r = Rig(episodes: [1, 3, 4], skips: f.service);
    await r.driver.start(r.launch(epKey: '3'));
    r.started(dur: const Duration(seconds: 1450));
    await f.until(() => f.service.request != null);
    expect(f.service.request!.number, 3);
    r.driver.stop();

    final shifted = Fx(listen: false);
    addTearDown(shifted.dispose);
    final s = Rig(episodes: [13, 14, 15], skips: shifted.service);
    await s.driver.start(s.launch(epKey: '14'));
    s.started(dur: const Duration(seconds: 1450));
    await shifted.until(() => shifted.service.request != null);
    expect(shifted.service.request!.number, isNull, reason: 'continuous numbering: 14 is not Hikka\'s 14');
    s.driver.stop();
  });

  test('a dub that joined mid-season (Re:Zero 4 by «Далі Буде»: 10–19) beside one from 1: its numbers are the season\'s', () async {
    const rezero = HikkaEpisodeInfo(released: 19, total: 19, finished: true);
    final f = Fx(listen: false);
    addTearDown(f.dispose);
    final r = Rig(episodes: [for (var i = 10; i <= 19; i++) i], others: [for (var i = 1; i <= 19; i++) i], skips: f.service);
    await r.driver.start(r.launch(epKey: '14', hikka: rezero));
    r.started(dur: const Duration(seconds: 1420));
    await f.until(() => f.service.request != null);
    expect(f.service.request!.number, 14);
    r.driver.stop();

    final alone = Fx(listen: false);
    addTearDown(alone.dispose);
    final s = Rig(episodes: [for (var i = 10; i <= 19; i++) i], skips: alone.service);
    await s.driver.start(s.launch(epKey: '14', hikka: rezero));
    s.started(dur: const Duration(seconds: 1420));
    await alone.until(() => alone.service.request != null);
    expect(alone.service.request!.number, isNull, reason: 'alone it may be counted on from a previous season');
    s.driver.stop();
  });

  testWidgets('the chapters menu: the shift of the times, "the opening started here", where the times come from', (t) async {
    t.view.physicalSize = const Size(1280, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    // All of it in the test's fake time: the fakes answer at once
    final f = Fx(listen: false);
    final r = Rig(skips: f.service);
    await r.driver.start(r.launch());
    r.started(dur: const Duration(seconds: 1450));
    await t.pump();
    expect(r.driver.chapters, isNotEmpty);
    final c = FakeController();
    c.fakePlayer.tickPosition(const Duration(seconds: 34));
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        backgroundColor: const Color(0xFF3B4A57),
        body: ListenableBuilder(
          listenable: r.driver,
          builder: (context, _) => Stack(children: [
            SettingsDrawer(
              scale: 1.0,
              screenWidth: 1280,
              drawerAnchorPixelX: 1100,
              activeDrawer: 'chapters',
              activeDrawerPrev: null,
              player: c.fakePlayer,
              currentSpeed: 1.0,
              currentHwdec: 'auto',
              subtitleTracks: const [],
              audioTracks: const [],
              chapters: r.driver.chapters,
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
              remote: r.driver,
            ),
          ]),
        ),
      ),
    ));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('Зсув таймкодів'), findsOneWidget);
    expect(find.text('≈+15 с'), findsOneWidget, reason: 'the middle of what the lengths allow');
    expect(find.textContaining('Приблизно'), findsOneWidget);
    expect(find.text('Опенінґ почався тут'), findsOneWidget);

    await t.tap(find.text('Опенінґ почався тут'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(f.service.current.value?.shift?.source, 'user');
    expect(find.text('+9 с'), findsOneWidget, reason: '34 s − AniSkip\'s 25 s');
    expect(find.textContaining('вручну'), findsOneWidget);

    await t.tap(find.byKey(const ValueKey('skipshift-minus')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('+8,5 с'), findsOneWidget);
    expect(SettingsDrawer.skipNote(const SkipPlan(key: 'k', stamps: [], shift: StartShift.exact(3, 'audio'), source: 'AniSkip + аналіз звуку')),
        contains('підігнані'));
    f.dispose();
  });
}
