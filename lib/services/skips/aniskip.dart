/// AniSkip (`api.aniskip.com`): opening / ending times marked by viewers, by MyAnimeList id and episode number.
///
/// Each answer belongs to one version of the episode, the one it was marked on (`episodeLength`). Versions of the same
/// episode differ a lot (checked on Frieren 1: the opening at 3.2 s in a 1559.9 s version, at 116.7 s in a 1510.1 s
/// one), so the length always travels with the times. The API answers with the version nearest to the length asked
/// for (with 0 — the most trusted one per kind); [AniSkip.candidates] asks both ways and leaves the choice to
/// `alignSkips`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../app_log.dart';
import '../storage_service.dart';

/// What a time marks (AniSkip's `skipType`)
enum SkipKind { op, ed, mixedOp, mixedEd, recap }

class AniSkipTime {
  final SkipKind kind;
  final double start;
  final double end;

  /// The length of the version these times were marked on (seconds)
  final double episodeLength;
  final String id;

  const AniSkipTime(this.kind, this.start, this.end, this.episodeLength, {this.id = ''});

  double get length => end - start;

  /// The base the times come from: Anime Skip's carry `as:` in their id
  String get base => id.startsWith('as:') ? 'Anime Skip' : 'AniSkip';

  static SkipKind? kindOf(String t) => switch (t) {
        'op' => SkipKind.op,
        'ed' => SkipKind.ed,
        'mixed-op' => SkipKind.mixedOp,
        'mixed-ed' => SkipKind.mixedEd,
        'recap' => SkipKind.recap,
        _ => null,
      };

  Map<String, Object> toJson() => {'k': kind.name, 's': start, 'e': end, 'l': episodeLength, if (id.isNotEmpty) 'id': id};

  static AniSkipTime? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final kind = SkipKind.values.asNameMap()[raw['k']];
    final s = (raw['s'] as num?)?.toDouble();
    final e = (raw['e'] as num?)?.toDouble();
    final l = (raw['l'] as num?)?.toDouble();
    if (kind == null || s == null || e == null || l == null) return null;
    return AniSkipTime(kind, s, e, l, id: '${raw['id'] ?? ''}');
  }

  /// One result of the API (`{interval: {startTime, endTime}, skipType, skipId, episodeLength}`)
  static AniSkipTime? fromApi(Object? raw) {
    if (raw is! Map) return null;
    final kind = kindOf('${raw['skipType']}');
    final interval = raw['interval'];
    if (kind == null || interval is! Map) return null;
    final s = (interval['startTime'] as num?)?.toDouble();
    final e = (interval['endTime'] as num?)?.toDouble();
    final l = (raw['episodeLength'] as num?)?.toDouble();
    if (s == null || e == null || l == null || e <= s || s < 0 || l <= 0) return null;
    return AniSkipTime(kind, s, e, l, id: '${raw['skipId'] ?? ''}');
  }
}

/// GET → (status, body); tests replace it
typedef AniSkipGet = Future<(int, String)> Function(Uri url);

class AniSkip {
  static AniSkip instance = AniSkip();

  static const String host = 'https://api.aniskip.com/v2/skip-times';

  final AniSkipGet _get;

  /// Where answers are kept between runs (null: memory only)
  final String? _cachePath;

  /// How long an answer counts as fresh; an older one still serves when AniSkip cannot be reached (offline)
  final Duration ttl;
  final Duration emptyTtl;

  final DateTime Function() _now;

  AniSkip({
    AniSkipGet? get,
    String? cachePath,
    bool persist = true,
    this.ttl = const Duration(days: 7),
    this.emptyTtl = const Duration(days: 1),
    DateTime Function()? now,
  })  : _get = get ?? _httpGet,
        _now = now ?? DateTime.now,
        _cachePath = cachePath ?? (persist ? '${StorageService.appBasePath}${Platform.pathSeparator}aniskip_cache.json' : null);

  /// key → (when, times)
  final Map<String, (DateTime, List<AniSkipTime>)> _cache = {};
  Future<void>? _loading;
  Timer? _saveTimer;
  final Map<String, Future<List<AniSkipTime>?>> _inflight = {};

  static const int _maxEntries = 1500;

  /// Lengths are asked in 5-second steps: a few seconds more or less pick the same version
  static int bucket(double length) => length <= 0 ? 0 : (length / 5).round() * 5;

  static String keyOf(int malId, int episode, int length) => '$malId/$episode/$length';

