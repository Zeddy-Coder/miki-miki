/// Why the app's earlier runs ended, as Android remembers it (`ApplicationExitInfo`, Android 11+): a crash in Dart
/// leaves its error in the log, but a crash in native code (libmpv, the decoder, the engine), a freeze or the system
/// killing the app for memory leaves nothing — the log just stops. At start each such end not reported yet is written
/// to the log once (tag «аварія»): the reason, and for a native crash the signal, the abort message, the crashed thread
/// and its first frames read from the tombstone; for a freeze, the main thread's stack.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'app_log.dart';
import 'storage_service.dart';
import 'system_controls.dart';

/// One earlier end of the app's process
class ExitRecord {
  final DateTime time;

  /// `ApplicationExitInfo.REASON_*`
  final int reason;

  /// The signal (a native crash, «signaled») or the exit code
  final int status;
  final String? description;

  /// `RunningAppProcessInfo.IMPORTANCE_*` at the end: 100 on the screen … 400 cached in the background
  final int importance;
  final int pssKb;
  final int rssKb;
  final Uint8List? trace;

  const ExitRecord({
    required this.time,
    required this.reason,
    this.status = 0,
    this.description,
    this.importance = 1000,
    this.pssKb = 0,
    this.rssKb = 0,
    this.trace,
  });

  static ExitRecord? fromMap(Map<String, Object?> m) {
    final t = m['time'];
    final r = m['reason'];
    if (t is! num || r is! num) return null;
    final trace = m['trace'];
    return ExitRecord(
      time: DateTime.fromMillisecondsSinceEpoch(t.toInt()),
      reason: r.toInt(),
      status: (m['status'] as num?)?.toInt() ?? 0,
      description: (m['description'] as String?)?.trim().isEmpty ?? true ? null : (m['description'] as String).trim(),
      importance: (m['importance'] as num?)?.toInt() ?? 1000,
      pssKb: (m['pssKb'] as num?)?.toInt() ?? 0,
      rssKb: (m['rssKb'] as num?)?.toInt() ?? 0,
      trace: trace is Uint8List ? trace : (trace is List ? Uint8List.fromList(trace.cast<int>()) : null),
    );
  }

  static const int exitSelf = 1, signaled = 2, lowMemory = 3, crash = 4, crashNative = 5, anr = 6, initFailure = 7;
  static const int excessiveResources = 9, dependencyDied = 12, other = 13, freezer = 14;

  /// The person could see it (on the screen, or playing in the background), not a cached process cleared away
  bool get seen => importance <= 230;

  /// Worth reporting: it went down by itself or by the system's hand — not closed, stopped or updated by the person.
  /// A process killed while cached in the background is how Android frees memory, not a failure
  bool get abnormal => switch (reason) {
        crash || crashNative || anr || initFailure || excessiveResources || dependencyDied => true,
        signaled || lowMemory || other || freezer => seen,
        _ => false,
      };
}

/// What a native crash's tombstone says: the signal, the abort message, the crashed thread and its first frames
class NativeCrash {
  final String? signal;
  final String? code;
  final int? faultAddress;
  final String? abort;
  final String? thread;
  final List<String> frames;

  const NativeCrash({this.signal, this.code, this.faultAddress, this.abort, this.thread, this.frames = const []});
}

class ExitReports {
  ExitReports._();

  /// How many frames of the crashed thread go to the log
  static const int frameCount = 8;

  /// The tombstone of a native crash: protobuf (Android 12+, `tombstone.proto`) or, on Android 11, text
  static NativeCrash? parseTombstone(Uint8List bytes) {
    if (bytes.isEmpty) return null;
    if (_looksText(bytes)) return _textTombstone(utf8.decode(bytes, allowMalformed: true));
    try {
      return _protoTombstone(bytes);
    } on FormatException {
      return null;
    } on RangeError {
      return null;
    }
  }

  static bool _looksText(Uint8List b) {
    final n = b.length < 256 ? b.length : 256;
    var printable = 0;
    for (var i = 0; i < n; i++) {
      final c = b[i];
      if (c == 9 || c == 10 || c == 13 || (c >= 32 && c < 127)) printable++;
    }
    return printable >= n * 0.95;
  }

