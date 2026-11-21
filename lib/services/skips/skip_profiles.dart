/// What was learned of how each dub's videos differ from AniSkip's versions (StorageService section `skip_profiles`).
///
/// - Per title + dub (`animeKey|groupId`): observations of the start shift — the seconds inserted before the episode —
///   each with where it came from (`site`: the site's own times compared with AniSkip's; `audio`: the opening found by
///   listening), a correction by hand, the dub's own intro found by listening, and per episode the opening found by
///   listening (exact times for that very video).
/// - Per team (by name): its observations from every title — a hint for titles not met yet (it picks AniSkip's
///   version, but never makes times exact by itself: one title may carry a Uniplex logo, another not).
library;

import 'package:flutter/foundation.dart';

import '../storage_service.dart';
import '../watch_models.dart';
import 'skip_align.dart';

/// What listening found in one episode (seconds on its own timeline)
class EpisodeListen {
  final double? opStart;
  final double? opEnd;

  /// The dub's own intro at the very start (0…[intro]), the same in every episode
  final double? intro;

  const EpisodeListen({this.opStart, this.opEnd, this.intro});

  bool get hasOp => opStart != null && opEnd != null && opEnd! > opStart!;

  Map<String, Object> toJson() => {
        if (opStart != null) 'os': opStart!,
        if (opEnd != null) 'oe': opEnd!,
        if (intro != null) 'in': intro!,
      };

  static EpisodeListen? fromJson(Object? raw) {
    if (raw is! Map) return null;
    return EpisodeListen(
      opStart: (raw['os'] as num?)?.toDouble(),
      opEnd: (raw['oe'] as num?)?.toDouble(),
      intro: (raw['in'] as num?)?.toDouble(),
    );
  }
}

class SkipProfiles extends ChangeNotifier {
  static SkipProfiles instance = SkipProfiles();

  static const String section = 'skip_profiles';

  /// Observations kept per dub and per team (the newest)
  static const int _keep = 12;

  /// Observations closer than this agree
  static const double agree = 1.5;

  final Map<String, dynamic> Function() _load;
  final void Function(Map<String, dynamic>) _save;

  SkipProfiles({Map<String, dynamic> Function()? load, void Function(Map<String, dynamic>)? save})
      : _load = load ?? (() => StorageService.getSection(section)),
        _save = save ?? ((m) => StorageService.saveSection(section, m));

  Map<String, dynamic>? _data;

  Map<String, dynamic> get _all => _data ??= () {
        final raw = _load();
        return <String, dynamic>{
          'dubs': Map<String, dynamic>.of((raw['dubs'] as Map?)?.cast<String, dynamic>() ?? const {}),
          'teams': Map<String, dynamic>.of((raw['teams'] as Map?)?.cast<String, dynamic>() ?? const {}),
        };
      }();

  static String dubKey(String animeKey, WatchGroup g) => '$animeKey|${g.id}';

  /// The team's name as a key (several teams of one release count as one name)
  static String teamKey(WatchGroup g) => g.teamLabel.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

  Map<String, dynamic> _dub(String animeKey, WatchGroup g, {bool create = false}) {
    final dubs = _all['dubs'] as Map<String, dynamic>;
    final k = dubKey(animeKey, g);
    final cur = dubs[k];
    if (cur is Map) return cur.cast<String, dynamic>();
    final fresh = <String, dynamic>{};
    if (create) dubs[k] = fresh;
    return fresh;
  }

  void _commit() {
    _save(_all);
    notifyListeners();
  }

  static List<double> _values(Object? obs, {Set<String>? sources}) => [
        for (final o in (obs as List?) ?? const [])
          if (o is List && o.isNotEmpty && o[0] is num && (sources == null || (o.length > 1 && sources.contains(o[1])))) (o[0] as num).toDouble(),
      ];

  static double _median(List<double> v) {
    final s = [...v]..sort();
    final n = s.length;
    return n.isOdd ? s[n ~/ 2] : (s[n ~/ 2 - 1] + s[n ~/ 2]) / 2;
  }

