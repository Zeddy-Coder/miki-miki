import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'anime4k_service.dart';
import 'app_log.dart';
import 'osd_message.dart';
import 'storage_service.dart';

/// Стан і керування Anime4K: режим, якість, увімкнено / вимкнено, пропуск для відео з великою
/// роздільністю. Не залежить від Player: команди mpv надходять через [command].
class Anime4kController extends ChangeNotifier {
  Anime4kController({required this.command, required this.osd});

  final MpvCommand command;
  final OsdSink osd;

  bool enabled = false;
  Anime4kMode mode = Anime4kMode.a;
  Anime4kQuality quality = Anime4kQuality.fast;

  /// Не застосовувати до відео з висотою від N пікселів (0 — застосовувати завжди)
  int skipHeight = 0;

  /// Шейдери зараз підключені до рушія
  bool applied = false;

  /// Тимчасово не застосовується: роздільність відео не менша за [skipHeight]
  bool skipped = false;

  /// Остання помилка (розпакування, команда mpv або компіляція шейдера)
  String? error;

  int _videoHeight = 0;

  /// Користувач увімкнув режим вручну — пропуск за роздільністю не діє до наступного файлу
  bool _forced = false;

  /// Чи змінювали ми `glsl-shaders` у рушії (щоб не стирати шейдери з власного mpv.conf)
  bool _touched = false;
  DateTime? _appliedAt;
  Future<void> _queue = Future.value();
  bool _disposed = false;

  /// Anime4K реально працює на поточному відео
  bool get active => enabled && applied && !skipped;

  int get videoHeight => _videoHeight;

  /// Короткий стан для підписів: «Режим A · Fast», «Вимкнено», «Пропущено (1080p)»
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

  /// Узгоджує рушій з поточним станом. Викликати після ініціалізації плеєра.
  Future<void> syncToEngine() => _sync(announce: false);

  Future<void> _sync({required bool announce, List<String> keys = const []}) {
    return _enqueue(() async {
      if (enabled && !skipped) {
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
        AppLog.i('anime4k', skipped ? 'пропущено: відео ${_videoHeight}p не потребує апскейлу' : 'вимкнено');
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

  bool _shouldSkip() => enabled && skipHeight > 0 && _videoHeight >= skipHeight && !_forced;

  /// Вибір режиму: вмикає Anime4K і застосовує ланцюжок (Ctrl+1…6)
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

  /// Вимкнення (Ctrl+0)
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

  /// Застосування налаштувань із діалогу (діє пропуск за роздільністю)
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

  /// Нова роздільність відео: пропускаємо або повертаємо Anime4K
  void onVideoHeight(int height) {
    _videoHeight = height;
    _reevaluateSkip();
  }

  /// Відкрито інший файл: ручний вибір режиму більше не перекриває пропуск
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

  /// Рядок логу mpv: якщо одразу після вмикання з'явилася помилка шейдера — вимикаємо Anime4K
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
