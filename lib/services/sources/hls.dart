/// Розбір майстер-плейлиста HLS (m3u8): варіанти якості й додаткові доріжки (EXT-X-MEDIA).
/// Чиста Dart-логіка. Аналог того, що UAKino робить у Aniyomi підрядковими пошуками, але повноцінно:
/// з лапками в атрибутах, відносними адресами та без залежності від порядку атрибутів.
library;

import '../../models/source_models.dart';

class HlsVariant {
  final Uri url;
  final int? bandwidth;
  final int? width;
  final int? height;
  final String? codecs;
  final String? audioGroup;

  const HlsVariant(this.url, {this.bandwidth, this.width, this.height, this.codecs, this.audioGroup});
}

class HlsRendition {
  /// AUDIO / SUBTITLES / VIDEO / CLOSED-CAPTIONS
  final String type;
  final String groupId;
  final String name;
  final String? language;
  final Uri? uri;
  final bool isDefault;

  const HlsRendition(this.type, this.groupId, this.name, {this.language, this.uri, this.isDefault = false});
}

class HlsMaster {
  final List<HlsVariant> variants;
  final List<HlsRendition> renditions;

  const HlsMaster(this.variants, this.renditions);
}

/// Атрибути рядка `#EXT-X-…:KEY=VALUE,KEY="a,b"` → мапа (лапки знімаються)
Map<String, String> parseHlsAttributes(String s) {
  final out = <String, String>{};
  var i = 0;
  while (i < s.length) {
    while (i < s.length && (s[i] == ',' || s[i] == ' ')) {
      i++;
    }
    final eq = s.indexOf('=', i);
    if (eq < 0) break;
    final key = s.substring(i, eq).trim();
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
    if (key.isNotEmpty) out[key.toUpperCase()] = value;
  }
  return out;
}

/// Розбирає майстер-плейлист. `null` — це не m3u8 або у ньому немає варіантів (тоді це «медіа-плейлист»).
HlsMaster? parseHlsMaster(String text, Uri base) {
  if (!text.contains('#EXTM3U')) return null;
  final lines = text.split(RegExp(r'\r?\n'));
  final variants = <HlsVariant>[];
  final renditions = <HlsRendition>[];
  for (int i = 0; i < lines.length; i++) {
    final line = lines[i].trim();
    if (line.startsWith('#EXT-X-STREAM-INF:')) {
      final attrs = parseHlsAttributes(line.substring('#EXT-X-STREAM-INF:'.length));
      // адреса — наступний непорожній рядок, що не є тегом
      String? uri;
      for (int j = i + 1; j < lines.length; j++) {
        final next = lines[j].trim();
        if (next.isEmpty) continue;
        if (next.startsWith('#')) {
          if (next.startsWith('#EXT-X-STREAM-INF')) break;
          continue;
        }
        uri = next;
        i = j;
        break;
      }
      if (uri == null || uri.isEmpty) continue;
      final res = attrs['RESOLUTION']?.split(RegExp('[xX]'));
      variants.add(HlsVariant(
        base.resolve(uri),
        bandwidth: int.tryParse(attrs['BANDWIDTH'] ?? '') ?? int.tryParse(attrs['AVERAGE-BANDWIDTH'] ?? ''),
        width: res != null && res.length == 2 ? int.tryParse(res[0]) : null,
        height: res != null && res.length == 2 ? int.tryParse(res[1]) : null,
        codecs: attrs['CODECS'],
        audioGroup: attrs['AUDIO'],
      ));
    } else if (line.startsWith('#EXT-X-MEDIA:')) {
      final a = parseHlsAttributes(line.substring('#EXT-X-MEDIA:'.length));
      final uri = a['URI'];
      renditions.add(HlsRendition(
        a['TYPE'] ?? '',
        a['GROUP-ID'] ?? '',
        a['NAME'] ?? '',
        language: a['LANGUAGE'],
        uri: uri == null || uri.isEmpty ? null : base.resolve(uri),
        isDefault: (a['DEFAULT'] ?? '').toUpperCase() == 'YES',
      ));
    }
  }
  if (variants.isEmpty) return null;
  return HlsMaster(variants, renditions);
}

/// Варіанти якості → список `Video` (найкраща якість першою). Спершу — «Авто» (сам майстер-плейлист:
/// лишає вибір доріжок і якості за mpv), якщо `withAuto`.
List<Video> videosFromHls(HlsMaster master, Uri masterUrl, {Map<String, String> headers = const {}, bool withAuto = true}) {
  final sorted = [...master.variants]..sort((a, b) {
      final h = (b.height ?? 0).compareTo(a.height ?? 0);
      return h != 0 ? h : (b.bandwidth ?? 0).compareTo(a.bandwidth ?? 0);
    });
  final out = <Video>[];
  if (withAuto) out.add(Video(url: masterUrl.toString(), title: 'Авто', headers: headers));
  final seen = <int?, int>{};
  for (final v in sorted) {
    seen[v.height] = (seen[v.height] ?? 0) + 1;
  }
  for (final v in sorted) {
    final base = v.height != null ? '${v.height}p' : (v.bandwidth != null ? '${(v.bandwidth! / 1000).round()} кбіт/с' : 'Відео');
    final dup = seen[v.height]! > 1 && v.bandwidth != null ? ' · ${(v.bandwidth! / 1000).round()} кбіт/с' : '';
    out.add(Video(url: v.url.toString(), title: '$base$dup', resolution: v.height, bitrate: v.bandwidth, headers: headers));
  }
  return out;
}
