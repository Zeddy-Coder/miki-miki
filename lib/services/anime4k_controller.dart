import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'anime4k_service.dart';
import 'app_log.dart';
import 'osd_message.dart';
import 'storage_service.dart';

/// State and control of Anime4K: mode, quality, on / off, skip for high-resolution
/// video. Independent of Player: mpv commands arrive through [command].
class Anime4kController extends ChangeNotifier {
  Anime4kController({required this.command, required this.osd});

  final MpvCommand command;
  final OsdSink osd;

  bool enabled = false;
  Anime4kMode mode = Anime4kMode.a;
  Anime4kQuality quality = Anime4kQuality.fast;

  /// Do not apply to videos with a height of N pixels or more (0 means always apply)
  int skipHeight = 0;

  /// Shaders are currently attached to the engine
  bool applied = false;

  /// Temporarily not applied: the video resolution is not below [skipHeight]
  bool skipped = false;

  /// Paused while the video is in a small window (mini player, picture-in-picture): the upscale cannot be seen there
  /// and only burns GPU. The setting itself (enabled / mode) is untouched and comes back when the window grows again.
  bool suspended = false;

  /// Last error (unpacking, mpv command or shader compilation)
  String? error;

  int _videoHeight = 0;

  /// The user enabled the mode manually: the resolution skip does not apply until the next file
  bool _forced = false;

  /// Whether we changed `glsl-shaders` in the engine (so we do not erase shaders from the user's own mpv.conf)
  bool _touched = false;
  DateTime? _appliedAt;
  Future<void> _queue = Future.value();
  bool _disposed = false;

  /// Anime4K is actually working on the current video
  bool get active => enabled && applied && !skipped && !suspended;

  int get videoHeight => _videoHeight;

  /// Short state for captions: "Режим A · Fast", "Вимкнено", "Пропущено (1080p)"
  String get summary {
    if (!enabled) return 'Вимкнено';
    if (skipped) return 'Пропущено (${_videoHeight}p)';
    return '${mode.title} · ${quality.label}';
  }

  void load() {
    enabled = StorageService.getAnime4kEnabled();
    mode = Anime4kMode.parse(StorageService.getAnime4kMode());
    quality = Anime4kQuality.parse(StorageService.getAnime4kQuality());
    skipHeight = StorageService.getAnime4kSkipHeight();
  }

  void _persist() {
    StorageService.saveAnime4kEnabled(enabled);
    StorageService.saveAnime4kMode(mode.name);
    StorageService.saveAnime4kQuality(quality.name);
    StorageService.saveAnime4kSkipHeight(skipHeight);
    StorageService.flush();
  }

  Future<void> _enqueue(Future<void> Function() job) {
    return _queue = _queue.then((_) async {
      if (!_disposed) await job();
    }).catchError((_) {});
  }

  /// Syncs the engine with the current state. Call after player initialization.
  Future<void> syncToEngine() => _sync(announce: false);

  Future<void> _sync({required bool announce, List<String> keys = const []}) {
    return _enqueue(() async {
      if (enabled && !skipped && !suspended) {
        final err = await Anime4kService.apply(command, mode, quality);
        _touched = true;
        if (err != null) {
          AppLog.w('anime4k', 'не вдалося застосувати ${mode.name}/${quality.name}: $err');
          applied = false;
          error = err;
          osd(OsdMessage(icon: Symbols.error_rounded, title: 'Anime4K', detail: err, isError: true),
              duration: const Duration(seconds: 5));
        } else {
          applied = true;
          error = null;
          _appliedAt = DateTime.now();
          AppLog.i('anime4k', 'застосовано: ${Anime4kService.describe(mode, quality)} (відео ${_videoHeight}p)');
          if (announce) {
            osd(OsdMessage(
              icon: Symbols.auto_awesome_rounded,
              title: 'Anime4K',
              detail: Anime4kService.describe(mode, quality),
              keys: keys,
            ));
          }
        }
      } else if (_touched || applied) {
        await Anime4kService.clear(command);
        applied = false;
        AppLog.i('anime4k', suspended && enabled ? 'призупинено: мале вікно (міні-плеєр / PiP)' : skipped ? 'пропущено: відео ${_videoHeight}p не потребує апскейлу' : 'вимкнено');
        if (announce) {
          osd(OsdMessage(
            icon: Symbols.auto_awesome_rounded,
            title: skipped ? 'Anime4K пропущено' : 'Anime4K вимкнено',
            detail: skipped ? 'Відео ${_videoHeight}p не потребує апскейлу' : null,
            keys: skipped ? const [] : keys,
          ));
        }
      }
      if (!_disposed) notifyListeners();
    });
  }

