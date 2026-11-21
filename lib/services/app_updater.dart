import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;

import '../constants/app_identity.dart';
import 'app_log.dart';
import 'storage_service.dart';
import 'system_controls.dart';

/// New version from GitHub Releases
class UpdateInfo {
  final String version;
  final String notes;
  final String pageUrl;

  /// Direct file for this platform (APK on Android, the setup on Windows); empty means only the release page
  final String downloadUrl;
  final String assetName;
  final int size;

  /// The file's checksum as GitHub gives it (`sha256:<hex>`); empty when the release has none
  final String digest;

  const UpdateInfo({
    required this.version,
    required this.notes,
    required this.pageUrl,
    this.downloadUrl = '',
    this.assetName = '',
    this.size = 0,
    this.digest = '',
  });

  /// What to open for the user: the file or, if there is none, the release page
  String get target => downloadUrl.isNotEmpty ? downloadUrl : pageUrl;

  Map<String, dynamic> toJson() =>
      {'version': version, 'notes': notes, 'page': pageUrl, 'url': downloadUrl, 'name': assetName, 'size': size, 'digest': digest};

  static UpdateInfo? fromJson(Object? j) {
    if (j is! Map) return null;
    final v = j['version'];
    final p = j['page'];
    if (v is! String || p is! String) return null;
    return UpdateInfo(
      version: v,
      notes: (j['notes'] as String?) ?? '',
      pageUrl: p,
      downloadUrl: (j['url'] as String?) ?? '',
      assetName: (j['name'] as String?) ?? '',
      size: (j['size'] as num?)?.toInt() ?? 0,
      digest: (j['digest'] as String?) ?? '',
    );
  }
}

sealed class UpdateState {
  const UpdateState();
}

class UpdateIdle extends UpdateState {
  const UpdateIdle();
}

class UpdateChecking extends UpdateState {
  const UpdateChecking();
}

class UpdateUpToDate extends UpdateState {
  const UpdateUpToDate();
}

class UpdateAvailable extends UpdateState {
  final UpdateInfo info;
  const UpdateAvailable(this.info);
}

class UpdateFailed extends UpdateState {
  final String message;
  const UpdateFailed(this.message);
}

/// The update file on this device: not loaded, loading, ready to install, failed
sealed class UpdateDownload {
  const UpdateDownload();
}

class DownloadIdle extends UpdateDownload {
  const DownloadIdle();
}

class DownloadRunning extends UpdateDownload {
  final String version;
  final int received;

  /// The whole file's size; 0 when unknown
  final int total;

  const DownloadRunning(this.version, this.received, this.total);

  /// 0…1, or null while the size is unknown
  double? get fraction => total > 0 ? (received / total).clamp(0.0, 1.0) : null;
}

class DownloadReady extends UpdateDownload {
  final String version;
  final String path;

  /// Android: the install waits until the person allows Miki Miki to install apps (the system settings are open)
  final bool waitingPermission;

  /// Why the last attempt to install did not start (the file stays ready)
  final String? error;

  const DownloadReady(this.version, this.path, {this.waitingPermission = false, this.error});
}

class DownloadFailed extends UpdateDownload {
  final String version;
  final String message;
  const DownloadFailed(this.version, this.message);
}

/// What [AppUpdater.install] did
enum UpdateInstall {
  /// The system installer (Android) or the setup (Windows) is running
  started,

  /// Android: the system settings opened to allow installing apps from Miki Miki; the install continues on return
  needsPermission,

  /// Nothing to install here (no ready file, or this platform installs by hand)
  unavailable,

  failed,
}

/// `(status, body)` for GET; replaced in tests
typedef UpdateTransport = Future<(int, String)> Function(String url);

/// An opened download: the status (200 — the whole file, 206 — the rest asked for), the body's length (-1 unknown),
/// the body and a way to break the connection
class UpdateFetchResponse {
  final int status;
  final int length;
  final Stream<List<int>> body;
  final void Function() cancel;

  const UpdateFetchResponse(this.status, this.length, this.body, this.cancel);
}

/// Opens [url] from byte `from` (0 — the whole file); replaced in tests
typedef UpdateFetch = Future<UpdateFetchResponse> Function(String url, int from);

/// Checks GitHub Releases for a new version, downloads the file for this platform inside the app (with progress,
/// resuming after a break, checking the size and GitHub's SHA-256) and hands it to the system: on Android the system
/// installer asks to update, on Windows the setup runs quietly and the app starts again.
class AppUpdater {
  static AppUpdater instance = AppUpdater();

