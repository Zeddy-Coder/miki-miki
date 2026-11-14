/// Mikai (mikai.me) — українська база аніме з озвучками й субтитрами від команд. Працює через публічний API
/// (api.mikai.me/public/v1), а не через розбір сторінок: каталог, команди (з аватарами й посиланнями),
/// серії та готові адреси плеєрів. Приймає `hikka:<slug>` — тож аніме з Hikka зіставляється без вгадування назв.
library;

import 'dart:convert';

import '../../../constants/app_identity.dart';
import '../../../models/source_models.dart';
import '../../storage_service.dart';
import '../anime_source.dart';
import '../extractors.dart';
import '../source_http.dart';

class MikaiTeam {
  final int id;
  final String slug;
  final String name;
  final String? avatarUrl;

  const MikaiTeam(this.id, this.slug, this.name, [this.avatarUrl]);
}

/// Подробиці про команду озвучення / субтитрів
class MikaiTeamInfo {
  final MikaiTeam team;
  final String? description;
  final DateTime? birthday;

  /// Посилання на соцмережі команди: `telegram`, `youtube`, `instagram` …
  final Map<String, String> links;
  final bool hasVoice;
  final bool hasSubs;
  final int animeCount;
  final int viewsTotal;

  const MikaiTeamInfo(
    this.team, {
    this.description,
    this.birthday,
    this.links = const {},
    this.hasVoice = false,
    this.hasSubs = false,
    this.animeCount = 0,
    this.viewsTotal = 0,
  });

  String get pageUrl => 'https://mikai.me/team/${team.slug}';
}

class MikaiEmbed {
  final String provider;
  final String url;

  const MikaiEmbed(this.provider, this.url);
}

class MikaiEpisode {
  final double number;
  final String label;

  /// mangaCanon / animeCanon / filler / mixed
  final String kind;
  final DateTime? addedAt;
  final List<MikaiEmbed> embeds;

  const MikaiEpisode(this.number, this.label, this.kind, this.addedAt, this.embeds);
}

/// Один реліз = команда (або колаборація) + доріжка: озвучення чи субтитри
class MikaiRelease {
  final String id;
  final bool isSub;
  final bool isCollab;
  final List<MikaiTeam> teams;
  final int episodesCount;
  final double lastEpisode;
  final DateTime? updatedAt;
  final List<MikaiEpisode> episodes;

  const MikaiRelease({
    required this.id,
    required this.isSub,
    required this.isCollab,
    required this.teams,
    required this.episodesCount,
    required this.lastEpisode,
    required this.updatedAt,
    required this.episodes,
  });

  String get teamsName => teams.map((t) => t.name).join(' + ');

  /// Підпис для вибору: «FanVoxUA» або «Inari (суб.)»
  String get label => isSub ? '$teamsName (суб.)' : teamsName;
}

/// Ліцензований в Україні тайтл: джерел немає, лише куди дивитися легально
class MikaiLicense {
  final String? holder;
  final List<({String title, String url})> links;

  const MikaiLicense(this.holder, this.links);
}

class MikaiPlayer {
  final bool licensed;
  final MikaiLicense? license;
  final List<MikaiRelease> releases;

  const MikaiPlayer(this.licensed, this.license, this.releases);
}

class _Cached<T> {
  final T value;
  final DateTime expires;
  const _Cached(this.value, this.expires);
}

class MikaiSource extends HttpAnimeSource {
  MikaiSource({super.http, this.apiKey, DateTime Function()? now}) : _now = now ?? DateTime.now;

  /// Необовʼязковий ключ API (300 запитів/хв замість 60); можна змінити під час роботи
  String? apiKey;
  final DateTime Function() _now;

  static const String apiBase = 'https://api.mikai.me/public/v1';
  static const int pageSize = 24;

  @override
  String get id => 'mikai';
  @override
  String get name => 'Mikai';
  @override
  String get lang => 'uk';
  @override
  String get baseUrl => 'https://mikai.me';
  @override
  String get about => 'Каталог українських озвучок і субтитрів від команд — серії одразу зіставляються з Hikka';

  // ── Запити до API ───────────────────────────────────────────────────────────────

  final Map<String, _Cached<Map<String, dynamic>>> _cache = {};
  final Map<String, Future<Map<String, dynamic>>> _inflight = {};

  /// Скинути кеш відповідей
  void clearCache() => _cache.clear();

