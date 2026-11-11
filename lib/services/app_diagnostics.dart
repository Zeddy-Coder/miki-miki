/// Глобальна діагностика: помилки Flutter, життєвий цикл застосунку, зміни розміру вікна, повільні кадри,
/// памʼять, стан пристрою (енергозбереження, нагрів, маршрут звуку) і навігація діалогами.
/// Усе пишеться в [AppLog]; налагоджувальні рядки лише в детальному режимі.
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../utils/platform_info.dart';
import 'app_log.dart';
import 'storage_service.dart';
import 'system_controls.dart';

class AppDiagnostics with WidgetsBindingObserver {
  AppDiagnostics._();

  static final AppDiagnostics instance = AppDiagnostics._();

  /// Позначка збірки в журналі
  static const String build = 'b52';

  bool _installed = false;
  Timer? _sampleTimer;
  Timer? _metricsTimer;
  String _lastMetrics = '';
  String _lastDevice = '';
  int _samples = 0;

  // Повільні кадри збираються у вікно 5 с, щоб не засмічувати журнал
  DateTime? _windowStart;
  int _frames = 0;
  int _slow = 0;
  int _worstUs = 0;
  int _worstBuildUs = 0;
  int _worstRasterUs = 0;

  /// Підключає перехоплення помилок і спостерігачі. Викликається один раз зі `main()`.
  void install() {
    if (_installed) return;
    _installed = true;

    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      try {
        final where = details.library == null ? '' : ' [${details.library}]';
        final ctx = details.context == null ? '' : ' — ${details.context!.toDescription()}';
        AppLog.e('помилка Flutter', '${details.exceptionAsString()}$where$ctx', null, details.stack);
      } catch (_) {}
      (previous ?? FlutterError.presentError)(details);
    };

    final previousAsync = ui.PlatformDispatcher.instance.onError;
    ui.PlatformDispatcher.instance.onError = (error, stack) {
      AppLog.e('необроблена помилка', '$error', null, stack);
      return previousAsync?.call(error, stack) ?? false;
    };

