/// Anime Skip (`api.anime-skip.com`): a second base of opening / ending times marked by viewers. It has episodes
/// AniSkip does not (Vinland Saga 2, episode 11: nothing in AniSkip, opening and ending here), so both are asked.
///
/// Its shows are found by AniList id (MyAnimeList's id → AniList's through AniList's own API); one AniList title may
/// have several shows made by different people. An episode's marks are where its parts begin (Branding, Intro, Canon,
/// Credits, Preview…): a part runs to the next mark, the last one to the end of the version marked
/// (`baseDuration`). They are read into AniSkip's form (`AniSkipTime`, the version's length with them), so
/// `alignSkips` weighs both bases the same way. Remembered on disk (`<appBasePath>/anime_skip_cache.json`): a
/// title's AniList id for half a year, its episodes for a week; an old answer still serves offline. The episodes' names
/// come along (`names`): the last resort of the episode list's titles.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../app_log.dart';
import '../storage_service.dart';
import 'aniskip.dart';

/// POST [body] (JSON) with [headers] → (status, body); tests replace it
typedef SkipPost = Future<(int, String)> Function(Uri url, String body, Map<String, String> headers);

/// The marks of a part that is skipped, by the part's kind; the others (Canon, Branding, Preview…) are the episode
SkipKind? animeSkipKind(String type) => switch (type.trim().toLowerCase()) {
      'intro' || 'new intro' => SkipKind.op,
      'mixed intro' => SkipKind.mixedOp,
      'credits' || 'new credits' => SkipKind.ed,
      'mixed credits' => SkipKind.mixedEd,
      'recap' => SkipKind.recap,
      _ => null,
    };

/// The times in Anime Skip's answer (`findShowsByExternalId { episodes { id number baseDuration timestamps { at type
/// { name } } } }`) by episode number. Per version and kind only the longest part counts (a stray «Credits» of a few
/// seconds after the preview is not the ending); openings and endings of under 20 s or over 150 s are not taken
Map<int, List<AniSkipTime>> animeSkipTimes(Object? json) {
  final data = json is Map ? json['data'] : null;
  final shows = data is Map ? data['findShowsByExternalId'] : null;
  final out = <int, List<AniSkipTime>>{};
  for (final show in shows is List ? shows : const []) {
    if (show is! Map) continue;
    for (final ep in (show['episodes'] as List?) ?? const []) {
      if (ep is! Map) continue;
      final n = double.tryParse('${ep['number'] ?? ''}'.trim());
      final length = (ep['baseDuration'] as num?)?.toDouble();
      if (n == null || n < 1 || n != n.roundToDouble() || length == null || length <= 0) continue;
      final marks = <(double, String)>[
        for (final t in (ep['timestamps'] as List?) ?? const [])
          if (t is Map && t['at'] is num && t['type'] is Map) ((t['at'] as num).toDouble(), '${(t['type'] as Map)['name'] ?? ''}'),
      ]..sort((a, b) => a.$1.compareTo(b.$1));
      final best = <SkipKind, AniSkipTime>{};
      for (var i = 0; i < marks.length; i++) {
        final kind = animeSkipKind(marks[i].$2);
        if (kind == null) continue;
        final start = marks[i].$1 < 0 ? 0.0 : marks[i].$1;
        final end = i + 1 < marks.length ? marks[i + 1].$1 : length;
        final len = end - start;
        final song = kind != SkipKind.recap;
        if (len < (song ? 20 : 5) || (song && len > 150) || end > length + 1) continue;
        if ((best[kind]?.length ?? 0) >= len) continue;
        best[kind] = AniSkipTime(kind, start, end, length, id: 'as:${ep['id'] ?? n}:${kind.name}');
      }
      if (best.isNotEmpty) (out[n.toInt()] ??= []).addAll(best.values);
    }
  }
  return out;
}

