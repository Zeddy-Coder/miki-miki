/// "Дивитись": for a Hikka anime gathers what was found in the sources (first Mikai by Hikka slug, the rest by search
/// by titles, remembering the match) and groups episodes by dub / subtitles.
library;

import 'package:flutter/foundation.dart';

import '../models/hikka_models.dart';
import '../models/source_models.dart';
import 'episode_check.dart';
import 'source_registry.dart';
import 'sources/anime_source.dart';
import 'sources/source_http.dart';
import 'sources/title_match.dart';
import 'sources/ua/mikai_source.dart';
import 'watch_models.dart';
import 'storage_service.dart';
import 'watch_store.dart';

/// What to offer when the manually chosen dub has no next episode
class MissingNext {
  final WatchGroup pinned;

  /// The first dub by priority that has the next episode
  final WatchGroup byPriority;

  /// A full dub with the next episode, if it differs from [byPriority]
  final WatchGroup? full;

  const MissingNext({required this.pinned, required this.byPriority, this.full});
}

/// Load progress for one anime page: offers arrive as the sources respond
class WatchLoad extends ChangeNotifier {
  final String animeKey;
  final HikkaEpisodeInfo hikka;
  final List<AnimeSource> order;

  final List<WatchOffer> _offers = [];
  final Map<String, String> _errors = {};
  final Set<String> _pending = {};
  bool _licensed = false;
  MikaiLicense? _license;
  bool _disposed = false;

  /// Where to record how many episodes the chosen dub has (for "Нова серія" in "Продовжити перегляд")
  final WatchStore? store;

  WatchLoad({required this.animeKey, required this.hikka, required this.order, this.store});

  WatchTitle get title => WatchTitle(
        animeKey: animeKey,
        offers: List.unmodifiable(_offers),
        licensed: _licensed,
        license: _license,
        errors: Map.unmodifiable(_errors),
        episodeLimit: (hikka.total ?? 0) > 0 ? hikka.total : null,
      );

  /// Sources still searching
  Set<String> get pending => Set.unmodifiable(_pending);

  bool get busy => _pending.isNotEmpty;

  @visibleForTesting
  void addOfferForTest(WatchOffer o) => _offers.add(o);

  EpisodeCheck checkOf(WatchGroup g) => checkGroup(g, hikka);

  /// The variant for the "Дивитись" button; `null` until anything is found.
  ///
  /// 1. The dub chosen manually for the title ([WatchStore.pinnedGroup]), if it has the next episode.
  /// 2. Otherwise automatically ([_auto]): among dubs with the next episode (by number, not by count), the first by
  ///    team priority, so "Amanogawa 1–9" gives way to "Далі Буде 10–19" as soon as the needed episode exists only there.
  ///    With the [StorageService.getPreferFullDub] switch, full dubs first.
  /// [seen] is how many episodes are already watched (by history or Hikka).
  WatchGroup? defaultGroup(WatchStore store, {int seen = 0}) {
    final groups = title.groups;
    if (groups.isEmpty) return null;
    final pin = store.pinnedGroup(animeKey);
    if (pin != null) {
      for (final g in groups) {
        if (g.id != pin) continue;
        if (_tier(groups, seen).contains(g)) return g;
      }
    }
    return _auto(store, seen);
  }

  /// Dubs to choose from: those with the next episode, otherwise those with anything further, otherwise all
  List<WatchGroup> _tier(List<WatchGroup> groups, int seen) {
    final withNext = [for (final g in groups) if (g.hasEpisode(seen + 1)) g];
    if (withNext.isNotEmpty) return withNext;
    final later = [for (final g in groups) if (g.hasEpisodeAfter(seen)) g];
    return later.isNotEmpty ? later : groups;
  }

  WatchGroup _auto(WatchStore store, int seen, {bool? fullOnly}) {
    final all = title.groups;
    var groups = _tier(all, seen);
    if (fullOnly ?? StorageService.getPreferFullDub()) {
      final maxLast = maxEpisodeOf(all, limit: title.episodeLimit);
      final full = [for (final g in groups) if (!g.isIncomplete(maxLast)) g];
      if (full.isNotEmpty) groups = full;
    }
    return pickGroup(
      groups,
      favorites: store.favoriteChoices,
      priority: StorageService.getWatchTeamPriority(),
      safe: (g) => checkOf(g).syncSafe,
    );
  }

