import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:miki_miki/services/app_log.dart';
import 'package:miki_miki/services/exit_reports.dart';
import 'package:miki_miki/services/storage_service.dart';

/// A tiny protobuf writer for the tombstone fixtures
class Pb {
  final BytesBuilder _b = BytesBuilder();

  void _varint(int v) {
    var x = v;
    while (x >= 0x80) {
      _b.addByte((x & 0x7f) | 0x80);
      x >>= 7;
    }
    _b.addByte(x);
  }

  Pb int_(int field, int v) {
    _varint(field << 3);
    _varint(v);
    return this;
  }

  Pb bytes(int field, List<int> v) {
    _varint(field << 3 | 2);
    _varint(v.length);
    _b.add(v);
    return this;
  }

  Pb str(int field, String v) => bytes(field, utf8.encode(v));
  Pb msg(int field, Pb m) => bytes(field, m.done());
  Pb fixed64(int field) {
    _varint(field << 3 | 1);
    _b.add(List.filled(8, 7));
    return this;
  }

  Uint8List done() => _b.toBytes();
}

Pb frame({int relPc = 0, String? fn, int offset = 0, required String file}) {
  final f = Pb().int_(1, relPc).int_(2, relPc + 0x7000000000).int_(3, 0x7ff0000000);
  if (fn != null) f.str(4, fn).int_(5, offset);
  return f.str(6, file).str(8, 'a1b2c3');
}

/// A tombstone as Android 12+ writes it: the crashed thread 4242 «mpv/vo», another thread, and fields the reader skips
Uint8List tombstone({String? abort}) {
  final main = Pb().int_(1, 4241).str(2, 'mikimiki.app').msg(4, frame(relPc: 0x10, fn: 'epoll_wait', offset: 8, file: '/apex/com.android.runtime/lib64/bionic/libc.so'));
  final vo = Pb()
      .int_(1, 4242)
      .str(2, 'mpv/vo')
      .msg(3, Pb().str(1, 'x0').int_(2, 0))
      .msg(4, frame(relPc: 0x1234, fn: 'vo_flip_frame', offset: 24, file: '/data/app/~~abc/com.mikimiki.app-1/lib/arm64/libmpv.so'))
      .msg(4, frame(relPc: 0x99, file: '/data/app/~~abc/com.mikimiki.app-1/lib/arm64/libmpv.so'))
      .msg(4, frame(relPc: 0x20, fn: '__pthread_start(void*)', offset: 196, file: '/apex/com.android.runtime/lib64/bionic/libc.so'));
  final t = Pb()
      .int_(1, 3)
      .str(2, 'google/husky/husky:17/DP11/1:user/release-keys')
      .int_(5, 4241)
      .int_(6, 4242)
      .msg(10, Pb().int_(1, 11).str(2, 'SIGSEGV').int_(3, 1).str(4, 'SEGV_MAPERR').int_(8, 1).int_(9, 0x10))
      .msg(16, Pb().int_(1, 4241).msg(2, main))
      .msg(16, Pb().int_(1, 4242).msg(2, vo))
      .msg(17, Pb().str(1, '/system/lib64/libc.so'))
      .fixed64(30);
  if (abort != null) t.str(14, abort);
  return t.done();
}

const textTombstone = '''*** *** *** *** *** *** *** *** *** *** *** *** *** *** *** ***
Build fingerprint: 'google/redfin/redfin:11/RQ3A/1:user/release-keys'
pid: 9001, tid: 9020, name: mpv/demux  >>> com.mikimiki.app <<<
signal 6 (SIGABRT), code -1 (SI_QUEUE), fault addr --------
Abort message: 'av_assert0 failed at libavcodec/hevc_refs.c:59'
backtrace:
      #00 pc 000000000004e8a4  /apex/com.android.runtime/lib64/bionic/libc.so (abort+164)
      #01 pc 0000000000123456  /data/app/com.mikimiki.app/lib/arm64/libavcodec.so
''';

const anrTrace = '''----- pid 9001 at 2026-11-21 12:23:27 -----
Cmd line: com.mikimiki.app

"Signal Catcher" daemon prio=10 tid=4 Runnable
  at java.lang.Object.wait(Native method)

"main" prio=5 tid=1 Blocked
  | group="main" sCount=1
  at android.media.MediaCodec.native_release(Native method)
  at android.media.MediaCodec.release(MediaCodec.java:2006)
  - waiting to lock <0x0f> held by thread 20
  at com.mikimiki.app.MainActivity.onPause(MainActivity.kt:120)

"RenderThread" prio=7 tid=20 Native
''';

