/// HLS media playlists for downloads: the segments with their keys and init sections, and the local playlist that
/// plays the downloaded copy. Pure Dart, no network.
library;

/// An `#EXT-X-KEY`: how the following segments are encrypted
class HlsKey {
  /// `NONE`, `AES-128`, `SAMPLE-AES` …
  final String method;
  final Uri? uri;

  /// The initialization vector as written (`0x…`); without it the segment's sequence number is the IV
  final String? iv;
  final String? keyFormat;

  const HlsKey(this.method, {this.uri, this.iv, this.keyFormat});

  bool get isNone => method.toUpperCase() == 'NONE';

  /// AES-128 of whole segments: ffmpeg decrypts it while playing (the key lies next to the segments)
  bool get isAes128 => method.toUpperCase() == 'AES-128';
}

/// An `#EXT-X-MAP` (fMP4 init section)
class HlsMap {
  final Uri uri;
  final int? offset;
  final int? length;

  const HlsMap(this.uri, {this.offset, this.length});

  String get id => '$uri|$offset|$length';
}

class HlsSegment {
  final Uri uri;
  final double duration;

  /// Absolute media sequence number (the IV of AES-128 without an explicit one)
  final int sequence;

  /// `#EXT-X-BYTERANGE`: part of [uri]
  final int? offset;
  final int? length;
  final HlsKey? key;
  final HlsMap? map;
  final bool discontinuity;

  const HlsSegment(this.uri, this.duration, this.sequence,
      {this.offset, this.length, this.key, this.map, this.discontinuity = false});
}

class HlsMedia {
  final List<HlsSegment> segments;
  final int targetDuration;

  /// `#EXT-X-ENDLIST`: a finished (video-on-demand) playlist; a live one cannot be downloaded
  final bool ended;

  const HlsMedia(this.segments, {required this.targetDuration, required this.ended});

  double get duration => segments.fold(0.0, (a, s) => a + s.duration);

  /// Distinct keys that need a file (AES-128 with an address), in order of appearance
  List<HlsKey> get keys {
    final seen = <String>{};
    return [
      for (final s in segments)
        if (s.key != null && s.key!.isAes128 && s.key!.uri != null && seen.add(s.key!.uri.toString())) s.key!,
    ];
  }

  /// Distinct init sections, in order of appearance
  List<HlsMap> get maps {
    final seen = <String>{};
    return [for (final s in segments) if (s.map != null && seen.add(s.map!.id)) s.map!];
  }

  /// Encryption the app cannot keep playable (SAMPLE-AES and DRM key systems); `null` when everything is fine
  String? get unsupportedEncryption {
    for (final s in segments) {
      final k = s.key;
      if (k == null || k.isNone || k.isAes128 && (k.keyFormat == null || k.keyFormat == 'identity')) continue;
      return k.method;
    }
    return null;
  }
}

Map<String, String> _attributes(String s) {
  final out = <String, String>{};
  var i = 0;
  while (i < s.length) {
    while (i < s.length && (s[i] == ',' || s[i] == ' ')) {
      i++;
    }
    final eq = s.indexOf('=', i);
    if (eq < 0) break;
    final key = s.substring(i, eq).trim().toUpperCase();
    i = eq + 1;
    String value;
    if (i < s.length && s[i] == '"') {
      final end = s.indexOf('"', i + 1);
      value = end < 0 ? s.substring(i + 1) : s.substring(i + 1, end);
      i = end < 0 ? s.length : end + 1;
    } else {
      final end = s.indexOf(',', i);
      value = (end < 0 ? s.substring(i) : s.substring(i, end)).trim();
      i = end < 0 ? s.length : end + 1;
    }
    if (key.isNotEmpty) out[key] = value;
  }
  return out;
}

/// `len@offset` (the offset may be missing: right after the previous range of the same address)
(int length, int? offset)? _byteRange(String v) {
  final parts = v.split('@');
  final len = int.tryParse(parts.first.trim());
  if (len == null) return null;
  return (len, parts.length > 1 ? int.tryParse(parts[1].trim()) : null);
}

