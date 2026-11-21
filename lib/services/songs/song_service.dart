/// The songs of the episode playing: its opening and ending, who sings them, a cover, where to listen.
///
/// By the MyAnimeList id from Hikka, from three sources (`combineSongs`): AnimeThemes' GraphQL API (which OP / ED plays
/// in which episodes, by every version; who sings them; links), MyAnimeList's themes through Tenrai (the same episodes
/// a little rougher, full artist names, original titles «Yuusha (勇者)» the stores find covers by) — the first that has
/// the title is the base, MyAnimeList fills in what AnimeThemes lacks — and Hikka's own list of the title's songs
/// (Spotify links; alone, when neither has the title, it shows only a title's single opening / ending: Hikka does not
/// say which plays when). The cover: from the song's own Apple Music or Spotify page when linked, else Apple Music's
/// search (with its link), else Deezer's. Remembered on disk (`<appBasePath>/theme_songs.json`): a title's songs for
/// two weeks, a song's cover for two months; an old answer still serves when the services cannot be reached.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../app_log.dart';
import '../hikka_api.dart';
import '../storage_service.dart';
import 'theme_songs.dart';

/// The songs found for one episode
class EpisodeSongs {
  /// `animeKey#epKey`
  final String key;
  final ThemeSong? op;
  final ThemeSong? ed;

  /// Covers (and an Apple Music link) as they are found
  final Map<SongKind, SongArt> art;

  const EpisodeSongs({required this.key, this.op, this.ed, this.art = const {}});

  ThemeSong? of(SongKind kind) => kind == SongKind.op ? op : ed;

  EpisodeSongs copyWith({ThemeSong? op, ThemeSong? ed, Map<SongKind, SongArt>? art}) =>
      EpisodeSongs(key: key, op: op ?? this.op, ed: ed ?? this.ed, art: art ?? this.art);
}

/// One way to listen: the app, the address, and whether it is the song itself (or a search)
class SongLink {
  final MusicApp app;
  final String url;
  final bool direct;
  const SongLink(this.app, this.url, {required this.direct});
}

/// GET (or POST [body] as JSON) → (status, body); tests replace it
typedef SongGet = Future<(int, String)> Function(Uri url, {String? body});

class SongService {
  static SongService instance = SongService();

  final SongGet _get;
  final String? _cachePath;
  final Future<int?> Function(String animeKey) _malId;
  final Future<List<ThemeSong>?> Function(String animeKey) _ost;
  final DateTime Function() _now;
  final bool Function() _enabled;

  static const Duration songsTtl = Duration(days: 14);
  static const Duration emptyTtl = Duration(days: 2);
  static const Duration artTtl = Duration(days: 60);
  static const int _maxEntries = 1200;

  SongService({
    SongGet? get,
    String? cachePath,
    bool persist = true,
    Future<int?> Function(String animeKey)? malId,
    Future<List<ThemeSong>?> Function(String animeKey)? ost,
    DateTime Function()? now,
    bool Function()? enabled,
  })  : _get = get ?? _http,
        _cachePath = cachePath ?? (persist ? '${StorageService.appBasePath}${Platform.pathSeparator}theme_songs.json' : null),
        _malId = malId ?? HikkaApi.instance.malIdOf,
        _ost = ost ?? _hikkaOst,
        _now = now ?? DateTime.now,
        _enabled = enabled ?? StorageService.getShowThemeSongs;

  /// Hikka's songs of a title opened from Hikka (its page is cached by HikkaApi, on disk too)
  static Future<List<ThemeSong>?> _hikkaOst(String animeKey) async {
    if (!animeKey.startsWith('hikka:')) return null;
    return songsOfHikka((await HikkaApi.instance.anime(animeKey.substring(6))).ost);
  }

  /// The songs of the episode playing now (null: none known, or not yet)
  final ValueNotifier<EpisodeSongs?> current = ValueNotifier<EpisodeSongs?>(null);

  String? _key;

  // ── The player's episode ─────────────────────────────────────────────────

