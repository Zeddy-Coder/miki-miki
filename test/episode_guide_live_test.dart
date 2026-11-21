// A "live" check of where the Ukrainian episode titles and stills come from: TheMovieDB alone vs MoonAnime alone, over
// MoonAnime's most popular TV titles with a Ukrainian translation and its latest updated ones (the first 100 episodes
// of each, aired ones only; MyAnimeList's episodes through Tenrai are the count). Not part of the regular suite: it
// asks the real services and runs only with the keys in the environment —
//   MOON_API_KEY=… [TMDB_KEY=…] [GUIDE_CACHE=<file>] [GUIDE_OUT=<file.json>] flutter test test/episode_guide_live_test.dart
// (without TMDB_KEY only MoonAnime is counted). Prints a table; asserts nothing about the numbers.
@Timeout(Duration(minutes: 30))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:miki_miki/models/hikka_models.dart';
import 'package:miki_miki/services/episode_guide.dart';

final Map<String, String> env = Platform.environment;
final String moonKey = env['MOON_API_KEY'] ?? '';
final String tmdbKey = env['TMDB_KEY'] ?? '';

final HttpClient http = HttpClient()..connectionTimeout = const Duration(seconds: 15);

Future<Object?> moonGet(String path, [Map<String, String>? query]) async {
  final req = await http.getUrl(Uri.https('api.moonanime.art', path, query));
  req.headers.set('X-API-KEY', moonKey);
  req.headers.set(HttpHeaders.acceptHeader, 'application/json');
  final res = await req.close();
  final text = await res.transform(utf8.decoder).join();
  if (res.statusCode == 404) return null;
  if (res.statusCode != 200) throw HttpException('MoonAnime $path: ${res.statusCode}');
  return jsonDecode(text);
}

/// MoonAnime's episode guide shaped as our backend gives it (tools/backend/guide.ts, `episodesOf`)
Future<Map<String, dynamic>?> moonGuide(int mal) async {
  await Future<void>.delayed(const Duration(milliseconds: 300));
  final j = await moonGet('/api/7.0/anime/$mal/schedule');
  final data = j is Map ? j['data'] : null;
  if (data is! Map) return {'mal': mal, 'eps': <String, dynamic>{}};
  final all = [
    for (final s in (data['episode_guide'] as List?) ?? const [])
      for (final e in (s is Map ? s['episodes'] as List? : null) ?? const [])
        if (e is Map) e,
  ];
  final seen = <int, int>{};
  for (final e in all) {
    final n = e['episode'];
    if (n is int) seen[n] = (seen[n] ?? 0) + 1;
  }
  final standIn = RegExp(r'^\s*(серія|серiя|епізод|episode)\s*\d+\s*$', caseSensitive: false);
  final eps = <String, dynamic>{};
  for (final e in all) {
    final n = e['episode'];
    if (n is! int || n < 1 || seen[n] != 1 || e['upcoming'] == true) continue;
    final t = '${e['title'] ?? ''}'.trim();
    final thumb = '${e['thumb_url'] ?? ''}';
    eps['$n'] = {
      if (t.isNotEmpty && !standIn.hasMatch(t)) 't': t,
      if (thumb.startsWith('https://')) 'i': '/api/guideThumb?u=x',
    };
  }
  return {'mal': mal, 'eps': eps};
}

/// Plain GET; Tenrai's answers are kept for the run, so the second pass does not ask it again
final Map<String, (int, String)> tenrai = {};
Future<(int, String)> get(Uri u, {Map<String, String>? headers}) async {
  final k = '$u';
  final kept = tenrai[k];
  if (kept != null) return kept;
  final req = await http.getUrl(u);
  req.headers.set(HttpHeaders.acceptHeader, 'application/json');
  headers?.forEach(req.headers.set);
  final res = await req.close();
  final r = (res.statusCode, await res.transform(utf8.decoder).join());
  if (u.host == 'api.tenrai.org' && res.statusCode == 200) tenrai[k] = r;
  return r;
}

class Title {
  final int mal;
  final String name;
  final HikkaAnime anime;
  final int episodes;
  Title(this.mal, this.name, this.anime, this.episodes);
}

