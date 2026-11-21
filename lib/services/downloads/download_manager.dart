/// Episode downloads: the queue, where the files go, when the network lets them go, and what is on the device.
///
/// One episode downloads at a time (its segments in parallel lanes, [DownloadWorker]); the rest wait in order.
/// Nothing is downloaded without internet or, with «Лише через Wi-Fi», over mobile data: such episodes just wait
/// ([DownloadManager.waitReason]) and go on by themselves, from where they stopped, when the network allows. The index
/// lies in `<app data>/downloads.json`; the files under [DownloadManager.root] (Android: the app's private folder,
/// Windows: `Videos\Miki Miki`), one folder per episode: `<title>/<dub>/<episode>`.
///
/// A downloaded episode is not a separate thing to manage: the player takes it instead of the site by itself
/// ([DownloadAwareResolver]), the "watched" marks and positions are the same, and after a downloaded episode is watched
/// the next one can download by itself ([DownloadPrefs.autoNext]) and the watched one go ([DownloadPrefs.deleteWatched]).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../constants/app_identity.dart';
import '../../models/source_models.dart';
import '../app_log.dart';
import '../episode_check.dart' show HikkaEpisodeInfo;
import '../network_status.dart';
import '../remote_playback.dart';
import '../source_prefs.dart';
import '../source_registry.dart';
import '../sources/source_http.dart';
import '../storage_service.dart';
import '../stream_resolver.dart';
import '../system_controls.dart';
import '../watch_models.dart';
import 'download_models.dart';
import 'download_worker.dart';

/// How downloads behave (the «Завантаження» settings)
class DownloadPrefs {
  /// Mobile data is not spent: downloads wait for Wi-Fi (or any unmetered network)
  final bool wifiOnly;

  /// The wanted frame height (0: the same as for watching, «Якість» of the sources)
  final int height;

  /// After a downloaded episode is watched, the next one downloads by itself
  final bool autoNext;

  /// A watched downloaded episode is deleted (once another one opens)
  final bool deleteWatched;

  /// The folder for new downloads ('' — the default one, [DownloadManager.defaultRoot])
  final String folder;

  const DownloadPrefs({this.wifiOnly = true, this.height = 0, this.autoNext = true, this.deleteWatched = false, this.folder = ''});

  DownloadPrefs copyWith({bool? wifiOnly, int? height, bool? autoNext, bool? deleteWatched, String? folder}) => DownloadPrefs(
        wifiOnly: wifiOnly ?? this.wifiOnly,
        height: height ?? this.height,
        autoNext: autoNext ?? this.autoNext,
        deleteWatched: deleteWatched ?? this.deleteWatched,
        folder: folder ?? this.folder,
      );

  Map<String, dynamic> toJson() => {
        'wifiOnly': wifiOnly,
        'height': height,
        'autoNext': autoNext,
        'deleteWatched': deleteWatched,
        if (folder.isNotEmpty) 'folder': folder,
      };

  static DownloadPrefs fromJson(Map<String, dynamic> j) => DownloadPrefs(
        wifiOnly: j['wifiOnly'] as bool? ?? true,
        height: (j['height'] as num?)?.toInt() ?? 0,
        autoNext: j['autoNext'] as bool? ?? true,
        deleteWatched: j['deleteWatched'] as bool? ?? false,
        folder: j['folder'] as String? ?? '',
      );
}

/// The dub an episode was downloaded from, as it was then: plays offline with all its episodes (the ones not on the
/// device go online), and smart downloads know which episode comes next
class DownloadGroup {
  final String animeKey;
  final String animeTitle;
  final String? poster;
  final String id;
  final String sourceId;
  final String label;
  final bool isSub;
  final List<SEpisode> episodes;
  final HikkaEpisodeInfo? hikka;

  /// The dub's folder (absolute); the episodes lie in its subfolders
  final String folder;

  const DownloadGroup({
    required this.animeKey,
    required this.animeTitle,
    this.poster,
    required this.id,
    required this.sourceId,
    required this.label,
    this.isSub = false,
    required this.episodes,
    this.hikka,
    required this.folder,
  });

  static String keyOf(String animeKey, String groupId) => '$animeKey\u0000$groupId';

  String get key => keyOf(animeKey, id);

  WatchGroup get watchGroup => WatchGroup(id: id, sourceId: sourceId, label: label, episodes: episodes, isSub: isSub);

  List<String> get keys => episodeKeysOf(watchGroup);

  Map<String, Object?> toJson() => {
        'anime': animeKey,
        'animeTitle': animeTitle,
        if (poster != null) 'poster': poster,
        'id': id,
        'source': sourceId,
        'label': label,
        if (isSub) 'sub': true,
        'episodes': [for (final e in episodes) e.toJson()],
        if (hikka != null) 'hikka': {'r': hikka!.released, 't': hikka!.total, 'f': hikka!.finished},
        'folder': folder,
      };