  /// The player opened episode [epKey] of [animeKey]; [number] — its number as MyAnimeList counts (null: unknown)
  Future<void> attach({required String animeKey, required String epKey, int? number}) async {
    final key = '$animeKey#$epKey';
    if (_key == key && current.value != null) return;
    _key = key;
    current.value = null;
    if (!_enabled()) return;
    try {
      final mal = await _malId(animeKey).catchError((_) => null);
      if (_key != key) return;
      final (themes, malSongs, hikka) = await (
        mal == null ? Future<List<ThemeSong>?>.value() : songsOf(mal),
        mal == null ? Future<List<ThemeSong>?>.value() : malSongsOf(mal),
        _ost(animeKey).catchError((_) => null),
      ).wait;
      if (_key != key) return;
      final songs = combineSongs(animeThemes: themes, mal: malSongs, hikka: hikka);
      final op = pickSong(songs, SongKind.op, number);
      final ed = pickSong(songs, SongKind.ed, number);
      final at = number == null ? '$epKey, номер невідомий' : 'серія $number';
      final from = _sources(mal, themes, malSongs, hikka);
      if (op == null && ed == null) {
        AppLog.i('пісні', 'не знайдено ($at): $from');
        return;
      }
      current.value = EpisodeSongs(key: key, op: op, ed: ed);
      AppLog.i('пісні', '${[if (op != null) '$op', if (ed != null) '$ed'].join(' · ')} ($at; $from)');
      // The covers come after: the card shows the song at once, the picture when it is there
      for (final kind in SongKind.values) {
        final s = kind == SongKind.op ? op : ed;
        if (s == null) continue;
        final art = await artOf(s);
        final cur = current.value;
        if (_key != key || cur == null) return;
        if (art != null) current.value = cur.copyWith(art: {...cur.art, kind: art});
      }
    } catch (e) {
      AppLog.w('пісні', 'не знайдено: $e');
    }
  }

  /// Where the songs came from, for the log: «MAL 918: AnimeThemes 24, Tenrai 24, Hikka 24»
  static String _sources(int? mal, List<ThemeSong>? themes, List<ThemeSong>? malSongs, List<ThemeSong>? hikka) {
    String of(String name, List<ThemeSong>? list) => '$name ${switch (list) { null => 'недоступний', [] => 'не знає', _ => '${list.length}' }}';
    return '${mal == null ? 'без MAL id' : 'MAL $mal: ${of('AnimeThemes', themes)}, ${of('Tenrai', malSongs)}'}, ${hikka == null ? 'Hikka —' : of('Hikka', hikka)}';
  }

  void detach() {
    _key = null;
    current.value = null;
  }

  /// Where to listen to [song]: a direct link when known, else a search in the app
  static List<SongLink> linksFor(ThemeSong song, {SongArt? art}) => [
        for (final app in MusicApp.values)
          if (song.links[app] ?? (app == MusicApp.appleMusic ? art?.appleMusic : null) case final url?)
            SongLink(app, url, direct: true)
          else
            SongLink(app, searchLink(app, song.query), direct: false),
      ];

  // ── Songs of a title ──────────────────────────────────────────────────────

  final Map<String, (DateTime, Object)> _cache = {};
  Future<void>? _loading;
  Timer? _saveTimer;
  final Map<String, Future<Object?>> _inflight = {};

  /// AnimeThemes' openings and endings of MyAnimeList's title [malId] (empty: it does not have the title; null: it
  /// cannot be reached and nothing is remembered)
  Future<List<ThemeSong>?> songsOf(int malId) async {
    final raw = await _remembered('themes:$malId', (list) => (list as List).isEmpty ? emptyTtl : songsTtl, () async {
      final json = await _json(Uri.parse(animeThemesGraphql), body: animeThemesQuery(malId));
      if (json is! Map || json['data'] is! Map) {
        // A GraphQL answer with errors only (the schema changed?): asked again next time
        if (json is Map && json['errors'] is List) {
          final err = '${(json['errors'] as List).firstOrNull}';
          AppLog.w('пісні', 'AnimeThemes: ${err.length > 300 ? err.substring(0, 300) : err}');
        }
        return null;
      }
      return [for (final s in songsOfAnimeThemes(json)) s.toJson()];
    });
    if (raw is! List) return null;
    return [for (final j in raw) if (ThemeSong.fromJson(j) case final s?) s];
  }

  /// MyAnimeList's openings and endings of [malId] through Tenrai (empty: none listed; null: it cannot be reached and
  /// nothing is remembered)
  Future<List<ThemeSong>?> malSongsOf(int malId) async {
    final raw = await _remembered('tenrai:$malId', (list) => (list as List).isEmpty ? emptyTtl : songsTtl, () async {
      final json = await _json(tenraiThemes(malId));
      return json == null ? null : [for (final s in songsOfMal(json)) s.toJson()];
    });
    if (raw is! List) return null;
    return [for (final j in raw) if (ThemeSong.fromJson(j) case final s?) s];
  }

