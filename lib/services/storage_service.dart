import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier, visibleForTesting;

import '../constants/app_identity.dart';
import '../utils/platform_info.dart';

/// Reading / writing a separate state section (for services that must not call `StorageService` directly; replaced in tests)
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

      // App rename: data from the old folder moves to the new one (PC only; on Android the new
      // app has its own private folder)
      if (!Platform.isAndroid) {
        await AppIdentity.migrateLegacyData(Directory(_basePathFor(AppIdentity.legacyDataDirName)), Directory(basePath));
      }

      final dir = Directory(basePath);
      if (!await dir.exists()) await dir.create(recursive: true);

      _storageFile = File('$basePath/app_state.json');
      // Android: the state used to live in the cache (the system may clear it): we move it to a persistent folder
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
      // One time: auto-skipping openings is off by default (it could previously have stayed on)
      if (_cache['auto_skip_default_v2'] != true) {
        _cache['auto_skip_chapters'] = false;
        _cache['auto_skip_default_v2'] = true;
        _isDirty = true;
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
      // The app's private folder next to the cache: settings, history and positions do not vanish when the cache is cleared
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

  /// Audio delay (ms) of a single work; the key comes from `PlayerStateController.audioDelayKey`
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

  // --- Raw access for settings sync (`SettingsSync`) ---
  /// A top-level value by key (null if absent)
  static Object? readRaw(String key) => _cache[key];

  /// Writes (or, for null, removes) a top-level value
  static void writeRaw(String key, Object? value) {
    if (value == null) {
      _cache.remove(key);
    } else {
      _cache[key] = value;
    }
    _isDirty = true;
  }

  /// All saved positions (`path or hikka:<slug>#<episode>` → ms)
  static Map<String, int> allPlaybackPositions() {
    final m = _cache['playback_positions'];
    return m is Map ? {for (final e in m.entries) '${e.key}': (e.value as num).toInt()} : <String, int>{};
  }

  /// Sets / removes a position without the "almost finished" rules of [savePlaybackPosition]
  static void writePlaybackPosition(String key, int? ms) {
    _cache['playback_positions'] ??= <String, dynamic>{};
    final map = _cache['playback_positions'] as Map<String, dynamic>;
    if (ms == null) {
      map.remove(key);
    } else {
      map[key] = ms;
    }
    _isDirty = true;
  }

  // --- Arbitrary sections (watch-source data: links, progress, settings) ---
  static Map<String, dynamic> getSection(String key) {
    final v = _cache[key];
    return v is Map<String, dynamic> ? v : <String, dynamic>{};
  }

  static void saveSection(String key, Map<String, dynamic> value) {
    _cache[key] = value;
    _isDirty = true;
  }

  // --- External services: banners ---
  /// TheMovieDB key for fallback banners (empty means unused). Can also be passed at build time:
  /// `--dart-define=TMDB_KEY=…`
  static String getTmdbKey({String fallback = ''}) =>
      _cache['tmdb_key'] as String? ?? const String.fromEnvironment('TMDB_KEY', defaultValue: '');
  static void saveTmdbKey(String key) { _cache['tmdb_key'] = key.trim(); _isDirty = true; }

  // --- Hidden features ---
  /// The old local media library (open a file, file history, playlists): hidden, enabled in "Розробник"
  static bool getLocalLibrary({bool fallback = false}) => _cache['local_library'] as bool? ?? fallback;
  static void saveLocalLibrary(bool val) {
    _cache['local_library'] = val;
    _isDirty = true;
    _localLibrary?.value = val;
  }

  static ValueNotifier<bool>? _localLibrary;

  /// Listener for the local media library switch: "Профіль" shows the item right away, without a restart
  static ValueListenable<bool> get localLibraryListenable => _localLibrary ??= ValueNotifier<bool>(getLocalLibrary());

  // --- Theme settings ---
  static String getThemeMode({String fallback = 'system'}) => _cache['theme_mode'] as String? ?? fallback;
  static void saveThemeMode(String mode) { _cache['theme_mode'] = mode; _isDirty = true; }

  static String getAccentColorHex({String fallback = '#FFAA00'}) => _cache['accent_color'] as String? ?? fallback;
  static void saveAccentColorHex(String hex) { _cache['accent_color'] = hex; _isDirty = true; }

  static String getUiRadius({String fallback = 'MD'}) => _cache['ui_radius'] as String? ?? fallback;
  static void saveUiRadius(String r) { _cache['ui_radius'] = r; _isDirty = true; }

  // --- Playback settings ---
  static bool getAutoplayNext({bool fallback = true}) => _cache['autoplay_next'] as bool? ?? fallback;
  static void saveAutoplayNext(bool val) { _cache['autoplay_next'] = val; _isDirty = true; }

  static double getDefaultPlaybackSpeed({double fallback = 1.0}) => (_cache['default_playback_speed'] as num?)?.toDouble() ?? fallback;
  static void saveDefaultPlaybackSpeed(double speed) { _cache['default_playback_speed'] = speed; _isDirty = true; }

  static int getSeekStep({int fallback = 10}) => (_cache['seek_step'] as num?)?.toInt() ?? fallback;
  static void saveSeekStep(int step) { _cache['seek_step'] = step; _isDirty = true; }

  static bool getSeekButtons({bool fallback = false}) => _cache['seek_buttons'] as bool? ?? fallback;
  static void saveSeekButtons(bool val) { _cache['seek_buttons'] = val; _isDirty = true; }

  /// The ±step buttons on the phone player screen (on by default)
  static bool getMobileSeekButtons({bool fallback = true}) => _cache['mobile_seek_buttons'] as bool? ?? fallback;
  static void saveMobileSeekButtons(bool val) { _cache['mobile_seek_buttons'] = val; _isDirty = true; }

  static bool getDoubleTapSeek({bool fallback = true}) => _cache['double_tap_seek'] as bool? ?? fallback;
  static void saveDoubleTapSeek(bool val) { _cache['double_tap_seek'] = val; _isDirty = true; }

  static bool getHoldToSpeedEnabled({bool fallback = true}) => _cache['hold_to_speed_enabled'] as bool? ?? fallback;
  static void saveHoldToSpeedEnabled(bool val) { _cache['hold_to_speed_enabled'] = val; _isDirty = true; }

  static double getHoldToSpeedRate({double fallback = 2.0}) => (_cache['hold_to_speed_rate'] as num?)?.toDouble() ?? fallback;
  static void saveHoldToSpeedRate(double rate) { _cache['hold_to_speed_rate'] = rate; _isDirty = true; }

  static bool getAutoSkipChapters({bool fallback = false}) => _cache['auto_skip_chapters'] as bool? ?? fallback;
  static void saveAutoSkipChapters(bool val) { _cache['auto_skip_chapters'] = val; _isDirty = true; }

  /// The "Skip opening / ending" button in the player (shown by default)
  static bool getShowSkipButton({bool fallback = true}) => _cache['show_skip_button'] as bool? ?? fallback;
  static void saveShowSkipButton(bool val) { _cache['show_skip_button'] = val; _isDirty = true; }

  // --- Anime4K (upscaling shaders) ---
  static bool getAnime4kEnabled({bool fallback = false}) => _cache['anime4k_enabled'] as bool? ?? fallback;
  static void saveAnime4kEnabled(bool val) { _cache['anime4k_enabled'] = val; _isDirty = true; }

  /// Mode: a | b | c | aa | bb | ca
  static String getAnime4kMode({String fallback = 'a'}) => _cache['anime4k_mode'] as String? ?? fallback;
  static void saveAnime4kMode(String mode) { _cache['anime4k_mode'] = mode; _isDirty = true; }

  /// Chain quality: fast | hq
  static String getAnime4kQuality({String fallback = 'fast'}) => _cache['anime4k_quality'] as String? ?? fallback;
  static void saveAnime4kQuality(String quality) { _cache['anime4k_quality'] = quality; _isDirty = true; }

  /// Do not apply Anime4K to videos with a height of N pixels or more (0 means always apply)
  static int getAnime4kSkipHeight({int fallback = 0}) => (_cache['anime4k_skip_height'] as num?)?.toInt() ?? fallback;
  static void saveAnime4kSkipHeight(int height) { _cache['anime4k_skip_height'] = height; _isDirty = true; }

  // --- Hikka catalog ---
  /// Title language in the catalog: ua | en | ja
  static String getHikkaTitleLang({String fallback = 'ua'}) => _cache['hikka_title_lang'] as String? ?? fallback;
  static void saveHikkaTitleLang(String lang) { _cache['hikka_title_lang'] = lang; _isDirty = true; }

  /// Secondary title under the title-page heading: whether to show it and in which language (ua | en | ja)
  static bool getHikkaShowSecondary({bool fallback = true}) => _cache['hikka_show_secondary'] as bool? ?? fallback;
  static void saveHikkaShowSecondary(bool val) { _cache['hikka_show_secondary'] = val; _isDirty = true; }
  static String getHikkaSecondaryLang({String fallback = 'en'}) => _cache['hikka_secondary_lang'] as String? ?? fallback;
  static void saveHikkaSecondaryLang(String lang) { _cache['hikka_secondary_lang'] = lang; _isDirty = true; }

  /// Dub team priority: names (as on the sites), the most needed first; the "Дивитись" button picks the variant by them
  static List<String> getWatchTeamPriority() => [for (final x in (_cache['watch_team_priority'] as List? ?? const [])) '$x'];
  static void saveWatchTeamPriority(List<String> v) { _cache['watch_team_priority'] = v; _isDirty = true; }

  /// Prefer full dubs (from episode 1, no gaps and not shorter than the others): in the list and on the
  /// "Продовжити" button they rank above incomplete ones, wherever those stand in the priority. Off: only the team priority decides
  /// and whether the dub has the needed episode
  static bool getPreferFullDub({bool fallback = false}) => _cache['prefer_full_dub'] as bool? ?? fallback;
  static void savePreferFullDub(bool v) { _cache['prefer_full_dub'] = v; _isDirty = true; }

  /// After what share of an episode (in percent) it counts as watched; 85 by default
  static int getWatchedPercent({int fallback = 85}) => ((_cache['watched_percent'] as num?)?.toInt() ?? fallback).clamp(50, 100);
  static void saveWatchedPercent(int v) { _cache['watched_percent'] = v.clamp(50, 100); _isDirty = true; }

  /// Count an episode as watched earlier, when the ending is reached (by the dub's timestamps)
  static bool getWatchedByEnding({bool fallback = true}) => _cache['watched_by_ending'] as bool? ?? fallback;
  static void saveWatchedByEnding(bool v) { _cache['watched_by_ending'] = v; _isDirty = true; }

  /// Dub teams the app has already seen on the sites (newest first): the priority can be chosen from them in settings
  static List<String> getKnownTeams() => [for (final x in (_cache['known_teams'] as List? ?? const [])) '$x'];
  @visibleForTesting
  static void clearKnownTeams() { _cache.remove('known_teams'); }
  static void rememberTeams(Iterable<String> names) {
    final list = getKnownTeams();
    var changed = false;
    for (final raw in names) {
      final n = raw.trim();
      if (n.isEmpty) continue;
      final i = list.indexWhere((x) => x.toLowerCase() == n.toLowerCase());
      if (i == 0) continue;
      if (i > 0) list.removeAt(i);
      list.insert(0, n);
      changed = true;
    }
    if (!changed) return;
    _cache['known_teams'] = list.take(300).toList();
    _isDirty = true;
  }

  /// Show 18+ content (hentai); off by default
  static bool getHikkaAllowAdult({bool fallback = false}) => _cache['hikka_allow_adult'] as bool? ?? fallback;
  static void saveHikkaAllowAdult(bool val) { _cache['hikka_allow_adult'] = val; _isDirty = true; }

  // --- Keyboard ---
  /// Hotkey scheme: standard (↑/↓ volume, J/L seek) | mpv (as in mpv by default)
  static String getKeyScheme({String fallback = 'standard'}) => _cache['key_scheme'] as String? ?? fallback;
  static void saveKeyScheme(String scheme) { _cache['key_scheme'] = scheme; _isDirty = true; }

  // --- Audio and video engine ---
  static String getHwdec({String? fallback}) => _cache['hwdec'] as String? ?? fallback ?? AppPlatform.defaultHwdec;
  static Future<void> saveHwdec(String hwdec) async { _cache['hwdec'] = hwdec; _isDirty = true; await flush(); }

  static double getVolume({double fallback = 100.0}) => (_cache['volume'] as num?)?.toDouble() ?? fallback;
  static void saveVolume(double vol) { _cache['volume'] = vol; _isDirty = true; }

  static double getSpeed({double fallback = 1.0}) => (_cache['speed'] as num?)?.toDouble() ?? fallback;
  static void saveSpeed(double speed) { _cache['speed'] = speed; _isDirty = true; }

  static bool getPitchCorrection({bool fallback = true}) => _cache['pitch_correction'] as bool? ?? fallback;
  static void savePitchCorrection(bool val) { _cache['pitch_correction'] = val; _isDirty = true; }

  /// Phone player orientation: 'system' | 'landscape' | 'portrait' (see `PlayerOrientation`)
  static String getPlayerOrientation({String fallback = 'landscape'}) => _cache['player_orientation'] as String? ?? fallback;
  static void savePlayerOrientation(String v) { _cache['player_orientation'] = v; _isDirty = true; }

  /// Verbose log (writing almost all actions to a file). On by default during testing.
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

  // --- Subtitles ---
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

  static String getSubFont({String fallback = 'Arial'}) => _cache['sub_font'] as String? ?? fallback;
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

  // --- Last queue and playlists ---
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

  /// Last playback queue: {'items': List<Map<String,String>>, 'index': int} or null
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

  /// Playlists: [{'id','name','items','created'}], newest first
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
