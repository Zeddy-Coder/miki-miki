// Skips without the site's times: the AniSkip client (cache, versions, failures), moving AniSkip's times onto our
// video (safe while the shift is unknown, ambiguous versions), what is learned of dubs, and listening (the fingerprint
// finds the team's intro and the opening at different places of two episodes). No network, no player.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:miki_miki/models/source_models.dart';
import 'package:miki_miki/services/downloads/download_models.dart';
import 'package:miki_miki/services/skips/aniskip.dart';
import 'package:miki_miki/services/skips/audio_print.dart';
import 'package:miki_miki/services/skips/skip_align.dart';
import 'package:miki_miki/services/skips/skip_profiles.dart';
import 'package:miki_miki/services/watch_models.dart';

import 'support/skip_sounds.dart';

/// An answer of the AniSkip API
String apiAnswer(List<(String type, double s, double e, double len, String id)> rows) => jsonEncode({
      'found': rows.isNotEmpty,
      'results': [
        for (final r in rows)
          {
            'interval': {'startTime': r.$2, 'endTime': r.$3},
            'skipType': r.$1,
            'skipId': r.$5,
            'episodeLength': r.$4,
          },
      ],
      'message': 'ok',
      'statusCode': 200,
    });

AniSkipTime op(double s, double e, double len, [String id = '']) => AniSkipTime(SkipKind.op, s, e, len, id: id);
AniSkipTime ed(double s, double e, double len, [String id = '']) => AniSkipTime(SkipKind.ed, s, e, len, id: id);

TimeStamp? stampOf(SkipPlan? p, ChapterType t) => p?.stamps.where((s) => s.type == t).firstOrNull;

