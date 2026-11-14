/// My Hikka lists: a title entry (status, episodes, score), favorites and sending progress from the player.
/// Everything is kept in memory only while the person is signed in; on sign-out the cache is reset.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/hikka_models.dart';
import '../models/hikka_user_models.dart';
import 'app_log.dart';
import 'hikka_api.dart';
import 'hikka_auth.dart';
import 'storage_service.dart';

class HikkaMyList extends ChangeNotifier {
  /// Shared instance (replaced in tests)
  static HikkaMyList instance = HikkaMyList();

  final HikkaAuth? _authOverride;
  final HikkaApi? _apiOverride;
  final SectionLoader? _loadOverride;
  final SectionSaver? _saveOverride;

  /// Saved statuses: poster badges appear immediately, and a network refresh happens at most once every few hours
  static const String indexSection = 'hikka_status_index';
  static const Duration indexMaxAge = Duration(hours: 6);

  /// Entry for a title by slug (`null` means it is in no lists)
  final Map<String, HikkaWatchEntry?> _entries = {};
  final Map<String, Future<HikkaWatchEntry?>> _loading = {};
  final Map<String, bool> _favourites = {};

  /// Status of each title in my lists (for poster badges): filled in one pass over all lists
  final Map<String, HikkaWatchStatus> _index = {};
  bool _indexed = false;
  int _indexAt = 0;
  Future<void>? _indexing;
  final Map<String, Future<void>> _syncing = {};
  HikkaWatchStats? _stats;
  int _version = 0;
  bool _wasSignedIn = false;

  HikkaMyList({HikkaAuth? auth, HikkaApi? api, SectionLoader? load, SectionSaver? save})
      : _authOverride = auth,
        _apiOverride = api,
        _loadOverride = load,
        _saveOverride = save {
    _wasSignedIn = _auth.signedIn;
    _auth.addListener(_onAuth);
  }

  HikkaAuth get _auth => _authOverride ?? HikkaAuth.instance;
  HikkaApi get _api => _apiOverride ?? HikkaApi.instance;

  /// Grows on every list change: the "Списки" page reloads on it
  int get version => _version;

  bool get signedIn => _auth.signedIn;

  void _onAuth() {
    final now = _auth.signedIn;
    if (now == _wasSignedIn) return;
    _wasSignedIn = now;
    clear();
    if (now) unawaited(loadIndex());
  }

  /// Resets everything known about the lists (sign-out, account change)
  void clear() {
    _entries.clear();
    _loading.clear();
    _favourites.clear();
    _index.clear();
    _indexed = false;
    _indexAt = 0;
    _indexing = null;
    _stats = null;
    try {
      (_saveOverride ?? ((d) => StorageService.saveSection(indexSection, d)))({});
    } catch (_) {}
    _bump();
  }

  // ── Statuses for poster badges ──────────────────────────────

  /// Status of a title in my lists; `null` means it is not there or not known yet
  HikkaWatchStatus? statusOf(String slug) {
    if (!signedIn) return null;
    if (_entries.containsKey(slug)) return _entries[slug]?.status;
    return _index[slug];
  }

  /// Statuses of all titles from the lists: first from disk (instantly), then, if the data is older than [indexMaxAge], from the network
  /// (100 per request, after [delay] so as not to compete with the first screen); an error is not fatal, there just will be no badges
  Future<void> loadIndex({bool refresh = false, Duration delay = Duration.zero}) {
    final name = _auth.username;
    if (!signedIn || name.isEmpty) return Future.value();
    if (_indexed && !refresh) return Future.value();
    return _indexing ??= _loadIndex(name, refresh, delay).whenComplete(() => _indexing = null);
  }

  Future<void> _loadIndex(String name, bool refresh, Duration delay) async {
    final fresh = !refresh && _restoreIndex(name);
    if (fresh) return;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (!signedIn || _auth.username != name) return;
    await _fillIndex(name);
  }

