/// Контракт джерела перегляду (аналог `AnimeSource` / `AnimeHttpSource` з Aniyomi, але на Dart):
/// популярне / нове / пошук → сторінка аніме → серії → відео. Реалізації — у `lib/services/sources/ua/`.
library;

import 'package:html/dom.dart';

import '../../models/source_models.dart';
import 'html_select.dart';
import 'source_http.dart';

abstract class AnimeSource {
  /// Стабільний ідентифікатор (зберігається в посиланнях, прогресі й налаштуваннях)
  String get id;
  String get name;

  /// Мова озвучки: `uk`, `en` …
  String get lang;
  String get baseUrl;
  bool get supportsLatest => true;
  bool get nsfw => false;

  /// Один рядок для сторінки «Джерела»
  String get about => '';

  Future<SAnimePage> popular(int page);
  Future<SAnimePage> latest(int page);
  Future<SAnimePage> search(int page, String query);

  /// Докладні дані зі сторінки аніме (повертає доповнену копію)
  Future<SAnime> details(SAnime anime);

  /// Серії в порядку зростання (для сайтів з кількома озвучками — окремий запис на кожну озвучку)
  Future<List<SEpisode>> episodes(SAnime anime);

  /// Відтворювані відео серії (різна якість), найкраща першою
  Future<List<Video>> videos(SEpisode episode);

  /// Хостинги серії. Типово — один, з усіма відео (старий шлях Aniyomi `getVideoList`)
  Future<List<Hoster>> hosters(SEpisode episode) async => [Hoster(name: name, videos: await videos(episode))];

  Future<List<Video>> hosterVideos(Hoster hoster) async => hoster.videos ?? const [];

  /// Повна адреса сторінки аніме (для «відкрити в браузері»)
  String animeWebUrl(SAnime anime);
}

/// Джерело, що ходить на сайт через `SourceHttp`: спільні дрібниці (адреси, документи).
abstract class HttpAnimeSource extends AnimeSource {
  final SourceHttp http;

  HttpAnimeSource({SourceHttp? http}) : http = http ?? SourceHttp();

  Uri get _base => Uri.parse(baseUrl);

  /// Відносну адресу робить повною (`/anime/1.html` → `https://site/anime/1.html`); `//cdn…` теж.
  String absoluteUrl(String url) {
    final u = url.trim();
    if (u.isEmpty) return '';
    return SourceHttp.parseUrl(u, _base).toString();
  }

  /// Те саме, що `setUrlWithoutDomain` в Aniyomi: зберігаємо шлях без домену, щоб зміна дзеркала не ламала посилань.
  String urlWithoutDomain(String url) {
    final u = url.trim();
    if (u.isEmpty) return '';
    final parsed = SourceHttp.parseUrl(u, _base);
    if (parsed.host == _base.host) {
      final q = parsed.hasQuery ? '?${parsed.query}' : '';
      return '${parsed.path}$q';
    }
    return parsed.toString();
  }

  @override
  String animeWebUrl(SAnime anime) => absoluteUrl(anime.url);

  Future<Document> document(String url, {Map<String, String>? headers}) async {
    final res = await http.get(url, headers: headers);
    return parseHtml(res.text);
  }

  /// Розбір списку на сторінці видачі за селекторами (як `ParsedAnimeHttpSource`).
  SAnimePage parseList(Document doc, {required String selector, required SAnime Function(Element) fromElement, String? nextSelector}) {
    final seen = <String>{};
    final animes = <SAnime>[];
    for (final e in select(doc, selector)) {
      final a = fromElement(e);
      if (a.url.isEmpty || a.title.isEmpty || !seen.add(a.url)) continue;
      animes.add(a);
    }
    final hasNext = nextSelector != null && selectFirst(doc, nextSelector) != null;
    return SAnimePage(animes, hasNext);
  }
}
