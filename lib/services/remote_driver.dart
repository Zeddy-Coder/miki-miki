/// Site episode driver: takes the link to the needed episode, opens it in the player, remembers the position,
/// marks "watched", moves to the next episode, switches dubs, players and quality, and helps when a video
/// does not start. Knows nothing about media_kit and widgets: the player is a [RemoteEngine], so everything is testable.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/media_models.dart';
import '../models/source_models.dart';
import 'app_log.dart';
import 'episode_check.dart';
import 'hikka_lists.dart';
import 'lang_match.dart';
import 'remote_playback.dart';
import 'skips/skip_align.dart';
import 'skips/skip_service.dart';
import 'songs/song_service.dart';
import 'source_registry.dart';
import 'sources/source_http.dart';
import 'sources/hls_proxy.dart';
import 'sources/source_log.dart';
import 'storage_service.dart';
import 'stream_resolver.dart';
import 'watch_marks.dart';
import 'watch_models.dart';
import 'watch_store.dart';

/// What the driver needs from the player
abstract class RemoteEngine {
  /// Opens a direct video (the previous playback is cancelled); [start] is where to begin
  Future<void> openVideo(Video video, {Duration? start});

  Duration get position;
  Duration get duration;

  /// The video is currently playing (not paused)
  bool get playing;

  /// Adds an external subtitle; [select] shows it right away
  Future<void> addSubtitle(Track track, {required bool select});

  /// Adds an external audio track (e.g. a dub as a separate file)
  Future<void> addAudio(Track track, {required bool select});
}

/// Episode playback state
/// The episode ended and there is no next one in this dub, though other dubs have it: what to offer the viewer
class NextOffer {
  /// Number of the needed episode
  final int next;

  /// Name of the dub that has no next episode
  final String from;

  /// First dub by priority that has the next episode
  final WatchGroup byPriority;

  /// Full dub with the next episode, if it differs from [byPriority]
  final WatchGroup? full;

  const NextOffer({required this.next, required this.from, required this.byPriority, this.full});
}

enum RemotePhase {
  /// No session
  idle,

  /// Looking for a direct video link
  resolving,

  /// The link was passed to the player, waiting for the video to start
  opening,

  /// The video is playing
  playing,

  /// Failed (there is [RemoteDriver.error])
  failed,
}

class RemoteDriver extends ChangeNotifier {
  final RemoteEngine engine;
  final SourceRegistry registry;
  final StreamResolver resolver;
  final WatchStore store;

  /// Whether to move to the next episode when this one ends
  final bool Function() autoNext;

  final int Function(String key) _readPosition;
  final void Function(String key, int positionMs, int durationMs) _writePosition;
  final DateTime Function() _now;

  /// Subtitle language priority from settings: of several external tracks the highest by it is turned on
  final List<String> Function() _subPriorities;

  /// How long to wait for the video to start before trying another player
  final Duration openTimeout;

  /// How long to wait after a player error (errors can be minor: the video may still go)
  final Duration errorGrace;

  RemoteDriver({
    required this.engine,
    required this.registry,
    required this.resolver,
    WatchStore? store,
    bool Function()? autoNext,
    int Function(String key)? readPosition,
    void Function(String key, int positionMs, int durationMs)? writePosition,
    DateTime Function()? now,
    List<String> Function()? subPriorities,
    this.openTimeout = const Duration(seconds: 30),
    this.errorGrace = const Duration(seconds: 6),
    this.skips,
    this.songs,
  }) : store = store ?? WatchStore.instance,
       autoNext = autoNext ?? (() => StorageService.getAutoplayNext()),
       _subPriorities = subPriorities ?? (() => StorageService.getSubLangPriorities()),
       _readPosition = readPosition ?? StorageService.getPlaybackPosition,
       _writePosition = writePosition ?? StorageService.savePlaybackPosition,
       _now = now ?? DateTime.now {
    skips?.current.addListener(_onPlan);
    // The songs come after the start: the menu and the chapters show them
    songs?.current.addListener(_changed);
  }

  /// Skips for episodes the site gave no times for (AniSkip, listening); null: only the site's own times
  final SkipService? skips;

  /// The songs of the episode's opening and ending (the card over the video, «Пісня» in the menu); null: none
  final SongService? songs;

  // ── Callbacks to the player controller ────────────────────────────────────────

  /// The current episode changed (title, position key)
  void Function(int index)? onEntry;

