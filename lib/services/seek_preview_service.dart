import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Seek preview: a separate "headless" player opens the same local file,
/// seeks to the needed moment when hovering the progress bar and takes a small
/// snapshot. Frames are cached in memory by time "buckets", so repeated hovering is instant.
/// Log: prefix [SeekPrev].
class SeekPreviewService {
  static const int previewWidth = 320;

  static Player? _player;
  static String? _uri;
  static Future<Player?>? _opening;
  static int _bucketMs = 5000;
  static int _totalMs = 0;

  static final LinkedHashMap<int, Uint8List> _cache = LinkedHashMap();
  static final Set<int> _failed = {};
  static int? _wanted;
  static final Queue<int> _backlog = Queue<int>();
  static bool _busy = false;
  static int _generation = 0;

  /// The background player is released if it has not been used for this long (frames stay in the cache).
  /// A live libmpv costs memory and an open file, and on a phone also battery.
  static const Duration idleRelease = Duration(seconds: 30);
  static Timer? _idleTimer;

  /// Tests only: replaces creation of the background player (a real libmpv is unavailable in tests)
  @visibleForTesting
  static Future<Player?> Function(String uri)? debugPlayerFactory;

  // Result of supports() for the current file: it is called on every mouse event over the bar,
  // so asking the file system (stat) each time is not acceptable; on network paths that is a hang.
  static String? _supportsUri;
  static bool _supportsValue = false;

  /// Change counter: the widget listens to it and repaints the frame when a new one appears.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static void _log(String m) => debugPrint('[SeekPrev] $m');

  static bool supports(String? uri) {
    if (uri == null || uri.isEmpty) return false;
    if (uri == _supportsUri) return _supportsValue;
    final l = uri.toLowerCase();
    bool ok;
    if (l.contains('://') && !l.startsWith('file://')) {
      ok = false;
    } else {
      try {
        final path = l.startsWith('file://') ? Uri.parse(uri).toFilePath() : uri;
        ok = File(path).existsSync();
      } catch (_) {
        ok = false;
      }
    }
    _supportsUri = uri;
    _supportsValue = ok;
    return ok;
  }

  /// Prepares the service for a file (starts nothing until the first frame request)
  static void prepare(String? uri, Duration total) {
    if (uri == null || total <= Duration.zero) return;
    if (_uri != uri) {
      _reset();
      _uri = uri;
    }
    _totalMs = total.inMilliseconds;
    _bucketMs = (_totalMs / 200).clamp(2000, 10000).round();
  }

  static int _key(Duration t) => (t.inMilliseconds ~/ _bucketMs);

  /// Frame for moment [t]: exact or the nearest one already ready
  static Uint8List? frame(Duration t) {
    if (_cache.isEmpty) return null;
    final k = _key(t);
    final exact = _cache[k];
    if (exact != null) return exact;
    for (int d = 1; d <= 6; d++) {
      final a = _cache[k - d];
      if (a != null) return a;
      final b = _cache[k + d];
      if (b != null) return b;
    }
    return null;
  }

  static bool hasExact(Duration t) => _cache.containsKey(_key(t));

  static void request(Duration t) {
    final uri = _uri;
    if (uri == null || !supports(uri)) return;
    final k = _key(t);
    if (_cache.containsKey(k) || _failed.contains(k)) return;
    _wanted = k;
    _touch();
    _pump();
  }

  /// Background frame queue (e.g. for the chapter list): runs when there are no urgent requests
  static void requestMany(Iterable<Duration> times) {
    final uri = _uri;
    if (uri == null || !supports(uri)) return;
    for (final t in times) {
      final k = _key(t);
      if (!_cache.containsKey(k) && !_failed.contains(k) && !_backlog.contains(k)) _backlog.add(k);
    }
    _touch();
    _pump();
  }

  /// Marks usage: another 30 s of idle before the player is released.
  /// Called only on real work (a new frame request, a ready frame), not on every
  /// mouse event: frames from the player's cache do not need it.
  static void _touch() {
    _idleTimer?.cancel();
    _idleTimer = Timer(idleRelease, _releaseIdlePlayer);
  }

  static void _releaseIdlePlayer() {
    _idleTimer = null;
    if (_busy || _wanted != null || _backlog.isNotEmpty) {
      // Still working (a long frame, the queue): we check again after the full idle time
      _touch();
      return;
    }
    final p = _player;
    final opening = _opening;
    if (p == null && opening == null) return;
    _player = null;
    _opening = null;
    if (p != null) {
      p.dispose();
    } else {
      opening?.then((pl) => pl?.dispose());
    }
    _log('player released (idle)');
  }

