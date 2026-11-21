/// Downloaded episodes: what is kept about each one, so it plays without the network with everything the online
/// episode had (the title, the dub, the number among the others, subtitles, opening / ending marks). Pure Dart.
library;

import '../../models/source_models.dart';

enum DownloadState {
  /// Waits for its turn (or for the network: Wi-Fi only, offline)
  queued,
  running,

  /// Stopped by the person
  paused,
  failed,
  done,
}

/// A downloaded (or downloading) episode of one dub
class DownloadItem {
  /// `<sourceId>|<episode url>`: the same episode of the same dub is downloaded once
  final String id;

  /// `hikka:<slug>` (or the source's own key)
  final String animeKey;
  final String animeTitle;
  final String? poster;

  /// The dub / subtitles variant (`WatchGroup`)
  final String groupId;
  final String groupLabel;
  final bool isSub;
  final String sourceId;

  /// The episode as the source gave it: the address to get a fresh link from when the old one expires
  final SEpisode episode;

  /// The episode key ("5", "s2e3"); the position and the "watched" mark go by `animeKey#epKey`
  final String epKey;

  /// "Серія 5"
  final String title;

  /// The place in the dub's list and its length: "Серія 5 з 12", the order offline
  final int order;
  final int count;

  /// The wanted frame height (0: the best)
  final int height;
  final DateTime addedAt;

  // ── What happened ─────────────────────────────────────────────────────────

  final DownloadState state;
  final String? error;

  /// The episode's folder (absolute: changing the downloads folder leaves what is downloaded where it is)
  final String folder;

  /// The file to play, relative to [folder] (`index.m3u8` or `video.mp4`)
  final String file;

  /// "1080p" and the player it came from
  final String quality;
  final String hoster;
  final int bytes;

  /// The whole size when known (a file) or estimated (segments)
  final int totalBytes;
  final int parts;
  final int partsDone;
  final double duration;
  final List<DownloadTrack> subtitles;
  final List<DownloadTrack> audio;
  final List<TimeStamp> timestamps;
  final DateTime? doneAt;

  const DownloadItem({
    required this.id,
    required this.animeKey,
    required this.animeTitle,
    this.poster,
    required this.groupId,
    required this.groupLabel,
    this.isSub = false,
    required this.sourceId,
    required this.episode,
    required this.epKey,
    required this.title,
    required this.order,
    required this.count,
    this.height = 0,
    required this.addedAt,
    this.state = DownloadState.queued,
    this.error,
    this.folder = '',
    this.file = '',
    this.quality = '',
    this.hoster = '',
    this.bytes = 0,
    this.totalBytes = 0,
    this.parts = 0,
    this.partsDone = 0,
    this.duration = 0,
    this.subtitles = const [],
    this.audio = const [],
    this.timestamps = const [],
    this.doneAt,
  });

  static String idOf(String sourceId, SEpisode episode) => '$sourceId|${episode.url}';

  /// The position / "watched" key, as `RemoteEntry.key`
  String get entryKey => '$animeKey#$epKey';

  bool get isDone => state == DownloadState.done;
  bool get isActive => state == DownloadState.queued || state == DownloadState.running;

  /// 0…1; null while nothing is known
  double? get fraction {
    if (isDone) return 1;
    if (parts > 0) return (partsDone / parts).clamp(0.0, 1.0);
    if (totalBytes > 0) return (bytes / totalBytes).clamp(0.0, 1.0);
    return null;
  }

  /// Hikka's slug, when the title came from Hikka
  String? get slug => animeKey.startsWith('hikka:') ? animeKey.substring(6) : null;