    WidgetsBinding.instance.addObserver(this);
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    _sampleTimer = Timer.periodic(const Duration(seconds: 15), (_) => unawaited(_sample()));
    unawaited(logEnvironment());
  }

  // ── Середовище ──────────────────────────────────────────────────────────────

  /// Запис про пристрій і налаштування на початку сесії (потрапляє і в шапку звіту)
  Future<void> logEnvironment() async {
    final env = <String>[];
    void add(String line) {
      env.add(line);
      AppLog.i('система', line);
    }

    add('Збірка: $build');
    add('Платформа: ${Platform.operatingSystem} ${Platform.operatingSystemVersion.split('\n').first}');
    add('Dart ${Platform.version.split(' ').first}; процесорів: ${Platform.numberOfProcessors}; мова: ${Platform.localeName}');
    try {
      final view = WidgetsBinding.instance.platformDispatcher.views.first;
      final hz = view.display.refreshRate;
      add('Екран: ${view.physicalSize.width.round()}×${view.physicalSize.height.round()} px, DPR ${view.devicePixelRatio.toStringAsFixed(2)}, ${hz.toStringAsFixed(0)} Гц');
      _lastMetrics = _metrics();
    } catch (_) {}

    final info = await SystemControls.deviceInfo();
    if (info != null) {
      add('Пристрій: ${info['model']}; Android ${info['android']}; ${info['hardware']}');
      add('Памʼять: ${info['ramTotalMb']} МБ, вільно ${info['ramFreeMb']} МБ; частота екрана ${_num(info['refreshHz'])} Гц');
      add('Звук: ${_route(info)}; системна частота ${info['audioRate']} Гц, буфер ${info['audioFrames']} кадрів');
      add('Стан: енергозбереження ${_yes(info['powerSave'])}, нагрів ${info['thermal'] ?? '—'}');
      _lastDevice = _deviceState(info);
    }

    add('Налаштування: декодер ${StorageService.getHwdec()}, швидкість ${StorageService.getDefaultPlaybackSpeed()}, '
        'орієнтація плеєра ${StorageService.getPlayerOrientation()}, детальний журнал ${StorageService.getDetailedLog() ? 'так' : 'ні'}');
    AppLog.instance.environment
      ..clear()
      ..addAll(env);
  }

  static String _yes(Object? v) => v == true ? 'так' : 'ні';
  static String _num(Object? v) => v is num ? v.toStringAsFixed(0) : '—';

  /// Маршрут звуку: куди зараз іде вихід (динамік, навушники, Bluetooth…)
  static String _route(Map<String, Object?> info) {
    final out = info['audioOut'];
    final devices = out is List ? out.join(', ') : '—';
    final bt = info['bluetoothA2dp'] == true ? '; активний Bluetooth A2DP' : '';
    final wired = info['wiredHeadset'] == true ? '; активні дротові навушники' : '';
    return 'виходи: $devices$bt$wired';
  }

  static String _deviceState(Map<String, Object?> info) =>
      '${info['powerSave']}|${info['thermal']}|${_route(info)}|${info['lowMemory']}';

  /// Опис маршруту звуку для запису про відкриття відео
  static Future<String> describeAudioRoute() async {
    final info = await SystemControls.deviceInfo();
    return info == null ? 'невідомо' : _route(info);
  }

  String _metrics() {
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final s = view.physicalSize;
    return '${s.width.round()}×${s.height.round()} @${view.devicePixelRatio.toStringAsFixed(2)} ${s.width > s.height ? 'альбомна' : 'портретна'}';
  }

  // ── Спостерігач життєвого циклу ─────────────────────────────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    AppLog.i('життєвий цикл', state.name);
    if (state != AppLifecycleState.resumed) {
      unawaited(AppLog.instance.flushNow());
      // Налаштування й токен входу не мають залежати від того, чи застосунок закрили «правильно»
      unawaited(StorageService.flush());
    }
  }

  @override
  void didHaveMemoryPressure() {
    AppLog.w('памʼять', 'система просить звільнити памʼять');
    unawaited(_sample(force: true));
  }

  @override
  void didChangeMetrics() {
    _metricsTimer?.cancel();
    _metricsTimer = Timer(const Duration(milliseconds: 400), () {
      try {
        final now = _metrics();
        if (now == _lastMetrics) return;
        _lastMetrics = now;
        AppLog.i('екран', 'змінилися розміри: $now');
      } catch (_) {}
    });
  }

  // ── Повільні кадри ──────────────────────────────────────────────────────────

  void _onTimings(List<ui.FrameTiming> timings) {
    if (!AppLog.on) return;
    final now = DateTime.now();
    _windowStart ??= now;
    for (final t in timings) {
      _frames++;
      final total = t.totalSpan.inMicroseconds;
      if (total > 40000) {
        _slow++;
        if (total > _worstUs) {
          _worstUs = total;
          _worstBuildUs = t.buildDuration.inMicroseconds;
          _worstRasterUs = t.rasterDuration.inMicroseconds;
        }
      }
    }
    final elapsed = now.difference(_windowStart!);
    if (elapsed < const Duration(seconds: 5)) return;
    if (_slow > 0) {
      AppLog.w(
        'кадри',
        'за ${elapsed.inSeconds} с: $_slow повільних (>40 мс) із $_frames; найгірший ${(_worstUs / 1000).toStringAsFixed(0)} мс '
            '(збірка ${(_worstBuildUs / 1000).toStringAsFixed(0)}, растр ${(_worstRasterUs / 1000).toStringAsFixed(0)})',
      );
    }
    _windowStart = now;
    _frames = 0;
    _slow = 0;
    _worstUs = 0;
    _worstBuildUs = 0;
    _worstRasterUs = 0;
  }

  // ── Періодичний знімок ресурсів ─────────────────────────────────────────────

  Future<void> _sample({bool force = false}) async {
    if (!AppLog.on && !force) return;
    _samples++;
    try {
      final rss = (ProcessInfo.currentRss / 1048576).toStringAsFixed(0);
      final cache = PaintingBinding.instance.imageCache;
      AppLog.d('ресурси', 'RSS $rss МБ; кеш зображень ${(cache.currentSizeBytes / 1048576).toStringAsFixed(0)} МБ (${cache.currentSize} шт.)');
    } catch (_) {}
    if (!AppPlatform.isAndroid) return;
    final info = await SystemControls.deviceInfo();
    if (info == null) return;
    final state = _deviceState(info);
    if (state != _lastDevice) {
      _lastDevice = state;
      AppLog.i('пристрій', 'змінився стан: енергозбереження ${_yes(info['powerSave'])}, нагрів ${info['thermal'] ?? '—'}, '
          '${_route(info)}, мало памʼяті: ${_yes(info['lowMemory'])}');
    } else if (_samples % 4 == 0) {
      AppLog.d('пристрій', 'вільно ${info['ramFreeMb']} МБ із ${info['ramTotalMb']} МБ');
    }
  }

  /// Зупиняє таймери (для завершення роботи)
  void dispose() {
    _sampleTimer?.cancel();
    _metricsTimer?.cancel();
    if (_installed) WidgetsBinding.instance.removeObserver(this);
    _installed = false;
  }
}

/// Записує відкриття й закриття екранів, діалогів і нижніх панелей
class AppNavObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    AppLog.i('навігація', 'відкрито ${_name(route)}${previousRoute == null ? '' : ' (поверх ${_name(previousRoute)})'}');
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    AppLog.i('навігація', 'закрито ${_name(route)}');
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    AppLog.d('навігація', 'прибрано ${_name(route)}');
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    AppLog.i('навігація', 'замінено ${oldRoute == null ? '?' : _name(oldRoute)} на ${newRoute == null ? '?' : _name(newRoute)}');
  }

  static String _name(Route<dynamic> r) {
    final n = r.settings.name;
    if (n != null && n.isNotEmpty) return n;
    return r.runtimeType.toString().replaceAll(RegExp(r'<.*>'), '');
  }
}
