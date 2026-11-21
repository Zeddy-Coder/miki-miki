/// "Дивитись" models: what was found for an anime (dubs / subtitles with episodes) and the episode queue for the player.
/// Pure Dart logic without Flutter.
library;

import '../models/source_models.dart';
import 'sources/anime_source.dart';
import 'episode_check.dart' show looksLikeExtra;
import 'storage_service.dart';
import 'sources/ua/mikai_source.dart';

/// Episode key for progress: "3", "3.5", "s2e5"; without a number, an ordinal ("i7").
String episodeKey(SEpisode e, int index) {
  final n = e.number;
  final num = n == null ? 'i${index + 1}' : (n == n.roundToDouble() ? '${n.toInt()}' : '$n');
  final s = e.season;
  return s == null ? num : 's${s}e$num';
}

/// Episode number for buttons and lists: "3", "3.5"; without a number, an ordinal
String episodeLabel(SEpisode e, int index) {
  final n = e.number;
  if (n == null) return '${index + 1}';
  return n == n.roundToDouble() ? '${n.toInt()}' : '$n';
}

/// «з N» for a dub's episodes ("Серія 14 з 19"): by their numbers, not the list's length (a dub of 10–19 has 10 in
/// its list), and Hikka's [total] when it is more (a dub of 38 of Gintama's 201)
int episodesOfList(Iterable<SEpisode> episodes, {int? total}) {
  var n = episodes.length;
  for (final e in episodes) {
    final x = e.number;
    if (x != null && x == x.roundToDouble() && x > n) n = x.toInt();
  }
  return (total ?? 0) > n ? total! : n;
}

/// One watch variant: a dub or subtitles from a specific team (or a dub from another site)
class WatchGroup {
  /// Stable identifier: `source|anime|release`
  final String id;
  final String sourceId;
  final String label;
  final bool isSub;

  /// Teams (Mikai only): avatars and pages with a description and links
  final List<MikaiTeam> teams;

  /// Episodes in watch order
  final List<SEpisode> episodes;

  /// When the variant was last updated (not every source has it; Mikai provides it)
  final DateTime? updatedAt;

  const WatchGroup({
    required this.id,
    required this.sourceId,
    required this.label,
    required this.episodes,
    this.isSub = false,
    this.teams = const [],
    this.updatedAt,
  });

  /// Team name without the "(суб.)" marker: the kind is shown by an icon
  String get teamLabel => isSub ? label.replaceAll(RegExp(r'\s*\(суб\.\)\s*$'), '') : label;

  String get kindLabel => isSub ? 'Субтитри' : 'Озвучення';

  /// Label with the kind: "Озвучення: Inari" / "Субтитри: Inari". "(суб.)" is removed from the name because the kind is already named
  String get fullLabel => '$kindLabel: ${isSub ? label.replaceAll(RegExp(r'\s*\(суб\.\)\s*$'), '') : label}';

  /// Whether the variant has an episode with the integer number [n] (without numbers, by order). It matters to go by number: a dub with
  /// "10 of 19" may be, for example, episodes 3–12, and then episode 12 can be watched in it
  bool hasEpisode(int n) {
    for (var i = 0; i < episodes.length; i++) {
      final v = episodes[i].number;
      if (v == null ? i + 1 == n : v == n.toDouble()) return true;
    }
    return false;
  }

  /// Whether the variant has an episode with a number greater than [n]
  bool hasEpisodeAfter(int n) {
    for (var i = 0; i < episodes.length; i++) {
      final v = episodes[i].number;
      if (v == null ? i + 1 > n : v > n) return true;
    }
    return false;
  }

