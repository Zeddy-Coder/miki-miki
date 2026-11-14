/// Watch-source models: a Dart version of Aniyomi's `animesource.model`: anime, episodes, videos, tracks, timestamps.
/// Pure Dart logic without Flutter: used by site parsers, stores and the player.
library;

enum SAnimeStatus { unknown, ongoing, completed, licensed, cancelled, onHiatus }

/// An anime from a source site page (in a list: only title, cover and address; the rest after `details`).
class SAnime {
  /// Page address: relative to the source's `baseUrl` or absolute, as the site returned it.
  final String url;
  final String title;

  /// Original (Latin / Japanese) title, if the site shows it; needed for matching with Hikka.
  final String? originalTitle;
  final String? thumbnailUrl;
  final String? description;

  /// Studio
  final String? author;
  final List<String> genres;
  final SAnimeStatus status;
  final int? year;

  /// How many episodes have aired / are planned in total (if the site reports it)
  final int? episodesAired;
  final int? episodesTotal;

  const SAnime({
    required this.url,
    required this.title,
    this.originalTitle,
    this.thumbnailUrl,
    this.description,
    this.author,
    this.genres = const [],
    this.status = SAnimeStatus.unknown,
    this.year,
    this.episodesAired,
    this.episodesTotal,
  });

  /// All titles for matching (Ukrainian + original)
  List<String> get allTitles => [title, if (originalTitle != null && originalTitle!.isNotEmpty) originalTitle!];

  /// Fills in fields from the detailed page on top of the list data (empty values do not overwrite existing ones).
  SAnime mergedWith(SAnime d) => SAnime(
        url: url,
        title: d.title.isNotEmpty ? d.title : title,
        originalTitle: _pick(d.originalTitle, originalTitle),
        thumbnailUrl: _pick(d.thumbnailUrl, thumbnailUrl),
        description: _pick(d.description, description),
        author: _pick(d.author, author),
        genres: d.genres.isNotEmpty ? d.genres : genres,
        status: d.status != SAnimeStatus.unknown ? d.status : status,
        year: d.year ?? year,
        episodesAired: d.episodesAired ?? episodesAired,
        episodesTotal: d.episodesTotal ?? episodesTotal,
      );

  static String? _pick(String? a, String? b) => (a != null && a.isNotEmpty) ? a : b;

  Map<String, Object?> toJson() => {
        'url': url,
        'title': title,
        if (originalTitle != null) 'original': originalTitle,
        if (thumbnailUrl != null) 'thumb': thumbnailUrl,
        if (description != null) 'desc': description,
        if (author != null) 'author': author,
        if (genres.isNotEmpty) 'genres': genres,
        if (status != SAnimeStatus.unknown) 'status': status.name,
        if (year != null) 'year': year,
        if (episodesAired != null) 'aired': episodesAired,
        if (episodesTotal != null) 'total': episodesTotal,
      };

  factory SAnime.fromJson(Map<String, dynamic> j) => SAnime(
        url: j['url'] as String? ?? '',
        title: j['title'] as String? ?? '',
        originalTitle: j['original'] as String?,
        thumbnailUrl: j['thumb'] as String?,
        description: j['desc'] as String?,
        author: j['author'] as String?,
        genres: (j['genres'] as List?)?.whereType<String>().toList() ?? const [],
        status: SAnimeStatus.values.asNameMap()[j['status']] ?? SAnimeStatus.unknown,
        year: (j['year'] as num?)?.toInt(),
        episodesAired: (j['aired'] as num?)?.toInt(),
        episodesTotal: (j['total'] as num?)?.toInt(),
      );

  @override
  String toString() => 'SAnime($title, $url)';
}

/// Results page (popular / new / search)
class SAnimePage {
  final List<SAnime> animes;
  final bool hasNextPage;

  const SAnimePage(this.animes, this.hasNextPage);

  static const empty = SAnimePage([], false);
}

/// Episode (with a specific dub; on sites with several dubs the episode repeats for each one)
class SEpisode {
  /// Address of the episode page / player / playlist; only the source knows which
  final String url;

  /// Display name: "Серія 3", "Сезон 2 · Серія 5", "Фільм"
  final String name;

  /// Episode number within the season (or continuous); `null` means unknown
  final double? number;
  final int? season;

  /// Dub / team (`scanlator` in Aniyomi)
  final String? voice;
  final DateTime? date;