  /// Pauses / resumes the shaders for a small window (mini player, PiP). No OSD: the person did not ask for it.
  Future<void> setSuspended(bool value) {
    if (value == suspended) return Future.value();
    suspended = value;
    notifyListeners();
    return enabled ? _sync(announce: false) : Future.value();
  }

  bool _shouldSkip() => enabled && skipHeight > 0 && _videoHeight >= skipHeight && !_forced;

  /// Mode choice: enables Anime4K and applies the chain (Ctrl+1…6)
  Future<void> setMode(Anime4kMode newMode) {
    mode = newMode;
    enabled = true;
    _forced = true;
    skipped = false;
    _persist();
    notifyListeners();
    return _sync(announce: true, keys: ['Ctrl', '${newMode.digit}']);
  }

  Future<void> enable() {
    enabled = true;
    _forced = true;
    skipped = false;
    _persist();
    notifyListeners();
    return _sync(announce: true, keys: const ['Ctrl', '8']);
  }

  /// Turn off (Ctrl+0)
  Future<void> disable({bool announce = true}) {
    enabled = false;
    skipped = false;
    _persist();
    notifyListeners();
    return _sync(announce: announce, keys: const ['Ctrl', '0']);
  }

  Future<void> toggle() => enabled ? disable() : enable();

  Future<void> setQuality(Anime4kQuality newQuality) {
    quality = newQuality;
    _persist();
    notifyListeners();
    if (enabled && !skipped) return _sync(announce: true, keys: const ['Ctrl', '9']);
    osd(OsdMessage(
      icon: Symbols.auto_awesome_rounded,
      title: 'Якість Anime4K',
      detail: newQuality.title,
      keys: const ['Ctrl', '9'],
    ));
    return Future.value();
  }

  Future<void> toggleQuality() =>
      setQuality(quality == Anime4kQuality.fast ? Anime4kQuality.hq : Anime4kQuality.fast);

  /// Applying settings from the dialog (the resolution skip applies)
  Future<void> configure({
    required bool enabled,
    required Anime4kMode mode,
    required Anime4kQuality quality,
    required int skipHeight,
  }) {
    final changed = enabled != this.enabled ||
        mode != this.mode ||
        quality != this.quality ||
        skipHeight != this.skipHeight;
    if (!changed) return Future.value();
    this.enabled = enabled;
    this.mode = mode;
    this.quality = quality;
    this.skipHeight = skipHeight;
    _forced = false;
    skipped = _shouldSkip();
    _persist();
    notifyListeners();
    return _sync(announce: true);
  }

  /// New video resolution: skip or restore Anime4K
  void onVideoHeight(int height) {
    _videoHeight = height;
    _reevaluateSkip();
  }

  /// Another file opened: a manual mode choice no longer overrides the skip
  void onFileChanged() {
    _forced = false;
    _reevaluateSkip();
  }

  void _reevaluateSkip() {
    final was = skipped;
    skipped = _shouldSkip();
    if (skipped != was) {
      notifyListeners();
      _sync(announce: true);
    }
  }

  /// mpv log line: if a shader error appears right after enabling, turn Anime4K off
  void onEngineLog(String level, String text) {
    final at = _appliedAt;
    if (!applied || at == null) return;
    if (DateTime.now().difference(at) > const Duration(seconds: 8)) return;
    if (!Anime4kService.looksLikeShaderFailure(level, text)) return;
    _fail(text);
  }

  void _fail(String text) {
    AppLog.e('anime4k', 'помилка шейдера, Anime4K вимкнено: ${text.trim()}');
    error = text.trim();
    enabled = false;
    applied = false;
    _persist();
    osd(
      OsdMessage(
        icon: Symbols.error_rounded,
        title: 'Anime4K вимкнено',
        detail: 'Помилка шейдера — перевірте драйвер відеокарти або оберіть режим Fast',
        isError: true,
      ),
      duration: const Duration(seconds: 5),
    );
    notifyListeners();
    _enqueue(() async {
      await Anime4kService.clear(command);
    });
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
