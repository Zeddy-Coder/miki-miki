import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:miki_miki/services/app_log.dart';
import 'package:miki_miki/services/log_export.dart';

void main() {
  late AppLog log;

  Future<Directory> temp() async => Directory.systemTemp.createTempSync('applog_test_');

  group('AppLog: запис і режими', () {
    test('налагоджувальний рівень пишеться лише в детальному режимі', () async {
      final d = await temp();
      log = AppLog();
      await log.init(directory: d, detailed: false);
      log.log(LogLevel.debug, 'т', 'докладно');
      log.log(LogLevel.info, 'т', 'звичайно');
      expect(log.entries.map((e) => e.message), ['звичайно']);
      await log.setDetailed(true);
      log.log(LogLevel.debug, 'т', 'докладно');
      expect(log.entries.map((e) => e.message), contains('докладно'));
      await log.shutdown();
      d.deleteSync(recursive: true);
    });

    test('однакові рядки поспіль згортаються в один із лічильником', () async {
      log = AppLog();
      for (var i = 0; i < 5; i++) {
        log.log(LogLevel.warn, 'мережа', 'обрив');
      }
      log.log(LogLevel.info, 'мережа', 'інше');
      final msgs = log.entries.map((e) => e.message).toList();
      expect(msgs.first, 'обрив');
      expect(msgs[1], contains('повторився ще 4'));
      expect(msgs[2], 'інше');
      expect(msgs.length, 3);
    });

    test('секрети маскуються', () {
      expect(AppLog.sanitize('GET https://x/a?token=abc123&q=1'), 'GET https://x/a?token=***&q=1');
      expect(AppLog.sanitize('Authorization: Bearer abc.def-ghi'), 'Authorization: ***');
      expect(AppLog.sanitize('заголовок Bearer abc.def'), 'заголовок Bearer ***');
      expect(AppLog.sanitize('apikey=SECRET; password: hunter2'), 'apikey=***; password: ***');
      expect(AppLog.sanitize('Set-Cookie: sid=1; Path=/'), contains('Set-Cookie: ***'));
      // звичайний текст не чіпаємо
      expect(AppLog.sanitize('keyboard: ok, monkey see'), 'keyboard: ok, monkey see');
      expect(AppLog.sanitize('швидкість ×1.25, поз 12:34'), 'швидкість ×1.25, поз 12:34');
    });

    test('помилка з винятком і початком стека', () {
      log = AppLog();
      AppLog.instance = log;
      AppLog.e('тест', 'збій', StateError('ой'), StackTrace.fromString('#0 a (x:1)\n#1 b (y:2)\n#2 c (z:3)'));
      final e = log.entries.single;
      expect(e.level, LogLevel.error);
      expect(e.message, contains('Bad state: ой'));
      expect(e.message, contains('#1 b (y:2)'));
    });

    test('дуже довгий рядок обрізається', () {
      log = AppLog();
      log.log(LogLevel.info, 'т', 'я' * (AppLog.maxLineChars + 500));
      expect(log.entries.single.message.length, lessThan(AppLog.maxLineChars + 60));
      expect(log.entries.single.message, contains('ще 500 симв.'));
    });

    test('кільцевий буфер не росте безмежно', () {
      log = AppLog();
      for (var i = 0; i < 4000; i++) {
        log.log(LogLevel.info, 'т', 'рядок $i');
      }
      expect(log.length, lessThanOrEqualTo(1500));
      expect(log.entries.last.message, 'рядок 3999');
    });

    test('формат рядка: дата, рівень, тег', () {
      final e = LogEntry(DateTime(2026, 11, 3, 14, 5, 9, 7), LogLevel.warn, 'hikka', 'привіт');
      expect(e.format(), '2026-11-03 14:05:09.007 W [hikka] привіт');
      expect(e.clock, '14:05:09.007');
    });
  });

  group('AppLog: файл', () {
    test('детальний режим пише у файл сесії, багаторядкові записи з відступом', () async {
      final d = await temp();
      log = AppLog();
      await log.init(directory: d, detailed: true);
      log.log(LogLevel.info, 'т', 'перший');
      log.log(LogLevel.error, 'т', 'рядок1\nрядок2');
      await log.flushNow();
      final files = await log.files();
      expect(files.length, 1);
      final text = files.single.readAsStringSync();
      expect(text, contains('I [т] перший'));
      expect(text, contains('E [т] рядок1\n    рядок2'));
      expect(files.single.uri.pathSegments.last, startsWith('miki_miki_'));
      await log.shutdown();
      d.deleteSync(recursive: true);
    });

    test('запис, зроблений до вмикання, потрапляє у файл без дублів', () async {
      final d = await temp();
      log = AppLog();
      await log.init(directory: d, detailed: false);
      log.log(LogLevel.info, 'т', 'до вмикання');
      await log.setDetailed(true);
      log.log(LogLevel.info, 'т', 'після вмикання');
      await log.setDetailed(false);
      log.log(LogLevel.info, 'т', 'рядок за паузи запису');
      await log.setDetailed(true);
      await log.flushNow();
      final text = (await log.files()).map((f) => f.readAsStringSync()).join('\n');
      expect('до вмикання'.allMatches(text).length, 1);
      expect('після вмикання'.allMatches(text).length, 1);
      expect('рядок за паузи запису'.allMatches(text).length, 1, reason: 'пропущене під час вимкнення дописується при вмиканні');
      await log.shutdown();
      d.deleteSync(recursive: true);
    });

    test('ротація: файл ділиться на частини, старі сесії видаляються, поточна лишається', () async {
      final d = await temp();
      for (var i = 1; i <= 5; i++) {
        File('${d.path}/my_player_2020010${i}_000000.log').writeAsStringSync('старий $i\n' * 10);
      }
      log = AppLog(maxFileBytes: 600, maxFiles: 4);
      await log.init(directory: d, detailed: true);
      for (var i = 0; i < 80; i++) {
        log.log(LogLevel.info, 'т', 'рядок номер $i із довгим текстом для заповнення файлу');
      }
      await log.flushNow();
      for (var i = 0; i < 20; i++) {
        log.log(LogLevel.info, 'т', 'ще один рядок $i, довгий-довгий, щоб перейти до наступної частини файлу');
        await log.flushNow();
      }
      final files = await log.files();
      final names = files.map((f) => f.uri.pathSegments.last).toList();
      expect(names.where((n) => n.contains('_p')).isNotEmpty, isTrue, reason: 'є частини сесії: $names');
      expect(names.where((n) => n.startsWith('my_player_2020')).length, lessThan(5), reason: 'старі сесії прибрано: $names');
      final all = await log.sessionText(maxBytes: 10 * 1024 * 1024);
      expect(all, contains('рядок номер 0 '));
      expect(all, contains('ще один рядок 19'));
      await log.shutdown();
      d.deleteSync(recursive: true);
    });

    test('журнали під старою назвою читаються і впорядковуються разом із новими за часом', () async {
      final d = await temp();
      File('${d.path}/my_player_20200101_000000.log').writeAsStringSync('# стара назва\n2020 E [т] стара аварія\n');
      File('${d.path}/miki_miki_20210101_000000.log').writeAsStringSync('# нова назва\n2021 E [т] нова аварія\n');
      log = AppLog();
      await log.init(directory: d, detailed: true);
      final names = (await log.files()).map((f) => f.uri.pathSegments.last).toList();
      expect(names.first, 'my_player_20200101_000000.log', reason: 'за часом, а не за літерами префікса: $names');
      expect(names, contains('miki_miki_20210101_000000.log'));
      expect(await log.previousSessionText(), contains('нова аварія'));
      await log.shutdown();
      d.deleteSync(recursive: true);
    });

    test('звіт: шапка, додаткові розділи, журнал сесії і хвіст попереднього запуску', () async {
      final d = await temp();
      File('${d.path}/my_player_20200101_000000.log').writeAsStringSync('# попередня сесія\n2020-01-01 00:00:00.000 E [т] аварія\n');
      log = AppLog();
      await log.init(directory: d, detailed: true);
      log.environment.add('Пристрій: Тест 1');
      log.log(LogLevel.info, 'т', 'поточна подія token=ABC');
      final report = await log.buildReport(extra: [('ПЛЕЄР', 'поз 1:00'), ('ПОРОЖНІЙ', '  ')]);
      expect(report, contains('MIKI MIKI — ЖУРНАЛ'));
      expect(report, contains('Детальний журнал: так'));
      expect(report, contains('Пристрій: Тест 1'));
      expect(report, contains('══ ПЛЕЄР ══\nпоз 1:00'));
      expect(report, isNot(contains('ПОРОЖНІЙ')));
      expect(report, contains('поточна подія token=***'));
      expect(report, isNot(contains('ABC')));
      expect(report, contains('ПОПЕРЕДНІЙ ЗАПУСК'));
      expect(report, contains('аварія'));
      await log.shutdown();
      d.deleteSync(recursive: true);
    });

    test('без файлу звіт береться з памʼяті', () async {
      log = AppLog();
      log.log(LogLevel.warn, 'т', 'лише в памʼяті');
      final report = await log.buildReport();
      expect(report, contains('лише в памʼяті'));
    });

    test('очищення видаляє файли й буфер', () async {
      final d = await temp();
      log = AppLog();
      await log.init(directory: d, detailed: true);
      log.log(LogLevel.info, 'т', 'щось');
      await log.flushNow();
      expect((await log.files()).length, 1);
      await log.clear();
      expect(await log.files(), isEmpty);
      expect(log.length, 0);
      // після очищення журнал знову пишеться
      log.log(LogLevel.info, 'т', 'нове');
      await log.flushNow();
      expect((await log.sessionText()), contains('нове'));
      await log.shutdown();
      d.deleteSync(recursive: true);
    });

    test('недоступна тека не ламає журнал', () async {
      final blocker = File('${Directory.systemTemp.path}/applog_blocker_${DateTime.now().microsecondsSinceEpoch}');
      blocker.writeAsStringSync('файл замість теки');
      log = AppLog();
      await log.init(directory: Directory('${blocker.path}/logs'), detailed: true);
      expect(log.sinkError, isNotNull);
      log.log(LogLevel.info, 'т', 'все одно працює');
      expect(log.entries.last.message, 'все одно працює');
      expect(await log.buildReport(), contains('все одно працює'));
      blocker.deleteSync();
    });
  });

  group('Збереження у файл', () {
    test('назва файлу містить дату й час', () {
      expect(LogExport.fileName(DateTime(2026, 11, 3, 9, 5, 7)), 'miki_miki_log_20261103_090507.txt');
    });

    test('звіт передається системному вікну як UTF-8 байти', () async {
      log = AppLog();
      log.log(LogLevel.info, 'т', 'подія для файлу');
      String? gotName;
      Uint8List? gotBytes;
      final r = await LogExport.save(
        log: log,
        extra: [('РОЗДІЛ', 'вміст')],
        now: DateTime(2026, 11, 3, 1, 2, 3),
        saver: (name, bytes) async {
          gotName = name;
          gotBytes = bytes;
          return '/storage/Download/$name';
        },
      );
      expect(r.saved, isTrue);
      expect(r.cancelled, isFalse);
      expect(gotName, 'miki_miki_log_20261103_010203.txt');
      final text = utf8.decode(gotBytes!);
      expect(text, contains('подія для файлу'));
      expect(text, contains('══ РОЗДІЛ ══'));
    });

    test('скасування вікна — не помилка', () async {
      log = AppLog();
      final r = await LogExport.save(log: log, saver: (n, b) async => null);
      expect(r.saved, isFalse);
      expect(r.cancelled, isTrue);
      expect(r.error, isNull);
    });

    test('збій системного вікна повертається як помилка', () async {
      log = AppLog();
      AppLog.instance = log;
      final r = await LogExport.save(log: log, saver: (n, b) async => throw StateError('немає доступу'));
      expect(r.saved, isFalse);
      expect(r.error, contains('немає доступу'));
    });
  });
}
