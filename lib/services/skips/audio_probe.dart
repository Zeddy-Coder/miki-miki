/// An episode's sound as samples, for listening for the opening. A hidden player of its own (its own mpv: no picture,
/// no speakers) writes the soundtrack into a raw PCM file — 8 kHz, mono, 16 bit — as fast as it decodes, and the file
/// is read back. Android's player has no sound-analysis filters, but it has this writer (`ao=pcm`). The picture is not
/// decoded (`vid=no`) and an HLS stream gives its lowest quality (`hls-bitrate=min`), so a few minutes cost a few
/// megabytes.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:media_kit/media_kit.dart';

import '../app_log.dart';
import 'audio_print.dart';

/// Decodes [length] seconds from [start] of [url] into [printRate] Hz mono samples; null when it failed
typedef PcmDecoder = Future<Int16List?> Function(String url, {Map<String, String> headers, double start, double length});

class AudioProbe {
  AudioProbe._();

  /// One at a time: two hidden players would only race each other for the network
  static Future<void> _queue = Future<void>.value();

  static Future<Int16List?> decode(String url, {Map<String, String> headers = const {}, double start = 0, double length = 240}) {
    final run = _queue.then((_) => _decode(url, headers: headers, start: start, length: length));
    _queue = run.then((_) {}, onError: (_) {});
    return run;
  }

  static Future<Int16List?> _decode(String url, {required Map<String, String> headers, required double start, required double length}) async {
    final file = File('${Directory.systemTemp.path}${Platform.pathSeparator}miki_listen_${DateTime.now().microsecondsSinceEpoch}.pcm');
    final watch = Stopwatch()..start();
    Player? player;
    try {
      player = Player(configuration: const PlayerConfiguration(title: 'listen', logLevel: MPVLogLevel.error, bufferSize: 8 * 1024 * 1024));
      final dynamic p = player.platform;
      for (final (k, v) in const [
        ('vid', 'no'),
        ('sid', 'no'),
        ('ao', 'pcm'),
        ('ao-pcm-waveheader', 'no'),
        ('audio-samplerate', '$printRate'),
        ('audio-channels', 'mono'),
        ('audio-format', 's16'),
        ('untimed', 'yes'),
        ('hls-bitrate', 'min'),
        ('volume', '100'),
        ('mute', 'no'),
        ('ytdl', 'no'),
      ]) {
        await p.setProperty(k, v);
      }
      await p.setProperty('ao-pcm-file', file.path);
      final done = player.stream.completed.firstWhere((c) => c).timeout(const Duration(seconds: 150));
      await player.open(
        Media(url, httpHeaders: headers.isEmpty ? null : headers, start: Duration(milliseconds: (start * 1000).round()), end: Duration(milliseconds: ((start + length) * 1000).round())),
      );
      await done;
    } catch (e) {
      AppLog.w('пропуск', 'звук не розібрано: $e');
    } finally {
      try {
        await player?.dispose();
      } catch (_) {}
    }
    try {
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      await file.delete();
      if (bytes.length < printRate * 2 * 5) return null;
      AppLog.i('пропуск', 'звук для аналізу: ${(bytes.length / (printRate * 2)).toStringAsFixed(0)} с за ${watch.elapsedMilliseconds} мс');
      return Int16List.view(bytes.buffer, bytes.offsetInBytes, bytes.length ~/ 2);
    } catch (e) {
      AppLog.w('пропуск', 'файл звуку не прочитано: $e');
      return null;
    }
  }
}
