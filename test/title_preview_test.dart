// A preview of the title page as a phone shows it, with real pictures (Frieren): for comparing with design concepts.
// Not a check: it runs only with PREVIEW=1 and writes test/preview/title_*.png
// (PREVIEW=1 flutter test --update-goldens test/title_preview_test.dart).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miki_miki/models/source_models.dart';
import 'package:miki_miki/services/downloads/download_manager.dart';
import 'package:miki_miki/services/downloads/download_worker.dart';
import 'package:miki_miki/services/hikka_auth.dart';
import 'package:miki_miki/services/hikka_images.dart';
import 'package:miki_miki/services/hikka_lists.dart';
import 'package:miki_miki/services/hikka_nav.dart';
import 'package:miki_miki/services/network_status.dart';
import 'package:miki_miki/services/source_prefs.dart';
import 'package:miki_miki/services/source_registry.dart';
import 'package:miki_miki/services/sources/ua/mikai_source.dart';
import 'package:miki_miki/services/storage_service.dart';
import 'package:miki_miki/services/ui_theme_service.dart';
import 'package:miki_miki/services/watch_models.dart';
import 'package:miki_miki/services/watch_service.dart';
import 'package:miki_miki/utils/platform_info.dart';
import 'package:miki_miki/widgets/home_hub.dart';

import 'hikka_lists_ui_test.dart' as lists;
import 'support/fake_site.dart';
import 'support/hikka_account_fakes.dart';
import 'support/hikka_fakes.dart';
import 'support/remote_fakes.dart';

const String frieren = 'sousou-no-frieren-ad4e3e';
const String pics = '/tmp/concept/img';

final bool kPreview = Platform.environment['PREVIEW'] == '1';

Future<ByteData> _bytes(String path) async => ByteData.sublistView(Uint8List.fromList(await File(path).readAsBytes()));

/// Fonts as on a phone: "Arial" is missing there, so the text falls back to the bundled Liberation Sans
Future<void> _fonts() async {
  for (final family in ['Arial', 'MikiSans']) {
    await (FontLoader(family)
          ..addFont(_bytes('assets/fonts/subtitle.ttf'))
          ..addFont(_bytes('assets/fonts/LiberationSans-Bold.ttf')))
        .load();
  }
  final home = Platform.environment['HOME'] ?? '/root';
  await (FontLoader('packages/material_symbols_icons/MaterialSymbolsRounded')
        ..addFont(_bytes('$home/.pub-cache/hosted/pub.dev/material_symbols_icons-4.2960.0/lib/fonts/MaterialSymbolsRounded.ttf')))
      .load();
}

