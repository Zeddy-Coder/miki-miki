// The downloads' screens: the picker's choices, the downloads page, the title's downloads, the offline strip and the
// one-line summary for "Профіль". The manager is real (a temporary folder, a fake CDN); it is filled outside the fake clock.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miki_miki/models/source_models.dart';
import 'package:miki_miki/services/downloads/download_manager.dart';
import 'package:miki_miki/services/downloads/download_worker.dart';
import 'package:miki_miki/services/hikka_nav.dart';
import 'package:miki_miki/services/network_status.dart';
import 'package:miki_miki/services/source_prefs.dart';
import 'package:miki_miki/services/source_registry.dart';
import 'package:miki_miki/services/watch_models.dart';
import 'package:miki_miki/services/watch_service.dart';
import 'package:miki_miki/widgets/downloads/download_kit.dart';
import 'package:miki_miki/widgets/downloads/download_picker.dart';
import 'package:miki_miki/widgets/downloads/downloads_page.dart';

import 'support/remote_fakes.dart';

WatchGroup dub({int count = 12}) => WatchGroup(
      id: 'mikai|1|inari',
      sourceId: 'mikai',
      label: 'Inari',
      episodes: [for (var i = 1; i <= count; i++) SEpisode(url: 'ep$i', name: 'Серія $i', number: i.toDouble())],
    );

