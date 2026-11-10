import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../constants/app_constants.dart';

class AppFormatters {
  static final Map<String, String> _trackTitleCache = {};
  static final Map<String, String> _chapterTitleCache = {};

  static void clearTrackCache() {
    _trackTitleCache.clear();
    _chapterTitleCache.clear();
  }

  static String formatTime(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
  }

  static String formatSpeed(double s) {
    return s == s.toInt() ? '${s.toInt()}x' : '${s}x';
  }

  static IconData getSpeedIcon(double speed) {
    if (speed <= 1.05) return Symbols.speed_2_rounded;
    if (speed <= 1.35) return Symbols.speed_3_rounded;
    if (speed <= 1.60) return Symbols.speed_4_rounded;
    return Symbols.speed_rounded;
  }

  static String cleanMediaTitle(String raw) {
    if (raw.isEmpty) return "Відео";
    String title = raw.contains('?') ? raw.split('?').first : raw;
    try {
      title = Uri.decodeFull(title);
    } catch (_) {}

    if (title.contains('/') || title.contains('\\')) {
      final parts = title.split(RegExp(r'[/\\]')).where((p) => p.isNotEmpty).toList();
      if (parts.isNotEmpty) {
        title = parts.last;
      }
    }

    title = title.replaceAll(RegExp(r'\.(mp4|mkv|avi|mov|webm|flv|ts|m4v|m3u|m3u8|pls)$', caseSensitive: false), '');

    if (!title.contains(' ') && (title.contains('.') || title.contains('_'))) {
      title = title.replaceAll(RegExp(r'[._]'), ' ');
    }

    title = title.trim();

    if (RegExp(r'^\d+$').hasMatch(title)) {
      final numVal = int.tryParse(title) ?? 0;
      title = "Відео ${numVal > 0 ? numVal : 1}";
    }

    return title.isNotEmpty ? title : "Відео";
  }

  /// Переклад назви розділу. Результат запам'ятовується: функція компілює десятки
  /// регулярних виразів, а викликається з підписів, панелей і кнопки «Пропустити».
  static String translateChapterTitle(String rawTitle) {
    final cached = _chapterTitleCache[rawTitle];
    if (cached != null) return cached;
    final result = _translateChapterTitle(rawTitle);
    if (_chapterTitleCache.length > 500) _chapterTitleCache.clear();
    return _chapterTitleCache[rawTitle] = result;
  }

  static String _translateChapterTitle(String rawTitle) {
    if (rawTitle.isEmpty) return "Розділ";
    String title = rawTitle.trim();

    final Map<String, String> exactMap = {
      "prologue": "Вступ",
      "intro": "Опенінґ",
      "opening": "Опенінґ",
      "op": "Опенінґ",
      "outro": "Ендінґ",
      "ending": "Ендінґ",
      "ed": "Ендінґ",
      "credits": "Ендінґ",
      "preview": "Анонс",
      "recap": "Рекап",
      "eyecatch": "Айкетч",
      "part": "Частина",
      "scene": "Сцена",
      "chapter": "Розділ",
      "episode": "Серія",
    };

    title = title.replaceAllMapped(RegExp(r'\bpart\s*(\d+)\b', caseSensitive: false), (m) => "Частина ${m[1]}");
    title = title.replaceAllMapped(RegExp(r'\bchapter\s*(\d+)\b', caseSensitive: false), (m) => "Розділ ${m[1]}");
    title = title.replaceAllMapped(RegExp(r'\bepisode\s*(\d+)\b', caseSensitive: false), (m) => "Серія ${m[1]}");
    title = title.replaceAllMapped(RegExp(r'\bscene\s*(\d+)\b', caseSensitive: false), (m) => "Сцена ${m[1]}");

    exactMap.forEach((en, ukr) {
      title = title.replaceAll(RegExp('\\b$en\\b', caseSensitive: false), ukr);
    });

    return title;
  }