  static DownloadGroup? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final j = raw.cast<String, dynamic>();
    if (j['anime'] is! String || j['id'] is! String || j['folder'] is! String) return null;
    final h = j['hikka'];
    return DownloadGroup(
      animeKey: j['anime'] as String,
      animeTitle: '${j['animeTitle'] ?? ''}',
      poster: j['poster'] as String?,
      id: j['id'] as String,
      sourceId: '${j['source'] ?? ''}',
      label: '${j['label'] ?? ''}',
      isSub: j['sub'] == true,
      episodes: [
        for (final e in (j['episodes'] as List?) ?? const [])
          if (e is Map) SEpisode.fromJson(e.cast<String, dynamic>()),
      ],
      hikka: h is Map ? HikkaEpisodeInfo(released: (h['r'] as num?)?.toInt(), total: (h['t'] as num?)?.toInt(), finished: h['f'] == true) : null,
      folder: j['folder'] as String,
    );
  }
}

class _Job {
  final String id;
  final DownloadCancel cancel = DownloadCancel();
  final Completer<void> finished = Completer<void>();

  /// Bytes at the first progress report: what was already on disk is not "speed"
  int? lastBytes;

  _Job(this.id);
}

class DownloadManager extends ChangeNotifier {
  static DownloadManager instance = DownloadManager();

  /// An episode finished downloading (the app learns its skips: AniSkip, listening)
  void Function(DownloadItem item)? onDone;

  /// The index file (tests: a temporary one)
  final String? _indexPath;
  final String? _rootOverride;
  final DownloadFetch _fetch;
  final VideoResolver? _resolveOverride;
  final NetworkStatus? _networkOverride;
  final SourceRegistry? _registryOverride;
  final Map<String, dynamic> Function() _loadPrefs;
  final void Function(Map<String, dynamic>) _savePrefs;

  /// The height for watching («Якість» of the sources): downloads take it when their own is "the same"
  final int Function() _watchHeight;
  final String Function() _watchHoster;

  /// Network failures: the first retry waits this long, then longer (up to 16×)
  final Duration retryBase;

  /// A failed part (a segment, a file) is tried again after this, a few times, before the episode counts as failed
  final Duration partRetryDelay;

  /// Less free space than this and a download does not start (the system needs room too)
  final int reserveBytes;

  /// How long a watched episode waits before it is deleted after another one opens (the player lets go of the file)
  final Duration trashDelay;

  /// Free and total bytes where a path lies; null when unknown (tests replace it)
  final Future<(int, int)?> Function(String path) _storage;

  final int parallel;

  DownloadManager({
    String? indexPath,
    String? root,
    DownloadFetch? fetch,
    VideoResolver? resolve,
    NetworkStatus? network,
    SourceRegistry? registry,
    Map<String, dynamic> Function()? loadPrefs,
    void Function(Map<String, dynamic>)? savePrefs,
    int Function()? watchHeight,
    String Function()? watchHoster,
    Future<(int, int)?> Function(String path)? storage,
    this.retryBase = const Duration(seconds: 15),
    this.partRetryDelay = const Duration(seconds: 2),
    this.reserveBytes = 300 * 1024 * 1024,
    this.trashDelay = const Duration(seconds: 8),
    this.parallel = 4,
  })  : _indexPath = indexPath,
        _rootOverride = root,
        _fetch = fetch ?? DownloadWorker.httpFetch,
        _resolveOverride = resolve,
        _networkOverride = network,
        _registryOverride = registry,
        _loadPrefs = loadPrefs ?? (() => StorageService.getSection('downloads')),
        _savePrefs = savePrefs ?? ((m) => StorageService.saveSection('downloads', m)),
        _watchHeight = watchHeight ?? (() => SourcePrefs.instance.maxHeight),
        _watchHoster = watchHoster ?? (() => SourcePrefs.instance.hoster),
        _storage = storage ?? SystemControls.storageInfo;

  NetworkStatus get _network => _networkOverride ?? NetworkStatus.instance;
  SourceRegistry get _registry => _registryOverride ?? SourceRegistry.instance;

  final Map<String, DownloadItem> _items = {};
  final Map<String, DownloadGroup> _groups = {};
  final Map<String, _Job> _jobs = {};

  /// Paused or removed downloads whose workers are still letting go of their files
  final Map<String, _Job> _stopping = {};

  /// Watched episodes to delete once nothing plays them ([DownloadPrefs.deleteWatched])
  final Set<String> _trash = {};

