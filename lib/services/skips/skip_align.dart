/// How AniSkip's times (marked on some version of the episode) move onto our video. Pure logic.
///
/// Our video = AniSkip's version + seconds inserted at the start (the dub team's intro, a Uniplex logo) + seconds at the
/// end (the team's credits), sometimes minus what was cut. Every moment of the episode itself moves by the start insert
/// alone, so that is the one thing to know ([StartShift]); the total difference (our length − the version's) only tells
/// its bounds. While it is not known exactly, the times are made safe ([alignSkips]): the button is shown only where
/// every possible shift — and every version that may be ours — says "opening", and it jumps to the earliest possible
/// end. The episode itself is never skipped: at worst a few seconds of the opening are left, and nothing is skipped by
/// itself.
library;

import 'dart:math' as math;

import '../../models/source_models.dart';
import 'aniskip.dart';

/// What is known of the seconds inserted before the episode (a range; exact when narrow)
class StartShift {
  final double min;
  final double max;

  /// Where it is known from: `length` (the lengths alone), `site`, `audio`, `user`
  final String source;

  const StartShift(this.min, this.max, this.source);

  const StartShift.exact(double v, this.source)
      : min = v,
        max = v;

  /// Narrower than this counts as known
  static const double exactWidth = 1.0;

  bool get exact => max - min <= exactWidth;
  double get mid => (min + max) / 2;

  /// What both say; null when they do not agree (allowing [slack] seconds)
  StartShift? intersect(StartShift o, {double slack = 1.0}) {
    final lo = math.max(min, o.min);
    final hi = math.min(max, o.max);
    if (lo > hi + slack) return null;
    if (lo > hi) return StartShift.exact((lo + hi) / 2, o.source);
    return StartShift(lo, hi, o.exact ? o.source : source);
  }

  @override
  String toString() => exact ? '${mid.toStringAsFixed(1)} с ($source)' : '${min.toStringAsFixed(1)}…${max.toStringAsFixed(1)} с ($source)';
}

/// The skips of one episode for the player
class SkipPlan {
  /// The episode it belongs to (`animeKey#groupId#epKey`)
  final String key;

  /// On our timeline; `exact: false` — safe times (button only)
  final List<TimeStamp> stamps;

  /// The shift AniSkip's times were moved by (null: no AniSkip times used)
  final StartShift? shift;

  /// For people: «сайт», «AniSkip», «AniSkip + аналіз звуку»…
  final String source;

  /// Our length − the length of the version the opening was marked on
  final double? extra;

  /// Where AniSkip's opening starts on its version (so "the opening started here" tells the shift)
  final double? opBase;

  const SkipPlan({required this.key, required this.stamps, this.shift, required this.source, this.extra, this.opBase});

  bool get exact => stamps.every((s) => s.exact);

  /// Its times came from AniSkip, so their shift can be corrected by hand
  bool get adjustable => shift != null;

  SkipPlan copyWith({List<TimeStamp>? stamps, String? source}) =>
      SkipPlan(key: key, stamps: stamps ?? this.stamps, shift: shift, source: source ?? this.source, extra: extra, opBase: opBase);
}

/// Lengths closer than this count as the same version (seconds: different containers measure a bit differently)
const double sameLength = 1.5;

/// More inserted than this, or more cut, and it is another version (a recap episode, a double one): its times are not used.
/// A TV rip is often half a minute shorter than the version AniSkip marked (Gintama 1: 1454 s there, ~1420 s here); 75 s
/// either way still leaves 15 s that surely belong to a 90-second opening
const double maxInsert = 75;
const double maxCut = 75;

/// Too short a safe interval is not worth a button
const double minSafeSkip = 15;

/// A measured shift may lie this far outside what the lengths allow (containers measure lengths a bit differently)
const double shiftSlack = 2.0;

/// The kinds that mark one thing: an opening is `op`, else `mixed-op` (and so on)
const List<List<SkipKind>> _kindGroups = [
  [SkipKind.recap],
  [SkipKind.op, SkipKind.mixedOp],
  [SkipKind.ed, SkipKind.mixedEd],
];

bool _plausible(AniSkipTime t, double duration) {
  final extra = duration - t.episodeLength;
  return extra <= maxInsert && extra >= -maxCut && t.end <= t.episodeLength + 1;
}

/// AniSkip's times of one thing (the first of [kinds] that has any) that can be on our video of [duration] s: our video
/// may be longer by what was inserted or a little shorter by what was cut. The likeliest first: nearest to [expected]
/// extra seconds (0: the same length)
List<AniSkipTime> versionsOf(List<AniSkipTime> all, List<SkipKind> kinds, double duration, {double expected = 0}) {
  for (final k in kinds) {
    final list = [for (final t in all) if (t.kind == k && _plausible(t, duration)) t];
    if (list.isEmpty) continue;
    list.sort((a, b) => ((duration - a.episodeLength) - expected).abs().compareTo(((duration - b.episodeLength) - expected).abs()));
    return list;
  }
  return const [];
}