  static NativeCrash _protoTombstone(Uint8List bytes) {
    final p = _Proto(bytes);
    int? tid;
    String? signal, code, abort;
    int? fault;
    final threads = <int, (String?, List<String>)>{};
    while (p.more) {
      final (field, wire) = p.tag();
      if (field == 6 && wire == 0) {
        tid = p.varint();
      } else if (field == 10 && wire == 2) {
        final s = _Proto(bytes, p.lengthDelimited());
        while (s.more) {
          final (f, w) = s.tag();
          if (f == 2 && w == 2) {
            signal = s.string();
          } else if (f == 4 && w == 2) {
            code = s.string();
          } else if (f == 9 && w == 0) {
            fault = s.varint();
          } else {
            s.skip(w);
          }
        }
      } else if (field == 14 && wire == 2) {
        abort = p.string();
      } else if (field == 16 && wire == 2) {
        // map<uint32, Thread>: an entry is {1: key, 2: Thread}
        final e = _Proto(bytes, p.lengthDelimited());
        int? key;
        (String?, List<String>)? thread;
        while (e.more) {
          final (f, w) = e.tag();
          if (f == 1 && w == 0) {
            key = e.varint();
          } else if (f == 2 && w == 2) {
            thread = _thread(bytes, e.lengthDelimited());
          } else {
            e.skip(w);
          }
        }
        if (key != null && thread != null) threads[key] = thread;
      } else {
        p.skip(wire);
      }
    }
    final crashed = threads[tid] ?? (threads.isEmpty ? null : threads.values.first);
    return NativeCrash(signal: signal, code: code, faultAddress: fault, abort: abort, thread: crashed?.$1, frames: crashed?.$2 ?? const []);
  }

  /// A thread: its name and the first frames of its backtrace («libmpv.so (vo_flip+24)»)
  static (String?, List<String>) _thread(Uint8List bytes, (int, int) range) {
    final t = _Proto(bytes, range);
    String? name;
    final frames = <String>[];
    while (t.more) {
      final (f, w) = t.tag();
      if (f == 2 && w == 2) {
        name = t.string();
      } else if (f == 4 && w == 2 && frames.length < frameCount) {
        final fr = _Proto(bytes, t.lengthDelimited());
        var relPc = 0, offset = 0;
        String? function, file;
        while (fr.more) {
          final (ff, ww) = fr.tag();
          if (ff == 1 && ww == 0) {
            relPc = fr.varint();
          } else if (ff == 4 && ww == 2) {
            function = fr.string();
          } else if (ff == 5 && ww == 0) {
            offset = fr.varint();
          } else if (ff == 6 && ww == 2) {
            file = fr.string();
          } else {
            fr.skip(ww);
          }
        }
        frames.add(_frame(file, function, offset, relPc));
      } else {
        t.skip(w);
      }
    }
    return (name, frames);
  }

  static String _frame(String? file, String? function, int offset, int relPc) {
    final lib = file == null || file.isEmpty ? '?' : file.split('/').last;
    if (function != null && function.isNotEmpty) return '$lib ($function+$offset)';
    return '$lib +0x${relPc.toRadixString(16)}';
  }

  /// Android 11's text tombstone: the «signal» line, the abort message, the thread's name and the «#00 pc …» lines
  static NativeCrash _textTombstone(String text) {
    String? signal, code, abort, thread;
    int? fault;
    final frames = <String>[];
    final sig = RegExp(r'^signal \d+ \((\w+)\), code -?\d+ \((\w+)\)(?:, fault addr (0x[0-9a-f]+|--------))?', multiLine: true).firstMatch(text);
    if (sig != null) {
      signal = sig.group(1);
      code = sig.group(2);
      final f = sig.group(3);
      if (f != null && f.startsWith('0x')) fault = int.tryParse(f.substring(2), radix: 16);
    }
    abort = RegExp(r"^Abort message: '(.*)'$", multiLine: true).firstMatch(text)?.group(1);
    thread = RegExp(r'^pid: \d+, tid: \d+, name: (.+?)\s+>>>', multiLine: true).firstMatch(text)?.group(1);
    final frame = RegExp(r'^\s*#\d+ pc ([0-9a-f]+)\s+(\S+)(?: \((.+?)\))?', multiLine: true);
    for (final m in frame.allMatches(text)) {
      if (frames.length >= frameCount) break;
      final pc = int.tryParse(m.group(1)!, radix: 16) ?? 0;
      final fn = m.group(3);
      frames.add(fn == null ? _frame(m.group(2), null, 0, pc) : '${m.group(2)!.split('/').last} ($fn)');
    }
    return NativeCrash(signal: signal, code: code, faultAddress: fault, abort: abort, thread: thread, frames: frames);
  }

  /// The main thread's stack from an ANR trace (text): «at …» lines of the `"main"` thread
  static List<String> anrMain(Uint8List bytes, {int lines = 8}) {
    final text = utf8.decode(bytes, allowMalformed: true);
    final start = text.indexOf('"main"');
    if (start < 0) return const [];
    final out = <String>[];
    for (final l in const LineSplitter().convert(text.substring(start)).skip(1)) {
      if (l.trim().isEmpty) break;
      final t = l.trim();
      if (t.startsWith('at ') || t.startsWith('native:')) out.add(t);
      if (out.length >= lines) break;
    }
    return out;
  }