  DownloadPrefs _prefs = const DownloadPrefs();
  Future<void>? _loading;
  bool _loaded = false;
  bool _disposed = false;
  bool _noSpace = false;
  int _failStreak = 0;
  DateTime? _retryAt;
  Timer? _retryTimer;
  Timer? _saveTimer;
  Timer? _notifyTimer;
  Timer? _trashTimer;
  DateTime _serviceAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _serviceOn = false;
  String? _playing;

  /// (time ms, bytes downloaded so far): the speed over the last seconds
  final List<(int, int)> _samples = [];
  int _counter = 0;

  // ── Reading ───────────────────────────────────────────────────────────────

  bool get ready => _loaded;

  DownloadPrefs get prefs => _prefs;

  set prefs(DownloadPrefs p) {
    final wifiChanged = p.wifiOnly != _prefs.wifiOnly;
    _prefs = p;
    _savePrefs(p.toJson());
    if (wifiChanged) _onNetwork();
    notifyListeners();
  }

  /// Where new downloads go
  String get root => _rootOverride ?? (_prefs.folder.isNotEmpty ? _prefs.folder : defaultRoot);

  static String? _defaultRoot;

  /// Android: the app's private folder (gone with the app, invisible to others); Windows: `Videos\Miki Miki`
  static String get defaultRoot => _defaultRoot ??= () {
        if (Platform.isWindows) {
          final home = Platform.environment['USERPROFILE'];
          if (home != null && Directory('$home\\Videos').existsSync()) return '$home\\Videos\\${AppIdentity.name}';
        }
        return '${StorageService.appBasePath}${Platform.pathSeparator}downloads';
      }();

  String get _index => _indexPath ?? '${StorageService.appBasePath}${Platform.pathSeparator}downloads.json';

  /// Everything, in queue order
  List<DownloadItem> get items => List.unmodifiable(_items.values);

  DownloadItem? item(String id) => _items[id];

  /// What is not finished yet: running, waiting, paused, failed
  List<DownloadItem> get pending => [for (final i in _items.values) if (!i.isDone) i];

  List<DownloadItem> get done => [for (final i in _items.values) if (i.isDone) i];

  /// Running or waiting for its turn (or the network)
  bool get busy => _items.values.any((i) => i.isActive);

  /// The episode downloading now
  DownloadItem? get current => _jobs.isEmpty ? null : _items[_jobs.keys.first];

  int get usedBytes => _items.values.fold(0, (a, i) => a + i.bytes);

  List<DownloadShelf> get shelves => DownloadShelf.of(_items.values);

  DownloadGroup? group(String animeKey, String groupId) => _groups[DownloadGroup.keyOf(animeKey, groupId)];

  /// The dubs of [animeKey] with something downloaded, newest first
  List<DownloadGroup> groupsOf(String animeKey) => [for (final g in _groups.values) if (g.animeKey == animeKey) g];

  DownloadItem? itemOf(String sourceId, SEpisode e) => _items[DownloadItem.idOf(sourceId, e)];

  /// The dub's downloads by episode key (the plates of the "Перегляд" panel and the player's list)
  Map<String, DownloadItem> byEpKey(String animeKey, String groupId) => {
        for (final i in _items.values)
          if (i.animeKey == animeKey && i.groupId == groupId) i.epKey: i,
      };

  /// A finished download of this episode, ready to play
  DownloadItem? playable(String sourceId, SEpisode e) {
    final i = itemOf(sourceId, e);
    return i != null && i.isDone && i.file.isNotEmpty ? i : null;
  }

  /// The title has finished downloads (any dub)
  bool hasDone(String animeKey) => _items.values.any((i) => i.animeKey == animeKey && i.isDone);

  /// Bytes a second over the last few seconds (0 when nothing goes)
  double get speed {
    if (_jobs.isEmpty || _samples.length < 2) return 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    final from = _samples.firstWhere((s) => now - s.$1 <= 6000, orElse: () => _samples.last);
    final ms = now - from.$1;
    if (ms < 800) return 0;
    return (_counter - from.$2) * 1000 / ms;
  }

  /// Why nothing downloads now although something waits; null when downloads go (or nothing waits)
  String? get waitReason {
    if (!_items.values.any((i) => i.state == DownloadState.queued)) return null;
    if (_noSpace) return 'Замало місця на пристрої';
    if (!_network.online) return 'Немає інтернету — продовжиться, щойно він зʼявиться';
    if (_prefs.wifiOnly && _network.metered) return 'Чекаю на Wi-Fi: мобільний інтернет для завантажень вимкнено';
    final at = _retryAt;
    if (at != null && _jobs.isEmpty) {
      final s = at.difference(DateTime.now()).inSeconds;
      if (s > 0) return 'Звʼязок перервався — повторю за $s с';
    }
    return null;
  }