/// The likeliest version of each thing (recap, opening, ending)
List<AniSkipTime> pickVersions(List<AniSkipTime> all, double duration, {double expected = 0}) => [
      for (final kinds in _kindGroups)
        if (versionsOf(all, kinds, duration, expected: expected) case [final first, ...]) first,
    ];

/// What the lengths alone say of the start shift for a time marked on a version of [episodeLength] s
StartShift lengthShift(double duration, double episodeLength) {
  final extra = duration - episodeLength;
  if (extra.abs() <= sameLength) return const StartShift.exact(0, 'length');
  // Inserted: somewhere between nothing and all of it at the start; cut: the same, backwards
  return extra > 0 ? StartShift(0, extra, 'length') : StartShift(extra, 0, 'length');
}

/// Whether a start shift of [shift] s can be ours if [t]'s version is
bool fitsShift(AniSkipTime t, double duration, double shift) {
  final b = lengthShift(duration, t.episodeLength);
  return shift >= b.min - shiftSlack && shift <= b.max + shiftSlack;
}

/// The start shift an opening measured on our video ([start], [length] s) tells against AniSkip's opening: of the
/// versions that may be ours (likeliest first), the first marking an opening of about that length ([lengthSlack]) that
/// the lengths allow at that place (with that version). Null when none does
(double, AniSkipTime)? shiftFromOpening(List<AniSkipTime> all, double duration, double start, double length, {double expected = 0, double lengthSlack = 6}) {
  for (final t in versionsOf(all, const [SkipKind.op, SkipKind.mixedOp], duration, expected: expected)) {
    if ((t.length - length).abs() > lengthSlack) continue;
    final shift = start - t.start;
    if (fitsShift(t, duration, shift)) return (shift, t);
  }
  return null;
}

String _nameOf(SkipKind k) => switch (k) {
      SkipKind.op || SkipKind.mixedOp => 'Опенінґ',
      SkipKind.ed || SkipKind.mixedEd => 'Ендінґ',
      SkipKind.recap => 'Рекап',
    };

ChapterType _typeOf(SkipKind k) => switch (k) {
      SkipKind.op => ChapterType.opening,
      SkipKind.mixedOp => ChapterType.mixedOp,
      SkipKind.ed || SkipKind.mixedEd => ChapterType.ending,
      SkipKind.recap => ChapterType.recap,
    };

/// One thing on our timeline from versions [vs] moved by shifts [ss] (one per version). Where they all agree within a
/// second it is exact; otherwise safe: from the latest possible start to the earliest possible end, if long enough
TimeStamp? _place(List<AniSkipTime> vs, List<StartShift> ss, double duration) {
  var loS = double.infinity, hiS = double.negativeInfinity, loE = double.infinity, hiE = double.negativeInfinity;
  for (var i = 0; i < vs.length; i++) {
    loS = math.min(loS, vs[i].start + ss[i].min);
    hiS = math.max(hiS, vs[i].start + ss[i].max);
    loE = math.min(loE, vs[i].end + ss[i].min);
    hiE = math.max(hiE, vs[i].end + ss[i].max);
  }
  final exact = hiS - loS <= StartShift.exactWidth && hiE - loE <= StartShift.exactWidth;
  double start;
  double end;
  if (exact) {
    start = (loS + hiS) / 2;
    end = (loE + hiE) / 2;
  } else {
    start = hiS;
    end = loE;
    if (end - start < minSafeSkip) return null;
  }
  start = math.max(0, start);
  if (duration > 0) end = math.min(duration, end);
  if (end - start < 5) return null;
  final k = vs.first.kind;
  return TimeStamp(start, end, _nameOf(k), _typeOf(k), exact);
}