  /// Repository with the releases
  static const String repo = 'Zeddy-Coder/miki-miki';
  static const String section = 'updates';

  /// At most once per this interval when the check runs by itself
  static const Duration autoEvery = Duration(minutes: 30);

  /// A download with no data for this long is broken (the next try continues from where it stopped)
  static const Duration stallTimeout = Duration(seconds: 30);

  final UpdateTransport _transport;
  final UpdateFetch _fetch;
  final SectionLoader _load;
  final SectionSaver _save;
  final String currentVersion;
  final bool Function() _isAndroid;
  final bool Function() _isWindows;
  final bool Function() _installedCopy;
  final String Function() _dirPath;
  final Future<String> Function(String path, bool ask) _installApk;
  final Future<bool> Function(String path) _runSetup;
  final void Function(void Function() callback) _nextResume;

  /// Current state for the UI
  final ValueNotifier<UpdateState> state = ValueNotifier<UpdateState>(const UpdateIdle());

  /// The update file on this device
  final ValueNotifier<UpdateDownload> download = ValueNotifier<UpdateDownload>(const DownloadIdle());

  /// Asks the app to show the "Доступне оновлення" window now (a tap on an "update" notification, a link)
  final ValueNotifier<int> promptRequests = ValueNotifier<int>(0);

  /// Counts finished downloads: the app offers to install one that finished while no window was open
  final ValueNotifier<int> downloadsDone = ValueNotifier<int>(0);

  late final Map<String, dynamic> _data = Map<String, dynamic>.of(_load());
  Future<void>? _running;
  Future<void>? _downloading;
  _DownloadJob? _job;

  AppUpdater({
    UpdateTransport? transport,
    UpdateFetch? fetch,
    SectionLoader? load,
    SectionSaver? save,
    String? currentVersion,
    bool Function()? isAndroid,
    bool Function()? isWindows,
    bool Function()? installedCopy,
    String Function()? dir,
    Future<String> Function(String path, bool ask)? installApk,
    Future<bool> Function(String path)? runSetup,
    void Function(void Function() callback)? onNextResume,
  })  : _transport = transport ?? _httpTransport,
        _fetch = fetch ?? _httpFetch,
        _load = load ?? (() => StorageService.getSection(section)),
        _save = save ?? ((d) => StorageService.saveSection(section, d)),
        currentVersion = currentVersion ?? AppIdentity.version,
        _isAndroid = isAndroid ?? (() => Platform.isAndroid),
        _isWindows = isWindows ?? (() => Platform.isWindows),
        _installedCopy = installedCopy ?? _detectInstalledCopy,
        _dirPath = dir ?? _defaultDir,
        _installApk = installApk ?? ((path, ask) => SystemControls.installApk(path, askPermission: ask)),
        _runSetup = runSetup ?? _runWindowsSetup,
        _nextResume = onNextResume ?? _whenResumed {
    // A newer version found earlier is visible immediately, before a new check
    final saved = UpdateInfo.fromJson(_data['latest']);
    if (saved != null && compareVersions(saved.version, this.currentVersion) > 0) {
      state.value = UpdateAvailable(saved);
    }
    _restoreFile();
  }