  /// Free and total bytes where new downloads go (Android; null where unknown)
  Future<(int, int)?> storageInfo() => _storage(root);

  /// Downloads may go now as far as the network is concerned
  bool get networkAllows => _network.allows(wifiOnly: _prefs.wifiOnly);

  // ── Start ─────────────────────────────────────────────────────────────────

  /// Reads the index (once): finished downloads whose files are gone are forgotten, unfinished ones go on
  Future<void> init() => _loading ??= _load();

  Future<void> _load() async {
    try {
      _prefs = DownloadPrefs.fromJson(_loadPrefs());
    } catch (_) {}
    try {
      final f = File(_index);
      if (await f.exists()) {
        final j = jsonDecode(await f.readAsString());
        if (j is Map) {
          for (final g in (j['groups'] as List?) ?? const []) {
            final group = DownloadGroup.fromJson(g);
            if (group != null) _groups[group.key] = group;
          }
          for (final raw in (j['items'] as List?) ?? const []) {
            final i = DownloadItem.fromJson(raw);
            if (i != null) _items[i.id] = i;
          }
          for (final t in (j['trash'] as List?) ?? const []) {
            if (t is String) _trash.add(t);
          }
        }
      }
    } catch (e) {
      AppLog.w('завантаження', 'список завантажень не прочитано: $e');
    }
    // A downloaded episode whose files were deleted outside the app is no longer on the device
    var lost = 0;
    for (final i in [..._items.values]) {
      if (!i.isDone) continue;
      if (!await File(_join(i.folder, i.file)).exists()) {
        _items.remove(i.id);
        lost++;
      }
    }
    if (lost > 0) AppLog.w('завантаження', 'файлів $lost завантажених серій немає на диску — прибрано зі списку');
    _dropEmptyGroups();
    _loaded = true;
    _network.addListener(_onNetwork);
    SystemControls.onDownloadsAction = (a) {
      if (a == 'pause') pauseAll();
    };
    final waiting = _items.values.where((i) => !i.isDone).length;
    AppLog.i('завантаження', 'на пристрої ${done.length} серій (${formatBytes(usedBytes)}), у черзі $waiting');
    if (lost > 0) _saveSoon();
    if (!_disposed) notifyListeners();
    // On Android the first seconds must not go over mobile data before the system tells which network it is
    await _network.ready;
    _pump();
    _scheduleTrash(trashDelay * 2.5);
  }

  /// Reads the index again into this same manager (previews change it on disk); nothing may be running
  @visibleForTesting
  Future<void> debugReload() async {
    if (_loaded) _network.removeListener(_onNetwork);
    _items.clear();
    _groups.clear();
    _trash.clear();
    _loaded = false;
    _loading = null;
    await init();
  }

  // ── Adding ────────────────────────────────────────────────────────────────

  /// Queues episodes [indexes] of dub [group]. Already downloaded ones are skipped, paused or failed ones go on.
  /// Returns how many were queued
  Future<int> enqueue({
    required String animeKey,
    required String animeTitle,
    String? poster,
    required WatchGroup group,
    required Iterable<int> indexes,
    HikkaEpisodeInfo? hikka,
  }) async {
    await init();
    final g = _snapshot(animeKey, animeTitle, poster, group, hikka);
    final keys = g.keys;
    final height = _prefs.height > 0 ? _prefs.height : _watchHeight();
    final now = DateTime.now();
    var added = 0;
    for (final i in indexes.toSet().toList()..sort()) {
      if (i < 0 || i >= group.episodes.length) continue;
      final e = group.episodes[i];
      final id = DownloadItem.idOf(group.sourceId, e);
      final old = _items[id];
      if (old != null) {
        if (old.state == DownloadState.paused || old.state == DownloadState.failed) {
          _items[id] = old.copyWith(state: DownloadState.queued, clearError: true);
          added++;
        }
        continue;
      }
      _items[id] = DownloadItem(
        id: id,
        animeKey: animeKey,
        animeTitle: animeTitle,
        poster: poster,
        groupId: group.id,
        groupLabel: group.label,
        isSub: group.isSub,
        sourceId: group.sourceId,
        episode: e,
        epKey: keys[i],
        title: e.name.isEmpty ? 'Серія ${episodeLabel(e, i)}' : e.name,
        order: i,
        count: group.episodes.length,
        height: height,
        addedAt: now,
        folder: _join(g.folder, _safe('Серія ${keys[i]}')),
      );
      added++;
    }
    if (added > 0) {
      _noSpace = false;
      AppLog.i('завантаження', 'у черзі +$added: $animeTitle · ${group.label}');
    }
    _changedNow();
    _saveSoon();
    _pump();
    return added;
  }