  /// The start shift of this dub as far as it is known: a hand correction; else what the site's times and listening
  /// agree on (exact) or the range they span; null when nothing was learned
  StartShift? shiftFor(String animeKey, WatchGroup g) {
    final d = _dub(animeKey, g);
    final user = (d['user'] as num?)?.toDouble();
    if (user != null) return StartShift.exact(user, 'user');
    final audio = _values(d['obs'], sources: {'audio'});
    final site = _values(d['obs'], sources: {'site'});
    // Listening measures this very video: it outweighs the site's times
    final v = audio.isNotEmpty ? audio : site;
    if (v.isEmpty) return null;
    final lo = v.reduce((a, b) => a < b ? a : b);
    final hi = v.reduce((a, b) => a > b ? a : b);
    final source = audio.isNotEmpty ? 'audio' : 'site';
    if (hi - lo <= agree) return StartShift.exact(_median(v), source);
    return StartShift(lo, hi, source);
  }

  /// The team's usual start shift over its titles (only a hint: it picks AniSkip's version), when they agree
  double? teamHint(WatchGroup g) {
    final t = (_all['teams'] as Map<String, dynamic>)[teamKey(g)];
    final v = _values(t is Map ? t['obs'] : null);
    if (v.length < 2) return null;
    final m = _median(v);
    final close = v.where((x) => (x - m).abs() <= agree).length;
    return close * 3 >= v.length * 2 ? m : null;
  }

  /// A measured start shift of this dub ([source]: `site` or `audio`)
  void observe(String animeKey, WatchGroup g, double shift, String source) {
    final d = _dub(animeKey, g, create: true);
    final obs = [...((d['obs'] as List?) ?? const []), [double.parse(shift.toStringAsFixed(2)), source, DateTime.now().millisecondsSinceEpoch]];
    d['obs'] = obs.length > _keep ? obs.sublist(obs.length - _keep) : obs;
    final teams = _all['teams'] as Map<String, dynamic>;
    final tk = teamKey(g);
    if (tk.isNotEmpty) {
      final t = Map<String, dynamic>.of((teams[tk] as Map?)?.cast<String, dynamic>() ?? const {});
      final tobs = [...((t['obs'] as List?) ?? const []), [double.parse(shift.toStringAsFixed(2)), animeKey]];
      t['obs'] = tobs.length > _keep * 2 ? tobs.sublist(tobs.length - _keep * 2) : tobs;
      teams[tk] = t;
    }
    _commit();
  }

  double? userShift(String animeKey, WatchGroup g) => (_dub(animeKey, g)['user'] as num?)?.toDouble();

  /// A correction by hand (null: forget it, back to what was learned)
  void setUser(String animeKey, WatchGroup g, double? shift) {
    final d = _dub(animeKey, g, create: true);
    if (shift == null) {
      d.remove('user');
    } else {
      d['user'] = double.parse(shift.toStringAsFixed(2));
    }
    _commit();
  }

  /// The dub's own intro at the start of every episode (found by listening), seconds
  double? introFor(String animeKey, WatchGroup g) => (_dub(animeKey, g)['intro'] as num?)?.toDouble();

  void setIntro(String animeKey, WatchGroup g, double seconds) {
    _dub(animeKey, g, create: true)['intro'] = double.parse(seconds.toStringAsFixed(2));
    _commit();
  }

  /// What listening found in episode [epKey]
  EpisodeListen? episode(String animeKey, WatchGroup g, String epKey) => EpisodeListen.fromJson((_dub(animeKey, g)['eps'] as Map?)?[epKey]);

  void saveEpisode(String animeKey, WatchGroup g, String epKey, EpisodeListen e) {
    final d = _dub(animeKey, g, create: true);
    final eps = Map<String, dynamic>.of((d['eps'] as Map?)?.cast<String, dynamic>() ?? const {});
    eps[epKey] = e.toJson();
    d['eps'] = eps;
    _commit();
  }

  /// Episodes of this dub with something found by listening
  Iterable<String> listened(String animeKey, WatchGroup g) => ((_dub(animeKey, g)['eps'] as Map?)?.keys ?? const []).map((k) => '$k');
}
