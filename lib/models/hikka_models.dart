/// Моделі каталогу Hikka (api.hikka.io). Розбір толерантний: відсутнє або несподіване поле
/// не ламає екран, а лише лишається порожнім. Без залежності від Flutter — покрито тестами.
library;

// Колекції та статті спільноти: лежать в окремому файлі, але користуються тими самими допоміжними функціями
part 'hikka_community_models.dart';

// ── Допоміжне розбирання JSON ────────────────────────────────────────────────

String? _str(Object? v) {
  if (v is! String) return null;
  final t = v.trim();
  return t.isEmpty ? null : t;
}

int? _int(Object? v) => v is num ? v.toInt() : null;
int _intOr0(Object? v) => v is num ? v.toInt() : 0;
double _dbl(Object? v) => v is num ? v.toDouble() : 0.0;
bool _bool(Object? v) => v is bool && v;

List<T> _list<T>(Object? v, T Function(Map<String, dynamic>) parse) {
  if (v is! List) return const [];
  return [
    for (final e in v)
      if (e is Map<String, dynamic>) parse(e),
  ];
}

Map<String, dynamic> _map(Object? v) => v is Map<String, dynamic> ? v : const <String, dynamic>{};

/// Мова назв у каталозі
enum HikkaTitleLang {
  ua('Українська'),
  en('Англійська'),
  ja('Японська (ромаджі)');

  final String label;
  const HikkaTitleLang(this.label);

  static HikkaTitleLang fromName(String? name) =>
      HikkaTitleLang.values.firstWhere((l) => l.name == name, orElse: () => HikkaTitleLang.ua);
}

/// Підписи значень API українською (ті самі, що на hikka.io)
class HikkaText {
  const HikkaText._();

  static const Map<String, String> mediaTypes = {
    'tv': 'TV Серіал',
    'movie': 'Фільм',
    'ova': 'OVA',
    'ona': 'ONA',
    'special': 'Спешл',
    'music': 'Музика',
  };

  static const Map<String, String> statuses = {
    'ongoing': 'Онґоїнґ',
    'finished': 'Завершено',
    'announced': 'Анонс',
    'paused': 'Призупинено',
    'discontinued': 'Припинено',
  };

  static const Map<String, String> seasons = {
    'winter': 'Зима',
    'spring': 'Весна',
    'summer': 'Літо',
    'fall': 'Осінь',
  };

  static const Map<String, String> ratings = {
    'g': 'G',
    'pg': 'PG',
    'pg_13': 'PG-13',
    'r': 'R',
    'r_plus': 'R PLUS',
    'rx': 'RX',
  };

  static const Map<String, String> ratingHints = {
    'g': 'Немає вікових обмежень',
    'pg': 'Рекомендується присутність батьків',
    'pg_13': 'Дітям до 13 років перегляд небажаний',
    'r': 'Особам до 18 років потрібна присутність дорослого',
    'r_plus': 'Особам до 18 років перегляд заборонений',
    'rx': 'Хентай',
  };

  static const Map<String, String> sources = {
    'original': 'Оригінал',
    'manga': 'Манґа',
    'web_manga': 'Веб-манґа',
    'digital_manga': 'Цифрова манґа',
    '4_koma_manga': 'Манґа в 4 панелі',
    'light_novel': 'Ранобе',
    'novel': 'Новела',
    'visual_novel': 'Візуальна новела',
    'game': 'Гра',
    'card_game': 'Карткова гра',
    'book': 'Книга',
    'picture_book': 'Ілюстрована книга',
    'music': 'Музика',
    'radio': 'Радіо',
    'other': 'Інше',
  };

  static const Map<String, String> genreTypes = {
    'genre': 'Жанри',
    'theme': 'Теми',
    'demographic': 'Аудиторія',
    'explicit': 'Для дорослих',
  };

  static const List<String> weekdays = ['Понеділок', 'Вівторок', 'Середа', 'Четвер', 'Пʼятниця', 'Субота', 'Неділя'];

  static const List<String> monthsGenitive = [
    'січня',
    'лютого',
    'березня',
    'квітня',
    'травня',
    'червня',
    'липня',
    'серпня',
    'вересня',
    'жовтня',
    'листопада',
    'грудня',
  ];

  static String mediaType(String? v) => v == null ? '' : (mediaTypes[v] ?? v.toUpperCase());
  static String status(String? v) => v == null ? '' : (statuses[v] ?? v);
  static String season(String? v) => v == null ? '' : (seasons[v] ?? v);
  static String rating(String? v) => v == null ? '' : (ratings[v] ?? v.toUpperCase());
  static String source(String? v) => v == null ? '' : (sources[v] ?? v);

  /// Сезон року за номером місяця (як на hikka.io): зима 1–3, весна 4–6, літо 7–9, осінь 10–12
  static String seasonOfMonth(int month) => month <= 3
      ? 'winter'
      : month <= 6
          ? 'spring'
          : month <= 9
              ? 'summer'
              : 'fall';

