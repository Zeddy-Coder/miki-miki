/// «Дивитись»: для аніме з Hikka збирає, що знайдено в джерелах (спершу Mikai за slug Hikka, решту — пошуком
/// за назвами із запамʼятовуванням зіставлення), і групує серії за озвучками / субтитрами.
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
import 'watch_store.dart';

/// Хід завантаження для однієї сторінки аніме: пропозиції надходять у міру відповіді джерел
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

  WatchLoad({required this.animeKey, required this.hikka, required this.order});

  WatchTitle get title => WatchTitle(
        animeKey: animeKey,
        offers: List.unmodifiable(_offers),
        licensed: _licensed,
        license: _license,
        errors: Map.unmodifiable(_errors),
      );

  /// Джерела, які ще шукають
  Set<String> get pending => Set.unmodifiable(_pending);

  bool get busy => _pending.isNotEmpty;

  EpisodeCheck checkOf(WatchGroup g) => checkGroup(g, hikka);

  /// Варіант за кнопкою «Дивитись» (див. [pickGroup]); `null`, поки нічого не знайдено
  WatchGroup? defaultGroup(WatchStore store) {
    final groups = title.groups;
    if (groups.isEmpty) return null;
    return pickGroup(
      groups,
      preferredId: store.preferredGroup(animeKey),
      favorites: store.favoriteChoices,
      safe: (g) => checkOf(g).syncSafe,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
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

  /// Усі назви Hikka (укр., англ., яп., синоніми) без повторів
  static List<String> titlesOf(HikkaAnime a) {
    final out = <String>[];
    final seen = <String>{};
    for (final t in [a.titleUa, a.titleEn, a.titleJa, a.titleNative, ...a.synonyms]) {
      final s = t?.trim() ?? '';
      if (s.isNotEmpty && seen.add(s.toLowerCase())) out.add(s);
    }
    return out;
  }

  /// Запити для пошуку на сайтах: укр. назва, англійська, японська (до трьох різних)
  static List<String> queriesOf(HikkaAnime a) {
    final out = <String>[];
    for (final t in [a.titleUa, a.titleEn, a.titleJa]) {
      final s = t?.trim() ?? '';
      if (s.isNotEmpty && !out.contains(s)) out.add(s);
    }
    return out;
  }

  /// Починає пошук у ввімкнених джерелах. Повертає одразу; підсумок поповнюється, а `WatchLoad` сповіщає.
  WatchLoad start(HikkaAnime a, {bool searchOthers = true}) {
    final sources = registry.enabled;
    final load = WatchLoad(animeKey: keyOf(a), hikka: infoOf(a), order: registry.all);
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
    // озвучення першими, а в межах виду — де серій більше
    final indexed = groups.asMap().entries.toList()
      ..sort((x, y) {
        final k = (x.value.isSub ? 1 : 0).compareTo(y.value.isSub ? 1 : 0);
        if (k != 0) return k;
        final c = y.value.episodes.length.compareTo(x.value.episodes.length);
        return c != 0 ? c : x.key.compareTo(y.key);
      });
    load._done(
      m.id,
      offer: WatchOffer(source: m, anime: anime, groups: [for (final e in indexed) e.value]),
      licensed: p.licensed,
      license: p.license,
    );
  }

  /// Шукає тайтл на сайті за назвами Hikka (або бере запамʼятоване зіставлення) і збирає його серії
  Future<WatchOffer?> searchOffer(AnimeSource s, HikkaAnime a) async {
    var linked = store.link(a.slug, s.id);
    if (linked != null) {
      try {
        return await offerFor(s, linked);
      } on SourceException catch (e) {
        if (e.kind != SourceErrorKind.notFound) rethrow;
        store.setLink(a.slug, s.id, null); // сторінка зникла чи змінила адресу — шукаємо наново
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

  /// Серії відомого запису джерела, згруповані за озвучками
  Future<WatchOffer> offerFor(AnimeSource s, SAnime anime) async {
    final eps = await s.episodes(anime);
    return WatchOffer(source: s, anime: anime, groups: groupEpisodes(s, anime, eps));
  }

  /// Групує серії за озвучкою. Порядок — як з джерела, серії всередині групи — за сезоном і номером.
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