  /// The manually chosen dub has no next episode while others do: what to offer instead.
  /// `null`: nothing to warn about
  MissingNext? missingNext(WatchStore store, {int seen = 0}) {
    final pin = store.pinnedGroup(animeKey);
    if (pin == null) return null;
    final groups = title.groups;
    final pinned = groups.where((g) => g.id == pin).firstOrNull;
    if (pinned == null || pinned.hasEpisode(seen + 1)) return null;
    if (!groups.any((g) => g.hasEpisode(seen + 1))) return null;
    final byPriority = _auto(store, seen, fullOnly: false);
    final full = _auto(store, seen, fullOnly: true);
    return MissingNext(pinned: pinned, byPriority: byPriority, full: full.id == byPriority.id ? null : full);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// The dub the person chose while watching (otherwise the one chosen on the page): how many episodes it has now
  void _recordAvailability() {
    final s = store;
    if (s == null) return;
    final last = s.last(animeKey)?.groupId ?? '';
    final id = last.isNotEmpty ? last : s.preferredGroup(animeKey);
    if (id == null || id.isEmpty) return;
    for (final o in _offers) {
      for (final g in o.groups) {
        if (g.id != id) continue;
        s.setAvailable(animeKey, g.id, g.teamLabel, g.lastNumber?.floor() ?? g.episodes.length);
        return;
      }
    }
  }

  void _begin(String id) => _pending.add(id);

  void _done(String id, {WatchOffer? offer, String? error, bool? licensed, MikaiLicense? license}) {
    if (_disposed) return;
    _pending.remove(id);
    if (offer != null) {
      _offers
        ..removeWhere((o) => o.source.id == id)
        ..add(offer)
        ..sort((a, b) => order.indexOf(a.source).compareTo(order.indexOf(b.source)));
    }
    if (offer != null) {
      StorageService.rememberTeams([for (final g in offer.groups) ...(g.teams.isNotEmpty ? g.teams.map((t) => t.name) : [g.teamLabel])]);
      _recordAvailability();
    }
    if (error != null) _errors[id] = error;
    if (licensed != null) {
      _licensed = licensed;
      _license = license;
    }
    notifyListeners();
  }
}

class WatchService {
  final SourceRegistry registry;
  final WatchStore store;

  WatchService({SourceRegistry? registry, WatchStore? store})
      : registry = registry ?? SourceRegistry.instance,
        store = store ?? WatchStore.instance;

  static WatchService instance = WatchService();

  static String keyOf(HikkaAnime a) => 'hikka:${a.slug}';

  static HikkaEpisodeInfo infoOf(HikkaAnime a) => HikkaEpisodeInfo(
        released: a.episodesReleased,
        total: a.episodesTotal,
        finished: a.status == 'finished',
      );

  /// All Hikka titles (Ukr., Eng., Jap., synonyms) without repeats
  static List<String> titlesOf(HikkaAnime a) {
    final out = <String>[];
    final seen = <String>{};
    for (final t in [a.titleUa, a.titleEn, a.titleJa, a.titleNative, ...a.synonyms]) {
      final s = t?.trim() ?? '';
      if (s.isNotEmpty && seen.add(s.toLowerCase())) out.add(s);
    }
    return out;
  }

  /// Queries for searching sites: Ukr. title, English, Japanese (up to three different ones)
  static List<String> queriesOf(HikkaAnime a) {
    final out = <String>[];
    for (final t in [a.titleUa, a.titleEn, a.titleJa]) {
      final s = t?.trim() ?? '';
      if (s.isNotEmpty && !out.contains(s)) out.add(s);
    }
    return out;
  }

  /// Starts the search in enabled sources. Returns at once; the summary fills up and `WatchLoad` notifies.
  WatchLoad start(HikkaAnime a, {bool searchOthers = true}) {
    final sources = registry.enabled;
    final load = WatchLoad(animeKey: keyOf(a), hikka: infoOf(a), order: registry.all, store: store);
    for (final s in sources) {
      final isMikai = s is MikaiSource;
      if (!isMikai && !searchOthers) continue;
      load._begin(s.id);
      () async {
        try {
          if (s is MikaiSource) {
            await _runMikai(load, s, a);
          } else {
            final offer = await searchOffer(s, a);
            load._done(s.id, offer: offer);
          }
        } on SourceException catch (e) {
          load._done(s.id, error: e.message);
        } catch (e) {
          load._done(s.id, error: 'Не вдалося отримати дані: $e');
        }
      }();
    }
    return load;
  }

