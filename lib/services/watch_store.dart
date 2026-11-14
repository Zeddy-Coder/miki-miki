/// What the person has already watched and where they stopped + remembered Hikka ↔ site matches.
/// Positions inside episodes are stored by `StorageService.savePlaybackPosition` (the key is `RemoteEntry.key`).
library;

import 'package:flutter/foundation.dart';

import '../models/source_models.dart';
import 'storage_service.dart';

/// The last episode opened
class WatchLast {
  final String epKey;
  final String groupId;
  final DateTime at;

  const WatchLast(this.epKey, this.groupId, this.at);
}

class WatchStore extends ChangeNotifier {
  static const String section = 'watch_store';
  static const int _maxTitles = 400;

  final SectionLoader _load;
  final SectionSaver _save;
  final DateTime Function() _now;
  late Map<String, dynamic> _data = _fresh(_load());

  WatchStore({SectionLoader? load, SectionSaver? save, DateTime Function()? now})
      : _load = load ?? (() => StorageService.getSection(section)),
        _save = save ?? ((d) => StorageService.saveSection(section, d)),
        _now = now ?? DateTime.now;

  static WatchStore instance = WatchStore();

  static Map<String, dynamic> _fresh(Map<String, dynamic> src) => {
        'watched': Map<String, dynamic>.of((src['watched'] as Map?)?.cast<String, dynamic>() ?? const {}),
        'last': Map<String, dynamic>.of((src['last'] as Map?)?.cast<String, dynamic>() ?? const {}),
        'links': Map<String, dynamic>.of((src['links'] as Map?)?.cast<String, dynamic>() ?? const {}),
        'group': Map<String, dynamic>.of((src['group'] as Map?)?.cast<String, dynamic>() ?? const {}),
        'pin': Map<String, dynamic>.of((src['pin'] as Map?)?.cast<String, dynamic>() ?? const {}),
        'avail': Map<String, dynamic>.of((src['avail'] as Map?)?.cast<String, dynamic>() ?? const {}),
        if (src['favorites'] is List) 'favorites': [for (final x in src['favorites'] as List) '$x'],
      };

  void reload() {
    _data = _fresh(_load());
    notifyListeners();
  }

  Map<String, dynamic> _map(String name) => _data[name] as Map<String, dynamic>;

  void _commit() {
    _save(_data);
    notifyListeners();
  }

  // ── Watched ──────────────────────────────────────────────────────────────────

  Set<String> watched(String animeKey) => {for (final x in (_map('watched')[animeKey] as List? ?? const [])) '$x'};

  bool isWatched(String animeKey, String epKey) => watched(animeKey).contains(epKey);

  void setWatched(String animeKey, String epKey, bool value) {
    final set = watched(animeKey);
    if (value ? !set.add(epKey) : !set.remove(epKey)) return;
    if (set.isEmpty) {
      _map('watched').remove(animeKey);
    } else {
      _map('watched')[animeKey] = set.toList();
    }
    _commit();
  }

  /// Mark all episodes up to [upToEpKey] inclusive (by the order [order])
  void markUpTo(String animeKey, List<String> order, String upToEpKey) {
    final i = order.indexOf(upToEpKey);
    if (i < 0) return;
    final set = watched(animeKey)..addAll(order.take(i + 1));
    _map('watched')[animeKey] = set.toList();
    _commit();
  }

  // ── Last episode and the chosen dub ────────────────────────────────────────────

  WatchLast? last(String animeKey) {
    final j = _map('last')[animeKey];
    if (j is! Map) return null;
    final ep = j['e'];
    if (ep is! String) return null;
    return WatchLast(ep, (j['g'] as String?) ?? '', DateTime.fromMillisecondsSinceEpoch((j['t'] as num?)?.toInt() ?? 0));
  }

  /// Records the last opened episode; the oldest entries beyond the limit are dropped
  void setLast(String animeKey, String epKey, String groupId) {
    final m = _map('last');
    m[animeKey] = {'e': epKey, 'g': groupId, 't': _now().millisecondsSinceEpoch};
    if (m.length > _maxTitles) {
      final byAge = m.entries.toList()..sort((a, b) => ((a.value as Map)['t'] as num).compareTo((b.value as Map)['t'] as num));
      for (final e in byAge.take(m.length - _maxTitles)) {
        m.remove(e.key);
        _map('watched').remove(e.key);
        _map('avail').remove(e.key);
      }
    }
    _commit();
  }