/// Real pictures by address: the poster, the AniList banner, character portraits; the rest are gradients
Future<Uint8List> _picture(String url) async {
  String? file;
  if (url.contains('anilist.co')) file = 'banner.jpg';
  if (url.contains('/anime/$frieren/') || url.contains('myanimelist')) file = 'poster.jpg';
  const chars = {'frieren-': 'c0.jpg', 'fern-': 'c1.jpg', 'stark-': 'c2.jpg', 'methode-': 'c3.jpg', 'himmel-': 'c4.jpg'};
  for (final e in chars.entries) {
    if (url.contains('/characters/${e.key}')) file = e.value;
  }
  if (file != null) return File('$pics/$file').readAsBytesSync();
  return fakePng(url);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(_fonts);

  /// [statusBar] in dp; the screen is [width]×[height] dp at the density of the person's phone (2.8)
  Future<void> render(WidgetTester tester, String name, {double width = 412, double height = 916, double statusBar = 34, List<double> scrollTo = const [], bool panel = false, bool screens = false, bool modals = false, bool guest = false, bool downloads = false, bool desktop = false}) async {
    final dpr = desktop ? 1.25 : 2.8;
    tester.view.physicalSize = Size(width * dpr, height * dpr);
    tester.view.devicePixelRatio = dpr;
    addTearDown(tester.view.reset);
    AppPlatform.debugMobile = !desktop;
    addTearDown(() => AppPlatform.debugMobile = null);
    uiTheme.setThemeMode('dark');

    final env = HikkaTestEnv();
    addTearDown(env.dispose);
    env.hasBanner = (_) => true;
    HikkaImageStore.instance = HikkaImageStore(dir: env.imageDir, fetcher: _picture);

    // Signed in; Frieren is in "Дивлюсь" with one episode
    final account = lists.FakeAccountServer(env.server)..seed();
    account.mine[frieren] = account.watchJson(frieren, status: 'watching', episodes: 1);
    HikkaAuth.instance = HikkaAuth(
      load: () => guest ? <String, dynamic>{} : {'token': 'tok-ui', 'me': Map<String, dynamic>.of(kMe)},
      save: (_) {},
      urlOpener: (url) async => true,
      loopbackFactory: () async => null,
    );
    HikkaMyList.instance = HikkaMyList();

    // Mikai knows the title: Inari has all 28 episodes, the first one is watched
    final detail = jsonDecode(fixture('mikai_detail.json')) as Map<String, dynamic>;
    final ids = (detail['result'] as Map<String, dynamic>)['ids'] as Map<String, dynamic>;
    ids['hikka'] = frieren;
    ids['mal'] = 52991;
    final player = jsonDecode(fixture('mikai_player.json')) as Map<String, dynamic>;
    for (final r in ((player['result'] as Map<String, dynamic>)['releases'] as List).cast<Map<String, dynamic>>()) {
      final n = (r['id'] as String).startsWith('t_121:') ? 28 : 12;
      r['episodes'] = [
        for (int i = 1; i <= n; i++)
          {
            'number': i,
            'label': '$i',
            'addedAt': '2026-11-02T06:48:37Z',
            'sources': [
              {'provider': 'moon', 'embedUrl': 'https://moonanime.art/iframe/${r['id']}/v$i/'},
            ],
          },
      ];
      r['episodesCount'] = n;
      r['lastEpisode'] = n;
    }
    final site = FakeSite({
      '/anime/hikka:$frieren': jsonEncode(detail),
      '/anime/7601/player': jsonEncode(player),
      '/teams/2': fixture('mikai_team.json'),
    });
    final store = memoryStore()
      ..setWatched('hikka:$frieren', '1', true)
      ..setLast('hikka:$frieren', '1', 'mikai|7601|t_121:voice');
    StorageService.saveWatchTeamPriority(['Inari']);
    WatchService.instance = WatchService(
      registry: SourceRegistry(sources: [MikaiSource(http: site.http)], prefs: SourcePrefs(load: () => {}, save: (_) {}), http: site.http),
      store: store,
    );

    // Downloads: a real manager over a temporary folder and a fake CDN (episodes download for real, quickly)
    final oldDownloads = DownloadManager.instance;
    final oldNetwork = NetworkStatus.instance;
    DownloadsRig? rig;
    if (downloads) {
      NetworkStatus.instance = NetworkStatus(probe: () async => true);
      rig = await tester.runAsync(() async => DownloadsRig.create(WatchService.instance.registry));
      addTearDown(() async {
        await tester.runAsync(() => rig!.dispose());
        DownloadManager.instance = oldDownloads;
        NetworkStatus.instance = oldNetwork;
      });
    }

    HomeHub.debugReset();
    final pad = EdgeInsets.only(top: desktop ? 0 : statusBar);
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      builder: (context, w) => MediaQuery(data: MediaQuery.of(context).copyWith(padding: pad, viewPadding: pad), child: w!),
      home: Scaffold(
        backgroundColor: uiTheme.bgPrimary,
        body: HomeHub(
          scale: AppPlatform.mobileScale,
          onOpenFile: (_) {},
          onOpenMultipleFiles: (_) {},
          onOpenQueue: (_, __) {},
          onOpenSettings: ({int? tab}) {},
        ),
      ),
    ));
    await lists.load(tester, rounds: 8);
    Future<void> snap(String shot) => expectLater(find.byType(MaterialApp), matchesGoldenFile('preview/modal_$shot.png'));
    Future<void> close() async {
      await tester.tapAt(const Offset(20, 120));
      await lists.load(tester, rounds: 8);
    }

    if (guest) {
      HikkaNav.instance.setMain(MainTab.lists);
      await lists.load(tester, rounds: 12);
      await snap('l6_guest');
      HikkaNav.instance.setMain(MainTab.profile);
      await lists.load(tester, rounds: 12);
      await snap('profile_guest');
      return;
    }
    if (modals) {
      // The lists: the sort drop-down, the long press, the filters, rows, an empty tab
      HikkaNav.instance.setMain(MainTab.lists);
      await lists.load(tester, rounds: 16);
      await tester.tap(find.text('Оновлені нещодавно'));
      await lists.load(tester, rounds: 8);
      await snap('m3_sort');
      await close();
      await tester.longPress(find.text('Зошит смерті'));
      await lists.load(tester, rounds: 8);
      await snap('l5_hold');
      await close();
      await tester.tap(find.byTooltip('Фільтри й сортування'));
      await lists.load(tester, rounds: 12);
      await snap('l4_filters');
      await tester.tap(find.byTooltip('Закрити').last);
      await lists.load(tester, rounds: 8);
      await tester.tap(find.byTooltip('Списком'));
      await lists.load(tester, rounds: 8);
      await snap('l2_rows');
      await tester.tap(find.byTooltip('Сіткою'));
      await tester.ensureVisible(find.byKey(const ValueKey('list-tab-3')));
      await lists.load(tester, rounds: 4);
      await tester.tap(find.byKey(const ValueKey('list-tab-3')));
      await lists.load(tester, rounds: 12);
      await snap('l7_empty');
      // The title page: "Мій список", a picker of the panel
      HikkaNav.instance.openAnime(frieren);
      await lists.load(tester, rounds: 40);
      await tester.tap(find.byTooltip('У списку: Дивлюсь'));
      await lists.load(tester, rounds: 12);
      await snap('m1_my_list');
      await tester.tap(find.byTooltip('Закрити').last);
      await lists.load(tester, rounds: 8);
      await tester.tap(find.byTooltip('Ще'));
      await lists.load(tester, rounds: 12);
      await tester.tap(find.text('Якість'));
      await lists.load(tester, rounds: 12);
      await snap('m4_picker');
      await tester.tap(find.byTooltip('Закрити').last);
      await lists.load(tester, rounds: 8);
      await tester.tap(find.byTooltip('Закрити').last);
      await lists.load(tester, rounds: 8);
      HikkaNav.instance.back();
      // The profile: signing out asks first
      HikkaNav.instance.setMain(MainTab.profile);
      await lists.load(tester, rounds: 16);
      await tester.scrollUntilVisible(find.text('Вийти з акаунта'), 300, scrollable: find.byType(Scrollable).first);
      await lists.load(tester, rounds: 6);
      await tester.tap(find.text('Вийти з акаунта'));
      await lists.load(tester, rounds: 8);
      await snap('m5_confirm');
      return;
    }
    if (downloads) {
      Future<void> snap(String shot) => expectLater(find.byType(MaterialApp), matchesGoldenFile('preview/downloads_${name}_$shot.png'));
      HikkaNav.instance.openAnime(frieren);
      await lists.load(tester, rounds: 40);
      final load = HikkaNav.instance.top!.memo['watch'] as WatchLoad;
      final groups = load.title.groups;
      await tester.runAsync(() => rig!.fill(groups, title: 'Фрірен, що проводжає в останню путь'));
      await lists.load(tester, rounds: 20);
      if (!desktop) {
        // The "Перегляд" panel: marks on the downloaded plates, the "Завантажити серії" row; then the picker
        await tester.tap(find.byTooltip('Ще'));
        await lists.load(tester, rounds: 12);
        await tester.drag(find.text('Якість').last, const Offset(0, -260));
        await lists.load(tester, rounds: 8);
        await snap('panel');
        await tester.tap(find.text('Завантажити серії'));
        await lists.load(tester, rounds: 16);
        await snap('picker');
        await tester.tap(find.text('Вибрати вручну'));
        await lists.load(tester, rounds: 12);
        for (final n in ['12', '13', '15']) {
          await tester.tap(find.text(n).last);
          await tester.pump();
        }
        await lists.load(tester, rounds: 8);
        await snap('picker_manual');
        await tester.tap(find.byTooltip('Закрити').last);
        await lists.load(tester, rounds: 8);
      }
      HikkaNav.instance.openDownloads();
      await lists.load(tester, rounds: 20);
      await snap('page_1');
      if (!desktop) {
        final list = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).hitTestable().first;
        await tester.drag(list, const Offset(0, -700));
        await lists.load(tester, rounds: 12);
        await snap('page_2');
      }
      HikkaNav.instance.openDownloadShelf(load.title.animeKey, groups.first.id);
      await lists.load(tester, rounds: 20);
      await snap('shelf');
      // No internet: the strip over the navigation, what is downloaded first on "Головна" (Hikka does not answer either)
      env.server.interceptor = (r) => throw const SocketException('offline');
      NetworkStatus.instance.apply(online: false, certain: true);
      HikkaNav.instance.back();
      HikkaNav.instance.back();
      HikkaNav.instance.back();
      HikkaNav.instance.setMain(MainTab.home);
      await lists.load(tester, rounds: 30);
      await snap('home_offline');
      // Its recheck timer must not outlive the test (removing listeners after this is allowed)
      NetworkStatus.instance.dispose();
      return;
    }
    if (screens) {
      // Every main tab and page as it looks now: the base for the next design concepts
      Future<void> grab(String shot, {double scroll = 0}) async {
        if (scroll > 0) {
          final list = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).hitTestable().first;
          await tester.drag(list, Offset(0, -scroll));
          await lists.load(tester, rounds: 12);
        }
        await expectLater(find.byType(MaterialApp), matchesGoldenFile(name == 'screens' ? 'preview/screen_$shot.png' : 'preview/${name}_$shot.png'));
      }
      for (final tab in MainTab.values) {
        HikkaNav.instance.setMain(tab);
        await lists.load(tester, rounds: 30);
        await grab('${tab.name}_1');
        await grab('${tab.name}_2', scroll: 700);
        await grab('${tab.name}_3', scroll: 700);
      }
      if (name != 'screens') return;
      // The sections of "Огляд" besides "Усе"
      HikkaNav.instance.setMain(MainTab.discover);
      for (final t in HikkaTab.values.where((t) => t != HikkaTab.overview)) {
        HikkaNav.instance.setTab(t);
        await lists.load(tester, rounds: 30);
        await grab('tab_${t.name}_1');
        await grab('tab_${t.name}_2', scroll: 700);
      }
      HikkaNav.instance.setTab(HikkaTab.overview);
      final pages = <String, VoidCallback>{
        'character': () => HikkaNav.instance.openCharacter('frieren-7f706c'),
        'person': () => HikkaNav.instance.openPerson('kanehito-yamada-d0a463'),
        'franchise': () => HikkaNav.instance.openFranchise(frieren),
        'cast': () => HikkaNav.instance.openAnimeCharacters(frieren),
        'staff': () => HikkaNav.instance.openAnimeStaff(frieren),
        'collection': () => HikkaNav.instance.openCollection('ff0f841a-7e7f-4cae-b61f-db123dcbab8b'),
        'article': () => HikkaNav.instance.openArticle('systema-stattey-tak-yak-neyu-korystuvatys-63a557'),
        'notifications': () => HikkaNav.instance.openNotifications(),
        'user': () => HikkaNav.instance.openUser('tester'),
        'local': () => HikkaNav.instance.openLocalLibrary(),
      };
      for (final e in pages.entries) {
        e.value();
        await lists.load(tester, rounds: 30);
        await grab('${e.key}_1');
        await grab('${e.key}_2', scroll: 700);
        HikkaNav.instance.back();
        await lists.load(tester, rounds: 12);
      }
      return;
    }
    HikkaNav.instance.setMain(MainTab.discover);
    await lists.load(tester, rounds: 8);
    HikkaNav.instance.openAnime(frieren);
    await lists.load(tester, rounds: 40);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('preview/title_$name.png'));
    if (panel) {
      await tester.tap(find.byTooltip('Ще'));
      await lists.load(tester, rounds: 12);
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('preview/title_${name}_panel.png'));
      await tester.tap(find.text('Озвучення'));
      await lists.load(tester, rounds: 12);
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('preview/title_${name}_dubs.png'));
      return;
    }
    var done = 0.0;
    for (final (i, y) in scrollTo.indexed) {
      final list = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first;
      await tester.drag(list, Offset(0, -(y - done)));
      done = y;
      await lists.load(tester, rounds: 12);
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('preview/title_${name}_${i + 1}.png'));
    }
  }

  testWidgets('сторінка тайтла як на телефоні 412 dp', (tester) => render(tester, 'phone', scrollTo: const [520, 1150, 1800]), skip: !kPreview);
  testWidgets('панель «Перегляд» і вибір озвучки', (tester) => render(tester, 'phone', panel: true), skip: !kPreview);
  testWidgets('решта екранів, як вони виглядають зараз', (tester) => render(tester, 'screens', screens: true), skip: !kPreview);
  testWidgets('вікна й меню (М1, М3–М5, Л2, Л4, Л5, Л7)', (tester) => render(tester, 'modals', modals: true), skip: !kPreview);
  testWidgets('гість: списки й профіль (Л6)', (tester) => render(tester, 'guest', guest: true), skip: !kPreview);
  testWidgets('завантаження: панель, вибір серій, сторінки, офлайн (телефон)', (tester) => render(tester, 'phone', downloads: true), skip: !kPreview);
  testWidgets('завантаження на ПК', (tester) => render(tester, 'pc', width: 1280, height: 800, downloads: true, desktop: true), skip: !kPreview);
  testWidgets('головні вкладки на ширшому екрані, 520 dp', (tester) => render(tester, 'tabs520', width: 520, height: 1157, statusBar: 32, screens: true), skip: !kPreview);
  testWidgets('ширший екран (дрібний масштаб системи), 520 dp', (tester) => render(tester, 'w520', width: 520, height: 1157, statusBar: 32), skip: !kPreview);
}


