import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:miki_miki/services/anime4k_controller.dart';
import 'package:miki_miki/services/anime4k_service.dart';
import 'package:miki_miki/services/osd_message.dart';
import 'package:miki_miki/services/storage_service.dart';

/// Розбирає офіційний input.conf Anime4K: `CTRL+N … set "~~/shaders/a.glsl;~~/shaders/b.glsl"`
Map<int, List<String>> parseOfficial(String path) {
  final out = <int, List<String>>{};
  final re = RegExp(r'^CTRL\+(\d)\s+no-osd change-list glsl-shaders set "([^"]+)"');
  for (final line in File(path).readAsLinesSync()) {
    final m = re.firstMatch(line.trim());
    if (m == null) continue;
    out[int.parse(m.group(1)!)] = m.group(2)!.split(';').map((p) => p.replaceFirst('~~/shaders/', '')).toList();
  }
  return out;
}

class Rig {
  Rig() {
    controller = Anime4kController(
      command: (args) async {
        if (failCommands) throw StateError('mpv відхилив команду');
        commands.add(args);
      },
      osd: (message, {duration}) => osd.add(message),
    );
  }

  late final Anime4kController controller;
  final List<List<String>> commands = [];
  final List<OsdMessage> osd = [];
  bool failCommands = false;

  List<List<String>> get glsl => commands.where((a) => a.length > 1 && a[1] == 'glsl-shaders').toList();

