/// Журнал подій плеєра та періодичний «знімок» синхронізації звуку й відео.
///
/// Слухає потоки `Player` (відтворення, буферизація, доріжки, помилки, лог libmpv) і кожні 3 с у детальному
/// режимі читає з рушія показники синхронізації: `avsync`, втрачені / запізнілі кадри, буфер, швидкість.
/// Відхилення (розбіжність A/V, втрата кадрів, зупинка позиції) пишуться як попередження.
library;

import 'dart:async';

import 'package:media_kit/media_kit.dart';

import '../utils/formatters.dart';
import 'app_diagnostics.dart';
import 'app_log.dart';

/// Знімок показників рушія (для порівняння з попереднім і для тестів)
class SyncSnapshot {
  final DateTime at;
  final Duration position;
  final bool playing;
  final bool buffering;
  final double rate;
  final double? avsync;
  final int drops;
  final int decoderDrops;
  final int voDrops;
  final int mistimed;
  final int delayed;

  const SyncSnapshot({
    required this.at,
    required this.position,
    required this.playing,
    required this.buffering,
    required this.rate,
    this.avsync,
    this.drops = 0,
    this.decoderDrops = 0,
    this.voDrops = 0,
    this.mistimed = 0,
    this.delayed = 0,
  });
}

/// Порівнює два знімки й повертає застереження (порожній список — усе гаразд)
List<String> analyzeSync(SyncSnapshot? prev, SyncSnapshot cur) {
  final out = <String>[];
  final a = cur.avsync;
  if (cur.playing && !cur.buffering && a != null && a.abs() > 0.1) {
    out.add('розбіжність звуку й відео: A/V ${a >= 0 ? '+' : ''}${a.toStringAsFixed(3)} с');
  }
  if (prev == null) return out;
  final dDrops = cur.drops - prev.drops;
  if (dDrops >= 8) out.add('втрата кадрів: +$dDrops за ${cur.at.difference(prev.at).inSeconds} с (декодер +${cur.decoderDrops - prev.decoderDrops}, вивід +${cur.voDrops - prev.voDrops})');
  final wall = cur.at.difference(prev.at).inMilliseconds / 1000.0;
  if (wall >= 2 && prev.playing && cur.playing && !prev.buffering && !cur.buffering) {
    final moved = (cur.position - prev.position).inMilliseconds / 1000.0;
    final expected = wall * cur.rate;
    if (expected > 0) {
      final ratio = moved / expected;
      if (ratio.abs() < 0.05) {
        out.add('позиція не рухається (${moved.toStringAsFixed(2)} с за ${wall.toStringAsFixed(1)} с) без буферизації');
      } else if (ratio > 0.05 && ratio < 0.7) {
        out.add('відтворення відстає: рух ×${ratio.toStringAsFixed(2)} від очікуваного');
      }
    }
  }
  return out;
}

class PlayerDiagnostics {
  PlayerDiagnostics(this.player, {this.context});

  final Player player;

  /// Додатковий текст у знімку (шейдери, джерело…)
  final String Function()? context;

  final List<StreamSubscription<dynamic>> _subs = [];
  Timer? _timer;
  bool _disposed = false;
  bool _sampling = false;
  SyncSnapshot? _prev;
  String? _describedUri;

