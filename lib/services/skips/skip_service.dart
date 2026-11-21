/// Skips for site episodes that came without times of their own: AniSkip's times moved onto our video, made exact by
/// what was learned of the dub, and by listening.
///
/// The player tells which episode plays ([SkipService.attach]); the plan for it is in [SkipService.current] and changes
/// when more is learned (listening found the opening, a correction by hand). Where it comes from, in order:
/// 1. the site's own times (Moon) — exact; compared with AniSkip's they teach the dub's start shift;
/// 2. what listening found in this very episode — the opening, the dub's intro;
/// 3. AniSkip's times moved by the dub's start shift (`SkipProfiles.shiftFor`: listening, the site, a correction);
/// 4. AniSkip's times made safe (`alignSkips`): a button only where every possible shift has the opening.
/// Listening (`_listen`) compares the first minutes of two episodes of the dub: on Wi-Fi or from downloads only.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../../models/source_models.dart';
import '../app_log.dart';
import '../downloads/download_manager.dart';
import '../downloads/download_models.dart';
import '../hikka_api.dart';
import '../network_status.dart';
import '../source_prefs.dart';
import '../source_registry.dart';
import '../storage_service.dart';
import '../stream_resolver.dart';
import '../watch_models.dart';
import 'anime_skip.dart';
import 'aniskip.dart';
import 'audio_print.dart';
import 'audio_probe.dart';
import 'skip_align.dart';
import 'skip_profiles.dart';

/// The episode the player opened
class SkipRequest {
  final String animeKey;
  final WatchGroup group;
  final int index;
  final String epKey;

  /// AniSkip's episode number (null: our numbering may not match MyAnimeList's — merged parts and the like)
  final int? number;

  /// Seconds
  final double duration;
  final Video video;

  /// The site's own times (Moon); empty when it gave none
  List<TimeStamp> get site => video.timestamps;

  const SkipRequest({
    required this.animeKey,
    required this.group,
    required this.index,
    required this.epKey,
    required this.number,
    required this.duration,
    required this.video,
  });

  String get key => '$animeKey#${group.id}#$epKey';
}

class SkipService {
  static SkipService instance = SkipService();

  final AniSkip _aniskip;
  final AnimeSkip _animeSkip;
  final SkipProfiles _profiles;
  final PcmDecoder _decode;
  final Future<int?> Function(String animeKey) _malId;
  final Future<Video?> Function(String sourceId, SEpisode episode) _videoOf;
  final NetworkStatus Function() _network;
  final bool Function() _listenOn;
  final String? _printsDir;

  /// Listening waits this long after the start (the player buffers first)
  final Duration listenDelay;

  /// How much of an episode's start is listened to (seconds)
  final double listenLength;

  /// Fingerprinting and comparing run here (an isolate in the app; at once in tests)
  final Future<R> Function<M, R>(R Function(M) fn, M message) _compute;

  SkipService({
    AniSkip? aniskip,
    AnimeSkip? animeSkip,
    SkipProfiles? profiles,
    PcmDecoder? decode,
    Future<int?> Function(String animeKey)? malId,
    Future<Video?> Function(String sourceId, SEpisode episode)? videoOf,
    NetworkStatus Function()? network,
    bool Function()? listenOn,
    String? printsDir,
    this.listenDelay = const Duration(seconds: 6),
    this.listenLength = 240,
    Future<R> Function<M, R>(R Function(M) fn, M message)? run,
  })  : _aniskip = aniskip ?? AniSkip.instance,
        _animeSkip = animeSkip ?? AnimeSkip.instance,
        _profiles = profiles ?? SkipProfiles.instance,
        _decode = decode ?? AudioProbe.decode,
        _malId = malId ?? _hikkaMalId,
        _videoOf = videoOf ?? _siteVideo,
        _network = network ?? (() => NetworkStatus.instance),
        _listenOn = listenOn ?? StorageService.getListenForSkips,
        _printsDir = printsDir,
        _compute = run ?? _isolate;

  static Future<R> _isolate<M, R>(R Function(M) fn, M message) => compute(fn, message);

  /// Heard stretches are used a little inside their edges (seconds): a skip lands a moment before the episode goes on
  static const double edgeIn = 0.2;
  static const double edgeOut = 0.4;

  /// Fingerprints kept on disk (60 KB each): the newest
  static const int keepPrints = 200;

  /// The plan of the episode playing now (null: nothing to skip, or nothing yet)
  final ValueNotifier<SkipPlan?> current = ValueNotifier<SkipPlan?>(null);

