// Synthetic sound for listening tests (8 kHz): "music" (notes of two voices with harmonics) and "speech" (voiced bursts with
// pauses), put together into an episode's first minutes with its own faint noise and gain (another encode)
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:miki_miki/services/skips/audio_print.dart';

/// Notes of two voices with harmonics and a soft strike at each start: like music, every band has some of it
Float64List music(int seed, double seconds) {
  final rng = math.Random(seed);
  final n = (seconds * printRate).round();
  final out = Float64List(n);
  var pos = 0;
  while (pos < n) {
    final len = math.min(((rng.nextDouble() * 0.25 + 0.15) * printRate).round(), n - pos);
    final voices = [for (var i = 0; i < 2; i++) (150 + rng.nextDouble() * 450, 0.3 + rng.nextDouble() * 0.5)];
    final strike = [for (var i = 0; i < 240; i++) rng.nextDouble() - 0.5];
    for (var i = 0; i < len; i++) {
      final t = i / printRate;
      final env = math.min(1.0, math.min(t / 0.02, (len - i) / printRate / 0.05));
      var v = 0.0;
      for (final (f, a) in voices) {
        for (var k = 1; k <= 8 && f * k < 3800; k++) {
          v += math.sin(2 * math.pi * f * k * t) * a / k;
        }
      }
      if (i < strike.length) v += strike[i] * (1 - i / strike.length) * 0.8;
      out[pos + i] = v * env / 4;
    }
    pos += len;
  }
  return out;
}

Float64List speech(int seed, double seconds) {
  final rng = math.Random(seed);
  final n = (seconds * printRate).round();
  final out = Float64List(n);
  var pos = 0;
  while (pos < n) {
    final len = math.min(((rng.nextDouble() * 0.9 + 0.3) * printRate).round(), n - pos);
    if (rng.nextDouble() < 0.7) {
      final f0 = 110 + rng.nextDouble() * 150;
      final mod = 3 + rng.nextDouble() * 4;
      for (var i = 0; i < len; i++) {
        final t = i / printRate;
        var v = 0.0;
        for (var k = 1; k < 8; k++) {
          v += math.sin(2 * math.pi * f0 * k * t) / k;
        }
        out[pos + i] = v * 0.15 * (1 + 0.5 * math.sin(2 * math.pi * mod * t));
      }
    }
    pos += len;
  }
  return out;
}

/// An episode's first minutes from [parts], with its own faint noise and gain (another encode of the same sound)
Int16List pcmEpisode(List<Float64List> parts, {required int noise, double gain = 1}) {
  final total = parts.fold<int>(0, (a, p) => a + p.length);
  final out = Int16List(total);
  final rng = math.Random(noise);
  var o = 0;
  for (final p in parts) {
    for (final v in p) {
      final x = (v * gain + (rng.nextDouble() - 0.5) * 0.01) * 20000;
      out[o++] = x.round().clamp(-32768, 32767);
    }
  }
  return out;
}
