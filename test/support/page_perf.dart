// Shared tools of the page speed tests (page_perf_test, pages_perf_test): frame time and rebuild counts, a finger
// that scrolls, the app shell with a signed-in account, and generated "heavy" data — lists as long as on a real
// account and pages of really big titles (a long franchise, a voice actor with hundreds of roles, a long article).
//
// Frame times are debug-mode numbers on the CPU: they only compare runs. Rebuild counts and "frames asked for"
// do not depend on the machine: those are what the checks rest on.
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miki_miki/services/episode_alerts.dart';
import 'package:miki_miki/services/hikka_api.dart';
import 'package:miki_miki/services/hikka_auth.dart';
import 'package:miki_miki/services/hikka_images.dart';
import 'package:miki_miki/services/hikka_lists.dart';
import 'package:miki_miki/services/hikka_nav.dart';
import 'package:miki_miki/services/source_prefs.dart';
import 'package:miki_miki/services/source_registry.dart';
import 'package:miki_miki/services/sources/ua/mikai_source.dart';
import 'package:miki_miki/services/storage_service.dart';
import 'package:miki_miki/services/ui_theme_service.dart';
import 'package:miki_miki/services/watch_service.dart';
import 'package:miki_miki/utils/app_clock.dart';
import 'package:miki_miki/utils/platform_info.dart';
import 'package:miki_miki/widgets/app_settings_dialog.dart';
import 'package:miki_miki/widgets/home_hub.dart';

import '../hikka_lists_ui_test.dart' as lists;
import 'fake_site.dart';
import 'fakes.dart';
import 'hikka_account_fakes.dart';
import 'hikka_fakes.dart';
import 'perf_harness.dart';
import 'remote_fakes.dart';

const String perfFrieren = 'sousou-no-frieren-ad4e3e';
const String _pics = '/tmp/concept/img';

Future<ByteData> _bytes(String path) async => ByteData.sublistView(Uint8List.fromList(await File(path).readAsBytes()));

/// Fonts as on a phone: "Arial" falls back to the bundled Liberation Sans (the real text layout cost). The icon font
/// comes from the pub cache when it is where this machine keeps it; without it the icons are boxes, the counts stay
/// the same
Future<void> perfFonts() async {
  for (final family in ['Arial', 'MikiSans']) {
    await (FontLoader(family)
          ..addFont(_bytes('assets/fonts/subtitle.ttf'))
          ..addFont(_bytes('assets/fonts/LiberationSans-Bold.ttf')))
        .load();
  }
  final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '/root';
  final symbols = File('$home/.pub-cache/hosted/pub.dev/material_symbols_icons-4.2960.0/lib/fonts/MaterialSymbolsRounded.ttf');
  if (symbols.existsSync()) {
    await (FontLoader('packages/material_symbols_icons/MaterialSymbolsRounded')..addFont(_bytes(symbols.path))).load();
  }
}

/// Real pictures by address when they are on disk (the poster, the banner, portraits); the rest are generated
/// (a poster-sized picture, so decoding costs about what a real one does)
Future<Uint8List> perfPicture(String url) async {
  String? file;
  if (url.contains('anilist.co')) file = 'banner.jpg';
  if (url.contains('/anime/$perfFrieren/') || url.contains('myanimelist')) file = 'poster.jpg';
  const chars = {'frieren-': 'c0.jpg', 'fern-': 'c1.jpg', 'stark-': 'c2.jpg', 'methode-': 'c3.jpg', 'himmel-': 'c4.jpg'};
  for (final e in chars.entries) {
    if (url.contains('/characters/${e.key}')) file = e.value;
  }
  if (file != null && File('$_pics/$file').existsSync()) return File('$_pics/$file').readAsBytesSync();
  return fakePng(url, w: 230, h: 320);
}

// ── Measuring ───────────────────────────────────────────────────────────────────

/// Counts rebuilds like [RebuildCounter] and remembers the rebuilt elements: [roots] tells where each wave of
/// rebuilds started (a `setState`, a changed dependency) — the element whose nearest component ancestor was not rebuilt
class PerfRebuilds extends RebuildCounter {
  final Set<Element> _rebuilt = HashSet<Element>.identity();

  @override
  void start() {
    debugOnRebuildDirtyWidget = (Element e, bool builtOnce) {
      total++;
      final name = e.widget.runtimeType.toString();
      byType[name] = (byType[name] ?? 0) + 1;
      _rebuilt.add(e);
    };
  }

