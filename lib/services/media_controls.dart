import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'app_log.dart';

/// Windows media controls (System Media Transport Controls): the system volume / media overlay,
/// the lock screen and, most importantly, the play / pause / next / previous buttons of headphones and keyboards.
/// Implemented natively in `windows/runner/media_controls.cpp`, channel `miki_miki/media_controls`.
/// On other platforms every method is a safe no-op.
class MediaControls {
  MediaControls._();

  static const MethodChannel _channel = MethodChannel('miki_miki/media_controls');

  /// A system button was pressed: `play`, `pause`, `toggle`, `next`, `previous` or `stop`
  static void Function(String button)? onButton;

  static bool _bound = false;

  /// Last state sent to the native side: identical updates are skipped (the controller calls this often)
  static Map<String, Object?>? _last;

  /// Tests only: allows working with the channel off Windows
  @visibleForTesting
  static bool debugEnabled = false;

  static bool get active => Platform.isWindows || debugEnabled;

  /// Subscribes to button presses from the system. Called once at startup.
  static void init() {
    if (!active || _bound) return;
    _bound = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'button' && call.arguments is String) onButton?.call(call.arguments as String);
      return null;
    });
  }

  /// Publishes what is playing: the title, whether it plays now and which skip buttons are enabled.
  /// [thumbnail] is an optional http(s) address of a poster shown in the system overlay.
  static Future<void> update({
    required String title,
    String subtitle = '',
    required bool playing,
    bool hasPrevious = false,
    bool hasNext = false,
    String? thumbnail,
  }) async {
    if (!active) return;
    final state = <String, Object?>{
      'title': title,
      'subtitle': subtitle,
      'playing': playing,
      'hasPrevious': hasPrevious,
      'hasNext': hasNext,
      'thumbnail': thumbnail ?? '',
    };
    if (mapEquals(_last, state)) return;
    _last = state;
    await _call('update', state);
  }

  /// Nothing is playing: the system overlay disappears and the media keys go back to other apps
  static Future<void> clear() async {
    if (!active || _last == null) return;
    _last = null;
    await _call('clear');
  }

  static Future<void> _call(String method, [Object? args]) async {
    try {
      await _channel.invokeMethod<void>(method, args);
    } catch (e) {
      // A missing native side (e.g. an old build) must never break playback
      AppLog.w('медіа-клавіші', '$method: $e');
    }
  }
}
