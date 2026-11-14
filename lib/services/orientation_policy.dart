/// Phone screen orientation in the player.
///
/// The "Орієнтація плеєра" setting defines the orientation a video opens in. When the player leaves the screen
/// (exit to home or collapse into the mini player), the orientation from before it opened is restored.
/// The logic is separated from widgets and `SystemChrome` (passed in from outside), so it is tested.
library;

import 'package:flutter/services.dart';

/// Which orientation to enable when the player opens
enum PlayerOrientation {
  system('system', 'Як у системі'),
  landscape('landscape', 'Альбомна'),
  portrait('portrait', 'Портретна');

  final String id;
  final String label;
  const PlayerOrientation(this.id, this.label);

  static PlayerOrientation parse(String? id) =>
      PlayerOrientation.values.firstWhere((o) => o.id == id, orElse: () => PlayerOrientation.landscape);

  /// Allowed orientations (`null` means change nothing)
  List<DeviceOrientation>? get orientations => switch (this) {
        PlayerOrientation.system => null,
        PlayerOrientation.landscape => const [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight],
        PlayerOrientation.portrait => const [DeviceOrientation.portraitUp],
      };
}

class OrientationPolicy {
  OrientationPolicy({required this.apply, required this.preference, this.log});

  /// Passes the list of allowed orientations to the system (empty means auto-rotate by sensor)
  final Future<void> Function(List<DeviceOrientation> orientations) apply;

  /// The user's current setting
  final PlayerOrientation Function() preference;

  /// Log entry (optional)
  final void Function(String message)? log;

  List<DeviceOrientation> _current = const [];
  bool _locked = false;
  bool _inPlayer = false;
  List<DeviceOrientation>? _saved;
  bool _savedLocked = false;

  /// Rotation is locked (by the setting or the button); otherwise the sensor decides the orientation
  bool get locked => _locked;

  /// The player is currently on screen
  bool get inPlayer => _inPlayer;

  List<DeviceOrientation> get current => _current;

  /// The player appeared on screen: remember the current orientation and enable the one set in settings
  void enterPlayer() {
    if (_inPlayer) return;
    _inPlayer = true;
    _saved = List<DeviceOrientation>.of(_current);
    _savedLocked = _locked;
    final want = preference().orientations;
    log?.call('плеєр відкрито; до цього: ${_describe(_current, _locked)}; налаштування: ${preference().label}');
    if (want != null) _set(want, locked: true);
  }

  /// The player left the screen (exit or collapse): restore the orientation from before it
  void leavePlayer() {
    if (!_inPlayer) return;
    _inPlayer = false;
    final saved = _saved;
    _saved = null;
    if (saved == null) return;
    if (!_same(saved, _current) || _locked != _savedLocked) {
      log?.call('плеєр закрито; повертаю: ${_describe(saved, _savedLocked)}');
      _set(saved, locked: _savedLocked);
    }
  }

  /// The setting changed while the player is open
  void preferenceChanged() {
    if (!_inPlayer) return;
    final want = preference().orientations;
    if (want != null) {
      _set(want, locked: true);
    } else if (_saved != null) {
      _set(_saved!, locked: _savedLocked);
    }
  }

  /// Rotate button: portrait ↔ landscape (and locking the choice)
  void toggle({required bool landscapeNow}) {
    _set(
      landscapeNow
          ? const [DeviceOrientation.portraitUp]
          : const [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight],
      locked: true,
    );
  }

  /// Restores auto-rotate by sensor
  void unlock() {
    if (!_locked) return;
    _set(const [], locked: false);
  }

  void _set(List<DeviceOrientation> orientations, {required bool locked}) {
    _current = orientations;
    _locked = locked;
    apply(orientations);
  }

  static bool _same(List<DeviceOrientation> a, List<DeviceOrientation> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static String _describe(List<DeviceOrientation> o, bool locked) {
    if (o.isEmpty) return 'автоповорот';
    return '${locked ? 'зафіксовано' : 'дозволено'}: ${o.map((e) => e.name).join('+')}';
  }
}