  /// "Image ← HikkaPoster ← HikkaAnimeCard" → how many waves started there (with how many rebuilds in all)
  Map<String, int> roots() {
    final out = <String, int>{};
    for (final e in _rebuilt) {
      final chain = <String>[];
      var isRoot = true;
      try {
        e.visitAncestorElements((p) {
          if (p is ComponentElement && chain.isEmpty) {
            if (_rebuilt.contains(p)) {
              isRoot = false;
              return false;
            }
          }
          if (p is ComponentElement) chain.add(p.widget.runtimeType.toString());
          return chain.length < 3;
        });
      } catch (_) {
        continue; // already gone from the tree
      }
      if (!isRoot) continue;
      final name = [e.widget.runtimeType.toString(), ...chain].join(' ← ');
      out[name] = (out[name] ?? 0) + 1;
    }
    return out;
  }
}

/// One stage's frames: time (debug, ms) and how many widgets each one rebuilt
class PerfFrames {
  final String name;
  final List<double> ms = [];
  final List<int> builds = [];
  final Map<String, int> top = {};

  /// What the frame with the most rebuilds rebuilt (by widget type) and where its waves of rebuilds started
  Map<String, int> heaviest = const {};
  Map<String, int> heaviestRoots = const {};
  int _heaviestBuilds = -1;

  PerfFrames(this.name);

  void add(double t, RebuildCounter c) {
    ms.add(t);
    builds.add(c.total);
    for (final e in c.byType.entries) {
      top[e.key] = (top[e.key] ?? 0) + e.value;
    }
    if (c.total > _heaviestBuilds) {
      _heaviestBuilds = c.total;
      heaviest = Map.of(c.byType);
      heaviestRoots = c is PerfRebuilds ? c.roots() : const {};
    }
  }

  /// Takes [other]'s frames in (the loading pauses between scroll passes)
  void merge(PerfFrames other) {
    ms.addAll(other.ms);
    builds.addAll(other.builds);
    for (final e in other.top.entries) {
      top[e.key] = (top[e.key] ?? 0) + e.value;
    }
    if (other._heaviestBuilds > _heaviestBuilds) {
      _heaviestBuilds = other._heaviestBuilds;
      heaviest = other.heaviest;
      heaviestRoots = other.heaviestRoots;
    }
  }

  /// The heaviest frame's rebuilds, the most frequent types first
  String heaviestText([int n = 8]) {
    final l = heaviest.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return l.take(n).map((e) => '${e.key}×${e.value}').join(', ');
  }

  /// Where the heaviest frame's rebuilds started, the most frequent first
  String rootsText([int n = 6]) {
    final l = heaviestRoots.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return l.take(n).map((e) => '${e.key} ×${e.value}').join('; ');
  }

  static double _pct(List<num> v, double p) {
    if (v.isEmpty) return 0;
    final s = [...v]..sort();
    return s[((s.length - 1) * p).round()].toDouble();
  }

  double get msMedian => _pct(ms, 0.5);
  double get msP90 => _pct(ms, 0.9);
  double get msMax => ms.isEmpty ? 0 : ms.reduce((a, b) => a > b ? a : b);
  int get buildsMedian => _pct(builds, 0.5).round();
  int get buildsP90 => _pct(builds, 0.9).round();
  int get buildsMax => builds.isEmpty ? 0 : builds.reduce((a, b) => a > b ? a : b);
  int get buildsTotal => builds.fold(0, (a, b) => a + b);

  String topText([int n = 6]) {
    final l = top.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return l.take(n).map((e) => '${e.key}×${e.value}').join(', ');
  }

  /// "8.6 / 21 / 40 мс · 12 / 49 / 700" — median, p90 and max of time and rebuilds
  String get short => '${msMedian.toStringAsFixed(1)} / ${msP90.toStringAsFixed(1)} / ${msMax.toStringAsFixed(0)} мс · '
      '$buildsMedian / $buildsP90 / $buildsMax';

  @override
  String toString() => '$name: кадрів ${ms.length}; мс/кадр (debug) медіана ${msMedian.toStringAsFixed(1)}, p90 ${msP90.toStringAsFixed(1)}, '
      'макс ${msMax.toStringAsFixed(1)}; перебудов/кадр медіана $buildsMedian, p90 $buildsP90, макс $buildsMax (усього $buildsTotal); '
      'найчастіше: ${topText()}';
}

