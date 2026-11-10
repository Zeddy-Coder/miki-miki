import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;

import '../constants/app_identity.dart';
import '../utils/platform_info.dart';

/// Читання / запис окремого розділу стану (для сервісів, що не мають звертатись до `StorageService` напряму — у тестах підміняються)
typedef SectionLoader = Map<String, dynamic> Function();
typedef SectionSaver = void Function(Map<String, dynamic> data);

class StorageService {
  static late final File _storageFile;
  static Map<String, dynamic> _cache = {};
  static bool _initialized = false;
  static bool _isDirty = false;

  static Future<void> init() async {
    if (_initialized) return;

    try {
      final basePath = appBasePath;

      // Перейменування застосунку: дані зі старої теки переїжджають у нову (лише ПК; на Android у нового
      // застосунку своя приватна тека)
      if (!Platform.isAndroid) {
        await AppIdentity.migrateLegacyData(Directory(_basePathFor(AppIdentity.legacyDataDirName)), Directory(basePath));
      }

      final dir = Directory(basePath);
      if (!await dir.exists()) await dir.create(recursive: true);

      _storageFile = File('$basePath/app_state.json');
      // Android: раніше стан лежав у кеші (його може очистити система) — переносимо в постійну теку
      if (Platform.isAndroid && !await _storageFile.exists()) {
        final old = File('${Directory.systemTemp.path}/${AppIdentity.legacyDataDirName}/app_state.json');
        if (await old.exists()) {
          try {
            await old.copy(_storageFile.path);
          } catch (_) {}
        }
      }
      if (await _storageFile.exists()) {
        final content = await _storageFile.readAsString();
        if (content.isNotEmpty) _cache = jsonDecode(content) as Map<String, dynamic>;
      }
    } catch (_) {
      _cache = {};
    } finally {
      _initialized = true;
    }
  }

  static String get appBasePath => _basePathFor(AppIdentity.dataDirName);