  /// Picks up the saved statuses; `true` means they are fresh enough and the network is not needed
  bool _restoreIndex(String name) {
    try {
      final data = (_loadOverride ?? (() => StorageService.getSection(indexSection)))();
      if (data['user'] != name) return false;
      final map = data['map'];
      if (map is! Map) return false;
      for (final e in map.entries) {
        final st = HikkaWatchStatus.fromApi(e.value);
        if (st != null) _index[e.key as String] = st;
      }
      _indexed = true;
      notifyListeners();
      _indexAt = (data['at'] as num?)?.toInt() ?? 0;
      final at = DateTime.fromMillisecondsSinceEpoch(_indexAt);
      return DateTime.now().difference(at) < indexMaxAge;
    } catch (_) {
      return false;
    }
  }

  void _persistIndex() {
    if (_indexed && _auth.username.isNotEmpty) _saveIndex(_auth.username);
  }

  void _saveIndex(String name) {
    try {
      (_saveOverride ?? ((d) => StorageService.saveSection(indexSection, d)))({
        'user': name,
        'at': _indexAt,
        'map': {for (final e in _index.entries) e.key: e.value.api},
      });
    } catch (_) {}
  }

  Future<void> _fillIndex(String name) async {
    try {
      final fresh = <String, HikkaWatchStatus>{};
      for (final status in HikkaWatchStatus.values) {
        var page = 1;
        while (true) {
          final p = await _api.watchList(name, status: status, page: page, size: 100);
          for (final e in p.items) {
            final slug = e.anime?.slug;
            if (slug != null && slug.isNotEmpty) fresh[slug] = e.status;
          }
          if (page >= p.pages || p.items.isEmpty) break;
          page++;
        }
      }
      if (!signedIn || _auth.username != name) return;
      _index
        ..clear()
        ..addAll(fresh);
      _indexed = true;
      _indexAt = DateTime.now().millisecondsSinceEpoch;
      notifyListeners();
      _saveIndex(name);
    } catch (e) {
      AppLog.w('hikka', 'статуси списків не завантажено: $e');
    }
  }

  void _bump() {
    _version++;
    notifyListeners();
  }

  // ── Title entry ──────────────────────────────────────────────────

  /// What is already known without the network: `null` as a value means the title is in no lists; no key means unknown
  bool knows(String slug) => _entries.containsKey(slug);
  HikkaWatchEntry? cached(String slug) => _entries[slug];

  /// My entry for a title (from the network once, then from memory)
  Future<HikkaWatchEntry?> entry(String slug, {bool refresh = false}) {
    if (!signedIn) return Future.value(null);
    if (!refresh && _entries.containsKey(slug)) return Future.value(_entries[slug]);
    return _loading[slug] ??= _api.myWatch(slug).then((e) {
      _entries[slug] = e;
      return e;
    }).whenComplete(() {
      _loading.remove(slug);
    });
  }

  /// Saves the entry and returns what the server answered.
  /// [total] is how many episodes the title has: for "Переглянуто" the counter is topped up to the end, as on the site.
  Future<HikkaWatchEntry> save(
    String slug, {
    HikkaWatchStatus? status,
    int? episodes,
    int? score,
    int? total,
    HikkaAnime? anime,
  }) async {
    final old = await entry(slug);
    var next = (old ?? const HikkaWatchEntry(status: HikkaWatchStatus.planned)).copyWith(status: status, episodes: episodes, score: score);
    if (status == HikkaWatchStatus.completed && total != null && total > 0 && next.episodes < total) {
      next = next.copyWith(episodes: total);
    }
    if (total != null && total > 0 && next.episodes > total) next = next.copyWith(episodes: total);
    final saved = await _api.saveWatch(slug, next);
    _entries[slug] = saved.anime == null && anime != null ? saved.copyWith(anime: anime) : saved;
    _index[slug] = saved.status;
    _persistIndex();
    _stats = null;
    _bump();
    return _entries[slug]!;
  }

  /// Removes the title from the lists
  Future<void> remove(String slug) async {
    await _api.removeWatch(slug);
    _entries[slug] = null;
    _index.remove(slug);
    _persistIndex();
    _stats = null;
    _bump();
  }

  /// How many titles are in each status
  Future<HikkaWatchStats> stats({bool refresh = false}) async {
    final name = _auth.username;
    if (name.isEmpty) return const HikkaWatchStats();
    if (!refresh && _stats != null) return _stats!;
    return _stats = await _api.watchStats(name);
  }

  // ── Favorites ─────────────────────────────────────────────────────

