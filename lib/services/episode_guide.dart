/// Titles, air dates and stills of a title's episodes for the player's episode list, by MyAnimeList's numbers.
///
/// Ukrainian titles and stills come from TheMovieDB (`language=uk-UA`) and, after it, from MoonAnime's episode guide
/// through our backend (`BackendClient.guide`: MoonAnime's key stays on the server, its 1 MB stills come back 320 px
/// wide through Hosting's CDN; also the episodes' lengths and descriptions). TheMovieDB's show is found by the title's
/// names (as the banners' search does) and its episodes are matched to MyAnimeList's by air date, however TheMovieDB
/// splits the seasons; stand-ins («Епізод 5», «Серія 17») and titles without a Cyrillic letter (or with Russian-only
/// letters) are not Ukrainian titles. English and Japanese titles, air dates, filler and recap marks come from
/// MyAnimeList through Tenrai (`/anime/{id}/episodes`, a hundred a page); when Tenrai cannot be reached, the names from
/// Anime Skip. Remembered on disk (`<appBasePath>/episode_guide.json`); an old answer still serves offline.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import '../models/hikka_models.dart';
import 'app_log.dart';
import 'backend_client.dart';
import 'banner_art.dart' show TmdbBackdrops;
import 'hikka_api.dart';
import 'skips/anime_skip.dart';
import 'storage_service.dart';

// ── Reading the answers ─────────────────────────────────────────────────────

/// «2026-04-08T00:00:00+00:00» or «2026-04-08» → that day (UTC midnight); null for anything else
DateTime? dayOf(Object? v) {
  if (v is! String || v.length < 10) return null;
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(v);
  if (m == null) return null;
  return DateTime.utc(int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!));
}

