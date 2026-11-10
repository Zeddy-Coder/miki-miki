/// Моделі джерел перегляду — Dart-версія `animesource.model` з Aniyomi: аніме, серії, відео, доріжки, таймкоди.
/// Чиста Dart-логіка без Flutter: ними користуються парсери сайтів, сховища й плеєр.
library;

enum SAnimeStatus { unknown, ongoing, completed, licensed, cancelled, onHiatus }

/// Аніме зі сторінки сайту-джерела (у списку — лише назва, обкладинка й адреса; решта — після `details`).
class SAnime {
  /// Адреса сторінки: відносна до `baseUrl` джерела або повна — як її віддав сайт.
  final String url;
  final String title;

  /// Оригінальна (латиницею / японською) назва, якщо сайт її показує — потрібна для зіставлення з Hikka.
  final String? originalTitle;
  final String? thumbnailUrl;
  final String? description;

  /// Студія
  final String? author;
  final List<String> genres;
  final SAnimeStatus status;
  final int? year;

  /// Скільки серій вийшло / заплановано всього (якщо сайт повідомляє)
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

  /// Усі назви для зіставлення (українська + оригінальна)
  List<String> get allTitles => [title, if (originalTitle != null && originalTitle!.isNotEmpty) originalTitle!];

  /// Дописує поля зі сторінки докладно поверх даних зі списку (порожнє не затирає наявне).
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

/// Сторінка видачі (популярне / нове / пошук)
class SAnimePage {
  final List<SAnime> animes;
  final bool hasNextPage;

  const SAnimePage(this.animes, this.hasNextPage);

  static const empty = SAnimePage([], false);
}

/// Серія (з конкретною озвучкою — у сайтів з кількома озвучками серія повторюється для кожної)
class SEpisode {
  /// Адреса сторінки / плеєра / плейлиста серії — що саме, знає лише джерело
  final String url;

  /// Назва для показу: «Серія 3», «Сезон 2 · Серія 5», «Фільм»
  final String name;

  /// Номер серії в межах сезону (або наскрізний); `null` — невідомо
  final double? number;
  final int? season;

  /// Озвучка / команда (у Aniyomi — `scanlator`)
  final String? voice;
  final DateTime? date;

  /// Службові дані джерела (наприклад, адреса окремої звукової доріжки) — плеєр їх не чіпає
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

/// Зовнішня доріжка (субтитри або звук)
class Track {
  final String url;
  final String lang;

  const Track(this.url, this.lang);
}

enum ChapterType { opening, ending, recap, mixedOp, other }

/// Таймкод опенінґу / ендінґу тощо (секунди)
class TimeStamp {
  final double start;
  final double end;
  final String name;
  final ChapterType type;

  const TimeStamp(this.start, this.end, this.name, [this.type = ChapterType.other]);
}

/// Готове до відтворення відео: пряме посилання + все, що потрібно плеєру.
class Video {
  /// Пряме посилання (mp4 / m3u8)
  final String url;

  /// Підпис для вибору якості: «1080p», «Авто»
  final String title;

  /// Висота кадру, якщо відома
  final int? resolution;
  final int? bitrate;

  /// Заголовки запиту (Referer, User-Agent, Cookie …)
  final Map<String, String> headers;
  final List<Track> subtitleTracks;
  final List<Track> audioTracks;
  final List<TimeStamp> timestamps;

  /// Джерело радить саме це відео (у Aniyomi — `preferred`)
  final bool preferred;

  /// Додаткові опції mpv «ключ → значення»
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

/// Хостинг відео (у Aniyomi — `Hoster`): група відео з одного плеєра. Відео можуть бути вже відомі
/// (`videos`) або завантажуватися окремо (`videos == null`, тоді їх дістає `AnimeSource.hosterVideos`).
class Hoster {
  final String name;
  final String url;
  final List<Video>? videos;

  /// Службові дані джерела (для відкладеного завантаження відео)
  final String internalData;

  const Hoster({required this.name, this.url = '', this.videos, this.internalData = ''});
}

/// Вибір відео за побажанням користувача: `preferred` джерела має пріоритет, далі — найближча до
/// бажаної висоти якість (не вища за неї, а якщо таких немає — найнижча з вищих).
/// `maxHeight == 0` — найвища доступна.
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
