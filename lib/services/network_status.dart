import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../utils/platform_info.dart';
import 'app_log.dart';
import 'system_controls.dart';

/// Is there internet, and is it metered (mobile data)? Downloads wait for Wi-Fi when asked to; the app shows what works
/// offline. Android reports changes itself (`ConnectivityManager`); on a PC a failed request makes us look (a name lookup),
/// and while offline we look again every [recheck].
class NetworkStatus extends ChangeNotifier {
  static NetworkStatus instance = NetworkStatus();

  /// How often to look again while offline (PC)
  final Duration recheck;

  /// Looks whether the internet answers (tests replace it)
  final Future<bool> Function() _probe;

  NetworkStatus({this.recheck = const Duration(seconds: 20), Future<bool> Function()? probe}) : _probe = probe ?? _lookup;

  bool _online = true;
  bool _metered = false;
  String _type = '';
  bool _started = false;
  final Completer<void> _first = Completer<void>();
  Timer? _timer;
  Future<bool>? _probing;

  bool get online => _online;

  /// The state comes from the system (Android), not from a guess after a failed request (PC): only then requests
  /// skip their retries while offline
  bool get certain => _certain;
  bool _certain = false;

  /// Downloads may go now: online and, when [wifiOnly], not on mobile data
  bool allows({required bool wifiOnly}) => _online && !(wifiOnly && _metered);

  /// The first real state is known (Android answered, or a PC needs none): downloads wait for it, so that the first
  /// seconds after the start do not go over mobile data. Never started (tests): at once
  Future<void> get ready => !_started || _first.isCompleted ? Future<void>.value() : _first.future.timeout(const Duration(seconds: 3), onTimeout: () {});

  /// Mobile data or a metered hotspot
  bool get metered => _metered;

  /// `wifi`, `cellular`, `ethernet` … (Android), empty when unknown
  String get type => _type;

  /// Starts listening (once, at startup)
  void start() {
    if (_started) return;
    _started = true;
    if (AppPlatform.isAndroid) {
      SystemControls.onNetwork = (online, metered, type) => apply(online: online, metered: metered, type: type, certain: true);
      unawaited(SystemControls.networkState().then((s) {
        if (s != null) apply(online: s.$1, metered: s.$2, type: s.$3, certain: true);
        if (!_first.isCompleted) _first.complete();
      }));
    } else {
      _first.complete();
      unawaited(check());
    }
  }

  /// A new state (from Android or a probe)
  void apply({required bool online, bool? metered, String? type, bool certain = false}) {
    if (certain) _certain = true;
    final changed = online != _online || (metered != null && metered != _metered) || (type != null && type != _type);
    if (online != _online) AppLog.i('мережа', online ? 'інтернет є${type == null || type.isEmpty ? '' : ' ($type)'}' : 'інтернету немає');
    _online = online;
    if (metered != null) _metered = metered;
    if (type != null) _type = type;
    _schedule();
    if (changed) notifyListeners();
  }

  /// A request failed for lack of connection: on a PC we look whether the internet is gone
  void reportFailure() {
    if (!AppPlatform.isAndroid) unawaited(check());
  }

  /// A request reached its server (over TLS, so not a captive portal): we are online, whatever was thought before
  void reportSuccess() {
    if (!_online) apply(online: true);
  }

  /// Looks now (PC; on Android the system knows better)
  Future<bool> check() => _probing ??= _probe().then((ok) {
        apply(online: ok);
        return ok;
      }).whenComplete(() => _probing = null);

  void _schedule() {
    _timer?.cancel();
    _timer = null;
    if (_online || AppPlatform.isAndroid) return;
    _timer = Timer(recheck, () => unawaited(check()));
  }

  static Future<bool> _lookup() async {
    try {
      final r = await InternetAddress.lookup('api.hikka.io').timeout(const Duration(seconds: 5));
      return r.isNotEmpty && r.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
