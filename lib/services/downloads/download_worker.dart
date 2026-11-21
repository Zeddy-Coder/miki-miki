/// Downloads one episode into its folder: an HLS stream as its segments (with keys and init sections) plus a local
/// playlist, or a plain video file; subtitles and separate audio tracks next to it. Resumes what is already on disk,
/// asks the source for a fresh link when the old one expires. The network and the source are injected (tests).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../models/source_models.dart';
import '../sources/hls.dart';
import '../sources/hls_proxy.dart';
import 'download_models.dart';
import 'hls_media.dart';

/// One HTTP answer: the status, the body's length (-1: unknown), the body and a way to drop the connection
class FetchResponse {
  final int status;
  final int length;
  final Stream<List<int>> body;
  final void Function() cancel;

  const FetchResponse(this.status, this.length, this.body, this.cancel);
}

/// GET [url]; [offset] / [length] ask for a byte range (`length` null: to the end)
typedef DownloadFetch = Future<FetchResponse> Function(Uri url, Map<String, String> headers, {int? offset, int? length});

/// A fresh playable video of the episode and the player it came from (links of sites expire within hours)
class ResolvedVideo {
  final Video video;
  final String hoster;

  const ResolvedVideo(this.video, this.hoster);
}

typedef VideoResolver = Future<ResolvedVideo> Function(DownloadItem item);

/// Why a download stopped, in words for the person. [network]: no connection (the download waits and goes on later)
class DownloadFailure implements Exception {
  final String message;
  final bool network;
  final bool noSpace;

  const DownloadFailure(this.message, {this.network = false, this.noSpace = false});

  @override
  String toString() => message;
}

/// The person paused or removed the download
class DownloadCancelled implements Exception {
  const DownloadCancelled();
}

/// The link expired (the server refuses it): a new one is asked from the source
class _Expired implements Exception {
  final int status;
  const _Expired(this.status);
}

/// Stops a running download: drops its connections
class DownloadCancel {
  bool _cancelled = false;
  final Set<void Function()> _open = {};

  bool get cancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final c in [..._open]) {
      c();
    }
    _open.clear();
  }

  void _check() {
    if (_cancelled) throw const DownloadCancelled();
  }
}

class DownloadWorker {
  final DownloadItem item;

  /// The episode's folder
  final Directory dir;
  final DownloadFetch fetch;
  final VideoResolver resolve;

  /// The item with new progress (after every part)
  final void Function(DownloadItem item) onProgress;
  final DownloadCancel cancel;

  /// Segments fetched at once
  final int parallel;

  /// Tries of one part before the download fails
  final int retries;
  final Duration retryDelay;

  DownloadWorker({
    required this.item,
    required this.dir,
    required this.fetch,
    required this.resolve,
    required this.onProgress,
    DownloadCancel? cancel,
    this.parallel = 4,
    this.retries = 3,
    this.retryDelay = const Duration(seconds: 2),
  }) : cancel = cancel ?? DownloadCancel();

  late DownloadItem _it = item;

  /// A part failed: the other lanes stop at once instead of fetching on
  Object? _halt;

  void _checkGo() {
    cancel._check();
    final h = _halt;
    if (h != null) throw h;
  }

  /// Downloads everything; returns the finished item (state [DownloadState.done])
  Future<DownloadItem> run() async {
    await dir.create(recursive: true);
    for (var attempt = 0;; attempt++) {
      cancel._check();
      final ResolvedVideo rv;
      try {
        rv = await resolve(_it);
      } on DownloadFailure {
        rethrow;
      } on SocketException {
        throw const DownloadFailure('Немає зʼєднання', network: true);
      } catch (e) {
        throw DownloadFailure('Сайт не дав посилання на серію: $e');
      }
      cancel._check();
      final video = _direct(rv.video);
      final headers = {...HlsProxy.browserDefaults, ...video.headers};
      _it = _it.copyWith(hoster: rv.hoster, quality: _qualityLabel(video), timestamps: video.timestamps);
      try {
        final url = Uri.parse(video.url);
        String file;
        double duration = 0;
        if (await _isHls(url, headers)) {
          duration = await _hls(url, headers, '');
          file = 'index.m3u8';
        } else {
          file = await _file(url, headers, 'video', main: true);
        }
        final subs = await _subtitles(video.subtitleTracks, headers);
        final audio = await _audio(video.audioTracks, headers);
        final size = await _folderSize(dir);
        _it = _it.copyWith(
          state: DownloadState.done,
          clearError: true,
          file: file,
          duration: duration > 0 ? duration : null,
          subtitles: subs,
          audio: audio,
          bytes: size,
          totalBytes: size,
          doneAt: DateTime.now(),
        );
        await File('${dir.path}/episode.json').writeAsString(jsonEncode(_it.toJson()));
        return _it;
      } on _Expired catch (e) {
        if (attempt >= 2) throw DownloadFailure('Сервер не віддає відео (відповідь ${e.status}). Спробуйте пізніше або інший плеєр');
        // A new link: the parts already on disk stay (the same quality gives the same segments)
        continue;
      } on FileSystemException catch (e) {
        final code = e.osError?.errorCode;
        // ENOSPC (Linux, Android), ERROR_DISK_FULL / ERROR_HANDLE_DISK_FULL (Windows)
        if (code == 28 || code == 112 || code == 39) throw const DownloadFailure('Замало місця на пристрої', noSpace: true);
        throw DownloadFailure('Не вдалося записати файл: ${e.osError?.message ?? e.message}');
      }
    }
  }

