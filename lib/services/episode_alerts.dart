/// "New episode released" notifications: the Mikai releases feed (`GET /updates`) is matched against the titles the person watches
/// and the dub (team) they chose for each. Episodes by other teams, and "just aired in Japan", do not count.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'continue_watching.dart';
import 'source_registry.dart';
import 'storage_service.dart';
import 'system_controls.dart';
import 'watch_store.dart';

/// One notification: episode [episode] of title [slug] came out in the dub or subtitles of team [teamName]
class EpisodeAlert {
  final String id;
  final String slug;
  final String title;
  final String? image;
  final int episode;
  final String teamName;

  /// `voice` is dubbing, `sub` is subtitles
  final String kind;
  final DateTime at;
  final bool read;

  /// Pinned entries stay at the top and are never trimmed away
  final bool pinned;

  /// `episode` (a new episode), or a message pushed by the developer: `news` / `update` (then [body] is the text)
  final String type;
  final String body;

  const EpisodeAlert({
    required this.id,
    required this.slug,
    required this.title,
    required this.episode,
    required this.teamName,
    required this.at,
    this.image,
    this.kind = 'voice',
    this.read = false,
    this.pinned = false,
    this.type = 'episode',
    this.body = '',
  });

  bool get isSub => kind == 'sub';
  bool get isEpisode => type == 'episode';

  /// "Вийшла серія 7" (for a message from the developer, its text)
  String get headline => isEpisode ? 'Вийшла серія $episode' : body;

  /// "Озвучення: Togarashi" / "Субтитри: Togarashi"
  String get dubLine => '${isSub ? 'Субтитри' : 'Озвучення'}: $teamName';

  EpisodeAlert copyWith({bool? read, bool? pinned}) => EpisodeAlert(
        id: id,
        slug: slug,
        title: title,
        image: image,
        episode: episode,
        teamName: teamName,
        kind: kind,
        at: at,
        read: read ?? this.read,
        pinned: pinned ?? this.pinned,
        type: type,
        body: body,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'slug': slug,
        'title': title,
        if (image != null) 'image': image,
        'ep': episode,
        'team': teamName,
        'kind': kind,
        't': at.millisecondsSinceEpoch,
        if (read) 'read': true,
        if (pinned) 'pin': true,
        if (!isEpisode) 'type': type,
        if (body.isNotEmpty) 'body': body,
      };

  static EpisodeAlert? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'];
    final slug = j['slug'];
    if (id is! String || slug is! String) return null;
    final type = (j['type'] as String?) ?? 'episode';
    return EpisodeAlert(
      id: id,
      slug: slug,
      title: (j['title'] as String?) ?? slug,
      image: j['image'] as String?,
      episode: (j['ep'] as num?)?.toInt() ?? 0,
      teamName: (j['team'] as String?) ?? '',
      kind: (j['kind'] as String?) ?? 'voice',
      at: DateTime.fromMillisecondsSinceEpoch((j['t'] as num?)?.toInt() ?? 0),
      read: j['read'] == true,
      pinned: j['pin'] == true,
      type: type,
      body: (j['body'] as String?) ?? '',
    );
  }
}

/// A feed page: the records and the total number of pages
typedef UpdatesFetch = Future<(List<Map<String, dynamic>>, int)> Function(DateTime since, int page);

class EpisodeAlerts extends ChangeNotifier {
  static const String section = 'episode_alerts';
  static const int maxItems = 100;

  /// How many feed pages (100 records each) we scan per check
  static const int maxPages = 6;

  /// The first check takes releases from the last two days so notifications do not appear "from zero"
  static const Duration firstLookback = Duration(hours: 48);

  final SectionLoader _load;
  final SectionSaver _save;
  final DateTime Function() _now;
  final UpdatesFetch _fetch;
  final WatchStore Function() _store;

  late final Map<String, dynamic> _data = _fresh(_load());
  bool _checking = false;
  DateTime? _lastRun;

  EpisodeAlerts({SectionLoader? load, SectionSaver? save, DateTime Function()? now, UpdatesFetch? fetch, WatchStore? store})
      : _load = load ?? (() => StorageService.getSection(section)),
        _save = save ?? ((d) => StorageService.saveSection(section, d)),
        _now = now ?? DateTime.now,
        _fetch = fetch ?? _mikaiFetch,
        _store = (() => store ?? WatchStore.instance);

  static EpisodeAlerts instance = EpisodeAlerts();

  static Map<String, dynamic> _fresh(Map<String, dynamic> src) => {
        'items': [if (src['items'] is List) ...(src['items'] as List)],
        if (src['since'] is num) 'since': src['since'],
        'dismissed': [if (src['dismissed'] is List) ...(src['dismissed'] as List)],
      };