  /// Поточний сезон так, як його рахує hikka.io: день, що минув, ще належить попередньому сезону
  static (String season, int year) currentSeason(DateTime now) {
    final d = now.subtract(const Duration(days: 1));
    return (seasonOfMonth(d.month), d.year);
  }

  /// Наступний за [season] сезон: після осені — зима наступного року
  static (String season, int year) nextSeason(String season, int year) {
    const order = ['winter', 'spring', 'summer', 'fall'];
    final i = order.indexOf(season);
    return i == 3 ? ('winter', year + 1) : (order[(i + 1) % 4], year);
  }

  /// Форма слова за числом: `plural(1, 'тайтл', 'тайтли', 'тайтлів')` → «тайтл», 2 → «тайтли», 5 → «тайтлів»
  static String plural(int n, String one, String few, String many) {
    final m100 = n.abs() % 100;
    final m10 = n.abs() % 10;
    if (m100 >= 11 && m100 <= 14) return many;
    if (m10 == 1) return one;
    if (m10 >= 2 && m10 <= 4) return few;
    return many;
  }

  /// «5 листопада» / «5 листопада 2026»
  static String dayMonth(DateTime d, {DateTime? now, bool withYear = false}) {
    final base = '${d.day} ${monthsGenitive[d.month - 1]}';
    return withYear || (now != null && now.year != d.year) ? '$base ${d.year}' : base;
  }

  /// Число з пропусками між розрядами: 28720 → «28 720»
  static String count(int n) {
    final s = n.abs().toString();
    final b = StringBuffer(n < 0 ? '-' : '');
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write('\u00a0');
      b.write(s[i]);
    }
    return b.toString();
  }

  /// Коротко для лічильників на картках: 950 → «950», 1 250 → «1,3 тис.», 48 000 → «48 тис.», 2 400 000 → «2,4 млн»
  static String compact(int n) {
    final a = n.abs();
    final sign = n < 0 ? '-' : '';
    String one(double v) {
      final r = (v * 10).round() / 10;
      return r == r.roundToDouble() ? '${r.toInt()}' : r.toString().replaceAll('.', ',');
    }

    if (a < 1000) return '$n';
    if (a < 10000) return '$sign${one(a / 1000)}\u00a0тис.';
    if (a < 1000000) return '$sign${a ~/ 1000}\u00a0тис.';
    return '$sign${one(a / 1000000)}\u00a0млн';
  }

  /// «18:05»
  static String hhmm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  /// «Сьогодні» / «Завтра» / «Вчора» / «Середа» (протягом тижня) / «12 листопада»
  static String dayName(DateTime when, DateTime now) {
    final diff = DateTime.utc(when.year, when.month, when.day).difference(DateTime.utc(now.year, now.month, now.day)).inDays;
    if (diff == 0) return 'Сьогодні';
    if (diff == 1) return 'Завтра';
    if (diff == -1) return 'Вчора';
    if (diff > 1 && diff < 7) return weekdays[when.weekday - 1];
    return dayMonth(when, now: now);
  }

  /// «Сьогодні, 18:05»
  static String airingLabel(DateTime when, DateTime now) => '${dayName(when, now)}, ${hhmm(when)}';

  /// Заголовок дня в календарі: «Сьогодні · 3 листопада», «Середа · 5 листопада»
  static String dayHeader(DateTime when, DateTime now) {
    final name = dayName(when, now);
    final date = dayMonth(when, now: now);
    return name == date ? name : '$name · $date';
  }
}

// ── Жанри, студії ────────────────────────────────────────────────────────────

class HikkaGenre {
  final String slug;
  final String? nameUa;
  final String? nameEn;
  final String type;

  const HikkaGenre({required this.slug, this.nameUa, this.nameEn, this.type = 'genre'});

  String get name => nameUa ?? nameEn ?? slug;
  bool get isExplicit => type == 'explicit';

  factory HikkaGenre.fromJson(Map<String, dynamic> j) => HikkaGenre(
        slug: _str(j['slug']) ?? '',
        nameUa: _str(j['name_ua']),
        nameEn: _str(j['name_en']),
        type: _str(j['type']) ?? 'genre',
      );
}

class HikkaCompany {
  final String slug;
  final String name;
  final String? image;

  const HikkaCompany({required this.slug, required this.name, this.image});

  factory HikkaCompany.fromJson(Map<String, dynamic> j) =>
      HikkaCompany(slug: _str(j['slug']) ?? '', name: _str(j['name']) ?? '', image: _str(j['image']));
}

/// Компанія із роллю в аніме (студія або продюсер)
class HikkaAnimeCompany {
  final HikkaCompany company;
  final String type; // studio | producer

