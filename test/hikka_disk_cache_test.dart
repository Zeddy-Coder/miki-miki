import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:miki_miki/models/hikka_models.dart';
import 'package:miki_miki/services/hikka_api.dart';
import 'package:miki_miki/services/hikka_disk_cache.dart';

import 'support/hikka_fakes.dart';

void main() {
  late Directory dir;
  late FakeHikka server;
  late DateTime clock;

  HikkaApi make() => HikkaApi(sender: server.call, retryDelay: Duration.zero, now: () => clock)..disk = HikkaDiskCache(dir: dir);

  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 80)); // фоновий запис/оновлення

  setUp(() {
    dir = Directory.systemTemp.createTempSync('hikka_disk');
    server = FakeHikka();
    clock = DateTime(2026, 11, 10, 12);
  });

  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('назва файлу стабільна й залежить від ключа', () {
    expect(HikkaDiskCache.fileName('a'), HikkaDiskCache.fileName('a'));
    expect(HikkaDiskCache.fileName('a'), isNot(HikkaDiskCache.fileName('b')));
    expect(HikkaDiskCache.fileName('a'), matches(RegExp(r'^[0-9a-f]{16}\.json$')));
  });

  test('новий запуск бере свіжі дані з диска без мережі', () async {
    final first = make();
    final p1 = await first.searchAnime(const HikkaSearchFilters(), size: 30);
    expect(first.networkCalls, 1);
    await settle();

    final second = make(); // «новий запуск»: памʼять порожня
    final p2 = await second.searchAnime(const HikkaSearchFilters(), size: 30);
    expect(second.networkCalls, 0, reason: 'свіже з диска');
    expect(p2.items.length, p1.items.length);
  });

  test('застаріле (але не старе) віддається одразу, а оновлюється у фоні', () async {
    final first = make();
    await first.searchAnime(const HikkaSearchFilters(), size: 30);
    await settle();

    clock = clock.add(const Duration(hours: 2)); // за межами TTL, але в межах «віддати одразу»
    final second = make();
    final p = await second.searchAnime(const HikkaSearchFilters(), size: 30);
    expect(p.items, isNotEmpty);
    await settle();
    expect(second.networkCalls, 1, reason: 'фонове оновлення');
    await second.searchAnime(const HikkaSearchFilters(), size: 30);
    expect(second.networkCalls, 1, reason: 'після оновлення — свіжа памʼять');
  });

  test('ручне оновлення не віддає збережене як свіже', () async {
    final first = make();
    await first.searchAnime(const HikkaSearchFilters(), size: 30);
    await settle();

    final second = make();
    clock = clock.add(const Duration(seconds: 1));
    second.clearCache();
    await second.searchAnime(const HikkaSearchFilters(), size: 30);
    expect(second.networkCalls, 1, reason: 'після clearCache йде в мережу');
  });

  test('без мережі віддається навіть дуже старий кеш з диска', () async {
    final first = make();
    await first.searchAnime(const HikkaSearchFilters(), size: 30);
    await settle();

    clock = clock.add(const Duration(days: 5)); // старше за «віддати одразу»
    server.offline = true;
    final second = make();
    final p = await second.searchAnime(const HikkaSearchFilters(), size: 30);
    expect(p.items, isNotEmpty);
  });

  test('без збереженого й без мережі — помилка; пошкоджений файл не ламає', () async {
    server.offline = true;
    final api = make();
    await expectLater(api.searchAnime(const HikkaSearchFilters(), size: 30), throwsA(isA<HikkaException>()));

    server.offline = false;
    final good = make();
    await good.searchAnime(const HikkaSearchFilters(), size: 30);
    await settle();
    for (final f in dir.listSync().whereType<File>()) {
      f.writeAsStringSync('{не json');
    }
    final again = make();
    await again.searchAnime(const HikkaSearchFilters(), size: 30);
    expect(again.networkCalls, 1, reason: 'пошкоджений кеш ігнорується');
  });
}