  SkipRequest? _req;
  Timer? _listenTimer;
  final Set<String> _listening = {};

  SkipRequest? get request => _req;

  // ── The player's episode ─────────────────────────────────────────────────

  /// The player opened [r]: its plan goes to [current] (the site's times at once; AniSkip's when they come)
  Future<void> attach(SkipRequest r) async {
    _req = r;
    _listenTimer?.cancel();
    if (r.site.isNotEmpty) {
      current.value = SkipPlan(key: r.key, stamps: r.site, source: 'сайт');
      unawaited(_learnFromSite(r));
      return;
    }
    current.value = null;
    await refresh();
    if (_req?.key != r.key) return;
    final why = _whyNotListen(r);
    if (why == null) {
      _listenTimer = Timer(listenDelay, () => unawaited(_listen(r)));
      AppLog.i('пропуск', 'аналіз звуку: за ${listenDelay.inSeconds} с слухатиму початок ${r.epKey} і сусідньої серії');
    } else if (why.isNotEmpty) {
      AppLog.i('пропуск', 'аналіз звуку: $why');
    }
  }

  /// The player left the episode
  void detach() {
    _req = null;
    _listenTimer?.cancel();
    current.value = null;
  }

  /// The last plan written to the log (a plan that did not change is not written again)
  String? _logged;

  /// Plans the current episode again (after something was learned)
  Future<void> refresh() async {
    final r = _req;
    if (r == null || r.site.isNotEmpty) return;
    final (plan, why) = await _plan(r);
    if (_req?.key != r.key) return;
    current.value = plan;
    final line = '${r.group.teamLabel} · ${r.epKey}, відео ${r.duration.round()} с; $why';
    if (line != _logged) AppLog.i('пропуск', _logged = line);
  }

  /// Moves the current episode's AniSkip times by [delta] seconds — for every episode of this dub
  Future<void> shiftBy(double delta) async {
    final r = _req;
    final plan = current.value;
    if (r == null || plan == null || plan.shift == null) return;
    final now = _profiles.userShift(r.animeKey, r.group) ?? plan.shift!.mid;
    _profiles.setUser(r.animeKey, r.group, double.parse((now + delta).toStringAsFixed(2)));
    AppLog.i('пропуск', 'зсув вручну: ${r.group.teamLabel} → ${(now + delta).toStringAsFixed(1)} с');
    await refresh();
  }

  /// The viewer marked where the current episode's opening starts ([position] s): AniSkip's opening moves there, and
  /// every time of this dub with it
  Future<void> openingAt(double position) async {
    final r = _req;
    final base = current.value?.opBase;
    if (r == null || base == null) return;
    _profiles.setUser(r.animeKey, r.group, double.parse((position - base).toStringAsFixed(2)));
    AppLog.i('пропуск', 'початок опенінґу вручну: ${r.group.teamLabel} ${r.epKey} → ${position.toStringAsFixed(1)} с');
    await refresh();
  }

  /// Forgets the correction by hand
  Future<void> resetShift() async {
    final r = _req;
    if (r == null) return;
    _profiles.setUser(r.animeKey, r.group, null);
    await refresh();
  }

  // ── Planning ──────────────────────────────────────────────────────────────

  final Map<String, int?> _malIds = {};

  Future<int?> _mal(String animeKey) async {
    if (_malIds.containsKey(animeKey)) return _malIds[animeKey];
    final id = await _malId(animeKey).catchError((_) => null);
    if (id != null && id > 0) _malIds[animeKey] = id;
    return id;
  }

  static Future<int?> _hikkaMalId(String animeKey) => HikkaApi.instance.malIdOf(animeKey);

  /// The times of [r]: AniSkip's, and Anime Skip's where AniSkip has nothing that fits (`withFallback`); null — unknown
  /// numbering, no MAL id, or neither base could be reached with nothing remembered. And what both had, for the log
  Future<(List<AniSkipTime>?, String)> _timesOf(SkipRequest r) async {
    final n = r.number;
    if (n == null) return (null, 'AniSkip: номер серії невідомий');
    final mal = await _mal(r.animeKey);
    if (mal == null) return (null, 'AniSkip: нема MAL id');
    final (a, b) = await (_aniskip.candidates(mal, n, r.duration), _animeSkip.times(mal, n)).wait;
    String said(List<AniSkipTime>? t) => t == null ? 'недоступний' : describeTimes(t, r.duration);
    final what = 'AniSkip $mal/$n: ${said(a)}; Anime Skip: ${said(b)}';
    return (a == null && b == null ? null : withFallback(a ?? const [], b ?? const [], r.duration), what);
  }