  static final List<MapEntry<String, String>> _sortedTagEntries = [
    const MapEntry("latin american", "латиноамериканська"),
    const MapEntry("latin-american", "латиноамериканська"),
    const MapEntry("latin america", "латиноамериканська"),
    const MapEntry("signs & songs", "написи та пісні"),
    const MapEntry("signs and songs", "написи та пісні"),
    const MapEntry("signs/songs", "написи та пісні"),
    const MapEntry("hong kong", "Гонконг"),
    const MapEntry("latam", "латиноамериканська"),
    const MapEntry("castilian", "кастильська"),
    const MapEntry("castillian", "кастильська"),
    const MapEntry("canadian", "канадська"),
    const MapEntry("parisian", "паризька"),
    const MapEntry("brazilian", "бразильська"),
    const MapEntry("brasil", "бразильська"),
    const MapEntry("european", "європейська"),
    const MapEntry("simplified", "спрощена"),
    const MapEntry("traditional", "традиційна"),
    const MapEntry("american", "американська"),
    const MapEntry("british", "британська"),
    const MapEntry("australian", "австралійська"),
    const MapEntry("mexican", "мексиканська"),
    const MapEntry("mainland", "материкова"),
    const MapEntry("taiwan", "Тайвань"),
    const MapEntry("forced", "форсовані"),
    const MapEntry("sdh", "SDH"),
    const MapEntry("commentary", "коментарі"),
    const MapEntry("signs", "написи"),
    const MapEntry("songs", "пісні"),
    const MapEntry("full", "повні"),
    const MapEntry("dub", "дубляж"),
    const MapEntry("dubbed", "дубляж"),
    const MapEntry("original", "оригінал"),
  ];

  static String formatTrackTitle(String? lang, String? rawTitle, {String? channels}) {
    final cacheKey = '${lang ?? ""}|${rawTitle ?? ""}';
    if (_trackTitleCache.containsKey(cacheKey)) {
      return _trackTitleCache[cacheKey]!;
    }

    final cleanLang = (lang ?? "").replaceAll("_", "-").trim().toLowerCase();
    final base = cleanLang.split("-").first;
    String langName = AppConstants.langMap[base] ?? AppConstants.langMap[cleanLang] ?? "";

    String title = (rawTitle ?? "").trim();
    title = title.replaceAll(RegExp(r'\b(unknown\d*|2\s*ch|6\s*ch|8\s*ch|2\.0|5\.1|7\.1|stereo|mono|channels?)\b', caseSensitive: false), '').trim();
    title = title.replaceAll(RegExp(r'[\(\[\{]\s*[\)\]\}]'), '').trim();

    String workingTitle = title.toLowerCase();
    List<String> tags = [];

    for (final entry in _sortedTagEntries) {
      final key = entry.key;
      final value = entry.value;

      if (workingTitle.contains(key) || cleanLang.contains(key)) {
        if (!tags.contains(value)) {
          tags.add(value);
        }
        workingTitle = workingTitle.replaceAll(key, '').trim();
        title = title.replaceAll(RegExp('\\b$key\\b', caseSensitive: false), '').trim();
      }
    }

    title = title.replaceAll(RegExp(r'[\(\[\{]\s*[\)\]\}]'), '').trim();
    final ctLower = title.toLowerCase();

    // Очищення тавтологій
    final bool isTautology = ctLower.isEmpty ||
        ctLower == "subs" ||
        ctLower == "sub" ||
        ctLower == "subtitles" ||
        ctLower == "subtitle" ||
        ctLower == "audio" ||
        ctLower == "audio track" ||
        ctLower == "english subs" ||
        ctLower == "english sub" ||
        ctLower == "english subtitles" ||
        ctLower == "japanese audio" ||
        ctLower == "und" ||
        ctLower == "default" ||
        ctLower == "null" ||
        ctLower == base ||
        ctLower == cleanLang ||
        (langName.isNotEmpty && ctLower == langName.toLowerCase());

    final bool hasMeaningfulTitle = !isTautology && title.isNotEmpty;

    List<String> details = [];
    if (hasMeaningfulTitle) {
      details.add(title);
    }
    details.addAll(tags);

    String result = "";
    if (langName.isNotEmpty) {
      if (details.isNotEmpty) {
        result = "$langName (${details.join(', ')})";
      } else {
        result = langName;
      }
    } else if (details.isNotEmpty) {
      result = details.join(', ');
    } else if (hasMeaningfulTitle) {
      result = title;
    } else {
      result = "Аудіо / Субтитри";
    }

    _trackTitleCache[cacheKey] = result;
    return result;
  }
}