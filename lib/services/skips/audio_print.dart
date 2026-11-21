/// Listening for the opening: an audio fingerprint of an episode's first minutes and the stretches two episodes share.
/// Pure Dart (runs in an isolate).
///
/// The fingerprint is the classic robust audio hash (Haitsma & Kalker): 33 bands between 300 and 2000 Hz, and for each
/// 16 ms step 32 bits — whether the energy difference of neighbouring bands grew or fell since the previous step. It
/// survives re-encoding and volume, so the same opening song in two episodes of one dub gives mostly the same bits,
/// while different sound differs in half of them. The steps are short (frames overlap by 7/8) because the song lies at
/// any place in each episode: frames cut at different places of it differ (a half-step apart — a third of the bits).
/// What two episodes share: the opening (the longest common stretch) and the dub's own intro or a distributor's logo
/// (common from the very start).
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// The sample rate the decoder is asked for
const int printRate = 8000;
const int _frame = 2048;
const int _hop = 128;
const int _bands = 33;

/// Steps back each word compares with (64 ms)
const int _lag = 4;

/// Seconds per fingerprint step
const double printStep = _hop / printRate;

class AudioPrint {
  /// One 32-bit word per step
  final Uint32List words;

  /// Where the fingerprinted sound starts on the video's timeline (seconds)
  final double offset;

  const AudioPrint(this.words, {this.offset = 0});

  double get seconds => words.length * printStep;

  Uint8List toBytes() {
    final b = ByteData(8 + words.length * 4)
      ..setUint32(0, 0x4D4B4150) // "MKAP"
      ..setFloat32(4, offset);
    for (var i = 0; i < words.length; i++) {
      b.setUint32(8 + i * 4, words[i]);
    }
    return b.buffer.asUint8List();
  }

  static AudioPrint? fromBytes(Uint8List bytes) {
    if (bytes.length < 8) return null;
    final b = ByteData.sublistView(bytes);
    if (b.getUint32(0) != 0x4D4B4150) return null;
    final n = (bytes.length - 8) ~/ 4;
    final w = Uint32List(n);
    for (var i = 0; i < n; i++) {
      w[i] = b.getUint32(8 + i * 4);
    }
    return AudioPrint(w, offset: b.getFloat32(4).toDouble());
  }
}

/// In-place radix-2 FFT of (re, im)
void _fft(Float64List re, Float64List im) {
  final n = re.length;
  for (var i = 1, j = 0; i < n; i++) {
    var bit = n >> 1;
    for (; (j & bit) != 0; bit >>= 1) {
      j ^= bit;
    }
    j ^= bit;
    if (i < j) {
      final tr = re[i];
      re[i] = re[j];
      re[j] = tr;
      final ti = im[i];
      im[i] = im[j];
      im[j] = ti;
    }
  }
  for (var len = 2; len <= n; len <<= 1) {
    final ang = -2 * math.pi / len;
    final wr = math.cos(ang);
    final wi = math.sin(ang);
    for (var i = 0; i < n; i += len) {
      var cr = 1.0;
      var ci = 0.0;
      final half = len >> 1;
      for (var k = 0; k < half; k++) {
        final a = i + k;
        final b = a + half;
        final xr = re[b] * cr - im[b] * ci;
        final xi = re[b] * ci + im[b] * cr;
        re[b] = re[a] - xr;
        im[b] = im[a] - xi;
        re[a] += xr;
        im[a] += xi;
        final nr = cr * wr - ci * wi;
        ci = cr * wi + ci * wr;
        cr = nr;
      }
    }
  }
}