  /// Mikai feed: `since` is RFC3339; an empty result is not an error
  static Future<(List<Map<String, dynamic>>, int)> _mikaiFetch(DateTime since, int page) async {
    final m = SourceRegistry.instance.mikai;
    if (m == null) return (const <Map<String, dynamic>>[], 0);
    final body = await m.api(
      '/updates',
      query: {'since': since.toUtc().toIso8601String(), 'limit': '100', 'page': '$page'},
      ttl: Duration.zero,
    );
    final list = [
      if (body['result'] is List)
        for (final x in body['result'] as List)
          if (x is Map<String, dynamic>) x,
    ];
    return (list, (body['pages'] as num?)?.toInt() ?? 0);
  }

  List<EpisodeAlert> get items {
    final out = <EpisodeAlert>[
      for (final j in (_data["items"] as List)) if (EpisodeAlert.fromJson(j) case final a?) a,
    ];
    // Pinned first, then the newest
    out.sort((a, b) => a.pinned != b.pinned ? (a.pinned ? -1 : 1) : b.at.compareTo(a.at));
    return out;
  }

  int get unread => items.where((a) => !a.read).length;

  bool get checking => _checking;

  void _commit() {
    _save(_data);
    notifyListeners();
  }

  void _replace(List<EpisodeAlert> list) {
    // Pinned entries are always kept; the rest are the newest ones that fit
    final pinned = list.where((a) => a.pinned).toList();
    final rest = (list.where((a) => !a.pinned).toList()..sort((a, b) => b.at.compareTo(a.at))).take(maxItems > pinned.length ? maxItems - pinned.length : 0);
    _data['items'] = [for (final a in [...pinned, ...rest]) a.toJson()];
  }

  void markRead(String id) {
    final list = items;
    final i = list.indexWhere((a) => a.id == id);
    if (i < 0 || list[i].read) return;
    list[i] = list[i].copyWith(read: true);
    _replace(list);
    _commit();
  }

  void markAllRead() {
    final list = items;
    if (list.every((a) => a.read)) return;
    _replace([for (final a in list) a.copyWith(read: true)]);
    _commit();
  }

  /// Ids of notifications the person deleted: neither the feed check nor the push inbox brings them back
  Set<String> get _dismissed => {for (final x in (_data['dismissed'] as List)) '$x'};

  /// Deletes one notification (it does not come back when the same episode is found again)
  void remove(String id) {
    final list = items;
    if (!list.any((a) => a.id == id)) return;
    _replace([for (final a in list) if (a.id != id) a]);
    final d = [..._dismissed.where((x) => x != id), id];
    _data['dismissed'] = d.length > 300 ? d.sublist(d.length - 300) : d;
    _commit();
  }

  void togglePin(String id) {
    final list = items;
    final i = list.indexWhere((a) => a.id == id);
    if (i < 0) return;
    list[i] = list[i].copyWith(pinned: !list[i].pinned);
    _replace(list);
    _commit();
  }

  void clear() {
    if ((_data['items'] as List).isEmpty) return;
    _data['items'] = <dynamic>[];
    _commit();
  }