/// Downloads for the previews: a manager over a temporary folder, a CDN that answers at once, one episode that stops
/// at 44 % (its stream never ends), sizes as real episodes have
class DownloadsRig {
  final Directory dir;
  final StreamController<List<int>> slow = StreamController<List<int>>();
  String slowId = '';
  late final DownloadManager manager;
  final SourceRegistry registry;

  DownloadsRig._(this.dir, this.registry);

  static Future<DownloadsRig> create(SourceRegistry registry) async {
    final r = DownloadsRig._(await Directory.systemTemp.createTemp('miki_dl_preview'), registry);
    r.manager = r._make();
    DownloadManager.instance = r.manager;
    await r.manager.init();
    return r;
  }

  DownloadManager _make() => DownloadManager(
        indexPath: '${dir.path}/downloads.json',
        root: '${dir.path}/root',
        network: NetworkStatus.instance,
        registry: registry,
        loadPrefs: () => {},
        savePrefs: (_) {},
        storage: (_) async => (21 * 1024 * 1024 * 1024 + 400 * 1024 * 1024, 64 * 1024 * 1024 * 1024),
        resolve: (item) async => ResolvedVideo(Video(url: 'https://cdn.test/${Uri.encodeComponent(item.id)}.mp4', title: '1080p', resolution: 1080), 'Moon'),
        fetch: (url, headers, {offset, length}) async {
          final id = Uri.decodeComponent(url.pathSegments.last.replaceAll('.mp4', ''));
          if (id == slowId) return FetchResponse(200, 315 * 1024 * 1024, slow.stream, () {});
          return FetchResponse(200, 64, Stream.value(List.filled(64, 1)), () {});
        },
      );