  const HikkaAnimeCompany({required this.company, required this.type});

  bool get isStudio => type == 'studio';

  factory HikkaAnimeCompany.fromJson(Map<String, dynamic> j) =>
      HikkaAnimeCompany(company: HikkaCompany.fromJson(_map(j['company'])), type: _str(j['type']) ?? 'producer');
}

// ── Службові блоки сторінки аніме ────────────────────────────────────────────

class HikkaLink {
  final String url;
  final String text;
  final String type; // general | watch | read

  const HikkaLink({required this.url, required this.text, required this.type});

  bool get isWatch => type == 'watch';

  factory HikkaLink.fromJson(Map<String, dynamic> j) =>
      HikkaLink(url: _str(j['url']) ?? '', text: _str(j['text']) ?? '', type: _str(j['type']) ?? 'general');
}

class HikkaVideo {
  final String url;
  final String? title;
  final String type; // video_promo | video_music

  const HikkaVideo({required this.url, this.title, required this.type});

  factory HikkaVideo.fromJson(Map<String, dynamic> j) =>
      HikkaVideo(url: _str(j['url']) ?? '', title: _str(j['title']), type: _str(j['video_type']) ?? 'video_promo');
}

class HikkaOst {
  final int index;
  final String? title;
  final String? author;
  final String type; // opening | ending

  const HikkaOst({required this.index, this.title, this.author, required this.type});

  bool get isOpening => type == 'opening';

  factory HikkaOst.fromJson(Map<String, dynamic> j) => HikkaOst(
        index: _intOr0(j['index']),
        title: _str(j['title']),
        author: _str(j['author']),
        type: _str(j['ost_type']) ?? 'opening',
      );
}

/// Запланований вихід серії (поле `schedule` сторінки аніме)
class HikkaEpisodeSlot {
  final int episode;
  final int airingAt; // unix, секунди

  const HikkaEpisodeSlot({required this.episode, required this.airingAt});

  DateTime get time => DateTime.fromMillisecondsSinceEpoch(airingAt * 1000);

  factory HikkaEpisodeSlot.fromJson(Map<String, dynamic> j) =>
      HikkaEpisodeSlot(episode: _intOr0(j['episode']), airingAt: _intOr0(j['airing_at']));
}

class HikkaAnimeStats {
  final int completed, watching, planned, dropped, onHold;

  /// Кількість оцінок 1…10 (індекс 0 — оцінка 1)
  final List<int> scores;

  const HikkaAnimeStats({
    this.completed = 0,
    this.watching = 0,
    this.planned = 0,
    this.dropped = 0,
    this.onHold = 0,
    this.scores = const [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
  });

  int get inLists => completed + watching + planned + dropped + onHold;

  factory HikkaAnimeStats.fromJson(Map<String, dynamic> j) => HikkaAnimeStats(
        completed: _intOr0(j['completed']),
        watching: _intOr0(j['watching']),
        planned: _intOr0(j['planned']),
        dropped: _intOr0(j['dropped']),
        onHold: _intOr0(j['on_hold']),
        scores: [for (int i = 1; i <= 10; i++) _intOr0(j['score_$i'])],
      );
}

// ── Аніме ────────────────────────────────────────────────────────────────────

/// Аніме: і елемент списку (каталог, календар, франшиза), і повна сторінка
/// (поля сторінки — `duration`, `synonyms`, `external`… — у списках порожні).
class HikkaAnime {
  final String slug;
  final String? titleUa;
  final String? titleEn;

  /// Ромаджі (поле API `title_ja`)
  final String? titleJa;

  /// Оригінальна назва японською (поле API `title_native`)
  final String? titleNative;
  final String? mediaType;
  final String? status;
  final String? season;
  final String? source;
  final String? rating;
  final int? year;
  final int? episodesReleased;
  final int? episodesTotal;
  final String? image;
  final double score;
  final int scoredBy;
  final double nativeScore;
  final int nativeScoredBy;
  final int? startDate; // unix, секунди
  final int? endDate;
  final bool translatedUa;
  final int malId;
  final List<HikkaCompany> studios;
  final List<HikkaGenre> genres;
  final String? synopsisUa;
  final String? synopsisEn;

  // Лише повна сторінка
  final int? duration; // хвилини
  final bool hasFranchise;
  final bool nsfw;
  final int commentsCount;
  final List<String> synonyms;
  final List<HikkaAnimeCompany> companies;
  final List<HikkaLink> external;
  final List<HikkaVideo> videos;
  final List<HikkaOst> ost;
  final List<HikkaEpisodeSlot> schedule;
  final HikkaAnimeStats? stats;