/// One frame: [action] (a pointer move, a navigation…), then the frame itself; time and rebuilds of both
Future<void> perfFrame(WidgetTester tester, PerfFrames f, {Future<void> Function()? action, Duration step = const Duration(milliseconds: 16)}) async {
  final c = PerfRebuilds()..start();
  final sw = Stopwatch()..start();
  try {
    if (action != null) await action();
    await tester.pump(step);
  } finally {
    sw.stop();
    c.stop();
  }
  f.add(sw.elapsedMicroseconds / 1000, c);
}

/// Lets the fake network and the image store answer (real async work), then a frame; counted into [f]
Future<void> perfSettle(WidgetTester tester, PerfFrames f, {int rounds = 12}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await perfFrame(tester, f, step: const Duration(milliseconds: 60));
  }
}

/// A still page: for 2 s no frame may be asked for (no endless animation, no timer that repaints); [moving] gets
/// what was rebuilt meanwhile (a hint at what moves)
Future<int> perfIdleFrames(WidgetTester tester, {PerfFrames? moving}) async {
  await tester.pump(const Duration(seconds: 2)); // the last animations end
  var busy = 0;
  for (var i = 0; i < 120; i++) {
    if (moving != null) {
      await perfFrame(tester, moving);
    } else {
      await tester.pump(const Duration(milliseconds: 16));
    }
    if (tester.binding.hasScheduledFrame) busy++;
  }
  return busy;
}

/// The page's vertical scroll view: the largest one that takes touches (not the PC sidebar or a row of cards)
Element _pageScrollable(WidgetTester tester) {
  final all = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).hitTestable().evaluate();
  Element? best;
  var area = -1.0;
  for (final e in all) {
    final r = tester.getRect(find.byElementPredicate((x) => identical(x, e)));
    if (r.width * r.height > area) {
      best = e;
      area = r.width * r.height;
    }
  }
  return best!;
}

Rect perfScrollRect(WidgetTester tester) {
  final e = _pageScrollable(tester);
  return tester.getRect(find.byElementPredicate((x) => identical(x, e)));
}

/// The page's scroll position (how far it is from the top)
ScrollPosition perfScrollPosition(WidgetTester tester) => ((_pageScrollable(tester) as StatefulElement).state as ScrollableState).position;

/// A finger scrolls [distance] in [frames] even steps (a frame per step); [up] — back to the top
Future<void> perfScroll(WidgetTester tester, PerfFrames f, {required double distance, int frames = 60, bool up = false}) async {
  final box = perfScrollRect(tester);
  final start = Offset(box.center.dx, up ? box.top + box.height * 0.25 : box.top + box.height * 0.75);
  final g = await tester.startGesture(start);
  final dy = (up ? 1 : -1) * distance / frames;
  for (var i = 0; i < frames; i++) {
    await perfFrame(tester, f, action: () => g.moveBy(Offset(0, dy)));
  }
  await g.up();
  await tester.pump(const Duration(milliseconds: 16));
}

// ── The app with an account ─────────────────────────────────────────────────────────

/// The mounted app: the fake Hikka server and the signed-in account on it
class PerfHub {
  final HikkaTestEnv env;
  final lists.FakeAccountServer account;
  final bool phone;

  PerfHub(this.env, this.account, this.phone);

  FakeHikka get server => env.server;

  /// Puts [handler] in front of the server's answers: what it returns wins, `null` passes the request on; [next]
  /// asks the answers under it (the account, earlier generators)
  void intercept(HikkaResponse? Function(HikkaRequest r, List<String> segs, HikkaResponse? Function(HikkaRequest r) next) handler) {
    final inner = server.interceptor;
    HikkaResponse? next(HikkaRequest r) => inner?.call(r);
    server.interceptor = (r) => handler(r, r.url.path.split('/').where((s) => s.isNotEmpty).toList(), next) ?? next(r);
  }
}

