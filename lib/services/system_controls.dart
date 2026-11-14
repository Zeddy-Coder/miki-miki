import 'dart:io' show Platform, Process, ProcessStartMode;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../utils/platform_info.dart';
import 'deep_links.dart';

/// Android capabilities Flutter lacks out of the box: picture-in-picture (PiP),
/// screen brightness and system volume. Implemented in `MainActivity.kt`, channel `miki_miki/system`.
/// On other platforms all methods are safe (they do nothing). The exception is [openUrl], which works everywhere.
class SystemControls {
  SystemControls._();

  static const MethodChannel _channel = MethodChannel('miki_miki/system');

  /// true while the app window is shown as a PiP thumbnail
  static final ValueNotifier<bool> inPip = ValueNotifier<bool>(false);

  /// The "pause / play" button in the PiP window (set by MainActivity)
  static void Function()? onPipToggle;

  /// Another app took / returned audio focus: `loss` (permanent), `transient` (a call etc.), `gain`
  static void Function(String event)? onAudioFocus;

  static bool _bound = false;

  /// Tests only: allows working with the channel off Android
  @visibleForTesting
  static bool debugEnabled = false;

  static bool get _active => AppPlatform.isAndroid || debugEnabled;

  /// Subscription to events from Android (entering / leaving PiP). Called once at startup.
  static void init() {
    if (!_active || _bound) return;
    _bound = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'pipChanged') inPip.value = call.arguments == true;
      if (call.method == 'pipToggle') onPipToggle?.call();
      if (call.method == 'audioFocus' && call.arguments is String) onAudioFocus?.call(call.arguments as String);
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

  /// Whether the device supports PiP
  static Future<bool> pipSupported() async => (await _call<bool>('pipSupported')) ?? false;

  /// Collapse the video into a PiP window. `width`/`height` are the frame proportions.
  static Future<bool> enterPip({int width = 16, int height = 9}) async =>
      (await _call<bool>('pipEnter', {'w': width, 'h': height})) ?? false;

  /// Enter PiP automatically when the user leaves the app (the "home" gesture);
  /// enabled only while a video is playing.
  static Future<void> setPipAuto(bool enabled, {int width = 16, int height = 9}) =>
      _call<void>('pipAuto', {'enabled': enabled, 'w': width, 'h': height});

  /// The icon of the button in the PiP window: pause (during playback) or "play"
  static Future<void> setPipPlaying(bool playing) => _call<void>('pipPlaying', {'playing': playing});

  /// Takes (true) or gives up (false) Android audio focus: while we hold it, other apps' music is paused.
  /// Returns whether focus was obtained.
  static Future<bool> setAudioFocus(bool enabled) async =>
      (await _call<bool>('audioFocus', {'enabled': enabled})) ?? false;

  /// Brightness the user set with a gesture in the video (null means untouched).
  /// Applies only inside the player: on home the system one comes back.
  static double? userBrightness;

  /// App screen brightness, 0..1
  static Future<double?> getBrightness() => _call<double>('getBrightness');
  static Future<void> setBrightness(double value) {
    userBrightness = value;
    return _call<void>('setBrightness', {'value': value});
  }

  /// Restores the system brightness (entering the home page)
  static Future<void> resetBrightness() => _call<void>('setBrightness', {'value': -1.0});

  /// Sets again the brightness the user set in the video (entering the player)
  static Future<void> restoreBrightness() {
    final v = userBrightness;
    return v == null ? Future<void>.value() : _call<void>('setBrightness', {'value': v});
  }

  /// Device, memory, power saving, screen refresh rate and audio route (for the log). Off Android, `null`.
  static Future<Map<String, Object?>?> deviceInfo() async {
    final raw = await _call<Map<Object?, Object?>>('deviceInfo');
    return raw?.map((k, v) => MapEntry('$k', v));
  }

  /// Opens an http(s) link in the default browser. false: the address is invalid or there is no browser.
  static Future<bool> openUrl(String url, {bool chooser = false}) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https') || uri.host.isEmpty) return false;
    if (_active) return (await _call<bool>('openUrl', {'url': uri.toString(), 'chooser': chooser})) ?? false;
    try {
      // The address is passed as a separate argument, without a shell: `&` and spaces in it break nothing
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

  /// FCM token of this phone; null if there is no Firebase in this build or off Android
  static Future<String?> pushToken() async {
    lastPushError = null;
    if (!_active) return null;
    try {
      return await _channel.invokeMethod<String>('pushToken');
    } on PlatformException catch (e) {
      lastPushError = '${e.code}: ${e.message}';
      debugPrint('[SystemControls] pushToken: $lastPushError');
      return null;
    } catch (e) {
      lastPushError = '$e';
      return null;
    }
  }

  /// Android: the pushes the native messaging service has received since the last call, as a JSON array (the inbox is emptied)
  static Future<String?> pushInbox() => _call<String>('pushInbox');

  /// Android: repeats the Firebase registration request from this phone and reports Google's answer (for push troubleshooting)
  static Future<String?> pushDiagnose() => _call<String>('pushDiagnose');

  /// Why the last [pushToken] call gave no token (for the log and the screen)
  static String? lastPushError;

  /// Android 13+: asks for permission to show notifications. true: allowed (or the question is not needed).
  static Future<bool> requestPushPermission() async => (await _call<bool>('pushPermission')) ?? false;

  /// The `miki://…` link the app was launched with (Android only; handed out once)
  static Future<String?> initialLink() => _call<String>('initialLink');

  /// System volume (the "media" stream), 0..1
  static Future<double?> getVolume() => _call<double>('getVolume');
  static Future<void> setVolume(double value) => _call<void>('setVolume', {'value': value});
}