  const HikkaAnime({
    required this.slug,
    this.titleUa,
    this.titleEn,
    this.titleJa,
    this.titleNative,
    this.mediaType,
    this.status,
    this.season,
    this.source,
    this.rating,
    this.year,
    this.episodesReleased,
    this.episodesTotal,
    this.image,
    this.score = 0,
    this.scoredBy = 0,
    this.nativeScore = 0,
    this.nativeScoredBy = 0,
    this.startDate,
    this.endDate,
    this.translatedUa = false,
    this.malId = 0,
    this.studios = const [],
    this.genres = const [],
    this.synopsisUa,
    this.synopsisEn,
    this.duration,
    this.hasFranchise = false,
    this.nsfw = false,
    this.commentsCount = 0,
    this.synonyms = const [],
    this.companies = const [],
    this.external = const [],
    this.videos = const [],
    this.ost = const [],
    this.schedule = const [],
    this.stats,
  });

  factory HikkaAnime.fromJson(Map<String, dynamic> j) {
    final companies = _list(j['companies'], HikkaAnimeCompany.fromJson);
    final studios = j.containsKey('studios')
        ? _list(j['studios'], HikkaCompany.fromJson)
        : [for (final c in companies) if (c.isStudio) c.company];
    final statsJson = j['stats'];
    return HikkaAnime(
      slug: _str(j['slug']) ?? '',
      titleUa: _str(j['title_ua']),
      titleEn: _str(j['title_en']),
      titleJa: _str(j['title_ja']),
      titleNative: _str(j['title_native']),
      mediaType: _str(j['media_type']),
      status: _str(j['status']),
      season: _str(j['season']),
      source: _str(j['source']),
      rating: _str(j['rating']),
      year: _int(j['year']),
      episodesReleased: _int(j['episodes_released']),
      episodesTotal: _int(j['episodes_total']),
      image: _str(j['image']),
      score: _dbl(j['score']),
      scoredBy: _intOr0(j['scored_by']),
      nativeScore: _dbl(j['native_score']),
      nativeScoredBy: _intOr0(j['native_scored_by']),
      startDate: _int(j['start_date']),
      endDate: _int(j['end_date']),
      translatedUa: _bool(j['translated_ua']),
      malId: _intOr0(j['mal_id']),
      studios: studios,
      genres: _list(j['genres'], HikkaGenre.fromJson),
      synopsisUa: _str(j['synopsis_ua']),
      synopsisEn: _str(j['synopsis_en']),
      duration: _int(j['duration']),
      hasFranchise: _bool(j['has_franchise']),
      nsfw: _bool(j['nsfw']),
      commentsCount: _intOr0(j['comments_count']),
      synonyms: [
        if (j['synonyms'] is List)
          for (final s in j['synonyms'] as List)
            if (_str(s) != null) _str(s)!,
      ],
      companies: companies,
      external: _list(j['external'], HikkaLink.fromJson),
      videos: _list(j['videos'], HikkaVideo.fromJson),
      ost: _list(j['ost'], HikkaOst.fromJson),
      schedule: _list(j['schedule'], HikkaEpisodeSlot.fromJson),
      stats: statsJson is Map<String, dynamic> ? HikkaAnimeStats.fromJson(statsJson) : null,
    );
  }

  /// Хентай (`rating == rx`) або відмічене сайтом як 18+
  bool get isAdult => rating == 'rx' || nsfw;
  bool get isOngoing => status == 'ongoing';
  bool get isAnnounced => status == 'announced';

  /// Є сенс показувати оцінку (аніме без оцінок має 0)
  bool get hasScore => score > 0 && scoredBy > 0;

  /// Назва за вибраною мовою; якщо її немає — перша наявна за запасним порядком
  String title(HikkaTitleLang lang) {
    final order = switch (lang) {
      HikkaTitleLang.ua => [titleUa, titleEn, titleJa, titleNative],
      HikkaTitleLang.en => [titleEn, titleUa, titleJa, titleNative],
      HikkaTitleLang.ja => [titleJa, titleNative, titleEn, titleUa],
    };
    for (final t in order) {
      if (t != null) return t;
    }
    return slug;
  }

  /// Одна другорядна назва вибраною мовою; `null`, якщо її немає або вона збігається з основною
  String? secondaryTitle(HikkaTitleLang main, HikkaTitleLang secondary) {
    final t = switch (secondary) {
      HikkaTitleLang.ua => titleUa,
      HikkaTitleLang.en => titleEn,
      HikkaTitleLang.ja => titleJa ?? titleNative,
    };
    if (t == null || t.trim().isEmpty || t.toLowerCase() == title(main).toLowerCase()) return null;
    return t;
  }

  /// Решта назв, відмінних від основної (для шапки сторінки): англійська, ромаджі, оригінал
  List<String> otherTitles(HikkaTitleLang lang) {
    final main = title(lang);
    final seen = <String>{main.toLowerCase()};
    final out = <String>[];
    for (final t in [titleUa, titleEn, titleJa, titleNative]) {
      if (t != null && seen.add(t.toLowerCase())) out.add(t);
    }
    return out;
  }