/// The app shell as on the person's phone (412 dp, density 2.8, status bar 34) or a PC window (1280×720): signed in,
/// Frieren in "Дивлюсь" with one episode watched, Mikai with Inari ([episodes] in its release). [data] adds the heavy
/// data before the first frame; [initial] — the tab the app starts on; [size] — another window (dp)
Future<PerfHub> mountPerfHub(
  WidgetTester tester, {
  required bool phone,
  void Function(PerfHub hub)? data,
  int episodes = 28,
  MainTab initial = MainTab.home,
  Size? size,
}) async {
  final dpr = phone ? 2.8 : 1.0;
  size ??= phone ? const Size(412, 916) : const Size(1280, 720);
  tester.view.physicalSize = size * dpr;
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.reset);
  AppPlatform.debugMobile = phone;
  addTearDown(() => AppPlatform.debugMobile = null);
  uiTheme.setThemeMode('dark');

  final env = HikkaTestEnv();
  addTearDown(env.dispose);
  env.hasBanner = (_) => true;
  HikkaImageStore.instance = HikkaImageStore(dir: env.imageDir, fetcher: perfPicture);

  final account = lists.FakeAccountServer(env.server)..seed();
  account.mine[perfFrieren] = account.watchJson(perfFrieren, status: 'watching', episodes: 1);
  final hub = PerfHub(env, account, phone);
  EpisodeAlerts.instance = PerfData.alerts(0);
  data?.call(hub);
  HikkaAuth.instance = HikkaAuth(
    load: () => {'token': 'tok-ui', 'me': Map<String, dynamic>.of(kMe)},
    save: (_) {},
    urlOpener: (url) async => true,
    loopbackFactory: () async => null,
  );
  HikkaMyList.instance = HikkaMyList();

  final detail = jsonDecode(fixture('mikai_detail.json')) as Map<String, dynamic>;
  final ids = (detail['result'] as Map<String, dynamic>)['ids'] as Map<String, dynamic>;
  ids['hikka'] = perfFrieren;
  ids['mal'] = 52991;
  final player = jsonDecode(fixture('mikai_player.json')) as Map<String, dynamic>;
  for (final r in ((player['result'] as Map<String, dynamic>)['releases'] as List).cast<Map<String, dynamic>>()) {
    final n = (r['id'] as String).startsWith('t_121:') ? episodes : 12;
    r['episodes'] = [
      for (int i = 1; i <= n; i++)
        {
          'number': i,
          'label': '$i',
          'addedAt': '2026-11-02T06:48:37Z',
          'sources': [
            {'provider': 'moon', 'embedUrl': 'https://moonanime.art/iframe/v$i/'},
          ],
        },
    ];
    r['episodesCount'] = n;
    r['lastEpisode'] = n;
  }
  final site = FakeSite({
    '/anime/hikka:$perfFrieren': jsonEncode(detail),
    '/anime/7601/player': jsonEncode(player),
    '/teams/2': fixture('mikai_team.json'),
  });
  final store = memoryStore()
    ..setWatched('hikka:$perfFrieren', '1', true)
    ..setLast('hikka:$perfFrieren', '1', 'mikai|7601|t_121:voice');
  StorageService.saveWatchTeamPriority(['Inari']);
  WatchService.instance = WatchService(
    registry: SourceRegistry(sources: [MikaiSource(http: site.http)], prefs: SourcePrefs(load: () => {}, save: (_) {}), http: site.http),
    store: store,
  );

  HomeHub.debugReset();
  if (initial != MainTab.home) HikkaNav.instance.setMain(initial);
  final pad = EdgeInsets.only(top: phone ? 34 : 0);
  final scale = phone ? AppPlatform.mobileScale : 1.0;
  await tester.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    builder: (context, w) => MediaQuery(data: MediaQuery.of(context).copyWith(padding: pad, viewPadding: pad), child: w!),
    home: Scaffold(
      backgroundColor: uiTheme.bgPrimary,
      body: HomeHub(
        scale: scale,
        onOpenFile: (_) {},
        onOpenMultipleFiles: (_) {},
        onOpenQueue: (_, __) {},
        onOpenSettings: ({int? tab}) {},
        // On a phone the settings are a page of the app (as in the player screen); on a PC a window
        settingsBuilder: (ctx) => AppSettingsDialog(scale: scale, controller: FakeController(), embedded: true, initialTab: HikkaNav.instance.settingsTab),
      ),
    ),
  ));
  await lists.load(tester, rounds: 10);
  return hub;
}

// ── Heavy data ───────────────────────────────────────────────────────────────────

HikkaResponse _ok(Object? body) => HikkaResponse(200, jsonEncode(body));