  /// Ranges of integer episode numbers in the variant: [(1,5),(7,19)]. Without numbers, by order 1…N
  /// Extra episodes (OVA / special by title) and numbers greater than [limit] (the episode count on Hikka) are not counted
  List<(int, int)> ranges({int? limit}) {
    final nums = <int>{};
    for (var i = 0; i < episodes.length; i++) {
      if (looksLikeExtra(episodes[i].name)) continue;
      final v = episodes[i].number;
      if (v == null) {
        nums.add(i + 1);
      } else if (v == v.roundToDouble() && v >= 0) {
        nums.add(v.toInt());
      }
    }
    final sorted = [for (final n in nums) if (limit == null || limit <= 0 || n <= limit) n]..sort();
    final out = <(int, int)>[];
    for (final n in sorted) {
      if (out.isNotEmpty && out.last.$2 == n - 1) {
        out[out.length - 1] = (out.last.$1, n);
      } else {
        out.add((n, n));
      }
    }
    return out;
  }

  /// Which episodes the variant covers: "1–10", "10–19", "1–5, 7–19"
  String get coverage {
    final r = ranges();
    if (r.isEmpty) return '0';
    return r.map((x) => x.$1 == x.$2 ? '${x.$1}' : '${x.$1}–${x.$2}').join(', ');
  }

  /// A variant not starting from episode 1 or with gaps ranks lower than full ones in order and selection
  bool get isPartial {
    final r = ranges();
    return r.isEmpty || r.length > 1 || r.first.$1 > 1;
  }

  /// An incomplete variant relative to [maxLast], the largest episode number among all variants: not from episode 1,
  /// with gaps or missing the last episodes that others have
  bool isIncomplete(int maxLast) {
    final r = ranges(limit: maxLast);
    return r.length != 1 || r.first.$1 > 1 || r.first.$2 < maxLast;
  }

  /// Number of the last episode, if known
  double? get lastNumber {
    double? best;
    for (final e in episodes) {
      final n = e.number;
      if (n != null && (best == null || n > best)) best = n;
    }
    return best;
  }
}

/// A stable sign of a variant beyond the title: "dub / subtitles" + team. It is used to remember
/// the person's deliberate choice (`WatchStore.favoriteChoice`) so a familiar dub opens in later titles.
String choiceKeyOf(WatchGroup g) {
  final who = g.teams.isNotEmpty
      ? ([for (final t in g.teams) t.id > 0 ? '${t.id}' : t.slug]..sort()).join('+')
      : '${g.sourceId}:${g.label.toLowerCase()}';
  return '${g.isSub ? 's' : 'v'}:$who';
}

/// Which variant to open with the "Дивитись" button when the person did not choose one on the page:
///  1. the one they chose (or watched) for this title, [preferredId];
///  1a. a team from their priority list [priority] (names, the most needed first), even if the numbering does not match
///      Hikka (the ⚠ mark): the person deliberately ranked it higher, and Hikka sync is merely disabled for such a variant;
///  2. the one they deliberately chose in other titles, [favorites] (by [choiceKeyOf], newest first), if it is [safe];
///  3. the first [safe] variant (dubs go before subtitles, more episodes ranks higher);
///  4. otherwise the first. [safe] means "numbering matches Hikka" (not `mismatch`).
WatchGroup pickGroup(
  List<WatchGroup> groups, {
  String? preferredId,
  List<String> favorites = const [],
  List<String> priority = const [],
  bool Function(WatchGroup g)? safe,
}) {
  assert(groups.isNotEmpty);
  bool ok(WatchGroup g) => safe == null || safe(g);
  if (preferredId != null) {
    for (final g in groups) {
      if (g.id == preferredId) return g;
    }
  }
  for (final name in priority) {
    final n = name.trim().toLowerCase();
    if (n.isEmpty) continue;
    for (final g in groups) {
      if (teamMatches(g, n)) return g;
    }
  }
  for (final fav in favorites) {
    for (final g in groups) {
      if (choiceKeyOf(g) == fav && ok(g)) return g;
    }
  }
  for (final g in groups) {
    if (ok(g)) return g;
  }
  return groups.first;
}

/// Whether the variant belongs to the team named [lowerName] (lowercase): matched by the variant's name or its teams
bool teamMatches(WatchGroup g, String lowerName) {
  if (g.teamLabel.toLowerCase().contains(lowerName)) return true;
  return g.teams.any((t) => t.name.toLowerCase().contains(lowerName));
}