  static Future<void> _pump() async {
    if (_busy) return;
    _busy = true;
    final gen = _generation;
    try {
      while ((_wanted != null || _backlog.isNotEmpty) && gen == _generation) {
        final k = _wanted ?? _backlog.removeFirst();
        if (_cache.containsKey(k)) {
          if (_wanted == k) _wanted = null;
          continue;
        }
        final bytes = await _capture(k);
        if (gen != _generation) return;
        if (bytes != null) {
          _cache[k] = bytes;
          while (_cache.length > 400) {
            _cache.remove(_cache.keys.first);
          }
          revision.value++;
        } else {
          _failed.add(k);
        }
        if (_wanted == k) _wanted = null;
        _touch();
      }
    } finally {
      _busy = false;
    }
  }

  static Future<Player?> _ensurePlayer() {
    return _opening ??= _createPlayer();
  }

  static Future<Player?> _createPlayer() async {
    final uri = _uri;
    if (uri == null) return null;
    final factory = debugPlayerFactory;
    if (factory != null) {
      final p = await factory(uri);
      _player = p;
      return p;
    }
    try {
      final p = Player(
        configuration: const PlayerConfiguration(
          libass: false,
          bufferSize: 4 * 1024 * 1024,
          logLevel: MPVLogLevel.error,
        ),
      );
      final controller = VideoController(
        p,
        configuration: const VideoControllerConfiguration(
          width: previewWidth,
          height: 180,
          enableHardwareAcceleration: false,
        ),
      );
      final dynamic plat = p.platform;
      Future<void> prop(String k, String v) async {
        try {
          await plat.setProperty(k, v);
        } catch (e) {
          _log('property $k failed: $e');
        }
      }

      await prop('vf', 'scale=$previewWidth:-2'); // the snapshot is small right away: fast encoding
      await prop('hwdec', 'no');
      await prop('aid', 'no');
      await prop('sid', 'no');
      await prop('hr-seek', 'no'); // seeking by keyframes is much faster
      // The preview must not steal CPU from the main playback: a few decoder threads instead of "all cores"
      await prop('vd-lavc-threads', '2');
      await prop('vd-lavc-fast', 'yes');
      await p.setVolume(0);
      await p.open(Media(uri), play: false);

      for (int i = 0; i < 40 && p.state.duration == Duration.zero; i++) {
        await Future.delayed(const Duration(milliseconds: 150));
      }
      try {
        await controller.waitUntilFirstFrameRendered.timeout(const Duration(seconds: 5));
      } catch (e) {
        _log('first frame wait failed: $e');
      }
      _log('player ready for $uri');
      _player = p;
      return p;
    } catch (e, st) {
      _log('create failed: $e\n$st');
      return null;
    }
  }

  static Future<Uint8List?> _capture(int key) async {
    try {
      final p = await _ensurePlayer();
      if (p == null) return null;

      final target = Duration(milliseconds: key * _bucketMs + _bucketMs ~/ 2);
      final before = p.state.position;
      await p.seek(target);

      // wait until the position changes (the seek finished)
      final done = Completer<void>();
      final sub = p.stream.position.listen((pos) {
        if (pos != before && !done.isCompleted) done.complete();
      });
      await done.future.timeout(const Duration(milliseconds: 700), onTimeout: () {});
      await sub.cancel();
      await Future.delayed(const Duration(milliseconds: 90));

      final bytes = await p.screenshot(format: 'image/jpeg');
      if (bytes == null || bytes.isEmpty) {
        _log('screenshot null for bucket $key');
        return null;
      }
      return bytes;
    } catch (e) {
      _log('capture error: $e');
      return null;
    }
  }

  static void _reset() {
    _idleTimer?.cancel();
    _idleTimer = null;
    _supportsUri = null;
    _generation++;
    _cache.clear();
    _failed.clear();
    _wanted = null;
    _backlog.clear();
    _busy = false;
    final opening = _opening;
    final p = _player;
    _player = null;
    _opening = null;
    _uri = null;
    revision.value++;
    if (p != null) {
      p.dispose();
    } else if (opening != null) {
      opening.then((pl) => pl?.dispose());
    }
  }

  static void dispose() => _reset();
}