/// Generated data on the scale of real heavy cases. Each generator adds its answers in front of the fake server;
/// every item has its own address and picture (as on Hikka: a new row brings new pictures to decode)
abstract final class PerfData {
  static final List<Map<String, dynamic>> _anime = [
    for (final e in (sampleMap('big_search.json')['list'] as List)) e as Map<String, dynamic>,
  ];
  static final List<Map<String, dynamic>> _characters = [for (int i = 1; i <= 8; i++) sampleMap('char_$i.json')];
  static final Map<String, dynamic> _person = ((sampleMap('staff.json')['list'] as List).first as Map<String, dynamic>)['person'] as Map<String, dynamic>;

  /// A page of [all] by the request's `page` / `size` (as the server cuts it)
  static Map<String, dynamic> page(List<Map<String, dynamic>> all, Uri url, {int size = 30}) {
    final p = int.tryParse(url.queryParameters['page'] ?? '') ?? 1;
    final s = int.tryParse(url.queryParameters['size'] ?? '') ?? size;
    final from = ((p - 1) * s).clamp(0, all.length);
    final to = (from + s).clamp(0, all.length);
    return {
      'pagination': {'total': all.length, 'pages': (all.length / s).ceil().clamp(1, 1 << 20), 'page': p},
      'list': all.sublist(from, to),
    };
  }

  /// The [i]-th generated anime: a catalog record with its own address, name and poster
  static Map<String, dynamic> anime(int i) {
    final b = _anime[i % _anime.length];
    final title = (b['title_ua'] ?? b['title_en'] ?? b['title_ja'] ?? 'Аніме') as String;
    return {
      ...b,
      'slug': 'gen-anime-$i',
      'title_ua': i < _anime.length ? title : '$title ${i ~/ _anime.length + 1}',
      'image': 'https://cdn.hikka.io/content/anime/gen-anime-$i/poster.jpg',
      'mal_id': 900000 + i,
      'nsfw': false,
      'rating': b['rating'] == 'rx' ? 'r' : b['rating'],
      'year': 1990 + (i * 7) % 36,
    };
  }

  static Map<String, dynamic> character(int i) {
    final b = _characters[i % _characters.length];
    return {
      ...b,
      'slug': 'gen-char-$i',
      'name_ua': '${b['name_ua']} ${i + 1}',
      'image': 'https://cdn.hikka.io/content/characters/gen-char-$i/portrait.jpg',
    };
  }

  static Map<String, dynamic> person(int i) => {
        ..._person,
        'slug': 'gen-person-$i',
        'name_ua': '${_person['name_ua']} ${i + 1}',
        'image': i % 5 == 4 ? null : 'https://cdn.hikka.io/content/people/gen-person-$i/photo.jpg',
      };

  /// [n] more titles in the catalog ("Огляд → Каталог", shelves); the lists take their titles from here too
  static void catalog(PerfHub h, int n) => h.server.animeList.addAll([for (int i = 0; i < n; i++) anime(i)]);

  /// [n] more characters ("Огляд → Персонажі")
  static void characters(PerfHub h, int n) => h.server.characters.addAll([for (int i = 0; i < n; i++) character(i)]);

  /// The calendar of a busy season: [perDay] episodes a day for [days] days from yesterday
  static void schedule(PerfHub h, {int perDay = 36, int days = 15}) {
    final base = (sampleMap('sched_default.json')['list'] as List).cast<Map<String, dynamic>>();
    final now = HikkaTestEnv.fixedNow;
    final start = DateTime(now.year, now.month, now.day - 1, 0, 30).millisecondsSinceEpoch ~/ 1000;
    final all = [
      for (int k = 0; k < perDay * days; k++)
        {
          ...base[k % base.length],
          'anime': {
            ...(base[k % base.length]['anime'] as Map<String, dynamic>),
            'slug': 'gen-sched-${k % (perDay * 7)}',
            'image': 'https://cdn.hikka.io/content/anime/gen-sched-${k % (perDay * 7)}/poster.jpg',
            'nsfw': false,
            'rating': 'pg_13',
          },
          'episode': 1 + k ~/ (perDay * 7),
          'airing_at': start + (k * 86400) ~/ perDay,
        },
    ];
    h.intercept((r, segs, _) => r.method == 'POST' && r.url.path == '/schedule/anime' ? _ok(page(all, r.url, size: 50)) : null);
  }