void main() {
  late Directory tmp;
  late NetworkStatus net;
  late DownloadManager m;
  final oldManager = DownloadManager.instance;
  final oldNetwork = NetworkStatus.instance;
  final oldWatch = WatchService.instance;

  Future<void> prepare(WidgetTester t, Future<void> Function(DownloadManager m) fill) async {
    await t.runAsync(() async {
      tmp = await Directory.systemTemp.createTemp('miki_dl_ui');
      net = NetworkStatus(probe: () async => true);
      final registry = SourceRegistry(sources: [FakeSource('mikai', const {})], prefs: SourcePrefs(load: () => {}, save: (_) {}));
      m = DownloadManager(
        indexPath: '${tmp.path}/downloads.json',
        root: '${tmp.path}/root',
        network: net,
        registry: registry,
        loadPrefs: () => {},
        savePrefs: (_) {},
        storage: (_) async => null,
        resolve: (item) async => ResolvedVideo(Video(url: 'https://cdn.test/${item.episode.url}.mp4', title: '720p', resolution: 720), 'Moon'),
        fetch: (url, headers, {offset, length}) async => FetchResponse(200, 32, Stream.value(List.filled(32, 1)), () {}),
      );
      DownloadManager.instance = m;
      NetworkStatus.instance = net;
      WatchService.instance = WatchService(registry: registry, store: memoryStore());
      await m.init();
      await fill(m);
      for (var i = 0; i < 300 && m.pending.any((x) => x.isActive); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      await m.save();
    });
    addTearDown(() async {
      await t.runAsync(() async {
        m.dispose();
        net.dispose();
        if (await tmp.exists()) await tmp.delete(recursive: true);
      });
      DownloadManager.instance = oldManager;
      NetworkStatus.instance = oldNetwork;
      WatchService.instance = oldWatch;
    });
  }

  Future<void> host(WidgetTester t, Widget child) async {
    t.view.physicalSize = const Size(900, 2200);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(home: Scaffold(body: child)));
    await t.pump();
  }

  testWidgets('вибір серій: наступні, непереглянуті, усі, вручну; завантажене не пропонується', (t) async {
    await prepare(t, (m) async => m.enqueue(animeKey: 'hikka:frieren', animeTitle: 'Фрірен', group: dub(), indexes: [5]));
    await host(
      t,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => DownloadPicker.show(context, scale: 1, animeKey: 'hikka:frieren', animeTitle: 'Фрірен', group: dub(), watched: {'1', '2'}, from: 2, manager: m),
          child: const Text('open'),
        ),
      ),
    );
    await t.tap(find.text('open'));
    // The manager was read outside the fake clock: its future resumes there
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await t.pumpAndSettle();
    expect(find.text('Озвучення Inari · на пристрої 1 з 12'), findsOneWidget);
    expect(find.text('3 серії: 3–5'), findsOneWidget);
    // Episode 6 is on the device: "all" are 11 of 12, "unwatched" 9 of them
    expect(find.text('9 серій: 3–5, 7–12'), findsOneWidget);
    expect(find.text('11 серій: 1–5, 7–12'), findsOneWidget);
    expect(find.text('Завантажити 3 серії'), findsOneWidget);
    await t.tap(find.text('Усі непереглянуті'));
    await t.pump();
    expect(find.text('Завантажити 9 серій'), findsOneWidget);
    await t.tap(find.text('Вибрати вручну'));
    await t.pumpAndSettle();
    expect(find.text('Нічого не вибрано'), findsOneWidget);
    await t.tap(find.text('8'));
    await t.tap(find.text('10'));
    // A downloaded plate does not take a tap
    await t.tap(find.text('6'));
    await t.pump();
    expect(find.text('2 серії: 8, 10'), findsOneWidget);
    expect(find.text('Завантажити 2 серії'), findsOneWidget);
  });

  testWidgets('сторінка «Завантаження»: черга з причиною очікування, тайтли з «Продовжити», місце й налаштування', (t) async {
    await prepare(t, (m) async {
      await m.enqueue(animeKey: 'hikka:frieren', animeTitle: 'Фрірен', group: dub(), indexes: [0, 1, 2]);
    });
    // Episode 4 waits: no internet
    await t.runAsync(() async {
      net.apply(online: false, certain: true);
      await m.enqueue(animeKey: 'hikka:frieren', animeTitle: 'Фрірен', group: dub(), indexes: [3]);
      await m.save();
    });
    WatchService.instance.store
      ..setWatched('hikka:frieren', '1', true)
      ..setLast('hikka:frieren', '1', 'mikai|1|inari');
    await host(t, DownloadsPage(route: HikkaRoute(HikkaRouteKind.downloads, 'downloads'), scale: 1, manager: m));
    expect(find.text('Немає інтернету'), findsOneWidget);
    expect(find.text('Завантажується · 1'), findsOneWidget);
    expect(find.textContaining('Серія 4 · Немає інтернету'), findsOneWidget);
    expect(find.text('На пристрої'), findsOneWidget);
    expect(find.text('Продовжити · серія 2'), findsOneWidget);
    expect(find.text('Налаштування завантажень'), findsOneWidget);
    expect(find.text('Наступна серія сама'), findsOneWidget);
    expect(find.text('Видалити всі завантаження'), findsOneWidget);
    await t.runAsync(() async => net.apply(online: true, certain: true));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await t.pump();
  });

  testWidgets('сторінка тайтлу в завантаженнях: серії з розмірами, переглянута позначена', (t) async {
    await prepare(t, (m) async => m.enqueue(animeKey: 'hikka:frieren', animeTitle: 'Фрірен', group: dub(), indexes: [0, 1]));
    WatchService.instance.store.setWatched('hikka:frieren', '1', true);
    await host(t, DownloadShelfPage(route: HikkaRoute(HikkaRouteKind.downloadShelf, 'hikka:frieren|mikai|1|inari'), scale: 1, manager: m));
    expect(find.text('На пристрої 2 з 12 · 1 КБ'), findsOneWidget);
    expect(find.text('Продовжити · серія 2'), findsOneWidget);
    expect(find.text('Завантажити ще серії'), findsOneWidget);
    expect(find.text('720p · 1 КБ · переглянуто'), findsOneWidget);
    expect(find.text('Видалити всі серії'), findsOneWidget);
  });

  testWidgets('смужка «Немає інтернету» з дорогою до завантаженого', (t) async {
    await prepare(t, (m) async => m.enqueue(animeKey: 'hikka:frieren', animeTitle: 'Фрірен', group: dub(), indexes: [0]));
    await host(t, const Column(children: [Expanded(child: SizedBox()), OfflineStrip(scale: 1)]));
    expect(find.byKey(const ValueKey('offline-strip')).hitTestable(), findsNothing);
    net.apply(online: false, certain: true);
    await t.pumpAndSettle();
    expect(find.text('Немає інтернету'), findsOneWidget);
    expect(find.text('Завантажене'), findsOneWidget);
    net.apply(online: true, certain: true);
    await t.pumpAndSettle();
  });

  test('рядок у «Профілі»: що йде, чому чекає, що на пристрої', () async {
    final tmp = await Directory.systemTemp.createTemp('miki_dl_sum');
    final net = NetworkStatus(probe: () async => true);
    final m = DownloadManager(
      indexPath: '${tmp.path}/d.json',
      root: '${tmp.path}/r',
      network: net,
      registry: SourceRegistry(sources: const [], prefs: SourcePrefs(load: () => {}, save: (_) {})),
      loadPrefs: () => {},
      savePrefs: (_) {},
      storage: (_) async => null,
      resolve: (item) async => ResolvedVideo(Video(url: 'https://cdn.test/${item.episode.url}.mp4', title: '720p'), 'Moon'),
      fetch: (url, headers, {offset, length}) async => FetchResponse(200, 2048, Stream.value(List.filled(2048, 1)), () {}),
    );
    addTearDown(() async {
      m.dispose();
      net.dispose();
      await tmp.delete(recursive: true);
    });
    await m.init();
    expect(downloadsSummary(m), 'Серії для перегляду без інтернету');
    net.apply(online: false, certain: true);
    await m.enqueue(animeKey: 'hikka:x', animeTitle: 'X', group: dub(count: 3), indexes: [0, 1]);
    expect(downloadsSummary(m), 'Завантажується 2 · Немає інтернету');
    net.apply(online: true, certain: true);
    for (var i = 0; i < 300 && m.pending.isNotEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(downloadsSummary(m), '2 серії · 4 КБ');
    expect(DownloadText.amount(140 * 1024 * 1024, 315 * 1024 * 1024), '140 з 315 МБ');
    expect(DownloadText.episodes(21), '21 серія');
  });
}