  /// On Android Moon's video comes wrapped in the local proxy for the player: the download goes to the original
  Video _direct(Video v) {
    final original = HlsProxy.instance.original(v.url);
    return original == null ? v : v.copyWith(url: original.$1, headers: original.$2);
  }

  static String _qualityLabel(Video v) => v.resolution != null ? '${v.resolution}p' : (v.title == 'Авто' ? '' : v.title);

  // ── HTTP ──────────────────────────────────────────────────────────────────

  static Future<int> _folderSize(Directory d) async {
    var total = 0;
    await for (final e in d.list(recursive: true)) {
      if (e is File && !e.path.endsWith('.part')) total += await e.length();
    }
    return total;
  }

  Future<FetchResponse> _get(Uri url, Map<String, String> headers, {int? offset, int? length}) async {
    _checkGo();
    final FetchResponse res;
    try {
      res = await fetch(url, headers, offset: offset, length: length);
    } on SocketException {
      throw const DownloadFailure('Немає зʼєднання', network: true);
    } on TimeoutException {
      throw const DownloadFailure('Сервер не відповідає', network: true);
    } on HttpException catch (e) {
      throw DownloadFailure('Зʼєднання обірвалося: ${e.message}', network: true);
    } on TlsException catch (e) {
      throw DownloadFailure('Не вдалося встановити захищене зʼєднання з сервером (${e.message})');
    }
    if (res.status == 401 || res.status == 403 || res.status == 404 || res.status == 410) {
      res.cancel();
      throw _Expired(res.status);
    }
    if (res.status >= 400) {
      res.cancel();
      throw DownloadFailure('Сервер відповів ${res.status}');
    }
    return res;
  }

  Future<List<int>> _bytes(Uri url, Map<String, String> headers, {int? offset, int? length}) async {
    final res = await _get(url, headers, offset: offset, length: length);
    cancel._open.add(res.cancel);
    try {
      final out = <int>[];
      await for (final chunk in res.body.timeout(const Duration(seconds: 30))) {
        _checkGo();
        out.addAll(chunk);
      }
      // A server without ranges sends the whole file: the needed part is cut out
      if (offset != null && res.status == 200 && out.length > offset) {
        final end = length == null ? out.length : (offset + length).clamp(0, out.length);
        return out.sublist(offset, end);
      }
      return out;
    } on TimeoutException {
      throw const DownloadFailure('Зʼєднання завмерло', network: true);
    } on SocketException {
      throw const DownloadFailure('Немає зʼєднання', network: true);
    } on HttpException catch (e) {
      throw DownloadFailure('Зʼєднання обірвалося: ${e.message}', network: true);
    } finally {
      cancel._open.remove(res.cancel);
    }
  }

  Future<String> _text(Uri url, Map<String, String> headers) async => utf8.decode(await _bytes(url, headers), allowMalformed: true);

  /// One part with a few tries: a dropped connection or a slow server happen during long downloads
  Future<T> _retry<T>(Future<T> Function() run) async {
    for (var i = 0;; i++) {
      try {
        return await run();
      } on DownloadFailure catch (e) {
        if (!e.network || i >= retries || _halt != null) rethrow;
      }
      _checkGo();
      await Future<void>.delayed(retryDelay * (i + 1));
      _checkGo();
    }
  }

  Future<bool> _isHls(Uri url, Map<String, String> headers) async {
    if (url.path.toLowerCase().endsWith('.m3u8')) return true;
    if (url.path.toLowerCase().endsWith('.mp4') || url.path.toLowerCase().endsWith('.mkv')) return false;
    final head = await _retry(() => _bytes(url, headers, offset: 0, length: 16));
    return utf8.decode(head, allowMalformed: true).startsWith('#EXTM3U');
  }

  // ── HLS ───────────────────────────────────────────────────────────────────