  /// [n] articles in "Огляд → Статті" (each with its own cover)
  static void articles(PerfHub h, int n) {
    final base = (sampleMap('articles_list.json')['list'] as List).cast<Map<String, dynamic>>();
    final all = [
      for (int i = 0; i < n; i++)
        {
          ...base[i % base.length],
          'slug': 'gen-article-$i',
          'title': '${base[i % base.length]['title']} (${i + 1})',
          'vote_score': (i * 13) % 120,
          'comments_count': (i * 5) % 40,
          'author': {...(base[i % base.length]['author'] as Map<String, dynamic>), 'username': 'author_${i % 17}'},
          'preview': [
            {
              'type': 'p',
              'children': [
                {'text': 'Короткий вступ до статті номер ${i + 1}: що сталося, хто це зробив і чому це важливо для глядачів.'},
              ],
            },
            {
              'type': 'image_group',
              'children': [
                {
                  'type': 'image',
                  'url': 'https://cdn.hikka.io/uploads/gen/attachment/cover-$i.webp',
                  'children': [
                    {'text': ''},
                  ],
                },
              ],
            },
          ],
        },
    ];
    h.intercept((r, segs, _) => r.method == 'POST' && r.url.path == '/articles' ? _ok(page(all, r.url, size: 20)) : null);
  }

  /// A long article ([repeats] times the sample's 19 blocks: paragraphs, headings, lists, quotes, a spoiler and
  /// image groups, each picture its own)
  static void article(PerfHub h, String slug, {int repeats = 7}) {
    final detail = sampleMap('article_detail.json');
    final blocks = (detail['document'] as List).cast<Map<String, dynamic>>();
    Object? unique(Object? node, int r) {
      if (node is Map<String, dynamic>) {
        return {
          for (final e in node.entries) e.key: e.key == 'url' && node['type'] == 'image' ? '${e.value}?r=$r' : unique(e.value, r),
        };
      }
      if (node is List) return [for (final x in node) unique(x, r)];
      return node;
    }

    final document = [for (int r = 0; r < repeats; r++) for (final b in blocks) unique(b, r)];
    h.intercept((r, segs, _) => r.method == 'GET' && segs.length == 2 && segs[0] == 'articles' && segs[1] == slug
        ? _ok({...detail, 'slug': slug, 'document': document})
        : null);
  }

  /// [n] collections like on Hikka: different titles, authors and numbers, each with its own posters; built from the
  /// two in the sample data
  static List<Map<String, dynamic>> collectionList(int n) {
    final base = (sampleMap('collections_list.json')['list'] as List).cast<Map<String, dynamic>>();
    const words = ['Осінь', 'Правило трьох епізодів', 'Україна в аніме', 'Найкраще за десятиліття', 'Для вечора', 'Ісекай без втоми',
        'Тихі історії про життя й дорослішання', 'Спорт', 'Меха', 'Романтика на кожен день', 'Детективи', 'Класика'];
    return [
      for (int i = 0; i < n; i++)
        () {
          final b = base[i % base.length];
          final entries = (b['collection'] as List).cast<Map<String, dynamic>>();
          return <String, dynamic>{
            ...b,
            'reference': 'gen-collection-$i',
            'title': '${words[i % words.length]}${i >= words.length ? ' · ${i ~/ words.length + 1}' : ''}',
            'vote_score': (i * 37) % 300,
            'comments_count': (i * 11) % 90,
            'entries': 10 + (i * 7) % 90,
            'nsfw': false,
            'author': {...(b['author'] as Map<String, dynamic>), 'username': 'user_${i % 23}'},
            'collection': [
              for (int k = 0; k < 4 && k < entries.length; k++)
                {
                  ...entries[k],
                  'content': {
                    ...(entries[k]['content'] as Map<String, dynamic>),
                    'image': 'https://cdn.hikka.io/content/anime/gen-$i-$k.jpg',
                    'nsfw': false,
                    'rating': 'pg_13',
                  },
                },
            ],
          };
        }(),
    ];
  }

  /// [n] collections in every collection list (20 per page)
  static void collections(PerfHub h, int n) {
    final all = collectionList(n);
    h.intercept((r, segs, _) => r.method == 'POST' && r.url.path == '/collections' ? _ok(page(all, r.url, size: 15)) : null);
  }

