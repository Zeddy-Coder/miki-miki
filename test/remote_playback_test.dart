import 'package:flutter_test/flutter_test.dart';
import 'package:miki_miki/models/source_models.dart';
import 'package:miki_miki/services/playback_clock.dart';
import 'package:miki_miki/services/remote_playback.dart';
import 'package:miki_miki/services/watch_models.dart';

TimeStamp op(double s, double e) => TimeStamp(s, e, 'Opening', ChapterType.opening);
TimeStamp ed(double s, double e) => TimeStamp(s, e, 'Ending', ChapterType.ending);

void main() {
  const total = Duration(minutes: 24);

  group('розділи з таймкодів', () {
    test('опенінґ і ендінґ: проміжки заповнюються розділами «Серія», розділи суцільні', () {
      final c = chaptersFromTimestamps([op(90, 180), ed(1320, 1410)], total);
      expect(c.map((x) => x.title), ['Episode', 'Opening', 'Episode', 'Ending', 'Episode']);
      expect(c.map((x) => x.startTime.inSeconds), [0, 90, 180, 1320, 1410]);
      expect(c.last.endTime, total);
      // кожен розділ починається там, де закінчився попередній
      for (int i = 1; i < c.length; i++) {
        expect(c[i].startTime, c[i - 1].endTime);
      }
    });

    test('опенінґ з нульової секунди — без розділу «Серія» перед ним', () {
      final c = chaptersFromTimestamps([op(0, 90)], total);
      expect(c.map((x) => x.title), ['Opening', 'Episode']);
      expect(c.first.startTime, Duration.zero);
    });

    test('ендінґ до самого кінця — без розділу «Серія» після нього', () {
      final c = chaptersFromTimestamps([ed(1350, 1440)], total);
      expect(c.map((x) => x.title), ['Episode', 'Ending']);
      expect(c.last.endTime, total);
    });

    test('крихітний проміжок (менше секунди) приєднується до розділу', () {
      final c = chaptersFromTimestamps([op(0.4, 90)], total);
      expect(c.first.title, 'Opening');
      expect(c.first.startTime, Duration.zero);
    });

    test('таймкоди за межами тривалості обрізаються, некоректні відкидаються', () {
      final c = chaptersFromTimestamps([op(10, 100), ed(1400, 2000), const TimeStamp(50, 40, 'x'), const TimeStamp(-5, 10, 'y'), const TimeStamp(5000, 6000, 'z')], total);
      expect(c.map((x) => x.title), ['Episode', 'Opening', 'Episode', 'Ending']);
      expect(c.last.endTime!.inSeconds, 1440);
    });

    test('накладені таймкоди підрізаються під попередній', () {
      final c = chaptersFromTimestamps([op(10, 100), ed(80, 200)], total);
      expect(c.map((x) => x.startTime.inSeconds), [0, 10, 100, 200]);
      expect(c.map((x) => x.title), ['Episode', 'Opening', 'Ending', 'Episode']);
    });

    test('рекап, змішаний опенінґ і довільна назва', () {
      final c = chaptersFromTimestamps([
        const TimeStamp(0, 40, 'Recap', ChapterType.recap),
        const TimeStamp(40, 130, 'OP', ChapterType.mixedOp),
        const TimeStamp(700, 760, 'Preview', ChapterType.other),
        const TimeStamp(800, 860, '', ChapterType.other),
      ], total);
      expect(c.map((x) => x.title), ['Recap', 'Opening', 'Episode', 'Preview', 'Episode', 'Part', 'Episode']);
    });

    test('без таймкодів розділів немає; тривалість ще невідома — без хвоста', () {
      expect(chaptersFromTimestamps(const [], total), isEmpty);
      final c = chaptersFromTimestamps([op(90, 180)], Duration.zero);
      expect(c.map((x) => x.title), ['Episode', 'Opening']);
    });

    test('кнопка «Пропустити» бачить саме опенінґ, ендінґ і рекап', () {
      final c = chaptersFromTimestamps([
        const TimeStamp(0, 40, 'Recap', ChapterType.recap),
        op(90, 180),
        ed(1320, 1410),
      ], total);
      final flags = ChapterMath.skippableFlags(c);
      expect([for (int i = 0; i < c.length; i++) '${c[i].title}:${flags[i]}'], ['Recap:true', 'Episode:false', 'Opening:true', 'Episode:false', 'Ending:true', 'Episode:false']);
      // кнопка з'являється на початку опенінґа (перші 15 с розділу); посеред серії її немає
      expect(ChapterMath.skipIndexAt(c, flags, const Duration(seconds: 95), total), 2);
      expect(ChapterMath.skipIndexAt(c, flags, const Duration(seconds: 120), total), -1);
      expect(ChapterMath.skipIndexAt(c, flags, const Duration(seconds: 600), total), -1);
    });
  });

  group('«серію переглянуто»', () {
    test('поріг 85 % тривалості', () {
      expect(episodeSeen(const Duration(minutes: 20), total, const []), isFalse);
      expect(episodeSeen(const Duration(minutes: 21), total, const []), isTrue);
    });

    test('дійшли до ендінґа в другій половині серії', () {
      expect(episodeSeen(const Duration(minutes: 18), total, [ed(1320, 1410)]), isFalse);
      expect(episodeSeen(const Duration(seconds: 1330), total, [ed(1320, 1410)]), isTrue);
    });

    test('свій поріг: 95 % і вимкнений ендінґ', () {
      expect(episodeSeen(const Duration(minutes: 21), total, const [], fraction: 0.95), isFalse);
      expect(episodeSeen(const Duration(minutes: 23), total, const [], fraction: 0.95), isTrue);
      expect(episodeSeen(const Duration(seconds: 1330), total, [ed(1320, 1410)], fraction: 0.95, byEnding: false), isFalse, reason: 'ендінґ не враховується');
    });

    test('ендінґ на початку (ранній ED) серію переглянутою не робить', () {
      expect(episodeSeen(const Duration(minutes: 5), total, [ed(120, 210)]), isFalse);
    });

    test('тривалість невідома — не переглянуто', () {
      expect(episodeSeen(const Duration(minutes: 5), Duration.zero, const []), isFalse);
    });
  });

  group('запуск перегляду', () {
    SEpisode ep(int n) => SEpisode(url: 'u$n', name: 'Серія $n', number: n.toDouble());
    final group = WatchGroup(id: 'g1', sourceId: 'mikai', label: 'TuTaZaSho', episodes: [ep(1), ep(2), ep(3)]);
    final title = WatchTitle(animeKey: 'hikka:abc', offers: const [], licensed: false);

    test('сесія й початкова серія за ключем', () {
      final l = RemoteLaunch(title: title, group: group, animeTitle: 'Назва', epKey: '3');
      expect(l.session.entries.length, 3);
      expect(l.startIndex, 2);
      expect(l.session.groupLabel, 'TuTaZaSho');
      expect(RemoteLaunch(title: title, group: group, animeTitle: 'x').startIndex, 0);
      expect(RemoteLaunch(title: title, group: group, animeTitle: 'x', epKey: '77').startIndex, 0);
    });

    test('WatchLauncher: без плеєра play повертає false, із плеєром — передає запуск', () async {
      final l = RemoteLaunch(title: title, group: group, animeTitle: 'x');
      expect(WatchLauncher.available, isFalse);
      expect(await WatchLauncher.play(l), isFalse);
      RemoteLaunch? got;
      Future<void> handler(RemoteLaunch x) async => got = x;
      WatchLauncher.attach(handler);
      expect(WatchLauncher.available, isTrue);
      expect(await WatchLauncher.play(l), isTrue);
      expect(got, same(l));
      WatchLauncher.detach(handler);
      expect(WatchLauncher.available, isFalse);
    });
  });
}
