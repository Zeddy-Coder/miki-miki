/// Public Hikka user profile (page `hikka.io/u/<name>`): header, counters, activity over a year
/// and the list-change history. No Flutter dependency; covered by tests.
library;

import 'hikka_models.dart';
import 'hikka_user_models.dart';

String? _s(Object? v) {
  if (v is! String) return null;
  final t = v.trim();
  return t.isEmpty ? null : t;
}

int _i(Object? v) => v is num ? v.toInt() : 0;
Map<String, dynamic> _m(Object? v) => v is Map<String, dynamic> ? v : const <String, dynamic>{};

/// Link from the profile ("Telegram" etc.)
class HikkaUserLink {
  final String url;
  final String text;
  final String icon;

  const HikkaUserLink({required this.url, this.text = '', this.icon = ''});

  factory HikkaUserLink.fromJson(Map<String, dynamic> j) =>
      HikkaUserLink(url: _s(j['url']) ?? '', text: _s(j['text']) ?? '', icon: _s(j['icon']) ?? '');

  /// Button label: the link text or the domain
  String get label {
    if (text.isNotEmpty) return text;
    final host = Uri.tryParse(url)?.host ?? '';
    return host.startsWith('www.') ? host.substring(4) : (host.isEmpty ? url : host);
  }
}

/// Hikka user (`GET /user/{username}`)
class HikkaUser {
  final String reference;
  final String username;
  final String avatar;
  final String? cover;
  final String? description;
  final String? role;
  final List<HikkaUserLink> links;

  /// Registration date (unix, seconds)
  final int created;

  const HikkaUser({
    required this.username,
    this.reference = '',
    this.avatar = '',
    this.cover,
    this.description,
    this.role,
    this.links = const [],
    this.created = 0,
  });

  factory HikkaUser.fromJson(Map<String, dynamic> j) => HikkaUser(
        reference: _s(j['reference']) ?? '',
        username: _s(j['username']) ?? '',
        avatar: _s(j['avatar']) ?? '',
        cover: _s(j['cover']),
        description: _s(j['description']),
        role: _s(j['role']),
        links: [
          if (j['links'] is List)
            for (final l in j['links'] as List)
              if (l is Map<String, dynamic> && _s(l['url']) != null) HikkaUserLink.fromJson(l),
        ],
        created: _i(j['created']),
      );

  /// Header of one's own profile right after sign-in, before the `/user/{username}` response
  factory HikkaUser.fromMe(HikkaMe me) => HikkaUser(
        reference: me.reference,
        username: me.username,
        avatar: me.avatar,
        cover: me.cover,
        description: me.description,
        role: me.role,
      );

  /// Role label for people; a regular user is `null`
  String? get roleLabel => switch (role) {
        'admin' => 'Адміністратор',
        'moderator' => 'Модератор',
        _ => null,
      };
}

/// Profile counters (`GET /user/{username}/stats`)
class HikkaUserStats {
  final int favouriteAnime;
  final int favouriteCharacters;
  final int favouriteCollections;
  final int comments;
  final int reviews;
  final int edits;

  const HikkaUserStats({
    this.favouriteAnime = 0,
    this.favouriteCharacters = 0,
    this.favouriteCollections = 0,
    this.comments = 0,
    this.reviews = 0,
    this.edits = 0,
  });

  factory HikkaUserStats.fromJson(Map<String, dynamic> j) {
    final f = _m(j['favourites_count']);
    return HikkaUserStats(
      favouriteAnime: _i(f['anime']),
      favouriteCharacters: _i(f['character']),
      favouriteCollections: _i(f['collection']),
      comments: _i(j['comments_count']),
      reviews: _i(j['reviews_count']),
      edits: _i(j['edits_count']),
    );
  }
}

/// Follows (`GET /follow/{username}/stats`)
class HikkaFollowStats {
  final int followers;
  final int following;

  const HikkaFollowStats({this.followers = 0, this.following = 0});

  factory HikkaFollowStats.fromJson(Map<String, dynamic> j) =>
      HikkaFollowStats(followers: _i(j['followers']), following: _i(j['following']));
}

/// Activity day (`GET /user/{username}/activity`): Hikka returns 365 days, each at UTC midnight
class HikkaActivityDay {
  final DateTime day;
  final int actions;

  const HikkaActivityDay(this.day, this.actions);

  static List<HikkaActivityDay> parseList(Object? json) {
    if (json is! List) return const [];
    final out = <HikkaActivityDay>[
      for (final e in json)
        if (e is Map<String, dynamic> && e['timestamp'] is num)
          HikkaActivityDay(
            DateTime.fromMillisecondsSinceEpoch(_i(e['timestamp']) * 1000, isUtc: true),
            _i(e['actions']).clamp(0, 1 << 30),
          ),
    ];
    out.sort((a, b) => a.day.compareTo(b.day));
    return out;
  }
}

/// History entry (`GET /history/user/{username}`). The app is anime-only: manga and light novels are dropped.
class HikkaHistoryEntry {
  final String reference;

  /// `watch`, `watch_delete`, `watch_import`, `favourite_anime_add`, `favourite_anime_remove`…
  final String type;