  Future<void> _settle() async {
    for (var i = 0; i < 300 && manager.pending.any((x) => x.isActive); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await manager.save();
  }

  /// Episodes 1–5 of the first dub and 1–2 of the second on the device (with real sizes), episode 6 at 44 %, 7–8
  /// waiting for it
  Future<void> fill(List<WatchGroup> groups, {required String title}) async {
    const poster = 'https://cdn.hikka.io/anime/sousou-no-frieren-ad4e3e/poster.jpg';
    await manager.enqueue(animeKey: 'hikka:$frieren', animeTitle: title, poster: poster, group: groups[0], indexes: [0, 1, 2, 3, 4]);
    if (groups.length > 1) await manager.enqueue(animeKey: 'hikka:$frieren', animeTitle: title, poster: poster, group: groups[1], indexes: [0, 1]);
    await _settle();
    // Real episodes weigh ~300 МБ: the index gets their sizes and a fresh manager reads it
    final f = File('${dir.path}/downloads.json');
    final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    var n = 0;
    for (final i in (j['items'] as List).cast<Map<String, dynamic>>()) {
      i['bytes'] = i['total'] = (288 + (n++ * 37) % 60) * 1024 * 1024;
    }
    await f.writeAsString(jsonEncode(j));
    await manager.debugReload();
    slowId = '${groups[0].sourceId}|${groups[0].episodes[5].url}';
    await manager.enqueue(animeKey: 'hikka:$frieren', animeTitle: title, poster: poster, group: groups[0], indexes: [5, 6, 7]);
    for (var i = 0; i < 35; i++) {
      slow.add(List.filled(4 * 1024 * 1024, 0));
      await Future<void>.delayed(const Duration(milliseconds: 60));
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  Future<void> dispose() async {
    manager.dispose();
    await slow.close();
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}