  /// The variant closest to the wanted height (not above it; the lowest of the higher ones when there is none)
  static HlsVariant pickVariant(List<HlsVariant> variants, int height) {
    final sorted = [...variants]..sort((a, b) {
        final h = (b.height ?? 0).compareTo(a.height ?? 0);
        return h != 0 ? h : (b.bandwidth ?? 0).compareTo(a.bandwidth ?? 0);
      });
    if (height <= 0) return sorted.first;
    for (final v in sorted) {
      if ((v.height ?? 0) <= height) return v;
    }
    return sorted.last;
  }

  /// Downloads a stream into [sub] (relative to [dir]: '' — the episode's folder); returns its duration
  Future<double> _hls(Uri url, Map<String, String> headers, String sub) async {
    final folder = sub.isEmpty ? dir.path : '${dir.path}/$sub';
    await Directory(folder).create(recursive: true);
    var mediaUrl = url;
    var text = await _retry(() => _text(url, headers));
    final master = parseHlsMaster(text, url);
    if (master != null) {
      final v = pickVariant(master.variants, _it.height);
      mediaUrl = v.url;
      if (sub.isEmpty) _it = _it.copyWith(quality: v.height != null ? '${v.height}p' : _it.quality);
      text = await _retry(() => _text(mediaUrl, headers));
    }
    final media = parseHlsMedia(text, mediaUrl);
    if (media == null) throw const DownloadFailure('Сайт віддав не відео, а щось інше');
    if (!media.ended) throw const DownloadFailure('Це пряма трансляція: її не завантажити');
    final enc = media.unsupportedEncryption;
    if (enc != null) throw DownloadFailure('Відео захищене ($enc), завантажити його не вийде');

    final keys = media.keys;
    for (var i = 0; i < keys.length; i++) {
      final f = File('$folder/key_$i.bin');
      if (!await f.exists()) await f.writeAsBytes(await _retry(() => _bytes(keys[i].uri!, headers)));
    }
    final maps = media.maps;
    for (var i = 0; i < maps.length; i++) {
      final f = File('$folder/init_$i.mp4');
      if (!await f.exists()) {
        await f.writeAsBytes(await _retry(() => _bytes(maps[i].uri, headers, offset: maps[i].offset, length: maps[i].length)));
      }
    }

    final segs = media.segments;
    final ext = segmentExtension(segs.first.uri, fmp4: maps.isNotEmpty);
    String name(int i) => 'seg_${i.toString().padLeft(5, '0')}.$ext';
    final main = sub.isEmpty;
    if (main) {
      // Another set of segments than the parts on disk (a different quality came): the old ones go
      if (_it.parts > 0 && _it.parts != segs.length) await _clearSegments(folder);
      var done = 0;
      var bytes = 0;
      for (var i = 0; i < segs.length; i++) {
        final f = File('$folder/${name(i)}');
        if (await f.exists()) {
          done++;
          bytes += await f.length();
        }
      }
      _it = _it.copyWith(parts: segs.length, partsDone: done, bytes: bytes, totalBytes: _estimate(bytes, done, segs.length));
      onProgress(_it);
    }

    var next = 0;
    Future<void> lane() async {
      while (_halt == null) {
        final i = next++;
        if (i >= segs.length) return;
        final f = File('$folder/${name(i)}');
        if (await f.exists()) continue;
        final s = segs[i];
        final data = await _retry(() => _bytes(s.uri, headers, offset: s.offset, length: s.length));
        _checkGo();
        final part = File('${f.path}.part');
        await part.writeAsBytes(data, flush: true);
        await part.rename(f.path);
        final partsDone = (main ? _it.partsDone : 0) + 1;
        _it = _it.copyWith(
          bytes: _it.bytes + data.length,
          partsDone: main ? partsDone : null,
          totalBytes: main ? _estimate(_it.bytes + data.length, partsDone, segs.length) : null,
        );
        onProgress(_it);
      }
    }

    Object? first;
    await Future.wait([
      for (var l = 0; l < parallel; l++)
        lane().catchError((Object e) {
          // One lane failed: the others stop and drop their connections; the first reason is reported
          if (first == null) {
            first = e;
            _halt = e;
            for (final c in [...cancel._open]) {
              c();
            }
          }
        }),
    ]);
    _halt = null;
    final failed = first;
    if (failed != null) throw failed;
    await File('$folder/index.m3u8').writeAsString(buildLocalPlaylist(media, segmentFile: name));
    return media.duration;
  }

  static int _estimate(int bytes, int done, int total) => done <= 0 ? 0 : (bytes / done * total).round();

  Future<void> _clearSegments(String folder) async {
    await for (final e in Directory(folder).list()) {
      if (e is File && RegExp(r'seg_\d+\.\w+(\.part)?$').hasMatch(e.path)) await e.delete();
    }
  }

  // ── A plain file ──────────────────────────────────────────────────────────