void main() {
  group('аварії: що Android памʼятає про завершення', () {
    test('надгробок protobuf: сигнал, адреса, потік, що впав, і його перші кадри', () {
      final c = ExitReports.parseTombstone(tombstone(abort: 'FORTIFY: pthread_mutex_lock called on a destroyed mutex'))!;
      expect(c.signal, 'SIGSEGV');
      expect(c.code, 'SEGV_MAPERR');
      expect(c.faultAddress, 0x10);
      expect(c.thread, 'mpv/vo');
      expect(c.abort, 'FORTIFY: pthread_mutex_lock called on a destroyed mutex');
      expect(c.frames, ['libmpv.so (vo_flip_frame+24)', 'libmpv.so +0x99', 'libc.so (__pthread_start(void*)+196)']);
    });

    test('надгробок текстом (Android 11): сигнал, повідомлення, потік, кадри', () {
      final c = ExitReports.parseTombstone(Uint8List.fromList(utf8.encode(textTombstone)))!;
      expect(c.signal, 'SIGABRT');
      expect(c.code, 'SI_QUEUE');
      expect(c.faultAddress, isNull);
      expect(c.thread, 'mpv/demux');
      expect(c.abort, 'av_assert0 failed at libavcodec/hevc_refs.c:59');
      expect(c.frames, ['libc.so (abort+164)', 'libavcodec.so +0x123456']);
    });

    test('зламані байти — без падіння', () {
      expect(ExitReports.parseTombstone(Uint8List.fromList([0x0a, 0xff, 0xff, 0xff])), isNull);
      expect(ExitReports.parseTombstone(Uint8List(0)), isNull);
    });

    test('ANR: стек головного потоку', () {
      expect(ExitReports.anrMain(Uint8List.fromList(utf8.encode(anrTrace))), [
        'at android.media.MediaCodec.native_release(Native method)',
        'at android.media.MediaCodec.release(MediaCodec.java:2006)',
        'at com.mikimiki.app.MainActivity.onPause(MainActivity.kt:120)',
      ]);
    });

    test('рядок журналу: нативна аварія на екрані з потоком і стеком', () {
      final r = ExitRecord(
        time: DateTime(2026, 11, 21, 12, 23, 27),
        reason: ExitRecord.crashNative,
        status: 11,
        importance: 100,
        pssKb: 812 * 1024,
        trace: tombstone(),
      );
      expect(r.abnormal, isTrue);
      expect(
        ExitReports.describe(r),
        'Запуск 21.11 о 12:23:27 (на екрані) завершився: аварія в нативному коді (сигнал 11); SIGSEGV (SEGV_MAPERR) адреса 0x10; '
        'потік «mpv/vo»; стек: libmpv.so (vo_flip_frame+24) ← libmpv.so +0x99 ← libc.so (__pthread_start(void*)+196); памʼять 812 МБ',
      );
    });

    test('що вважається збоєм: процес, зупинений у фоні, — ні; закритий людиною — ні; забракло памʼяті на екрані — так', () {
      ExitRecord r(int reason, int importance) => ExitRecord(time: DateTime(2026), reason: reason, importance: importance);
      expect(r(ExitRecord.signaled, 400).abnormal, isFalse, reason: 'Android звільняє памʼять від фонових');
      expect(r(ExitRecord.signaled, 100).abnormal, isTrue);
      expect(r(ExitRecord.lowMemory, 125).abnormal, isTrue, reason: 'грав у фоні — людина помітила');
      expect(r(10, 100).abnormal, isFalse, reason: 'закрила людина');
      expect(r(16, 100).abnormal, isFalse, reason: 'оновлення');
      expect(r(ExitRecord.anr, 400).abnormal, isTrue);
      expect(r(ExitRecord.crash, 400).abnormal, isTrue);
    });

    test('при старті: збої після останнього звіту — у журнал по разу, від старішого; звичайні виходи — ні', () async {
      AppLog.instance = AppLog();
      StorageService.saveSection('diagnostics', {});
      final asked = <int>[];
      Future<List<Map<String, Object?>>> exits(int since) async {
        asked.add(since);
        final all = [
          {'time': 3000, 'reason': ExitRecord.crashNative, 'status': 11, 'importance': 100, 'pssKb': 0, 'trace': tombstone()},
          {'time': 2000, 'reason': 10, 'status': 0, 'importance': 100},
          {'time': 1000, 'reason': ExitRecord.anr, 'status': 0, 'importance': 100, 'description': 'Input dispatching timed out'},
        ];
        return [for (final e in all) if ((e['time'] as int) > since) e];
      }

      expect(await ExitReports.logRecent(exits: exits), 2);
      final lines = [for (final e in AppLog.instance.entries) if (e.tag == 'аварія') e.message];
      expect(lines, hasLength(2));
      expect(lines[0], contains('застосунок не відповідав (ANR)'));
      expect(lines[0], contains('система: «Input dispatching timed out»'));
      expect(lines[1], contains('потік «mpv/vo»'));

      expect(await ExitReports.logRecent(exits: exits), 0, reason: 'уже записані — вдруге ні');
      expect(asked, [0, 3000]);
    });
  });
}