  /// Removes a title from the "Продовжити перегляд" list; marks of watched episodes stay
  void forgetLast(String animeKey) {
    if (_map('last').remove(animeKey) == null) return;
    _commit();
  }

  /// Titles with recent views, newest first
  List<String> recentTitles({int limit = 20}) {
    final m = _map('last');
    final keys = m.keys.toList()..sort((a, b) => ((m[b] as Map)['t'] as num).compareTo((m[a] as Map)['t'] as num));
    return keys.take(limit).toList();
  }

  // ── How many episodes the title's chosen dub has ──────────────────────────

  /// How many episodes variant [groupId] of this title had last time (and what it is called; `prev` is how many it had before the last
  /// increase); `null`: not checked yet
  ({String groupId, String label, int count, int prev, DateTime at})? available(String animeKey) {
    final j = _map('avail')[animeKey];
    if (j is! Map || j['g'] is! String) return null;
    return (
      groupId: j['g'] as String,
      label: (j['l'] as String?) ?? '',
      count: (j['n'] as num?)?.toInt() ?? 0,
      prev: (j['p'] as num?)?.toInt() ?? (j['n'] as num?)?.toInt() ?? 0,
      at: DateTime.fromMillisecondsSinceEpoch((j['t'] as num?)?.toInt() ?? 0),
    );
  }

  /// Remembers the episode count of the chosen variant. It is recorded (and notifies) only if something changed or the data is
  /// older than half an hour, so frequent checks do not ring across the whole app
  void setAvailable(String animeKey, String groupId, String label, int count) {
    final old = available(animeKey);
    final same = old != null && old.groupId == groupId && old.count == count && old.label == label;
    if (same && _now().difference(old.at) < const Duration(minutes: 30)) return;
    // prev is how many episodes were available before the last increase: it shows whether the viewer was "caught up" when the new one came out
    final prev = old == null || old.groupId != groupId ? count : (count > old.count ? old.count : (count < old.prev ? count : old.prev));
    _map('avail')[animeKey] = {'g': groupId, 'l': label, 'n': count, 'p': prev, 't': _now().millisecondsSinceEpoch};
    if (same) {
      _save(_data);
    } else {
      _commit();
    }
  }

  String? preferredGroup(String animeKey) => _map('group')[animeKey] as String?;

  /// The dub the person chose manually for this title (the list on the page or the player): it outranks the team priority
  /// and auto-switching. Autostart does not set it
  String? pinnedGroup(String animeKey) => _map('pin')[animeKey] as String?;

  void setPinnedGroup(String animeKey, String groupId) {
    if (_map('pin')[animeKey] == groupId) return;
    _map('pin')[animeKey] = groupId;
    _commit();
  }

  void clearPinnedGroup(String animeKey) {
    if (_map('pin').remove(animeKey) != null) _commit();
  }

  void setPreferredGroup(String animeKey, String groupId) {
    if (_map('group')[animeKey] == groupId) return;
    _map('group')[animeKey] = groupId;
    _commit();
  }

  /// Dubs and subtitles (`choiceKeyOf`) the person deliberately chose in the player, newest first: a familiar one
  /// is taken from them in new titles (see `pickGroup`)
  List<String> get favoriteChoices => List.unmodifiable((_data['favorites'] as List?) ?? const <String>[]);

  static const int _maxFavorites = 8;

  void setFavoriteChoice(String key) {
    final list = [...favoriteChoices];
    if (list.isNotEmpty && list.first == key) return;
    list
      ..remove(key)
      ..insert(0, key);
    _data['favorites'] = list.take(_maxFavorites).toList();
    _commit();
  }

  // ── Hikka ↔ site matches ────────────────────────────────────────────────

  static String _linkKey(String hikkaSlug, String sourceId) => '$hikkaSlug|$sourceId';

  SAnime? link(String hikkaSlug, String sourceId) {
    final j = _map('links')[_linkKey(hikkaSlug, sourceId)];
    return j is Map ? SAnime.fromJson(j.cast<String, dynamic>()) : null;
  }

  void setLink(String hikkaSlug, String sourceId, SAnime? anime) {
    final k = _linkKey(hikkaSlug, sourceId);
    if (anime == null) {
      if (_map('links').remove(k) == null) return;
    } else {
      _map('links')[k] = anime.toJson();
    }
    _commit();
  }
}
