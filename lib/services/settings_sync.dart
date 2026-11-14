import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'app_log.dart';
import 'backend_client.dart';
import 'hikka_auth.dart';
import 'hikka_prefs.dart';
import 'storage_service.dart';
import 'ui_theme_service.dart';

/// What the sync reads and writes. In the app it is [StorageService]; tests pass a fake.
abstract class SyncStore {
  /// Current value of a synced key (null if absent)
  Object? read(String key);

  /// Writes (null removes) a synced key
  void write(String key, Object? value);

  /// Keys that exist right now beyond the fixed list (watch positions: `pos:hikka:<slug>#<episode>`)
  Iterable<String> dynamicKeys();

  /// The sync's own bookkeeping
  Map<String, dynamic> loadState();
  void saveState(Map<String, dynamic> state);
}

class _AppStore implements SyncStore {
  static const String section = 'settings_sync';
  static const String posPrefix = 'pos:';

  @override
  Object? read(String key) {
    if (key.startsWith(posPrefix)) return StorageService.allPlaybackPositions()[key.substring(posPrefix.length)];
    return StorageService.readRaw(key);
  }

  @override
  void write(String key, Object? value) {
    if (key.startsWith(posPrefix)) {
      StorageService.writePlaybackPosition(key.substring(posPrefix.length), value == null ? null : (value as num).toInt());
    } else {
      StorageService.writeRaw(key, value);
    }
  }

  @override
  Iterable<String> dynamicKeys() => [
        for (final k in StorageService.allPlaybackPositions().keys)
          if (k.startsWith('hikka:')) '$posPrefix$k',
      ];

  @override
  Map<String, dynamic> loadState() => Map<String, dynamic>.of(StorageService.getSection(section));

  @override
  void saveState(Map<String, dynamic> state) => StorageService.saveSection(section, state);
}

/// Result of a sync run (for the UI and tests)
class SyncOutcome {
  final bool ok;
  final int applied; // keys taken from the server
  final int sent; // keys the server did not have or had older
  final String? error;
  const SyncOutcome({required this.ok, this.applied = 0, this.sent = 0, this.error});
}

/// Keeps the same settings, themes and watch positions on every device of one Hikka account, through the app backend
/// (`syncGet` / `syncPut`, see `tools/backend/sync.ts`).
///
/// How it works. Every synced key has a value and a change time. Local changes are found by comparing the store with what
/// was seen at the last run (nothing has to call the sync when a setting changes); a changed key gets "now" as its time.
/// The server keeps one map `key → {v, t}`; on merge the newer time wins per key, a removal is a `v: null` entry.
/// A device that has never synced gives all its keys the time 1, so the account's data wins over fresh defaults.
/// Not synced (device-specific): hardware decoding, orientation, logging, local files and playlists, keys and secrets.
class SettingsSync extends ChangeNotifier {
  static SettingsSync instance = SettingsSync();

  /// Fixed list of synced keys: look, playback behaviour, languages, subtitles, titles
  static const List<String> keys = [
    'theme_mode', 'accent_color', 'ui_radius',
    'autoplay_next', 'default_playback_speed', 'seek_step', 'double_tap_seek', 'hold_to_speed_enabled', 'hold_to_speed_rate',
    'auto_skip_chapters', 'show_skip_button', 'pitch_correction',
    'hikka_title_lang', 'hikka_show_secondary', 'hikka_secondary_lang', 'hikka_allow_adult',
    'watch_team_priority', 'prefer_full_dub', 'watched_percent', 'watched_by_ending', 'known_teams',
    'default_audio_lang', 'audio_lang_priorities', 'sub_lang_priorities', 'default_sub_lang',
    'sub_font', 'sub_font_size', 'sub_text_color', 'sub_border_size', 'sub_border_color', 'sub_shadow_offset', 'sub_margin_y',
    'sub_bg_opacity', 'sub_ass_mode',
  ];

  /// Removed entries are kept this long so other devices learn about the removal
  static const Duration tombstoneTtl = Duration(days: 30);

  final SyncStore store;
  final BackendClient Function() backend;
  final String Function() token;
  final int Function() now;
  final VoidCallback? onApplied;

  SettingsSync({SyncStore? store, BackendClient Function()? backend, String Function()? token, int Function()? now, VoidCallback? onApplied})
      : store = store ?? _AppStore(),
        backend = backend ?? (() => BackendClient.instance),
        token = token ?? (() => HikkaAuth.instance.token),
        now = now ?? (() => DateTime.now().millisecondsSinceEpoch),
        onApplied = onApplied ?? _reloadLiveSettings;

  static void _reloadLiveSettings() {
    uiTheme.init();
    HikkaPrefs.instance.reload();
  }

  late final Map<String, dynamic> _state = store.loadState();
  Timer? _timer;
  bool _running = false;
  String? lastError;

  /// On by default once signed in; the person can turn it off in the account window
  bool get enabled => (_state['enabled'] as bool?) ?? true;

  set enabled(bool value) {
    if (value == enabled) return;
    _state['enabled'] = value;
    store.saveState(_state);
    notifyListeners();
    if (value) unawaited(sync());
  }