  /// The queue changed (another dub was chosen)
  VoidCallback? onSession;

  /// A short message for the screen ("Наступна серія", "Це остання серія")
  void Function(String text, {bool error})? onMessage;

  /// The episode was watched to the end (marked by itself, not by hand): smart downloads go on from it
  void Function(String animeKey, RemoteEntry entry)? onWatched;

  /// Set by the open "Перегляд" panel: a step back inside it (from an episode's details or an inner page to the list);
  /// false — it is at its list already. The system Back and Esc ask it before closing the panel
  bool Function()? panelBack;

  // ── State ────────────────────────────────────────────────────────────────────

  RemoteSession? _session;
  NextOffer? _offer;
  WatchTitle? _title;
  HikkaEpisodeInfo? _hikka;
  String _groupId = '';
  int _index = 0;
  RemotePhase _phase = RemotePhase.idle;
  String? _error;
  ResolvedStream? _stream;
  Video? _video;
  List<VideoChapter> _chapters = const [];

  /// The times behind [_chapters]: the site's, or the skip plan's (AniSkip, listening)
  List<TimeStamp> _stamps = const [];

  RemoteSession? get session => _session;

  /// All watch variants of the anime (for switching dubs); `null` if launched without them
  WatchTitle? get title => _title;

  String get groupId => _groupId;

  int get index => _index;

  RemotePhase get phase => _phase;

  /// Failure message for the user (in the [RemotePhase.failed] phase)
  String? get error => _error;

  /// The direct video being played and all its quality variants / players
  ResolvedStream? get stream => _stream;

  Video? get video => _video;

  /// Chapters from the site's timestamps or the skip plan (opening, ending …)
  List<VideoChapter> get chapters => _chapters;

  /// The skip plan of the episode playing now (where its times come from, their shift); null: none
  SkipPlan? get skipPlan {
    final p = skips?.current.value;
    return p != null && p.key == _planKey ? p : null;
  }

  /// Moves the AniSkip times of this dub by [delta] seconds (every episode of it)
  Future<void> shiftSkips(double delta) async => skips?.shiftBy(delta);

  /// The viewer marked where this episode's opening starts: AniSkip's times of the dub move to fit
  Future<void> skipOpeningAt(Duration position) async => skips?.openingAt(position.inMilliseconds / 1000);

  /// Forgets the hand correction of the times
  Future<void> resetSkipShift() async => skips?.resetShift();

  bool get active => _session != null;

  /// The episode is still being prepared or failed to start: the player shows a state screen instead of the video
  bool get showsStatus => _session != null && (_offer != null || _phase == RemotePhase.resolving || _phase == RemotePhase.opening || _phase == RemotePhase.failed);

  /// An offer to switch to another dub when this one has no next episode
  NextOffer? get offer => _offer;

  void dismissOffer() {
    if (_offer == null) return;
    _offer = null;
    _changed();
  }

  /// Accept the offer: open the needed episode in dub [g]
  Future<void> acceptOffer(WatchGroup g) async {
    final o = _offer;
    _offer = null;
    await switchGroup(g, episode: o?.next);
  }

  /// Another player of this episode worth trying after the current one (in a cycle); `null` if there is no choice
  String? get alternativeHoster {
    final list = _stream?.hosters ?? const <String>[];
    if (list.length < 2) return null;
    final i = list.indexWhere((h) => h.toLowerCase() == hoster.toLowerCase());
    return list[(i + 1) % list.length];
  }

  RemoteEntry? get entry => _session == null || _index >= _session!.entries.length ? null : _session!.entries[_index];

  bool get hasNext => _session != null && _index + 1 < _session!.entries.length;

  bool get hasPrevious => _session != null && _index > 0;

  /// Everything that can be shown to the user about the current variant
  WatchGroup? get group => _title?.groupById(_groupId);

  /// Subtitles, not dubbing
  bool get isSub => group?.isSub ?? false;

  String get hoster => _stream?.hoster ?? '';

  /// What is playing now on one line: "Озвучення: Amanogawa · Moon · 1080p" (without the label if [withKind] = false)
  String nowPlaying({bool withKind = true}) {
    final g = group;
    final q = _video?.title ?? '';
    return [if (g != null) (withKind ? g.fullLabel : g.label), if (hoster.isNotEmpty) hoster, if (q.isNotEmpty) q].join(' · ');
  }

  /// Attempt number (1 is the first player), for the "Пробую інший плеєр" label
  int get attempt => _tried.length;

