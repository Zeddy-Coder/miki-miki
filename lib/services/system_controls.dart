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

  /// The audio output devices changed (Bluetooth, wired, USB, HDMI): `change` is `added` / `removed`, `devices` what came
  /// or went, `route` where the sound goes now
  static void Function({required String change, List<String> devices, String route})? onAudioRoute;

  /// Headphones came off (Android's "becoming noisy")
  static void Function()? onAudioNoisy;

  /// The network changed (Android): online, metered (mobile data), type (`wifi`, `cellular` …)
  static void Function(bool online, bool metered, String type)? onNetwork;

  /// A button of the downloads notification: `pause`
  static void Function(String action)? onDownloadsAction;

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
      if (call.method == 'audioRoute' && call.arguments is Map) {
        final a = (call.arguments as Map).cast<String, Object?>();
        onAudioRoute?.call(
          change: '${a['change'] ?? ''}',
          devices: [for (final d in (a['devices'] as List?) ?? const []) '$d'],
          route: '${a['route'] ?? ''}',
        );
      }
      if (call.method == 'audioNoisy') onAudioNoisy?.call();
      if (call.method == 'network' && call.arguments is Map) {
        final a = call.arguments as Map;
        onNetwork?.call(a['online'] == true, a['metered'] == true, '${a['type'] ?? ''}');
      }
      if (call.method == 'downloadsAction' && call.arguments is String) onDownloadsAction?.call(call.arguments as String);
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

  /// How the app's recent processes ended after [since] (Android 11+, `ApplicationExitInfo`): reason, status,
  /// description, importance, memory, and the raw trace of a native crash / freeze. Off Android or older, empty.
  static Future<List<Map<String, Object?>>> exits(int since) async {
    final raw = await _call<List<Object?>>('exits', {'since': since});
    return [
      for (final e in raw ?? const <Object?>[])
        if (e is Map) e.map((k, v) => MapEntry('$k', v)),
    ];
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

  /// Android: hands a downloaded APK to the system installer. `started`: the installer opened; `permission`: the
  /// settings opened so the person allows Miki Miki to install apps ([askPermission]); `denied`: that permission is
  /// still missing ([askPermission] false). Anything else is why it failed
  static Future<String> installApk(String path, {bool askPermission = true}) async {
    if (!_active) return 'unsupported';
    try {
      return await _channel.invokeMethod<String>('installApk', {'path': path, 'ask': askPermission}) ?? 'failed';
    } on PlatformException catch (e) {
      return '${e.code}: ${e.message}';
    } catch (e) {
      return '$e';
    }
  }

  /// The network now (Android): online, metered, type; null elsewhere
  static Future<(bool, bool, String)?> networkState() async {
    final m = await _call<Map>('networkState');
    if (m == null) return null;
    return (m['online'] == true, m['metered'] == true, '${m['type'] ?? ''}');
  }

  /// Android: keeps downloads going in the background and with the screen off (a foreground service with a progress
  /// notification). [progress] 0…100, -1 — unknown; `active: false` stops the service
  static Future<void> downloadService({required bool active, String title = '', String text = '', int progress = -1}) =>
      _call<void>('downloadService', {'active': active, 'title': title, 'text': text, 'progress': progress});

  /// Free and total bytes on the storage where [path] lies (Android); null elsewhere
  static Future<(int, int)?> storageInfo(String path) async {
    final m = await _call<Map>('storageInfo', {'path': path});
    if (m == null) return null;
    return ((m['free'] as num?)?.toInt() ?? 0, (m['total'] as num?)?.toInt() ?? 0);
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