  /// Remembers (or refreshes) the dub as it is now; its folder stays the one given the first time
  DownloadGroup _snapshot(String animeKey, String animeTitle, String? poster, WatchGroup group, HikkaEpisodeInfo? hikka) {
    final key = DownloadGroup.keyOf(animeKey, group.id);
    final old = _groups[key];
    final g = DownloadGroup(
      animeKey: animeKey,
      animeTitle: animeTitle,
      poster: poster ?? old?.poster,
      id: group.id,
      sourceId: group.sourceId,
      label: group.label,
      isSub: group.isSub,
      episodes: group.episodes,
      hikka: hikka ?? old?.hikka,
      folder: old?.folder ?? _folderFor(animeTitle, group, key),
    );
    _groups[key] = g;
    return g;
  }

  /// `<root>/<title>/<dub>`; another dub or title with the same name gets " 2", " 3"…
  String _folderFor(String animeTitle, WatchGroup group, String key) {
    final base = _join(_join(root, _safe(animeTitle)), _safe('${group.isSub ? 'Субтитри' : 'Озвучення'} ${group.teamLabel}'));
    var path = base;
    for (var n = 2; _groups.values.any((g) => g.key != key && g.folder == path); n++) {
      path = '$base $n';
    }
    return path;
  }

  /// A name any file system takes: no reserved characters, no trailing dots or spaces, not too long
  static String _safe(String name) {
    var s = name.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (s.length > 64) s = s.substring(0, 64).trim();
    s = s.replaceAll(RegExp(r'[. ]+$'), '');
    return s.isEmpty ? '_' : s;
  }

  static String _join(String a, String b) => a.endsWith('/') || a.endsWith('\\') ? '$a$b' : '$a${Platform.pathSeparator}$b';

  // ── Control ───────────────────────────────────────────────────────────────

  void pause(String id) {
    final it = _items[id];
    if (it == null || it.isDone || it.state == DownloadState.paused) return;
    _items[id] = it.copyWith(state: DownloadState.paused);
    _stop(id);
    AppLog.i('завантаження', 'пауза: ${it.animeTitle} · ${it.title}');
    _changedNow();
    _saveSoon();
    _pump();
  }

  /// Goes on with a paused or failed download (a failed one tries again from where it stopped)
  void resume(String id) {
    final it = _items[id];
    if (it == null || it.isDone || it.isActive) return;
    _items[id] = it.copyWith(state: DownloadState.queued, clearError: true);
    _noSpace = false;
    _retryAt = null;
    _failStreak = 0;
    _changedNow();
    _saveSoon();
    _pump();
  }

  void pauseAll() {
    var n = 0;
    for (final it in [..._items.values]) {
      if (!it.isActive) continue;
      _items[it.id] = it.copyWith(state: DownloadState.paused);
      _stop(it.id);
      n++;
    }
    if (n == 0) return;
    AppLog.i('завантаження', 'пауза всіх ($n)');
    _changedNow();
    _saveSoon();
    _syncService(force: true);
  }

  void resumeAll() {
    var n = 0;
    for (final it in [..._items.values]) {
      if (it.state != DownloadState.paused && it.state != DownloadState.failed) continue;
      _items[it.id] = it.copyWith(state: DownloadState.queued, clearError: true);
      n++;
    }
    if (n == 0) return;
    _noSpace = false;
    _retryAt = null;
    _failStreak = 0;
    _changedNow();
    _saveSoon();
    _pump();
  }

  /// Deletes the download and its files (a running one stops first)
  Future<void> remove(String id) => removeMany([id]);

  Future<void> removeMany(Iterable<String> ids) async {
    final gone = <DownloadItem>[];
    for (final id in ids.toList()) {
      final it = _items.remove(id);
      if (it == null) continue;
      _trash.remove(id);
      _stop(id);
      gone.add(it);
    }
    if (gone.isEmpty) return;
    _noSpace = false;
    _changedNow();
    _saveSoon();
    await Future.wait([for (final it in gone) _stopping[it.id]?.finished.future ?? Future<void>.value()]);
    for (final it in gone) {
      await _deleteFolder(it.folder);
    }
    AppLog.i('завантаження', 'видалено ${gone.length}: ${gone.first.animeTitle}${gone.length > 1 ? ' …' : ' · ${gone.first.title}'}');
    _dropEmptyGroups();
    _changedNow();
    _saveSoon();
    _pump();
  }

  Future<void> removeGroup(String animeKey, String groupId) =>
      removeMany([for (final i in _items.values) if (i.animeKey == animeKey && i.groupId == groupId) i.id]);

  Future<void> removeAll() => removeMany([..._items.keys]);