  Future<Map<String, dynamic>> api(String path, {Map<String, String>? query, Duration ttl = const Duration(minutes: 3)}) {
    final qs = query == null || query.isEmpty ? '' : '?${query.entries.map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}').join('&')}';
    final key = '$path$qs';
    final hit = _cache[key];
    if (hit != null && hit.expires.isAfter(_now())) return Future.value(hit.value);
    final running = _inflight[key];
    if (running != null) return running;
    final fut = _fetch('$apiBase$path$qs').then((v) {
      _cache[key] = _Cached(v, _now().add(ttl));
      return v;
    });
    _inflight[key] = fut;
    fut.then<void>((_) {
      _inflight.remove(key);
    }, onError: (Object _) {
      _inflight.remove(key);
    });
    return fut;
  }

  Future<Map<String, dynamic>> _fetch(String url) async {
    final res = await http.get(
      url,
      headers: {
        'Accept': 'application/json',
        'User-Agent': AppIdentity.userAgent('personal media player'),
        if (apiKey != null && apiKey!.isNotEmpty) 'X-API-Key': apiKey!,
      },
      throwOnError: false,
    );
    Object? body;
    try {
      body = jsonDecode(res.text);
    } on FormatException {
      body = null;
    }
    if (res.status == 404) throw SourceException(SourceErrorKind.notFound, 'Mikai ${res.url}', status: 404);
    if (res.status == 429) throw SourceException(SourceErrorKind.rateLimited, 'Mikai ${res.url}', status: 429);
    if (res.status >= 500) throw SourceException(SourceErrorKind.server, 'Mikai ${res.url} → ${res.status}', status: res.status);
    if (body is! Map<String, dynamic> || body['ok'] != true) {
      final code = body is Map ? ((body['error'] as Map?)?['code'] ?? '') : '';
      if (code == 'not_found') throw SourceException(SourceErrorKind.notFound, 'Mikai ${res.url}', status: res.status);
      if (code == 'rate_limited') throw SourceException(SourceErrorKind.rateLimited, 'Mikai ${res.url}', status: res.status);
      throw SourceException(SourceErrorKind.badResponse, 'Mikai ${res.url} → ${res.status} $code', status: res.status);
    }
    return body;
  }

  // ── Розбір карток ───────────────────────────────────────────────────────────────

  static String? _image(Object? images, String slot, String size) {
    final m = images is Map ? images[slot] : null;
    final s = m is Map ? m[size] : null;
    if (s is! Map) return null;
    return (s['webp'] ?? s['jpg']) as String?;
  }

  static String? _posterOf(Object? images, String size) {
    if (images is Map) {
      final ua = images['uaPoster'];
      if (ua is Map && ua['images'] is Map) {
        final u = (ua['images'] as Map)[size];
        if (u is Map && (u['webp'] ?? u['jpg']) != null) return (u['webp'] ?? u['jpg']) as String;
      }
    }
    return _image(images, 'poster', size);
  }

  static SAnimeStatus _status(Object? s) => switch (s) {
        'ongoing' => SAnimeStatus.ongoing,
        'finished' => SAnimeStatus.completed,
        'cancelled' => SAnimeStatus.cancelled,
        'break' => SAnimeStatus.onHiatus,
        _ => SAnimeStatus.unknown,
      };

  /// Картка зі списку (`/anime`) або повний запис (`/anime/{ref}`) → `SAnime`
  static SAnime animeFromJson(Map<dynamic, dynamic> j, {String posterSize = 'small'}) {
    final ids = (j['ids'] as Map?) ?? const {};
    final titles = (j['titles'] as Map?) ?? const {};
    final ua = (titles['ua'] as String?)?.trim();
    final en = (titles['english'] as String?)?.trim();
    final orig = (titles['original'] as String?)?.trim();
    final title = (ua != null && ua.isNotEmpty) ? ua : (en != null && en.isNotEmpty ? en : (orig ?? ''));
    final alt = (orig != null && orig.isNotEmpty && orig != title) ? orig : ((en != null && en.isNotEmpty && en != title) ? en : null);
    final eps = j['episodes'];
    int? aired, total;
    if (eps is Map) {
      aired = (eps['aired'] as num?)?.toInt();
      total = (eps['total'] as num?)?.toInt();
    } else if (eps is num) {
      total = eps.toInt();
    }
    final genres = (j['genres'] as List?)?.map((g) => g is Map ? (g['ua'] ?? g['name']) : g).whereType<String>().toList() ?? const <String>[];
    final studio = j['studio'];
    return SAnime(
      url: '${ids['mikai']}',
      title: title,
      originalTitle: alt,
      thumbnailUrl: _posterOf(j['images'], posterSize),
      description: (j['description'] as String?)?.trim(),
      author: studio is String && studio.isNotEmpty ? studio : null,
      genres: genres,
      status: _status(j['status']),
      year: (j['year'] as num?)?.toInt(),
      episodesAired: aired,
      episodesTotal: total,
    );
  }

  static MikaiTeam teamFromJson(Map<dynamic, dynamic> t) => MikaiTeam(
        (t['id'] as num?)?.toInt() ?? 0,
        (t['slug'] as String?) ?? '',
        (t['name'] as String?) ?? '',
        _image(t, 'avatar', 'small'),
      );

  static DateTime? _date(Object? s) => s is String ? DateTime.tryParse(s) : null;

  static MikaiPlayer playerFromJson(Map<String, dynamic> body) {
    final r = (body['result'] as Map?) ?? const {};
    final releases = <MikaiRelease>[];
    for (final rel in (r['releases'] as List? ?? const [])) {
      if (rel is! Map) continue;
      final eps = <MikaiEpisode>[];
      for (final e in (rel['episodes'] as List? ?? const [])) {
        if (e is! Map) continue;
        final embeds = <MikaiEmbed>[
          for (final s in (e['sources'] as List? ?? const []))
            if (s is Map && s['embedUrl'] is String) MikaiEmbed('${s['provider']}', s['embedUrl'] as String),
        ];
        eps.add(MikaiEpisode(
          (e['number'] as num?)?.toDouble() ?? 0,
          '${e['label'] ?? e['number'] ?? ''}',
          '${e['kind'] ?? ''}',
          _date(e['addedAt']),
          embeds,
        ));
      }
      releases.add(MikaiRelease(
        id: '${rel['id']}',
        isSub: rel['kind'] == 'sub',
        isCollab: rel['isCollab'] == true,
        teams: [for (final t in (rel['teams'] as List? ?? const [])) if (t is Map) teamFromJson(t)],
        episodesCount: (rel['episodesCount'] as num?)?.toInt() ?? eps.length,
        lastEpisode: (rel['lastEpisode'] as num?)?.toDouble() ?? 0,
        updatedAt: _date(rel['updatedAt']),
        episodes: eps,
      ));
    }
    return MikaiPlayer(r['licensed'] == true, _licenseFrom(r['license']), releases);
  }

  /// Блок ліцензії (формат у документації не описано) — беремо назву власника й усі посилання, що знайдемо
  static MikaiLicense? _licenseFrom(Object? raw) {
    if (raw == null) return null;
    String? holder;
    final links = <({String title, String url})>[];
    void walk(Object? v, String key) {
      if (v is String) {
        if (v.startsWith('http')) {
          links.add((title: key.isEmpty ? v : key, url: v));
        } else if (holder == null && v.isNotEmpty && (key == 'licensee' || key == 'holder' || key == 'name' || key == 'company')) {
          holder = v;
        }
      } else if (v is Map) {
        final label = (v['title'] ?? v['name'] ?? v['label'] ?? v['platform'] ?? v['provider'] ?? '') as Object;
        v.forEach((k, x) {
          if (x is String && x.startsWith('http')) {
            links.add((title: label.toString().isEmpty ? '$k' : label.toString(), url: x));
          } else {
            walk(x, '$k');
          }
        });
      } else if (v is List) {
        for (final x in v) {
          walk(x, key);
        }
      }
    }

    walk(raw, '');
    final seen = <String>{};
    links.retainWhere((l) => seen.add(l.url));
    return MikaiLicense(holder, links);
  }

  // ── Каталог ─────────────────────────────────────────────────────────────────────

  Future<SAnimePage> _catalog(int page, Map<String, String> extra) async {
    final body = await api('/anime', query: {'page': '$page', 'limit': '$pageSize', ...extra}, ttl: const Duration(minutes: 3));
    final list = (body['result'] as List? ?? const []).whereType<Map>().map((m) => animeFromJson(m)).toList();
    final pages = (body['pages'] as num?)?.toInt() ?? 1;
    return SAnimePage(list.where((a) => a.url != 'null' && a.title.isNotEmpty).toList(), page < pages);
  }

  @override
  Future<SAnimePage> popular(int page) => _catalog(page, {'sort': 'views', 'order': 'desc'});

  @override
  Future<SAnimePage> latest(int page) => _catalog(page, {'sort': 'updated', 'order': 'desc'});

  @override
  Future<SAnimePage> search(int page, String query) => _catalog(page, {'search': query});

  @override
  Future<SAnime> details(SAnime anime) async {
    final body = await api('/anime/${anime.url}');
    final r = body['result'];
    if (r is! Map) throw const SourceException(SourceErrorKind.badResponse, 'Mikai: порожній запис');
    return anime.mergedWith(animeFromJson(r, posterSize: 'medium'));
  }

  /// Аніме з Hikka → запис Mikai; `null`, якщо Mikai такого не знає
  Future<SAnime?> byHikka(String hikkaSlug) async {
    try {
      final body = await api('/anime/hikka:${Uri.encodeComponent(hikkaSlug)}', ttl: const Duration(minutes: 10));
      final r = body['result'];
      if (r is! Map) return null;
      return animeFromJson(r, posterSize: 'medium');
    } on SourceException catch (e) {
      if (e.kind == SourceErrorKind.notFound) return null;
      rethrow;
    }
  }

  /// Те саме за MAL-id (запасний шлях, якщо slug Hikka ще не потрапив у Mikai)
  Future<SAnime?> byMal(int malId) async {
    try {
      final body = await api('/anime/mal:$malId', ttl: const Duration(minutes: 10));
      final r = body['result'];
      return r is Map ? animeFromJson(r, posterSize: 'medium') : null;
    } on SourceException catch (e) {
      if (e.kind == SourceErrorKind.notFound) return null;
      rethrow;
    }
  }

  @override
  String animeWebUrl(SAnime anime) => '$baseUrl/anime/${anime.url}';

  // ── Команди ─────────────────────────────────────────────────────────────────────

  /// Одна сторінка команд озвучення (`GET /teams`, без ключа), найпопулярніші (за кількістю тайтлів) першими.
  /// Повертає й ознаку «далі є ще»
  Future<(List<MikaiTeam>, bool)> teamsPage({int page = 1, int limit = 50, String search = ''}) async {
    final q = search.trim();
    final body = await api(
      '/teams',
      query: {'haveVoice': 'true', 'limit': '$limit', 'page': '$page', if (q.isEmpty) ...{'sort': 'count', 'order': 'desc'} else 'search': q},
      ttl: const Duration(hours: 1),
    );
    final raw = (body['result'] as List? ?? const []);
    final list = [for (final t in raw) if (t is Map) teamFromJson(t)].where((t) => t.name.isNotEmpty).toList();
    final pages = (body['pages'] as num?)?.toInt();
    final more = pages != null ? page < pages : raw.length >= limit;
    return (list, more);
  }

  /// Перша сторінка команд (для коротких запитів і тестів)
  Future<List<MikaiTeam>> teams({String search = '', int limit = 50}) async => (await teamsPage(limit: limit, search: search)).$1;

  static const String teamsSection = 'mikai_teams';
  static const Duration teamsMaxAge = Duration(hours: 24);

  /// Усі команди озвучення Mikai: зі збереженого списку на диску, а коли він застарів (доба) — перезавантажує всі сторінки
  /// й зберігає. Без мережі повертає застарілий список, якщо він є. Аватарки кешує віджет зображень.
  Future<List<MikaiTeam>> allTeams({bool refresh = false}) async {
    final cached = _readTeams();
    if (!refresh && cached != null && _now().difference(cached.$1) < teamsMaxAge) return cached.$2;
    try {
      final all = <MikaiTeam>[];
      final seen = <int>{};
      for (var page = 1; page <= 60; page++) {
        final (list, more) = await teamsPage(page: page);
        for (final t in list) {
          if (seen.add(t.id > 0 ? t.id : t.slug.hashCode)) all.add(t);
        }
        if (!more || list.isEmpty) break;
      }
      if (all.isNotEmpty) {
        _writeTeams(all);
        return all;
      }
    } catch (_) {
      if (cached != null) return cached.$2;
      rethrow;
    }
    return cached?.$2 ?? const [];
  }

  (DateTime, List<MikaiTeam>)? _readTeams() {
    try {
      final d = StorageService.getSection(teamsSection);
      final l = d['list'];
      if (l is! List || l.isEmpty) return null;
      return (
        DateTime.fromMillisecondsSinceEpoch((d['at'] as num?)?.toInt() ?? 0),
        [for (final x in l) if (x is Map) MikaiTeam((x['i'] as num?)?.toInt() ?? 0, (x['s'] as String?) ?? '', (x['n'] as String?) ?? '', x['a'] as String?)],
      );
    } catch (_) {
      return null;
    }
  }

  void _writeTeams(List<MikaiTeam> all) {
    try {
      StorageService.saveSection(teamsSection, {
        'at': _now().millisecondsSinceEpoch,
        'list': [for (final t in all) {'i': t.id, 's': t.slug, 'n': t.name, if (t.avatarUrl != null) 'a': t.avatarUrl}],
      });
    } catch (_) {}
  }

  Future<MikaiTeamInfo> teamInfo(MikaiTeam team) async {
    final body = await api('/teams/${team.id > 0 ? team.id : team.slug}', ttl: const Duration(hours: 1));
    final r = (body['result'] as Map?) ?? const {};
    final links = <String, String>{};
    final rawLinks = r['links'];
    if (rawLinks is Map) {
      rawLinks.forEach((k, v) {
        if (v is String && v.startsWith('http')) links['$k'] = v;
      });
    }
    final views = r['views'];
    return MikaiTeamInfo(
      teamFromJson(r),
      description: (r['description'] as String?)?.trim(),
      birthday: _date(r['birthday']),
      links: links,
      hasVoice: r['hasVoice'] == true,
      hasSubs: r['hasSubs'] == true,
      animeCount: (r['animeCount'] as num?)?.toInt() ?? 0,
      viewsTotal: views is Map ? ((views['total'] as num?)?.toInt() ?? 0) : 0,
    );
  }

  // ── Серії ───────────────────────────────────────────────────────────────────────

  /// Релізи й серії тайтлу (кеш на кілька хвилин)
  Future<MikaiPlayer> player(SAnime anime) async {
    final body = await api('/anime/${anime.url}/player', ttl: const Duration(minutes: 3));
    return playerFromJson(body);
  }

  static String _episodeName(MikaiEpisode e) {
    final l = e.label.trim();
    if (l.isEmpty) return 'Серія ${_num(e.number)}';
    if (RegExp(r'^\d+(\.\d+)?$').hasMatch(l)) return 'Серія $l';
    return l;
  }

  static String _num(double n) => n == n.roundToDouble() ? '${n.toInt()}' : '$n';

  /// Серії одного релізу, які є чим відтворити (серії лише з Fenix / Tortuga пропускаються).
  /// `voice` — підпис релізу, `data` — JSON з усіма плеєрами серії.
  List<SEpisode> episodesOfRelease(MikaiRelease rel) {
    final out = <SEpisode>[];
    for (final e in rel.episodes) {
      final embeds = [for (final m in e.embeds) EmbedLink(m.provider, m.url)];
      final playable = [for (final m in embeds) if (VideoExtractors.forUrl(m.url) != null) m];
      if (playable.isEmpty) continue; // лише Fenix / Tortuga — відтворити нічим
      out.add(SEpisode(
        url: playable.first.url,
        name: _episodeName(e),
        number: e.number,
        voice: rel.label,
        date: e.addedAt,
        data: encodeEmbeds(embeds, extra: {'r': rel.id, if (e.kind.isNotEmpty) 'k': e.kind}),
      ));
    }
    out.sort((a, b) => (a.number ?? 0).compareTo(b.number ?? 0));
    return out;
  }

  /// Плаский перелік серій за всіма релізами
  List<SEpisode> flatten(MikaiPlayer p) => [for (final rel in p.releases) ...episodesOfRelease(rel)];

  @override
  Future<List<SEpisode>> episodes(SAnime anime) async {
    final p = await player(anime);
    final list = flatten(p);
    list.sort((a, b) {
      final v = (a.voice ?? '').compareTo(b.voice ?? '');
      return v != 0 ? v : (a.number ?? 0).compareTo(b.number ?? 0);
    });
    return list;
  }

  @override
  Future<List<Hoster>> hosters(SEpisode episode) async => hostersFor(episode);

  @override
  Future<List<Video>> hosterVideos(Hoster hoster) => hosterVideosOf(http, hoster, referer: '$baseUrl/');

  /// Відео серії: пробуємо плеєри за порядком, перший, що дав відео, виграє
  @override
  Future<List<Video>> videos(SEpisode episode) => videosOfEpisode(http, episode, referer: '$baseUrl/');
}