  /// Downloads [url] into `<base>.<ext>` (resuming a `.part`); returns the file name. [main]: the episode's video
  /// (its progress is the download's progress)
  Future<String> _file(Uri url, Map<String, String> headers, String base, {bool main = false}) async {
    var ext = url.path.contains('.') ? url.path.substring(url.path.lastIndexOf('.') + 1).toLowerCase() : 'mp4';
    if (ext.length > 4 || ext.contains('/')) ext = 'mp4';
    final name = '$base.$ext';
    final file = File('${dir.path}/$name');
    if (await file.exists()) return name;
    final part = File('${file.path}.part');
    await _retry(() async {
      final from = await part.exists() ? await part.length() : 0;
      final res = await _get(url, headers, offset: from > 0 ? from : null);
      cancel._open.add(res.cancel);
      final append = from > 0 && res.status == 206;
      final total = res.length >= 0 ? (append ? from + res.length : res.length) : 0;
      final sink = part.openWrite(mode: append ? FileMode.append : FileMode.write);
      var got = append ? from : 0;
      var shown = DateTime.now();
      final before = main ? 0 : _it.bytes;
      try {
        await for (final chunk in res.body.timeout(const Duration(seconds: 30))) {
          _checkGo();
          sink.add(chunk);
          got += chunk.length;
          final now = DateTime.now();
          if (main && now.difference(shown) >= const Duration(milliseconds: 250)) {
            shown = now;
            _it = _it.copyWith(bytes: before + got, totalBytes: total);
            onProgress(_it);
          }
        }
      } on TimeoutException {
        throw const DownloadFailure('Зʼєднання завмерло', network: true);
      } on SocketException {
        throw const DownloadFailure('Немає зʼєднання', network: true);
      } on HttpException catch (e) {
        throw DownloadFailure('Зʼєднання обірвалося: ${e.message}', network: true);
      } finally {
        cancel._open.remove(res.cancel);
        await sink.close();
      }
      if (total > 0 && got < total) throw const DownloadFailure('Завантаження обірвалося', network: true);
      _it = _it.copyWith(bytes: before + got, totalBytes: main ? (total > 0 ? total : got) : null);
      onProgress(_it);
    });
    await part.rename(file.path);
    return name;
  }

  // ── Subtitles and audio ───────────────────────────────────────────────────

  Future<List<DownloadTrack>> _subtitles(List<Track> tracks, Map<String, String> headers) async {
    final out = <DownloadTrack>[];
    for (var i = 0; i < tracks.length; i++) {
      final t = tracks[i];
      try {
        final uri = Uri.parse(t.url);
        final data = await _retry(() => _bytes(uri, headers));
        final head = utf8.decode(data.take(64).toList(), allowMalformed: true).trimLeft();
        final byName = uri.path.toLowerCase();
        final ext = head.startsWith('WEBVTT')
            ? 'vtt'
            : head.startsWith('[Script Info]')
                ? 'ass'
                : RegExp(r'\.(ass|ssa|srt|vtt)$').firstMatch(byName)?.group(1) ?? 'srt';
        final name = 'sub_$i.$ext';
        await File('${dir.path}/$name').writeAsBytes(data);
        out.add(DownloadTrack(name, t.lang));
      } on DownloadCancelled {
        rethrow;
      } catch (_) {
        // A missing subtitle file does not spoil the episode
      }
    }
    return out;
  }

  Future<List<DownloadTrack>> _audio(List<Track> tracks, Map<String, String> headers) async {
    final out = <DownloadTrack>[];
    for (var i = 0; i < tracks.length; i++) {
      final uri = Uri.parse(tracks[i].url);
      if (uri.path.toLowerCase().endsWith('.m3u8')) {
        await _hls(uri, headers, 'audio_$i');
        out.add(DownloadTrack('audio_$i/index.m3u8', tracks[i].lang));
      } else {
        out.add(DownloadTrack(await _file(uri, headers, 'audio_$i'), tracks[i].lang));
      }
    }
    return out;
  }

  // ── The real network ──────────────────────────────────────────────────────

  static HttpClient? _client;

  /// `dart:io` with the headers sites and CDNs expect (Range for parts)
  static Future<FetchResponse> httpFetch(Uri url, Map<String, String> headers, {int? offset, int? length}) async {
    final client = _client ??= HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..idleTimeout = const Duration(seconds: 30)
      ..autoUncompress = false;
    final req = await client.getUrl(url).timeout(const Duration(seconds: 20));
    headers.forEach(req.headers.set);
    req.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
    if (offset != null) req.headers.set(HttpHeaders.rangeHeader, 'bytes=$offset-${length == null ? '' : offset + length - 1}');
    final res = await req.close().timeout(const Duration(seconds: 30));
    return FetchResponse(res.statusCode, res.contentLength, res, () => req.abort());
  }
}