  /// Stops a running download: its worker lets go of the files in the background ([_stopping])
  void _stop(String id) {
    final job = _jobs.remove(id);
    if (job == null) return;
    _stopping[id] = job;
    job.cancel.cancel();
  }

  // ── Smart downloads ───────────────────────────────────────────────────────

  /// The player marked episode [epKey] watched (by itself, at the end). If it was downloaded: the next episode
  /// not on the device yet downloads ([DownloadPrefs.autoNext]) and this one goes later ([DownloadPrefs.deleteWatched]).
  /// [group] is the dub as the player knows it now (fresher than the copy: new episodes come out)
  void onWatched(String animeKey, String epKey, {WatchGroup? group}) {
    if (!_loaded) return;
    for (final g in groupsOf(animeKey)) {
      if (group != null && group.id != g.id) continue;
      final fresh = group != null ? _snapshot(animeKey, g.animeTitle, g.poster, group, g.hikka) : g;
      final keys = fresh.keys;
      final i = keys.indexOf(epKey);
      if (i < 0) continue;
      final it = _items[DownloadItem.idOf(fresh.sourceId, fresh.episodes[i])];
      if (it == null) continue;
      if (_prefs.deleteWatched && it.isDone) {
        _trash.add(it.id);
        _saveSoon();
      }
      if (!_prefs.autoNext) continue;
      for (var j = i + 1; j < fresh.episodes.length; j++) {
        if (_items.containsKey(DownloadItem.idOf(fresh.sourceId, fresh.episodes[j]))) continue;
        AppLog.i('завантаження', 'наступна серія сама: ${fresh.animeTitle} · ${keys[j]}');
        unawaited(enqueue(animeKey: animeKey, animeTitle: fresh.animeTitle, poster: fresh.poster, group: fresh.watchGroup, indexes: [j], hikka: fresh.hikka));
        break;
      }
    }
  }

  /// The player opened [id] (a downloaded episode) or something else (null): what waits for deletion and is not
  /// playing goes a little later (on Windows the player must let go of the old file first)
  void markPlaying(String? id) {
    _playing = id;
    if (_trash.isNotEmpty) _scheduleTrash(trashDelay);
  }

  void _scheduleTrash(Duration after) {
    _trashTimer?.cancel();
    if (_trash.isEmpty) return;
    _trashTimer = Timer(after, () {
      final ids = [for (final id in _trash) if (id != _playing) id];
      if (ids.isNotEmpty) unawaited(removeMany(ids));
    });
  }

  // ── Offline playback ──────────────────────────────────────────────────────

  /// What the player needs to play the dub from the downloads (without the network: its episodes as they were).
  /// [epKey]: the episode to start from
  RemoteLaunch? launch(String animeKey, String groupId, {String? epKey}) {
    final g = group(animeKey, groupId);
    if (g == null) return null;
    final source = _registry.byId(g.sourceId);
    if (source == null) return null;
    final wg = g.watchGroup;
    return RemoteLaunch(
      title: WatchTitle(
        animeKey: animeKey,
        offers: [WatchOffer(source: source, anime: SAnime(url: '', title: g.animeTitle), groups: [wg])],
        episodeLimit: g.hikka?.total,
      ),
      group: wg,
      animeTitle: g.animeTitle,
      epKey: epKey,
      poster: g.poster,
      hikka: g.hikka,
    );
  }

  /// Where to start dub [groupId] without internet: [from] (the continue point) when it is downloaded, else the first
  /// downloaded episode after it, else the first downloaded unwatched one, else the first downloaded; null when the
  /// dub has nothing on the device
  String? offlineStart(String animeKey, String groupId, List<String> keys, int from, Set<String> watched) {
    final have = {for (final e in byEpKey(animeKey, groupId).entries) if (e.value.isDone) e.key};
    if (have.isEmpty) return null;
    for (var i = from.clamp(0, keys.length); i < keys.length; i++) {
      if (have.contains(keys[i])) return keys[i];
    }
    for (final k in keys) {
      if (have.contains(k) && !watched.contains(k)) return k;
    }
    for (final k in keys) {
      if (have.contains(k)) return k;
    }
    return null;
  }

  /// The downloaded copy as a video for the player: the local playlist or file, subtitles and audio next to it
  Video? localVideo(DownloadItem item) {
    if (!item.isDone || item.file.isEmpty) return null;
    final base = item.folder;
    final h = int.tryParse(item.quality.replaceAll(RegExp(r'\D'), ''));
    return Video(
      url: _join(base, item.file),
      title: item.quality.isEmpty ? 'Завантажено' : item.quality,
      resolution: h == null || h <= 0 ? null : h,
      subtitleTracks: [for (final s in item.subtitles) Track(_join(base, s.file), s.lang)],
      audioTracks: [for (final a in item.audio) Track(_join(base, a.file), a.lang)],
      timestamps: item.timestamps,
    );
  }