/// The fingerprint of [pcm] (mono, [printRate] Hz). [offset]: where it starts on the video's timeline
AudioPrint audioPrint(Int16List pcm, {double offset = 0}) {
  final frames = pcm.length < _frame ? 0 : (pcm.length - _frame) ~/ _hop + 1;
  final words = Uint32List(frames);
  if (frames == 0) return AudioPrint(words, offset: offset);
  final window = Float64List(_frame);
  for (var i = 0; i < _frame; i++) {
    window[i] = 0.5 - 0.5 * math.cos(2 * math.pi * i / (_frame - 1));
  }
  // Band edges in FFT bins, log-spaced 300…2000 Hz
  final edges = List<int>.generate(_bands + 1, (k) {
    final f = 300 * math.pow(2000 / 300, k / _bands);
    return (f * _frame / printRate).round();
  });
  final re = Float64List(_frame);
  final im = Float64List(_frame);
  // The band energies of the last [_lag] steps: each word compares with the step 64 ms back (16 ms apart the frames
  // are nearly the same, and faint noise would decide the bits)
  final past = List<Float64List>.generate(_lag + 1, (_) => Float64List(_bands));
  var seed = 0x9E3779B9;
  for (var n = 0; n < frames; n++) {
    final base = n * _hop;
    var energy = 0.0;
    for (var i = 0; i < _frame; i++) {
      final v = pcm[base + i] / 32768.0;
      energy += v * v;
      re[i] = v * window[i];
      im[i] = 0;
    }
    _fft(re, im);
    final cur = past[n % (_lag + 1)];
    for (var m = 0; m < _bands; m++) {
      var e = 0.0;
      for (var k = edges[m]; k < edges[m + 1]; k++) {
        e += re[k] * re[k] + im[k] * im[k];
      }
      cur[m] = e;
    }
    var w = 0;
    if (energy / _frame < 1e-7) {
      // Silence: its bits would be the same in any two episodes; a word of its own never matches anything
      seed = (seed * 1103515245 + 12345 + n) & 0xFFFFFFFF;
      w = seed;
    } else if (n >= _lag) {
      final prev = past[(n - _lag) % (_lag + 1)];
      for (var m = 0; m < 32; m++) {
        final d = (cur[m] - cur[m + 1]) - (prev[m] - prev[m + 1]);
        if (d > 0) w |= 1 << m;
      }
    }
    words[n] = w;
  }
  return AudioPrint(words, offset: offset);
}

/// A stretch two fingerprints share: from [aStart] in the first, from [bStart] in the second, [length] seconds (all on
/// the videos' timelines), with this share of differing bits
class PrintRun {
  final double aStart;
  final double bStart;
  final double length;
  final double ber;

  const PrintRun(this.aStart, this.bStart, this.length, this.ber);

  double get aEnd => aStart + length;
  double get bEnd => bStart + length;

  @override
  String toString() => 'PrintRun(${aStart.toStringAsFixed(1)}/${bStart.toStringAsFixed(1)}, ${length.toStringAsFixed(1)} с, ${(ber * 100).round()} %)';
}

final Uint8List _bits16 = () {
  final t = Uint8List(65536);
  for (var i = 1; i < 65536; i++) {
    t[i] = (i & 1) + t[i >> 1];
  }
  return t;
}();

int _pop(int x) => _bits16[x & 0xFFFF] + _bits16[(x >> 16) & 0xFFFF];

/// Every offset is tried, but along it only every [_stride]-th step is compared (64 ms apart): a quarter of the work
const int _stride = 4;