  /// The log line about one end
  static String describe(ExitRecord r) {
    final hh = '${r.time.hour.toString().padLeft(2, '0')}:${r.time.minute.toString().padLeft(2, '0')}:${r.time.second.toString().padLeft(2, '0')}';
    final day = '${r.time.day.toString().padLeft(2, '0')}.${r.time.month.toString().padLeft(2, '0')}';
    final where = r.seen ? (r.importance <= 100 ? 'на екрані' : 'видимий') : 'у фоні';
    final mem = r.pssKb > 0 ? '; памʼять ${(r.pssKb / 1024).round()} МБ' : '';
    final note = r.description == null ? '' : '; система: «${r.description}»';
    final parts = <String>['Запуск $day о $hh ($where) завершився: ${_reason(r)}'];
    if (r.reason == ExitRecord.crashNative && r.trace != null) {
      final c = parseTombstone(r.trace!);
      if (c != null) {
        if (c.signal != null) {
          parts.add([
            c.signal!,
            if (c.code != null) '(${c.code})',
            if (c.faultAddress != null) 'адреса 0x${c.faultAddress!.toRadixString(16)}',
          ].join(' '));
        }
        if (c.thread != null) parts.add('потік «${c.thread}»');
        if (c.abort != null) parts.add('повідомлення: «${c.abort}»');
        if (c.frames.isNotEmpty) parts.add('стек: ${c.frames.join(' ← ')}');
      }
    }
    if (r.reason == ExitRecord.anr && r.trace != null) {
      final main = anrMain(r.trace!);
      if (main.isNotEmpty) parts.add('головний потік: ${main.join(' ← ')}');
    }
    return '${parts.join('; ')}$note$mem';
  }

  static String _reason(ExitRecord r) => switch (r.reason) {
        ExitRecord.crash => 'аварія в коді Java/Kotlin',
        ExitRecord.crashNative => 'аварія в нативному коді (сигнал ${r.status})',
        ExitRecord.anr => 'застосунок не відповідав (ANR)',
        ExitRecord.lowMemory => 'системі забракло памʼяті',
        ExitRecord.signaled => 'систему зупинила процес сигналом ${r.status}',
        ExitRecord.initFailure => 'не вдалося запуститися',
        ExitRecord.excessiveResources => 'забагато ресурсів (процесор чи памʼять)',
        ExitRecord.dependencyDied => 'зупинився процес, від якого він залежав',
        ExitRecord.freezer => 'система заморозила й зупинила процес',
        _ => 'причина ${r.reason}',
      };

  /// At start: the ends after the last one reported, the abnormal ones to the log (oldest first); [exits] — for tests
  static Future<int> logRecent({Future<List<Map<String, Object?>>> Function(int since)? exits}) async {
    final section = StorageService.getSection('diagnostics');
    final since = (section['exits_seen'] as num?)?.toInt() ?? 0;
    final raw = await (exits ?? SystemControls.exits)(since);
    final records = [for (final m in raw) if (ExitRecord.fromMap(m) case final r?) r]..sort((a, b) => a.time.compareTo(b.time));
    if (records.isEmpty) return 0;
    var logged = 0;
    for (final r in records) {
      if (!r.abnormal) continue;
      AppLog.w('аварія', describe(r));
      logged++;
    }
    StorageService.saveSection('diagnostics', {...section, 'exits_seen': records.last.time.millisecondsSinceEpoch});
    return logged;
  }
}

/// A minimal protobuf reader (wire format): varints, length-delimited fields; the rest is skipped
class _Proto {
  final Uint8List b;
  int i;
  final int end;

  _Proto(this.b, [(int, int)? range])
      : i = range?.$1 ?? 0,
        end = range?.$2 ?? b.length;

  bool get more => i < end;

  int varint() {
    var r = 0, s = 0;
    while (true) {
      if (i >= end) throw const FormatException('protobuf: varint');
      final x = b[i++];
      r |= (x & 0x7f) << s;
      if (x < 0x80) return r;
      s += 7;
      if (s > 63) throw const FormatException('protobuf: varint');
    }
  }

  (int, int) tag() {
    final t = varint();
    return (t >> 3, t & 7);
  }

  /// The range of a length-delimited field
  (int, int) lengthDelimited() {
    final n = varint();
    if (n < 0 || i + n > end) throw const FormatException('protobuf: length');
    final r = (i, i + n);
    i += n;
    return r;
  }

  String string() {
    final (a, z) = lengthDelimited();
    return utf8.decode(Uint8List.sublistView(b, a, z), allowMalformed: true);
  }

  void skip(int wire) {
    switch (wire) {
      case 0:
        varint();
      case 1:
        i += 8;
      case 2:
        lengthDelimited();
      case 5:
        i += 4;
      default:
        throw const FormatException('protobuf: wire type');
    }
    if (i > end) throw const FormatException('protobuf: past the end');
  }
}