  Future<List<AniSkipTime>?> _times(SkipRequest r) async => (await _timesOf(r)).$1;

  /// The plan for [r] without the site's times: what listening found in this very episode, AniSkip's times moved by
  /// what is known of the dub, the dub's intro
  Future<SkipPlan?> planFor(SkipRequest r) async => (await _plan(r)).$1;

  /// [planFor] and, for the log, what AniSkip had and what came of it
  Future<(SkipPlan?, String)> _plan(SkipRequest r) async {
    final (fetched, asked) = await _timesOf(r);
    final times = fetched ?? const <AniSkipTime>[];
    final heard = _profiles.episode(r.animeKey, r.group, r.epKey);
    var known = _profiles.shiftFor(r.animeKey, r.group);
    final hint = _profiles.teamHint(r.group);
    // A correction by hand outweighs even listening (it may have caught another common stretch: a preview, a recap)
    final byHand = known?.source == 'user';
    final useHeard = heard != null && heard.hasOp && !byHand;
    // The opening heard in this very episode gives its own shift against AniSkip's opening
    if (useHeard) {
      final s = shiftFromOpening(times, r.duration, heard.opStart!, heard.opEnd! - heard.opStart!, expected: hint ?? 0);
      if (s != null) known = StartShift.exact(s.$1, 'audio');
    }
    final aligned = alignSkips(r.key, times, r.duration, known: known, expected: hint);
    final stamps = <TimeStamp>[...?aligned?.stamps];
    final bases = basesOf(times, r.duration);
    var source = aligned == null ? '' : bases;
    // The opening heard in this episode replaces AniSkip's (exact on this very video; a little inside its edges, so a
    // skip never lands in the episode itself)
    if (useHeard) {
      stamps.removeWhere((s) => s.type == ChapterType.opening || s.type == ChapterType.mixedOp);
      stamps.add(TimeStamp(heard.opStart! + edgeIn, heard.opEnd! - edgeOut, 'Опенінґ', ChapterType.opening));
      source = aligned == null ? 'аналіз звуку' : '$bases + аналіз звуку';
    } else if (aligned != null && known?.source == 'audio') {
      source = '$bases + аналіз звуку';
    }
    // The dub's own intro: exact when heard in this episode; from other episodes only as a button
    final intro = heard?.intro ?? _profiles.introFor(r.animeKey, r.group);
    if (intro != null && intro >= 1.5 && intro < r.duration / 4 && !stamps.any((s) => s.start < intro - 0.5)) {
      stamps.add(TimeStamp(0, intro - edgeOut, 'Заставка', ChapterType.other, heard?.intro != null));
    }
    if (stamps.isEmpty) return (null, '$asked → пропусків нема');
    stamps.sort((a, b) => a.start.compareTo(b.start));
    final plan = SkipPlan(key: r.key, stamps: stamps, shift: aligned?.shift, source: source, extra: aligned?.extra, opBase: aligned?.opBase);
    return (plan, '$asked → ${describePlan(plan)}${source.isEmpty ? '' : ' [$source]'}');
  }

  /// The site gave its own times: compared with AniSkip's opening they tell the dub's start shift (for its episodes
  /// that come without times, on other players too)
  Future<void> _learnFromSite(SkipRequest r) async {
    try {
      final siteOp = r.site.where((s) => s.type == ChapterType.opening || s.type == ChapterType.mixedOp).firstOrNull;
      if (siteOp == null) return;
      final times = await _times(r);
      if (times == null || times.isEmpty) return;
      // The same opening (its length), placed where the lengths allow
      final found = shiftFromOpening(times, r.duration, siteOp.start, siteOp.end - siteOp.start, lengthSlack: 4);
      if (found == null) return;
      final (shift, op) = found;
      // The site's times equal AniSkip's although our video is longer: likely copied, not measured
      final bounds = lengthShift(r.duration, op.episodeLength);
      if (shift.abs() < 0.3 && bounds.max - bounds.min > 3) return;
      _profiles.observe(r.animeKey, r.group, shift, 'site');
    } catch (e) {
      AppLog.d('пропуск', 'зсув із таймкодів сайту не визначено: $e');
    }
  }

  // ── Listening ─────────────────────────────────────────────────────────────