  /// Source-internal data (e.g. the address of a separate audio track); the player does not touch it
  final String? data;

  const SEpisode({required this.url, required this.name, this.number, this.season, this.voice, this.date, this.data});

  Map<String, Object?> toJson() => {
        'url': url,
        'name': name,
        if (number != null) 'n': number,
        if (season != null) 's': season,
        if (voice != null) 'v': voice,
        if (date != null) 'd': date!.millisecondsSinceEpoch,
        if (data != null) 'x': data,
      };

  factory SEpisode.fromJson(Map<String, dynamic> j) => SEpisode(
        url: j['url'] as String? ?? '',
        name: j['name'] as String? ?? '',
        number: (j['n'] as num?)?.toDouble(),
        season: (j['s'] as num?)?.toInt(),
        voice: j['v'] as String?,
        date: j['d'] == null ? null : DateTime.fromMillisecondsSinceEpoch((j['d'] as num).toInt()),
        data: j['x'] as String?,
      );

  @override
  String toString() => 'SEpisode($name${voice == null ? '' : ' · $voice'}, $url)';
}

/// External track (subtitles or audio)
class Track {
  final String url;
  final String lang;

  const Track(this.url, this.lang);
}

enum ChapterType { opening, ending, recap, mixedOp, other }

/// Timestamp of an opening / ending etc. (seconds)
class TimeStamp {
  final double start;
  final double end;
  final String name;
  final ChapterType type;

  const TimeStamp(this.start, this.end, this.name, [this.type = ChapterType.other]);
}

/// A video ready for playback: a direct link + everything the player needs.
class Video {
  /// Direct link (mp4 / m3u8)
  final String url;

  /// Label for quality selection: "1080p", "Авто"
  final String title;

  /// Frame height, if known
  final int? resolution;
  final int? bitrate;

  /// Request headers (Referer, User-Agent, Cookie …)
  final Map<String, String> headers;
  final List<Track> subtitleTracks;
  final List<Track> audioTracks;
  final List<TimeStamp> timestamps;

  /// The source recommends this exact video (`preferred` in Aniyomi)
  final bool preferred;

  /// Extra mpv options "key → value"
  final Map<String, String> mpvOptions;

  const Video({
    required this.url,
    required this.title,
    this.resolution,
    this.bitrate,
    this.headers = const {},
    this.subtitleTracks = const [],
    this.audioTracks = const [],
    this.timestamps = const [],
    this.preferred = false,
    this.mpvOptions = const {},
  });

  Video copyWith({String? url, String? title, Map<String, String>? headers, bool? preferred}) => Video(
        url: url ?? this.url,
        title: title ?? this.title,
        resolution: resolution,
        bitrate: bitrate,
        headers: headers ?? this.headers,
        subtitleTracks: subtitleTracks,
        audioTracks: audioTracks,
        timestamps: timestamps,
        preferred: preferred ?? this.preferred,
        mpvOptions: mpvOptions,
      );

  @override
  String toString() => 'Video($title, $url)';
}

/// Video host (`Hoster` in Aniyomi): a group of videos from one player. The videos may already be known
/// (`videos`) or loaded separately (`videos == null`; then `AnimeSource.hosterVideos` fetches them).
class Hoster {
  final String name;
  final String url;
  final List<Video>? videos;

  /// Source-internal data (for deferred video loading)
  final String internalData;

  const Hoster({required this.name, this.url = '', this.videos, this.internalData = ''});
}

/// Picks a video by the user's preference: the source's `preferred` has priority, then the quality closest to
/// the desired height (not higher; if there is none, the lowest of the higher ones).
/// `maxHeight == 0` means the highest available.
Video? pickVideo(List<Video> videos, {int maxHeight = 0}) {
  final usable = videos.where((v) => v.url.isNotEmpty).toList();
  if (usable.isEmpty) return null;
  final pref = usable.where((v) => v.preferred);
  if (pref.isNotEmpty) return pref.first;
  final withRes = usable.where((v) => v.resolution != null).toList()..sort((a, b) => b.resolution!.compareTo(a.resolution!));
  if (withRes.isEmpty) return usable.first;
  if (maxHeight <= 0) return withRes.first;
  for (final v in withRes) {
    if (v.resolution! <= maxHeight) return v;
  }
  return withRes.last;
}
