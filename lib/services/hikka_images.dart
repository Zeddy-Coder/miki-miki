/// Зображення каталогу Hikka: зменшені копії через сервіс зображень сайту, дисковий кеш і `ImageProvider`.
///
/// Постер повного розміру важить ~180 КБ, а картка в сітці — 100–200 px завширшки, тому запитуємо
/// зменшену копію (≈25 КБ). Кеш на диску тримається між запусками: повторне відкриття каталогу
/// не качає нічого. Завантаження йде в обмеженому паралелізмі, останній запит — першим
/// (картки, що саме на екрані, обганяють ті, що вже проскролили).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import '../constants/app_identity.dart';

class HikkaImages {
  const HikkaImages._();

  static const String resizer = 'https://img.hikka.io';

  /// Зменшена копія зображення через сервіс Hikka (imgproxy). Чужі адреси не чіпаємо.
  static String resized(String src, {int width = 0, int height = 0}) {
    final host = Uri.tryParse(src)?.host;
    if (host != 'cdn.hikka.io' || (width <= 0 && height <= 0)) return src;
    return '$resizer/insecure/rs:fit:$width:$height:0:0/plain/$src';
  }

  /// Ширина запиту в пікселях, округлена вгору до кроку 80: різні картки ділять один файл кешу
  static int bucket(double logicalWidth, double devicePixelRatio) {
    final px = logicalWidth * devicePixelRatio;
    return ((px / 80).ceil() * 80).clamp(80, 960);
  }

  /// Ім'я файлу кешу: FNV-1a (64 біти) від адреси, 16 шістнадцяткових цифр
  static String fileName(String url) {
    int h = 0xcbf29ce484222325;
    for (final b in utf8.encode(url)) {
      h ^= b;
      h *= 0x100000001b3;
    }
    // int у Dart знаковий: від'ємне число дало б '-…', тож виводимо дві половини окремо
    final hi = (h >>> 32).toRadixString(16).padLeft(8, '0');
    final lo = (h & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0');
    return '$hi$lo.img';
  }
}

typedef HikkaImageFetcher = Future<Uint8List> Function(String url);

/// Обмежувач паралелізму: черга працює як стек (останній запит обслуговується першим)
class _Gate {
  final int limit;
  int _active = 0;
  final List<Completer<void>> _waiting = [];

  _Gate(this.limit);

  Future<void> acquire() {
    if (_active < limit) {
      _active++;
      return Future.value();
    }
    final c = Completer<void>();
    _waiting.add(c);
    return c.future;
  }

  void release() {
    if (_waiting.isNotEmpty) {
      _waiting.removeLast().complete();
    } else {
      _active--;
    }
  }
}

class HikkaImageStore {
  /// Спільний екземпляр (у тестах підміняється)
  static HikkaImageStore instance = HikkaImageStore();

  static HttpClient? _client;

  static Future<Uint8List> _download(String url) async {
    final client = _client ??= HttpClient()
      ..connectionTimeout = const Duration(seconds: 12)
      ..idleTimeout = const Duration(seconds: 20)
      ..userAgent = AppIdentity.userAgent('Hikka images');
    final req = await client.getUrl(Uri.parse(url));
    final res = await req.close().timeout(const Duration(seconds: 25));
    if (res.statusCode != 200) {
      await res.drain<void>();
      throw HttpException('HTTP ${res.statusCode}', uri: Uri.parse(url));
    }
    final bytes = await consolidateHttpClientResponseBytes(res).timeout(const Duration(seconds: 40));
    if (bytes.isEmpty) throw HttpException('Порожня відповідь', uri: Uri.parse(url));
    return bytes;
  }

  final Directory? _dirOverride;
  final HikkaImageFetcher _fetch;
  final _Gate _gate;
  final int maxBytes;

  Directory? _dir;
  bool _pruned = false;
  final Map<String, Future<Uint8List>> _inflight = {};

  /// Скільки зображень реально завантажено з мережі (для тестів)
  int downloads = 0;

  HikkaImageStore({
    Directory? dir,
    HikkaImageFetcher? fetcher,
    int maxParallel = 6,
    this.maxBytes = 300 * 1024 * 1024,
  })  : _dirOverride = dir,
        _fetch = fetcher ?? _download,
        _gate = _Gate(maxParallel);

  Future<Directory?> _ensureDir() async {
    if (_dir != null) return _dir;
    try {
      final d = _dirOverride ?? Directory('${Directory.systemTemp.path}/${AppIdentity.dataDirName}/hikka_images');
      if (!await d.exists()) await d.create(recursive: true);
      return _dir = d;
    } catch (_) {
      return null; // без диска працюємо лише через мережу
    }
  }