  int _token = 0;
  Timer? _watchdog;
  Timer? _stallCheck;
  bool _marked = false;
  bool _disposed = false;
  DateTime _openedAt = DateTime.fromMillisecondsSinceEpoch(0);
  Duration _openStart = Duration.zero;
  DateTime? _lastRecover;
  final Set<String> _tried = {};
  String? _stickyHoster;
  int? _stickyHeight;

  // ── Launch and navigation ──────────────────────────────────────────────────────

  /// Reconciliation of the variant's episodes with Hikka (for warnings in the dub list). Without Hikka data, numbering check only.
  /// What Hikka knows about the episodes (released / total): "28 з 28 серій" under the dub in the player's panel
  HikkaEpisodeInfo? get hikka => _hikka;

  EpisodeCheck checkOf(WatchGroup g) => checkGroup(g, _hikka ?? const HikkaEpisodeInfo(), all: _title?.groups ?? const []);

  /// Starts watching: the queue is all episodes of the chosen dub, the starting one opens
  Future<void> start(RemoteLaunch launch) async {
    _savePosition();
    _offer = null;
    _session = launch.session;
    _title = launch.title;
    _hikka = launch.hikka;
    _groupId = launch.group.id;
    _stickyHoster = null;
    _stickyHeight = null;
    store.setPreferredGroup(launch.title.animeKey, launch.group.id);
    onSession?.call();
    await open(launch.startIndex, saveCurrent: false);
  }

  /// Opens episode [i] of the current queue. [startAt] is where to start (otherwise from the saved place, and if there is none, from the start).
  Future<void> open(int i, {String? hoster, int? height, Duration? startAt, bool saveCurrent = true}) async {
    final s = _session;
    if (s == null || i < 0 || i >= s.entries.length) return;
    if (saveCurrent) _savePosition();
    final token = ++_token;
    _cancelTimers();
    _index = i;
    _error = null;
    _stream = null;
    _video = null;
    _chapters = const [];
    _stamps = const [];
    skips?.detach();
    songs?.detach();
    _marked = false;
    _offer = null;
    _tried.clear();
    _phase = RemotePhase.resolving;
    final e = s.entries[i];
    store.setLast(s.animeKey, e.epKey, e.groupId);
    onEntry?.call(i);
    _changed();
    await _resolveAndPlay(token, e, hoster: hoster ?? _stickyHoster, height: height ?? _stickyHeight, startAt: startAt);
  }

  Future<bool> next({bool save = true}) async {
    if (!hasNext) return false;
    await open(_index + 1, saveCurrent: save);
    return true;
  }

  Future<bool> previous() async {
    if (!hasPrevious) return false;
    await open(_index - 1);
    return true;
  }

  /// Try again (after a failure): with the same position, without remembered failed players
  Future<void> retry() async {
    if (!active) return;
    final at = engine.position > const Duration(seconds: 5) ? engine.position : null;
    await open(_index, startAt: at ?? _fallbackStart(), saveCurrent: false);
  }

  Duration? _fallbackStart() => _openStart > const Duration(seconds: 5) ? _openStart : null;

  /// The next episode exists in other dubs but not in this one: which dub to offer (by priority and full)
  NextOffer? _offerFor(RemoteEntry e) {
    final t = _title;
    final n = e.episode.number;
    final cur = group;
    if (t == null || n == null || n != n.roundToDouble()) return null;
    final next = n.round() + 1;
    var pool = [for (final g in t.groups) if (g.id != _groupId && g.hasEpisode(next)) g];
    if (cur != null && pool.any((g) => g.isSub == cur.isSub)) pool = [for (final g in pool) if (g.isSub == cur.isSub) g];
    if (pool.isEmpty) return null;
    WatchGroup pick(List<WatchGroup> from) => pickGroup(
          from,
          favorites: store.favoriteChoices,
          priority: StorageService.getWatchTeamPriority(),
          safe: (g) => checkOf(g).syncSafe,
        );
    final byPriority = pick(pool);
    final maxLast = maxEpisodeOf(t.groups, limit: t.episodeLimit);
    final fullPool = [for (final g in pool) if (!g.isIncomplete(maxLast)) g];
    final full = fullPool.isEmpty ? null : pick(fullPool);
    return NextOffer(next: next, from: cur?.label ?? '', byPriority: byPriority, full: full == null || full.id == byPriority.id ? null : full);
  }

