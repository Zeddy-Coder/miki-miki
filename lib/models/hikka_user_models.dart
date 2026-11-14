/// Hikka account data: profile, watch-list entries, per-status counters.
library;

import 'hikka_models.dart';

/// Status of a title in the watch list (values match the Hikka API)
enum HikkaWatchStatus {
  watching('watching', 'Дивлюсь'),
  planned('planned', 'У планах'),
  completed('completed', 'Переглянуто'),
  onHold('on_hold', 'Відкладено'),
  dropped('dropped', 'Кинуто');

  final String api;
  final String label;

  const HikkaWatchStatus(this.api, this.label);

  static HikkaWatchStatus? fromApi(Object? value) {
    for (final s in values) {
      if (s.api == value) return s;
    }
    return null;
  }
}

/// Access token issued after the user's consent (`POST /auth/token`)
class HikkaToken {
  final String secret;
  final int created;
  final int expiration;

  const HikkaToken({required this.secret, this.created = 0, this.expiration = 0});

  factory HikkaToken.fromJson(Map<String, dynamic> j) => HikkaToken(
        secret: (j['secret'] as String?) ?? '',
        created: (j['created'] as num?)?.toInt() ?? 0,
        expiration: (j['expiration'] as num?)?.toInt() ?? 0,
      );
}

/// Current user (`GET /user/me`). The email is deliberately not stored.
class HikkaMe {
  final String reference;
  final String username;
  final String avatar;
  final String? cover;
  final String? description;
  final String? role;

  const HikkaMe({required this.reference, required this.username, this.avatar = '', this.cover, this.description, this.role});

  factory HikkaMe.fromJson(Map<String, dynamic> j) => HikkaMe(
        reference: '${j['reference'] ?? ''}',
        username: '${j['username'] ?? ''}',
        avatar: (j['avatar'] as String?) ?? '',
        cover: j['cover'] as String?,
        description: j['description'] as String?,
        role: j['role'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'reference': reference,
        'username': username,
        'avatar': avatar,
        if (cover != null) 'cover': cover,
        if (description != null) 'description': description,
        if (role != null) 'role': role,
      };
}

/// Watch-list entry (`WatchResponse`)
class HikkaWatchEntry {
  final String reference;
  final HikkaWatchStatus status;

  /// How many episodes were watched
  final int episodes;

  /// Score 1–10, `0` means no score
  final int score;
  final int rewatches;
  final String? note;

  /// Start and end dates (unix, seconds)
  final int? startDate;
  final int? endDate;
  final int updated;
  final HikkaAnime? anime;

  const HikkaWatchEntry({
    this.reference = '',
    required this.status,
    this.episodes = 0,
    this.score = 0,
    this.rewatches = 0,
    this.note,
    this.startDate,
    this.endDate,
    this.updated = 0,
    this.anime,
  });

  factory HikkaWatchEntry.fromJson(Map<String, dynamic> j) {
    final a = j['anime'];
    return HikkaWatchEntry(
      reference: '${j['reference'] ?? ''}',
      status: HikkaWatchStatus.fromApi(j['status']) ?? HikkaWatchStatus.planned,
      episodes: (j['episodes'] as num?)?.toInt() ?? 0,
      score: (j['score'] as num?)?.toInt() ?? 0,
      rewatches: (j['rewatches'] as num?)?.toInt() ?? 0,
      note: j['note'] as String?,
      startDate: (j['start_date'] as num?)?.toInt(),
      endDate: (j['end_date'] as num?)?.toInt(),
      updated: (j['updated'] as num?)?.toInt() ?? 0,
      anime: a is Map<String, dynamic> ? HikkaAnime.fromJson(a) : null,
    );
  }

  HikkaWatchEntry copyWith({HikkaWatchStatus? status, int? episodes, int? score, int? rewatches, HikkaAnime? anime}) => HikkaWatchEntry(
        reference: reference,
        status: status ?? this.status,
        episodes: episodes ?? this.episodes,
        score: score ?? this.score,
        rewatches: rewatches ?? this.rewatches,
        note: note,
        startDate: startDate,
        endDate: endDate,
        updated: updated,
        anime: anime ?? this.anime,
      );

  /// Body of `PUT /watch/{slug}`. We send the whole entry so a status or episode change does not erase the score,
  /// note and dates the person set on the site.
  Map<String, Object?> toArgs() => {
        'status': status.api,
        'episodes': episodes,
        'score': score,
        'rewatches': rewatches,
        if (note != null) 'note': note,
        // We do not send the dates (start_date / end_date): the Hikka API answers 400 "Invalid field start_date in request body"
      };
}

/// How many titles are in each status (`GET /watch/{username}/stats`)
class HikkaWatchStats {
  final int watching;
  final int planned;
  final int completed;
  final int onHold;
  final int dropped;

  /// Total minutes watched (Hikka counts by episode duration)
  final int duration;

  const HikkaWatchStats({this.watching = 0, this.planned = 0, this.completed = 0, this.onHold = 0, this.dropped = 0, this.duration = 0});

  factory HikkaWatchStats.fromJson(Map<String, dynamic> j) => HikkaWatchStats(
        watching: (j['watching'] as num?)?.toInt() ?? 0,
        planned: (j['planned'] as num?)?.toInt() ?? 0,
        completed: (j['completed'] as num?)?.toInt() ?? 0,
        onHold: (j['on_hold'] as num?)?.toInt() ?? 0,
        dropped: (j['dropped'] as num?)?.toInt() ?? 0,
        duration: (j['duration'] as num?)?.toInt() ?? 0,
      );

  int of(HikkaWatchStatus s) => switch (s) {
        HikkaWatchStatus.watching => watching,
        HikkaWatchStatus.planned => planned,
        HikkaWatchStatus.completed => completed,
        HikkaWatchStatus.onHold => onHold,
        HikkaWatchStatus.dropped => dropped,
      };

  int get total => watching + planned + completed + onHold + dropped;
}