  /// A big collection: [n] titles in three groups, every other one with the author's comment
  static void collection(PerfHub h, String reference, int n) {
    final detail = sampleMap('collection_detail.json');
    const labels = ['Осінь 2023', 'Зима 2024', 'Весна 2024'];
    const comments = [
      'Перші три серії тримають, далі — ще краще. **Must watch** для тих, хто любить повільні історії.',
      'Кинула на п’ятій серії: красиво, але порожньо. Можливо, повернуся, якщо вийде другий сезон.',
      'Неочікувано сильна драма. ||Фінал восьмої серії — найкраще, що я бачила цього сезону.|| Раджу [оригінал](https://hikka.io).',
    ];
    final entries = [
      for (int i = 0; i < n; i++)
        {
          'content_type': 'anime',
          'comment': i.isEven ? comments[(i ~/ 2) % comments.length] : null,
          'label': labels[(i * labels.length) ~/ n],
          'order': i + 1,
          'content': anime(i),
        },
    ];
    h.intercept((r, segs, _) => r.method == 'GET' && segs.length == 2 && segs[0] == 'collections' && segs[1] == reference
        ? _ok({...detail, 'reference': reference, 'entries': n, 'labels_order': labels, 'collection': entries})
        : null);
  }

  /// All [n] characters of a title (12 main ones), 30 per page
  static void animeCharacters(PerfHub h, int n) {
    final all = [for (int i = 0; i < n; i++) {'main': i < 12, 'character': character(i)}];
    h.intercept((r, segs, _) => r.method == 'GET' && segs.length == 3 && segs[0] == 'anime' && segs[2] == 'characters' ? _ok(page(all, r.url)) : null);
  }

  /// All [n] authors of a title, one to four roles each
  static void animeStaff(PerfHub h, int n) {
    const roles = ['Режисер', 'Сценарист', 'Композитор', 'Аніматор ключових кадрів', 'Дизайнер персонажів', 'Звукорежисер',
        'Продюсер', 'Художник-постановник', 'Оператор', 'Монтажер', 'Розкадровка', 'Режисер епізоду'];
    final all = [
      for (int i = 0; i < n; i++)
        {
          'roles': [
            for (int k = 0; k <= i % 4; k++) {'name_ua': roles[(i + k) % roles.length], 'name_en': 'Role', 'weight': 100 - k, 'slug': 'role-${(i + k) % roles.length}'},
          ],
          'person': person(i),
          'weight': 1000 - i,
        },
    ];
    h.intercept((r, segs, _) => r.method == 'GET' && segs.length == 3 && segs[0] == 'anime' && segs[2] == 'staff' ? _ok(page(all, r.url)) : null);
  }

  /// A voice actor with a long career: [anime] titles and [characters] roles
  static void personPage(PerfHub h, {int anime = 150, int characters = 300}) {
    final works = [
      for (int i = 0; i < anime; i++)
        {
          'anime': PerfData.anime(i),
          'roles': [
            {'name_ua': i % 3 == 0 ? 'Сейю' : 'Режисер озвучення', 'name_en': 'Voice', 'weight': 10, 'slug': 'voice'},
          ],
        },
    ];
    final roles = [for (int i = 0; i < characters; i++) {'character': character(i), 'anime': PerfData.anime(i % anime)}];
    h.intercept((r, segs, _) {
      if (r.method != 'GET' || segs.isEmpty || segs[0] != 'people') return null;
      if (segs.length == 2) return _ok({..._person, 'description_ua': 'Сейю з довгою кар’єрою: сотні ролей у серіалах і фільмах.', 'anime_count': anime, 'characters_count': characters, 'manga_count': 0});
      if (segs.length == 3 && segs[2] == 'anime') return _ok(page(works, r.url));
      if (segs.length == 3 && segs[2] == 'characters') return _ok(page(roles, r.url));
      return null;
    });
  }

  /// A character of a long franchise: [anime] titles and [voices] voice actors (several languages)
  static void characterPage(PerfHub h, {int anime = 60, int voices = 40}) {
    final titles = [for (int i = 0; i < anime; i++) {'main': i % 3 == 0, 'anime': PerfData.anime(i)}];
    const langs = ['ja', 'en', 'de', 'es', 'fr', 'it', 'pt', 'ko', 'pl', 'uk'];
    final cast = [for (int i = 0; i < voices; i++) {'anime': PerfData.anime(i % 12), 'person': person(i), 'language': langs[i % langs.length]}];
    h.intercept((r, segs, _) {
      if (r.method != 'GET' || segs.length != 3 || segs[0] != 'characters') return null;
      if (segs[2] == 'anime') return _ok(page(titles, r.url));
      if (segs[2] == 'voices') return _ok(page(cast, r.url, size: 100));
      return null;
    });
  }

