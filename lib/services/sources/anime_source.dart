/// Watch-source contract (analogous to Aniyomi's `AnimeSource` / `AnimeHttpSource`, but in Dart):
/// popular / new / search → anime page → episodes → video. Implementations are in `lib/services/sources/ua/`.
library;

import 'package:html/dom.dart';

import '../../models/source_models.dart';
import 'html_select.dart';
import 'source_http.dart';

abstract class AnimeSource {
  /// Stable identifier (stored in links, progress and settings)
  String get id;
  String get name;

  /// Dub language: `uk`, `en` …
  String get lang;
  String get baseUrl;
  bool get supportsLatest => true;
  bool get nsfw => false;

  /// One line for the "Джерела" page
  String get about => '';

  Future<SAnimePage> popular(int page);
  Future<SAnimePage> latest(int page);
  Future<SAnimePage> search(int page, String query);

  /// Detailed data from the anime page (returns a completed copy)
  Future<SAnime> details(SAnime anime);

  /// Episodes in ascending order (for sites with several dubs, a separate entry per dub)
  Future<List<SEpisode>> episodes(SAnime anime);

  /// Playable videos of the episode (different quality), best first
  Future<List<Video>> videos(SEpisode episode);

  /// Episode hosters. By default one, with all videos (the old Aniyomi `getVideoList` path)
  Future<List<Hoster>> hosters(SEpisode episode) async => [Hoster(name: name, videos: await videos(episode))];

  Future<List<Video>> hosterVideos(Hoster hoster) async => hoster.videos ?? const [];

  /// Full address of the anime page (for "open in browser")
  String animeWebUrl(SAnime anime);
}

/// A source that goes to the site through `SourceHttp`: shared small things (addresses, documents).
abstract class HttpAnimeSource extends AnimeSource {
  final SourceHttp http;

  HttpAnimeSource({SourceHttp? http}) : http = http ?? SourceHttp();

  Uri get _base => Uri.parse(baseUrl);

  /// Makes a relative address full (`/anime/1.html` → `https://site/anime/1.html`); `//cdn…` too.
  String absoluteUrl(String url) {
    final u = url.trim();
    if (u.isEmpty) return '';
    return SourceHttp.parseUrl(u, _base).toString();
  }

  /// The same as Aniyomi's `setUrlWithoutDomain`: we store the path without the domain so a mirror change does not break links.
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

  /// Parsing a list on a results page by selectors (like `ParsedAnimeHttpSource`).
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