  String get typeLabel => HikkaText.mediaType(mediaType);
  String get statusLabel => HikkaText.status(status);

  /// «Осінь 2026» / «2023» / порожньо
  String get seasonLabel {
    final s = season == null ? '' : HikkaText.season(season);
    if (year == null) return s;
    return s.isEmpty ? '$year' : '$s $year';
  }

  /// «28 еп.» або «4 / 25 еп.» для того, що виходить зараз; порожньо, якщо кількість невідома
  String get episodesLabel {
    final total = episodesTotal;
    final released = episodesReleased;
    if ((isOngoing || isAnnounced) && released != null && total != null && total > 0) {
      return '$released / $total еп.';
    }
    if (total != null && total > 0) return '$total еп.';
    if (released != null && released > 0) return '$released еп.';
    return '';
  }

  String get durationLabel => duration == null || duration! <= 0 ? '' : '$duration хв.';

  /// Найближча ще не вийшла серія за розкладом
  HikkaEpisodeSlot? nextEpisode(DateTime now) {
    final t = now.millisecondsSinceEpoch ~/ 1000;
    HikkaEpisodeSlot? best;
    for (final s in schedule) {
      if (s.airingAt > t && (best == null || s.airingAt < best.airingAt)) best = s;
    }
    return best;
  }

  /// Студія (перша) — коротко для підпису
  String get studioName => studios.isEmpty ? '' : studios.first.name;

  /// Опис: український, якщо є, інакше англійський
  String? get synopsis => synopsisUa ?? synopsisEn;
}

// ── Сторінкові відповіді ─────────────────────────────────────────────────────

class HikkaPage<T> {
  final List<T> items;
  final int page;
  final int pages;
  final int total;

  const HikkaPage({required this.items, this.page = 1, this.pages = 1, this.total = 0});

  bool get hasMore => page < pages;

  static HikkaPage<T> parse<T>(Object? json, T Function(Map<String, dynamic>) parse) {
    final m = _map(json);
    final p = _map(m['pagination']);
    final items = _list(m['list'], parse);
    return HikkaPage<T>(
      items: items,
      page: _int(p['page']) ?? 1,
      pages: _int(p['pages']) ?? 1,
      total: _int(p['total']) ?? items.length,
    );
  }
}

// ── Персонажі, люди ──────────────────────────────────────────────────────────

class HikkaCharacter {
  final String slug;
  final String? nameUa;
  final String? nameEn;
  final String? nameJa;
  final String? image;
  final List<String> synonyms;

  // Лише повна сторінка
  final String? descriptionUa;
  final int animeCount;
  final int voicesCount;

  const HikkaCharacter({
    required this.slug,
    this.nameUa,
    this.nameEn,
    this.nameJa,
    this.image,
    this.synonyms = const [],
    this.descriptionUa,
    this.animeCount = 0,
    this.voicesCount = 0,
  });

  factory HikkaCharacter.fromJson(Map<String, dynamic> j) => HikkaCharacter(
        slug: _str(j['slug']) ?? '',
        nameUa: _str(j['name_ua']),
        nameEn: _str(j['name_en']),
        nameJa: _str(j['name_ja']),
        image: _str(j['image']),
        synonyms: [
          if (j['synonyms'] is List)
            for (final s in j['synonyms'] as List)
              if (_str(s) != null) _str(s)!,
        ],
        descriptionUa: _str(j['description_ua']),
        animeCount: _intOr0(j['anime_count']),
        voicesCount: _intOr0(j['voices_count']),
      );

  /// Ім'я: українське → англійське → японське
  String get name => nameUa ?? nameEn ?? nameJa ?? slug;

  /// Решта імен, відмінних від основного
  List<String> get otherNames {
    final seen = <String>{name.toLowerCase()};
    return [
      for (final n in [nameEn, nameJa, nameUa])
        if (n != null && seen.add(n.toLowerCase())) n,
    ];
  }
}

/// Персонаж у складі аніме: головний чи другорядний
class HikkaCharacterRole {
  final bool main;
  final HikkaCharacter character;

  const HikkaCharacterRole({required this.main, required this.character});

  factory HikkaCharacterRole.fromJson(Map<String, dynamic> j) =>
      HikkaCharacterRole(main: _bool(j['main']), character: HikkaCharacter.fromJson(_map(j['character'])));
}

/// Аніме, у якому з'являється персонаж
class HikkaCharacterAnime {
  final bool main;
  final HikkaAnime anime;

  const HikkaCharacterAnime({required this.main, required this.anime});

  factory HikkaCharacterAnime.fromJson(Map<String, dynamic> j) =>
      HikkaCharacterAnime(main: _bool(j['main']), anime: HikkaAnime.fromJson(_map(j['anime'])));
}

class HikkaPerson {
  final String slug;
  final String? nameNative;
  final String? nameUa;
  final String? nameEn;
  final String? image;