  static Future<(int, String)> _httpTransport(String url) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.getUrl(Uri.parse(url)).timeout(const Duration(seconds: 15));
      req.headers.set('Accept', 'application/vnd.github+json');
      req.headers.set('User-Agent', AppIdentity.userAgent('updates'));
      final res = await req.close().timeout(const Duration(seconds: 20));
      final text = await utf8.decodeStream(res).timeout(const Duration(seconds: 20));
      return (res.statusCode, text);
    } finally {
      client.close(force: true);
    }
  }

  /// GitHub's file link redirects to its storage: the client follows it, and `Range` goes along
  static Future<UpdateFetchResponse> _httpFetch(String url, int from) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.getUrl(Uri.parse(url)).timeout(const Duration(seconds: 20));
      req.headers.set('Accept', 'application/octet-stream');
      req.headers.set('User-Agent', AppIdentity.userAgent('updates'));
      if (from > 0) req.headers.set('Range', 'bytes=$from-');
      final res = await req.close().timeout(const Duration(seconds: 30));
      return UpdateFetchResponse(res.statusCode, res.contentLength, res, () => client.close(force: true));
    } catch (_) {
      client.close(force: true);
      rethrow;
    }
  }

  /// Android: the app's cache (the system installer reads it through the app's file provider, `cache/updates`);
  /// Windows: the temporary folder
  static String _defaultDir() => Platform.isAndroid
      ? '${Directory.systemTemp.path}/updates'
      : '${Directory.systemTemp.path}${Platform.pathSeparator}${AppIdentity.dataDirName}${Platform.pathSeparator}updates';

  static bool? _installedCache;

  /// Windows: this copy was put by the setup (its uninstaller lies next to the exe), so the setup can update it in place.
  /// A copy run from a plain folder updates by hand (the release page)
  static bool _detectInstalledCopy() => _installedCache ??= () {
        try {
          return File(Platform.resolvedExecutable)
              .parent
              .listSync()
              .any((f) => f is File && RegExp(r'unins\d+\.exe$', caseSensitive: false).hasMatch(f.path));
        } catch (_) {
          return false;
        }
      }();

  static void _whenResumed(void Function() callback) {
    late final AppLifecycleListener listener;
    listener = AppLifecycleListener(onResume: () {
      listener.dispose();
      callback();
    });
  }

  /// Comparison of versions like `1.2.3` (optional `v`, ignoring suffixes after `-`/`+`):
  /// positive if [a] is newer than [b]
  static int compareVersions(String a, String b) {
    List<int> parse(String s) {
      final core = s.trim().replaceFirst(RegExp(r'^[vV]'), '').split(RegExp(r'[-+]')).first;
      return core.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    }

    final x = parse(a);
    final y = parse(b);
    for (var i = 0; i < (x.length > y.length ? x.length : y.length); i++) {
      final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
      if (d != 0) return d;
    }
    return 0;
  }

  /// Picks the release file for the platform: APK (arm64 preferred) on Android; on Windows the setup
  /// (`…Setup….exe`) first, then another exe, msix, a `win` archive, anything else
  @visibleForTesting
  static Map<String, dynamic>? pickAsset(List<dynamic> assets, {required bool android}) {
    final list = assets.whereType<Map>().map((e) => e.cast<String, dynamic>()).where((a) => a['browser_download_url'] is String).toList();
    bool has(Map<String, dynamic> a, String s) => '${a['name']}'.toLowerCase().contains(s);
    bool ends(Map<String, dynamic> a, String e) => '${a['name']}'.toLowerCase().endsWith(e);
    if (android) {
      final apks = list.where((a) => ends(a, '.apk')).toList();
      if (apks.isEmpty) return null;
      return apks.firstWhere((a) => has(a, 'arm64'), orElse: () => apks.first);
    }
    final win = list.where((a) => (ends(a, '.zip') || ends(a, '.exe') || ends(a, '.msix')) && !has(a, 'android')).toList();
    if (win.isEmpty) return null;
    for (final pick in <bool Function(Map<String, dynamic>)>[
      (a) => ends(a, '.exe') && has(a, 'setup'),
      (a) => ends(a, '.exe'),
      (a) => ends(a, '.msix'),
      (a) => has(a, 'win'),
    ]) {
      for (final a in win) {
        if (pick(a)) return a;
      }
    }
    return win.first;
  }

  /// The version the user asked not to offer any more
  String get skippedVersion => '${_data['skip'] ?? ''}';

  void skip(String version) {
    _data['skip'] = version;
    _persist();
  }

  void _persist() {
    try {
      _save(_data);
    } catch (_) {}
  }

  /// Whether to show the "Доступне оновлення" dialog: the version is newer and was not skipped
  bool shouldPrompt(UpdateInfo info) => compareVersions(info.version, currentVersion) > 0 && skippedVersion != info.version;

  /// Shows the update window (a tap on a notification, a link): checks first while no newer version is known
  void requestPrompt() {
    if (state.value is! UpdateAvailable) unawaited(check());
    promptRequests.value++;
  }

  /// Checks for updates. `auto: true` is a silent check, at most once per [autoEvery] (the GitHub request stays within the limit) and without showing errors
  Future<void> check({bool auto = false}) {
    final running = _running;
    if (running != null) return running;
    if (auto) {
      final last = DateTime.tryParse('${_data['checkedAt'] ?? ''}');
      if (last != null && DateTime.now().difference(last) < autoEvery) return Future.value();
    }
    return _running = _run(auto).whenComplete(() => _running = null);
  }

  Future<void> _run(bool auto) async {
    final before = state.value;
    if (!auto) state.value = const UpdateChecking();
    try {
      final (status, body) = await _transport('https://api.github.com/repos/$repo/releases/latest');
      if (status == 404) {
        // There are no releases yet: this is not an error
        _done(null);
        return;
      }
      if (status != 200) throw 'GitHub відповів $status';
      final j = jsonDecode(body);
      if (j is! Map) throw 'неочікувана відповідь';
      final tag = (j['tag_name'] as String?) ?? '';
      if (tag.isEmpty) throw 'у релізі немає версії';
      final asset = pickAsset((j['assets'] as List?) ?? const [], android: _isAndroid());
      final info = UpdateInfo(
        version: tag.replaceFirst(RegExp(r'^[vV]'), ''),
        notes: ((j['body'] as String?) ?? '').trim(),
        pageUrl: (j['html_url'] as String?) ?? 'https://github.com/$repo/releases',
        downloadUrl: (asset?['browser_download_url'] as String?) ?? '',
        assetName: (asset?['name'] as String?) ?? '',
        size: (asset?['size'] as num?)?.toInt() ?? 0,
        digest: (asset?['digest'] as String?) ?? '',
      );
      _done(compareVersions(info.version, currentVersion) > 0 ? info : null);
    } catch (e) {
      AppLog.w('Updater', 'перевірка не вдалася: $e');
      // A silent check shows nothing; a manual one reports
      state.value = auto ? before : UpdateFailed('Не вдалося перевірити: ${e is SocketException ? 'немає мережі' : e}');
    }
  }

  void _done(UpdateInfo? info) {
    _data['checkedAt'] = DateTime.now().toIso8601String();
    if (info == null) {
      _data.remove('latest');
    } else {
      _data['latest'] = info.toJson();
    }
    _persist();
    state.value = info == null ? const UpdateUpToDate() : UpdateAvailable(info);
  }

  // ── Download and install ───────────────────────────────────────────────────

  /// Whether this version is downloaded and installed inside the app (an APK on Android; on Windows the setup, for a
  /// copy the setup installed); otherwise the file or the release page opens in the browser
  bool canInstallInApp(UpdateInfo info) {
    if (info.downloadUrl.isEmpty) return false;
    final name = (info.assetName.isNotEmpty ? info.assetName : (Uri.tryParse(info.downloadUrl)?.pathSegments.lastOrNull ?? '')).toLowerCase();
    if (_isAndroid()) return name.endsWith('.apk');
    if (_isWindows()) return name.endsWith('.exe') && _installedCopy();
    return false;
  }

  /// Windows: installing closes the app and starts it again
  bool get installRestartsApp => !_isAndroid() && _isWindows();

  /// The ready file, when it belongs to [version]
  DownloadReady? readyFor(String version) {
    final d = download.value;
    return d is DownloadReady && d.version == version ? d : null;
  }

  /// The file of [info] in the updates folder: the release file's name without what a path cannot hold
  String _fileFor(UpdateInfo info) {
    var name = info.assetName.replaceAll(RegExp(r'[^\w.\-]'), '_');
    if (name.isEmpty || name.startsWith('.')) name = 'miki-update-${info.version}.${_isAndroid() ? 'apk' : 'exe'}';
    return '${_dirPath()}${Platform.pathSeparator}$name';
  }

  /// A file kept from an earlier launch is ready while its version is newer; once the app is that version (the update
  /// installed), the file goes
  void _restoreFile() {
    final f = _data['file'];
    if (f is! Map) return;
    final version = '${f['version'] ?? ''}';
    final path = '${f['path'] ?? ''}';
    final size = (f['size'] as num?)?.toInt() ?? -1;
    final file = File(path);
    var exists = false;
    try {
      exists = path.isNotEmpty && file.existsSync() && (size < 0 || file.lengthSync() == size);
    } catch (_) {}
    if (exists && compareVersions(version, currentVersion) > 0) {
      download.value = DownloadReady(version, path);
      return;
    }
    _data.remove('file');
    _persist();
    try {
      if (path.isNotEmpty && file.existsSync()) file.deleteSync();
    } catch (_) {}
  }

  /// Downloads the file of [info] (the same version is not started twice; a ready file is not loaded again).
  /// The progress is in [download]; a broken download continues from where it stopped
  Future<void> startDownload(UpdateInfo info) {
    final cur = download.value;
    if (cur is DownloadRunning && cur.version == info.version) return _downloading ?? Future.value();
    if (cur is DownloadReady && cur.version == info.version && File(cur.path).existsSync()) return Future.value();
    final previous = _downloading;
    _job?.cancel();
    final job = _job = _DownloadJob();
    download.value = DownloadRunning(info.version, 0, info.size);
    late final Future<void> run;
    run = () async {
      // A cancelled download first lets go of its file
      if (previous != null) await previous;
      await _download(info, job);
    }()
        .whenComplete(() {
      if (identical(_job, job)) _job = null;
      if (identical(_downloading, run)) _downloading = null;
    });
    return _downloading = run;
  }

  /// Stops the download (what came stays: the next start continues from there)
  void cancelDownload() {
    final job = _job;
    if (job == null || download.value is! DownloadRunning) return;
    _job = null;
    job.cancel();
    download.value = const DownloadIdle();
  }

  Future<void> _download(UpdateInfo info, _DownloadJob job) async {
    if (job.cancelled) return;
    final file = File(_fileFor(info));
    final part = File('${file.path}.part');
    try {
      await file.parent.create(recursive: true);
      await _sweep(file.parent, keep: {file.path, part.path});
      var from = await part.exists() ? await part.length() : 0;
      if (info.size > 0 && from >= info.size) {
        // A whole (or longer) leftover cannot be trusted to be this version's: load it again
        await part.delete();
        from = 0;
      }
      if (job.cancelled) return;
      download.value = DownloadRunning(info.version, from, info.size);
      var res = await _fetch(info.downloadUrl, from);
      if (res.status == 416 && from > 0) {
        // The server cannot give "the rest": start over
        res.cancel();
        await part.delete();
        from = 0;
        res = await _fetch(info.downloadUrl, 0);
      }
      job.disconnect = res.cancel;
      if (job.cancelled) {
        res.cancel();
        return;
      }
      if (res.status == 200) {
        from = 0; // the whole file came: write it anew
      } else if (res.status != 206 || from == 0) {
        res.cancel();
        throw HttpException('сервер відповів ${res.status}');
      }
      final total = info.size > 0 ? info.size : (res.length >= 0 ? from + res.length : 0);
      var received = from;
      var shown = DateTime.now();
      final sink = part.openWrite(mode: from > 0 ? FileMode.append : FileMode.write);
      try {
        await for (final chunk in res.body.timeout(stallTimeout)) {
          if (job.cancelled) break;
          sink.add(chunk);
          received += chunk.length;
          final now = DateTime.now();
          // A dozen updates a second is plenty for a progress bar
          if (now.difference(shown) >= const Duration(milliseconds: 80)) {
            shown = now;
            download.value = DownloadRunning(info.version, received, total);
          }
        }
      } finally {
        await sink.close();
        if (job.cancelled) res.cancel();
      }
      if (job.cancelled) return;
      download.value = DownloadRunning(info.version, received, total);
      if (info.size > 0 && received != info.size) {
        if (received > info.size) await part.delete();
        throw HttpException(received < info.size ? 'завантаження обірвалося' : 'файл більший, ніж має бути');
      }
      final want = info.digest.trim().toLowerCase();
      if (want.startsWith('sha256:')) {
        final got = await _sha256(part.path);
        if (job.cancelled) return;
        if (got != want.substring(7)) {
          await part.delete();
          throw const FormatException('файл пошкоджено, контрольна сума не збігається');
        }
      }
      if (await file.exists()) await file.delete();
      await part.rename(file.path);
      _data['file'] = {'version': info.version, 'path': file.path, 'size': received};
      _persist();
      AppLog.i('Updater', 'оновлення ${info.version} завантажено (${(received / 1048576).toStringAsFixed(1)} МБ)');
      download.value = DownloadReady(info.version, file.path);
      downloadsDone.value++;
    } catch (e) {
      if (job.cancelled) return;
      AppLog.w('Updater', 'завантаження ${info.version} не вдалося: $e');
      download.value = DownloadFailed(info.version, describeError(e));
    }
  }

  /// A download error in words for the window
  @visibleForTesting
  static String describeError(Object e) => switch (e) {
        SocketException() || HandshakeException() => 'Немає зʼєднання. Спробуйте ще: завантаження продовжиться з того ж місця.',
        TimeoutException() => 'Зʼєднання обірвалося. Спробуйте ще: завантаження продовжиться з того ж місця.',
        HttpException(:final message) when message.contains('обірвалося') =>
          'Завантаження обірвалося. Спробуйте ще: воно продовжиться з того ж місця.',
        HttpException(:final message) => 'Не вдалося завантажити: $message.',
        FormatException(:final message) => 'Не вдалося завантажити: $message. Спробуйте ще раз.',
        FileSystemException() => 'Не вдалося записати файл: забракло місця чи немає доступу до папки.',
        _ => 'Не вдалося завантажити: $e',
      };

  /// Leftovers of other versions in the updates folder go (the files of the version being loaded stay)
  Future<void> _sweep(Directory dir, {required Set<String> keep}) async {
    try {
      await for (final e in dir.list()) {
        if (e is File && !keep.contains(e.path)) await e.delete();
      }
    } catch (_) {}
  }

  /// SHA-256 of a file in a background isolate (36 MB would hold the interface for a few hundred ms)
  static Future<String> _sha256(String path) =>
      Isolate.run(() async => (await sha256.bind(File(path).openRead()).first).toString());

  /// Hands the ready file to the system. On Android the system installer opens (first, if needed, the settings to allow
  /// installing apps from Miki Miki: the install continues when the person comes back); on Windows the setup runs
  /// quietly and the app starts again
  Future<UpdateInstall> install({bool askPermission = true}) async {
    final d = download.value;
    if (d is! DownloadReady) return UpdateInstall.unavailable;
    if (!File(d.path).existsSync()) {
      _data.remove('file');
      _persist();
      download.value = const DownloadIdle();
      return UpdateInstall.unavailable;
    }
    if (_isAndroid()) {
      final r = await _installApk(d.path, askPermission);
      switch (r) {
        case 'started':
          download.value = DownloadReady(d.version, d.path);
          return UpdateInstall.started;
        case 'permission':
          download.value = DownloadReady(d.version, d.path, waitingPermission: true);
          _nextResume(() {
            final now = download.value;
            if (now is DownloadReady && now.waitingPermission && now.version == d.version) unawaited(install(askPermission: false));
          });
          return UpdateInstall.needsPermission;
        case 'denied':
          download.value = DownloadReady(d.version, d.path,
              error: 'Android не дозволив встановлення. Увімкніть «Дозволити з цього джерела» для Miki Miki й натисніть «Встановити» ще раз.');
          return UpdateInstall.needsPermission;
        default:
          AppLog.w('Updater', 'інсталятор не відкрився: $r');
          download.value = DownloadReady(d.version, d.path, error: 'Системний інсталятор не відкрився. Спробуйте ще раз або завантажте файл зі сторінки релізу.');
          return UpdateInstall.failed;
      }
    }
    if (_isWindows()) {
      final ok = await _runSetup(d.path);
      if (!ok) download.value = DownloadReady(d.version, d.path, error: 'Інсталятор не запустився. Спробуйте ще раз або завантажте його зі сторінки релізу.');
      return ok ? UpdateInstall.started : UpdateInstall.failed;
    }
    return UpdateInstall.unavailable;
  }

  /// The PowerShell line that installs quietly, waits and starts the app again (the app itself exits so the setup can
  /// replace its files). Quotes in paths are doubled for PowerShell
  @visibleForTesting
  static String windowsScript(String setup, String exe) {
    String q(String s) => "'${s.replaceAll("'", "''")}'";
    return "Start-Process -FilePath ${q(setup)} -ArgumentList '/SILENT','/SP-','/SUPPRESSMSGBOXES','/NORESTART','/CLOSEAPPLICATIONS' -Wait; "
        'Start-Process -FilePath ${q(exe)}';
  }

  /// Windows: the installed copy updates quietly in place (the setup finds it by its AppId), then starts again
  static Future<bool> _runWindowsSetup(String setup) async {
    try {
      final exe = Platform.resolvedExecutable;
      await Process.start(
        'powershell.exe',
        ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-Command', windowsScript(setup, exe)],
        mode: ProcessStartMode.detached,
      );
      AppLog.i('Updater', 'запущено тихе встановлення; застосунок закривається');
      await StorageService.flush();
      await AppLog.instance.shutdown();
      // A moment for the window to say what is happening; then the files must be free for the setup
      await Future<void>.delayed(const Duration(milliseconds: 900));
      exit(0);
    } catch (e) {
      AppLog.w('Updater', 'інсталятор не запустився: $e');
      return false;
    }
  }
}

/// One download run: cancelling it breaks the connection
class _DownloadJob {
  bool cancelled = false;
  void Function()? disconnect;

  void cancel() {
    cancelled = true;
    disconnect?.call();
  }
}
