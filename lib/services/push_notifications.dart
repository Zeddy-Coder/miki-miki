import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'app_log.dart';
import 'backend_client.dart';
import 'episode_alerts.dart';
import 'storage_service.dart';
import 'system_controls.dart';

/// Push notifications about new episodes (Android, Firebase Cloud Messaging).
///
/// The phone tells the backend which releases it follows (`slug|release id`, the same list `EpisodeAlerts.tracked()` uses for
/// the in-app notifications), and the backend checks the Mikai feed once every 30 minutes for everybody and sends a push for
/// the matches (`tools/backend/push.ts`). Nothing here runs without a Firebase config in the build: then the token is null
/// and the toggle simply reports that push is unavailable.
class PushNotifications extends ChangeNotifier {
  static PushNotifications instance = PushNotifications();
  static const String section = 'push';

  /// Hosts push needs; for a private DNS / proxy these are the allowlist entries (one per line when copied)
  static const List<String> requiredDomains = [
    'firebaseinstallations.googleapis.com',
    'fcmregistrations.googleapis.com',
    'fcm.googleapis.com',
    'mtalk.google.com',
    'android.googleapis.com',
    'miki-miki-729d9.web.app',
    'europe-west1-miki-miki-729d9.cloudfunctions.net',
  ];

  /// Re-send the subscription at least this often (the server forgets devices that stay silent for 90 days)
  static const Duration refreshEvery = Duration(days: 20);

  final SectionLoader _load;
  final SectionSaver _save;
  final bool Function() _supported;
  final Future<String?> Function() _token;
  final Future<bool> Function() _permission;
  final List<String> Function() _follows;
  final BackendClient Function() _backend;
  final int Function() _now;

  PushNotifications({
    SectionLoader? load,
    SectionSaver? save,
    bool Function()? supported,
    Future<String?> Function()? token,
    Future<bool> Function()? permission,
    List<String> Function()? follows,
    BackendClient Function()? backend,
    int Function()? now,
  }) : _load = load ?? (() => StorageService.getSection(section)),
       _save = save ?? ((d) => StorageService.saveSection(section, d)),
       _supported = supported ?? (() => Platform.isAndroid),
       _token = token ?? SystemControls.pushToken,
       _permission = permission ?? SystemControls.requestPushPermission,
       _follows = follows ?? _trackedFollows,
       _backend = backend ?? (() => BackendClient.instance),
       _now = now ?? (() => DateTime.now().millisecondsSinceEpoch);

  static List<String> _trackedFollows() => [
    for (final e in EpisodeAlerts.instance.tracked().entries)
      '${e.key}|${e.value}',
  ];

  late final Map<String, dynamic> _data = Map<String, dynamic>.of(_load());
  Timer? _timer;
  bool _busy = false;

  /// Push is only on Android
  bool get supported => _supported();

  bool get enabled => supported && ((_data['enabled'] as bool?) ?? false);

  /// The last attempt could not get a token or reach the backend (shown under the toggle)
  String? problem;

  bool get busy => _busy;

  /// Turns push on / off. On: asks for the notification permission (Android 13+), then subscribes.
  Future<void> setEnabled(bool value) async {
    if (!supported || _busy) return;
    problem = null;
    if (value && !await _permission()) {
      problem = 'Сповіщення вимкнені для застосунку в налаштуваннях телефону.';
      notifyListeners();
      return;
    }
    _data['enabled'] = value;
    _data.remove('sig');
    _save(_data);
    notifyListeners();
    await sync(force: true);
  }

  /// Background upkeep: now (after a pause) and every 15 minutes; the network is used only when the followed list changed
  void start() {
    _timer ??= Timer.periodic(
      const Duration(minutes: 15),
      (_) => unawaited(sync()),
    );
    unawaited(Future<void>.delayed(const Duration(seconds: 10), sync));
  }

  /// Sends the subscription if something changed since the last time (or [force])
  Future<void> sync({bool force = false}) async {
    if (!supported || _busy) return;
    final on = enabled;
    if (!on && _data['registered'] != true) return;
    _busy = true;
    try {
      final token = await _token();
      if (token == null || token.isEmpty) {
        if (on) {
          final why = SystemControls.lastPushError;
          final details = await SystemControls.pushDiagnose();
          problem =
              'Не вдалося отримати токен push${why == null ? '' : ': $why'}${details == null ? '' : '\n$details'}\nВимкніть VPN, проксі чи приватний DNS або додайте винятки для доменів нижче й спробуйте ще раз.';
          AppLog.w('push', problem!);
        }
        return;
      }
      final follows = on ? (_follows()..sort()) : const <String>[];
      final sig = '$on|$token|${follows.join(',')}';
      final fresh =
          _now() - ((_data['sent_at'] as num?)?.toInt() ?? 0) <
          refreshEvery.inMilliseconds;
      if (!force && _data['sig'] == sig && fresh) return;
      final ok = await _backend().pushRegister(token, follows, enabled: on);
      if (!ok) {
        problem = 'Не вдалося звʼязатися з сервером. Спробую пізніше.';
        return;
      }
      problem = null;
      _data['sig'] = sig;
      _data['sent_at'] = _now();
      _data['registered'] = on;
      _save(_data);
      AppLog.i(
        'push',
        on ? 'підписку надіслано: ${follows.length} релізів' : 'підписку знято',
      );
    } on BackendException catch (e) {
      problem = 'Не вдалося звʼязатися з сервером. Спробую пізніше.';
      AppLog.w('push', 'не вдалося: ${e.message}');
    } catch (e) {
      AppLog.w('push', 'не вдалося: $e');
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}