  /// When it happened (unix, seconds): `updated`, because Hikka merges frequent changes of one title into one entry
  final int time;
  final HikkaAnime? anime;
  final Map<String, dynamic> before;
  final Map<String, dynamic> after;
  final bool isNew;

  const HikkaHistoryEntry({
    required this.reference,
    required this.type,
    required this.time,
    this.anime,
    this.before = const {},
    this.after = const {},
    this.isNew = false,
  });

  /// Types the app shows
  static const Set<String> animeTypes = {'watch', 'watch_delete', 'watch_import', 'favourite_anime_add', 'favourite_anime_remove'};

  bool get isAnime => animeTypes.contains(type);

  DateTime get when => DateTime.fromMillisecondsSinceEpoch(time * 1000);

  factory HikkaHistoryEntry.fromJson(Map<String, dynamic> j) {
    final data = _m(j['data']);
    final content = _m(j['content']);
    final created = _i(j['created']);
    final updated = _i(j['updated']);
    return HikkaHistoryEntry(
      reference: _s(j['reference']) ?? '',
      type: _s(j['history_type']) ?? '',
      time: updated > 0 ? updated : created,
      anime: content.isNotEmpty && (content['data_type'] == null || content['data_type'] == 'anime') ? HikkaAnime.fromJson(content) : null,
      before: _m(data['before']),
      after: _m(data['after']),
      isNew: data['new_watch'] == true,
    );
  }

  /// What happened, in human words: "Переглянуто епізод 12 з 19", "Завершено", "Додано до списку «У планах»"…
  String describe() {
    switch (type) {
      case 'watch_delete':
        return 'Видалено зі списку';
      case 'watch_import':
        return 'Список імпортовано';
      case 'favourite_anime_add':
        return 'Додано до улюблених';
      case 'favourite_anime_remove':
        return 'Видалено з улюблених';
    }
    final parts = <String>[];
    final status = HikkaWatchStatus.fromApi(after['status']);
    final statusChanged = after.containsKey('status') && after['status'] != before['status'];
    // New entry: Hikka does not always set `new_watch`, but then "before" is empty
    final added = isNew || (before['status'] == null && status != null);
    if (added && status != null) {
      parts.add('Додано до списку «${status.label}»');
    } else if (statusChanged && status != null) {
      parts.add(status == HikkaWatchStatus.completed ? 'Завершено' : 'Статус «${status.label}»');
    }
    if (after['episodes'] is num && after['episodes'] != before['episodes']) {
      final to = _i(after['episodes']);
      final from = _i(before['episodes']);
      final total = anime?.episodesTotal ?? 0;
      final of = total > 0 ? ' з $total' : '';
      // "Завершено" already says everything was watched
      final redundant = statusChanged && status == HikkaWatchStatus.completed && total > 0 && to >= total;
      if (!redundant && !(added && to == 0)) {
        if (to > from + 1 && !added) {
          parts.add('Переглянуто епізоди ${from + 1}–$to$of');
        } else if (to > from) {
          parts.add('Переглянуто епізод $to$of');
        } else {
          parts.add('Епізодів переглянуто: $to$of');
        }
      }
    }
    // null → 0 is not a score change (that is how Hikka records a new entry without a score)
    final scoreBefore = _i(before['score']);
    final scoreAfter = _i(after['score']);
    if (after.containsKey('score') && scoreAfter != scoreBefore) {
      parts.add(scoreAfter > 0 ? 'Оцінка $scoreAfter' : 'Оцінку прибрано');
    }
    if (parts.isEmpty) return 'Запис оновлено';
    final first = parts.first;
    final rest = parts.skip(1).map((p) => p[0].toLowerCase() + p.substring(1));
    return [first, ...rest].join(', ');
  }
}

/// Profile texts
class HikkaProfileText {
  const HikkaProfileText._();

  /// Watch time from minutes, as on hikka.io: "4 місяці 29 днів", "3 дні 5 годин", "45 хвилин".
  /// A month is 30 days; the two largest units are shown.
  static String watchTime(int minutes) {
    if (minutes <= 0) return '0 хвилин';
    final months = minutes ~/ (30 * 24 * 60);
    final days = (minutes ~/ (24 * 60)) % 30;
    final hours = (minutes ~/ 60) % 24;
    final mins = minutes % 60;
    final units = <String>[
      if (months > 0) '$months ${HikkaText.plural(months, 'місяць', 'місяці', 'місяців')}',
      if (days > 0) '$days ${HikkaText.plural(days, 'день', 'дні', 'днів')}',
      if (hours > 0) '$hours ${HikkaText.plural(hours, 'година', 'години', 'годин')}',
      if (mins > 0) '$mins ${HikkaText.plural(mins, 'хвилина', 'хвилини', 'хвилин')}',
    ];
    return units.take(2).join(' ');
  }

  /// "Сьогодні", "Вчора", "11 листопада, середа"
  static String historyDay(DateTime when, DateTime now) {
    final diff = DateTime.utc(when.year, when.month, when.day).difference(DateTime.utc(now.year, now.month, now.day)).inDays;
    if (diff == 0) return 'Сьогодні';
    if (diff == -1) return 'Вчора';
    return '${HikkaText.dayMonth(when, now: now)}, ${HikkaText.weekdays[when.weekday - 1].toLowerCase()}';
  }
}