/// The stretches [a] and [b] share, longest first (each place of [a] in one stretch only). A stretch: one second at a
/// time with fewer than [maxBer] of the bits differing (a worse second or so inside it is forgiven: a sound effect over
/// the song, a different encoder), at least [minSeconds] long
List<PrintRun> commonRuns(AudioPrint a, AudioPrint b, {double minSeconds = 2.0, double maxBer = 0.35}) {
  final wa = a.words;
  final wb = b.words;
  // A window of 16 compared steps ≈ 1 s; a gap of up to 1.5 s inside a stretch
  const win = 16;
  final gap = (1.5 / (printStep * _stride)).round();
  final limit = (maxBer * 32 * win).floor();
  final minSteps = (minSeconds / printStep).ceil();
  final found = <(int, int, int, int)>[]; // (iA, iB, steps, differing bits)
  final errs = Int32List(wa.length ~/ _stride + 2);
  // The ends of a stretch hold windows (and frames) only partly inside it: they are tightened to where single steps
  // match about as well as the stretch does
  int near(int q, int s, int g) {
    var t = 0;
    var c = 0;
    for (var x = q - 1; x <= q + 1; x++) {
      if (x < s || x > g) continue;
      t += errs[x];
      c++;
    }
    return c == 0 ? 32 : t ~/ c;
  }

  void emit(int from, int k, int s, int g) {
    if ((g + 1 - s) * _stride < minSteps) return;
    final sorted = Int32List.fromList(errs.sublist(s, g + 1))..sort();
    final median = sorted[sorted.length ~/ 2];
    // Differing bits (of 32) above which a step is unlike: alike steps differ in a few, unlike ones in ~16
    final edge = math.min(13, math.max(median * 2, median + 3));
    while (s < g && near(s, s, g) > edge) {
      s++;
    }
    while (g > s && near(g, s, g) > edge) {
      g--;
    }
    final len = (g + 1 - s) * _stride;
    if (len < minSteps) return;
    var err = 0;
    for (var q = s; q <= g; q++) {
      err += errs[q];
    }
    found.add((from + s * _stride, from + s * _stride + k, len, err * _stride));
  }

  for (var k = -(wa.length - 1); k < wb.length; k++) {
    // Overlap: i in A, i + k in B
    final from = math.max(0, -k);
    final to = math.min(wa.length, wb.length - k);
    if (to - from < minSteps) continue;
    final n = (to - from + _stride - 1) ~/ _stride;
    var sum = 0;
    var runStart = -1;
    var lastGood = -1;
    for (var j = 0; j < n; j++) {
      final i = from + j * _stride;
      final e = _pop(wa[i] ^ wb[i + k]);
      errs[j] = e;
      sum += e;
      if (j >= win) sum -= errs[j - win];
      if (j < win - 1) continue;
      if (sum <= limit) {
        if (runStart < 0) runStart = j - win + 1;
        lastGood = j;
      } else if (runStart >= 0 && j - lastGood > gap) {
        emit(from, k, runStart, lastGood);
        runStart = -1;
      }
    }
    if (runStart >= 0) emit(from, k, runStart, lastGood);
  }
  // Neighbouring offsets find the same stretch: the best stays — long, and alike (the offset that fits it exactly)
  double score((int, int, int, int) f) => f.$3 * (0.5 - f.$4 / (32 * f.$3));
  found.sort((x, y) => score(y).compareTo(score(x)));
  final out = <PrintRun>[];
  final taken = <(int, int)>[];
  for (final f in found) {
    final s = f.$1;
    final e = f.$1 + f.$3;
    final overlaps = taken.any((t) => math.min(e, t.$2) - math.max(s, t.$1) > (e - s) ~/ 3);
    if (overlaps) continue;
    taken.add((s, e));
    out.add(PrintRun(a.offset + s * printStep, b.offset + f.$2 * printStep, f.$3 * printStep, f.$4 / (32 * f.$3)));
    if (out.length >= 8) break;
  }
  return out;
}

/// What two episodes' first minutes tell: the dub's own intro (common from the very start) and the opening in each
class Listened {
  /// Seconds of the dub's intro at the start of both (null: none)
  final double? intro;
  final PrintRun? opening;

  const Listened({this.intro, this.opening});
}

/// Reads [runs] (from [commonRuns]). A stretch both episodes start with (within a second) is the dub's intro, the
/// opening from the very start, or both: [opLength] (AniSkip's) tells which — about its length is the opening, longer
/// is the intro and the opening right after it, much shorter is the intro alone; without it, up to 20 s is an intro.
/// Otherwise the opening is the longest stretch of 20–160 s, the one nearest [opLength] when it is known
Listened listenRuns(List<PrintRun> runs, {double? opLength}) {
  PrintRun? prefix;
  for (final r in runs) {
    if (r.aStart <= 1.0 && r.bStart <= 1.0 && (r.aStart - r.bStart).abs() <= 0.5) {
      prefix = r;
      break;
    }
  }
  double? intro;
  PrintRun? opening;
  if (prefix != null) {
    final op = opLength;
    final diff = op == null ? null : prefix.length - op;
    if (diff != null && diff.abs() <= 3) {
      opening = prefix;
    } else if (diff != null && diff > 3 && diff <= 45) {
      intro = prefix.aStart + diff;
      opening = PrintRun(prefix.aStart + diff, prefix.bStart + diff, op!, prefix.ber);
    } else if (prefix.length <= (op == null ? 20 : 45)) {
      intro = prefix.aEnd;
    } else {
      opening = prefix;
    }
  }
  if (opening == null) {
    final candidates = [for (final r in runs) if (r != prefix && r.length >= 20 && r.length <= 160) r];
    if (candidates.isNotEmpty) {
      final op = opLength;
      candidates.sort((x, y) => op == null ? y.length.compareTo(x.length) : (x.length - op).abs().compareTo((y.length - op).abs()));
      final best = candidates.first;
      if (op == null || (best.length - op).abs() <= 12) opening = best;
    }
  }
  if (intro != null && intro < 1.5) intro = null;
  return Listened(intro: intro, opening: opening);
}