  DownloadItem copyWith({
    DownloadState? state,
    String? error,
    bool clearError = false,
    String? folder,
    String? file,
    String? quality,
    String? hoster,
    int? bytes,
    int? totalBytes,
    int? parts,
    int? partsDone,
    double? duration,
    List<DownloadTrack>? subtitles,
    List<DownloadTrack>? audio,
    List<TimeStamp>? timestamps,
    DateTime? doneAt,
    String? poster,
    int? height,
  }) =>
      DownloadItem(
        id: id,
        animeKey: animeKey,
        animeTitle: animeTitle,
        poster: poster ?? this.poster,
        groupId: groupId,
        groupLabel: groupLabel,
        isSub: isSub,
        sourceId: sourceId,
        episode: episode,
        epKey: epKey,
        title: title,
        order: order,
        count: count,
        height: height ?? this.height,
        addedAt: addedAt,
        state: state ?? this.state,
        error: clearError ? null : (error ?? this.error),
        folder: folder ?? this.folder,
        file: file ?? this.file,
        quality: quality ?? this.quality,
        hoster: hoster ?? this.hoster,
        bytes: bytes ?? this.bytes,
        totalBytes: totalBytes ?? this.totalBytes,
        parts: parts ?? this.parts,
        partsDone: partsDone ?? this.partsDone,
        duration: duration ?? this.duration,
        subtitles: subtitles ?? this.subtitles,
        audio: audio ?? this.audio,
        timestamps: timestamps ?? this.timestamps,
        doneAt: doneAt ?? this.doneAt,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'anime': animeKey,
        'animeTitle': animeTitle,
        if (poster != null) 'poster': poster,
        'group': groupId,
        'groupLabel': groupLabel,
        if (isSub) 'sub': true,
        'source': sourceId,
        'episode': episode.toJson(),
        'ep': epKey,
        'title': title,
        'order': order,
        'count': count,
        if (height > 0) 'height': height,
        'added': addedAt.millisecondsSinceEpoch,
        'state': state.name,
        if (error != null) 'error': error,
        if (folder.isNotEmpty) 'folder': folder,
        if (file.isNotEmpty) 'file': file,
        if (quality.isNotEmpty) 'quality': quality,
        if (hoster.isNotEmpty) 'hoster': hoster,
        if (bytes > 0) 'bytes': bytes,
        if (totalBytes > 0) 'total': totalBytes,
        if (parts > 0) 'parts': parts,
        if (partsDone > 0) 'partsDone': partsDone,
        if (duration > 0) 'duration': duration,
        if (subtitles.isNotEmpty) 'subs': [for (final s in subtitles) s.toJson()],
        if (audio.isNotEmpty) 'audio': [for (final s in audio) s.toJson()],
        if (timestamps.isNotEmpty)
          'stamps': [
            for (final t in timestamps) {'s': t.start, 'e': t.end, 'n': t.name, 't': t.type.name, if (!t.exact) 'x': false},
          ],
        if (doneAt != null) 'done': doneAt!.millisecondsSinceEpoch,
      };

