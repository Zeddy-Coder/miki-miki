/// Єдиний журнал застосунку.
///
/// Усі підсистеми пишуть сюди (`AppLog.i / w / e / d`). Кільцевий буфер у памʼяті є завжди (інформація,
/// попередження, помилки); у «детальному» режимі додатково фіксується налагоджувальний рівень, а все
/// дописується у файл сесії `<тека даних>/logs/miki_miki_<дата>_<час>.log` (ротація за розміром і кількістю).
/// Секрети (токени, ключі, паролі, cookie) маскуються ще до запису. Журнал ніколи не кидає винятків.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import '../constants/app_identity.dart';

/// Рівень запису
enum LogLevel {
  debug('D'),
  info('I'),
  warn('W'),
  error('E');

  final String letter;
  const LogLevel(this.letter);
}

class LogEntry {
  final DateTime time;
  final LogLevel level;
  final String tag;
  final String message;

  const LogEntry(this.time, this.level, this.tag, this.message);

  /// Рядок для файлу й звіту: `2026-11-03 14:30:12.345 I [тег] текст`
  String format() => '${AppLog.stamp(time, withDate: true)} ${level.letter} [$tag] $message';

  /// Короткий час для екрана
  String get clock => AppLog.stamp(time);

  @override
  String toString() => format();
}

class AppLog extends ChangeNotifier {
  /// Спільний екземпляр (у тестах підміняється)
  static AppLog instance = AppLog();