void main() {
  group('AniSkip', () {
    test('asks for every kind and the length, reads versions; 404 is "nothing marked", errors are null', () async {
      final asked = <Uri>[];
      var status = 200;
      final skip = AniSkip(
        persist: false,
        get: (u) async {
          asked.add(u);
          if (status != 200) return (status, '{"found":false}');
          return (200, apiAnswer([('op', 116.748, 206.748, 1510.092, 'a'), ('ed', 1417.135, 1507.135, 1510.102, 'b'), ('bogus', 1, 2, 3, 'c')]));
        },
      );
      final t = await skip.times(52991, 1, length: 1512);
      expect(t!.map((x) => x.kind), [SkipKind.op, SkipKind.ed]);
      expect(t.first.episodeLength, 1510.092);
      expect(t.first.length, closeTo(90, 1e-9));
      final q = asked.single.queryParametersAll;
      expect(q['types'], ['op', 'ed', 'mixed-op', 'mixed-ed', 'recap']);
      expect(q['episodeLength'], ['1510'], reason: 'the length goes in 5-second steps');
      expect(asked.single.path, '/v2/skip-times/52991/1');

      status = 404;
      expect(await skip.times(52991, 2), isEmpty);
      status = 500;
      expect(await skip.times(52991, 3), isNull);
      expect(await skip.times(0, 3), isEmpty, reason: 'no MAL id: nothing to ask');
    });

    test('answers are remembered on disk, refreshed after a week, and the old one serves when AniSkip is down', () async {
      final dir = Directory.systemTemp.createTempSync('aniskip');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/cache.json';
      var calls = 0;
      var down = false;
      var now = DateTime(2026, 11, 1);
      Future<(int, String)> get(Uri u) async {
        calls++;
        if (down) throw const SocketException('offline');
        return (200, apiAnswer([('op', 10, 100, 1420, 'x$calls')]));
      }

      final a = AniSkip(get: get, cachePath: path, now: () => now);
      expect((await a.times(1, 1))!.single.id, 'x1');
      expect((await a.times(1, 1))!.single.id, 'x1');
      expect(calls, 1, reason: 'a fresh answer is not asked again');
      await a.save();

      // Another run of the app: from the disk
      final b = AniSkip(get: get, cachePath: path, now: () => now);
      expect((await b.times(1, 1))!.single.id, 'x1');
      expect(calls, 1);

      // A week later it is asked again; offline the old answer still serves
      now = now.add(const Duration(days: 8));
      down = true;
      expect((await b.times(1, 1))!.single.id, 'x1');
      expect(calls, 2);
      down = false;
      expect((await b.times(1, 1))!.single.id, 'x3');

      // Offline, a length a few seconds off (a downloaded file measures a little differently): the neighbouring step
      expect((await b.times(1, 1, length: 1420))!.single.id, 'x4');
      down = true;
      expect((await b.times(1, 1, length: 1423))!.single.id, 'x4');
      expect(await b.times(1, 1, length: 1500), isNull, reason: 'nothing remembered near this length');
    });

    test('the same question at once is asked once; candidates merge the trusted and the nearest versions', () async {
      var calls = 0;
      final skip = AniSkip(
        persist: false,
        get: (u) async {
          calls++;
          await Future<void>.delayed(const Duration(milliseconds: 5));
          final len = u.queryParameters['episodeLength'];
          return (
            200,
            len == '0'
                ? apiAnswer([('op', 3.221, 93.221, 1559.949, 'top'), ('ed', 1417.135, 1507.135, 1510.102, 'end')])
                : apiAnswer([('op', 116.748, 206.748, 1510.092, 'near'), ('ed', 1417.135, 1507.135, 1510.102, 'end')]),
          );
        },
      );
      final both = await Future.wait([skip.times(52991, 1), skip.times(52991, 1)]);
      expect(calls, 1);
      expect(both[0], same(both[1]));

      final c = await skip.candidates(52991, 1, 1540);
      expect(c!.map((t) => t.id), ['top', 'end', 'near'], reason: 'the ending of both answers is one record');
      expect(AniSkip.bucket(1512.4), 1510);
      expect(AniSkip.bucket(1513), 1515);
      expect(AniSkip.bucket(0), 0);
    });

    test('inexact times survive a download\'s record', () {
      final item = DownloadItem(
        id: 'd',
        animeKey: 'hikka:a',
        animeTitle: 'A',
        groupId: 'g',
        groupLabel: 'G',
        sourceId: 's',
        episode: const SEpisode(url: 'e1', name: '1', number: 1),
        epKey: '1',
        title: '1',
        order: 0,
        count: 1,
        addedAt: DateTime(2026),
        timestamps: const [TimeStamp(55, 85, 'Опенінґ', ChapterType.opening, false), TimeStamp(1300, 1390, 'Ендінґ', ChapterType.ending)],
      );
      final back = DownloadItem.fromJson(jsonDecode(jsonEncode(item.toJson())))!;
      expect(back.timestamps.map((t) => (t.start, t.exact)), [(55.0, false), (1300.0, true)]);
    });

    test('a time survives the disk', () {
      final t = op(1.5, 91.5, 1420.25, 'id1');
      final back = AniSkipTime.fromJson(jsonDecode(jsonEncode(t.toJson())));
      expect((back!.kind, back.start, back.end, back.episodeLength, back.id), (SkipKind.op, 1.5, 91.5, 1420.25, 'id1'));
      expect(AniSkipTime.fromApi({'interval': {'startTime': 5, 'endTime': 4}, 'skipType': 'op', 'episodeLength': 100}), isNull);
    });
  });

  group('Moving AniSkip times onto our video', () {
    test('the same length: the times as they are, exact (may be skipped by itself)', () {
      final p = alignSkips('k', [op(85, 175, 1420), ed(1300, 1390, 1420.4)], 1420.8);
      expect(p!.exact, isTrue);
      expect(p.shift!.mid, 0);
      final o = stampOf(p, ChapterType.opening)!;
      expect((o.start, o.end, o.name), (85, 175, 'Опенінґ'));
      expect(stampOf(p, ChapterType.ending)!.start, 1300);
      expect(p.opBase, 85);
      expect(p.source, 'AniSkip');
    });

    test('a longer video, the shift unknown: only where the opening surely is, and not by itself', () {
      // 30 s longer: the opening is somewhere between 85…115 → 175…205
      final p = alignSkips('k', [op(85, 175, 1420)], 1450);
      final o = stampOf(p, ChapterType.opening)!;
      expect((o.start, o.end, o.exact), (115, 175, false));
      expect(p!.adjustable, isTrue);
      expect(p.extra, 30);
      expect(p.shift!.exact, isFalse);

      // 75 s longer leaves only 15 s that surely belong to a 90-second opening; more and it is another version
      expect(stampOf(alignSkips('k', [op(85, 175, 1420)], 1495), ChapterType.opening)!.end - 160, closeTo(15, 1e-9));
      expect(alignSkips('k', [op(85, 175, 1420)], 1496), isNull);
      // A short opening and a wide range: nothing worth a button
      expect(alignSkips('k', [op(85, 105, 1420)], 1450), isNull);
    });

    test('a shorter video: some of the start may have been cut', () {
      final p = alignSkips('k', [op(85, 175, 1420)], 1400);
      final o = stampOf(p, ChapterType.opening)!;
      expect((o.start, o.end, o.exact), (85, 155, false));
      // Gintama 1: AniSkip's opening on a 1454 s version, a TV rip of 1420 s
      final g = stampOf(alignSkips('k', [op(217.5, 307.542, 1454.429), ed(2735.6, 2825.6, 2865.988)], 1420), ChapterType.opening)!;
      expect(g.start, 217.5);
      expect(g.end, closeTo(273.11, 0.01));
      // Up to 75 s cut, as inserted; more and it is another version
      expect(stampOf(alignSkips('k', [op(85, 175, 1420)], 1345), ChapterType.opening)!.end, 100);
      expect(alignSkips('k', [op(85, 175, 1420)], 1344), isNull);
    });

    test('a learned shift makes the times exact, if the lengths allow it; a hand correction always does', () {
      final site = alignSkips('k', [op(85, 175, 1420), ed(1300, 1390, 1420)], 1450, known: const StartShift.exact(12, 'site'));
      expect(site!.exact, isTrue);
      expect(stampOf(site, ChapterType.opening)!.start, 97);
      expect(stampOf(site, ChapterType.ending)!.start, 1312);

      // 40 s does not fit a video only 30 s longer: the safe times stay
      final off = alignSkips('k', [op(85, 175, 1420)], 1450, known: const StartShift.exact(40, 'site'));
      expect(stampOf(off, ChapterType.opening)!.exact, isFalse);

      final user = alignSkips('k', [op(85, 175, 1420)], 1450, known: const StartShift.exact(40, 'user'));
      expect(stampOf(user, ChapterType.opening)!.start, 125);
      expect(user!.shift!.source, 'user');

      // A range learned from the site narrows the safe times
      final range = alignSkips('k', [op(85, 175, 1420)], 1450, known: const StartShift(8, 14, 'site'));
      final o = stampOf(range, ChapterType.opening)!;
      expect((o.start, o.end, o.exact), (99, 183, false));
    });

    test('versions that put the opening in different places: nothing, until the shift is known', () {
      // Frieren 1: the most trusted opening at 3.2 s of a 1559.9 s version, the nearest at 116.7 s of a 1510.1 s one
      final all = [op(3.221, 93.221, 1559.949, 'top'), op(116.748, 206.748, 1510.092, 'near'), ed(1417.135, 1507.135, 1510.102, 'e')];
      final p = alignSkips('k', all, 1540);
      expect(stampOf(p, ChapterType.opening), isNull, reason: 'no place is the opening for every version');
      expect(stampOf(p, ChapterType.ending), isNotNull);
      expect(p!.opBase, 3.221, reason: 'still can be marked by hand against the likeliest version');

      // 28 s inserted fits only the 1510 s version
      final known = alignSkips('k', all, 1540, known: const StartShift.exact(28, 'audio'));
      final o = stampOf(known, ChapterType.opening)!;
      expect(o.start, closeTo(144.748, 1e-9));
      expect(o.end, closeTo(234.748, 1e-9));
      expect(o.exact, isTrue);
      expect(known!.opBase, 116.748);

      // Versions that agree are all kept safe together
      final agree = alignSkips('k', [op(85, 175, 1420), op(86, 176, 1425)], 1430);
      final a = stampOf(agree, ChapterType.opening)!;
      expect((a.start, a.end), (95, 175), reason: 'the latest start of either, the earliest end of either');
    });

    test('openings: op, else mixed-op; endings: ed, else mixed-ed; recaps', () {
      final p = alignSkips('k', [
        const AniSkipTime(SkipKind.mixedOp, 0, 89, 1420),
        const AniSkipTime(SkipKind.mixedEd, 1330, 1420, 1420),
        const AniSkipTime(SkipKind.recap, 89, 130, 1420),
      ], 1420);
      expect(p!.stamps.map((s) => (s.name, s.type)), [
        ('Опенінґ', ChapterType.mixedOp),
        ('Рекап', ChapterType.recap),
        ('Ендінґ', ChapterType.ending),
      ]);
      expect(pickVersions([op(1, 91, 1420, 'a'), op(1, 91, 1450, 'b')], 1452).single.id, 'b');
      expect(pickVersions([op(1, 91, 1420, 'a'), op(1, 91, 1450, 'b')], 1452, expected: 30).single.id, 'a');
    });

    test('a measured opening tells the shift against the version it fits', () {
      final all = [op(3.221, 93.221, 1559.949, 'top'), op(116.748, 206.748, 1510.092, 'near')];
      final s = shiftFromOpening(all, 1540, 144.7, 90.1);
      expect(s!.$1, closeTo(27.952, 1e-6));
      expect(s.$2.id, 'near');
      expect(shiftFromOpening(all, 1540, 144.7, 60), isNull, reason: 'another length: not this opening');
      expect(shiftFromOpening(all, 1540, 500, 90), isNull, reason: 'the lengths do not allow it there');
    });
  });

  group('What is learned of dubs', () {
    const g = WatchGroup(id: 'src|a|1', sourceId: 'src', label: 'Команда А', episodes: []);
    const sub = WatchGroup(id: 'src|a|2', sourceId: 'src', label: 'Команда А (суб.)', isSub: true, episodes: []);

    SkipProfiles memory(Map<String, dynamic> box) => SkipProfiles(load: () => box, save: (m) => box.addAll(jsonDecode(jsonEncode(m)) as Map<String, dynamic>));

    test('a hand correction over listening over the site; agreeing observations are exact, others a range', () {
      final box = <String, dynamic>{};
      final p = memory(box);
      expect(p.shiftFor('hikka:a', g), isNull);
      p.observe('hikka:a', g, 12.0, 'site');
      p.observe('hikka:a', g, 12.6, 'site');
      expect(p.shiftFor('hikka:a', g)!.exact, isTrue);
      expect(p.shiftFor('hikka:a', g)!.mid, closeTo(12.3, 1e-9));
      p.observe('hikka:a', g, 20, 'site');
      final range = p.shiftFor('hikka:a', g)!;
      expect((range.min, range.max, range.exact), (12.0, 20.0, false));

      p.observe('hikka:a', g, 14.2, 'audio');
      expect(p.shiftFor('hikka:a', g)!.mid, 14.2, reason: 'listening measures this very video');
      expect(p.shiftFor('hikka:a', g)!.source, 'audio');

      p.setUser('hikka:a', g, 15.5);
      expect(p.shiftFor('hikka:a', g)!.mid, 15.5);
      expect(p.shiftFor('hikka:a', g)!.source, 'user');
      p.setUser('hikka:a', g, null);
      expect(p.shiftFor('hikka:a', g)!.source, 'audio');

      // Kept by title and dub, and in storage
      expect(p.shiftFor('hikka:b', g), isNull);
      expect(p.shiftFor('hikka:a', sub), isNull);
      expect(memory(box).shiftFor('hikka:a', g)!.mid, 14.2);
    });

    test('a team hint needs agreement over titles; the intro and heard episodes are kept', () {
      final p = memory({});
      p.observe('hikka:a', g, 10, 'site');
      expect(p.teamHint(g), isNull, reason: 'one title is not a habit');
      p.observe('hikka:b', g, 10.5, 'audio');
      expect(p.teamHint(g), closeTo(10.25, 1e-9));
      expect(p.teamHint(sub), closeTo(10.25, 1e-9), reason: 'one team, whatever the kind');
      p.observe('hikka:c', g, 40, 'site');
      p.observe('hikka:d', g, 41, 'site');
      expect(p.teamHint(g), isNull, reason: 'no clear habit');

      p.setIntro('hikka:a', g, 8.04);
      expect(p.introFor('hikka:a', g), 8.04);
      p.saveEpisode('hikka:a', g, '3', const EpisodeListen(opStart: 27.9, opEnd: 117.9, intro: 8.0));
      final e = p.episode('hikka:a', g, '3')!;
      expect((e.hasOp, e.opStart, e.opEnd, e.intro), (true, 27.9, 117.9, 8.0));
      expect(p.listened('hikka:a', g), ['3']);
      expect(p.episode('hikka:a', g, '4'), isNull);
    });
  });

  group('Listening', () {
    test('two episodes of a dub: the team intro at the start and the opening at different places', () {
      final intro = music(1, 5);
      final song = music(2, 40);
      final a = audioPrint(pcmEpisode([intro, speech(10, 12), song, speech(11, 43)], noise: 1));
      final b = audioPrint(pcmEpisode([intro, speech(20, 27), song, speech(21, 28)], noise: 2, gain: 0.8));
      final runs = commonRuns(a, b);
      final heard = listenRuns(runs, opLength: 40);
      expect(heard.intro, closeTo(5, 0.3));
      expect(heard.opening!.aStart, closeTo(17, 0.3));
      expect(heard.opening!.bStart, closeTo(32, 0.3));
      expect(heard.opening!.length, closeTo(40, 0.6));
      // Without AniSkip's length: the longest common stretch
      expect(listenRuns(runs).opening!.aStart, closeTo(17, 0.3));
    });

    test('an opening right at the start, without an intro', () {
      final song = music(2, 40);
      final a = audioPrint(pcmEpisode([song, speech(10, 30)], noise: 1));
      final b = audioPrint(pcmEpisode([song, speech(20, 30)], noise: 2));
      final heard = listenRuns(commonRuns(a, b), opLength: 40);
      expect(heard.intro, isNull);
      expect(heard.opening!.aStart, closeTo(0, 0.3));
      expect(heard.opening!.length, closeTo(40, 0.6));
    });

    test('unrelated sound and silence share nothing', () {
      final a = audioPrint(pcmEpisode([music(3, 20), speech(4, 20)], noise: 1));
      final b = audioPrint(pcmEpisode([music(5, 20), speech(6, 20)], noise: 2));
      expect(commonRuns(a, b), isEmpty);
      final quiet = Float64List(printRate * 10);
      final c = audioPrint(pcmEpisode([quiet, speech(7, 20)], noise: 3));
      final d = audioPrint(pcmEpisode([quiet, speech(8, 20)], noise: 4));
      expect(commonRuns(c, d).where((r) => r.aStart < 9), isEmpty, reason: 'silence is not a common intro');
    });

    test('reading common stretches', () {
      // A long stretch from the start: the intro and the opening right after it, split by AniSkip's length
      var h = listenRuns(const [PrintRun(0, 0, 98, 0.1)], opLength: 90);
      expect((h.intro, h.opening!.aStart, h.opening!.length), (8.0, 8.0, 90.0));
      // Without the length it is all the opening
      h = listenRuns(const [PrintRun(0, 0, 98, 0.1)]);
      expect((h.intro, h.opening!.aStart), (null, 0.0));
      // A short one from the start is the intro; the opening is the stretch of its length
      h = listenRuns(const [PrintRun(0, 0, 6.5, 0.1), PrintRun(30, 50, 89, 0.15), PrintRun(140, 150, 25, 0.2)], opLength: 90);
      expect((h.intro, h.opening!.aStart), (6.5, 30.0));
      // Nothing near AniSkip's length: no opening
      h = listenRuns(const [PrintRun(140, 150, 25, 0.2)], opLength: 90);
      expect(h.opening, isNull);
      // Stretches that begin at different moments are not an intro
      h = listenRuns(const [PrintRun(0, 3, 6, 0.1)]);
      expect(h.intro, isNull);
    });

    test('a fingerprint survives the disk', () {
      final p = audioPrint(pcmEpisode([music(9, 3)], noise: 1), offset: 12.5);
      final back = AudioPrint.fromBytes(p.toBytes())!;
      expect(back.words, p.words);
      expect(back.offset, 12.5);
      expect(AudioPrint.fromBytes(Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9])), isNull);
    });
  });
}
