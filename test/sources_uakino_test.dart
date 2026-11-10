import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:miki_miki/models/source_models.dart';
import 'package:miki_miki/services/sources/extractors.dart';
import 'package:miki_miki/services/sources/html_select.dart';
import 'package:miki_miki/services/sources/source_http.dart';
import 'package:miki_miki/services/sources/ua/uakino_source.dart';

import 'support/fake_site.dart';

// Фікстури зроблені за селекторами розширення Aniyomi «UAKino» (сам сайт з пісочниці закритий Cloudflare).
void main() {
  group('списки', () {
    final s = UaKinoSource();

    test('видача: картки, відносні адреси, обкладинки (src і data-src), без дублів і сторонніх блоків', () {
      final page = s.parsePage(parseHtml(fixture('uakino_list.html')));
      expect(page.animes.map((a) => a.title), ['Хвіст Феї', 'Друге аніме', 'Віджет збоку']);
      expect(page.animes.first.url, '/animeukr/12345-hvist-feji.html');
      expect(page.animes.first.thumbnailUrl, 'https://uakino.best/uploads/posts/2024-01/poster-12345.jpg');
      expect(page.animes[1].thumbnailUrl, 'https://uakino.best/uploads/posts/2024-02/poster-777.jpg');
      expect(page.hasNextPage, isTrue);
    });

    test('пошук бере лише short-item', () {
      final page = s.parsePage(parseHtml(fixture('uakino_list.html')), search: true);
      expect(page.animes.map((a) => a.title), ['Хвіст Феї', 'Друге аніме']);
    });

    test('без «Далі» наступної сторінки немає', () {
      final html = fixture('uakino_list.html').replaceAll('Далі', 'Назад');
      expect(s.parsePage(parseHtml(html)).hasNextPage, isFalse);
    });
  });

  group('сторінка аніме', () {
    test('назва, оригінал, постер, опис', () {
      final d = UaKinoSource().parseDetails(parseHtml(fixture('uakino_anime.html')));
      expect(d.title, 'Хвіст Феї');
      expect(d.originalTitle, 'Fairy Tail');
      expect(d.thumbnailUrl, 'https://uakino.best/uploads/posts/2024-01/full-12345.jpg');
      expect(d.description, startsWith('Люсі мріє потрапити до гільдії «Хвіст Феї»'));
      expect(d.description, contains('Це друге речення.'));
    });

    test('ідентифікатор новини: із прихованого поля, а як нема — із адреси', () {
      final s = UaKinoSource();
      expect(s.newsId(parseHtml(fixture('uakino_anime.html')), '/animeukr/12345-x.html'), '12345');
      expect(s.newsId(parseHtml('<html></html>'), '/animeukr/987-nazva.html'), '987');
    });
  });

  group('серії', () {
    test('плейлист DLE: серії однієї озвучки з різних плеєрів зливаються, схема // доповнюється', () {
      final html = (jsonDecode(fixture('uakino_playlist.json')) as Map)['response'] as String;
      final eps = UaKinoSource().parsePlaylist(html);
      expect(eps.length, 3);
      expect(eps.map((e) => '${e.voice}|${e.name}'), ['Inari|Серія 1', 'Inari|Серія 2', 'FanVoxUA|Серія 1']);
      expect(eps.first.number, 1);
      final inari1 = embedsOf(eps.first);
      expect(inari1.map((m) => m.provider), ['ashdi', 'moon']);
      expect(inari1.first.url, 'https://ashdi.vip/vod/111');
      expect(hostersFor(eps.first).map((h) => h.name), ['Moon', 'Ashdi']);
    });

    test('плеєр Ashdi для серіалу: озвучка → сезон → серія', () {
      final scripts = scriptsOf(parseHtml(fixture('uakino_ashdi_serial.html')));
      final eps = UaKinoSource().parseAshdiSerial(scripts);
      expect(eps.length, 4);
      expect(eps.map((e) => e.voice), ['Inari', 'Inari', 'Inari', 'FanVoxUA']);
      expect(eps.map((e) => e.season), [1, 1, 2, 1]);
      expect(eps.map((e) => e.number), [1, 2, 1, 1]);
      expect(eps.first.name, 'Сезон 1 · Серія 1');
      expect(eps.first.url, 'https://ashdi.vip/video3/1/s01e01/index.m3u8');
    });

    test('episodes(): AJAX-плейлист із хешем DLE і заголовками XHR', () async {
      final site = FakeSite({
        'GET https://uakino.best/animeukr/12345-hvist-feji.html': fixture('uakino_anime.html'),
        'playlists.php': fixture('uakino_playlist.json'),
      });
      final eps = await UaKinoSource(http: site.http).episodes(const SAnime(url: '/animeukr/12345-hvist-feji.html', title: 'x'));
      expect(eps.length, 3);
      final ajax = site.log.firstWhere((r) => r.url.path.endsWith('playlists.php'));
      expect(ajax.url.queryParameters, {'news_id': '12345', 'xfield': 'playlist', 'user_hash': 'a1b2c3d4e5f6'});
      expect(ajax.headers['X-Requested-With'], 'XMLHttpRequest');
      expect(ajax.headers['Referer'], 'https://uakino.best/animeukr/12345-hvist-feji.html');
    });

    test('episodes(): плейлиста нема → серіал у плеєрі Ashdi', () async {
      final site = FakeSite({
        'GET https://uakino.best/animeukr/12345-hvist-feji.html': fixture('uakino_anime.html'),
        'playlists.php': fixture('uakino_playlist_fail.json'),
        'https://ashdi.vip/serial/555': fixture('uakino_ashdi_serial.html'),
      });
      final eps = await UaKinoSource(http: site.http).episodes(const SAnime(url: '/animeukr/12345-hvist-feji.html', title: 'x'));
      expect(eps.length, 4);
      expect(eps.first.voice, 'Inari');
    });

    test('episodes(): фільм — один плеєр у iframe', () async {
      final page = fixture('uakino_anime.html').replaceAll('//ashdi.vip/serial/555', '//ashdi.vip/vod/9001');
      final site = FakeSite({
        'GET https://uakino.best/animeukr/1-film.html': page,
        'playlists.php': fixture('uakino_playlist_fail.json'),
      });
      final eps = await UaKinoSource(http: site.http).episodes(const SAnime(url: '/animeukr/1-film.html', title: 'x'));
      expect(eps.length, 1);
      expect(eps.single.name, 'Хвіст Феї');
      expect(eps.single.url, 'https://ashdi.vip/vod/9001');
      expect(hostersFor(eps.single).map((h) => h.name), ['Ashdi']);
    });
  });

  group('відео', () {
    test('невідомий плеєр → зрозуміла помилка', () {
      expect(
        UaKinoSource().videos(const SEpisode(url: 'https://example.com/embed/1', name: 'Серія 1')),
        throwsA(isA<SourceException>().having((e) => e.kind, 'kind', SourceErrorKind.unsupported)),
      );
    });
  });
}