  AppLog({
    this.maxFileBytes = 6 * 1024 * 1024,
    this.maxFiles = 8,
    this.maxTotalBytes = 30 * 1024 * 1024,
    this.flushDelay = const Duration(milliseconds: 1200),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// Розмір одного файлу (далі починається наступна частина сесії)
  final int maxFileBytes;

  /// Скільки файлів журналу лишається на диску (найстаріші видаляються)
  final int maxFiles;

  /// Загальний розмір усіх файлів журналу
  final int maxTotalBytes;

  /// Як часто буфер скидається у файл (помилки — одразу)
  final Duration flushDelay;

  final DateTime Function() _now;

  static const int maxLineChars = 4000;
  static const int _ringNormal = 1500;
  static const int _ringDetailed = 8000;
  static const String filePrefix = '${AppIdentity.packageName}_';

  /// Префікс файлів під попередньою назвою застосунку: такі журнали теж читаються й прибираються за ротацією
  static const String legacyFilePrefix = 'my_player_';

  static bool _isLogName(String name) =>
      (name.startsWith(filePrefix) || name.startsWith(legacyFilePrefix)) && name.endsWith('.log');

  /// Ключ порядку: дата й час сесії та номер частини (назви з різними префіксами сортуються за часом, а не за буквами)
  static String _orderKey(String path) {
    final name = path.split(RegExp(r'[\\/]')).last;
    final m = RegExp(r'(\d{8}_\d{6})(?:_p(\d+))?').firstMatch(name);
    if (m == null) return name;
    return '${m.group(1)}-${(m.group(2) ?? '1').padLeft(3, '0')}';
  }

  // ── Зручні виклики ──────────────────────────────────────────────────────────

  static void d(String tag, String message) => instance.log(LogLevel.debug, tag, message);
  static void i(String tag, String message) => instance.log(LogLevel.info, tag, message);
  static void w(String tag, String message) => instance.log(LogLevel.warn, tag, message);

  /// Помилка; за наявності винятку додається він і початок стека
  static void e(String tag, String message, [Object? error, StackTrace? stack]) {
    final extra = error == null ? '' : ': $error';
    instance.log(LogLevel.error, tag, '$message$extra${_stackTail(stack)}');
  }

  /// Чи ввімкнено детальний режим (щоб не будувати дорогі рядки даремно)
  static bool get on => instance._detailed;

  static String _stackTail(StackTrace? stack, [int lines = 6]) {
    if (stack == null) return '';
    final rows = stack.toString().split('\n').where((l) => l.trim().isNotEmpty).take(lines);
    final text = rows.map((l) => '\n    $l').join();
    return text;
  }

  // ── Стан ────────────────────────────────────────────────────────────────────

  final Queue<LogEntry> _ring = Queue<LogEntry>();
  bool _detailed = false;
  Directory? _dir;
  File? _file;
  bool _sinkOn = false;
  String? _sinkError;
  int _fileBytes = 0;
  int _part = 1;
  String _sessionStamp = '';
  final StringBuffer _pending = StringBuffer();
  Timer? _flushTimer;
  Timer? _notifyTimer;
  Future<void> _writeChain = Future<void>.value();

  /// Скільки записів додано за сесію і скільки з них уже потрапило у файл
  int _added = 0;
  int _written = 0;

  String? _lastKey;
  LogLevel _lastLevel = LogLevel.info;
  String _lastTag = '';
  int _repeats = 0;
  bool _disposed = false;

  /// Рядки «про середовище» для шапки звіту (пристрій, ОС, екран…)
  final List<String> environment = [];

  bool get detailed => _detailed;

  /// Файл, у який зараз пишеться журнал (або `null`)
  File? get currentFile => _sinkOn ? _file : null;

  /// Теку журналів (або `null`, якщо журнал працює лише в памʼяті)
  Directory? get directory => _dir;

  /// Помилка запису у файл (якщо була)
  String? get sinkError => _sinkError;

  List<LogEntry> get entries => List<LogEntry>.unmodifiable(_ring);
  int get length => _ring.length;

  // ── Ініціалізація ───────────────────────────────────────────────────────────

  /// Задає теку журналів і режим. Виклик до `runApp`.
  Future<void> init({required Directory directory, required bool detailed}) async {
    _dir = directory;
    _detailed = detailed;
    _sessionStamp = _fileStamp(_now());
    if (detailed) await _startSink();
  }

  /// Вмикає / вимикає детальний режим (запис у файл і налагоджувальний рівень)
  Future<void> setDetailed(bool value) async {
    if (_detailed == value) return;
    if (value) {
      _detailed = true;
      await _startSink();
      log(LogLevel.info, 'журнал', 'Детальний журнал увімкнено');
    } else {
      log(LogLevel.info, 'журнал', 'Детальний журнал вимкнено');
      await flushNow();
      _sinkOn = false;
      _flushTimer?.cancel();
      _flushTimer = null;
      _detailed = false;
    }
    _scheduleNotify();
  }

  // ── Запис ───────────────────────────────────────────────────────────────────

  void log(LogLevel level, String tag, String message) {
    if (level == LogLevel.debug && !_detailed) return;
    try {
      var text = sanitize(message);
      if (text.length > maxLineChars) {
        text = '${text.substring(0, maxLineChars)}… (ще ${text.length - maxLineChars} симв.)';
      }
      final key = '${level.index}|$tag|$text';
      if (key == _lastKey) {
        _repeats++;
        return;
      }
      _closeRepeats();
      _lastKey = key;
      _lastLevel = level;
      _lastTag = tag;
      _emit(LogEntry(_now(), level, tag, text));
    } catch (_) {
      // журнал не має ламати застосунок
    }
  }

  void _closeRepeats() {
    if (_repeats <= 0) return;
    final n = _repeats;
    _repeats = 0;
    _emit(LogEntry(_now(), _lastLevel, _lastTag, '↑ рядок вище повторився ще $n р.'));
  }

  void _emit(LogEntry entry) {
    _ring.addLast(entry);
    _added++;
    final limit = _detailed ? _ringDetailed : _ringNormal;
    while (_ring.length > limit) {
      _ring.removeFirst();
    }
    if (_sinkOn) {
      _pending.writeln(_fileLine(entry));
      _written = _added;
      if (entry.level == LogLevel.error) {
        _scheduleFlush(immediately: true);
      } else {
        _scheduleFlush();
      }
    }
    _scheduleNotify();
  }

  static String _fileLine(LogEntry e) => e.format().replaceAll('\n', '\n    ');

  void _scheduleNotify() {
    if (_disposed || !hasListeners || _notifyTimer != null) return;
    _notifyTimer = Timer(const Duration(milliseconds: 300), () {
      _notifyTimer = null;
      if (!_disposed) notifyListeners();
    });
  }

  // ── Файл ────────────────────────────────────────────────────────────────────

  String _nameFor(int part) => '$filePrefix$_sessionStamp${part > 1 ? '_p$part' : ''}.log';

  static String _fileStamp(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}${two(t.month)}${two(t.day)}_${two(t.hour)}${two(t.minute)}${two(t.second)}';
  }

  Future<void> _startSink() async {
    final dir = _dir;
    if (dir == null || _sinkOn) return;
    try {
      await dir.create(recursive: true);
      if (_sessionStamp.isEmpty) _sessionStamp = _fileStamp(_now());
      _part = 1;
      var file = File('${dir.path}/${_nameFor(_part)}');
      var size = await file.exists() ? await file.length() : 0;
      // Сесія вже мала кілька частин (журнал вимикали й вмикали) — продовжуємо останню
      while (true) {
        final next = File('${dir.path}/${_nameFor(_part + 1)}');
        if (!await next.exists()) break;
        _part++;
        file = next;
        size = await file.length();
      }
      _file = file;
      _fileBytes = size;
      _sinkError = null;

      final buf = StringBuffer();
      if (size == 0) buf.writeln('# ${AppIdentity.name} — журнал, сесія $_sessionStamp');
      if (_fileBytes > 0) buf.writeln('# — запис відновлено —');
      // Те, що накопичилось у памʼяті, поки запису у файл не було
      final firstInRing = _added - _ring.length;
      final skip = (_written - firstInRing).clamp(0, _ring.length);
      for (final e in _ring.skip(skip)) {
        buf.writeln(_fileLine(e));
      }
      _written = _added;
      _pending
        ..clear()
        ..write(buf);
      _sinkOn = true;
      await _prune();
      _scheduleFlush(immediately: true);
    } catch (e) {
      _sinkError = '$e';
      _sinkOn = false;
      _file = null;
    }
  }

  void _scheduleFlush({bool immediately = false}) {
    if (!_sinkOn) return;
    if (immediately) {
      _flushTimer?.cancel();
      _flushTimer = null;
      unawaited(flushNow());
      return;
    }
    _flushTimer ??= Timer(flushDelay, () {
      _flushTimer = null;
      unawaited(flushNow());
    });
  }

  /// Записує накопичене у файл. Повертає, коли запис завершено.
  Future<void> flushNow() {
    _closeRepeats();
    _flushTimer?.cancel();
    _flushTimer = null;
    if (!_sinkOn || _pending.isEmpty) return _writeChain;
    final bytes = utf8.encode(_pending.toString());
    _pending.clear();
    _writeChain = _writeChain.then((_) async {
      try {
        if (_fileBytes > 0 && _fileBytes + bytes.length > maxFileBytes) await _rollOver();
        final file = _file;
        if (file == null) return;
        await file.writeAsBytes(bytes, mode: FileMode.append, flush: true);
        _fileBytes += bytes.length;
      } catch (e) {
        // Диск повний чи немає прав: далі працюємо лише в памʼяті
        _sinkError = '$e';
        _sinkOn = false;
        _file = null;
      }
    });
    return _writeChain;
  }

  Future<void> _rollOver() async {
    final dir = _dir;
    if (dir == null) return;
    _part++;
    _file = File('${dir.path}/${_nameFor(_part)}');
    _fileBytes = 0;
    await _file!.writeAsString('# ${AppIdentity.name} — журнал, сесія $_sessionStamp, частина $_part\n', flush: true);
    await _prune();
  }

  bool _isCurrent(File f) {
    final name = f.uri.pathSegments.last;
    return _sessionStamp.isNotEmpty && name.startsWith('$filePrefix$_sessionStamp');
  }

  /// Усі файли журналу, від найстарішого
  Future<List<File>> files() async {
    final dir = _dir;
    if (dir == null || !await dir.exists()) return const [];
    final out = <File>[];
    await for (final e in dir.list()) {
      if (e is! File) continue;
      final name = e.uri.pathSegments.last;
      if (_isLogName(name)) out.add(e);
    }
    out.sort((a, b) => _orderKey(a.path).compareTo(_orderKey(b.path)));
    return out;
  }

  Future<void> _prune() async {
    try {
      final all = await files();
      var total = 0;
      final sizes = <File, int>{};
      for (final f in all) {
        final s = await f.length();
        sizes[f] = s;
        total += s;
      }
      var count = all.length;
      for (final f in all) {
        if (count <= maxFiles && total <= maxTotalBytes) break;
        if (_isCurrent(f)) continue; // поточну сесію не чіпаємо
        try {
          await f.delete();
          total -= sizes[f] ?? 0;
          count--;
        } catch (_) {}
      }
    } catch (_) {}
  }

  /// Загальний розмір файлів журналу
  Future<int> totalBytes() async {
    var sum = 0;
    for (final f in await files()) {
      try {
        sum += await f.length();
      } catch (_) {}
    }
    return sum;
  }

  /// Видаляє файли журналу й очищає буфер
  Future<void> clear() async {
    _ring.clear();
    _pending.clear();
    _repeats = 0;
    _lastKey = null;
    _written = _added;
    for (final f in await files()) {
      try {
        await f.delete();
      } catch (_) {}
    }
    _fileBytes = 0;
    _scheduleNotify();
  }

  // ── Читання й звіт ──────────────────────────────────────────────────────────

  static Future<String> _readTail(List<File> files, int maxBytes) async {
    final parts = <Uint8List>[];
    var total = 0;
    // Читаємо з кінця, поки не набереться потрібний обсяг
    for (final f in files.reversed) {
      try {
        final b = await f.readAsBytes();
        parts.add(b);
        total += b.length;
      } catch (_) {}
      if (total >= maxBytes) break;
    }
    final builder = BytesBuilder(copy: false);
    for (final b in parts.reversed) {
      builder.add(b);
    }
    var all = builder.takeBytes();
    var cut = false;
    if (all.length > maxBytes) {
      all = Uint8List.sublistView(all, all.length - maxBytes);
      final nl = all.indexOf(10);
      if (nl >= 0 && nl < all.length - 1) all = Uint8List.sublistView(all, nl + 1);
      cut = true;
    }
    final text = utf8.decode(all, allowMalformed: true);
    return cut ? '… (початок обрізано, показано останні ${(maxBytes / 1024).round()} КБ)\n$text' : text;
  }

  /// Текст журналу поточної сесії (з файлу, а за його відсутності — з памʼяті)
  Future<String> sessionText({int maxBytes = 5 * 1024 * 1024}) async {
    await flushNow();
    final current = (await files()).where(_isCurrent).toList();
    final fromFile = current.isEmpty ? '' : await _readTail(current, maxBytes);
    // Записи, які не потрапили у файл (запис був вимкнений)
    final unwritten = _added - _written;
    if (unwritten <= 0 && fromFile.isNotEmpty) return fromFile;
    final firstInRing = _added - _ring.length;
    final skip = fromFile.isEmpty ? 0 : (_written - firstInRing).clamp(0, _ring.length);
    final rest = _ring.skip(skip).map((e) => e.format()).join('\n');
    return fromFile.isEmpty ? rest : '$fromFile\n$rest';
  }

  /// Хвіст журналу попереднього запуску (допомагає, якщо застосунок аварійно закрився)
  Future<String> previousSessionText({int maxBytes = 1536 * 1024}) async {
    final prev = (await files()).where((f) => !_isCurrent(f)).toList();
    if (prev.isEmpty) return '';
    // Береться останній файл-початок попередньої сесії разом з її частинами
    final name = prev.last.uri.pathSegments.last;
    final stamp = RegExp('^(?:$filePrefix|$legacyFilePrefix)(\\d{8}_\\d{6})').firstMatch(name)?.group(1);
    final parts = stamp == null ? [prev.last] : prev.where((f) => f.uri.pathSegments.last.contains(stamp)).toList();
    return _readTail(parts, maxBytes);
  }

  /// Повний звіт: шапка, додаткові розділи (від викликача), журнал сесії, хвіст попереднього запуску
  Future<String> buildReport({List<(String, String)> extra = const []}) async {
    final b = StringBuffer()
      ..writeln('══ ${AppIdentity.name.toUpperCase()} — ЖУРНАЛ ══')
      ..writeln('Створено: ${stamp(_now(), withDate: true)}')
      ..writeln('Детальний журнал: ${_detailed ? 'так' : 'ні'}');
    if (_sinkError != null) b.writeln('Помилка запису у файл: $_sinkError');
    for (final line in environment) {
      b.writeln(line);
    }
    for (final (title, body) in extra) {
      if (body.trim().isEmpty) continue;
      b
        ..writeln()
        ..writeln('══ $title ══')
        ..writeln(body.trimRight());
    }
    b
      ..writeln()
      ..writeln('══ ЖУРНАЛ СЕСІЇ ══')
      ..writeln(sanitize(await sessionText()));
    final prev = await previousSessionText();
    if (prev.trim().isNotEmpty) {
      b
        ..writeln()
        ..writeln('══ ПОПЕРЕДНІЙ ЗАПУСК (хвіст) ══')
        ..writeln(sanitize(prev));
    }
    return b.toString();
  }

  /// Зупиняє таймери (для тестів і завершення роботи)
  Future<void> shutdown() async {
    await flushNow();
    _flushTimer?.cancel();
    _notifyTimer?.cancel();
    _flushTimer = null;
    _notifyTimer = null;
    _sinkOn = false;
  }

  @override
  void dispose() {
    _disposed = true;
    _flushTimer?.cancel();
    _notifyTimer?.cancel();
    super.dispose();
  }

  // ── Допоміжне ───────────────────────────────────────────────────────────────

  static final RegExp _secret = RegExp(
    r'''\b((?:access_token|refresh_token|token|api[_-]?key|apikey|key|authorization|auth|password|passwd|pwd|secret|set-cookie|cookie|sessionid|signature)\s*[=:]\s*)(?:Bearer\s+)?[^\s&;,"']+''',
    caseSensitive: false,
  );
  static final RegExp _bearer = RegExp(r'Bearer\s+[A-Za-z0-9._~+/=-]+', caseSensitive: false);

  /// Маскує токени, ключі, паролі й cookie
  static String sanitize(String s) => s.replaceAllMapped(_secret, (m) => '${m[1]}***').replaceAll(_bearer, 'Bearer ***');

  /// `14:30:12.345` або `2026-11-03 14:30:12.345`
  static String stamp(DateTime t, {bool withDate = false}) {
    String two(int v) => v.toString().padLeft(2, '0');
    final ms = t.millisecond.toString().padLeft(3, '0');
    final time = '${two(t.hour)}:${two(t.minute)}:${two(t.second)}.$ms';
    return withDate ? '${t.year}-${two(t.month)}-${two(t.day)} $time' : time;
  }

  /// Розмір у людському вигляді
  static String bytesLabel(int bytes) {
    if (bytes < 1024) return '$bytes Б';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} КБ';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} МБ';
  }
}