  /// When the last successful sync finished (ms since epoch; 0 = never)
  int get lastSync => (_state['last_sync'] as num?)?.toInt() ?? 0;

  bool get running => _running;

  Map<String, dynamic> get _last => (_state['last'] ??= <String, dynamic>{}) as Map<String, dynamic>;
  Map<String, dynamic> get _times => (_state['times'] ??= <String, dynamic>{}) as Map<String, dynamic>;

  /// Starts background syncing: a check every minute (a cheap local comparison; the network is used only when something
  /// changed locally or the last contact with the server was over 5 minutes ago). Call from `main` and on returning to the app.
  void start() {
    _timer ??= Timer.periodic(const Duration(minutes: 1), (_) => unawaited(sync(auto: true)));
    // Right after signing in (also on this device for the first time) pull the account's settings
    final auth = HikkaAuth.instance;
    var wasIn = auth.signedIn;
    auth.addListener(() {
      if (auth.signedIn && !wasIn) unawaited(sync());
      wasIn = auth.signedIn;
    });
    unawaited(Future<void>.delayed(const Duration(seconds: 8), () => sync(auto: true)));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Notes local changes: a key whose value differs from the previous run gets the current time
  int _detectLocalChanges() {
    final firstRun = !_state.containsKey('last');
    var changed = 0;
    final all = {...keys, ...store.dynamicKeys(), ..._last.keys};
    final stamp = now();
    for (final k in all) {
      final cur = jsonEncode(store.read(k));
      if (firstRun) {
        // Never synced on this device: its explicit values are older than anything on the account
        if (store.read(k) != null) _times[k] = 1;
        _last[k] = cur;
        continue;
      }
      if (_last[k] != cur) {
        _times[k] = stamp;
        _last[k] = cur;
        changed++;
      }
    }
    if (firstRun) _state['last_sync'] = 0;
    return changed;
  }

  /// One round: note local changes, fetch the server's map, merge per key, apply what won remotely, push what won locally.
  /// With [auto] the network is skipped when nothing changed locally and the last contact was recent.
  Future<SyncOutcome> sync({bool auto = false}) async {
    if (_running) return const SyncOutcome(ok: true);
    final t = token();
    if (!enabled || t.isEmpty) return const SyncOutcome(ok: true);
    _running = true;
    notifyListeners();
    try {
      final changed = _detectLocalChanges();
      store.saveState(_state);
      final recent = now() - lastSync < 5 * 60 * 1000;
      if (auto && changed == 0 && recent) return const SyncOutcome(ok: true);

      final (status, remote) = await backend().syncGet(t);
      if (status != 200) throw BackendException('сервер відповів $status', status: status);
      final remoteData = <String, Map<String, dynamic>>{
        for (final e in ((remote['data'] as Map?) ?? const {}).entries)
          if (e.value is Map) '${e.key}': (e.value as Map).cast<String, dynamic>(),
      };

      var applied = 0;
      var needPush = false;
      final merged = <String, dynamic>{};
      final stamp = now();
      for (final k in {...remoteData.keys, ..._times.keys}) {
        final r = remoteData[k];
        final rt = (r?['t'] as num?)?.toInt() ?? -1;
        final lt = (_times[k] as num?)?.toInt() ?? -1;
        if (r != null && rt >= lt) {
          // The server's value is as new or newer: take it
          final cur = jsonEncode(store.read(k));
          final incoming = jsonEncode(r['v']);
          if (cur != incoming) {
            store.write(k, r['v']);
            applied++;
          }
          _last[k] = incoming;
          _times[k] = rt;
          merged[k] = {'v': r['v'], 't': rt};
        } else if (lt >= 0) {
          // Ours is newer, or the server lacks the key
          needPush = true;
          merged[k] = {'v': store.read(k), 't': lt};
        }
      }
      // Old removals are no longer needed
      final cutoff = stamp - tombstoneTtl.inMilliseconds;
      merged.removeWhere((k, e) => e['v'] == null && (e['t'] as int) < cutoff);

      var sent = 0;
      if (needPush) {
        final (ps, _) = await backend().syncPut(t, merged);
        if (ps != 200) throw BackendException('сервер не зберіг налаштування ($ps)', status: ps);
        sent = merged.entries.where((e) => remoteData[e.key] == null || (remoteData[e.key]!['t'] as num).toInt() < (e.value['t'] as int)).length;
      }
      _state['last_sync'] = now();
      lastError = null;
      store.saveState(_state);
      if (applied > 0) {
        unawaited(StorageService.flush());
        onApplied?.call();
      }
      if (applied > 0 || sent > 0) AppLog.i('синхронізація', 'налаштування: отримано $applied, надіслано $sent');
      return SyncOutcome(ok: true, applied: applied, sent: sent);
    } on BackendException catch (e) {
      lastError = e.message;
      AppLog.w('синхронізація', 'не вдалося: ${e.message}');
      return SyncOutcome(ok: false, error: e.message);
    } catch (e) {
      lastError = '$e';
      AppLog.w('синхронізація', 'не вдалося: $e');
      return SyncOutcome(ok: false, error: '$e');
    } finally {
      _running = false;
      notifyListeners();
    }
  }
}
