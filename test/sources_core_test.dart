import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:miki_miki/models/source_models.dart';
import 'package:miki_miki/services/sources/episode_naming.dart';
import 'package:miki_miki/services/sources/extractors.dart';
import 'package:miki_miki/services/sources/hls.dart';
import 'package:miki_miki/services/sources/html_select.dart';
import 'package:miki_miki/services/sources/source_http.dart';

SourceResponse resp(int status, Uri url, String body, {Map<String, String> headers = const {}, List<String> cookies = const []}) =>
    SourceResponse(status, url, utf8.encode(body), headers: headers, setCookies: cookies);

void main() {
  group('html_select (Jsoup-подібні вибірки)', () {
    final doc = parseHtml('''
      <div class="pagi">
        <a href="/p1">Назад</a> <a href="/p3">Далі</a>
        <input id="post_id" value="123"><input value="https://video.ufdub.com/V2/VP.php?ID=1">
      </div>
      <ul><li class="a">Один <b>два</b></li><li class="b">Три&nbsp;&nbsp;чотири</li></ul>
      <script>var a = 1;</script><script>var b = "x";</script>
      <p>перший<br>рядок</p>
    ''');

    test(':contains працює без урахування регістру й вибирає потрібний елемент', () {
      expect(select(doc, 'a:contains(далі)').map(elementText), ['Далі']);
      expect(select(doc, 'a:contains(Далі)').single.attributes['href'], '/p3');
      expect(select(doc, 'a:containsOwn(Назад)').length, 1);
    });

    test('непозначені значення атрибутів із двокрапкою й слешами', () {
      expect(attrOf(doc, 'input[value*=https://video.ufdub.com]', 'value'), contains('VP.php?ID=1'));
      expect(attrOf(doc, 'input[id=post_id]', 'value'), '123');
    });

    test('текст нормалізується, nbsp і вкладені теги зводяться до одного пробілу', () {
      expect(textOf(doc, 'li.a'), 'Один два');
      expect(textOf(doc, 'li.b'), 'Три чотири');
      expect(textOf(doc, 'li'), 'Один два Три чотири');
      expect(elementText(selectFirst(doc, 'p')!), 'перший рядок');
    });

    test('кілька селекторів через кому — у порядку документа; скрипти — окремо', () {
      expect(select(doc, 'li.b, li.a').map((e) => e.className), ['a', 'b']);
      expect(scriptsOf(doc), contains('var a = 1;'));
      expect(scriptsOf(doc), contains('var b = "x";'));
    });
  });

  group('SourceHttp', () {
    test('куки зберігаються між запитами, а редирект POST→GET скидає тіло', () async {
      final seen = <SourceRequest>[];
      final http = SourceHttp(sender: (r) async {
        seen.add(r);
        if (r.url.path == '/login') return resp(302, r.url, '', headers: {'location': '/home'}, cookies: ['sid=abc; Path=/; HttpOnly']);
        if (r.url.path == '/home') return resp(200, r.url, 'ok');
        return resp(404, r.url, '');
      });
      final res = await http.postForm('https://site.test/login', {'q': 'аніме'});
      expect(res.text, 'ok');
      expect(res.url.path, '/home');
      expect(seen.length, 2);
      expect(seen[0].method, 'POST');
      expect(utf8.decode(seen[0].body!), contains('%D0%B0%D0%BD%D1%96%D0%BC%D0%B5'));
      expect(seen[1].method, 'GET');
      expect(seen[1].body, isNull);
      expect(seen[1].headers['Cookie'], 'sid=abc');
      await http.get('https://site.test/home');
      expect(seen.last.headers['Cookie'], 'sid=abc');
      // інший домен кукі не отримує
      await http.get('https://other.test/home');
      expect(seen.last.headers.containsKey('Cookie'), isFalse);
    });

    test('Location з пробілами й кирилицею розбирається', () async {
      final http = SourceHttp(sender: (r) async {
        if (r.url.path.endsWith('go')) {
          return resp(302, r.url, '', headers: {'location': 'https://api.test/VIDEO/1114-Серія 1 БГ-2023.mp4'});
        }
        return resp(206, r.url, '');
      });
      final r = await http.resolve('https://site.test/go');
      expect(r.status, 206);
      expect(r.url.toString(), 'https://api.test/VIDEO/1114-%D0%A1%D0%B5%D1%80%D1%96%D1%8F%201%20%D0%91%D0%93-2023.mp4');
    });

    test('Cloudflare і 404 розпізнаються, на 5xx є один повтор', () async {
      var calls = 0;
      final http = SourceHttp(retryDelay: Duration.zero, sender: (r) async {
        calls++;
        switch (r.url.path) {
          case '/cf':
            return resp(403, r.url, '<title>Attention Required! | Cloudflare</title>', headers: {'server': 'cloudflare', 'content-type': 'text/html'});
          case '/nf':
            return resp(404, r.url, '');
          case '/rl':
            return resp(429, r.url, '{"ok":false}', headers: {'content-type': 'application/json', 'server': 'cloudflare'});
          default:
            return resp(500, r.url, '');
        }
      });
      await expectLater(http.get('https://s.test/cf'), throwsA(isA<SourceException>().having((e) => e.kind, 'kind', SourceErrorKind.blocked)));
      await expectLater(http.get('https://s.test/nf'), throwsA(isA<SourceException>().having((e) => e.kind, 'kind', SourceErrorKind.notFound)));
      await expectLater(http.get('https://s.test/rl'), throwsA(isA<SourceException>().having((e) => e.kind, 'kind', SourceErrorKind.rateLimited)));
      calls = 0;
      await expectLater(http.get('https://s.test/boom'), throwsA(isA<SourceException>().having((e) => e.kind, 'kind', SourceErrorKind.server)));
      expect(calls, 2);
    });

    test('windows-1251 розкодовується', () {
      final bytes = <int>[0xCF, 0xF0, 0xE8, 0xE2, 0xB3, 0xF2]; // «Привіт»
      final r = SourceResponse(200, Uri.parse('https://a.test/'), bytes, headers: {'content-type': 'text/html; charset=windows-1251'});
      expect(r.text, 'Привіт');
    });
  });

  group('HLS і вибір відео', () {
    test('атрибути з лапками й комами, відносні адреси, дублікати висоти', () {
      const text = '#EXTM3U\n'
          '#EXT-X-STREAM-INF:BANDWIDTH=2000000,CODECS="avc1.64001f,mp4a.40.2",RESOLUTION=1280x720\n720/a.m3u8\n'
          '#EXT-X-STREAM-INF:RESOLUTION=1280x720,BANDWIDTH=900000\n720b/a.m3u8\n'
          '#EXT-X-STREAM-INF:RESOLUTION=640x360,BANDWIDTH=500000\nhttps://cdn.test/360.m3u8\n';
      final base = Uri.parse('https://x.test/path/master.m3u8');
      final m = parseHlsMaster(text, base)!;
      expect(m.variants.length, 3);
      expect(m.variants[0].url.toString(), 'https://x.test/path/720/a.m3u8');
      expect(m.variants[0].codecs, 'avc1.64001f,mp4a.40.2');
      final v = videosFromHls(m, base, withAuto: false);
      expect(v.map((e) => e.title), ['720p · 2000 кбіт/с', '720p · 900 кбіт/с', '360p']);
      expect(parseHlsMaster('#EXTM3U\n#EXTINF:5,\nseg.ts', base), isNull);
      expect(parseHlsMaster('<html>', base), isNull);
    });

    test('pickVideo: preferred > бажана висота > найвища', () {
      const a = Video(url: 'a', title: '1080p', resolution: 1080);
      const b = Video(url: 'b', title: '720p', resolution: 720);
      const c = Video(url: 'c', title: '480p', resolution: 480, preferred: true);
      expect(pickVideo([a, b])!.url, 'a');
      expect(pickVideo([a, b], maxHeight: 900)!.url, 'b');
      expect(pickVideo([a, b], maxHeight: 100)!.url, 'b');
      expect(pickVideo([a, b, c])!.url, 'c');
      expect(pickVideo(const []), isNull);
      expect(pickVideo([const Video(url: '', title: 'x')]), isNull);
    });
  });

  group('Спільні помічники', () {
    test('номер серії й сезону з назв', () {
      expect(parseEpisodeNumber('Серія 13 - Нацу проти Юкі'), 13);
      expect(parseEpisodeNumber('12 серія'), 12);
      expect(parseEpisodeNumber('Сезон 2 Серія 5 Озвучення'), 5);
      expect(parseEpisodeNumber('Episode 7.5'), 7.5);
      expect(parseEpisodeNumber('7'), 7);
      expect(parseEpisodeNumber('Фільм'), isNull);
      expect(parseSeasonNumber('Сезон 2 Серія 5'), 2);
      expect(parseSeasonNumber('Серія 5'), isNull);
    });

    test('[мітка]посилання: списки якостей і субтитрів', () {
      final l = parseBracketList('[1080]https://a.test/1080.mp4,[720]https://a.test/7 20.mp4,[Українська]//cdn.test/s.vtt');
      expect(l.map((e) => e.label), ['1080', '720', 'Українська']);
      expect(l.first.url, 'https://a.test/1080.mp4');
      expect(parseBracketList(''), isEmpty);
      expect(parseBracketList(null), isEmpty);
      expect(subtitleLang('Українська'), 'uk');
      expect(subtitleLang('English'), 'en');
    });

    test('серія з кількома плеєрами: порядок Moon → Ashdi, невідомі відкидаються', () {
      final ep = SEpisode(
        url: 'https://ashdi.vip/vod/1',
        name: 'Серія 1',
        data: encodeEmbeds(const [
          EmbedLink('fenix', 'https://fenixplay.xyz/vod/zzz'),
          EmbedLink('ashdi', 'https://ashdi.vip/vod/1'),
          EmbedLink('moon', 'https://moonanime.art/iframe/abc/'),
        ]),
      );
      expect(hostersFor(ep).map((h) => h.name), ['Moon', 'Ashdi']);
      expect(embedsOf(const SEpisode(url: 'https://ashdi.vip/vod/9', name: 'x')).single.provider, 'ashdi');
    });

    test('SEpisode / SAnime серіалізуються без втрат', () {
      const a = SAnime(url: '/x', title: 'T', originalTitle: 'O', thumbnailUrl: 'u', genres: ['a', 'b'], status: SAnimeStatus.ongoing, year: 2024, episodesAired: 3, episodesTotal: 12);
      final b = SAnime.fromJson(jsonDecode(jsonEncode(a.toJson())) as Map<String, dynamic>);
      expect(b.toJson(), a.toJson());
      final e = SEpisode(url: 'u', name: 'n', number: 2.5, season: 1, voice: 'v', date: DateTime.utc(2026, 1, 2), data: 'd');
      expect(SEpisode.fromJson(jsonDecode(jsonEncode(e.toJson())) as Map<String, dynamic>).toJson(), e.toJson());
    });
  });
}