/// The episodes' names in Anime Skip's answer by number: the first one given of every whole number; stand-ins such as
/// «Episode 1» left out
Map<int, String> animeSkipNames(Object? json) {
  final data = json is Map ? json['data'] : null;
  final shows = data is Map ? data['findShowsByExternalId'] : null;
  final out = <int, String>{};
  for (final show in shows is List ? shows : const []) {
    if (show is! Map) continue;
    for (final ep in (show['episodes'] as List?) ?? const []) {
      if (ep is! Map) continue;
      final n = double.tryParse('${ep['number'] ?? ''}'.trim());
      final name = ep['name'] is String ? (ep['name'] as String).trim() : '';
      if (n == null || n < 1 || n != n.roundToDouble() || name.isEmpty || _standInName.hasMatch(name)) continue;
      out.putIfAbsent(n.toInt(), () => name);
    }
  }
  return out;
}

final RegExp _standInName = RegExp(r'^\s*(episode|ep\.?)\s*\d+\s*$', caseSensitive: false);

class AnimeSkip {
  static AnimeSkip instance = AnimeSkip();

  static final Uri api = Uri.parse('https://api.anime-skip.com/graphql');
  static final Uri aniList = Uri.parse('https://graphql.anilist.co');

  /// Anime Skip's shared client id, the one its own docs give anyone (rate limited)
  static const String sharedClientId = 'ZGfO0sMF3eCwLYf8yMSCJjlynwNGRXWE';

  final SkipPost _post;
  final String? _cachePath;
  final String clientId;
  final Duration ttl;
  final Duration emptyTtl;
  final Duration idTtl;
  final DateTime Function() _now;

  AnimeSkip({
    SkipPost? post,
    String? cachePath,
    bool persist = true,
    this.clientId = sharedClientId,
    this.ttl = const Duration(days: 7),
    this.emptyTtl = const Duration(days: 1),
    this.idTtl = const Duration(days: 180),
    DateTime Function()? now,
  })  : _post = post ?? _httpPost,
        _now = now ?? DateTime.now,
        _cachePath = cachePath ?? (persist ? '${StorageService.appBasePath}${Platform.pathSeparator}anime_skip_cache.json' : null);

  /// key → (when, value): `al:<mal>` → AniList id (0: none), `show:<al>` → {episode: [times], `names`: {episode: name}}
  final Map<String, (DateTime, Object)> _cache = {};
  final Map<String, Future<Object?>> _inflight = {};
  Future<void>? _loading;
  Timer? _saveTimer;
  static const int _maxEntries = 1500;

  /// Episode [episode] of MyAnimeList's title [malId]: the times of every version marked (empty: none; null: Anime
  /// Skip or AniList could not be reached and nothing is remembered)
  Future<List<AniSkipTime>?> times(int malId, int episode) async {
    if (malId <= 0 || episode <= 0) return const [];
    final al = await _remembered('al:$malId', (v) => v == 0 ? ttl : idTtl, () => _aniListId(malId));
    if (al is! int) return null;
    if (al == 0) return const [];
    final show = await _remembered('show:$al', (v) => (v as Map).isEmpty ? emptyTtl : ttl, () => _show(al));
    if (show is! Map) return null;
    return [
      for (final t in (show['$episode'] as List?) ?? const [])
        if (AniSkipTime.fromJson(t) case final x?) x,
    ];
  }

  /// The episodes' names of MyAnimeList's title [malId] by number (empty: none; null: Anime Skip or AniList could not be
  /// reached and nothing is remembered)
  Future<Map<int, String>?> names(int malId) async {
    if (malId <= 0) return const {};
    final al = await _remembered('al:$malId', (v) => v == 0 ? ttl : idTtl, () => _aniListId(malId));
    if (al is! int) return null;
    if (al == 0) return const {};
    final show = await _remembered('show:$al', (v) => (v as Map).isEmpty ? emptyTtl : ttl, () => _show(al));
    if (show is! Map) return null;
    final names = show['names'];
    return {
      if (names is Map)
        for (final e in names.entries)
          if (int.tryParse('${e.key}') case final n?) n: '${e.value}',
    };
  }