  bool? favouriteCached(String slug) => _favourites[slug];

  Future<bool> isFavourite(String slug) async {
    if (!signedIn) return false;
    final known = _favourites[slug];
    if (known != null) return known;
    return _favourites[slug] = await _api.isFavourite(slug);
  }

  Future<void> setFavourite(String slug, bool value) async {
    await _api.setFavourite(slug, value);
    _favourites[slug] = value;
    _bump();
  }

  // ── Progress from the player ────────────────────────────────────────────

  /// Which episode to count as watched in the Hikka list: the source's episode number (episode 12 is 12), but no more
  /// than the title's episode count on Hikka ("13 of 12" is marked 12). If all of the variant's numbers lie outside
  /// the title (continuous numbering 13…24) or there is no number, [position], also capped by [total].
  static int episodeNumber({double? number, required int position, int? total, bool trustNumber = true}) {
    var r = position;
    final n = number;
    if (trustNumber && n != null && n >= 1 && n == n.roundToDouble()) r = n.toInt();
    if (total != null && total > 0 && r > total) r = total;
    return r < 1 ? 1 : r;
  }

  /// Episode [episode] of title [slug] was watched. Adds the title to "Дивлюсь", raises the episode counter and
  /// moves it to "Переглянуто" after the last one. Never lowers progress and never touches an already completed one.
  /// All failures are silent: watching matters more than syncing.
  Future<void> syncEpisode(String slug, int episode, {int? total}) {
    if (!signedIn || !_auth.syncProgress || episode < 1) return Future.value();
    final prev = _syncing[slug] ?? Future<void>.value();
    final run = prev.then((_) => _syncOne(slug, episode, total));
    _syncing[slug] = run;
    return run.whenComplete(() {
      if (identical(_syncing[slug], run)) _syncing.remove(slug);
    });
  }

  /// Removes the "watched" mark from episode [episode]: Hikka progress drops by one episode, but only if
  /// it counted that one; the rest of the list is unchanged. Same sign-in and sync rule as [syncEpisode]
  Future<void> unmarkEpisode(String slug, int episode, {int? total}) {
    if (!signedIn || !_auth.syncProgress || episode < 1) return Future.value();
    final prev = _syncing[slug] ?? Future<void>.value();
    final run = prev.then((_) => _unmarkOne(slug, episode, total));
    _syncing[slug] = run;
    return run.whenComplete(() {
      if (identical(_syncing[slug], run)) _syncing.remove(slug);
    });
  }

  Future<void> _unmarkOne(String slug, int episode, int? total) async {
    try {
      final old = await entry(slug, refresh: true);
      if (old == null || old.episodes < episode) return;
      await save(
        slug,
        status: old.status == HikkaWatchStatus.completed ? HikkaWatchStatus.watching : old.status,
        episodes: episode - 1,
        total: total,
      );
      AppLog.d('hikka', 'позначку знято: $slug, серія $episode');
    } on HikkaException catch (e) {
      AppLog.w('hikka', 'позначку не знято ($slug, серія $episode): $e');
    } catch (e) {
      AppLog.w('hikka', 'позначку не знято ($slug, серія $episode): $e');
    }
  }

  Future<void> _syncOne(String slug, int episode, int? total) async {
    try {
      // Fresh entry: on the site progress may have moved ahead, and with a stale cache we would understate it
      final old = await entry(slug, refresh: true);
      if (old != null) {
        if (old.status == HikkaWatchStatus.completed) return;
        if (episode <= old.episodes && old.status == HikkaWatchStatus.watching) return;
      }
      final done = total != null && total > 0 && episode >= total;
      final episodes = old == null ? episode : (episode > old.episodes ? episode : old.episodes);
      await save(
        slug,
        status: done ? HikkaWatchStatus.completed : HikkaWatchStatus.watching,
        episodes: episodes,
        total: total,
      );
      AppLog.d('hikka', 'прогрес передано: $slug, серія $episode${done ? ' (завершено)' : ''}');
    } on HikkaException catch (e) {
      AppLog.w('hikka', 'прогрес не передано ($slug, серія $episode): $e');
    } catch (e) {
      AppLog.w('hikka', 'прогрес не передано ($slug, серія $episode): $e');
    }
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuth);
    super.dispose();
  }
}
