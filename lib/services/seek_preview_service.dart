import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Прев'ю для перемотки: окремий «безголовий» плеєр відкриває той самий локальний файл,
/// за наведенням на смужку прогресу перемотується на потрібний момент і робить маленький
/// знімок. Кадри кешуються в пам'яті по «кошиках» часу, тож повторне наведення миттєве.
/// Лог: префікс [SeekPrev].
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

  /// Фоновий плеєр звільняється, якщо ним не користувались стільки часу (кадри в кеші лишаються).
  /// Живий libmpv коштує пам'яті й відкритого файлу, а на телефоні ще й батареї.
  static const Duration idleRelease = Duration(seconds: 30);
  static Timer? _idleTimer;

  /// Тільки для тестів: підміняє створення фонового плеєра (справжній libmpv у тестах недоступний)
  @visibleForTesting
  static Future<Player?> Function(String uri)? debugPlayerFactory;

  // Результат supports() для поточного файлу: його викликають на кожну подію миші над смужкою,
  // тож щоразу питати файлову систему (stat) не можна — на мережевих шляхах це зависання.
  static String? _supportsUri;
  static bool _supportsValue = false;

  /// Лічильник змін: віджет слухає його й перемальовує кадр, коли з'являється новий.
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

  /// Готує сервіс до файлу (нічого не запускає, доки не буде першого запиту кадру)
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

  /// Кадр для моменту [t]: точний або найближчий уже готовий
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

  /// Фонова черга кадрів (напр. для списку розділів): виконується, коли немає термінових запитів
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

  /// Відмічає використання: до звільнення плеєра знову 30 с простою.
  /// Викликається лише при справжній роботі (новий запит кадру, готовий кадр), а не на кожну
  /// подію миші — кадри з кешу плеєра не потребують.
  static void _touch() {
    _idleTimer?.cancel();
    _idleTimer = Timer(idleRelease, _releaseIdlePlayer);
  }

  static void _releaseIdlePlayer() {
    _idleTimer = null;
    if (_busy || _wanted != null || _backlog.isNotEmpty) {
      // Ще працює (довгий кадр, черга) — перевіримо знову через повний час простою
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

      await prop('vf', 'scale=$previewWidth:-2'); // знімок одразу малий — швидке кодування
      await prop('hwdec', 'no');
      await prop('aid', 'no');
      await prop('sid', 'no');
      await prop('hr-seek', 'no'); // сік по ключових кадрах — значно швидше
      // Прев'ю не повинно красти процесор у основного відтворення: кілька потоків декодера замість «усі ядра»
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

      // чекаємо, поки позиція зміниться (сік завершився)
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