  Future<Object?> _aniListId(int malId) async {
    final body = jsonEncode({'query': r'query($id:Int){ Media(idMal:$id, type: ANIME){ id } }', 'variables': {'id': malId}});
    final j = await _json(aniList, body, const {});
    if (j is! Map) return null;
    final media = j['data'] is Map ? (j['data'] as Map)['Media'] : null;
    // AniList answers 404 «Not Found.» for a MyAnimeList id it does not know
    if (media is! Map) return j['errors'] is List ? 0 : null;
    return (media['id'] as num?)?.toInt() ?? 0;
  }

  Future<Object?> _show(int aniListId) async {
    final body = jsonEncode({
      'query': '{ findShowsByExternalId(service: ANILIST, serviceId: "$aniListId") '
          '{ episodes { id number name baseDuration timestamps { at type { name } } } } }',
    });
    final j = await _json(api, body, {'X-Client-ID': clientId});
    if (j is! Map || j['data'] is! Map) {
      if (j is Map && j['errors'] is List) AppLog.w('пропуск', 'Anime Skip: ${'${(j['errors'] as List).firstOrNull}'.replaceAll('\n', ' ')}');
      return null;
    }
    final names = animeSkipNames(j);
    return {
      for (final e in animeSkipTimes(j).entries) '${e.key}': [for (final t in e.value) t.toJson()],
      if (names.isNotEmpty) 'names': {for (final e in names.entries) '${e.key}': e.value},
    };
  }

  Future<Object?> _json(Uri url, String body, Map<String, String> headers) async {
    try {
      final (status, text) = await _post(url, body, headers);
      if (status != 200 && !(status == 404 && url == aniList)) {
        AppLog.d('пропуск', '${url.host}: відповідь $status');
        return null;
      }
      return jsonDecode(text);
    } catch (e) {
      AppLog.d('пропуск', '${url.host} недоступний: $e');
      return null;
    }
  }

  static HttpClient? _client;

  static Future<(int, String)> _httpPost(Uri url, String body, Map<String, String> headers) async {
    final client = _client ??= HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      ..idleTimeout = const Duration(seconds: 15);
    final req = await client.postUrl(url).timeout(const Duration(seconds: 10));
    final bytes = utf8.encode(body);
    req.headers.set(HttpHeaders.acceptHeader, 'application/json');
    req.headers.set(HttpHeaders.userAgentHeader, 'MikiMiki (github.com/Zeddy-Coder/miki-miki)');
    req.headers.contentType = ContentType.json;
    headers.forEach(req.headers.set);
    req.contentLength = bytes.length;
    req.add(bytes);
    final res = await req.close().timeout(const Duration(seconds: 15));
    final text = await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 15));
    return (res.statusCode, text);
  }

  // ── The disk copy ─────────────────────────────────────────────────────────

  /// What is remembered under [key] while fresh ([ttl] by the value); else asked for, and the old one when that fails
  Future<Object?> _remembered(String key, Duration Function(Object value) ttl, Future<Object?> Function() fetch) async {
    await _load();
    final hit = _cache[key];
    final now = _now();
    if (hit != null && now.difference(hit.$1) < ttl(hit.$2)) return hit.$2;
    return _inflight[key] ??= fetch().then((fresh) {
      if (fresh == null) return hit?.$2;
      _cache[key] = (now, fresh);
      _saveSoon();
      return fresh;
    }).catchError((Object e) {
      AppLog.d('пропуск', 'Anime Skip $key: $e');
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
          AppLog.w('пропуск', 'кеш Anime Skip не прочитано: $e');
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
      AppLog.w('пропуск', 'кеш Anime Skip не збережено: $e');
    }
  }
}