  /// Where to go when the current episode is not in the new variant: the first not-yet-watched episode after it (by
  /// number); if there is none, the variant's last episode; without a number, the first unwatched one
  int _nearestIndex(RemoteSession ns, RemoteEntry cur, String animeKey) {
    final entries = ns.entries;
    final seen = store.watched(animeKey);
    final hikka = _hikkaSeen(animeKey);
    bool done(RemoteEntry e) => seen.contains(e.epKey) || (e.episode.number != null && e.episode.number! <= hikka);
    final n = cur.episode.number;
    if (n == null) {
      final i = entries.indexWhere((e) => !done(e));
      return i < 0 ? 0 : i;
    }
    final after = entries.indexWhere((e) => (e.episode.number ?? 0) > n && !done(e));
    return after >= 0 ? after : entries.length - 1;
  }

  /// How many episodes are already marked on Hikka (from memory; 0 when signed out)
  int _hikkaSeen(String animeKey) {
    const prefix = 'hikka:';
    if (!animeKey.startsWith(prefix)) return 0;
    return HikkaMyList.instance.cached(animeKey.substring(prefix.length))?.episodes ?? 0;
  }

  /// Switches dub / subtitles. The same episode (by number) opens from the same place; if the new variant
  /// does not have it, the first unwatched one from the start (previously the number was taken by position, which threw you to the end of the title).
  /// [episode]: open the episode with this number
  Future<void> switchGroup(WatchGroup g, {int? episode}) async {
    final s = _session;
    final t = _title;
    final cur = entry;
    if (s == null || t == null || cur == null || g.id == _groupId || g.episodes.isEmpty) return;
    final at = engine.position;
    _savePosition();
    final ns = RemoteSession.fromGroup(animeKey: s.animeKey, animeTitle: s.animeTitle, group: g, poster: s.poster);
    var ni = episode != null ? ns.entries.indexWhere((x) => x.episode.number == episode.toDouble()) : ns.indexOfKey(cur.epKey);
    final sameEpisode = ni >= 0 && episode == null;
    if (ni < 0) ni = _nearestIndex(ns, cur, s.animeKey);
    _session = ns;
    _groupId = g.id;
    _offer = null;
    _stickyHoster = null;
    // A deliberate choice: remembered for this title and becomes the default for new ones (see `pickGroup`)
    store.setPreferredGroup(s.animeKey, g.id);
    store.setPinnedGroup(s.animeKey, g.id);
    store.setFavoriteChoice(choiceKeyOf(g));
    onSession?.call();
    if (!sameEpisode) onMessage?.call('Відкрито: ${ns.entries[ni].title}');
    await open(ni, startAt: sameEpisode && at > const Duration(seconds: 5) ? at : null, saveCurrent: false);
  }

  /// Manually chosen player (Moon, Ashdi …): also applies to the next episodes of this session
  Future<void> switchHoster(String name) async {
    if (!active || name.isEmpty || name == hoster) return;
    _stickyHoster = name;
    final at = engine.position;
    await open(_index, hoster: name, startAt: at > const Duration(seconds: 5) ? at : _fallbackStart());
  }

  /// Another quality of the same player: the link is already known, no new lookup
  Future<void> switchQuality(Video v) async {
    final res = _stream;
    if (!active || res == null || _phase == RemotePhase.resolving || v.url == _video?.url) return;
    _stickyHeight = v.resolution; // "Авто" (no height) restores the default setting
    final at = engine.position;
    final token = ++_token;
    _cancelTimers();
    await _launch(token, res, v, at > const Duration(seconds: 5) ? at : null);
  }

  // ── Player events ────────────────────────────────────────────────────────────

  /// The player learned the duration: the video has really started
  void onDuration(Duration d) {
    if (!active || d <= Duration.zero || _phase != RemotePhase.opening) return;
    final v = _video;
    _watchdog?.cancel();
    _phase = RemotePhase.playing;
    _stamps = v?.timestamps ?? const [];
    _chapters = chaptersFromTimestamps(_stamps, d);
    _changed();
    final token = _token;
    if (v != null) unawaited(_applyExtras(token, v));
    final sk = skips, so = songs, e = entry, g = group, s = _session;
    if (e == null || s == null) return;
    final (number, why) = g == null ? (null, '') : _numberOf(e, checkOf(g));
    if (number == null && g != null && (sk != null || so != null)) AppLog.i('пропуск', '${g.teamLabel} · ${e.epKey}: номер для AniSkip невідомий — $why');
    if (sk != null && v != null && g != null) {
      unawaited(sk.attach(SkipRequest(animeKey: s.animeKey, group: g, index: _index, epKey: e.epKey, number: number, duration: d.inMilliseconds / 1000, video: v)));
    }
    if (so != null) unawaited(so.attach(animeKey: s.animeKey, epKey: e.epKey, number: number));
  }

