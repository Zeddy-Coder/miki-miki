/// "Продовжити перегляд": Hikka titles the person recently opened in the player, newest first.
/// Data comes from `WatchStore` (what was opened and when) and `HikkaApi` (poster and title); progress within
/// an episode is stored by the player separately.
library;

import 'dart:async';

import '../models/hikka_models.dart';
import '../models/hikka_user_models.dart';
import 'hikka_api.dart';
import 'hikka_auth.dart';
import 'hikka_lists.dart';
import 'watch_service.dart';
import 'watch_store.dart';

/// A title in the "Продовжити перегляд" list
class ContinueItem {
  final HikkaAnime anime;

  /// The last opened episode ("3", "s2e5") or `null` if there is no number
  final String? episodeKey;
  final DateTime at;

  /// The title was watched but is in none of the Hikka lists (shown with a badge)
  final bool notInList;

  /// How many episodes are already watched and how many the dub chosen during watching has (`null` means unknown)
  final int watched;
  final int? dubCount;

  /// How many episodes the dub had before the latest increase (see [hasNew])
  final int? dubPrev;

  /// Name of the chosen dub (for the caption "Нова серія · Inari")
  final String dubName;

  const ContinueItem({required this.anime, required this.episodeKey, required this.at, this.notInList = false, this.watched = 0, this.dubCount, this.dubPrev, this.dubName = ''});

  /// "New episode": only for ongoing titles and only if the viewer watched everything available in the chosen dub before the new
  /// episode came out (`watched >= dubPrev`). Whoever has not caught up sees no "new" until they do. Episodes
  /// released by other teams do not count
  bool get hasNew => anime.isOngoing && dubCount != null && dubCount! > watched && watched >= (dubPrev ?? dubCount!);

  /// "Серія 3" / "Сезон 2 · серія 5"; `null` if the episode is not determined
  String? get episodeLabel => episodeKey == null ? null : ContinueWatching.episodeCaption(episodeKey!);

  /// Short badge for the poster: "Серія 3" / "С2 · Е5"
  String? get episodeShort => episodeKey == null ? null : ContinueWatching.episodeShort(episodeKey!);
}

class ContinueWatching {
  const ContinueWatching._();

  /// Prefix of the Hikka title key in `WatchStore` (`hikka:<slug>`)
  static const String prefix = 'hikka:';

  /// Label by episode key: "3" → "Серія 3", "3.5" → "Серія 3.5", "s2e5" → "Сезон 2 · серія 5", "i7" → "Серія 7"
  static String? episodeCaption(String epKey) {
    final season = RegExp(r'^s(\d+)e(.+)$').firstMatch(epKey);
    if (season != null) return 'Сезон ${season.group(1)} · серія ${_number(season.group(2)!)}';
    final plain = _number(epKey);
    return plain.isEmpty ? null : 'Серія $plain';
  }

  /// Short form for the poster badge: "3" → "Серія 3", "s2e5" → "С2 · Е5"
  static String? episodeShort(String epKey) {
    final season = RegExp(r'^s(\d+)e(.+)$').firstMatch(epKey);
    if (season != null) return 'С${season.group(1)} · Е${_number(season.group(2)!)}';
    final plain = _number(epKey);
    return plain.isEmpty ? null : 'Серія $plain';
  }

  /// The ordinal number "i7" is shown as "7"
  static String _number(String key) => key.startsWith('i') ? key.substring(1) : key;

  /// Hikka titles with recent views: (slug, last opened episode, when), newest first
  static List<(String slug, String? epKey, DateTime at)> recent({WatchStore? store, int limit = 12}) {
    final s = store ?? WatchStore.instance;
    final out = <(String, String?, DateTime)>[];
    for (final key in s.recentTitles(limit: 400)) {
      if (!key.startsWith(prefix)) continue;
      final slug = key.substring(prefix.length);
      if (slug.isEmpty) continue;
      final last = s.last(key);
      if (last == null) continue;
      out.add((slug, last.epKey.isEmpty ? null : last.epKey, last.at));
      if (out.length >= limit) break;
    }
    return out;
  }

  /// How many episodes the dub chosen while watching this title has: (count, name) or (`null`, '').
  /// Only for the same dub as the last opened one (or the one chosen on the page): another team's data does not fit.
  static (int?, String, int?) dubOf(WatchStore s, String animeKey) {
    final av = s.available(animeKey);
    if (av == null) return (null, '', null);
    final chosen = (s.last(animeKey)?.groupId ?? '').isNotEmpty ? s.last(animeKey)!.groupId : s.preferredGroup(animeKey);
    if (chosen != av.groupId) return (null, '', null);
    return (av.count, av.label, av.prev);
  }

  /// Label of the episode counts of the chosen dubs: a change means the shelf must be rebuilt
  static String availabilitySignature({WatchStore? store}) {
    final s = store ?? WatchStore.instance;
    return [for (final r in recent(store: s, limit: 24)) () {
      final d = dubOf(s, '$prefix${r.$1}');
      return '${r.$1}:${d.$1}:${d.$3}';
    }()].join(',');
  }