  const HikkaPerson({required this.slug, this.nameNative, this.nameUa, this.nameEn, this.image});

  factory HikkaPerson.fromJson(Map<String, dynamic> j) => HikkaPerson(
        slug: _str(j['slug']) ?? '',
        nameNative: _str(j['name_native']),
        nameUa: _str(j['name_ua']),
        nameEn: _str(j['name_en']),
        image: _str(j['image']),
      );

  String get name => nameUa ?? nameEn ?? nameNative ?? slug;
}

/// Озвучення: хто й якою мовою озвучив персонажа в якому аніме
class HikkaCharacterVoice {
  final HikkaAnime anime;
  final HikkaPerson person;
  final String language;

  const HikkaCharacterVoice({required this.anime, required this.person, required this.language});

  factory HikkaCharacterVoice.fromJson(Map<String, dynamic> j) => HikkaCharacterVoice(
        anime: HikkaAnime.fromJson(_map(j['anime'])),
        person: HikkaPerson.fromJson(_map(j['person'])),
        language: _str(j['language']) ?? '',
      );

  /// Мови озвучення за кодом: сервер віддає двобуквені коди (`ja`, `en`)
  static const Map<String, String> languages = {
    'ja': 'Японська',
    'en': 'Англійська',
    'uk': 'Українська',
    'ko': 'Корейська',
    'de': 'Німецька',
    'es': 'Іспанська',
    'fr': 'Французька',
    'it': 'Італійська',
    'pt': 'Португальська',
    'br': 'Бразильська',
    'hu': 'Угорська',
    'he': 'Іврит',
    'zh': 'Китайська',
    'ru': 'Російська',
    'pl': 'Польська',
  };

  /// Інші написання тієї самої мови (повні назви, `ua`) зводяться до коду
  static const Map<String, String> _aliases = {
    'japanese': 'ja',
    'english': 'en',
    'ukrainian': 'uk',
    'ua': 'uk',
    'korean': 'ko',
    'german': 'de',
    'spanish': 'es',
    'french': 'fr',
    'italian': 'it',
    'portuguese': 'pt',
    'brazilian': 'br',
    'hungarian': 'hu',
    'hebrew': 'he',
    'iw': 'he',
    'mandarin': 'zh',
    'chinese': 'zh',
    'russian': 'ru',
    'polish': 'pl',
  };

  /// Канонічний код мови: за ним озвучення групуються й упорядковуються
  String get languageKey {
    final l = language.trim().toLowerCase();
    return _aliases[l] ?? l;
  }

  String get languageLabel {
    final key = languageKey;
    if (key.isEmpty) return 'Інша мова';
    return languages[key] ?? key.toUpperCase();
  }

  /// Озвучення за мовами: японська, українська, англійська, далі за назвою; люди без повторів
  static List<(String label, List<String> people)> groupByLanguage(Iterable<HikkaCharacterVoice> voices) {
    final byKey = <String, List<String>>{};
    final labels = <String, String>{};
    for (final v in voices) {
      final key = v.languageKey;
      labels[key] = v.languageLabel;
      final people = byKey.putIfAbsent(key, () => []);
      final name = v.person.name;
      if (!people.contains(name)) people.add(name);
    }
    const preferred = ['ja', 'uk', 'en'];
    int rank(String key) {
      final i = preferred.indexOf(key);
      if (i != -1) return i;
      if (key.isEmpty) return 30; // мову не вказано — наприкінці
      return languages.containsKey(key) ? 10 : 20; // невідомі коди — після відомих мов
    }

    final keys = byKey.keys.toList()
      ..sort((a, b) {
        final d = rank(a).compareTo(rank(b));
        return d != 0 ? d : _compareUk(labels[a]!, labels[b]!);
      });
    return [for (final k in keys) (labels[k]!, byKey[k]!)];
  }

  static const String _alphabet = 'абвгґдеєжзиіїйклмнопрстуфхцчшщьюя';

  /// Порівняння за українською абеткою (не за кодами символів: «І» інакше стояла б перед «Б»); латиниця — після кирилиці
  static int _compareUk(String a, String b) {
    final x = a.toLowerCase();
    final y = b.toLowerCase();
    for (int i = 0; i < x.length && i < y.length; i++) {
      final p = _alphabet.indexOf(x[i]);
      final q = _alphabet.indexOf(y[i]);
      final pi = p < 0 ? 100 + x.codeUnitAt(i) : p;
      final qi = q < 0 ? 100 + y.codeUnitAt(i) : q;
      if (pi != qi) return pi.compareTo(qi);
    }
    return x.length.compareTo(y.length);
  }
}

class HikkaRole {
  final String slug;
  final String? nameUa;
  final String? nameEn;
  final int weight;