  /// Times for episode [episode] of MAL title [malId] from the version nearest to [length] (0: the most trusted one
  /// per kind). An empty list: nothing is marked; null: AniSkip could not be reached and nothing is remembered
  Future<List<AniSkipTime>?> times(int malId, int episode, {double length = 0}) async {
    if (malId <= 0 || episode <= 0) return const [];
    await _load();
    final len = bucket(length);
    final key = keyOf(malId, episode, len);
    final cached = _cache[key];
    final now = _now();
    if (cached != null && now.difference(cached.$1) < (cached.$2.isEmpty ? emptyTtl : ttl)) return cached.$2;
    return _inflight[key] ??= _fetch(malId, episode, len).then((fresh) {
      // Unreachable (offline): what is remembered for this length, else for the neighbouring 5-second step (a
      // downloaded file measures a little differently from the player)
      if (fresh == null) return cached?.$2 ?? _cache[keyOf(malId, episode, len - 5)]?.$2 ?? _cache[keyOf(malId, episode, len + 5)]?.$2;
      _cache[key] = (now, fresh);
      _saveSoon();
      return fresh;
    }).whenComplete(() {
      _inflight.remove(key); // (not returned: whenComplete would wait for this very future)
    });
  }

  /// Everything worth weighing for a video of [length] s: the most trusted times per kind and the version nearest to
  /// [length] (both lists merged, without repeats). null: nothing known and AniSkip could not be reached
  Future<List<AniSkipTime>?> candidates(int malId, int episode, double length) async {
    final results = await Future.wait([times(malId, episode), if (length > 0) times(malId, episode, length: length)]);
    if (results.every((r) => r == null)) return null;
    final seen = <String>{};
    return [
      for (final list in results)
        for (final t in list ?? const <AniSkipTime>[])
          if (seen.add(t.id.isNotEmpty ? t.id : '${t.kind.name}|${t.start}|${t.episodeLength}')) t,
    ];
  }

  Future<List<AniSkipTime>?> _fetch(int malId, int episode, int length) async {
    final uri = Uri.parse('$host/$malId/$episode?types=op&types=ed&types=mixed-op&types=mixed-ed&types=recap&episodeLength=$length');
    try {
      final (status, body) = await _get(uri);
      if (status == 404) return const [];
      if (status != 200) {
        AppLog.w('пропуск', 'AniSkip: відповідь $status ($malId/$episode)');
        return null;
      }
      final j = jsonDecode(body);
      if (j is! Map || j['found'] != true) return const [];
      return [
        for (final r in (j['results'] as List?) ?? const [])
          if (AniSkipTime.fromApi(r) case final t?) t,
      ];
    } catch (e) {
      AppLog.d('пропуск', 'AniSkip недоступний ($malId/$episode): $e');
      return null;
    }
  }

  static HttpClient? _client;

  static Future<(int, String)> _httpGet(Uri url) async {
    final client = _client ??= HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      ..idleTimeout = const Duration(seconds: 15);
    final req = await client.getUrl(url).timeout(const Duration(seconds: 10));
    req.headers.set(HttpHeaders.acceptHeader, 'application/json');
    req.headers.set(HttpHeaders.userAgentHeader, 'MikiMiki (github.com/Zeddy-Coder/miki-miki)');
    final res = await req.close().timeout(const Duration(seconds: 12));
    final body = await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 12));
    return (res.statusCode, body);
  }

  // ── The disk copy ─────────────────────────────────────────────────────────

  Future<void> _load() => _loading ??= () async {
        final path = _cachePath;
        if (path == null) return;
        try {
          final f = File(path);
          if (!await f.exists()) return;
          final j = jsonDecode(await f.readAsString());
          if (j is! Map) return;
          j.forEach((k, v) {
            if (v is! Map) return;
            final t = (v['t'] as num?)?.toInt();
            if (t == null) return;
            _cache['$k'] = (
              DateTime.fromMillisecondsSinceEpoch(t),
              [
                for (final x in (v['r'] as List?) ?? const [])
                  if (AniSkipTime.fromJson(x) case final a?) a,
              ],
            );
          });
        } catch (e) {
          AppLog.w('пропуск', 'кеш AniSkip не прочитано: $e');
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
      await tmp.writeAsString(jsonEncode({
        for (final e in _cache.entries)
          e.key: {'t': e.value.$1.millisecondsSinceEpoch, 'r': [for (final t in e.value.$2) t.toJson()]},
      }));
      await tmp.rename(path);
    } catch (e) {
      AppLog.w('пропуск', 'кеш AniSkip не збережено: $e');
    }
  }
}