/// The largest integer episode number among the variants
///
/// Extra episodes are not counted (OVAs by title, and numbers greater than [limit], the episode count on Hikka):
/// a dub with an extra episode does not make the rest "incomplete"
int maxEpisodeOf(Iterable<WatchGroup> groups, {int? limit}) {
  var m = 0;
  for (final g in groups) {
    final r = g.ranges(limit: limit);
    if (r.isNotEmpty && r.last.$2 > m) m = r.last.$2;
  }
  return m;
}

/// Order of variants in lists: first teams from your priority (in its order), then dubs before
/// subtitles, more episodes ranks higher, and with equal counts alphabetically
/// [fullFirst]: full variants (see [WatchGroup.isIncomplete]) always rank above incomplete ones, wherever those are in the priority.
List<WatchGroup> sortGroups(List<WatchGroup> groups, {List<String> priority = const [], bool fullFirst = false, int? limit}) {
  final maxLast = maxEpisodeOf(groups, limit: limit);
  final names = [for (final n in priority) n.trim().toLowerCase()];
  int rank(WatchGroup g) {
    for (var i = 0; i < names.length; i++) {
      if (names[i].isNotEmpty && teamMatches(g, names[i])) return i;
    }
    return names.length;
  }

  final indexed = groups.asMap().entries.toList();
  indexed.sort((x, y) {
    final a = x.value, b = y.value;
    if (fullFirst) {
      final pa = (a.isIncomplete(maxLast) ? 1 : 0).compareTo(b.isIncomplete(maxLast) ? 1 : 0);
      if (pa != 0) return pa;
    }
    final r = rank(a).compareTo(rank(b));
    if (r != 0) return r;
    final k = (a.isSub ? 1 : 0).compareTo(b.isSub ? 1 : 0);
    if (k != 0) return k;
    final c = b.episodes.length.compareTo(a.episodes.length);
    if (c != 0) return c;
    final l = a.label.toLowerCase().compareTo(b.label.toLowerCase());
    return l != 0 ? l : x.key.compareTo(y.key);
  });
  return [for (final e in indexed) e.value];
}

/// What one source found for an anime
class WatchOffer {
  final AnimeSource source;
  final SAnime anime;
  final List<WatchGroup> groups;

  const WatchOffer({required this.source, required this.anime, required this.groups});

  String get webUrl => source.animeWebUrl(anime);
}

/// Summary for the anime page: source offers + license state
class WatchTitle {
  /// Key for progress: `hikka:<slug>` or `<source>:<address>`
  final String animeKey;
  final List<WatchOffer> offers;

  /// The title is licensed in Ukraine (per Mikai)
  final bool licensed;
  final MikaiLicense? license;

  /// Source errors: source id → a message for the user
  final Map<String, String> errors;

  /// Episode count of the title on Hikka (if known): anything beyond is extra and does not affect dub "completeness"
  final int? episodeLimit;

  const WatchTitle({
    required this.animeKey,
    required this.offers,
    this.licensed = false,
    this.license,
    this.errors = const {},
    this.episodeLimit,
  });

  /// All variants in display order: see [sortGroups]
  List<WatchGroup> get groups => sortGroups([for (final o in offers) ...o.groups], priority: StorageService.getWatchTeamPriority(), fullFirst: StorageService.getPreferFullDub(), limit: episodeLimit);

  bool get isEmpty => groups.isEmpty;

  WatchOffer? offerOf(String sourceId) {
    for (final o in offers) {
      if (o.source.id == sourceId) return o;
    }
    return null;
  }

  WatchGroup? groupById(String id) {
    for (final g in groups) {
      if (g.id == id) return g;
    }
    return null;
  }

  WatchOffer? offerOfGroup(WatchGroup g) => offerOf(g.sourceId);
}

/// An episode in the player queue
class RemoteEntry {
  /// Position and "watched" key: one per episode, regardless of dub
  final String key;
  final String epKey;
  final String title;
  final String sourceId;
  final SEpisode episode;
  final String groupId;

  const RemoteEntry({
    required this.key,
    required this.epKey,
    required this.title,
    required this.sourceId,
    required this.episode,
    required this.groupId,
  });
}