  // ── The queue ─────────────────────────────────────────────────────────────

  void _pump() {
    if (!_loaded || _disposed) return;
    while (_jobs.isEmpty) {
      if (_noSpace || !networkAllows) break;
      final at = _retryAt;
      if (at != null && DateTime.now().isBefore(at)) {
        _retryTimer?.cancel();
        _retryTimer = Timer(at.difference(DateTime.now()) + const Duration(milliseconds: 50), _pump);
        break;
      }
      DownloadItem? next;
      for (final i in _items.values) {
        if (i.state == DownloadState.queued && !_stopping.containsKey(i.id)) {
          next = i;
          break;
        }
      }
      if (next == null) break;
      _start(next);
    }
    _syncService();
  }

  void _start(DownloadItem item) {
    final job = _Job(item.id);
    _jobs[item.id] = job;
    final running = item.copyWith(state: DownloadState.running, clearError: true);
    _items[item.id] = running;
    AppLog.i('завантаження', 'почато: ${item.animeTitle} · ${item.title}');
    _changedNow();
    unawaited(_run(job, running));
  }

  Future<void> _run(_Job job, DownloadItem item) async {
    try {
      final space = await _storage(root);
      if (space != null && space.$1 < reserveBytes) throw const DownloadFailure('Замало місця на пристрої', noSpace: true);
      final worker = DownloadWorker(
        item: item,
        dir: Directory(item.folder),
        fetch: _fetch,
        resolve: _resolveOverride ?? _resolve,
        onProgress: (p) => _progress(job, p),
        cancel: job.cancel,
        parallel: parallel,
        retryDelay: partRetryDelay,
      );
      final done = await worker.run();
      _finish(job, done, null);
    } catch (e) {
      _finish(job, null, e);
    }
  }

  void _progress(_Job job, DownloadItem p) {
    if (!identical(_jobs[job.id], job)) return;
    final last = job.lastBytes;
    job.lastBytes = p.bytes;
    if (last != null && p.bytes > last) _sample(p.bytes - last);
    _items[job.id] = p.copyWith(state: DownloadState.running);
    _changedSoon();
    _syncService();
  }

  void _sample(int delta) {
    _counter += delta;
    final now = DateTime.now().millisecondsSinceEpoch;
    _samples.add((now, _counter));
    while (_samples.length > 2 && now - _samples.first.$1 > 8000) {
      _samples.removeAt(0);
    }
  }

  void _finish(_Job job, DownloadItem? done, Object? error) {
    if (!job.finished.isCompleted) job.finished.complete();
    final mine = identical(_jobs[job.id], job);
    if (mine) _jobs.remove(job.id);
    if (identical(_stopping[job.id], job)) _stopping.remove(job.id);
    final it = _items[job.id];
    if (_disposed) return;
    if (done != null && it != null) {
      _items[job.id] = done;
      _failStreak = 0;
      _retryAt = null;
      AppLog.i('завантаження', 'готово: ${done.animeTitle} · ${done.title} (${done.quality}, ${formatBytes(done.bytes)})');
      try {
        onDone?.call(done);
      } catch (_) {}
    } else if (error is DownloadCancelled || !mine || it == null) {
      // Paused, removed or stopped for the network: the state was set by whoever stopped it
    } else if (error is DownloadFailure && error.network) {
      _failStreak++;
      final wait = retryBase * (1 << (_failStreak - 1).clamp(0, 4));
      _retryAt = DateTime.now().add(wait);
      _items[job.id] = it.copyWith(state: DownloadState.queued, error: error.message);
      AppLog.w('завантаження', 'мережа: ${error.message} — повтор за ${wait.inSeconds} с (${it.title})');
      _network.reportFailure();
    } else {
      final failure = _describe(error);
      if (failure.noSpace) _noSpace = true;
      _items[job.id] = it.copyWith(state: DownloadState.failed, error: failure.message);
      AppLog.w('завантаження', 'не вдалося: ${it.animeTitle} · ${it.title}: ${failure.message}');
    }
    _changedNow();
    _saveSoon();
    _pump();
  }

  static DownloadFailure _describe(Object? e) {
    if (e is DownloadFailure) return e;
    if (e is FileSystemException) {
      final code = e.osError?.errorCode;
      // ENOSPC (Linux, Android), ERROR_DISK_FULL / ERROR_HANDLE_DISK_FULL (Windows)
      if (code == 28 || code == 112 || code == 39) return const DownloadFailure('Замало місця на пристрої', noSpace: true);
      return DownloadFailure('Не вдалося записати файл: ${e.osError?.message ?? e.message}');
    }
    return DownloadFailure('Збій завантаження: $e');
  }