  String get _planKey {
    final s = _session, e = entry;
    return s == null || e == null ? '' : '${s.animeKey}#$_groupId#${e.epKey}';
  }

  /// A new or better skip plan for the episode playing now
  void _onPlan() {
    final plan = skips?.current.value;
    final total = engine.duration;
    if (plan == null || !active || _phase != RemotePhase.playing || plan.key != _planKey || total <= Duration.zero) return;
    _stamps = plan.stamps;
    _chapters = chaptersFromTimestamps(plan.stamps, total);
    _changed();
  }

  /// AniSkip's number of [e] (MyAnimeList's numbering) by its dub's check [c]: whole numbers of a dub whose numbers
  /// still name Hikka's episodes (`EpisodeCheck.numbersHold`: a gap such as Gintama's 1, 3, 4… is fine); null when they
  /// may not (merged parts, seasons in one list, extras after the last episode), with why (for the log)
  (int?, String) _numberOf(RemoteEntry e, EpisodeCheck c) {
    final n = e.episode.number;
    if (n == null) return (null, 'серія без номера');
    if (n < 1 || n != n.roundToDouble()) return (null, 'номер $n');
    if (e.episode.season != null) return (null, 'у списку джерела є сезон ${e.episode.season}');
    if (!c.numbersHold) return (null, 'нумерація джерела не збігається з Hikka (${c.summary})');
    final limit = c.syncLimit;
    if (limit != null && n > limit) return (null, 'після останньої серії Hikka ($limit)');
    return (n.toInt(), '');
  }

  (RemoteSession, WatchGroup, HikkaEpisodeInfo?)? _numbersFor;
  List<int?> _numbers = const [];

  /// MyAnimeList's numbers of the queue's episodes by the AniSkip rule (null where a dub's number may name another
  /// episode): the titles of the episode list go by them
  List<int?> get malNumbers {
    final s = _session, g = group;
    if (s == null || g == null) return const [];
    final f = _numbersFor;
    if (f != null && identical(f.$1, s) && identical(f.$2, g) && identical(f.$3, _hikka)) return _numbers;
    final c = checkOf(g);
    _numbers = [for (final e in s.entries) _numberOf(e, c).$1];
    _numbersFor = (s, g, _hikka);
    return _numbers;
  }

  /// Every few seconds while an episode plays (the list's progress of it follows without rebuilding the whole panel)
  final ValueNotifier<int> progress = ValueNotifier<int>(0);

  /// Every few seconds: saves the position and marks the episode watched
  void tick() {
    if (!active || _phase != RemotePhase.playing) return;
    progress.value++;
    _savePosition();
    final e = entry;
    if (!_marked && e != null && episodeSeen(engine.position, engine.duration, _stamps, fraction: StorageService.getWatchedPercent() / 100, byEnding: StorageService.getWatchedByEnding())) {
      _markWatched(e);
    }
  }

  /// The episode played to the end
  Future<void> onCompleted() async {
    final e = entry;
    if (!active || e == null || _phase != RemotePhase.playing) return;
    // The video ended a moment after starting from the middle: the saved position did not suit this dub, so we start over
    if (_openStart > Duration.zero && _now().difference(_openedAt) < const Duration(seconds: 6)) {
      _openStart = Duration.zero;
      final token = ++_token;
      final res = _stream, v = _video;
      if (res != null && v != null) await _launch(token, res, v, Duration.zero);
      return;
    }
    if (!_marked) _markWatched(e);
    final dur = engine.duration.inMilliseconds;
    if (dur > 0) _writePosition(e.key, dur, dur); // watch from the beginning, not from the end
    if (!hasNext) {
      final o = _offerFor(e);
      if (o != null) {
        _offer = o;
        _changed();
      } else {
        onMessage?.call('Це остання серія');
      }
      return;
    }
    if (autoNext()) {
      onMessage?.call('Наступна серія');
      await next(save: false); // the episode summary was already recorded above
    }
  }