  Future<void> _runMikai(WatchLoad load, MikaiSource m, HikkaAnime a) async {
    var anime = await m.byHikka(a.slug);
    if (anime == null && a.malId > 0) anime = await m.byMal(a.malId);
    if (anime == null) {
      load._done(m.id);
      return;
    }
    final p = await m.player(anime);
    final groups = <WatchGroup>[];
    for (final rel in p.releases) {
      final eps = m.episodesOfRelease(rel);
      if (eps.isEmpty) continue;
      groups.add(WatchGroup(
        id: '${m.id}|${anime.url}|${rel.id}',
        sourceId: m.id,
        label: rel.label,
        isSub: rel.isSub,
        teams: rel.teams,
        episodes: eps,
        updatedAt: rel.updatedAt,
      ));
    }
    // order: team priority, dubs first, more episodes first, alphabetically
    final sorted = sortGroups(groups, priority: StorageService.getWatchTeamPriority(), fullFirst: StorageService.getPreferFullDub(), limit: (load.hikka.total ?? 0) > 0 ? load.hikka.total : null);
    load._done(
      m.id,
      offer: WatchOffer(source: m, anime: anime, groups: sorted),
      licensed: p.licensed,
      license: p.license,
    );
  }

  /// Looks for the title on the site by Hikka titles (or takes a remembered match) and gathers its episodes
  Future<WatchOffer?> searchOffer(AnimeSource s, HikkaAnime a) async {
    var linked = store.link(a.slug, s.id);
    if (linked != null) {
      try {
        return await offerFor(s, linked);
      } on SourceException catch (e) {
        if (e.kind != SourceErrorKind.notFound) rethrow;
        store.setLink(a.slug, s.id, null); // the page disappeared or changed address: search anew
        linked = null;
      }
    }
    final candidates = <SAnime>[];
    final seen = <String>{};
    final wanted = titlesOf(a);
    TitleMatch? best;
    for (final q in queriesOf(a)) {
      final page = await s.search(1, q);
      for (final x in page.animes) {
        if (seen.add(x.url)) candidates.add(x);
      }
      best = bestAnimeMatch(wanted, candidates, year: a.year);
      if (best != null) break;
    }
    if (best == null) return null;
    final offer = await offerFor(s, best.anime);
    store.setLink(a.slug, s.id, best.anime);
    return offer;
  }

  /// Episodes of a known source record, grouped by dub
  Future<WatchOffer> offerFor(AnimeSource s, SAnime anime) async {
    final eps = await s.episodes(anime);
    return WatchOffer(source: s, anime: anime, groups: groupEpisodes(s, anime, eps));
  }

  /// Groups episodes by dub. The order is as from the source, episodes within a group by season and number.
  static List<WatchGroup> groupEpisodes(AnimeSource s, SAnime anime, List<SEpisode> eps) {
    final order = <String>[];
    final by = <String, List<SEpisode>>{};
    for (final e in eps) {
      final v = (e.voice ?? '').trim();
      final key = v.isEmpty ? s.name : v;
      if (!by.containsKey(key)) order.add(key);
      by.putIfAbsent(key, () => []).add(e);
    }
    return [
      for (final key in order)
        WatchGroup(
          id: '${s.id}|${anime.url}|$key',
          sourceId: s.id,
          label: key,
          episodes: _sorted(by[key]!),
        ),
    ];
  }

  static List<SEpisode> _sorted(List<SEpisode> list) {
    final idx = {for (int i = 0; i < list.length; i++) list[i]: i};
    final out = List<SEpisode>.of(list);
    out.sort((a, b) {
      final s = (a.season ?? 0).compareTo(b.season ?? 0);
      if (s != 0) return s;
      final an = a.number, bn = b.number;
      if (an != null && bn != null && an != bn) return an.compareTo(bn);
      return idx[a]!.compareTo(idx[b]!);
    });
    return out;
  }
}