  /// Quietly checks whether new episodes appeared in the chosen dub of ongoing titles from the list (the result settles in `WatchStore`).
  /// At most once per [maxAge] for a title and no more than [max] at a time, one by one.
  static Future<void> refreshAvailability(
    List<ContinueItem> items, {
    WatchStore? store,
    WatchService? service,
    Duration maxAge = const Duration(hours: 3),
    int max = 4,
  }) async {
    final s = store ?? WatchStore.instance;
    final svc = service ?? WatchService.instance;
    var n = 0;
    for (final it in items) {
      if (n >= max) break;
      final a = it.anime;
      if (!a.isOngoing) continue;
      final key = '$prefix${a.slug}';
      final gid = (s.last(key)?.groupId ?? '').isNotEmpty ? s.last(key)!.groupId : s.preferredGroup(key);
      if (gid == null || gid.isEmpty) continue;
      final av = s.available(key);
      if (av != null && av.groupId == gid && DateTime.now().difference(av.at) < maxAge) continue;
      n++;
      final load = svc.start(a, searchOthers: !gid.startsWith('mikai|'));
      final done = Completer<void>();
      void check() {
        if (!load.busy && !done.isCompleted) done.complete();
      }
      load.addListener(check);
      check();
      await done.future.timeout(const Duration(seconds: 25), onTimeout: () {});
      load.removeListener(check);
      load.dispose();
    }
  }

  /// The "Продовжити перегляд" list: everything from the "Дивлюсь" list on Hikka (if signed in) plus titles watched
  /// locally but not added to any list (marked [ContinueItem.notInList]). Order follows the last
  /// view (for those without one, the time the Hikka entry was updated), so even ongoing titles without new episodes sit
  /// where you stopped on them. Finished and fully watched local titles are not shown.
  static Future<List<ContinueItem>> load({WatchStore? store, HikkaApi? api, HikkaAuth? auth, HikkaMyList? lists, int limit = 20, bool allowAdult = false}) async {
    final s = store ?? WatchStore.instance;
    final client = api ?? HikkaApi.instance;
    final user = auth ?? HikkaAuth.instance;
    final myList = lists ?? HikkaMyList.instance;
    final recents = recent(store: s, limit: 400);
    final local = {for (final r in recents) r.$1: r};

    // The "Дивлюсь" list (a network error is not fatal: local views remain)
    final watching = <HikkaWatchEntry>[];
    if (user.signedIn && user.username.isNotEmpty) {
      try {
        for (var page = 1; page <= 5; page++) {
          final p = await client.watchList(user.username, status: HikkaWatchStatus.watching, page: page, size: 100);
          watching.addAll(p.items.where((e) => e.anime != null));
          if (page >= p.pages || p.items.isEmpty) break;
        }
      } catch (_) {}
    }

    final out = <ContinueItem>[];
    final seen = <String>{};
    for (final e in watching) {
      final a = e.anime!;
      if (a.isAdult && !allowAdult) continue;
      if (!seen.add(a.slug)) continue;
      final l = local[a.slug];
      final done = s.watched('$prefix${a.slug}').length;
      final dub = dubOf(s, '$prefix${a.slug}');
      // Hikka progress is ahead of the local one (watched on the site): the label and continuation follow it
      final localNum = int.tryParse((l?.$2 ?? '').replaceAll(RegExp(r'^s\d+e'), '')) ?? 0;
      out.add(ContinueItem(
        anime: a,
        episodeKey: e.episodes > localNum ? '${e.episodes}' : l?.$2,
        at: l?.$3 ?? DateTime.fromMillisecondsSinceEpoch(e.updated * 1000),
        watched: done > e.episodes ? done : e.episodes,
        dubCount: dub.$1,
        dubPrev: dub.$3,
        dubName: dub.$2,
      ));
    }

    // Local views outside the "Дивлюсь" list
    final extra = [for (final r in recents) if (!seen.contains(r.$1)) r].take(limit).toList();
    final loaded = await Future.wait([
      for (final r in extra)
        () async {
          try {
            return await client.anime(r.$1);
          } catch (_) {
            return null;
          }
        }(),
    ]);
    for (int i = 0; i < extra.length; i++) {
      final anime = loaded[i];
      if (anime == null) continue;
      if (anime.isAdult && !allowAdult) continue;
      final total = anime.episodesTotal ?? 0;
      final done = s.watched('$prefix${extra[i].$1}').length;
      if (anime.status == 'finished' && total > 0 && done >= total) continue;
      // Titles from other lists (planned, on hold…) do not count as "not in list"
      final inList = user.signedIn && myList.statusOf(extra[i].$1) != null;
      out.add(ContinueItem(
        anime: anime,
        episodeKey: extra[i].$2,
        at: extra[i].$3,
        notInList: !inList,
        watched: done,
        dubCount: dubOf(s, '$prefix${extra[i].$1}').$1,
        dubPrev: dubOf(s, '$prefix${extra[i].$1}').$3,
        dubName: dubOf(s, '$prefix${extra[i].$1}').$2,
      ));
    }
    out.sort((a, b) => b.at.compareTo(a.at));
    return out.take(limit).toList();
  }
}