  void start() {
    final s = player.stream;
    _subs.addAll([
      s.playing.listen((v) => AppLog.i('плеєр', '${v ? 'відтворення' : 'пауза'} на ${_pos()}')),
      s.buffering.listen((v) => AppLog.i('плеєр', v ? 'буферизація… (${_pos()})' : 'буферизація завершена (${_pos()})')),
      s.completed.listen((v) {
        if (v) AppLog.i('плеєр', 'кінець файлу');
      }),
      s.error.listen((m) => AppLog.e('плеєр', 'помилка рушія: $m')),
      s.duration.listen((d) {
        if (d > Duration.zero) unawaited(_onDuration(d));
      }),
      s.rate.listen((r) => AppLog.i('плеєр', 'швидкість ×$r')),
      s.volume.listen((v) => AppLog.d('плеєр', 'гучність ${v.toStringAsFixed(0)}')),
      s.track.listen((t) => AppLog.i('доріжки', 'вибрано: звук ${_track(t.audio.id, t.audio.title, t.audio.language)}; субтитри ${_track(t.subtitle.id, t.subtitle.title, t.subtitle.language)}')),
      s.tracks.listen((t) => AppLog.i('доріжки', 'доступно: відео ${t.video.length}, звук ${t.audio.length}, субтитри ${t.subtitle.length}')),
      s.audioParams.listen((p) => AppLog.i('звук', 'параметри: $p')),
      s.audioDevice.listen((d) => AppLog.i('звук', 'пристрій виводу libmpv: ${d.name}')),
      s.videoParams.listen((p) => AppLog.d('відео', 'параметри: $p')),
      s.playlist.listen((pl) => AppLog.i('плеєр', 'черга: ${pl.index + 1} із ${pl.medias.length}${pl.index >= 0 && pl.index < pl.medias.length ? ' — ${_short(pl.medias[pl.index].uri)}' : ''}')),
      s.log.listen(_onMpvLog),
    ]);
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => unawaited(sample()));
  }

  String _pos() => AppFormatters.formatTime(player.state.position);

  static String _track(String id, String? title, String? lang) {
    final parts = <String>[id, if (lang != null && lang.isNotEmpty) lang, if (title != null && title.isNotEmpty) '«$title»'];
    return parts.join(' ');
  }

  /// Коротка форма адреси (без довгого запиту)
  static String _short(String uri) {
    final q = uri.indexOf('?');
    final base = q < 0 ? uri : '${uri.substring(0, q)}?…';
    return base.length > 140 ? '${base.substring(0, 70)}…${base.substring(base.length - 60)}' : base;
  }

  String? _currentUri() {
    final pl = player.state.playlist;
    return pl.index >= 0 && pl.index < pl.medias.length ? pl.medias[pl.index].uri : null;
  }

  void _onMpvLog(PlayerLog log) {
    final text = log.text.trimRight();
    if (text.isEmpty) return;
    final line = '[${log.prefix}] $text';
    switch (log.level) {
      case 'fatal':
      case 'error':
        AppLog.e('mpv', line);
      case 'warn':
        AppLog.w('mpv', line);
      default:
        AppLog.d('mpv', line);
    }
  }

  Future<String?> _prop(String name) async {
    try {
      final dynamic platform = player.platform;
      if (platform == null) return null;
      final res = await platform.getProperty(name);
      final text = res?.toString();
      return (text == null || text.isEmpty) ? null : text;
    } catch (_) {
      return null;
    }
  }

  /// Відео відкрито: фіксуємо, чим його буде відтворено, і куди йде звук
  Future<void> _onDuration(Duration d) async {
    final uri = _currentUri();
    if (uri == null || uri == _describedUri) return;
    _describedUri = uri;
    _prev = null;
    AppLog.i('плеєр', 'файл готовий: ${_short(uri)}; тривалість ${AppFormatters.formatTime(d)}');
    unawaited(AppDiagnostics.describeAudioRoute().then((r) => AppLog.i('звук', 'маршрут при відкритті: $r')));
    try {
      const names = [
        'file-format',
        'video-format',
        'hwdec-current',
        'container-fps',
        'audio-codec-name',
        'current-ao',
        'audio-delay',
        'video-sync',
        'audio-buffer',
      ];
      final vals = await Future.wait(names.map(_prop));
      final w = player.state.width, h = player.state.height;
      AppLog.i(
        'плеєр',
        'формат ${vals[0] ?? '?'}; відео ${vals[1] ?? '?'} ${w ?? '?'}×${h ?? '?'} @${vals[3] ?? '?'} fps, декодер ${vals[2] ?? '?'}; '
            'звук ${vals[4] ?? '?'}, вивід ${vals[5] ?? '?'}, затримка ${vals[6] ?? '0'} с, буфер ${vals[8] ?? '?'} с; синхронізація ${vals[7] ?? '?'}',
      );
    } catch (_) {}
  }

  /// Один знімок показників рушія (викликається таймером; публічний для перевірки)
  Future<void> sample() async {
    if (_disposed || _sampling || !AppLog.on) return;
    final st = player.state;
    if (st.playlist.medias.isEmpty || st.duration <= Duration.zero) return;
    _sampling = true;
    try {
      const names = [
        'avsync',
        'frame-drop-count',
        'decoder-frame-drop-count',
        'vo-drop-frame-count',
        'mistimed-frame-count',
        'vo-delayed-frame-count',
        'estimated-vf-fps',
        'display-fps',
        'demuxer-cache-duration',
        'cache-buffering-state',
        'audio-delay',
        'hwdec-current',
      ];
      final v = await Future.wait(names.map(_prop));
      if (_disposed) return;
      final cur = SyncSnapshot(
        at: DateTime.now(),
        position: st.position,
        playing: st.playing,
        buffering: st.buffering,
        rate: st.rate,
        avsync: double.tryParse(v[0] ?? ''),
        drops: int.tryParse(v[1] ?? '') ?? 0,
        decoderDrops: int.tryParse(v[2] ?? '') ?? 0,
        voDrops: int.tryParse(v[3] ?? '') ?? 0,
        mistimed: int.tryParse(v[4] ?? '') ?? 0,
        delayed: int.tryParse(v[5] ?? '') ?? 0,
      );
      final extra = context?.call() ?? '';
      final avs = cur.avsync;
      AppLog.d(
        'синхронізація',
        'поз ${_pos()}${st.playing ? '' : ' (пауза)'}; A/V ${avs == null ? '—' : '${avs >= 0 ? '+' : ''}${avs.toStringAsFixed(3)}'}; '
            'кадри: втрачено ${cur.drops} (декодер ${cur.decoderDrops}, вивід ${cur.voDrops}), запізнілих ${cur.delayed}, невчасних ${cur.mistimed}; '
            'fps ${v[6] ?? '—'}/екран ${v[7] ?? '—'}; буфер ${v[8] ?? '—'} с (${v[9] ?? '—'} %); ×${st.rate}; зсув звуку ${v[10] ?? '0'} с; '
            'декодер ${v[11] ?? '—'}${extra.isEmpty ? '' : '; $extra'}',
      );
      for (final warning in analyzeSync(_prev, cur)) {
        AppLog.w('синхронізація', '$warning (поз ${_pos()}${extra.isEmpty ? '' : '; $extra'})');
      }
      _prev = cur;
    } catch (_) {
      // діагностика не має заважати відтворенню
    } finally {
      _sampling = false;
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    _subs.clear();
  }
}
