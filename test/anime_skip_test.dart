// Anime Skip, the second base of skip times: its marks («Intro» at 474, «Canon» at 567…) read into AniSkip's form, the
// show found by AniList id, remembered; and the player's plan from it where AniSkip has nothing (Vinland Saga 2,
// episode 11). Real answers in test/data/skips. No network.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:miki_miki/models/source_models.dart';
import 'package:miki_miki/services/network_status.dart';
import 'package:miki_miki/services/skips/anime_skip.dart';
import 'package:miki_miki/services/skips/aniskip.dart';
import 'package:miki_miki/services/skips/skip_align.dart';
import 'package:miki_miki/services/skips/skip_profiles.dart';
import 'package:miki_miki/services/skips/skip_service.dart';
import 'package:miki_miki/services/watch_models.dart';

String fixture(String name) => File('test/data/skips/$name').readAsStringSync();

/// The real answers: AniList's id of Vinland Saga 2 (MyAnimeList 49387), Anime Skip's shows of it
class FakeBases {
  final List<Uri> asked = [];
  final List<String> bodies = [];
  bool down = false;

  Future<(int, String)> post(Uri u, String body, Map<String, String> headers) async {
    asked.add(u);
    bodies.add(body);
    if (down) throw const SocketException('offline');
    if (u.host == 'graphql.anilist.co') {
      return body.contains('49387') ? (200, fixture('anilist_vinland2.json')) : (404, fixture('anilist_none.json'));
    }
    expect(headers['X-Client-ID'], AnimeSkip.sharedClientId);
    return body.contains('serviceId: \\"136430') ? (200, fixture('animeskip_vinland2.json')) : (200, '{"data":{"findShowsByExternalId":[]}}');
  }
}

void main() {
  test('the marks: a part runs to the next mark; only openings, endings, recaps; the longest per version', () {
    final all = animeSkipTimes(jsonDecode(fixture('animeskip_vinland2.json')));
    final e11 = all[11]!;
    expect(e11.map((t) => (t.kind, t.start, t.end)), [
      (SkipKind.op, 474.0833333333333, 567.0833333333334),
      (SkipKind.ed, 1451.9999983333332, 1545.0833333333333),
    ]);
    expect(e11.first.episodeLength, 1555.041666);
    expect(e11.first.base, 'Anime Skip');
    // Episode 10: «Credits» again for 10 s after the preview is not the ending
    expect(all[10]!.where((t) => t.kind == SkipKind.ed).map((t) => t.length.round()), [94]);
    // Episode 3 is marked by two people (two shows of one AniList title); a recap at the start
    expect(all[3]!.where((t) => t.kind == SkipKind.op).map((t) => t.start.round()), unorderedEquals([351, 346]));
    expect(all[3]!.any((t) => t.kind == SkipKind.recap && t.start > 15 && t.end < 40), isTrue);
    // Episode 14: the ending marked after a «Transition»
    expect(all[14]!.firstWhere((t) => t.kind == SkipKind.ed).start.round(), 1455);
    expect(animeSkipKind('New Credits'), SkipKind.ed);
    expect(animeSkipKind('Preview'), isNull);
  });

  test('Anime Skip fills AniSkip\'s gaps, it does not blur its exact times', () {
    const aniskip = [AniSkipTime(SkipKind.op, 346, 437, 1555, id: 'x'), AniSkipTime(SkipKind.ed, 2735, 2825, 2866, id: 'y')];
    const animeSkip = [
      AniSkipTime(SkipKind.op, 351, 438, 1555, id: 'as:1:op'),
      AniSkipTime(SkipKind.ed, 1452, 1545, 1555, id: 'as:1:ed'),
      AniSkipTime(SkipKind.recap, 15, 40, 1555, id: 'as:1:recap'),
    ];
    final all = withFallback(aniskip, animeSkip, 1555);
    expect(all.map((t) => t.id), ['x', 'y', 'as:1:ed', 'as:1:recap'], reason: 'AniSkip\'s ending is of another version');
    final plan = alignSkips('k', all, 1555)!;
    final op = plan.stamps.firstWhere((s) => s.type == ChapterType.opening);
    expect((op.start, op.end, op.exact), (346, 437, true), reason: 'AniSkip\'s alone: still exact');
    expect(plan.stamps.firstWhere((s) => s.type == ChapterType.ending).start, 1452);
    expect(basesOf(all, 1555), 'AniSkip і Anime Skip');
    expect(basesOf(aniskip, 1555), 'AniSkip');
  });

  test('found by AniList id, remembered; a title AniList does not know: nothing; offline: what is remembered', () async {
    final web = FakeBases();
    var now = DateTime(2026, 11, 20);
    final dir = Directory.systemTemp.createTempSync('anime_skip');
    addTearDown(() => dir.deleteSync(recursive: true));
    final a = AnimeSkip(post: web.post, cachePath: '${dir.path}/c.json', now: () => now);
    final t11 = (await a.times(49387, 11))!;
    expect(t11.map((t) => t.kind), [SkipKind.op, SkipKind.ed]);
    expect(web.bodies.last, contains('serviceId: \\"136430'));
    expect((await a.times(49387, 12))!.map((t) => t.kind), contains(SkipKind.op));
    expect(web.asked, hasLength(2), reason: 'one AniList id and one show for every episode');
    expect(await a.times(999999999, 1), isEmpty);
    await a.save();

    web.down = true;
    now = now.add(const Duration(days: 30));
    final b = AnimeSkip(post: web.post, cachePath: '${dir.path}/c.json', now: () => now);
    expect((await b.times(49387, 11))!.map((t) => t.kind), [SkipKind.op, SkipKind.ed], reason: 'old, but nothing better offline');
    expect(await AnimeSkip(post: web.post, persist: false).times(49387, 11), isNull, reason: 'nothing remembered');
  });

  test('nothing in AniSkip, the times in Anime Skip: Vinland Saga 2, episode 11 gets its chapters', () async {
    final web = FakeBases();
    final service = SkipService(
      aniskip: AniSkip(persist: false, get: (u) async => (404, '{"found":false,"results":[],"statusCode":404}')),
      animeSkip: AnimeSkip(post: web.post, persist: false),
      profiles: SkipProfiles(load: () => {}, save: (_) {}),
      malId: (k) async => 49387,
      network: () => NetworkStatus()..apply(online: true, metered: true),
      listenOn: () => false,
      run: <M, R>(R Function(M) fn, M message) async => fn(message),
    );
    const group = WatchGroup(id: 'g', sourceId: 'mikai', label: 'Dzuski', episodes: [SEpisode(url: 'e11', name: '11', number: 11)]);
    final plan = (await service.planFor(const SkipRequest(
      animeKey: 'hikka:vinland-saga-season-2',
      group: group,
      index: 0,
      epKey: '11',
      number: 11,
      duration: 1555.0,
      video: Video(url: 'https://ashdi/e11.m3u8', title: '1080p'),
    )))!;
    expect(plan.source, 'Anime Skip');
    final op = plan.stamps.firstWhere((s) => s.type == ChapterType.opening);
    final ed = plan.stamps.firstWhere((s) => s.type == ChapterType.ending);
    expect((op.start.round(), op.end.round(), op.exact), (474, 567, true), reason: 'the same length: exact');
    expect((ed.start.round(), ed.end.round(), ed.exact), (1452, 1545, true));
  });
}
