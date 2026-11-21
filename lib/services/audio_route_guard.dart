import 'dart:async';

import 'app_log.dart';

/// Keeps the sound in step with the picture when the audio output changes (Android).
///
/// The delay of an output is measured when the player's audio output opens: Bluetooth adds 150–300 ms, the speaker
/// almost nothing. Headphones that connect or drop off mid-session left the old figure in place, and the sound lagged
/// or ran ahead of the picture until the app restarted. So on every change of the output devices the audio output is
/// reopened (`ao-reload`) once the route has settled; the picture and the position stay, the sound skips for a moment.
///
/// Headphones taken off (Android's "becoming noisy": a wired plug out, Bluetooth gone) pause playback, as other players
/// do, so the sound does not suddenly go out loud on the speaker.
class AudioRouteGuard {
  /// Reopens the player's audio output
  final Future<void> Function() reload;

  /// Something is open in the player (with nothing open there is no output to reopen)
  final bool Function() hasMedia;

  final bool Function() isPlaying;
  final void Function() pause;

  /// A line for the screen («Пауза: навушники відʼєднано»)
  final void Function(String text)? notice;

  /// Bluetooth reports a device in steps (connected, then the profile, then the codec): one reload after it settles
  final Duration settle;

  AudioRouteGuard({
    required this.reload,
    required this.hasMedia,
    required this.isPlaying,
    required this.pause,
    this.notice,
    this.settle = const Duration(milliseconds: 800),
  });

  Timer? _timer;
  String _route = '';

  /// Where the sound goes now («Bluetooth (A2DP)», «динамік»…), as Android last reported
  String get route => _route;

  /// The output devices changed: [change] is `added` / `removed`, [devices] what came or went, [route] where the
  /// sound goes now
  void routeChanged({required String change, List<String> devices = const [], String route = ''}) {
    if (route.isNotEmpty) _route = route;
    AppLog.i('звук', 'пристрої: ${change == 'added' ? 'підʼєднано' : 'відʼєднано'} ${devices.join(', ')}'
        '${route.isEmpty ? '' : '; звук іде на: $route'}');
    _timer?.cancel();
    _timer = Timer(settle, _reloadNow);
  }

  void _reloadNow() {
    _timer = null;
    if (!hasMedia()) return;
    AppLog.i('звук', 'вихід звуку перевідкрито під новий маршрут${_route.isEmpty ? '' : ' ($_route)'}');
    unawaited(reload());
  }

  /// Headphones came off
  void becomingNoisy() {
    if (!isPlaying()) return;
    AppLog.i('звук', 'навушники відʼєднано — пауза');
    pause();
    notice?.call('Пауза: навушники відʼєднано');
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
