import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:miki_miki/models/source_models.dart';
import 'package:miki_miki/services/sources/html_select.dart';
import 'package:miki_miki/services/sources/source_http.dart';
import 'package:miki_miki/services/sources/ua/ufdub_source.dart';

String fx(String name) => File('test/data/sources/$name').readAsStringSync();

SourceResponse resp(int status, Uri url, String body, {Map<String, String> headers = const {}}) =>
    SourceResponse(status, url, utf8.encode(body), headers: headers);

void main() {
  final src = UfDubSource(http: SourceHttp(sender: (r) async => resp(404, r.url, '')));

  test('список «популярне»: назва з a.short-t, оригінальна назва в span, адреса без домену', () {
    final page = src.parsePage(parseHtml(fx('ufdub_popular.html')));
    expect(page.animes.length, 4);
    expect(page.hasNextPage, isTrue);
    final a = page.animes.first;
    expect(a.title, 'Агенти Часу 3');
    expect(a.originalTitle, 'Shiguang Dailiren III');
    expect(a.url, '/anime/451-agenty-chasu.html');
    expect(a.thumbnailUrl, 'https://ufdub.com/uploads/posts/2026-08/linkclick.png');
    expect(a.genres, ['Донхва', 'Драма', 'Містика', 'Фантастика']); // «Аніме» відкинуто
    expect(a.description, startsWith('Після того, як інцидент'));
    expect(page.animes.map((e) => e.title), everyElement(isNotEmpty));
  });

  test('остання сторінка: кнопки «далі» нема', () {
    final page = src.parsePage(parseHtml(fx('ufdub_last.html')));
    expect(page.animes, isNotEmpty);
    expect(page.hasNextPage, isFalse);
  });

  test('результат пошуку: назва береться з a.short-t, оригінал — з div.short-t-or', () {
    final page = src.parsePage(parseHtml(fx('ufdub_search.html')));
    expect(page.animes, isNotEmpty);
    final ebichu = page.animes.firstWhere((a) => a.url.contains('286-oruchuban-ebichu'));
    expect(ebichu.title, 'Хазяйновита Ебічу');
    expect(ebichu.originalTitle, 'Oruchuban Ebichu');
  });

  test('сторінка аніме: назва, оригінал, постер, студія, жанри, рік, опис без «Порядку перегляду»', () {
    final d = src.parseDetails(parseHtml(fx('ufdub_anime21.html')));
    expect(d.title, 'Хвіст Феї (1 cезон)');
    expect(d.originalTitle, 'Fairy Tail (TV-1)');
    expect(d.thumbnailUrl, startsWith('https://ufdub.com/uploads/posts/2021-06/'));
    expect(d.author, 'A-1 Pictures Inc., Satelight');
    expect(d.genres, ['Пригоди', 'Фантастика', 'Комедія']);
    expect(d.year, 2014);
    expect(d.status, SAnimeStatus.completed);
    expect(d.description, startsWith('У королівстві Фіоре'));
    expect(d.description, isNot(contains('Порядок перегляду')));
  });

  test('адреса плеєра: поле «Посилання на плеєр», а без нього — iframe V2 / змінна input_player', () {
    expect(src.playerUrl(parseHtml(fx('ufdub_anime21.html'))), 'https://video.ufdub.com/AT/VP.php?ID=1114');
    final iframe = parseHtml('<iframe id="input_video_player" src="https://video.ufdub.com/V2/VP.php?ID=1114&Name=x"></iframe>');
    expect(src.playerUrl(iframe), startsWith('https://video.ufdub.com/V2/VP.php?ID=1114'));
    final viaVar = parseHtml('<script>var input_player="https://video.ufdub.com/V2/VP.php?ID=5";</script>');
    expect(src.playerUrl(viaVar), 'https://video.ufdub.com/V2/VP.php?ID=5');
  });

  test('серії зі сторінки плеєра: назви, номери (POS ≠ номер), посилання VIDEOS.php', () {
    final eps = src.parsePlayer(scriptsOf(parseHtml(fx('ufdub_player21.html'))));
    expect(eps.length, 12);
    expect(eps.first.name, 'Серія 1 - Хвіст Феї (Макао)');
    expect(eps.first.number, 1);
    expect(eps.first.voice, 'UFDub');
    expect(eps.first.url, startsWith('https://ufdub.com/video/VIDEOS.php?ID=1114&TAB='));
    expect(eps[11].number, 12);
  });

  test('запасний розбір: лише посилання VIDEOS.php', () {
    const js = "x=['https://ufdub.com/video/VIDEOS.php?ID=1&TAB=Основа&Seriya=Серія 2&POS=2'];";
    final eps = src.parsePlayer(js);
    expect(eps.single.name, 'Серія 2');
    expect(eps.single.number, 2);
  });

  test('відео: редирект на api.ufdub.com, адреса кодується, Dropbox dl=1 → raw=1', () async {
    final calls = <String>[];
    final s = UfDubSource(http: SourceHttp(sender: (r) async {
      calls.add('${r.method} ${r.url.host}${r.url.path}');
      if (r.url.host == 'ufdub.com') {
        expect(r.headers['Range'], 'bytes=0-0');
        return resp(302, r.url, '', headers: {'location': 'https://api.ufdub.com/UFDUB_UPLOAD/VIDEO/1114-Серія 1 БГ.mp4'});
      }
      if (r.url.host == 'dropbox.test') return resp(206, r.url, '', headers: {'content-type': 'video/mp4'});
      return resp(206, r.url, '', headers: {'content-type': 'application/octet-stream'});
    }));
    final v = (await s.videos(const SEpisode(url: 'https://ufdub.com/video/VIDEOS.php?ID=1114&Seriya=Серія 1', name: 'Серія 1'))).single;
    expect(v.url, 'https://api.ufdub.com/UFDUB_UPLOAD/VIDEO/1114-%D0%A1%D0%B5%D1%80%D1%96%D1%8F%201%20%D0%91%D0%93.mp4');
    expect(v.headers['Referer'], 'https://ufdub.com/');
    final d = (await s.videos(const SEpisode(url: 'https://dropbox.test/s/x/file.mp4?dl=1', name: 'x'))).single;
    expect(d.url, endsWith('?raw=1'));
    expect(calls.length, 3);
  });

  test('відео: замість файла HTML-сторінка → помилка', () async {
    final s = UfDubSource(http: SourceHttp(sender: (r) async => resp(200, r.url, '<html>', headers: {'content-type': 'text/html; charset=utf-8'})));
    await expectLater(s.videos(const SEpisode(url: 'https://ufdub.com/video/VIDEOS.php?ID=1', name: 'x')), throwsA(isA<SourceException>()));
  });

  test('повний ланцюжок episodes(): сторінка аніме → плеєр V2 → серії', () async {
    final s = UfDubSource(http: SourceHttp(sender: (r) async {
      if (r.url.host == 'ufdub.com') return resp(200, r.url, fx('ufdub_anime21.html'));
      expect(r.url.host, 'video.ufdub.com');
      expect(r.headers['Referer'], 'https://ufdub.com/');
      return resp(200, r.url, fx('ufdub_player21.html'));
    }));
    final eps = await s.episodes(const SAnime(url: '/anime/21-hvist-feji-1-cezon-fairy-tail-tv-1.html', title: 'x'));
    expect(eps.length, 12);
  });

  test('запити списків: сортування за рейтингом форма POST, сторінка в адресі', () async {
    final reqs = <SourceRequest>[];
    final s = UfDubSource(http: SourceHttp(sender: (r) async {
      reqs.add(r);
      return resp(200, r.url, fx('ufdub_popular.html'));
    }));
    await s.popular(3);
    await s.latest(2);
    await s.search(1, 'Фея');
    expect(reqs[0].method, 'POST');
    expect(reqs[0].url.path, '/anime/page/3');
    expect(utf8.decode(reqs[0].body!), contains('dlenewssortby=rating'));
    expect(reqs[1].method, 'GET');
    expect(reqs[1].url.path, '/anime/anime/page/2');
    expect(reqs[2].url.toString(), 'https://ufdub.com/index.php?do=search');
    expect(utf8.decode(reqs[2].body!), allOf(contains('subaction=search'), contains('story=%D0%A4%D0%B5%D1%8F')));
  });
}