/// A media playlist (segments). `null` when [text] is not one (a master playlist or not HLS at all)
HlsMedia? parseHlsMedia(String text, Uri base) {
  if (!text.contains('#EXTM3U') || text.contains('#EXT-X-STREAM-INF')) return null;
  final segments = <HlsSegment>[];
  var target = 0;
  var sequence = 0;
  var ended = false;
  double? duration;
  (int, int?)? range;
  HlsKey? key;
  HlsMap? map;
  var discontinuity = false;
  final rangeEnds = <String, int>{};
  for (final raw in text.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('#')) {
      final colon = line.indexOf(':');
      final tag = colon < 0 ? line : line.substring(0, colon);
      final value = colon < 0 ? '' : line.substring(colon + 1);
      switch (tag) {
        case '#EXT-X-TARGETDURATION':
          target = int.tryParse(value.trim()) ?? double.tryParse(value.trim())?.ceil() ?? 0;
        case '#EXT-X-MEDIA-SEQUENCE':
          sequence = int.tryParse(value.trim()) ?? 0;
        case '#EXTINF':
          duration = double.tryParse(value.split(',').first.trim()) ?? 0;
        case '#EXT-X-BYTERANGE':
          range = _byteRange(value);
        case '#EXT-X-KEY':
          final a = _attributes(value);
          final method = a['METHOD'] ?? 'NONE';
          final uri = a['URI'];
          key = method.toUpperCase() == 'NONE'
              ? null
              : HlsKey(method, uri: uri == null || uri.isEmpty ? null : base.resolve(uri), iv: a['IV'], keyFormat: a['KEYFORMAT']);
        case '#EXT-X-MAP':
          final a = _attributes(value);
          final uri = a['URI'];
          final r = a['BYTERANGE'] == null ? null : _byteRange(a['BYTERANGE']!);
          map = uri == null || uri.isEmpty ? null : HlsMap(base.resolve(uri), length: r?.$1, offset: r?.$2 ?? (r == null ? null : 0));
        case '#EXT-X-DISCONTINUITY':
          discontinuity = true;
        case '#EXT-X-ENDLIST':
          ended = true;
      }
      continue;
    }
    // An address: the segment the preceding tags describe
    final uri = base.resolve(line);
    int? offset;
    int? length;
    final r = range;
    if (r != null) {
      length = r.$1;
      offset = r.$2 ?? rangeEnds[uri.toString()] ?? 0;
      rangeEnds[uri.toString()] = offset + length;
    }
    segments.add(HlsSegment(uri, duration ?? 0, sequence + segments.length,
        offset: offset, length: length, key: key, map: map, discontinuity: discontinuity));
    duration = null;
    range = null;
    discontinuity = false;
  }
  if (segments.isEmpty) return null;
  return HlsMedia(segments, targetDuration: target, ended: ended);
}

/// The IV of AES-128 for [s] as `#EXT-X-KEY` writes it: the explicit one, otherwise the sequence number as 128 bits.
/// The local playlist numbers segments anew, so the implicit IV must be written out
String hlsIv(HlsSegment s) => s.key?.iv ?? '0x${s.sequence.toRadixString(16).padLeft(32, '0')}';

/// The playlist of the downloaded copy: the same segments, keys and init sections under local file names, numbered
/// from 0, finished (`#EXT-X-ENDLIST`). [segmentFile] gives the file of segment i (relative to the playlist).
/// Keys lie in `key_N.bin`: ffmpeg opens such a local file only with `allowed_extensions=ALL`, which media_kit puts
/// into `demuxer-lavf-o` itself (checked with mpv: AES-128 with explicit and implicit IVs and fMP4 play to the end)
String buildLocalPlaylist(
  HlsMedia media, {
  required String Function(int index) segmentFile,
  String Function(int keyIndex)? keyFile,
  String Function(int mapIndex)? mapFile,
}) {
  final keys = media.keys;
  final maps = media.maps;
  final hasMap = maps.isNotEmpty;
  var target = media.targetDuration;
  for (final s in media.segments) {
    if (s.duration.ceil() > target) target = s.duration.ceil();
  }
  final out = StringBuffer()
    ..writeln('#EXTM3U')
    ..writeln('#EXT-X-VERSION:${hasMap ? 7 : 3}')
    ..writeln('#EXT-X-TARGETDURATION:${target < 1 ? 1 : target}')
    ..writeln('#EXT-X-MEDIA-SEQUENCE:0')
    ..writeln('#EXT-X-PLAYLIST-TYPE:VOD');
  String? lastKey;
  String? lastMap;
  for (var i = 0; i < media.segments.length; i++) {
    final s = media.segments[i];
    if (s.discontinuity && i > 0) out.writeln('#EXT-X-DISCONTINUITY');
    final m = s.map;
    if (m != null && m.id != lastMap) {
      final mi = maps.indexWhere((x) => x.id == m.id);
      out.writeln('#EXT-X-MAP:URI="${mapFile == null ? 'init_$mi.mp4' : mapFile(mi)}"');
      lastMap = m.id;
    }
    final k = s.key;
    final keyLine = k == null || !k.isAes128 || k.uri == null
        ? '#EXT-X-KEY:METHOD=NONE'
        : '#EXT-X-KEY:METHOD=AES-128,URI="${keyFile == null ? 'key_${keys.indexWhere((x) => x.uri == k.uri)}.bin' : keyFile(keys.indexWhere((x) => x.uri == k.uri))}",IV=${hlsIv(s)}';
    // An explicit IV changes with every segment when it is implicit: the line repeats then
    if (keyLine != lastKey && !(lastKey == null && keyLine == '#EXT-X-KEY:METHOD=NONE')) {
      out.writeln(keyLine);
      lastKey = keyLine;
    }
    out
      ..writeln('#EXTINF:${s.duration.toStringAsFixed(3)},')
      ..writeln(segmentFile(i));
  }
  out.writeln('#EXT-X-ENDLIST');
  return out.toString();
}

/// The extension of segment files by their address (`.ts` by default; `.m4s` / `.mp4` for fMP4, `.aac` …)
String segmentExtension(Uri uri, {bool fmp4 = false}) {
  final path = uri.path.toLowerCase();
  final dot = path.lastIndexOf('.');
  final ext = dot < 0 || dot < path.lastIndexOf('/') ? '' : path.substring(dot + 1);
  const known = {'ts', 'm4s', 'mp4', 'm4a', 'm4v', 'aac', 'mp3', 'ac3', 'ec3', 'vtt', 'webvtt'};
  if (known.contains(ext)) return ext;
  return fmp4 ? 'm4s' : 'ts';
}