/// The skips for our video of [duration] s from AniSkip's times [all]. [known]: what was learned of this dub's start
/// shift (the site's own times, listening, a correction by hand). When it is exact, the versions it fits are taken and
/// moved by it; otherwise every version that may be ours is moved by every shift the lengths allow, and only where they
/// all agree is skipped. [expected]: the team's usual start shift from its other titles — it only orders the versions.
/// Null when nothing fits
SkipPlan? alignSkips(String key, List<AniSkipTime> all, double duration, {StartShift? known, double? expected}) {
  if (all.isEmpty || duration <= 0) return null;
  final k = known != null && known.exact ? known : null;
  final stamps = <TimeStamp>[];
  StartShift? used;
  double? extra;
  double? opBase;
  for (final kinds in _kindGroups) {
    var versions = versionsOf(all, kinds, duration, expected: expected ?? 0);
    if (versions.isEmpty) continue;
    if (k != null) {
      final fit = [for (final t in versions) if (fitsShift(t, duration, k.mid)) t];
      if (fit.isNotEmpty) versions = fit;
    }
    final primary = versions.first;
    TimeStamp? placed;
    StartShift shift;
    if (k != null && (k.source == 'user' || fitsShift(primary, duration, k.mid))) {
      // Known: the likeliest version moved by it (a hand correction is taken as it is)
      shift = k;
      placed = _place([primary], [k], duration);
    } else {
      final shifts = [
        for (final t in versions)
          if (known != null) lengthShift(duration, t.episodeLength).intersect(known) ?? lengthShift(duration, t.episodeLength) else lengthShift(duration, t.episodeLength),
      ];
      shift = shifts.first;
      placed = _place(versions, shifts, duration);
    }
    final isOp = primary.kind == SkipKind.op || primary.kind == SkipKind.mixedOp;
    // Even an opening that could not be placed safely can be marked by hand against its likeliest version
    if (isOp) opBase = primary.start;
    if (placed == null) continue;
    stamps.add(placed);
    if (isOp || used == null) {
      used = shift;
      extra = duration - primary.episodeLength;
    }
  }
  if (stamps.isEmpty) return null;
  stamps.sort((a, b) => a.start.compareTo(b.start));
  return SkipPlan(key: key, stamps: stamps, shift: used, source: 'AniSkip', extra: extra, opBase: opBase);
}

// ── For the log ─────────────────────────────────────────────────────────────

String _kindShort(SkipKind k) => switch (k) {
      SkipKind.op => 'оп',
      SkipKind.mixedOp => 'оп-мікс',
      SkipKind.ed => 'ед',
      SkipKind.mixedEd => 'ед-мікс',
      SkipKind.recap => 'рекап',
    };

String _clock(double s) {
  final t = s.round();
  return '${t ~/ 60}:${(t % 60).toString().padLeft(2, '0')}';
}

/// AniSkip's times against our video of [duration] s, in a line: «оп 3:38–5:08 на версії 1454 с (−34 с)», «… (−1446 с:
/// інша версія)»
String describeTimes(List<AniSkipTime> all, double duration) {
  if (all.isEmpty) return 'нічого не позначено';
  String fit(AniSkipTime t) {
    final extra = duration - t.episodeLength;
    if (t.end > t.episodeLength + 1) return 'час за кінцем версії';
    if (extra.abs() <= sameLength) return 'та сама довжина';
    final d = '${extra > 0 ? '+' : '−'}${extra.abs().round()} с';
    return _plausible(t, duration) ? d : '$d: інша версія';
  }

  return [for (final t in all) '${_kindShort(t.kind)} ${_clock(t.start)}–${_clock(t.end)} на версії ${t.episodeLength.round()} с (${fit(t)})'].join('; ');
}

/// [first]'s times, and [second]'s for what [first] has nothing that fits our video of [duration] s (an opening, an
/// ending, a recap): a second base fills gaps, it does not blur the first's exact times (two people never mark the
/// very same second, and the safe stretch of both would take the auto-skip away)
List<AniSkipTime> withFallback(List<AniSkipTime> first, List<AniSkipTime> second, double duration) {
  int family(SkipKind k) => switch (k) {
        SkipKind.op || SkipKind.mixedOp => 0,
        SkipKind.ed || SkipKind.mixedEd => 1,
        SkipKind.recap => 2,
      };
  final covered = {for (final t in first) if (_plausible(t, duration)) family(t.kind)};
  return [...first, for (final t in second) if (!covered.contains(family(t.kind))) t];
}

/// The bases whose times fit our video of [duration] s, for people: «AniSkip», «Anime Skip», «AniSkip і Anime Skip»
String basesOf(List<AniSkipTime> all, double duration) {
  final names = <String>{for (final t in all) if (_plausible(t, duration)) t.base};
  return names.isEmpty ? 'AniSkip' : names.join(' і ');
}

/// A plan in a line: «Опенінґ 3:38–4:33 (безпечно), Ендінґ 21:10–22:40; зсув 0.0…22.0 с (length)»
String describePlan(SkipPlan p) =>
    '${[for (final s in p.stamps) '${s.name} ${_clock(s.start)}–${_clock(s.end)}${s.exact ? '' : ' (безпечно)'}'].join(', ')}'
    '${p.shift == null ? '' : '; зсув ${p.shift}'}';