  /// Player error: before the video starts, we try another player; during watching, we check whether the stream froze
  void onPlayerError(String text) {
    if (!active) return;
    final token = _token;
    if (_phase == RemotePhase.opening) {
      _armWatchdog(token, errorGrace, text);
    } else if (_phase == RemotePhase.playing) {
      final at = engine.position;
      _stallCheck?.cancel();
      _stallCheck = Timer(errorGrace, () {
        if (token != _token || _phase != RemotePhase.playing || !engine.playing) return;
        if ((engine.position - at).inMilliseconds.abs() > 500) return; // the video is going: the error was minor
        unawaited(_recover());
      });
    }
  }

  /// The stream may have gone stale (links live a couple of hours): take a new one and continue from the same place
  Future<void> _recover() async {
    final now = _now();
    final last = _lastRecover;
    if (last != null && now.difference(last) < const Duration(seconds: 30)) return;
    _lastRecover = now;
    final at = engine.position;
    onMessage?.call('Оновлюю посилання на відео…');
    await open(_index, hoster: _stream?.hoster, startAt: at > const Duration(seconds: 5) ? at : null, saveCurrent: false);
  }

  /// Stops the session (the player was closed or another file was opened)
  void stop({bool save = true}) {
    if (!active) return;
    if (save) _savePosition();
    _token++;
    _cancelTimers();
    _session = null;
    _offer = null;
    _title = null;
    _stream = null;
    _video = null;
    _chapters = const [];
    _stamps = const [];
    skips?.detach();
    songs?.detach();
    _error = null;
    _phase = RemotePhase.idle;
    _changed();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelTimers();
    skips?.current.removeListener(_onPlan);
    songs?.current.removeListener(_changed);
    progress.dispose();
    super.dispose();
  }

  // ── Internal ───────────────────────────────────────────────────────────────

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void _cancelTimers() {
    _watchdog?.cancel();
    _stallCheck?.cancel();
    _blockedSub?.cancel();
    _blockedSub = null;
  }

  StreamSubscription<int>? _blockedSub;

  /// The local proxy reports that the server rejects segments: waiting 30 s is pointless, we try another player right away
  void _watchBlocked(int token) {
    _blockedSub?.cancel();
    final baseline = HlsProxy.instance.blockedCount;
    _blockedSub = HlsProxy.instance.blocked.listen((n) {
      if (token != _token || _phase != RemotePhase.opening || n - baseline < 3) return;
      _blockedSub?.cancel();
      unawaited(_failOver(token, 'Сервер відхиляє сегменти відео'));
    });
  }

  void _markWatched(RemoteEntry e) {
    _marked = true;
    final s = _session!;
    store.setWatched(s.animeKey, e.epKey, true);
    _syncToHikka(s, e);
    onWatched?.call(s.animeKey, e);
    _changed(); // a "watched" mark appears in the episode panel
  }

  /// Sends progress to Hikka lists: only for titles from the Hikka catalog, only when signed in, and quietly
  void _syncToHikka(RemoteSession s, RemoteEntry e) {
    final total = _hikka?.total;
    final n = WatchMarks.hikkaNumber(number: e.episode.number, position: s.entries.indexOf(e) + 1, allNumbers: s.entries.map((x) => x.episode.number), total: total);
    WatchMarks.syncToHikka(s.animeKey, n, total: total);
  }

  /// Long press on an episode in the list: sets or clears the "watched" mark (on Hikka too)
  void toggleWatched(int i) {
    final s = _session;
    if (s == null || i < 0 || i >= s.entries.length) return;
    final e = s.entries[i];
    final value = !store.isWatched(s.animeKey, e.epKey);
    final total = _hikka?.total;
    final n = WatchMarks.hikkaNumber(number: e.episode.number, position: i + 1, allNumbers: s.entries.map((x) => x.episode.number), total: total);
    WatchMarks.set(store, s.animeKey, e.epKey, value, hikkaEpisode: n, total: total);
    if (i == _index) _marked = true; // do not mark the current episode again automatically
    onMessage?.call(value ? 'Позначено переглянутою' : 'Позначку знято');
    _changed();
  }

  void _savePosition() {
    final e = entry;
    if (e == null || _phase != RemotePhase.playing) return;
    final dur = engine.duration;
    if (dur <= Duration.zero) return;
    _writePosition(e.key, engine.position.inMilliseconds, dur.inMilliseconds);
  }