  /// A franchise as long as Gundam's: the sample's titles and [n] more (series, films, specials over 35 years)
  static void franchise(PerfHub h, int n) {
    final sample = sampleMap('related_franchise.json');
    const types = ['tv', 'movie', 'ova', 'special', 'ona', 'tv', 'movie'];
    final more = [
      for (int i = 0; i < n; i++) {...anime(i), 'media_type': types[i % types.length], 'year': 1990 + (i * 35) ~/ n},
    ];
    final relations = [
      ...(sample['relations'] as List),
      for (int i = 0; i < n; i++)
        {
          'related_content_type': 'anime',
          'relation_type': i % 4 == 0 ? 'sequel' : (i % 4 == 1 ? 'side_story' : (i % 4 == 2 ? 'spin_off' : 'summary')),
          'content_type': 'anime',
          'related_slug': 'gen-anime-$i',
          'slug': i == 0 ? perfFrieren : 'gen-anime-${i - 1}',
        },
    ];
    h.intercept((r, segs, _) => r.method == 'GET' && segs.length == 4 && segs[0] == 'related' && segs[3] == 'franchise'
        ? _ok({...sample, 'anime': [...(sample['anime'] as List), ...more], 'relations': relations})
        : null);
  }

  /// The account's lists as on a long-time viewer's: so many titles in each status and in "Улюблене", 30 per
  /// page (the titles come from [catalog], which must hold as many)
  static void lists(PerfHub h, {int watching = 40, int planned = 150, int completed = 600, int onHold = 20, int dropped = 30, int favourites = 80}) {
    final a = h.account;
    var i = 0;
    void add(String status, int count) {
      for (int k = 0; k < count; k++, i++) {
        final slug = 'gen-anime-$i';
        a.mine[slug] = a.watchJson(slug, status: status, episodes: status == 'completed' ? 12 : (i * 3) % 12, score: (i * 7) % 11);
      }
    }

    add('watching', watching);
    add('planned', planned);
    add('completed', completed);
    add('on_hold', onHold);
    add('dropped', dropped);
    for (int k = 0; k < favourites; k++) {
      a.favourites.add('gen-anime-${(k * 7) % i}');
    }
    // The account answers with everything at once: cut it into pages as Hikka does
    h.intercept((r, segs, next) {
      final watch = r.method == 'POST' && segs.length == 3 && segs[0] == 'watch' && segs[2] == 'list';
      final fav = r.method == 'POST' && segs.length == 4 && segs[0] == 'favourite' && segs[3] == 'list';
      if (!watch && !fav) return null;
      final res = next(r);
      if (res == null || res.status != 200) return res;
      final all = ((jsonDecode(res.body) as Map<String, dynamic>)['list'] as List).cast<Map<String, dynamic>>();
      return _ok(page(all, r.url));
    });
  }

  /// [n] notifications: new episodes of different titles in the last days, the first few unread, one pinned
  static EpisodeAlerts alerts(int n) {
    final now = AppClock.now();
    const teams = ['Inari', 'Togarashi', 'Amanogawa', 'FanVoxUA', 'Gwean & Maslinka'];
    var data = <String, dynamic>{
      'items': [
        for (int i = 0; i < n; i++)
          EpisodeAlert(
            id: 'alert-$i',
            slug: 'gen-anime-${i % 60}',
            title: anime(i % 60)['title_ua'] as String,
            image: anime(i % 60)['image'] as String,
            episode: 1 + (i * 5) % 24,
            teamName: teams[i % teams.length],
            kind: i % 4 == 0 ? 'sub' : 'voice',
            at: now.subtract(Duration(minutes: 7 + i * 41)),
            read: i > 5,
            pinned: i == 3,
          ).toJson(),
      ],
    };
    return EpisodeAlerts(load: () => data, save: (d) => data = d, fetch: (since, page) async => (const <Map<String, dynamic>>[], 0));
  }
}