  static String _basePathFor(String dirName) {
    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'] ?? Platform.environment['USERPROFILE'] ?? '.';
      return '$appData/$dirName';
    }
    if (Platform.isAndroid) {
      // Приватна тека застосунку поруч із кешем: налаштування, історія й позиції не зникають, коли кеш чистять
      return '${Directory.systemTemp.parent.path}/files/$dirName';
    }
    return '${Directory.systemTemp.path}/$dirName';
  }

  static Future<void> flush() async {
    if (!_isDirty) return;
    try {
      if (_initialized && await _storageFile.parent.exists()) {
        await _storageFile.writeAsString(jsonEncode(_cache));
        _isDirty = false;
      }
    } catch (_) {}
  }

  /// Затримка звуку (мс) окремого твору; ключ дає `PlayerStateController.audioDelayKey`
  static int getAudioDelay(String key) {
    final map = _cache['audio_delays'] as Map<String, dynamic>?;
    return map?[key] as int? ?? 0;
  }

  static void saveAudioDelay(String key, int ms) {
    if (key.isEmpty) return;
    _cache['audio_delays'] ??= <String, dynamic>{};
    final map = _cache['audio_delays'] as Map<String, dynamic>;
    if (ms == 0) {
      map.remove(key);
    } else {
      map[key] = ms;
    }
    _isDirty = true;
  }

  static int getPlaybackPosition(String path) {
    final positions = _cache['playback_positions'] as Map<String, dynamic>?;
    return positions?[path] as int? ?? 0;
  }

  static void savePlaybackPosition(String path, int positionMs, int durationMs) {
    if (path.isEmpty || durationMs <= 0) return;
    _cache['playback_positions'] ??= <String, dynamic>{};
    final map = _cache['playback_positions'] as Map<String, dynamic>;
    if (positionMs < 5000 || (durationMs - positionMs) < 10000) {
      map.remove(path);
    } else {
      map[path] = positionMs;
    }
    _isDirty = true;
  }

  // --- Довільні розділи (дані джерел перегляду: зв'язки, прогрес, налаштування) ---
  static Map<String, dynamic> getSection(String key) {
    final v = _cache[key];
    return v is Map<String, dynamic> ? v : <String, dynamic>{};
  }

  static void saveSection(String key, Map<String, dynamic> value) {
    _cache[key] = value;
    _isDirty = true;
  }

  // --- Зовнішні сервіси: банери ---
  /// Ключ TheMovieDB для запасних банерів (порожній — не використовується). Можна передати й під час збирання:
  /// `--dart-define=TMDB_KEY=…`
  static String getTmdbKey({String fallback = ''}) =>
      _cache['tmdb_key'] as String? ?? const String.fromEnvironment('TMDB_KEY', defaultValue: '');
  static void saveTmdbKey(String key) { _cache['tmdb_key'] = key.trim(); _isDirty = true; }

  // --- Приховані можливості ---
  /// Стара локальна медіатека (відкрити файл, історія файлів, плейлисти): прихована, вмикається в «Розробник»
  static bool getLocalLibrary({bool fallback = false}) => _cache['local_library'] as bool? ?? fallback;
  static void saveLocalLibrary(bool val) {
    _cache['local_library'] = val;
    _isDirty = true;
    _localLibrary?.value = val;
  }

  static ValueNotifier<bool>? _localLibrary;

  /// Слухач перемикача локальної медіатеки: «Профіль» з'являється з пунктом одразу, без перезапуску
  static ValueListenable<bool> get localLibraryListenable => _localLibrary ??= ValueNotifier<bool>(getLocalLibrary());

  // --- Налаштування теми ---
  static String getThemeMode({String fallback = 'dark'}) => _cache['theme_mode'] as String? ?? fallback;
  static void saveThemeMode(String mode) { _cache['theme_mode'] = mode; _isDirty = true; }

  static String getAccentColorHex({String fallback = '#E46767'}) => _cache['accent_color'] as String? ?? fallback;
  static void saveAccentColorHex(String hex) { _cache['accent_color'] = hex; _isDirty = true; }

  static String getUiRadius({String fallback = 'MD'}) => _cache['ui_radius'] as String? ?? fallback;
  static void saveUiRadius(String r) { _cache['ui_radius'] = r; _isDirty = true; }

  // --- Налаштування відтворення ---
  static bool getAutoplayNext({bool fallback = true}) => _cache['autoplay_next'] as bool? ?? fallback;
  static void saveAutoplayNext(bool val) { _cache['autoplay_next'] = val; _isDirty = true; }

  static double getDefaultPlaybackSpeed({double fallback = 1.0}) => (_cache['default_playback_speed'] as num?)?.toDouble() ?? fallback;
  static void saveDefaultPlaybackSpeed(double speed) { _cache['default_playback_speed'] = speed; _isDirty = true; }

  static int getSeekStep({int fallback = 10}) => (_cache['seek_step'] as num?)?.toInt() ?? fallback;
  static void saveSeekStep(int step) { _cache['seek_step'] = step; _isDirty = true; }

  static bool getSeekButtons({bool fallback = false}) => _cache['seek_buttons'] as bool? ?? fallback;
  static void saveSeekButtons(bool val) { _cache['seek_buttons'] = val; _isDirty = true; }

  /// Кнопки ±крок на екрані плеєра на телефоні (за замовчуванням є)
  static bool getMobileSeekButtons({bool fallback = true}) => _cache['mobile_seek_buttons'] as bool? ?? fallback;
  static void saveMobileSeekButtons(bool val) { _cache['mobile_seek_buttons'] = val; _isDirty = true; }

  static bool getDoubleTapSeek({bool fallback = true}) => _cache['double_tap_seek'] as bool? ?? fallback;
  static void saveDoubleTapSeek(bool val) { _cache['double_tap_seek'] = val; _isDirty = true; }

  static bool getHoldToSpeedEnabled({bool fallback = true}) => _cache['hold_to_speed_enabled'] as bool? ?? fallback;
  static void saveHoldToSpeedEnabled(bool val) { _cache['hold_to_speed_enabled'] = val; _isDirty = true; }

  static double getHoldToSpeedRate({double fallback = 2.0}) => (_cache['hold_to_speed_rate'] as num?)?.toDouble() ?? fallback;
  static void saveHoldToSpeedRate(double rate) { _cache['hold_to_speed_rate'] = rate; _isDirty = true; }

  static bool getAutoSkipChapters({bool fallback = true}) => _cache['auto_skip_chapters'] as bool? ?? fallback;
  static void saveAutoSkipChapters(bool val) { _cache['auto_skip_chapters'] = val; _isDirty = true; }

  // --- Anime4K (шейдери апскейлу) ---
  static bool getAnime4kEnabled({bool fallback = false}) => _cache['anime4k_enabled'] as bool? ?? fallback;
  static void saveAnime4kEnabled(bool val) { _cache['anime4k_enabled'] = val; _isDirty = true; }

  /// Режим: a | b | c | aa | bb | ca
  static String getAnime4kMode({String fallback = 'a'}) => _cache['anime4k_mode'] as String? ?? fallback;
  static void saveAnime4kMode(String mode) { _cache['anime4k_mode'] = mode; _isDirty = true; }

  /// Якість ланцюжка: fast | hq
  static String getAnime4kQuality({String fallback = 'fast'}) => _cache['anime4k_quality'] as String? ?? fallback;
  static void saveAnime4kQuality(String quality) { _cache['anime4k_quality'] = quality; _isDirty = true; }

  /// Не застосовувати Anime4K до відео з висотою від N пікселів (0 — застосовувати завжди)
  static int getAnime4kSkipHeight({int fallback = 0}) => (_cache['anime4k_skip_height'] as num?)?.toInt() ?? fallback;
  static void saveAnime4kSkipHeight(int height) { _cache['anime4k_skip_height'] = height; _isDirty = true; }

  // --- Каталог Hikka ---
  /// Мова назв у каталозі: ua | en | ja
  static String getHikkaTitleLang({String fallback = 'ua'}) => _cache['hikka_title_lang'] as String? ?? fallback;
  static void saveHikkaTitleLang(String lang) { _cache['hikka_title_lang'] = lang; _isDirty = true; }

  /// Показувати контент 18+ (хентай); за замовчуванням ні
  static bool getHikkaAllowAdult({bool fallback = false}) => _cache['hikka_allow_adult'] as bool? ?? fallback;
  static void saveHikkaAllowAdult(bool val) { _cache['hikka_allow_adult'] = val; _isDirty = true; }

  // --- Клавіатура ---
  /// Схема гарячих клавіш: standard (↑/↓ — гучність, J/L — перемотка) | mpv (як у mpv за замовчуванням)
  static String getKeyScheme({String fallback = 'standard'}) => _cache['key_scheme'] as String? ?? fallback;
  static void saveKeyScheme(String scheme) { _cache['key_scheme'] = scheme; _isDirty = true; }

  // --- Аудіо та відео рушій ---
  static String getHwdec({String? fallback}) => _cache['hwdec'] as String? ?? fallback ?? AppPlatform.defaultHwdec;
  static Future<void> saveHwdec(String hwdec) async { _cache['hwdec'] = hwdec; _isDirty = true; await flush(); }

  static double getVolume({double fallback = 100.0}) => (_cache['volume'] as num?)?.toDouble() ?? fallback;
  static void saveVolume(double vol) { _cache['volume'] = vol; _isDirty = true; }

  static double getSpeed({double fallback = 1.0}) => (_cache['speed'] as num?)?.toDouble() ?? fallback;
  static void saveSpeed(double speed) { _cache['speed'] = speed; _isDirty = true; }

  static bool getPitchCorrection({bool fallback = true}) => _cache['pitch_correction'] as bool? ?? fallback;
  static void savePitchCorrection(bool val) { _cache['pitch_correction'] = val; _isDirty = true; }

  /// Орієнтація плеєра на телефоні: 'system' | 'landscape' | 'portrait' (див. `PlayerOrientation`)
  static String getPlayerOrientation({String fallback = 'system'}) => _cache['player_orientation'] as String? ?? fallback;
  static void savePlayerOrientation(String v) { _cache['player_orientation'] = v; _isDirty = true; }

  /// Детальний журнал (запис майже всіх дій у файл). На час тестування увімкнений за замовчуванням.
  static bool getDetailedLog({bool fallback = true}) => _cache['detailed_log'] as bool? ?? fallback;
  static void saveDetailedLog(bool v) { _cache['detailed_log'] = v; _isDirty = true; }

  static String getDefaultAudioLang({String fallback = 'auto'}) => _cache['default_audio_lang'] as String? ?? fallback;
  static void saveDefaultAudioLang(String l) { _cache['default_audio_lang'] = l; _isDirty = true; }

  static List<String> getAudioLangPriorities({List<String> fallback = const ['ja', 'uk', 'en']}) {
    final list = _cache['audio_lang_priorities'];
    if (list is List && list.isNotEmpty) return List<String>.from(list);
    final single = getDefaultAudioLang(fallback: 'auto');
    if (single == 'auto') return ['ja', 'uk', 'en'];
    return [single, 'uk', 'en'].toSet().toList();
  }

  static void saveAudioLangPriorities(List<String> list) {
    _cache['audio_lang_priorities'] = list;
    _cache['default_audio_lang'] = list.isNotEmpty ? list.first : 'auto';
    _isDirty = true;
  }

  // --- Субтитри ---
  static List<String> getSubLangPriorities({List<String> fallback = const ['uk', 'ja', 'en']}) {
    final list = _cache['sub_lang_priorities'];
    if (list is List && list.isNotEmpty) return List<String>.from(list);
    final single = getDefaultSubLang(fallback: 'uk');
    if (single == 'no') return [];
    if (single == 'auto') return ['uk', 'ja', 'en'];
    return [single, 'ja', 'en'].toSet().toList();
  }

  static void saveSubLangPriorities(List<String> list) {
    _cache['sub_lang_priorities'] = list;
    _cache['default_sub_lang'] = list.isNotEmpty ? list.first : 'no';
    _isDirty = true;
  }

  static String getDefaultSubLang({String fallback = 'uk'}) => _cache['default_sub_lang'] as String? ?? fallback;
  static void saveDefaultSubLang(String lang) { _cache['default_sub_lang'] = lang; _isDirty = true; }

  static String getSubFont({String fallback = 'Trebuchet MS'}) => _cache['sub_font'] as String? ?? fallback;
  static void saveSubFont(String f) { _cache['sub_font'] = f; _isDirty = true; }

  static double getSubFontSize({double fallback = 48.0}) => (_cache['sub_font_size'] as num?)?.toDouble() ?? fallback;
  static void saveSubFontSize(double s) { _cache['sub_font_size'] = s; _isDirty = true; }

  static String getSubTextColor({String fallback = '#FFFFFF'}) => _cache['sub_text_color'] as String? ?? fallback;
  static void saveSubTextColor(String c) { _cache['sub_text_color'] = c; _isDirty = true; }

  static double getSubBorderSize({double fallback = 5.0}) => (_cache['sub_border_size'] as num?)?.toDouble() ?? fallback;
  static void saveSubBorderSize(double b) { _cache['sub_border_size'] = b; _isDirty = true; }

  static String getSubBorderColor({String fallback = '#000000'}) => _cache['sub_border_color'] as String? ?? fallback;
  static void saveSubBorderColor(String c) { _cache['sub_border_color'] = c; _isDirty = true; }

  static double getSubShadowOffset({double fallback = 2.0}) => (_cache['sub_shadow_offset'] as num?)?.toDouble() ?? fallback;
  static void saveSubShadowOffset(double sh) { _cache['sub_shadow_offset'] = sh; _isDirty = true; }

  static double getSubMarginY({double fallback = 36.0}) => (_cache['sub_margin_y'] as num?)?.toDouble() ?? fallback;
  static void saveSubMarginY(double m) { _cache['sub_margin_y'] = m; _isDirty = true; }

  static double getSubBgOpacity({double fallback = 0.0}) => (_cache['sub_bg_opacity'] as num?)?.toDouble() ?? fallback;
  static void saveSubBgOpacity(double o) { _cache['sub_bg_opacity'] = o; _isDirty = true; }

  static String getSubAssMode({String fallback = 'yes'}) => _cache['sub_ass_mode'] as String? ?? fallback;
  static void saveSubAssMode(String m) { _cache['sub_ass_mode'] = m; _isDirty = true; }

  static List<String> getCustomFonts() => List<String>.from(_cache['custom_fonts'] ?? []);
  static void addCustomFont(String path) {
    final list = getCustomFonts();
    if (!list.contains(path)) {
      list.add(path);
      _cache['custom_fonts'] = list;
      _isDirty = true;
    }
  }

  static List<String> getRecentFiles() => List<String>.from(_cache['recent_files'] ?? []);
  static void addRecentFile(String path) {
    final list = getRecentFiles();
    list.remove(path);
    list.insert(0, path);
    if (list.length > 20) list.removeLast();
    _cache['recent_files'] = list;
    _isDirty = true;
  }

  static void clearRecentFiles() {
    _cache['recent_files'] = [];
    _isDirty = true;
  }

  // --- Остання черга та плейлисти ---
  static List<Map<String, String>> _normItems(dynamic raw) {
    if (raw is! List) return [];
    final out = <Map<String, String>>[];
    for (final e in raw) {
      if (e is Map && e['uri'] is String && (e['uri'] as String).isNotEmpty) {
        out.add({'uri': e['uri'] as String, 'title': (e['title'] as String?) ?? ''});
      }
    }
    return out;
  }

  /// Остання черга відтворення: {'items': List<Map<String,String>>, 'index': int} або null
  static Map<String, dynamic>? getLastQueue() {
    final q = _cache['last_queue'];
    if (q is! Map) return null;
    final items = _normItems(q['items']);
    if (items.isEmpty) return null;
    final idx = ((q['index'] as num?)?.toInt() ?? 0).clamp(0, items.length - 1).toInt();
    return {'items': items, 'index': idx};
  }

  static void saveLastQueue(List<Map<String, String>> items, int index) {
    if (items.isEmpty) return;
    _cache['last_queue'] = {'items': items, 'index': index};
    _isDirty = true;
    flush();
  }

  static void clearLastQueue() {
    _cache.remove('last_queue');
    _isDirty = true;
    flush();
  }

  /// Плейлисти: [{'id','name','items','created'}], найновіші першими
  static List<Map<String, dynamic>> getPlaylists() {
    final raw = _cache['playlists'];
    if (raw is! List) return [];
    final out = <Map<String, dynamic>>[];
    for (final e in raw) {
      if (e is Map && e['id'] is String) {
        out.add({
          'id': e['id'] as String,
          'name': (e['name'] as String?) ?? 'Без назви',
          'items': _normItems(e['items']),
          'created': (e['created'] as num?)?.toInt() ?? 0,
        });
      }
    }
    return out;
  }

  static void _writePlaylists(List<Map<String, dynamic>> list) {
    _cache['playlists'] = list;
    _isDirty = true;
    flush();
  }

  static String createPlaylist(String name, List<Map<String, String>> items) {
    final now = DateTime.now();
    final id = now.microsecondsSinceEpoch.toString();
    final list = getPlaylists();
    list.insert(0, {'id': id, 'name': name, 'items': items, 'created': now.millisecondsSinceEpoch});
    _writePlaylists(list);
    return id;
  }

  static void updatePlaylist(String id, {String? name, List<Map<String, String>>? items}) {
    final list = getPlaylists();
    for (final pl in list) {
      if (pl['id'] == id) {
        if (name != null) pl['name'] = name;
        if (items != null) pl['items'] = items;
      }
    }
    _writePlaylists(list);
  }

  static void deletePlaylist(String id) {
    _writePlaylists(getPlaylists()..removeWhere((pl) => pl['id'] == id));
  }
}