  /// Takes the pushes the native service has received (Android) into the list, so every push - a new episode, a message from the
  /// developer, a manual test - is kept on the "Сповіщення" tab. Returns how many new entries there are. A repeat of an entry
  /// (the same id, e.g. an episode that the feed check also found) is not added twice.
  Future<int> importInbox({Future<String?> Function()? source}) async {
    final String? raw;
    try {
      raw = await (source ?? SystemControls.pushInbox)();
    } catch (_) {
      return 0;
    }
    if (raw == null || raw.isEmpty) return 0;
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return 0;
    }
    if (decoded is! List || decoded.isEmpty) return 0;
    final known = {for (final a in items) a.id: a};
    final dismissed = _dismissed;
    var added = 0;
    for (final x in decoded) {
      if (x is! Map) continue;
      final type = '${x['type'] ?? 'episode'}';
      final slug = '${x['slug'] ?? ''}';
      final title = '${x['title'] ?? ''}';
      if (title.isEmpty) continue;
      final id = '${x['id'] ?? ''}'.isNotEmpty ? '${x['id']}' : 'push|${x['t']}';
      if (known.containsKey(id) || dismissed.contains(id)) continue;
      final image = '${x['image'] ?? ''}';
      known[id] = EpisodeAlert(
        id: id,
        slug: slug,
        title: title,
        image: image.startsWith('https://') ? image : null,
        episode: int.tryParse('${x['episode'] ?? ''}') ?? 0,
        teamName: '${x['team'] ?? ''}',
        kind: '${x['kind'] ?? ''}'.isEmpty ? 'voice' : '${x['kind']}',
        at: DateTime.fromMillisecondsSinceEpoch((x['t'] as num?)?.toInt() ?? _now().millisecondsSinceEpoch),
        type: const ['episode', 'news', 'update'].contains(type) ? type : 'news',
        body: '${x['body'] ?? ''}',
      );
      added++;
    }
    if (added == 0) return 0;
    _replace(known.values.toList()..sort((a, b) => b.at.compareTo(a.at)));
    _commit();
    return added;
  }

  /// Titles we follow: `Hikka slug → Mikai release id` (the team chosen by the person: manually, in the player, or the last one).
  /// Titles with dubs from other sites do not appear here.
  Map<String, String> tracked() {
    final s = _store();
    final out = <String, String>{};
    for (final key in s.recentTitles(limit: 400)) {
      if (!key.startsWith(ContinueWatching.prefix)) continue;
      final slug = key.substring(ContinueWatching.prefix.length);
      final last = s.last(key)?.groupId ?? '';
      final gid = s.pinnedGroup(key) ?? (last.isNotEmpty ? last : s.preferredGroup(key));
      if (gid == null || !gid.startsWith('mikai|')) continue;
      final rel = gid.split('|').last;
      if (slug.isNotEmpty && rel.isNotEmpty) out[slug] = rel;
    }
    return out;
  }

  static String? _poster(Object? images) {
    final p = images is Map ? images['poster'] : null;
    for (final size in const ['medium', 'big', 'small']) {
      final s = p is Map ? p[size] : null;
      if (s is Map) {
        final url = s['jpg'] ?? s['webp'];
        if (url is String && url.isNotEmpty) return url;
      }
    }
    return null;
  }

  /// Looks at the new releases feed. At most once per [minGap] unless [force]. Returns how many new notifications there are.
  Future<int> check({bool force = false, Duration minGap = const Duration(minutes: 10)}) async {
    if (_checking) return 0;
    final now = _now();
    if (!force && _lastRun != null && now.difference(_lastRun!) < minGap) return 0;
    _checking = true;
    try {
      final since = _data['since'] is num
          ? DateTime.fromMillisecondsSinceEpoch((_data['since'] as num).toInt())
          : now.subtract(firstLookback);
      final watch = tracked();
      final known = {for (final a in items) a.id: a};
      final dismissed = _dismissed;
      final fresh = <String, EpisodeAlert>{};
      var added = 0;
      if (watch.isNotEmpty) {
        var pages = 1;
        for (var page = 1; page <= pages && page <= maxPages; page++) {
          final (rows, total) = await _fetch(since, page);
          pages = total;
          for (final r in rows) {
            final anime = r['anime'];
            final ids = anime is Map ? anime['ids'] : null;
            final slug = ids is Map ? ids['hikka'] : null;
            if (slug is! String || watch[slug] != r['releaseId']) continue;
            final ep = (r['episode'] as num?)?.toInt();
            if (ep == null) continue;
            final id = '$slug|${r['releaseId']}|$ep';
            if (known.containsKey(id) || dismissed.contains(id)) continue;
            final titles = anime is Map ? anime['titles'] : null;
            final published = DateTime.tryParse('${r['publishedAt']}')?.toLocal() ?? now;
            known[id] = fresh[id] = EpisodeAlert(
              id: id,
              slug: slug,
              title: (titles is Map ? (titles['ua'] ?? titles['english'] ?? titles['original']) : null) as String? ?? slug,
              image: _poster(anime is Map ? anime['images'] : null),
              episode: ep,
              teamName: (r['teamName'] as String?) ?? '',
              kind: (r['kind'] as String?) ?? 'voice',
              at: published,
            );
            added++;
          }
        }
      }
      // A small overlap: a record that appeared on the server a bit later than its time is not lost (repeats are filtered by id)
      _data['since'] = now.subtract(const Duration(minutes: 5)).millisecondsSinceEpoch;
      _lastRun = now;
      // Merge into the CURRENT list (not the snapshot from before the network wait): a push imported meanwhile must not be lost
      final current = {for (final a in items) a.id: a};
      for (final e in fresh.entries) {
        current.putIfAbsent(e.key, () => e.value);
      }
      _replace(current.values.toList()..sort((a, b) => b.at.compareTo(a.at)));
      _commit();
      return added;
    } finally {
      _checking = false;
    }
  }
}