  const HikkaRole({required this.slug, this.nameUa, this.nameEn, this.weight = 0});

  String get name => nameUa ?? nameEn ?? slug;

  factory HikkaRole.fromJson(Map<String, dynamic> j) => HikkaRole(
        slug: _str(j['slug']) ?? '',
        nameUa: _str(j['name_ua']),
        nameEn: _str(j['name_en']),
        weight: _intOr0(j['weight']),
      );
}

/// Автор / учасник знімальної групи
class HikkaStaff {
  final HikkaPerson person;
  final List<HikkaRole> roles;
  final int weight;

  const HikkaStaff({required this.person, required this.roles, this.weight = 0});

  factory HikkaStaff.fromJson(Map<String, dynamic> j) => HikkaStaff(
        person: HikkaPerson.fromJson(_map(j['person'])),
        roles: _list(j['roles'], HikkaRole.fromJson),
        weight: _intOr0(j['weight']),
      );

  String get rolesLabel => roles.map((r) => r.name).join(', ');
}

// ── Календар ─────────────────────────────────────────────────────────────────

class HikkaScheduleEntry {
  final HikkaAnime anime;
  final int episode;
  final int airingAt; // unix, секунди

  const HikkaScheduleEntry({required this.anime, required this.episode, required this.airingAt});

  DateTime get time => DateTime.fromMillisecondsSinceEpoch(airingAt * 1000);

  factory HikkaScheduleEntry.fromJson(Map<String, dynamic> j) => HikkaScheduleEntry(
        anime: HikkaAnime.fromJson(_map(j['anime'])),
        episode: _intOr0(j['episode']),
        airingAt: _intOr0(j['airing_at']),
      );
}

// ── Франшиза ─────────────────────────────────────────────────────────────────

/// Зв'язок між двома тайтлами: [slug] — «батьківський», [relatedSlug] — його сиквел / побічна історія /
/// спіноф / рекап (для альтернативних версій напрям неважливий).
class HikkaRelation {
  final String slug;
  final String relatedSlug;
  final String contentType;
  final String relatedContentType;
  final String type; // sequel | side_story | summary | spin_off | alternative_version | alternative_setting | adaptation

  const HikkaRelation({
    required this.slug,
    required this.relatedSlug,
    required this.contentType,
    required this.relatedContentType,
    required this.type,
  });

  factory HikkaRelation.fromJson(Map<String, dynamic> j) => HikkaRelation(
        slug: _str(j['slug']) ?? '',
        relatedSlug: _str(j['related_slug']) ?? '',
        contentType: _str(j['content_type']) ?? 'anime',
        relatedContentType: _str(j['related_content_type']) ?? 'anime',
        type: _str(j['relation_type']) ?? 'sequel',
      );
}

/// Відповідь `/related/anime/{slug}/franchise`: усі аніме франшизи й зв'язки між ними
/// (манґа й ранобе з відповіді відкидаються — каталог лише аніме).
class HikkaFranchiseData {
  final List<HikkaAnime> anime;
  final List<HikkaRelation> relations;

  const HikkaFranchiseData({required this.anime, required this.relations});

  factory HikkaFranchiseData.fromJson(Object? json) {
    final m = _map(json);
    return HikkaFranchiseData(
      anime: _list(m['anime'], HikkaAnime.fromJson),
      relations: _list(m['relations'], HikkaRelation.fromJson),
    );
  }
}

// ── Пошук у каталозі ─────────────────────────────────────────────────────────

class HikkaSortOption {
  final String key;
  final String label;

  /// Додаткові поля, що додаються до сортування (оцінка + кількість оцінок)
  final List<String> secondary;

  const HikkaSortOption(this.key, this.label, {this.secondary = const []});
}

const Object _unset = Object();

/// Умови пошуку в каталозі. Порожнє значення = «без обмеження».
class HikkaSearchFilters {
  static const List<HikkaSortOption> sorts = [
    HikkaSortOption('score', 'Оцінка MAL', secondary: ['scored_by']),
    HikkaSortOption('native_score', 'Оцінка Hikka', secondary: ['native_scored_by']),
    HikkaSortOption('scored_by', 'Популярність'),
    HikkaSortOption('start_date', 'Дата виходу'),
    HikkaSortOption('created', 'Нещодавно додані'),
  ];

  /// Сортування списків користувача (`POST /watch/{user}/list`): власні поля запису й поля тайтлу
  static const String defaultListSort = 'watch_updated';
  static const List<HikkaSortOption> listSorts = [
    HikkaSortOption('watch_updated', 'Нещодавно оновлені'),
    HikkaSortOption('watch_created', 'Дата додавання'),
    HikkaSortOption('watch_score', 'Моя оцінка', secondary: ['watch_created']),
    HikkaSortOption('score', 'Оцінка MAL', secondary: ['scored_by']),
    HikkaSortOption('start_date', 'Дата виходу'),
    HikkaSortOption('scored_by', 'Популярність'),
  ];