void main() {
  test('звідки українські назви й кадри серій: TheMovieDB чи MoonAnime', () async {
    if (moonKey.isEmpty) {
      markTestSkipped('MOON_API_KEY не задано');
      return;
    }
    // The sample: the 100 most popular TV titles with a Ukrainian translation, then the 50 updated latest
    final titles = <int, Title>{};
    for (final q in [
      {'type': 'TV', 'translated_ua': 'true', 'order_by': 'popularity', 'per_page': '100', 'page': '1'},
      {'type': 'TV', 'translated_ua': 'true', 'per_page': '50', 'page': '1'},
    ]) {
      final j = await moonGet('/api/7.0/anime', q);
      for (final a in (j is Map ? j['data'] as List? : null) ?? const []) {
        if (a is! Map || a['id'] is! int) continue;
        final mal = a['id'] as int;
        final t = a['title'] is Map ? a['title'] as Map : const {};
        final eps = (a['episodes'] as num?)?.toInt() ?? 100;
        titles.putIfAbsent(
          mal,
          () => Title(
            mal,
            '${t['ua'] ?? t['en'] ?? mal}',
            HikkaAnime.fromJson({
              'slug': 'mal-$mal',
              'title_en': t['en'],
              'title_native': t['ja'],
              'title_ua': t['ua'],
              'media_type': 'tv',
              'mal_id': mal,
              'year': a['year'],
            }),
            eps < 1 ? 100 : (eps > 100 ? 100 : eps),
          ),
        );
      }
    }
    final cache = env['GUIDE_CACHE'] ?? '${Directory.systemTemp.path}/guide_live_cache.json';
    EpisodeGuideService service({required bool tmdb, required bool moon}) => EpisodeGuideService(
          get: get,
          cachePath: tmdb ? '$cache.tmdb' : '$cache.moon',
          malId: (k) async => int.tryParse(k.substring(4)),
          anime: (k) async => titles[int.parse(k.substring(4))]?.anime,
          tmdbKey: () => tmdb ? tmdbKey : '',
          moon: moon ? moonGuide : (_) async => null,
          animeSkipNames: (_) async => null,
          hosting: 'https://hosting.test',
        );

    final now = DateTime.now();
    final rows = <Map<String, Object?>>[];
    final viaTmdb = tmdbKey.isEmpty ? null : service(tmdb: true, moon: false);
    final viaMoon = service(tmdb: false, moon: true);
    for (final t in titles.values) {
      final key = 'mal:${t.mal}';
      // (Tenrai allows two requests a second; the guide asks it once a title, the disk copy serves the second pass)
      await Future<void>.delayed(const Duration(milliseconds: 600));
      final a = viaTmdb == null ? null : await viaTmdb.load(key, 1, t.episodes);
      if (viaTmdb != null) await viaTmdb.save();
      final b = await viaMoon.load(key, 1, t.episodes);
      await viaMoon.save();
      final base = a ?? b;
      if (base == null) continue;
      final aired = [
        for (final e in base.episodes.values)
          if (e.en != null || e.aired != null)
            if (e.aired == null || !e.aired!.isAfter(now)) e.number,
      ];
      int count(EpisodeGuide? g, bool Function(GuideEpisode e) f) => g == null ? 0 : aired.where((n) => g[n] != null && f(g[n]!)).length;
      rows.add({
        'mal': t.mal,
        'name': t.name,
        'aired': aired.length,
        'tmdb_uk': viaTmdb == null ? null : count(a, (e) => e.uk != null),
        'moon_uk': count(b, (e) => e.uk != null),
        'both_uk': viaTmdb == null ? null : aired.where((n) => a?[n]?.uk != null || b?[n]?.uk != null).length,
        'tmdb_still': viaTmdb == null ? null : count(a, (e) => e.still != null),
        'moon_still': count(b, (e) => e.still != null),
      });
    }
    final out = env['GUIDE_OUT'];
    if (out != null) File(out).writeAsStringSync(const JsonEncoder.withIndent(' ').convert(rows));
    int sum(String k) => rows.fold(0, (s, r) => s + ((r[k] as int?) ?? 0));
    final total = sum('aired');
    String pct(String k) => total == 0 ? '—' : '${sum(k)} (${(100 * sum(k) / total).toStringAsFixed(1)}%)';
    // ignore: avoid_print
    print('Тайтлів ${rows.length}, серій $total; українські назви — TMDB ${pct('tmdb_uk')}, MoonAnime ${pct('moon_uk')}, '
        'разом ${pct('both_uk')}; кадри — TMDB ${pct('tmdb_still')}, MoonAnime ${pct('moon_still')}');
    expect(rows, isNotEmpty);
  });
}
