import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../constants/app_identity.dart';

/// Прев'юшки відео: кеш на диску + фонова генерація кадру для тих файлів,
/// у яких прев'юшки ще немає.
///
/// Використання у віджетах: [watch] повертає [ValueNotifier] зі шляхом до
/// картинки (null, поки її немає). Якщо в кеші порожньо, прев'юшка ставиться в
/// чергу на генерацію й нотифікатор оновиться, коли вона буде готова.
/// Кожен [watch] має парний [unwatch] (див. AppMediaThumbnail).
class ThumbnailService {
  static const int thumbWidth = 480;
  static const int thumbHeight = 270;

  static String? _cacheDir;
  static final Map<String, String> _memoryCache = {};
  static final Map<String, ValueNotifier<String?>> _notifiers = {};
  static final Map<String, int> _refs = {};
  static final Set<String> _failed = {};
  static final Queue<String> _queue = Queue<String>();
  static String? _current;
  static bool _working = false;
  static DateTime _holdUntil = DateTime.fromMillisecondsSinceEpoch(0);

  /// Відкладає запуск фонової генерації (щоб не тягнути важкий старт mpv під час анімацій інтерфейсу)
  static void holdFor(Duration d) {
    final until = DateTime.now().add(d);
    if (until.isAfter(_holdUntil)) _holdUntil = until;
  }

  static void _log(String msg) => debugPrint('[Thumb] $msg');

  static Future<void> init() async {
    _ensureDir();
  }

  /// Синхронно створює теку кешу при першому зверненні (не залежить від main(),
  /// тож працює і після hot reload).
  static String? _ensureDir() {
    if (_cacheDir != null) return _cacheDir;
    try {
      String basePath;
      if (Platform.isWindows) {
        final appData = Platform.environment['APPDATA'] ?? Platform.environment['USERPROFILE'] ?? '.';
        basePath = '$appData\\${AppIdentity.dataDirName}\\thumbnails';
      } else {
        basePath = '${Directory.systemTemp.path}/${AppIdentity.dataDirName}/thumbnails';
      }
      Directory(basePath).createSync(recursive: true);
      _cacheDir = basePath;
      _log('cache dir: $basePath');
    } catch (e) {
      _log('cache dir FAILED: $e');
    }
    return _cacheDir;
  }

  // ── Ключі та шляхи ─────────────────────────────────────────────────────────