/// Keys of the variant's episodes. Identical numbers (merged parts) must not share marks and position,
/// so a repeat gets the suffix "~2", "~3" …
List<String> episodeKeysOf(WatchGroup group) {
  final out = <String>[];
  final used = <String>{};
  for (int i = 0; i < group.episodes.length; i++) {
    var k = episodeKey(group.episodes[i], i);
    if (!used.add(k)) {
      var n = 2;
      while (!used.add('$k~$n')) {
        n++;
      }
      k = '$k~$n';
    }
    out.add(k);
  }
  return out;
}

/// Where to continue watching the variant from
class ContinuePoint {
  /// Index in the variant's episode list
  final int index;
  final String epKey;

  /// There is history (opened or watched before): the label is "Продовжити", not "Дивитись"
  final bool started;

  /// Everything watched: the label is "Дивитись знову"
  final bool allWatched;

  const ContinuePoint(this.index, this.epKey, {this.started = false, this.allWatched = false});
}

/// Which episode to offer: the last opened (if already watched, the next), otherwise the first unwatched.
/// [keys] are the variant's episode keys ([episodeKeysOf]). [hikkaEpisodes] is how many episodes are marked watched on Hikka:
/// they count as watched even without history in the app (watched on the site or another device).
ContinuePoint continuePoint(List<String> keys, Set<String> watched, String? lastKey, {int hikkaEpisodes = 0}) {
  if (keys.isEmpty) return const ContinuePoint(0, '');
  final upTo = hikkaEpisodes.clamp(0, keys.length);
  final plain = RegExp(r'^(\d+)(?:~\d+)?$');
  // Episodes with plain numbers count as watched by number (a dub may not have all episodes in a row), the rest
  // (seasonal, fractional, without a number) by order
  bool seen(int i) {
    if (watched.contains(keys[i])) return true;
    final m = plain.firstMatch(keys[i]);
    if (m != null) return int.parse(m.group(1)!) <= hikkaEpisodes;
    return i < upTo;
  }
  final li = lastKey == null ? -1 : keys.indexOf(lastKey);
  if (li >= 0) {
    if (seen(li)) {
      for (var j = li + 1; j < keys.length; j++) {
        if (!seen(j)) return ContinuePoint(j, keys[j], started: true);
      }
    }
    return ContinuePoint(li, keys[li], started: true);
  }
  for (var i = 0; i < keys.length; i++) {
    if (!seen(i)) return ContinuePoint(i, keys[i], started: upTo > 0 || watched.any(keys.contains));
  }
  return ContinuePoint(0, keys.first, started: true, allWatched: true);
}

/// The episode queue of one anime in one dub
class RemoteSession {
  final String animeKey;
  final String animeTitle;
  final String? poster;
  final String groupLabel;
  final List<RemoteEntry> entries;

  const RemoteSession({
    required this.animeKey,
    required this.animeTitle,
    required this.entries,
    this.poster,
    this.groupLabel = '',
  });

  /// A queue from a dub: all its episodes, titles "Title — Серія N"
  factory RemoteSession.fromGroup({
    required String animeKey,
    required String animeTitle,
    required WatchGroup group,
    String? poster,
  }) {
    final entries = <RemoteEntry>[];
    final keys = episodeKeysOf(group);
    for (int i = 0; i < group.episodes.length; i++) {
      final e = group.episodes[i];
      final k = keys[i];
      entries.add(RemoteEntry(
        key: '$animeKey#$k',
        epKey: k,
        title: e.name.isEmpty ? 'Серія ${i + 1}' : e.name,
        sourceId: group.sourceId,
        episode: e,
        groupId: group.id,
      ));
    }
    return RemoteSession(animeKey: animeKey, animeTitle: animeTitle, entries: entries, poster: poster, groupLabel: group.label);
  }

  int indexOfKey(String epKey) => entries.indexWhere((e) => e.epKey == epKey);

  /// Title for the player screen: "Title · Серія 3"
  String displayTitle(int index) {
    final t = entries[index].title;
    return animeTitle.isEmpty ? t : '$animeTitle · $t';
  }
}