  Duration? _resumePoint(RemoteEntry e) {
    final ms = _readPosition(e.key);
    return ms > 5000 ? Duration(milliseconds: ms) : null;
  }

  Future<void> _resolveAndPlay(int token, RemoteEntry e, {String? hoster, int? height, Duration? startAt}) async {
    try {
      final source = registry.byId(e.sourceId);
      if (source == null) {
        _fail(token, 'Джерело «${e.sourceId}» не знайдено. Оновіть застосунок або відкрийте серію з іншого джерела.');
        return;
      }
      final res = await resolver.resolve(source, e.episode, hoster: hoster, height: height);
      if (token != _token) return; // another episode was chosen in the meantime
      if (_tried.contains(res.hoster.toLowerCase())) {
        _fail(token, 'Жоден із плеєрів не запустив це відео');
        return;
      }
      await _launch(token, res, res.video, startAt ?? _resumePoint(e));
    } on SourceException catch (ex) {
      _fail(token, ex.message);
    } catch (ex) {
      _fail(token, 'Не вдалося відкрити серію: $ex');
    }
  }

  /// Hands the video to the player and waits for it to start
  Future<void> _launch(int token, ResolvedStream res, Video v, Duration? start) async {
    if (token != _token) return;
    _stream = res;
    _video = v;
    _tried.add(res.hoster.toLowerCase());
    SourceLog.add('Відкриваю в плеєрі (${res.hoster}): ${v.url}; заголовки: ${v.headers.keys.isEmpty ? 'нема' : v.headers.keys.join(', ')}; з ${start ?? Duration.zero}');
    _openStart = start ?? Duration.zero;
    _openedAt = _now();
    _chapters = const [];
    _phase = RemotePhase.opening;
    _error = null;
    _armWatchdog(token, openTimeout, 'Відео довго не запускається');
    _watchBlocked(token);
    _changed();
    try {
      await engine.openVideo(v, start: start);
    } catch (ex) {
      if (token == _token) await _failOver(token, 'Плеєр не прийняв відео: $ex');
    }
  }

  void _armWatchdog(int token, Duration after, String reason) {
    _watchdog?.cancel();
    _watchdog = Timer(after, () {
      if (token != _token || _phase != RemotePhase.opening) return;
      SourceLog.add('Таймер відкриття спрацював: $reason (${after.inSeconds} с)');
      unawaited(_failOver(token, reason));
    });
  }

  /// The video did not start: we try the episode's next player, and when there are no more we report the failure
  Future<void> _failOver(int token, String reason) async {
    if (token != _token) return;
    SourceLog.add('Збій відкриття: $reason');
    final res = _stream;
    final e = entry;
    if (res != null && e != null) {
      String? other;
      for (final h in res.hosters) {
        if (!_tried.contains(h.toLowerCase())) {
          other = h;
          break;
        }
      }
      if (other != null) {
        onMessage?.call('Плеєр ${res.hoster} не відповідає, пробую $other', error: true);
        final next = ++_token;
        _cancelTimers();
        _phase = RemotePhase.resolving;
        _stream = null;
        _video = null;
        _changed();
        await _resolveAndPlay(next, e, hoster: other, height: _stickyHeight, startAt: _fallbackStart());
        return;
      }
    }
    _fail(token, '$reason. Спробуйте іншу озвучку чи плеєр або повторіть пізніше.');
  }

  void _fail(int token, String message) {
    if (token != _token) return;
    SourceLog.add('ПОМИЛКА: $message');
    _cancelTimers();
    _phase = RemotePhase.failed;
    _error = message;
    _changed();
  }

  /// External tracks (subtitles, a separate dub) are added once the video has loaded
  Future<void> _applyExtras(int token, Video v) async {
    try {
      final subs = v.subtitleTracks;
      // Subtitles were chosen deliberately (the "Субтитри" variant): turn on the track by the language from settings, not just the first one
      final pick = subs.isEmpty ? 0 : LangMatch.pickByLabel([for (final t in subs) t.lang], _subPriorities());
      for (int i = 0; i < subs.length; i++) {
        if (token != _token) return;
        await engine.addSubtitle(subs[i], select: isSub && i == pick);
      }
      final audios = v.audioTracks;
      for (int i = 0; i < audios.length; i++) {
        if (token != _token) return;
        await engine.addAudio(audios[i], select: i == 0);
      }
    } catch (ex) {
      debugPrint('[Remote] зовнішні доріжки: $ex');
    }
  }
}