  File _file(Directory d, String url) => File('${d.path}/${HikkaImages.fileName(url)}');

  /// Байти зображення: з диска або з мережі; [fallback] — запасна адреса, якщо основна не відповіла
  Future<Uint8List> load(String url, {String? fallback}) {
    // Тіло з фігурними дужками: `remove` повертає сам Future зі списку, і `whenComplete` чекав би на нього
    // самого (вічне очікування).
    return _inflight[url] ??= _load(url, fallback).whenComplete(() {
      _inflight.remove(url);
    });
  }

  Future<Uint8List> _load(String url, String? fallback) async {
    try {
      return await _loadOne(url);
    } catch (e) {
      if (fallback == null || fallback == url) rethrow;
      return _loadOne(fallback);
    }
  }

  Future<Uint8List> _loadOne(String url) async {
    final dir = await _ensureDir();
    if (dir != null) {
      final f = _file(dir, url);
      try {
        if (await f.exists()) {
          final bytes = await f.readAsBytes();
          if (bytes.isNotEmpty) return bytes;
        }
      } catch (_) {}
    }

    await _gate.acquire();
    Uint8List bytes;
    try {
      downloads++;
      bytes = await _fetch(url);
    } finally {
      _gate.release();
    }

    if (dir != null) {
      try {
        final f = _file(dir, url);
        final tmp = File('${f.path}.tmp');
        await tmp.writeAsBytes(bytes, flush: false);
        await tmp.rename(f.path);
        _pruneOnce(dir);
      } catch (_) {}
    }
    return bytes;
  }

  /// Видаляє файл з кешу (наприклад, якщо його не вдалося розкодувати)
  Future<void> evict(String url) async {
    final dir = await _ensureDir();
    if (dir == null) return;
    try {
      final f = _file(dir, url);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  /// Скільки місця займає дисковий кеш зображень, байт
  Future<int> diskSize() async {
    final dir = await _ensureDir();
    if (dir == null) return 0;
    var total = 0;
    try {
      await for (final e in dir.list()) {
        if (e is File) total += (await e.stat()).size;
      }
    } catch (_) {}
    return total;
  }

  /// Видаляє всі збережені зображення; повертає, скільки байт звільнено
  Future<int> clear() async {
    final dir = await _ensureDir();
    if (dir == null) return 0;
    var freed = 0;
    try {
      await for (final e in dir.list()) {
        if (e is! File) continue;
        try {
          final size = (await e.stat()).size;
          await e.delete();
          freed += size;
        } catch (_) {}
      }
    } catch (_) {}
    return freed;
  }

  /// Раз за запуск: якщо кеш перевищив ліміт, видаляє найстаріші файли до ~70 % ліміту
  void _pruneOnce(Directory dir) {
    if (_pruned) return;
    _pruned = true;
    unawaited(() async {
      try {
        final files = <(File, int, DateTime)>[];
        var total = 0;
        await for (final e in dir.list()) {
          if (e is! File) continue;
          final st = await e.stat();
          files.add((e, st.size, st.modified));
          total += st.size;
        }
        if (total <= maxBytes) return;
        files.sort((a, b) => a.$3.compareTo(b.$3));
        final target = (maxBytes * 0.7).round();
        for (final f in files) {
          if (total <= target) break;
          try {
            await f.$1.delete();
            total -= f.$2;
          } catch (_) {}
        }
      } catch (_) {}
    }());
  }
}

/// `ImageProvider` для зображень Hikka з дисковим кешем. Ключ — адреса (+ запасна адреса).
@immutable
class HikkaImage extends ImageProvider<HikkaImage> {
  final String url;
  final String? fallback;

  const HikkaImage(this.url, {this.fallback});

  @override
  Future<HikkaImage> obtainKey(ImageConfiguration configuration) => SynchronousFuture<HikkaImage>(this);

  @override
  ImageStreamCompleter loadImage(HikkaImage key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(
      codec: _load(key, decode),
      scale: 1.0,
      debugLabel: key.url,
      informationCollector: () => <DiagnosticsNode>[DiagnosticsProperty<ImageProvider>('Image provider', this)],
    );
  }

  Future<ui.Codec> _load(HikkaImage key, ImageDecoderCallback decode) async {
    final store = HikkaImageStore.instance;
    final bytes = await store.load(key.url, fallback: key.fallback);
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    try {
      return await decode(buffer);
    } catch (_) {
      unawaited(store.evict(key.url));
      rethrow;
    }
  }

  @override
  bool operator ==(Object other) => other is HikkaImage && other.url == url && other.fallback == fallback;

  @override
  int get hashCode => Object.hash(url, fallback);

  @override
  String toString() => 'HikkaImage("$url")';
}