  /// Файли з останньої команди `set`
  List<String> get lastChain {
    final set = glsl.lastWhere((a) => a[2] == 'set');
    return set[3].split(Platform.isWindows ? ';' : ':').map((p) => p.split('/').last).toList();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ланцюжки шейдерів', () {
    final official = {
      Anime4kQuality.fast: parseOfficial('test/data/official_fast.conf'),
      Anime4kQuality.hq: parseOfficial('test/data/official_hq.conf'),
    };

    test('офіційні конфіги прочитані (6 режимів на якість)', () {
      for (final q in Anime4kQuality.values) {
        expect(official[q]!.keys.toSet(), {1, 2, 3, 4, 5, 6}, reason: q.name);
      }
    });

    for (final q in Anime4kQuality.values) {
      for (final m in Anime4kMode.values) {
        test('${m.title} (${q.label}) збігається з офіційним input.conf', () {
          expect(Anime4kService.chain(m, q), official[q]![m.digit]);
        });
      }
    }

    test('усі шейдери ланцюжків є серед assets, і лише вони', () {
      final dir = Directory('assets/shaders/anime4k');
      final onDisk = dir.listSync().whereType<File>().map((f) => f.uri.pathSegments.last).where((n) => n.endsWith('.glsl')).toSet();
      expect(Anime4kService.allShaderFiles.difference(onDisk), isEmpty, reason: 'у збірці немає файлів');
      expect(onDisk.difference(Anime4kService.allShaderFiles), isEmpty, reason: 'зайві файли в assets');
      expect(File('assets/shaders/anime4k/LICENSE.txt').existsSync(), isTrue);
    });

    test('шейдери не порожні й починаються з директив mpv', () {
      for (final name in Anime4kService.allShaderFiles) {
        final text = File('assets/shaders/anime4k/$name').readAsStringSync();
        expect(text, contains('//!HOOK'), reason: name);
        expect(text.length, greaterThan(500), reason: name);
      }
    });

    test('режими з другим проходом позначені як такі, що потребують апскейлу', () {
      expect(Anime4kMode.values.where((m) => m.needsUpscale), [Anime4kMode.aa, Anime4kMode.bb, Anime4kMode.ca]);
    });

    test('цифри режимів 1…6 і розбір збережених значень', () {
      expect(Anime4kMode.values.map((m) => m.digit), [1, 2, 3, 4, 5, 6]);
      expect(Anime4kMode.parse('bb'), Anime4kMode.bb);
      expect(Anime4kMode.parse('сміття'), Anime4kMode.a);
      expect(Anime4kMode.parse(null), Anime4kMode.a);
      expect(Anime4kQuality.parse('hq'), Anime4kQuality.hq);
      expect(Anime4kQuality.parse(''), Anime4kQuality.fast);
    });

    test('розпізнавання помилок шейдера в логах mpv', () {
      expect(Anime4kService.looksLikeShaderFailure('error', 'Failed to compile shader: Anime4K_Restore'), isTrue);
      expect(Anime4kService.looksLikeShaderFailure('fatal', 'GLSL error'), isTrue);
      expect(Anime4kService.looksLikeShaderFailure('warn', 'shader warning'), isFalse);
      expect(Anime4kService.looksLikeShaderFailure('error', 'audio device lost'), isFalse);
    });
  });

  group('розпакування і підключення', () {
    test('apply розпаковує файли й викликає change-list set з усіма шляхами', () async {
      final commands = <List<String>>[];
      final err = await Anime4kService.apply((a) async => commands.add(a), Anime4kMode.c, Anime4kQuality.hq);
      expect(err, isNull);
      expect(commands, hasLength(1));
      final cmd = commands.single;
      expect(cmd.sublist(0, 3), ['change-list', 'glsl-shaders', 'set']);

      final sep = Platform.isWindows ? ';' : ':';
      final files = cmd[3].split(sep);
      expect(files.map((p) => p.split('/').last).toList(), Anime4kService.chain(Anime4kMode.c, Anime4kQuality.hq));
      for (final f in files) {
        expect(f.contains('\\'), isFalse, reason: 'шляхи мають бути з прямими слешами');
        final file = File(f);
        expect(file.existsSync(), isTrue, reason: f);
        // Розпакований файл ідентичний оригіналу з assets
        final name = f.split('/').last;
        expect(file.readAsBytesSync(), File('assets/shaders/anime4k/$name').readAsBytesSync(), reason: name);
      }
    });

    test('пошкоджений файл від попереднього запуску замінюється оригіналом', () async {
      const name = 'Anime4K_Restore_CNN_Soft_VL.glsl';
      final dir = Anime4kService.shaderDir..createSync(recursive: true);
      File('${dir.path}/$name').writeAsBytesSync([1, 2, 3]);
      final paths = await Anime4kService.ensureExtracted([name]);
      expect(File(paths.single).readAsBytesSync(), File('assets/shaders/anime4k/$name').readAsBytesSync());
    });

    test('видалений під час роботи файл розпаковується знову', () async {
      final commands = <List<String>>[];
      await Anime4kService.apply((a) async => commands.add(a), Anime4kMode.a, Anime4kQuality.fast);
      final path = commands.last[3].split(Platform.isWindows ? ';' : ':').first;
      final original = File(path).readAsBytesSync();
      File(path).deleteSync();
      await Anime4kService.apply((a) async => commands.add(a), Anime4kMode.a, Anime4kQuality.fast);
      expect(File(path).existsSync(), isTrue);
      expect(File(path).readAsBytesSync(), original);
    });

    test('відхилена команда повертає зрозумілу помилку', () async {
      final err = await Anime4kService.apply((a) async => throw StateError('boom'), Anime4kMode.a, Anime4kQuality.fast);
      expect(err, isNotNull);
      expect(err, contains('Рушій відхилив'));
    });

    test('clear надсилає change-list glsl-shaders clr і не кидає помилок', () async {
      final commands = <List<String>>[];
      await Anime4kService.clear((a) async => commands.add(a));
      expect(commands.single, ['change-list', 'glsl-shaders', 'clr', '']);
      await Anime4kService.clear((a) async => throw StateError('boom'));
    });
  });

  group('Anime4kController', () {
    Future<void> settled(Rig r, [int count = 1]) async {
      for (var i = 0; i < 200 && r.glsl.length < count; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }

    test('вимкнений Anime4K не чіпає шейдери з mpv.conf користувача', () async {
      final r = Rig();
      await r.controller.syncToEngine();
      r.controller.onVideoHeight(1080);
      r.controller.onFileChanged();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(r.commands, isEmpty);
      expect(r.controller.summary, 'Вимкнено');
    });

    test('setMode вмикає, застосовує ланцюжок і показує сповіщення з клавішами', () async {
      final r = Rig();
      await r.controller.setMode(Anime4kMode.bb);
      expect(r.controller.enabled, isTrue);
      expect(r.controller.active, isTrue);
      expect(r.lastChain, Anime4kService.chain(Anime4kMode.bb, Anime4kQuality.fast));
      expect(r.osd.last.title, 'Anime4K');
      expect(r.osd.last.detail, 'Режим B+B (Fast)');
      expect(r.osd.last.keys, ['Ctrl', '5']);
      expect(r.controller.summary, 'Режим B+B · Fast');
    });

    test('вибір режиму зберігається в налаштуваннях', () async {
      final r = Rig();
      await r.controller.setMode(Anime4kMode.ca);
      expect(StorageService.getAnime4kEnabled(), isTrue);
      expect(StorageService.getAnime4kMode(), 'ca');
      expect(StorageService.getAnime4kQuality(), 'fast');

      final fresh = Rig();
      fresh.controller.load();
      expect(fresh.controller.enabled, isTrue);
      expect(fresh.controller.mode, Anime4kMode.ca);
    });

    test('Ctrl+0: вимкнення скидає шейдери', () async {
      final r = Rig();
      await r.controller.setMode(Anime4kMode.a);
      await r.controller.disable();
      expect(r.controller.enabled, isFalse);
      expect(r.glsl.last, ['change-list', 'glsl-shaders', 'clr', '']);
      expect(r.osd.last.title, 'Anime4K вимкнено');
      expect(r.osd.last.keys, ['Ctrl', '0']);
      expect(r.controller.active, isFalse);
    });

    test('Ctrl+8: перемикач повертає останній режим', () async {
      final r = Rig();
      await r.controller.setMode(Anime4kMode.c);
      await r.controller.toggle();
      expect(r.controller.enabled, isFalse);
      await r.controller.toggle();
      expect(r.controller.enabled, isTrue);
      expect(r.controller.mode, Anime4kMode.c);
      expect(r.lastChain, Anime4kService.chain(Anime4kMode.c, Anime4kQuality.fast));
    });

    test('Ctrl+9: перемикання Fast ⇄ HQ перебудовує ланцюжок', () async {
      final r = Rig();
      await r.controller.setMode(Anime4kMode.a);
      await r.controller.toggleQuality();
      expect(r.controller.quality, Anime4kQuality.hq);
      expect(r.lastChain, Anime4kService.chain(Anime4kMode.a, Anime4kQuality.hq));
      expect(r.osd.last.detail, 'Режим A (HQ)');
      await r.controller.toggleQuality();
      expect(r.lastChain, Anime4kService.chain(Anime4kMode.a, Anime4kQuality.fast));
    });

    test('зміна якості при вимкненому Anime4K лише повідомляє, без команд mpv', () async {
      final r = Rig();
      await r.controller.setQuality(Anime4kQuality.hq);
      expect(r.commands, isEmpty);
      expect(r.osd.last.title, 'Якість Anime4K');
      expect(StorageService.getAnime4kQuality(), 'hq');
    });

    test('команди виконуються по черзі, останній вибір перемагає', () async {
      final r = Rig();
      r.controller.setMode(Anime4kMode.a);
      r.controller.setMode(Anime4kMode.b);
      await r.controller.setMode(Anime4kMode.c);
      expect(r.glsl.where((a) => a[2] == 'set').length, 3);
      expect(r.lastChain, Anime4kService.chain(Anime4kMode.c, Anime4kQuality.fast));
    });

    test('пропуск за роздільністю: 1080p при порозі 1080 → шейдери скинуто', () async {
      final r = Rig();
      await r.controller.configure(enabled: true, mode: Anime4kMode.a, quality: Anime4kQuality.fast, skipHeight: 1080);
      expect(r.controller.skipped, isFalse);
      r.controller.onVideoHeight(1080);
      expect(r.controller.skipped, isTrue);
      await settled(r, 2);
      expect(r.glsl.last, ['change-list', 'glsl-shaders', 'clr', '']);
      expect(r.controller.summary, 'Пропущено (1080p)');
      expect(r.controller.active, isFalse);

      // Наступне відео 720p — шейдери повертаються
      r.controller.onVideoHeight(720);
      expect(r.controller.skipped, isFalse);
      await settled(r, 3);
      expect(r.glsl.last[2], 'set');
      expect(r.controller.active, isTrue);
    });

    test('ручний вибір режиму діє попри поріг, до наступного файлу', () async {
      final r = Rig();
      await r.controller.configure(enabled: true, mode: Anime4kMode.a, quality: Anime4kQuality.fast, skipHeight: 1080);
      r.controller.onVideoHeight(2160);
      await settled(r, 2);
      expect(r.controller.skipped, isTrue);

      await r.controller.setMode(Anime4kMode.b);
      expect(r.controller.skipped, isFalse);
      expect(r.glsl.last[2], 'set');

      // Той самий файл: нове значення висоти не скасовує ручний вибір
      r.controller.onVideoHeight(2160);
      expect(r.controller.skipped, isFalse);

      // Інший файл — знову діє поріг
      r.controller.onFileChanged();
      expect(r.controller.skipped, isTrue);
    });

    test('configure без змін не надсилає команд', () async {
      final r = Rig();
      await r.controller.configure(enabled: false, mode: Anime4kMode.a, quality: Anime4kQuality.fast, skipHeight: 0);
      expect(r.commands, isEmpty);
      expect(r.osd, isEmpty);
    });

    test('configure зберігає всі поля й застосовує шейдери', () async {
      final r = Rig();
      await r.controller.configure(enabled: true, mode: Anime4kMode.bb, quality: Anime4kQuality.hq, skipHeight: 1440);
      expect(StorageService.getAnime4kSkipHeight(), 1440);
      expect(r.lastChain, Anime4kService.chain(Anime4kMode.bb, Anime4kQuality.hq));
    });

    test('помилка шейдера в логах mpv одразу після вмикання вимикає Anime4K', () async {
      final r = Rig();
      await r.controller.setMode(Anime4kMode.a);
      expect(r.controller.active, isTrue);
      r.controller.onEngineLog('error', 'Failed to compile shader Anime4K_Restore_CNN_M: syntax error');
      expect(r.controller.enabled, isFalse);
      expect(r.controller.error, contains('Failed to compile'));
      expect(r.osd.last.isError, isTrue);
      await settled(r, 2);
      expect(r.glsl.last, ['change-list', 'glsl-shaders', 'clr', '']);
    });

    test('сторонні помилки в логах не вимикають Anime4K', () async {
      final r = Rig();
      await r.controller.setMode(Anime4kMode.a);
      r.controller.onEngineLog('error', 'audio output failed');
      r.controller.onEngineLog('warn', 'shader cache miss');
      expect(r.controller.enabled, isTrue);
    });

    test('рушій відхилив команду: показується помилка, Anime4K не вважається активним', () async {
      final r = Rig()..failCommands = true;
      await r.controller.setMode(Anime4kMode.a);
      expect(r.controller.applied, isFalse);
      expect(r.controller.active, isFalse);
      expect(r.controller.error, isNotNull);
      expect(r.osd.last.isError, isTrue);
    });
  });
}