String _day(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String? _text(Object? v) {
  if (v is! String) return null;
  final t = v.trim();
  return t.isEmpty ? null : t;
}

/// «Episode 5», «Епізод 5», «Серія 5»: a stand-in, not a title
final RegExp _standIn = RegExp(r'^\s*(епізод|серія|серiя|episode|эпизод|серия)\s*(№\s*)?\d+\s*\.?\s*$', caseSensitive: false);
final RegExp _cyrillic = RegExp(r'[А-Яа-яІіЇїЄєҐґ]');
final RegExp _russianOnly = RegExp(r'[ЫыЭэЪъЁё]');

bool isStandInTitle(String t) => _standIn.hasMatch(t);

/// A Ukrainian episode title: a Cyrillic letter in it, no Russian-only letters, not a stand-in such as «Епізод 5»
bool isUkrainianTitle(String? t) => t != null && t.trim().isNotEmpty && _cyrillic.hasMatch(t) && !_russianOnly.hasMatch(t) && !isStandInTitle(t);

/// One of MyAnimeList's episodes (through Tenrai)
class MalEpisode {
  final int number;

  /// English title
  final String? title;
  final String? japanese;
  final DateTime? aired;
  final bool filler;
  final bool recap;

  const MalEpisode(this.number, {this.title, this.japanese, this.aired, this.filler = false, this.recap = false});

  Map<String, Object> toJson() => {
        'n': number,
        if (title != null) 't': title!,
        if (japanese != null) 'j': japanese!,
        if (aired != null) 'a': _day(aired!),
        if (filler) 'f': true,
        if (recap) 'r': true,
      };

  static MalEpisode? fromJson(Object? j) {
    if (j is! Map || j['n'] is! num) return null;
    return MalEpisode((j['n'] as num).toInt(), title: _text(j['t']), japanese: _text(j['j']), aired: dayOf(j['a']), filler: j['f'] == true, recap: j['r'] == true);
  }
}

/// MyAnimeList's episodes in Tenrai's answer (Jikan's form: `data: [{mal_id, title, title_japanese, aired, filler,
/// recap}]`) and whether more pages follow
(List<MalEpisode>, bool) malEpisodesOf(Object? json) {
  final data = json is Map ? json['data'] : null;
  final paging = json is Map ? json['pagination'] : null;
  final more = paging is Map && paging['has_next_page'] == true;
  final out = <MalEpisode>[];
  for (final e in data is List ? data : const []) {
    if (e is! Map) continue;
    final n = (e['mal_id'] as num?)?.toInt();
    if (n == null || n < 1) continue;
    final title = _text(e['title']);
    out.add(MalEpisode(
      n,
      title: title == null || isStandInTitle(title) ? null : title,
      japanese: _text(e['title_japanese']),
      aired: dayOf(e['aired']),
      filler: e['filler'] == true,
      recap: e['recap'] == true,
    ));
  }
  return (out, more);
}

/// One of TheMovieDB's episodes of a season
class TmdbEpisode {
  final int season;
  final int number;

  /// The Ukrainian title (null: TheMovieDB has none)
  final String? uk;

  /// The still's path («/abc.jpg»)
  final String? still;
  final DateTime? aired;

  /// Minutes
  final int? runtime;

  const TmdbEpisode(this.season, this.number, {this.uk, this.still, this.aired, this.runtime});

  Map<String, Object> toJson() => {
        's': season,
        'n': number,
        if (uk != null) 'u': uk!,
        if (still != null) 'i': still!,
        if (aired != null) 'a': _day(aired!),
        if (runtime != null) 'r': runtime!,
      };

  static TmdbEpisode? fromJson(Object? j) {
    if (j is! Map || j['s'] is! num || j['n'] is! num) return null;
    return TmdbEpisode((j['s'] as num).toInt(), (j['n'] as num).toInt(), uk: _text(j['u']), still: _text(j['i']), aired: dayOf(j['a']), runtime: (j['r'] as num?)?.toInt());
  }
}

/// The episodes of a season in TheMovieDB's answer (`/tv/{id}/season/{n}?language=uk-UA`), the title only where it
/// is a Ukrainian one
List<TmdbEpisode> tmdbEpisodesOf(Object? json) {
  final eps = json is Map ? json['episodes'] : null;
  final out = <TmdbEpisode>[];
  for (final e in eps is List ? eps : const []) {
    if (e is! Map) continue;
    final s = (e['season_number'] as num?)?.toInt() ?? (json is Map ? (json['season_number'] as num?)?.toInt() : null);
    final n = (e['episode_number'] as num?)?.toInt();
    if (s == null || n == null) continue;
    final name = _text(e['name']);
    final still = _text(e['still_path']);
    final runtime = (e['runtime'] as num?)?.toInt();
    out.add(TmdbEpisode(
      s,
      n,
      uk: isUkrainianTitle(name) ? name : null,
      still: still != null && still.startsWith('/') ? still : null,
      aired: dayOf(e['air_date']),
      runtime: runtime != null && runtime > 0 ? runtime : null,
    ));
  }
  return out;
}

/// The likely shows in TheMovieDB's search answer, in its order: Japanese ones (or, when none is, animated ones); three
/// at most
List<int> tmdbShowsOf(Object? json) {
  final results = json is Map ? json['results'] : null;
  if (results is! List) return const [];
  bool japanese(Map r) => r['original_language'] == 'ja' || (r['origin_country'] is List && (r['origin_country'] as List).contains('JP'));
  bool animated(Map r) => r['genre_ids'] is List && (r['genre_ids'] as List).contains(16);
  final maps = [for (final r in results) if (r is Map && r['id'] is num) r];
  var picked = [for (final r in maps) if (japanese(r)) r];
  if (picked.isEmpty) picked = [for (final r in maps) if (animated(r)) r];
  return [for (final r in picked.take(3)) (r['id'] as num).toInt()];
}

/// A show's seasons in TheMovieDB's answer (`/tv/{id}`): number and first air date; the specials (season 0) and
/// seasons without a date left out
List<(int, DateTime)> tmdbSeasonsOf(Object? json) {
  final seasons = json is Map ? json['seasons'] : null;
  final out = <(int, DateTime)>[];
  for (final s in seasons is List ? seasons : const []) {
    if (s is! Map) continue;
    final n = (s['season_number'] as num?)?.toInt();
    final d = dayOf(s['air_date']);
    if (n == null || n < 1 || d == null) continue;
    out.add((n, d));
  }
  out.sort((a, b) => a.$2.compareTo(b.$2));
  return out;
}

/// The seasons that may hold episodes aired between [first] and [last] (with a few days' slack): a season runs until
/// the next one begins
List<int> seasonsBetween(List<(int, DateTime)> seasons, DateTime first, DateTime last) {
  final from = first.subtract(const Duration(days: 3));
  final to = last.add(const Duration(days: 3));
  final out = <int>[];
  for (var i = 0; i < seasons.length; i++) {
    final start = seasons[i].$2;
    final end = i + 1 < seasons.length ? seasons[i + 1].$2 : null;
    if (start.isAfter(to)) continue;
    if (end != null && !end.isAfter(from)) continue;
    out.add(seasons[i].$1);
  }
  return out;
}

/// MyAnimeList's episodes matched to TheMovieDB's by air date (a day apart at most, for time zones), in order: a day
/// of several episodes pairs them one by one, an episode one side lacks (a recap TheMovieDB keeps among the
/// specials) pairs with nothing
Map<int, TmdbEpisode> matchByDate(List<MalEpisode> mal, List<TmdbEpisode> tmdb) {
  final pool = [for (final t in tmdb) if (t.aired != null) t]
    ..sort((a, b) {
      final c = a.aired!.compareTo(b.aired!);
      return c != 0 ? c : (a.season * 10000 + a.number).compareTo(b.season * 10000 + b.number);
    });
  final dated = [for (final m in mal) if (m.aired != null) m]..sort((a, b) => a.number.compareTo(b.number));
  final out = <int, TmdbEpisode>{};
  var next = 0;
  for (final m in dated) {
    for (var i = next; i < pool.length; i++) {
      final days = pool[i].aired!.difference(m.aired!).inDays;
      if (days < -1) continue;
      if (days > 1) break;
      out[m.number] = pool[i];
      next = i + 1;
      break;
    }
  }
  return out;
}

/// One of MoonAnime's episodes as our backend gives it (`guide`: `{eps: {"14": {t, d, a, i, f, r}}}`)
class MoonEpisode {
  final int number;

  /// The Ukrainian title (null: a stand-in or none)
  final String? uk;
  final int? seconds;

  /// The episode's description
  final String? about;

  /// The small still's path on our Hosting (`/api/guideThumb?…`)
  final String? still;
  final bool filler;
  final bool recap;

  const MoonEpisode(this.number, {this.uk, this.seconds, this.about, this.still, this.filler = false, this.recap = false});
}

/// MoonAnime's episodes in our backend's answer, by number
Map<int, MoonEpisode> moonEpisodesOf(Object? json) {
  final eps = json is Map ? json['eps'] : null;
  final out = <int, MoonEpisode>{};
  if (eps is! Map) return out;
  eps.forEach((k, v) {
    final n = int.tryParse('$k');
    if (n == null || n < 1 || v is! Map) return;
    final t = _text(v['t']);
    final still = _text(v['i']);
    final seconds = (v['d'] as num?)?.toInt();
    out[n] = MoonEpisode(
      n,
      uk: isUkrainianTitle(t) ? t : null,
      seconds: seconds != null && seconds > 0 ? seconds : null,
      about: _text(v['a']),
      still: still != null && still.startsWith('/api/') ? still : null,
      filler: v['f'] == 1 || v['f'] == true,
      recap: v['r'] == 1 || v['r'] == true,
    );
  });
  return out;
}

// ── The guide ───────────────────────────────────────────────────────────────

/// One episode as the list shows it
class GuideEpisode {
  /// MyAnimeList's number
  final int number;

  /// The Ukrainian title: TheMovieDB's, else MoonAnime's
  final String? uk;

  /// MyAnimeList's English title (or Anime Skip's name)
  final String? en;
  final String? ja;
  final DateTime? aired;

  /// The still's address at the list's size: TheMovieDB's, else MoonAnime's
  final String? still;

  /// Minutes (TheMovieDB)
  final int? runtime;

  /// The length to the second (MoonAnime)
  final int? seconds;

  /// MoonAnime's description of the episode
  final String? about;
  final bool filler;
  final bool recap;

  const GuideEpisode(
    this.number, {
    this.uk,
    this.en,
    this.ja,
    this.aired,
    this.still,
    this.runtime,
    this.seconds,
    this.about,
    this.filler = false,
    this.recap = false,
  });

  String? get stillUrl => still;
}

/// The episodes of a title the guide knows, by MyAnimeList's number
class EpisodeGuide {
  final int malId;
  final Map<int, GuideEpisode> episodes;

  const EpisodeGuide(this.malId, this.episodes);

  GuideEpisode? operator [](int? number) => number == null ? null : episodes[number];
}

/// GET → (status, body); tests replace it
typedef GuideGet = Future<(int, String)> Function(Uri url, {Map<String, String>? headers});

class EpisodeGuideService {
  static EpisodeGuideService instance = EpisodeGuideService();

  static const String tmdbApi = 'https://api.themoviedb.org/3';
  static const String stills = 'https://image.tmdb.org/t/p/w300';

  /// MyAnimeList's episodes in one of Tenrai's pages
  static const int pageSize = 100;

  final GuideGet _get;
  final String? _cachePath;
  final Future<int?> Function(String animeKey) _malId;
  final Future<HikkaAnime?> Function(String animeKey) _anime;
  final String Function() _tmdbKey;
  final Future<Map<int, String>?> Function(int malId) _animeSkipNames;
  final Future<Map<String, dynamic>?> Function(int malId) _moon;
  final String _hosting;
  final DateTime Function() _now;

  EpisodeGuideService({
    GuideGet? get,
    String? cachePath,
    bool persist = true,
    Future<int?> Function(String animeKey)? malId,
    Future<HikkaAnime?> Function(String animeKey)? anime,
    String Function()? tmdbKey,
    Future<Map<int, String>?> Function(int malId)? animeSkipNames,
    Future<Map<String, dynamic>?> Function(int malId)? moon,
    String? hosting,
    DateTime Function()? now,
  })  : _get = get ?? _http,
        _moon = moon ?? ((mal) => BackendClient.instance.guide(mal)),
        _hosting = hosting ?? BackendClient.hostingOrigin,
        _cachePath = cachePath ?? (persist ? '${StorageService.appBasePath}${Platform.pathSeparator}episode_guide.json' : null),
        _malId = malId ?? ((k) => HikkaApi.instance.malIdOf(k)),
        _anime = anime ?? _hikkaAnime,
        _tmdbKey = tmdbKey ?? BackendClient.effectiveTmdbKey,
        _animeSkipNames = animeSkipNames ?? ((mal) => AnimeSkip.instance.names(mal)),
        _now = now ?? DateTime.now;

  static Future<HikkaAnime?> _hikkaAnime(String animeKey) async =>
      animeKey.startsWith('hikka:') ? HikkaApi.instance.anime(animeKey.substring(6)) : null;

  /// What was put together for a range lately: the list shows it at once when the panel opens again
  final Map<String, (DateTime, EpisodeGuide)> _made = {};
  final Map<String, Future<EpisodeGuide?>> _making = {};
  static const Duration _madeFor = Duration(minutes: 30);

  /// The guide for episodes [from]–[to] (MyAnimeList's numbers) of [animeKey] put together lately, if any
  EpisodeGuide? peek(String animeKey, int from, int to) {
    final hit = _made['$animeKey#$from-$to'];
    return hit != null && _now().difference(hit.$1) < _madeFor ? hit.$2 : null;
  }

  /// Titles, dates and stills of episodes [from]–[to] (MyAnimeList's numbers) of [animeKey]; null: the title has no
  /// MyAnimeList id or nothing could be learned
  Future<EpisodeGuide?> load(String animeKey, int from, int to) {
    final known = peek(animeKey, from, to);
    if (known != null) return Future.value(known);
    final key = '$animeKey#$from-$to';
    return _making[key] ??= _build(animeKey, from, to).then((g) {
      if (g != null) _made[key] = (_now(), g);
      return g;
    }).catchError((Object e) {
      AppLog.w('назви', 'серії $from–$to: $e');
      return null;
    }).whenComplete(() {
      _making.remove(key); // (not returned: whenComplete would wait for this very future)
    });
  }

  Future<EpisodeGuide?> _build(String animeKey, int from, int to) async {
    if (from < 1 || to < from) return null;
    final mal = await _malId(animeKey).catchError((_) => null);
    if (mal == null) return null;
    // MoonAnime's guide is asked for meanwhile: it needs nothing of the others
    final moonF = _moonOf(mal);
    // MyAnimeList's episodes from the pages that hold [from]–[to]
    final malEps = <int, MalEpisode>{};
    var malDown = false;
    for (var p = (from - 1) ~/ pageSize + 1; p <= (to - 1) ~/ pageSize + 1; p++) {
      final page = await _malPage(mal, p);
      if (page == null) {
        malDown = true;
        continue;
      }
      for (final e in page) {
        malEps[e.number] = e;
      }
    }
    final wanted = [for (final e in malEps.values) if (e.number >= from && e.number <= to) e];
    final (tmdb, tmdbWhy) = await _tmdbFor(animeKey, mal, wanted);
    final moon = await moonF;
    // Anime Skip's names only when MyAnimeList's cannot be had
    Map<int, String>? skipNames;
    if (malDown || wanted.isEmpty) skipNames = await _animeSkipNames(mal).catchError((_) => null);
    final out = <int, GuideEpisode>{};
    for (var n = from; n <= to; n++) {
      final m = malEps[n], t = tmdb[n], s = skipNames?[n], o = moon?[n];
      if (m == null && t == null && s == null && o == null) continue;
      out[n] = GuideEpisode(
        n,
        uk: t?.uk ?? o?.uk,
        en: m?.title ?? s,
        ja: m?.japanese,
        aired: m?.aired ?? t?.aired,
        still: t?.still != null ? '$stills${t!.still}' : (o?.still != null ? '$_hosting${o!.still}' : null),
        runtime: t?.runtime,
        seconds: o?.seconds,
        about: o?.about,
        filler: m?.filler ?? o?.filler ?? false,
        recap: m?.recap ?? o?.recap ?? false,
      );
    }
    final uk = out.values.where((e) => e.uk != null).length;
    final en = out.values.where((e) => e.uk == null && e.en != null).length;
    final pics = out.values.where((e) => e.still != null).length;
    final moonUk = [for (var n = from; n <= to; n++) if (tmdb[n]?.uk == null && moon?[n]?.uk != null) n].length;
    final moonPics = [for (var n = from; n <= to; n++) if (tmdb[n]?.still == null && moon?[n]?.still != null) n].length;
    AppLog.i('назви', [
      'MAL $mal, серії $from–$to: українською $uk, англійською $en, кадрів $pics',
      tmdbWhy,
      moon == null ? 'MoonAnime недоступний' : 'MoonAnime: назв $moonUk, кадрів $moonPics',
      if (malDown) 'Tenrai недоступний',
      if (skipNames != null) 'Anime Skip ${skipNames.length}',
    ].join('; '));
    return EpisodeGuide(mal, out);
  }

  // ── MoonAnime through our backend ───────────────────────────────────────

  /// MoonAnime's episodes of [malId] (null: the backend cannot be reached or has no `guide` yet, and nothing is
  /// remembered); the backend keeps them a day itself, so does the device
  Future<Map<int, MoonEpisode>?> _moonOf(int malId) async {
    final raw = await _remembered('moon:$malId', (_) => const Duration(days: 1), () async {
      final json = await _moon(malId).catchError((_) => null);
      final eps = json?['eps'];
      return eps is Map ? {'eps': eps} : null;
    });
    return raw == null ? null : moonEpisodesOf(raw);
  }

  // ── MyAnimeList through Tenrai ──────────────────────────────────────────

  static const Duration _malTtl = Duration(days: 14);
  static const Duration _ongoingTtl = Duration(days: 1);

  /// Page [page] of MyAnimeList's episodes of [malId] (null: Tenrai cannot be reached and nothing is remembered)
  Future<List<MalEpisode>?> _malPage(int malId, int page) async {
    final raw = await _remembered('mal:$malId:$page', _malPageTtl, () async {
      final json = await _json(Uri.https('api.tenrai.org', '/v1/anime/$malId/episodes', {if (page > 1) 'page': '$page'}), 'Tenrai');
      if (json == null) return null;
      final (eps, more) = malEpisodesOf(json);
      return {'e': [for (final e in eps) e.toJson()], if (more) 'm': true};
    });
    if (raw is! Map) return null;
    return [for (final j in (raw['e'] as List?) ?? const []) if (MalEpisode.fromJson(j) case final e?) e];
  }

  /// The last page of a title still airing (or not aired yet) is asked again daily: new episodes, new titles
  Duration _malPageTtl(Object v) {
    if (v is! Map || v['m'] == true) return _malTtl;
    final eps = [for (final j in (v['e'] as List?) ?? const []) if (MalEpisode.fromJson(j) case final e?) e];
    if (eps.isEmpty) return _ongoingTtl;
    final latest = eps.map((e) => e.aired).whereType<DateTime>().fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);
    return latest == null || _now().difference(latest) < const Duration(days: 30) ? _ongoingTtl : _malTtl;
  }

  // ── TheMovieDB ──────────────────────────────────────────────────────────

  static const Duration _showTtl = Duration(days: 60);
  static const Duration _noShowTtl = Duration(days: 3);
  static const Duration _tvTtl = Duration(days: 3);

  /// TheMovieDB's episodes matched to [wanted] by air date, and what happened (for the log)
  Future<(Map<int, TmdbEpisode>, String)> _tmdbFor(String animeKey, int malId, List<MalEpisode> wanted) async {
    final key = _tmdbKey().trim();
    if (key.isEmpty) return (const <int, TmdbEpisode>{}, 'TMDB: ключа немає');
    final dated = [for (final e in wanted) if (e.aired != null) e];
    if (dated.isEmpty) return (const <int, TmdbEpisode>{}, 'TMDB: у MAL немає дат серій');
    final show = await _remembered('tmdbshow:$malId', (v) => v == 0 ? _noShowTtl : _showTtl, () => _findShow(animeKey, dated, key));
    if (show is! int) return (const <int, TmdbEpisode>{}, 'TMDB недоступний');
    if (show == 0) return (const <int, TmdbEpisode>{}, 'TMDB: шоу не знайдено');
    final matched = await _matched(show, dated, key);
    if (matched == null) return (const <int, TmdbEpisode>{}, 'TMDB недоступний (шоу $show)');
    final seasons = {for (final t in matched.values) t.season}.toList()..sort();
    return (matched, matched.isEmpty ? 'TMDB $show: дати серій не збіглися з MAL' : 'TMDB $show, сезон ${seasons.join(', ')}');
  }

  /// TheMovieDB's show of the title: searched by its names; the first likely show whose episodes match at least half
  /// of [dated] by date (0: none; null: TheMovieDB or Hikka could not be reached)
  Future<Object?> _findShow(String animeKey, List<MalEpisode> dated, String key) async {
    final a = await _anime(animeKey).catchError((_) => null);
    if (a == null) return null;
    if (a.mediaType == 'movie') return 0;
    final need = math.max(1, (dated.length / 2).ceil());
    final tried = <int>{};
    var reached = false;
    for (final q in TmdbBackdrops.searchQueries(a).take(4)) {
      final json = await _tmdb('/search/tv', {'query': q, 'include_adult': 'false'}, key);
      if (json == null) continue;
      reached = true;
      for (final id in tmdbShowsOf(json)) {
        if (!tried.add(id)) continue;
        final m = await _matched(id, dated, key);
        if (m != null && m.length >= need) return id;
      }
    }
    return reached ? 0 : null;
  }

  /// [dated] matched to the episodes of TheMovieDB's show [id] by date (null: it could not be reached)
  Future<Map<int, TmdbEpisode>?> _matched(int id, List<MalEpisode> dated, String key) async {
    final raw = await _remembered('tmdbtv:$id', (_) => _tvTtl, () async {
      final json = await _tmdb('/tv/$id', const {}, key);
      return json == null ? null : [for (final (n, d) in tmdbSeasonsOf(json)) {'n': n, 'a': _day(d)}];
    });
    if (raw is! List) return null;
    final seasons = [
      for (final s in raw)
        if (s is Map && s['n'] is num && dayOf(s['a']) != null) ((s['n'] as num).toInt(), dayOf(s['a'])!),
    ];
    final days = [for (final e in dated) e.aired!];
    final first = days.reduce((a, b) => a.isBefore(b) ? a : b);
    final last = days.reduce((a, b) => a.isAfter(b) ? a : b);
    final eps = <TmdbEpisode>[];
    for (final s in seasonsBetween(seasons, first, last)) {
      final season = await _remembered('tmdbs:$id:$s', _seasonTtl, () async {
        final json = await _tmdb('/tv/$id/season/$s', const {'language': 'uk-UA'}, key);
        return json == null ? null : [for (final e in tmdbEpisodesOf(json)) e.toJson()];
      });
      if (season is! List) return null;
      eps.addAll([for (final j in season) if (TmdbEpisode.fromJson(j) case final e?) e]);
    }
    return matchByDate(dated, eps);
  }

  /// A season still airing is asked again in two days, one with titles yet to be translated in a week, else a month
  Duration _seasonTtl(Object v) {
    final eps = [for (final j in v is List ? v : const []) if (TmdbEpisode.fromJson(j) case final e?) e];
    final now = _now();
    if (eps.isEmpty || eps.any((e) => e.aired == null || now.difference(e.aired!) < const Duration(days: 30))) return const Duration(days: 2);
    if (eps.any((e) => e.uk == null || e.still == null)) return const Duration(days: 7);
    return const Duration(days: 30);
  }

  /// A request to TheMovieDB: a v4 key («read access token», eyJ…) goes as a header, a v3 one as a parameter
  Future<Object?> _tmdb(String path, Map<String, String> params, String key) {
    final bearer = key.startsWith('eyJ');
    final url = Uri.parse('$tmdbApi$path').replace(queryParameters: {if (!bearer) 'api_key': key, ...params});
    return _json(url, 'TMDB', headers: bearer ? {'Authorization': 'Bearer $key'} : null);
  }

  // ── The network and the disk copy ───────────────────────────────────────

  Future<Object?> _json(Uri url, String name, {Map<String, String>? headers}) async {
    try {
      final (status, text) = await _get(url, headers: headers);
      if (status == 404) return const <String, Object>{};
      if (status != 200) {
        // (the address is not logged: TheMovieDB's key may be in it)
        if (status == 401) {
          AppLog.w('назви', '$name: відповідь 401 — ключ не прийнято');
        } else {
          AppLog.d('назви', '$name: відповідь $status');
        }
        return null;
      }
      return jsonDecode(text);
    } catch (e) {
      AppLog.d('назви', '$name недоступний: ${e.runtimeType}');
      return null;
    }
  }

  static HttpClient? _client;

  static Future<(int, String)> _http(Uri url, {Map<String, String>? headers}) async {
    final client = _client ??= HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      ..idleTimeout = const Duration(seconds: 15);
    final req = await client.getUrl(url).timeout(const Duration(seconds: 10));
    req.headers.set(HttpHeaders.acceptHeader, 'application/json');
    req.headers.set(HttpHeaders.userAgentHeader, 'MikiMiki (github.com/Zeddy-Coder/miki-miki)');
    headers?.forEach(req.headers.set);
    final res = await req.close().timeout(const Duration(seconds: 12));
    final text = await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 12));
    return (res.statusCode, text);
  }

  final Map<String, (DateTime, Object)> _cache = {};
  final Map<String, Future<Object?>> _inflight = {};
  Future<void>? _loading;
  Timer? _saveTimer;
  static const int _maxEntries = 1500;

  /// What is remembered under [key] while fresh ([ttl] by the value); else asked for, and the old one when that fails
  Future<Object?> _remembered(String key, Duration Function(Object value) ttl, Future<Object?> Function() fetch) async {
    await _load();
    final hit = _cache[key];
    if (hit != null && _now().difference(hit.$1) < ttl(hit.$2)) return hit.$2;
    return _inflight[key] ??= fetch().then((fresh) {
      if (fresh == null) return hit?.$2;
      _cache[key] = (_now(), fresh);
      _saveSoon();
      return fresh;
    }).catchError((Object e) {
      AppLog.d('назви', '$key: $e');
      return hit?.$2;
    }).whenComplete(() {
      _inflight.remove(key); // (not returned: whenComplete would wait for this very future)
    });
  }

  Future<void> _load() => _loading ??= () async {
        final path = _cachePath;
        if (path == null) return;
        try {
          final f = File(path);
          if (!await f.exists()) return;
          final j = jsonDecode(await f.readAsString());
          if (j is! Map) return;
          j.forEach((k, v) {
            if (v is Map && v['t'] is num && v['v'] != null) _cache['$k'] = (DateTime.fromMillisecondsSinceEpoch((v['t'] as num).toInt()), v['v'] as Object);
          });
        } catch (e) {
          AppLog.w('назви', 'кеш не прочитано: $e');
        }
      }();

  void _saveSoon() {
    if (_cachePath == null) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2), () => unawaited(save()));
  }

  Future<void> save() async {
    _saveTimer?.cancel();
    final path = _cachePath;
    if (path == null) return;
    if (_cache.length > _maxEntries) {
      final keys = _cache.keys.toList()..sort((a, b) => _cache[a]!.$1.compareTo(_cache[b]!.$1));
      for (final k in keys.take(_cache.length - _maxEntries)) {
        _cache.remove(k);
      }
    }
    try {
      final f = File(path);
      await f.parent.create(recursive: true);
      final tmp = File('$path.tmp');
      await tmp.writeAsString(jsonEncode({for (final e in _cache.entries) e.key: {'t': e.value.$1.millisecondsSinceEpoch, 'v': e.value.$2}}));
      await tmp.rename(path);
    } catch (e) {
      AppLog.w('назви', 'кеш не збережено: $e');
    }
  }
}