  /// Локальний шлях до файлу або null для мережевих потоків
  static String? _localPath(String uri) {
    final lower = uri.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://') || lower.startsWith('rtmp') || lower.startsWith('rtsp')) {
      return null;
    }
    if (lower.startsWith('file://')) {
      try {
        return Uri.parse(uri).toFilePath();
      } catch (_) {
        return null;
      }
    }
    return uri;
  }

  /// Відбиток файлу: шлях + розмір, щоб прев'юшка оновилась, якщо файл замінили
  static String _fingerprint(String uri) {
    final path = _localPath(uri);
    if (path != null) {
      try {
        final f = File(path);
        if (f.existsSync()) return '$uri|${f.lengthSync()}';
      } catch (_) {}
    }
    return uri;
  }

  /// Стабільний між запусками 64-бітний хеш (String.hashCode для цього не годиться)
  static String _key(String s) {
    int h1 = 0x811c9dc5;
    int h2 = 0x9747b28c;
    for (final u in s.codeUnits) {
      h1 = ((h1 ^ u) * 0x01000193) & 0xFFFFFFFF;
      h2 = (((h2 + u) * 0x85ebca6b) ^ (h2 >> 13)) & 0xFFFFFFFF;
    }
    return h1.toRadixString(16).padLeft(8, '0') + h2.toRadixString(16).padLeft(8, '0');
  }

  static String? _fileFor(String uri) {
    final dir = _ensureDir();
    if (dir == null) return null;
    final sep = Platform.isWindows ? '\\' : '/';
    return '$dir$sep${_key(_fingerprint(uri))}.png';
  }

  // ── Кеш ────────────────────────────────────────────────────────────────────

  static String? getCachedThumbnail(String uri) {
    final mem = _memoryCache[uri];
    if (mem != null) return mem;

    final path = _fileFor(uri);
    if (path == null) return null;
    final file = File(path);
    if (file.existsSync() && file.lengthSync() > 0) {
      _memoryCache[uri] = path;
      return path;
    }
    return null;
  }

  // ── Підписка з боку віджетів ───────────────────────────────────────────────

  static ValueNotifier<String?> watch(String uri) {
    final notifier = _notifiers.putIfAbsent(uri, () => ValueNotifier<String?>(getCachedThumbnail(uri)));
    _refs[uri] = (_refs[uri] ?? 0) + 1;

    if (notifier.value == null && !_failed.contains(uri) && _current != uri && !_queue.contains(uri)) {
      final path = _localPath(uri);
      if (path != null && File(path).existsSync()) {
        _log('queue: $path');
        _queue.add(uri);
        _pump();
      } else {
        _log('skip (not a local existing file): $uri');
      }
    }
    return notifier;
  }

  static void unwatch(String uri) {
    final left = (_refs[uri] ?? 1) - 1;
    if (left <= 0) {
      _refs.remove(uri);
      // Ніхто більше не дивиться: якщо генерація ще не почалась, прибираємо з черги
      if (_current != uri) _queue.remove(uri);
    } else {
      _refs[uri] = left;
    }
  }

  // ── Черга генерації (по одному файлу за раз) ───────────────────────────────

  static Future<void> _pump() async {
    if (_working) return;
    _working = true;
    try {
      while (_queue.isNotEmpty) {
        final wait = _holdUntil.difference(DateTime.now());
        if (wait > Duration.zero) await Future.delayed(wait);
        if (_queue.isEmpty) break;
        final uri = _queue.removeFirst();
        _current = uri;
        String? out;
        try {
          out = await _generate(uri).timeout(const Duration(seconds: 40));
        } catch (e, st) {
          _log('generate error: $e\n$st');
        }
        _current = null;

        if (out != null) {
          _log('done: $out');
          _memoryCache[uri] = out;
          _notifiers[uri]?.value = out;
        } else {
          _log('FAILED: $uri');
          _failed.add(uri);
        }
      }
    } finally {
      _working = false;
    }
  }

  /// Відкриває файл у тимчасовому «безголовому» плеєрі, перемотує на ~12% і робить знімок.
  static Future<String?> _generate(String uri) async {
    final path = _localPath(uri);
    if (path == null || !File(path).existsSync()) {
      _log('generate: file missing $uri');
      return null;
    }
    if (_ensureDir() == null) {
      _log('generate: no cache dir');
      return null;
    }
    _log('generate start: $path');

    final player = Player(
      configuration: const PlayerConfiguration(
        libass: false,
        bufferSize: 8 * 1024 * 1024,
        logLevel: MPVLogLevel.error,
      ),
    );
    try {
      final controller = VideoController(
        player,
        configuration: const VideoControllerConfiguration(
          width: thumbWidth,
          height: thumbHeight,
          enableHardwareAcceleration: false,
        ),
      );

      await player.setVolume(0);
      await player.open(Media(uri), play: false);
      _log('opened');

      Duration duration = Duration.zero;
      for (int i = 0; i < 60 && duration == Duration.zero; i++) {
        duration = player.state.duration;
        if (duration == Duration.zero) await Future.delayed(const Duration(milliseconds: 150));
      }
      _log('duration: $duration');
      if (duration == Duration.zero) return null;

      // Не одразу початок (чорний кадр/заставка), але й не пізніше 5 хвилин
      final ms = (duration.inMilliseconds * 0.12).round().clamp(0, 5 * 60 * 1000).toInt();
      await player.seek(Duration(milliseconds: ms));
      try {
        await controller.waitUntilFirstFrameRendered.timeout(const Duration(seconds: 8));
        _log('first frame rendered');
      } catch (e) {
        _log('first frame wait failed ($e), trying screenshot anyway');
      }
      await Future.delayed(const Duration(milliseconds: 500));

      // До 3 спроб: перший кадр після seek може ще не бути готовий
      for (int attempt = 1; attempt <= 3; attempt++) {
        Uint8List? bytes;
        try {
          bytes = await player.screenshot(format: 'image/png');
        } catch (e) {
          _log('screenshot attempt $attempt threw: $e');
        }
        if (bytes != null && bytes.isNotEmpty) {
          _log('screenshot ok: ${bytes.length} bytes');
          return await _saveResized(uri, bytes);
        }
        _log('screenshot attempt $attempt returned null');
        await Future.delayed(const Duration(milliseconds: 700));
      }
      return null;
    } finally {
      await player.dispose();
    }
  }

  /// Зменшує кадр до [thumbWidth] і зберігає у кеш як PNG
  static Future<String?> _saveResized(String uri, Uint8List bytes) async {
    final outPath = _fileFor(uri);
    if (outPath == null) return null;
    try {
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: thumbWidth);
      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      frame.image.dispose();
      codec.dispose();
      if (data == null) return null;
      await File(outPath).writeAsBytes(data.buffer.asUint8List());
      return outPath;
    } catch (e) {
      _log('save/resize failed: $e');
      return null;
    }
  }

  /// Зберігає знімок поточного кадру (з плеєра, що зараз грає) без повторного декодування файлу.
  static Future<void> saveLiveThumbnail(String uri, Uint8List bytes) async {
    if (bytes.isEmpty) return;
    final out = await _saveResized(uri, bytes);
    _log('live thumbnail ${out != null ? 'saved: $out' : 'FAILED'}');
    if (out != null) {
      _failed.remove(uri);
      _memoryCache[uri] = out;
      _notifiers[uri]?.value = out;
    }
  }
}
