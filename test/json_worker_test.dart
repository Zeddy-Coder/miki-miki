// Big JSON outside the UI thread: the background path gives the same data and the same errors as jsonDecode, and the
// disk cache keeps the response text as it came (no second encoding)
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:miki_miki/services/hikka_api.dart';
import 'package:miki_miki/services/hikka_disk_cache.dart';
import 'package:miki_miki/services/json_worker.dart';

import 'support/hikka_fakes.dart';

void main() {
  setUp(() => JsonWorker.threshold = 64);
  tearDown(() => JsonWorker.threshold = 1 << 30);

  test('великий текст розбирається у фоновому ізоляті й дає ті самі дані', () async {
    final data = {
      'list': [
        for (int i = 0; i < 200; i++) {'i': i, 'title': 'Колекція $i', 'tags': ['a', 'b'], 'nsfw': false, 'score': 7.5},
      ],
    };
    final text = jsonEncode(data);
    expect(text.length, greaterThan(JsonWorker.threshold));
    expect(await JsonWorker.decode(text), data);
  });

  test('малий текст розбирається на місці', () async {
    expect(await JsonWorker.decode('{"a":1}'), {'a': 1});
  });

  test('зламаний великий текст дає FormatException, як jsonDecode', () async {
    final broken = '{"list": [${List.filled(100, '"x"').join(',')}';
    await expectLater(JsonWorker.decode(broken), throwsA(isA<FormatException>()));
  });

  test('відповідь Hikka розбирається у фоні, а на диск лягає як прийшла; новий запуск читає її з диска', () async {
    final dir = Directory.systemTemp.createTempSync('json_worker');
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });
    final server = FakeHikka();
    final clock = DateTime(2026, 11, 16, 12);
    HikkaApi make() => HikkaApi(sender: server.call, retryDelay: Duration.zero, now: () => clock)..disk = HikkaDiskCache(dir: dir);

    final first = make();
    final page = await first.collections(page: 1, size: 20);
    expect(page.items, isNotEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 120)); // the background write
    final files = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.json')).toList();
    expect(files, isNotEmpty);
    final text = files.first.readAsStringSync();
    expect(jsonDecode(text), isA<Map>(), reason: 'файл — цілий JSON');
    expect(text, contains('"j":{"pagination"'), reason: 'відповідь записано як прийшла (текст сервера)');

    final second = make(); // a fresh launch: memory is empty, the disk answers
    final again = await second.collections(page: 1, size: 20);
    expect(second.networkCalls, 0);
    expect([for (final c in again.items) c.reference], [for (final c in page.items) c.reference]);
    expect(again.items.first.title, isA<String>());
  });
}