  /// Усі вікові рейтинги, крім хентаю
  static const List<String> safeRatings = ['g', 'pg', 'pg_13', 'r', 'r_plus'];

  final String query;
  final Set<String> mediaTypes;
  final Set<String> statuses;
  final Set<String> seasons;
  final Set<String> ratings;
  final Set<String> genres;
  final int? yearFrom;
  final int? yearTo;
  final int? scoreFrom;
  final int? scoreTo;
  final bool onlyTranslated;
  final String sort;
  final bool ascending;

  const HikkaSearchFilters({
    this.query = '',
    this.mediaTypes = const {},
    this.statuses = const {},
    this.seasons = const {},
    this.ratings = const {},
    this.genres = const {},
    this.yearFrom,
    this.yearTo,
    this.scoreFrom,
    this.scoreTo,
    this.onlyTranslated = false,
    this.sort = 'score',
    this.ascending = false,
  });

  HikkaSearchFilters copyWith({
    String? query,
    Set<String>? mediaTypes,
    Set<String>? statuses,
    Set<String>? seasons,
    Set<String>? ratings,
    Set<String>? genres,
    Object? yearFrom = _unset,
    Object? yearTo = _unset,
    Object? scoreFrom = _unset,
    Object? scoreTo = _unset,
    bool? onlyTranslated,
    String? sort,
    bool? ascending,
  }) =>
      HikkaSearchFilters(
        query: query ?? this.query,
        mediaTypes: mediaTypes ?? this.mediaTypes,
        statuses: statuses ?? this.statuses,
        seasons: seasons ?? this.seasons,
        ratings: ratings ?? this.ratings,
        genres: genres ?? this.genres,
        yearFrom: identical(yearFrom, _unset) ? this.yearFrom : yearFrom as int?,
        yearTo: identical(yearTo, _unset) ? this.yearTo : yearTo as int?,
        scoreFrom: identical(scoreFrom, _unset) ? this.scoreFrom : scoreFrom as int?,
        scoreTo: identical(scoreTo, _unset) ? this.scoreTo : scoreTo as int?,
        onlyTranslated: onlyTranslated ?? this.onlyTranslated,
        sort: sort ?? this.sort,
        ascending: ascending ?? this.ascending,
      );

  /// Пошуковий запис має щонайменше 2 символи (обмеження API)
  String? get effectiveQuery {
    final q = query.trim();
    return q.length >= 2 ? q : null;
  }

  /// Скільки груп фільтрів задано (без рядка пошуку й сортування)
  int get activeCount =>
      (mediaTypes.isNotEmpty ? 1 : 0) +
      (statuses.isNotEmpty ? 1 : 0) +
      (seasons.isNotEmpty ? 1 : 0) +
      (ratings.isNotEmpty ? 1 : 0) +
      (genres.isNotEmpty ? 1 : 0) +
      (yearFrom != null || yearTo != null ? 1 : 0) +
      (scoreFrom != null || scoreTo != null ? 1 : 0) +
      (onlyTranslated ? 1 : 0);

  bool get isDefault => activeCount == 0 && effectiveQuery == null && sort == 'score' && !ascending;

  /// Тіло запиту `POST /anime`. Хентай прибирається, якщо [allowAdult] вимкнено.
  Map<String, dynamic> toBody({required bool allowAdult}) {
    List<String> sorted(Set<String> s) => (s.toList()..sort());

    var ratingList = sorted(ratings);
    if (!allowAdult) {
      ratingList = ratingList.where((r) => r != 'rx').toList();
      if (ratingList.isEmpty) ratingList = List.of(safeRatings);
    }

    final option = [...sorts, ...listSorts].firstWhere((s) => s.key == sort, orElse: () => sorts.first);
    final dir = ascending ? 'asc' : 'desc';
    final sortList = ['${option.key}:$dir', for (final s in option.secondary) '$s:$dir'];

    final body = <String, dynamic>{'sort': sortList};
    final q = effectiveQuery;
    if (q != null) body['query'] = q;
    if (mediaTypes.isNotEmpty) body['media_type'] = sorted(mediaTypes);
    if (statuses.isNotEmpty) body['status'] = sorted(statuses);
    if (seasons.isNotEmpty) body['season'] = sorted(seasons);
    if (ratingList.isNotEmpty) body['rating'] = ratingList;
    if (genres.isNotEmpty) body['genres'] = sorted(genres);
    if (yearFrom != null || yearTo != null) body['years'] = [yearFrom, yearTo];
    if (scoreFrom != null || scoreTo != null) body['score'] = [scoreFrom, scoreTo];
    if (onlyTranslated) body['only_translated'] = true;
    return body;
  }
}