  /// A fresh link to the episode from its site, in the wanted quality (links live a few hours)
  Future<ResolvedVideo> _resolve(DownloadItem item) async {
    final source = _registry.byId(item.sourceId);
    if (source == null) throw DownloadFailure('Джерела «${item.sourceId}» більше немає в застосунку');
    try {
      final res = await StreamResolver(maxHeight: () => item.height, preferredHoster: _watchHoster).resolve(source, item.episode);
      return ResolvedVideo(res.video, res.hoster);
    } on SocketException {
      throw const DownloadFailure('Немає зʼєднання', network: true);
    } on SourceException catch (e) {
      final network = e.kind == SourceErrorKind.network || e.kind == SourceErrorKind.timeout;
      throw DownloadFailure(e.message, network: network);
    }
  }

  void _onNetwork() {
    if (!_loaded || _disposed) return;
    if (!networkAllows) {
      // Wi-Fi went and mobile data came (or nothing): stop at once, the parts on disk stay
      for (final id in [..._jobs.keys]) {
        final it = _items[id];
        if (it != null) _items[id] = it.copyWith(state: DownloadState.queued);
        _stop(id);
      }
      _changedNow();
    } else {
      // The network is back: no reason to wait out the retry delay
      _retryAt = null;
      _failStreak = 0;
    }
    _pump();
    notifyListeners();
  }

  // ── The notification (Android) ────────────────────────────────────────────

  void _syncService({bool force = false}) {
    final cur = current;
    if (cur == null) {
      if (_serviceOn) {
        _serviceOn = false;
        unawaited(SystemControls.downloadService(active: false));
      }
      return;
    }
    final now = DateTime.now();
    if (!force && _serviceOn && now.difference(_serviceAt) < const Duration(seconds: 1)) return;
    _serviceAt = now;
    _serviceOn = true;
    final f = cur.fraction;
    final rest = _items.values.where((i) => i.isActive).length - 1;
    unawaited(SystemControls.downloadService(
      active: true,
      title: '${cur.animeTitle} · ${cur.title}',
      text: [
        if (f != null) '${(f * 100).floor()} %',
        if (speed > 0) '${formatBytes(speed.round())}/с',
        if (rest > 0) 'ще $rest у черзі',
      ].join(' · '),
      progress: f == null ? -1 : (f * 100).floor(),
    ));
  }

  // ── Saving and notifying ──────────────────────────────────────────────────

  void _changedNow() {
    _notifyTimer?.cancel();
    _notifyTimer = null;
    if (!_disposed) notifyListeners();
  }

  /// Progress: at most four repaints a second
  void _changedSoon() {
    _notifyTimer ??= Timer(const Duration(milliseconds: 250), () {
      _notifyTimer = null;
      if (!_disposed) notifyListeners();
    });
  }

  void _saveSoon() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), () => unawaited(save()));
  }

  /// Writes the index now (a copy first, then a rename: a crash never leaves half a file)
  Future<void> save() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    if (!_loaded) return;
    final text = jsonEncode({
      'v': 1,
      'groups': [for (final g in _groups.values) g.toJson()],
      'items': [for (final i in _items.values) i.toJson()],
      if (_trash.isNotEmpty) 'trash': [..._trash],
    });
    try {
      final f = File(_index);
      await f.parent.create(recursive: true);
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(text, flush: true);
      try {
        await tmp.rename(f.path);
      } on FileSystemException {
        await f.writeAsString(text, flush: true);
        await tmp.delete().catchError((_) => tmp);
      }
    } catch (e) {
      AppLog.w('завантаження', 'список не збережено: $e');
    }
  }

  void _dropEmptyGroups() {
    final used = {for (final i in _items.values) DownloadGroup.keyOf(i.animeKey, i.groupId)};
    _groups.removeWhere((k, _) => !used.contains(k));
  }

  /// Deletes an episode's folder, and the dub's and title's folders when they are left empty
  Future<void> _deleteFolder(String path) async {
    try {
      final d = Directory(path);
      if (await d.exists()) await d.delete(recursive: true);
      var parent = d.parent;
      for (var up = 0; up < 2 && parent.path.length > root.length; up++) {
        if (!await parent.exists() || !(await parent.list().isEmpty)) break;
        await parent.delete();
        parent = parent.parent;
      }
    } catch (e) {
      AppLog.w('завантаження', 'файли не видалено ($path): $e');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    for (final j in _jobs.values) {
      j.cancel.cancel();
    }
    _retryTimer?.cancel();
    _saveTimer?.cancel();
    _notifyTimer?.cancel();
    _trashTimer?.cancel();
    if (_loaded) _network.removeListener(_onNetwork);
    super.dispose();
  }
}
