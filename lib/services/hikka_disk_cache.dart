/// Кеш відповідей Hikka на диску: застосунок стартує зі збережених даних (каталог, колекції, статті, розклад),
/// а не з порожніх скелетів, і працює без мережі. Один файл на запит; при збої запису все працює й без кешу.
library;

import 'dart:convert';
import 'dart:io';

import '../constants/app_identity.dart';
import 'app_log.dart';

class DiskHit {
  final Object? json;
  final DateTime at;
  const DiskHit(this.json, this.at);
}

class HikkaDiskCache {
  /// Скільки файлів тримаємо й як довго: старіше — видаляється при чищенні
  static const int maxFiles = 600;
  static const Duration maxAge = Duration(days: 14);

  final Directory? _dirOverride;
  Directory? _dir;
  bool _pruned = false;

  HikkaDiskCache({Directory? dir}) : _dirOverride = dir;

  Future<Directory?> _ensureDir() async {
    if (_dir != null) return _dir;
    try {
      final d = _dirOverride ?? Directory('${Directory.systemTemp.path}/${AppIdentity.dataDirName}/hikka_api');
      await d.create(recursive: true);
      return _dir = d;
    } catch (e) {
      AppLog.w('hikka', 'кеш відповідей на диску недоступний: $e');
      return null;
    }
  }

  /// Назва файлу з ключа запиту (FNV-1a 64 біт; ключ зберігається всередині файлу й перевіряється)
  static String fileName(String key) {
    var h = BigInt.parse('cbf29ce484222325', radix: 16);
    final prime = BigInt.parse('100000001b3', radix: 16);
    final mask = (BigInt.one << 64) - BigInt.one;
    for (final b in utf8.encode(key)) {
      h = ((h ^ BigInt.from(b)) * prime) & mask;
    }
    return '${h.toRadixString(16).padLeft(16, '0')}.json';
  }

  Future<DiskHit?> read(String key) async {
    final dir = await _ensureDir();
    if (dir == null) return null;
    try {
      final f = File('${dir.path}/${fileName(key)}');
      if (!await f.exists()) return null;
      final m = jsonDecode(await f.readAsString());
      if (m is! Map || m['k'] != key) return null;
      return DiskHit(m['j'], DateTime.fromMillisecondsSinceEpoch((m['at'] as num).toInt()));
    } catch (_) {
      return null;
    }
  }

  /// Записує у фоні; помилка запису не заважає роботі
  Future<void> write(String key, Object? json, DateTime at) async {
    final dir = await _ensureDir();
    if (dir == null) return;
    try {
      final f = File('${dir.path}/${fileName(key)}');
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(jsonEncode({'k': key, 'at': at.millisecondsSinceEpoch, 'j': json}), flush: false);
      await tmp.rename(f.path);
      if (!_pruned) {
        _pruned = true;
        _prune(dir);
      }
    } catch (e) {
      AppLog.w('hikka', 'запис кешу не вдався: $e');
    }
  }

  Future<void> clear() async {
    final dir = await _ensureDir();
    if (dir == null) return;
    try {
      await for (final e in dir.list()) {
        if (e is File) await e.delete();
      }
    } catch (_) {}
  }

  /// Раз за запуск: прибирає застарілі файли й лишає найновіші [maxFiles]
  void _prune(Directory dir) {
    Future(() async {
      try {
        final files = <File, DateTime>{};
        await for (final e in dir.list()) {
          if (e is File) files[e] = (await e.stat()).modified;
        }
        final cutoff = DateTime.now().subtract(maxAge);
        final sorted = files.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
        for (var i = 0; i < sorted.length; i++) {
          if (i >= maxFiles || sorted[i].value.isBefore(cutoff)) await sorted[i].key.delete();
        }
      } catch (_) {}
    });
  }
}
