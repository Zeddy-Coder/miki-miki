// Локальний HLS-проксі: переписування списків і віддача сегментів із заголовками оригінального сервера.
// Справжній `HttpServer` на loopback грає роль CDN; мережі назовні немає.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:miki_miki/models/source_models.dart';
import 'package:miki_miki/services/sources/extractors.dart';
import 'package:miki_miki/services/sources/hls_proxy.dart';
import 'package:miki_miki/services/sources/source_log.dart';

void main() {
  group('rewritePlaylist', () {
    test('адреси сегментів, підсписків і URI="…" стають локальними; решта рядків без змін', () {
      const text = '#EXTM3U\r\n#EXT-X-KEY:METHOD=AES-128,URI="key.bin"\r\n#EXTINF:4.0,\r\nseg0.ts?x=1\r\n#EXTINF:4.0,\r\nhttps://cdn.example/seg1.ts\r\n#EXT-X-ENDLIST\r\n';
      final out = HlsProxy.rewritePlaylist(text, Uri.parse('https://a.example/v/index.m3u8'), (t) => 'L(${t.toString()})');
      final lines = out.split('\n');
      expect(lines[1], '#EXT-X-KEY:METHOD=AES-128,URI="L(https://a.example/v/key.bin)"');
      expect(lines[3], 'L(https://a.example/v/seg0.ts?x=1)');
      expect(lines[5], 'L(https://cdn.example/seg1.ts)');
      expect(lines[2], '#EXTINF:4.0,');
      expect(lines.last, '');
    });
  });

  group('проксі з «CDN» на loopback', () {
    late HttpServer cdn;
    final seen = <String, Map<String, String>>{};
    final segment = List<int>.generate(5000, (i) => i % 251);

    setUp(() async {
      cdn = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      cdn.listen((r) async {
        seen[r.uri.path] = {
          'referer': r.headers.value('referer') ?? '',
          'ua': r.headers.value('user-agent') ?? '',
          'range': r.headers.value('range') ?? '',
        };
        // як справжній CDN Moon: без Accept-Language (і без Accept) — «сторінка захисту» з 403
        if (r.headers.value('referer') != 'https://site.example/' || r.headers.value('accept-language') == null || r.headers.value('accept') == null) {
          r.response.statusCode = 403;
          r.response.headers.contentType = ContentType.html;
          r.response.write('<html><body><h1>Access denied</h1><p>Error 1020</p></body></html>');
        } else if (r.uri.path.endsWith('/master.m3u8')) {
          r.response.write('#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1,RESOLUTION=1920x1080\nq/index.m3u8\n');
        } else if (r.uri.path.endsWith('/index.m3u8')) {
          r.response.write('#EXTM3U\n#EXTINF:4,\nseg0.ts\n#EXT-X-ENDLIST\n');
        } else if (r.headers.value('range') == 'bytes=0-9') {
          r.response.statusCode = 206;
          r.response.headers.set('content-range', 'bytes 0-9/5000');
          r.response.add(segment.sublist(0, 10));
        } else {
          r.response.headers.contentType = ContentType('video', 'mp2t');
          r.response.add(segment);
        }
        await r.response.close();
      });
    });

    tearDown(() => cdn.close(force: true));

    Future<(int, List<int>)> get(String url, {String? range}) async {
      final c = HttpClient();
      final rq = await c.getUrl(Uri.parse(url));
      if (range != null) rq.headers.set('range', range);
      final res = await rq.close();
      final bytes = await res.fold<List<int>>([], (a, b) => a..addAll(b));
      c.close();
      return (res.statusCode, bytes);
    }

    test('список → переписаний; сегмент → ті самі байти; Range і заголовки доходять до сервера', () async {
      final base = 'http://127.0.0.1:${cdn.port}';
      final proxied = await HlsProxy.instance.wrap('$base/v/master.m3u8', {'Referer': 'https://site.example/', 'User-Agent': 'UA-test'});
      expect(proxied, startsWith('http://127.0.0.1:'));
      expect(proxied, isNot(contains('${cdn.port}/v/master')));

      final (st, body) = await get(proxied);
      expect(st, 200);
      final master = utf8.decode(body);
      final variant = master.split('\n').firstWhere((l) => l.startsWith('http'));
      expect(variant, contains('127.0.0.1:${HlsProxy.instance.port}'));
      expect(seen['/v/master.m3u8']!['referer'], 'https://site.example/');
      expect(seen['/v/master.m3u8']!['ua'], 'UA-test');

      final (st2, body2) = await get(variant);
      expect(st2, 200);
      final segUrl = utf8.decode(body2).split('\n').firstWhere((l) => l.startsWith('http'));
      expect(seen['/v/q/index.m3u8']!['referer'], 'https://site.example/');

      final (st3, seg) = await get(segUrl);
      expect(st3, 200);
      expect(seg, segment);

      final (st4, part) = await get(segUrl, range: 'bytes=0-9');
      expect(st4, 206);
      expect(part, segment.sublist(0, 10));
      expect(seen['/v/q/seg0.ts']!['range'], 'bytes=0-9');
      expect(SourceLog.instance.lines.any((l) => l.contains('Проксі: сегмент 200')), isTrue);
    });

    test('помилка оригіналу (403) віддається як є, лічильник відмов росте, у журналі — початок сторінки захисту', () async {
      final base = 'http://127.0.0.1:${cdn.port}';
      final proxied = await HlsProxy.instance.wrap('$base/v/q/index.m3u8', {'Referer': 'https://site.example/'});
      final (st, body) = await get(proxied);
      expect(st, 200); // список віддається (Referer правильний)
      final segUrl = utf8.decode(body).split('\n').firstWhere((l) => l.startsWith('http'));
      final bad = await HlsProxy.instance.wrap('$base/v/q/seg0.ts', {'Referer': 'https://other.example/'});
      final before = HlsProxy.instance.blockedCount;
      final events = <int>[];
      final sub = HlsProxy.instance.blocked.listen(events.add);
      final (st2, _) = await get(bad);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await sub.cancel();
      expect(st2, 403);
      expect(HlsProxy.instance.blockedCount, before + 1);
      expect(events, [before + 1]);
      expect(segUrl, contains('127.0.0.1'));
      expect(SourceLog.instance.lines.any((l) => l.contains('Access denied')), isTrue);
    });

    test('Accept і Accept-Language додаються самі, навіть якщо їх нема в заголовках відео', () async {
      final base = 'http://127.0.0.1:${cdn.port}';
      final u = await HlsProxy.instance.wrap('$base/v/q/seg0.ts', {'Referer': 'https://site.example/', 'User-Agent': 'x'});
      final (st, body) = await get(u);
      expect(st, 200);
      expect(body, segment);
    });
  });

  test('Moon: з увімкненим проксі відео ведуть на 127.0.0.1 і без власних заголовків', () async {
    final prev = HlsProxy.enabled;
    HlsProxy.enabled = true;
    addTearDown(() => HlsProxy.enabled = prev);
    const v = Video(url: 'https://s.moonanime.net/x/index.m3u8', title: '1080p', resolution: 1080, headers: {'Referer': 'https://moonanime.art/'});
    final out = await VideoExtractors.moonViaProxyForTest([v]);
    expect(out.single.url, startsWith('http://127.0.0.1:'));
    expect(out.single.headers, isEmpty);
    expect(out.single.resolution, 1080);
  });
}