  /// A cover (and an Apple Music link) of [song]: the song's own Apple Music or Spotify page when its link is known
  /// (exact), else Apple Music's search, else Deezer's
  Future<SongArt?> artOf(ThemeSong song) async {
    final apple = song.links[MusicApp.appleMusic];
    final spotify = song.links[MusicApp.spotify];
    // By the song's own page when it is linked (another answer than the search's), else by what is searched for
    final raw = await _remembered('art:${apple ?? spotify ?? song.query.toLowerCase()}', (_) => artTtl, () async {
      var unreachable = false;
      final trackId = apple == null ? null : appleTrackId(apple);
      if (trackId != null) {
        final country = appleCountry(apple!);
        final json = await _json(Uri.https('itunes.apple.com', '/lookup', {'id': trackId, if (country != null) 'country': country}));
        final cover = coverOfItunesLookup(json);
        if (cover != null) return SongArt(cover: cover, appleMusic: apple).toJson();
        unreachable |= json == null;
      }
      if (spotify != null) {
        final json = await _json(Uri.https('open.spotify.com', '/oembed', {'url': spotify}));
        final cover = coverOfSpotify(json);
        if (cover != null) return SongArt(cover: cover).toJson();
        unreachable |= json == null;
      }
      // Without an artist a store's track cannot be told from another of that name: not searched
      if (song.artists.isEmpty) return null;
      SongArt? art;
      final itunes = await _json(Uri.https('itunes.apple.com', '/search', {'term': song.query, 'entity': 'song', 'limit': '10', 'country': 'JP'}));
      if (itunes != null) art = artOfItunes(song, itunes);
      if (art?.cover == null) {
        final deezer = await _json(Uri.https('api.deezer.com', '/search', {'q': song.query, 'limit': '10'}));
        final d = deezer == null ? null : artOfDeezer(song, deezer);
        if (d != null) art = SongArt(cover: d.cover, appleMusic: art?.appleMusic);
      }
      // Something unreachable and nothing found: ask again next time; all reached and not found: remember that
      if (art == null && (itunes == null || unreachable)) return null;
      return (art ?? const SongArt()).toJson();
    });
    if (raw is! Map) return null;
    final art = SongArt.fromJson(raw);
    return art.cover == null && art.appleMusic == null ? null : art;
  }

  // ── The disk copy ─────────────────────────────────────────────────────────

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
      AppLog.d('пісні', '$key: $e');
      return hit?.$2;
    }).whenComplete(() {
      _inflight.remove(key); // (not returned: whenComplete would wait for this very future)
    });
  }

  Future<Object?> _json(Uri url, {String? body}) async {
    try {
      final (status, text) = await _get(url, body: body);
      if (status == 404) return const <String, Object>{};
      if (status != 200) {
        AppLog.d('пісні', '${url.host}: відповідь $status');
        return null;
      }
      return jsonDecode(text);
    } catch (e) {
      AppLog.d('пісні', '${url.host} недоступний: $e');
      return null;
    }
  }

  static HttpClient? _client;

  static Future<(int, String)> _http(Uri url, {String? body}) async {
    final client = _client ??= HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      ..idleTimeout = const Duration(seconds: 15);
    final req = await (body == null ? client.getUrl(url) : client.postUrl(url)).timeout(const Duration(seconds: 10));
    req.headers.set(HttpHeaders.acceptHeader, 'application/json');
    req.headers.set(HttpHeaders.userAgentHeader, 'MikiMiki (github.com/Zeddy-Coder/miki-miki)');
    if (body != null) {
      final bytes = utf8.encode(body);
      req.headers.contentType = ContentType.json;
      req.contentLength = bytes.length;
      req.add(bytes);
    }
    final res = await req.close().timeout(const Duration(seconds: 12));
    final text = await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 12));
    return (res.statusCode, text);
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
            if (v is Map && v['t'] is num && v.containsKey('v')) _cache['$k'] = (DateTime.fromMillisecondsSinceEpoch((v['t'] as num).toInt()), v['v'] as Object);
          });
        } catch (e) {
          AppLog.w('пісні', 'кеш не прочитано: $e');
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
      AppLog.w('пісні', 'кеш не збережено: $e');
    }
  }
}