  /// Why [r] is not listened to (for the log; empty: nothing to learn, said nowhere); null — it is
  String? _whyNotListen(SkipRequest r) {
    if (!_listenOn()) return 'вимкнено в налаштуваннях';
    if (_profiles.episode(r.animeKey, r.group, r.epKey)?.hasOp == true) return '';
    // A base marked a version of this very length: its times are exact already
    final plan = current.value;
    if (plan != null && plan.exact && plan.shift?.source == 'length') return '';
    final known = _profiles.shiftFor(r.animeKey, r.group);
    // The dub's shift was already heard (or set by hand), and a base has times: nothing more to learn
    if (known != null && known.exact && (known.source == 'audio' || known.source == 'user') && current.value?.stamps.isNotEmpty == true) return '';
    if (_canFetch(r.video.url)) return null;
    final net = _network();
    return net.allows(wifiOnly: false) ? 'лише через Wi-Fi чи для завантажених серій (зараз ${net.type.isEmpty ? 'лімітна мережа' : net.type})' : 'немає інтернету';
  }

  /// Downloaded files cost nothing; the network only when it is not metered (Wi-Fi)
  bool _canFetch(String url) => !url.startsWith('http') || _network().allows(wifiOnly: true);

  static String _hash(String s) {
    var h = 0xcbf29ce484222325;
    for (final c in s.codeUnits) {
      h ^= c;
      h = (h * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    return h.toUnsigned(64).toRadixString(16);
  }

  String get _dir => _printsDir ?? '${StorageService.appBasePath}${Platform.pathSeparator}skip_prints';

  File _printFile(String animeKey, WatchGroup g, String epKey) => File('$_dir${Platform.pathSeparator}${_hash('$animeKey|${g.id}|$epKey')}.bin');

  Future<AudioPrint?> _storedPrint(String animeKey, WatchGroup g, String epKey) async {
    try {
      final f = _printFile(animeKey, g, epKey);
      if (!await f.exists()) return null;
      return AudioPrint.fromBytes(await f.readAsBytes());
    } catch (_) {
      return null;
    }
  }

  Future<AudioPrint?> _printOf(String animeKey, WatchGroup g, String epKey, Video v) async {
    final stored = await _storedPrint(animeKey, g, epKey);
    if (stored != null) return stored;
    if (!_canFetch(v.url)) return null;
    final pcm = await _decode(v.url, headers: v.headers, start: 0, length: listenLength);
    if (pcm == null) return null;
    final print = await _compute(_printOf_, pcm);
    try {
      final f = _printFile(animeKey, g, epKey);
      await f.parent.create(recursive: true);
      await f.writeAsBytes(print.toBytes());
      await _prune(f.parent);
    } catch (_) {}
    return print;
  }

  /// Keeps the newest [keepPrints] fingerprints
  static Future<void> _prune(Directory dir) async {
    final files = [
      await for (final e in dir.list())
        if (e is File && e.path.endsWith('.bin')) e,
    ];
    if (files.length <= keepPrints) return;
    final dated = [for (final f in files) (f, (await f.stat()).modified)]..sort((a, b) => b.$2.compareTo(a.$2));
    for (final (f, _) in dated.skip(keepPrints)) {
      try {
        await f.delete();
      } catch (_) {}
    }
  }

  static AudioPrint _printOf_(Int16List pcm) => audioPrint(pcm);

  static List<PrintRun> _runsOf(List<AudioPrint> pair) => commonRuns(pair[0], pair[1]);

  /// The episode next to [r] that can be listened to (a downloaded one first, then the next, then the previous)
  Future<(String, AudioPrint)?> _neighbour(SkipRequest r) async {
    final g = r.group;
    final keys = episodeKeysOf(g);
    // Already heard ones nearby first: they cost nothing (far ones may have another opening)
    for (var d = 1; d <= 6; d++) {
      for (final i in [r.index + d, r.index - d]) {
        if (i < 0 || i >= keys.length) continue;
        final p = await _storedPrint(r.animeKey, g, keys[i]);
        if (p != null) return (keys[i], p);
      }
    }
    for (final i in [r.index + 1, r.index - 1, r.index + 2]) {
      if (i < 0 || i >= g.episodes.length || i == r.index) continue;
      if (_req?.key != r.key) return null; // another episode opened meanwhile
      try {
        final v = await _videoOf(g.sourceId, g.episodes[i]);
        if (v == null) continue;
        final p = await _printOf(r.animeKey, g, keys[i], v);
        if (p != null) return (keys[i], p);
      } catch (e) {
        AppLog.d('пропуск', 'сусідня серія для аналізу недоступна: $e');
      }
    }
    return null;
  }

  /// Listens to the first minutes of [r] and of another episode of the dub: their common opening on each timeline, the
  /// dub's intro, and from them the dub's start shift against AniSkip
  Future<void> _listen(SkipRequest r, {Future<(String, AudioPrint)?> Function()? pair}) async {
    if (!_listening.add(r.key)) return;
    // The player's episode: listening stops when another one opens (a download is listened to to the end)
    bool gone() => pair == null && _req?.key != r.key;
    try {
      final mine = await _printOf(r.animeKey, r.group, r.epKey, r.video);
      if (mine == null || gone()) return;
      final other = await (pair ?? () => _neighbour(r))();
      if (other == null) {
        AppLog.i('пропуск', 'аналіз звуку: немає другої серії для порівняння (${r.group.teamLabel})');
        return;
      }
      final runs = await _compute(_runsOf, [mine, other.$2]);
      final times = await _times(r) ?? const <AniSkipTime>[];
      final hint = _profiles.teamHint(r.group) ?? 0;
      final op = versionsOf(times, const [SkipKind.op, SkipKind.mixedOp], r.duration, expected: hint).firstOrNull;
      final heard = listenRuns(runs, opLength: op?.length);
      AppLog.i('пропуск', 'аналіз звуку ${r.group.teamLabel} ${r.epKey}↔${other.$1}: заставка ${heard.intro?.toStringAsFixed(1) ?? '—'} с, опенінґ ${heard.opening ?? '—'}');
      if (heard.opening == null && heard.intro == null) return;
      final o = heard.opening;
      _profiles.saveEpisode(r.animeKey, r.group, r.epKey, EpisodeListen(opStart: o?.aStart, opEnd: o?.aEnd, intro: heard.intro));
      _profiles.saveEpisode(r.animeKey, r.group, other.$1, EpisodeListen(opStart: o?.bStart, opEnd: o?.bEnd, intro: heard.intro));
      if (heard.intro != null) _profiles.setIntro(r.animeKey, r.group, heard.intro!);
      final shift = o == null ? null : shiftFromOpening(times, r.duration, o.aStart, o.length, expected: hint);
      if (shift != null) _profiles.observe(r.animeKey, r.group, shift.$1, 'audio');
      if (_req?.key == r.key) await refresh();
    } catch (e) {
      AppLog.w('пропуск', 'аналіз звуку не вдався: $e');
    } finally {
      _listening.remove(r.key);
    }
  }

  /// A download finished: AniSkip's times for it are fetched now (they are kept for watching offline), and with another
  /// downloaded episode of the dub ([dub]) both are listened to at once (local files cost nothing)
  Future<void> onDownloaded(DownloadItem item, {required Iterable<DownloadItem> dub, required Video? Function(DownloadItem) videoOf}) async {
    try {
      if (item.timestamps.isNotEmpty) return; // the site's own times came with it
      final v = videoOf(item);
      if (v == null) return;
      final n = item.episode.number;
      final number = n != null && n >= 1 && n == n.roundToDouble() && item.episode.season == null ? n.toInt() : null;
      // Only the dub's name and id matter here (what was learned is kept by them)
      final g = WatchGroup(id: item.groupId, sourceId: item.sourceId, label: item.groupLabel, isSub: item.isSub, episodes: const []);
      final r = SkipRequest(animeKey: item.animeKey, group: g, index: -1, epKey: item.epKey, number: number, duration: item.duration, video: v);
      await _times(r);
      if (!_listenOn() || _profiles.episode(item.animeKey, g, item.epKey)?.hasOp == true) return;
      // The nearest other downloaded episode of the dub
      final others = [for (final o in dub) if (o.id != item.id && o.epKey != item.epKey && o.timestamps.isEmpty) o]
        ..sort((a, b) => (a.order - item.order).abs().compareTo((b.order - item.order).abs()));
      for (final o in others) {
        final ov = videoOf(o);
        if (ov == null) continue;
        await _listen(r, pair: () async {
          final p = await _printOf(o.animeKey, g, o.epKey, ov);
          return p == null ? null : (o.epKey, p);
        });
        return;
      }
    } catch (e) {
      AppLog.w('пропуск', 'завантажену серію не розібрано: $e');
    }
  }

  /// The real way to another episode's video: the downloaded copy, else the site (its lowest quality is enough)
  static Future<Video?> _siteVideo(String sourceId, SEpisode e) async {
    final dm = DownloadManager.instance;
    final local = dm.playable(sourceId, e);
    if (local != null) return dm.localVideo(local);
    final source = SourceRegistry.instance.byId(sourceId);
    if (source == null) return null;
    final res = await StreamResolver(maxHeight: () => 480, preferredHoster: () => SourcePrefs.instance.hoster).resolve(source, e);
    return res.video;
  }
}