  static DownloadItem? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final j = raw.cast<String, dynamic>();
    final ep = j['episode'];
    if (j['id'] is! String || j['anime'] is! String || ep is! Map) return null;
    List<DownloadTrack> tracks(Object? v) => [
          for (final t in (v as List?) ?? const [])
            if (DownloadTrack.fromJson(t) case final track?) track,
        ];
    return DownloadItem(
      id: j['id'] as String,
      animeKey: j['anime'] as String,
      animeTitle: '${j['animeTitle'] ?? ''}',
      poster: j['poster'] as String?,
      groupId: '${j['group'] ?? ''}',
      groupLabel: '${j['groupLabel'] ?? ''}',
      isSub: j['sub'] == true,
      sourceId: '${j['source'] ?? ''}',
      episode: SEpisode.fromJson(ep.cast<String, dynamic>()),
      epKey: '${j['ep'] ?? ''}',
      title: '${j['title'] ?? ''}',
      order: (j['order'] as num?)?.toInt() ?? 0,
      count: (j['count'] as num?)?.toInt() ?? 0,
      height: (j['height'] as num?)?.toInt() ?? 0,
      addedAt: DateTime.fromMillisecondsSinceEpoch((j['added'] as num?)?.toInt() ?? 0),
      // A download that was running when the app closed waits for its turn again
      state: switch (DownloadState.values.asNameMap()[j['state']]) {
        DownloadState.running || null => DownloadState.queued,
        final s => s,
      },
      error: j['error'] as String?,
      folder: '${j['folder'] ?? ''}',
      file: '${j['file'] ?? ''}',
      quality: '${j['quality'] ?? ''}',
      hoster: '${j['hoster'] ?? ''}',
      bytes: (j['bytes'] as num?)?.toInt() ?? 0,
      totalBytes: (j['total'] as num?)?.toInt() ?? 0,
      parts: (j['parts'] as num?)?.toInt() ?? 0,
      partsDone: (j['partsDone'] as num?)?.toInt() ?? 0,
      duration: (j['duration'] as num?)?.toDouble() ?? 0,
      subtitles: tracks(j['subs']),
      audio: tracks(j['audio']),
      timestamps: [
        for (final t in (j['stamps'] as List?) ?? const [])
          if (t is Map)
            TimeStamp(
              (t['s'] as num?)?.toDouble() ?? 0,
              (t['e'] as num?)?.toDouble() ?? 0,
              '${t['n'] ?? ''}',
              ChapterType.values.asNameMap()[t['t']] ?? ChapterType.other,
              t['x'] != false,
            ),
      ],
      doneAt: j['done'] == null ? null : DateTime.fromMillisecondsSinceEpoch((j['done'] as num).toInt()),
    );
  }
}

/// A downloaded subtitle or audio file (relative to the episode's folder) and its language label
class DownloadTrack {
  final String file;
  final String lang;

  const DownloadTrack(this.file, this.lang);

  Map<String, String> toJson() => {'file': file, 'lang': lang};

  static DownloadTrack? fromJson(Object? raw) {
    if (raw is! Map || raw['file'] is! String) return null;
    return DownloadTrack(raw['file'] as String, '${raw['lang'] ?? ''}');
  }
}

/// One title's downloads of one dub, for the downloads page
class DownloadShelf {
  final String animeKey;
  final String animeTitle;
  final String? poster;
  final String groupId;
  final String groupLabel;
  final bool isSub;
  final List<DownloadItem> items;

  const DownloadShelf({
    required this.animeKey,
    required this.animeTitle,
    required this.poster,
    required this.groupId,
    required this.groupLabel,
    required this.isSub,
    required this.items,
  });

  List<DownloadItem> get done => [for (final i in items) if (i.isDone) i];
  int get bytes => items.fold(0, (a, i) => a + i.bytes);
  DateTime get latest => items.map((i) => i.doneAt ?? i.addedAt).reduce((a, b) => a.isAfter(b) ? a : b);

  /// Groups [items] by title and dub, newest first; episodes inside in the dub's order
  static List<DownloadShelf> of(Iterable<DownloadItem> items) {
    final by = <String, List<DownloadItem>>{};
    for (final i in items) {
      (by['${i.animeKey}\u0000${i.groupId}'] ??= []).add(i);
    }
    final out = [
      for (final list in by.values)
        DownloadShelf(
          animeKey: list.first.animeKey,
          animeTitle: list.first.animeTitle,
          poster: list.map((i) => i.poster).firstWhere((p) => p != null && p.isNotEmpty, orElse: () => null),
          groupId: list.first.groupId,
          groupLabel: list.first.groupLabel,
          isSub: list.first.isSub,
          items: list..sort((a, b) => a.order.compareTo(b.order)),
        ),
    ];
    out.sort((a, b) => b.latest.compareTo(a.latest));
    return out;
  }
}

/// Bytes for people: "850 МБ", "2,1 ГБ"
String formatBytes(int bytes) {
  if (bytes <= 0) return '0 МБ';
  const mb = 1024 * 1024;
  const gb = mb * 1024;
  if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(bytes >= 10 * gb ? 0 : 1).replaceAll('.', ',')} ГБ';
  if (bytes >= mb) return '${(bytes / mb).round()} МБ';
  return '${(bytes / 1024).ceil()} КБ';
}
