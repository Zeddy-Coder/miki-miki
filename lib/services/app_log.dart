/// The app's single log.
///
/// All subsystems write here (`AppLog.i / w / e / d`). An in-memory ring buffer always exists (info,
/// warnings, errors); in verbose mode the debug level is recorded too, and everything is
/// appended to the session file `<data dir>/logs/miki_miki_<date>_<time>.log` (rotation by size and count).
/// Secrets (tokens, keys, passwords, cookies) are masked before writing. The log never throws.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import '../constants/app_identity.dart';

/// Record level
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

  /// Line for the file and report: `2026-11-03 14:30:12.345 I [tag] text`
  String format() => '${AppLog.stamp(time, withDate: true)} ${level.letter} [$tag] $message';

  /// Short time for the screen
  String get clock => AppLog.stamp(time);

  @override
  String toString() => format();
}

class AppLog extends ChangeNotifier {
  /// Shared instance (replaced in tests)
  static AppLog instance = AppLog();

  AppLog({
    this.maxFileBytes = 6 * 1024 * 1024,
    this.maxFiles = 8,
    this.maxTotalBytes = 30 * 1024 * 1024,
    this.flushDelay = const Duration(milliseconds: 1200),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// Size of one file (the next part of the session starts after it)
  final int maxFileBytes;

  /// How many log files stay on disk (the oldest are deleted)
  final int maxFiles;

  /// Total size of all log files
  final int maxTotalBytes;

  /// How often the buffer is flushed to the file (errors immediately)
  final Duration flushDelay;

  final DateTime Function() _now;

  static const int maxLineChars = 4000;
  static const int _ringNormal = 1500;
  static const int _ringDetailed = 8000;
  static const String filePrefix = '${AppIdentity.packageName}_';

  /// Prefix of files under the app's previous name: such logs are also read and cleaned by rotation
  static const String legacyFilePrefix = 'my_player_';

  static bool _isLogName(String name) =>
      (name.startsWith(filePrefix) || name.startsWith(legacyFilePrefix)) && name.endsWith('.log');

  /// Order key: session date and time plus part number (names with different prefixes sort by time, not by letters)
  static String _orderKey(String path) {
    final name = path.split(RegExp(r'[\\/]')).last;
    final m = RegExp(r'(\d{8}_\d{6})(?:_p(\d+))?').firstMatch(name);
    if (m == null) return name;
    return '${m.group(1)}-${(m.group(2) ?? '1').padLeft(3, '0')}';
  }

  // ── Convenience calls ──────────────────────────────────────────────────────────

  static void d(String tag, String message) => instance.log(LogLevel.debug, tag, message);
  static void i(String tag, String message) => instance.log(LogLevel.info, tag, message);
  static void w(String tag, String message) => instance.log(LogLevel.warn, tag, message);

  /// Error; if an exception is present, it and the start of the stack are appended
  static void e(String tag, String message, [Object? error, StackTrace? stack]) {
    final extra = error == null ? '' : ': $error';
    instance.log(LogLevel.error, tag, '$message$extra${_stackTail(stack)}');
  }

  /// Whether verbose mode is on (to avoid building expensive strings needlessly)
  static bool get on => instance._detailed;

  static String _stackTail(StackTrace? stack, [int lines = 6]) {
    if (stack == null) return '';
    final rows = stack.toString().split('\n').where((l) => l.trim().isNotEmpty).take(lines);
    final text = rows.map((l) => '\n    $l').join();
    return text;
  }

  // ── State ────────────────────────────────────────────────────────────────────

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

  /// How many records were added during the session and how many of them have reached the file
  int _added = 0;
  int _written = 0;

  String? _lastKey;
  LogLevel _lastLevel = LogLevel.info;
  String _lastTag = '';
  int _repeats = 0;
  bool _disposed = false;

  /// "About the environment" lines for the report header (device, OS, screen…)
  final List<String> environment = [];

  bool get detailed => _detailed;

  /// The file the log is currently written to (or `null`)
  File? get currentFile => _sinkOn ? _file : null;

  /// The log folder (or `null` if the log works in memory only)
  Directory? get directory => _dir;

  /// File write error (if any)
  String? get sinkError => _sinkError;

  List<LogEntry> get entries => List<LogEntry>.unmodifiable(_ring);
  int get length => _ring.length;

  // ── Initialization ───────────────────────────────────────────────────────────

  /// Sets the log folder and mode. Call before `runApp`.
  Future<void> init({required Directory directory, required bool detailed}) async {
    _dir = directory;
    _detailed = detailed;
    _sessionStamp = _fileStamp(_now());
    if (detailed) await _startSink();
  }

  /// Turns verbose mode on / off (file writing and debug level)
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

  // ── Writing ───────────────────────────────────────────────────────────────────

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
      // the log must not break the app
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

  // ── File ────────────────────────────────────────────────────────────────────

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
      // The session already had several parts (the log was turned off and on): continue the last one
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
      // What accumulated in memory while there was no file writing
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

  /// Writes the accumulated data to the file. Returns when the write is done.
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
        // Disk full or no permissions: we keep working in memory only
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

  /// All log files, from the oldest
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
        if (_isCurrent(f)) continue; // the current session is left untouched
        try {
          await f.delete();
          total -= sizes[f] ?? 0;
          count--;
        } catch (_) {}
      }
    } catch (_) {}
  }

  /// Total size of the log files
  Future<int> totalBytes() async {
    var sum = 0;
    for (final f in await files()) {
      try {
        sum += await f.length();
      } catch (_) {}
    }
    return sum;
  }

  /// Deletes the log files and clears the buffer
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

  // ── Reading and report ──────────────────────────────────────────────────────

  static Future<String> _readTail(List<File> files, int maxBytes) async {
    final parts = <Uint8List>[];
    var total = 0;
    // Read from the end until the needed amount is collected
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

  /// Text of the current session's log (from the file, or from memory if there is none)
  Future<String> sessionText({int maxBytes = 5 * 1024 * 1024}) async {
    await flushNow();
    final current = (await files()).where(_isCurrent).toList();
    final fromFile = current.isEmpty ? '' : await _readTail(current, maxBytes);
    // Records that did not reach the file (writing was off)
    final unwritten = _added - _written;
    if (unwritten <= 0 && fromFile.isNotEmpty) return fromFile;
    final firstInRing = _added - _ring.length;
    final skip = fromFile.isEmpty ? 0 : (_written - firstInRing).clamp(0, _ring.length);
    final rest = _ring.skip(skip).map((e) => e.format()).join('\n');
    return fromFile.isEmpty ? rest : '$fromFile\n$rest';
  }

  /// Tail of the previous launch's log (helps if the app crashed)
  Future<String> previousSessionText({int maxBytes = 1536 * 1024}) async {
    final prev = (await files()).where((f) => !_isCurrent(f)).toList();
    if (prev.isEmpty) return '';
    // Takes the last starting file of the previous session together with its parts
    final name = prev.last.uri.pathSegments.last;
    final stamp = RegExp('^(?:$filePrefix|$legacyFilePrefix)(\\d{8}_\\d{6})').firstMatch(name)?.group(1);
    final parts = stamp == null ? [prev.last] : prev.where((f) => f.uri.pathSegments.last.contains(stamp)).toList();
    return _readTail(parts, maxBytes);
  }

  /// Full report: header, extra sections (from the caller), session log, tail of the previous launch
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

  /// Stops the timers (for tests and shutdown)
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

  // ── Helpers ───────────────────────────────────────────────────────────────

  static final RegExp _secret = RegExp(
    r'''\b((?:access_token|refresh_token|token|api[_-]?key|apikey|key|authorization|auth|password|passwd|pwd|secret|set-cookie|cookie|sessionid|signature)\s*[=:]\s*)(?:Bearer\s+)?[^\s&;,"']+''',
    caseSensitive: false,
  );
  static final RegExp _bearer = RegExp(r'Bearer\s+[A-Za-z0-9._~+/=-]+', caseSensitive: false);

  /// Masks tokens, keys, passwords and cookies
  static String sanitize(String s) => s.replaceAllMapped(_secret, (m) => '${m[1]}***').replaceAll(_bearer, 'Bearer ***');

  /// `14:30:12.345` or `2026-11-03 14:30:12.345`
  static String stamp(DateTime t, {bool withDate = false}) {
    String two(int v) => v.toString().padLeft(2, '0');
    final ms = t.millisecond.toString().padLeft(3, '0');
    final time = '${two(t.hour)}:${two(t.minute)}:${two(t.second)}.$ms';
    return withDate ? '${t.year}-${two(t.month)}-${two(t.day)} $time' : time;
  }

  /// Human-readable size
  static String bytesLabel(int bytes) {
    if (bytes < 1024) return '$bytes Б';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} КБ';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} МБ';
  }
}
