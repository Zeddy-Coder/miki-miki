import 'dart:io' show Platform, Process, ProcessStartMode;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../utils/platform_info.dart';
import 'deep_links.dart';

/// Можливості Android, яких немає у Flutter «з коробки»: картинка в картинці (PiP),
/// яскравість екрана й системна гучність. Реалізація — у `MainActivity.kt`, канал `miki_miki/system`.
/// На інших платформах усі методи безпечні (нічого не роблять). Виняток — [openUrl], який працює скрізь.
class SystemControls {
  SystemControls._();

  static const MethodChannel _channel = MethodChannel('miki_miki/system');

  /// true, поки вікно застосунку відображається як мініатюра PiP
  static final ValueNotifier<bool> inPip = ValueNotifier<bool>(false);

  static bool _bound = false;

  /// Лише для тестів: дозволяє працювати з каналом не на Android
  @visibleForTesting
  static bool debugEnabled = false;

  static bool get _active => AppPlatform.isAndroid || debugEnabled;

  /// Підписка на події від Android (вхід / вихід із PiP). Викликається один раз при старті.
  static void init() {
    if (!_active || _bound) return;
    _bound = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'pipChanged') inPip.value = call.arguments == true;
      if (call.method == 'deepLink' && call.arguments is String) DeepLinks.handle(call.arguments as String);
      return null;
    });
  }

  static Future<T?> _call<T>(String method, [Object? args]) async {
    if (!_active) return null;
    try {
      return await _channel.invokeMethod<T>(method, args);
    } catch (e) {
      debugPrint('[SystemControls] $method: $e');
      return null;
    }
  }

  /// Чи підтримує пристрій PiP
  static Future<bool> pipSupported() async => (await _call<bool>('pipSupported')) ?? false;

  /// Згорнути відео у вікно PiP. `width`/`height` — пропорції кадру.
  static Future<bool> enterPip({int width = 16, int height = 9}) async =>
      (await _call<bool>('pipEnter', {'w': width, 'h': height})) ?? false;

  /// Автоматично входити в PiP, коли користувач виходить із застосунку (жест «додому») —
  /// вмикається лише поки відео відтворюється.
  static Future<void> setPipAuto(bool enabled, {int width = 16, int height = 9}) =>
      _call<void>('pipAuto', {'enabled': enabled, 'w': width, 'h': height});

  /// Яскравість, яку користувач виставив жестом у відео (null — не чіпав).
  /// Діє лише всередині плеєра: на головній повертається системна.
  static double? userBrightness;

  /// Яскравість екрана застосунку, 0..1
  static Future<double?> getBrightness() => _call<double>('getBrightness');
  static Future<void> setBrightness(double value) {
    userBrightness = value;
    return _call<void>('setBrightness', {'value': value});
  }

  /// Повертає системну яскравість (вхід на головну сторінку)
  static Future<void> resetBrightness() => _call<void>('setBrightness', {'value': -1.0});

  /// Знову ставить яскравість, яку користувач виставив у відео (вхід у плеєр)
  static Future<void> restoreBrightness() {
    final v = userBrightness;
    return v == null ? Future<void>.value() : _call<void>('setBrightness', {'value': v});
  }

  /// Пристрій, памʼять, енергозбереження, частота екрана й маршрут звуку (для журналу). Поза Android — `null`.
  static Future<Map<String, Object?>?> deviceInfo() async {
    final raw = await _call<Map<Object?, Object?>>('deviceInfo');
    return raw?.map((k, v) => MapEntry('$k', v));
  }

  /// Відкриває посилання http(s) у браузері за замовчуванням. false — адреса недійсна або браузера немає.
  static Future<bool> openUrl(String url, {bool chooser = false}) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https') || uri.host.isEmpty) return false;
    if (_active) return (await _call<bool>('openUrl', {'url': uri.toString(), 'chooser': chooser})) ?? false;
    try {
      // Адреса передається окремим аргументом, без оболонки: `&` та пробіли в ній нічого не ламають
      if (Platform.isWindows) {
        await Process.start('rundll32', ['url.dll,FileProtocolHandler', uri.toString()], mode: ProcessStartMode.detached);
      } else if (Platform.isMacOS) {
        await Process.start('open', [uri.toString()], mode: ProcessStartMode.detached);
      } else if (Platform.isLinux) {
        await Process.start('xdg-open', [uri.toString()], mode: ProcessStartMode.detached);
      } else {
        return false;
      }
      return true;
    } catch (e) {
      debugPrint('[SystemControls] openUrl: $e');
      return false;
    }
  }

  /// Посилання `miki://…`, з яким запущено застосунок (лише Android; віддається один раз)
  static Future<String?> initialLink() => _call<String>('initialLink');

  /// Системна гучність (потік «медіа»), 0..1
  static Future<double?> getVolume() => _call<double>('getVolume');
  static Future<void> setVolume(double value) => _call<void>('setVolume', {'value': value});
}
