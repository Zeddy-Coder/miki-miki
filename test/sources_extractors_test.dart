import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:miki_miki/models/source_models.dart';
import 'package:miki_miki/services/source_prefs.dart';
import 'package:miki_miki/services/sources/extractors.dart';
import 'package:miki_miki/services/sources/hls.dart';
import 'package:miki_miki/services/sources/source_http.dart';

String fx(String name) => File('test/data/sources/$name').readAsStringSync();

void main() {
  // Без вбудованого ключа: тести не залежать від того, що лежить у застосунку

  group('Moon', () {
    test('розбір сторінки плеєра: посилання на відео з двох шарів кодування', () {
      final page = MoonExtractor.parsePage(fx('moon_iframe.html'));
      expect(page.video, startsWith('https://s.moonanime.net/content/stream/anime/51/ne17f39gtidf642/hls/'));
      expect(page.video, contains('manifest.m3u8'));
      expect(page.subtitle, '');
      expect(page.skips, isEmpty);
    });

    test('шаблон PlayerJS: file: f("…") і таймкоди з __skipCtx', () {
      final page = MoonExtractor.parsePage(fx('moon_playerjs.html'));
      expect(page.video, startsWith('https://s.moonanime.net/content/stream/anime/51/vp3fbhr2xrf1/hls/'));
      expect(page.video, contains('hls:manifest.m3u8'));
      expect(page.subtitle, '');
      expect(page.skips.map((s) => s.type), [ChapterType.opening, ChapterType.ending]);
      expect(page.skips.first.start, closeTo(63.31, 0.001));
      expect(page.skips.first.end, closeTo(153.24, 0.001));
      expect(page.skips.last.start, closeTo(1335.25, 0.001));
      expect(page.skips.first.name, 'Опенінґ');
    });

    test('HLS: майстер Moon → 1080/720/480', () {
      final base = Uri.parse('https://s.moonanime.net/content/stream/anime/51/x/hls/video:a/hls:manifest.m3u8?expires=1');
      final m = parseHlsMaster(fx('moon_master.m3u8'), base)!;
      expect(m.variants.map((v) => v.height), [1080, 720, 480]);
      final v = videosFromHls(m, base);
      expect(v.map((e) => e.title), ['Авто', '1080p', '720p', '480p']);
      expect(v[1].url, startsWith('https://s.moonanime.net/'));
      expect(pickVideo(v)!.title, '1080p');
      expect(pickVideo(v, maxHeight: 720)!.title, '720p');
      expect(pickVideo(v, maxHeight: 360)!.title, '480p');
    });

    test('повний екстрактор через підставлений транспорт', () async {
      final calls = <String>[];
      final http = SourceHttp(sender: (r) async {
        calls.add('${r.method} ${r.url}');
        if (r.url.host == 'moonanime.net') {
          expect(r.headers['Sec-Fetch-Dest'], 'iframe');
          return SourceResponse(200, r.url, fx('moon_iframe.html').codeUnits.isEmpty ? [] : File('test/data/sources/moon_iframe.html').readAsBytesSync());
        }
        return SourceResponse(200, r.url, File('test/data/sources/moon_master.m3u8').readAsBytesSync());
      });
      final vids = await VideoExtractors.forUrl('https://moonanime.net/iframe/ne17f39gtidf642')!.extract(http, 'https://moonanime.net/iframe/ne17f39gtidf642', referer: 'https://anitube.in.ua/');
      expect(vids.map((e) => e.title), ['Авто', '1080p', '720p', '480p']);
      expect(calls.length, greaterThanOrEqualTo(2));
      // CDN Moon відповідає 403 без Accept-Language (ffmpeg його не шле): заголовки відео мають його містити
      expect(vids.every((v) => v.headers['Accept-Language']!.isNotEmpty && v.headers['Accept'] == '*/*'), isTrue);
    });
  });

  group('Moon через Premium API', () {
    const url = 'https://moonanime.art/iframe/ne17f39gtidf642/';
    late SourcePrefs saved;
    setUp(() {
      saved = SourcePrefs.instance;
      final store = <String, dynamic>{};
      SourcePrefs.instance = SourcePrefs(load: () => store, save: (d) => store..clear()..addAll(d));
    });
    tearDown(() => SourcePrefs.instance = saved);

    SourceResponse json(Uri u, Object body, [int status = 200]) => SourceResponse(status, u, utf8.encode(jsonEncode(body)));

    test('без власного ключа й без бекенду ключа немає, власний ключ важливіший за ключ із бекенду', () {
      expect(SourcePrefs.instance.effectiveMoonKey, isEmpty, reason: 'у застосунку ключів немає');
      SourcePrefs.instance.moonKey = 'own';
      expect(SourcePrefs.instance.effectiveMoonKey, 'own');
    });

    test('slug береться з адреси плеєра', () {
      expect(MoonExtractor.slugOf(Uri.parse(url)), 'ne17f39gtidf642');
      expect(MoonExtractor.slugOf(Uri.parse('https://moonanime.art/other')), isNull);
    });

    test('ключ → HLS, субтитри й таймкоди з API; сторінку плеєра не чіпає', () async {
      SourcePrefs.instance.moonKey = ' KEY123 ';
      final calls = <String>[];
      final http = SourceHttp(sender: (r) async {
        calls.add(r.url.toString());
        if (r.url.host.startsWith('api.moonanime.')) {
          expect(r.headers['Authorization'], 'Bearer KEY123');
          if (r.url.path.contains('/skips/')) {
            return json(r.url, {'ok': true, 'data': {'skips': [{'segment_type': 'opening', 'start_sec': 12.0, 'end_sec': 102.5}, {'segment_type': 'ending', 'start_ms': 1290000, 'end_ms': 1380000}]}});
          }
          return json(r.url, {'ok': true, 'data': {'video': {'hls': {'url': 'https://s.moonanime.art/premium/stream/x/hls/playlist.m3u8'}}, 'subtitles': [{'url': 'https://subtitles.moonanime.art/a.vtt', 'label': 'Субтитри', 'lang': null}]}});
        }
        expect(r.url.host, isNot('moonanime.art'), reason: 'з ключем сторінку плеєра не завантажуємо');
        return SourceResponse(200, r.url, File('test/data/sources/moon_master.m3u8').readAsBytesSync());
      });
      final vids = await VideoExtractors.forUrl(url)!.extract(http, url, referer: 'https://anitube.in.ua/');
      expect(vids.map((e) => e.title), contains('1080p'));
      expect(vids.first.subtitleTracks.single.url, 'https://subtitles.moonanime.art/a.vtt');
      expect(vids.first.timestamps.map((t) => (t.start, t.end)), [(12.0, 102.5), (1290.0, 1380.0)]);
      expect(calls.any((c) => c.startsWith('https://api.moonanime.net/premium/api/1.0/video/ne17f39gtidf642')), isTrue);
    });

    test('основний хост .net недоступний → запасний .art', () async {
      SourcePrefs.instance.moonKey = 'KEY123';
      final http = SourceHttp(sender: (r) async {
        if (r.url.host == 'api.moonanime.net') throw const SourceException(SourceErrorKind.network, 'x');
        if (r.url.host == 'api.moonanime.art') {
          return r.url.path.contains('/skips/')
              ? json(r.url, {'ok': true, 'data': {'skips': []}})
              : json(r.url, {'ok': true, 'data': {'video': {'hls': {'url': 'https://s.moonanime.art/x/playlist.m3u8'}}}});
        }
        return SourceResponse(200, r.url, File('test/data/sources/moon_master.m3u8').readAsBytesSync());
      });
      final vids = await VideoExtractors.forUrl(url)!.extract(http, url);
      expect(vids.map((e) => e.title), contains('720p'));
    });

    test('квота вичерпана (429) → запасний розбір сторінки плеєра', () async {
      SourcePrefs.instance.moonKey = 'KEY123';
      final http = SourceHttp(sender: (r) async {
        if (r.url.host.startsWith('api.moonanime.')) return json(r.url, {'ok': false, 'error': {'code': 'RATE_LIMIT_EXCEEDED', 'message': 'x'}}, 429);
        if (r.url.host == 'moonanime.art') return SourceResponse(200, r.url, File('test/data/sources/moon_iframe.html').readAsBytesSync());
        return SourceResponse(200, r.url, File('test/data/sources/moon_master.m3u8').readAsBytesSync());
      });
      final vids = await VideoExtractors.forUrl(url)!.extract(http, url, referer: 'https://anitube.in.ua/');
      expect(vids.map((e) => e.title), ['Авто', '1080p', '720p', '480p']);
    });
  });

  group('Ashdi', () {
    test('сторінка vod → file: → майстер', () async {
      final http = SourceHttp(sender: (r) async {
        if (r.url.path.contains('/vod/')) return SourceResponse(200, r.url, File('test/data/sources/ashdi_vod.html').readAsBytesSync());
        return SourceResponse(200, r.url, File('test/data/sources/ashdi_master.m3u8').readAsBytesSync());
      });
      final vids = await VideoExtractors.forUrl('https://ashdi.vip/vod/292003')!.extract(http, 'https://ashdi.vip/vod/292003', referer: 'https://anitube.in.ua/');
      expect(vids.map((e) => e.title), ['Авто', '1080p', '720p', '480p']);
      expect(vids[1].url, contains('/hls/1080/BKmJlHCGjuRcnBH+Aok=/index.m3u8'));
    });
  });
}
