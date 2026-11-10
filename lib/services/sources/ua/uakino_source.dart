/// UAKino (uakino.best) — фільми, серіали й аніме українською (розділ «animeukr»).
/// Порт розширення Aniyomi «UAKino» (yuzono/anime-repo): список з `div.movie-item`, серії з AJAX-плейлиста
/// DLE (`playlists.php`) або з плеєра Ashdi для серіалів, відео — через спільні екстрактори (Ashdi, Moon).
library;

import 'dart:convert';

import 'package:html/dom.dart';

import '../../../models/source_models.dart';
import '../anime_source.dart';
import '../episode_naming.dart';
import '../extractors.dart';
import '../html_select.dart';
import '../source_http.dart';

class UaKinoSource extends HttpAnimeSource {
  UaKinoSource({super.http});

  @override
  String get id => 'uakino';
  @override
  String get name => 'UAKino';
  @override
  String get lang => 'uk';
  @override
  String get baseUrl => 'https://uakino.best';
  @override
  String get about => 'Фільми, серіали й аніме з українською озвучкою (розділ «Аніме українською»)';

  static const String _animeSection = '/animeukr';
  static const String _items = 'div.movie-item';

  /// У видачі пошуку картки мають ще й клас `short-item` (як у розширенні Aniyomi)
  static const String _searchItems = 'div.movie-item.short-item';
  static const String _next = 'a:contains(Далі)';

  /// Популярне: за рейтингом, усі роки (верхня межа — поточний рік; у розширенні було зашито 2024)
  String get _popularPath => '$_animeSection/f/c.year=1921,${DateTime.now().year}/sort=rating;desc';

  // ── Списки ──────────────────────────────────────────────────────────────────────

  @override
  Future<SAnimePage> popular(int page) async {
    final res = await http.get('$baseUrl$_popularPath/page/$page');
    return parsePage(parseHtml(res.text));
  }

  @override
  Future<SAnimePage> latest(int page) async {
    final res = await http.get(page <= 1 ? '$baseUrl$_animeSection' : '$baseUrl$_animeSection/page/$page/');
    return parsePage(parseHtml(res.text));
  }

  @override
  Future<SAnimePage> search(int page, String query) async {
    final form = <String, String>{
      'do': 'search',
      'subaction': 'search',
      if (page > 1) 'search_start': '$page',
      if (page > 1) 'full_search': '0',
      if (page > 1) 'result_from': '${(page - 1) * 10 + 1}',
      'story': query,
    };
    final res = await http.postForm('$baseUrl/ua/', form, headers: {'Referer': '$baseUrl/'});
    return parsePage(parseHtml(res.text), search: true);
  }

  SAnimePage parsePage(Document doc, {bool search = false}) =>
      parseList(doc, selector: search ? _searchItems : _items, fromElement: fromElement, nextSelector: _next);

  SAnime fromElement(Element e) {
    final link = e.selectFirst('a.movie-title');
    final href = link?.attr('href') ?? '';
    var img = attrOf(e, 'div.movie-img img', 'src');
    if (img.isEmpty) img = attrOf(e, 'div.movie-img img', 'data-src');
    final title = link == null ? '' : elementText(link);
    return SAnime(
      url: urlWithoutDomain(href),
      title: title,
      thumbnailUrl: img.isEmpty ? null : absoluteUrl(img),
    );
  }

  // ── Сторінка аніме ──────────────────────────────────────────────────────────────

  @override
  Future<SAnime> details(SAnime anime) async {
    final doc = await document(absoluteUrl(anime.url));
    return anime.mergedWith(parseDetails(doc));
  }

  SAnime parseDetails(Document doc) {
    var poster = attrOf(doc, 'a[data-fancybox=gallery]', 'href');
    if (poster.isEmpty) poster = attrOf(doc, 'div.film-poster img', 'src');
    final original = textOf(doc, 'h1 span.origintitle');
    final desc = textOf(doc, 'div.full-text[itemprop=description]');
    return SAnime(
      url: '',
      title: textOf(doc, 'h1 span.solototle'),
      originalTitle: original.isEmpty ? null : original,
      thumbnailUrl: poster.isEmpty ? null : absoluteUrl(poster),
      description: desc.isEmpty ? null : desc,
    );
  }

  // ── Серії ───────────────────────────────────────────────────────────────────────

  /// Ідентифікатор новини DLE: прихований `<input id=post_id>`, а як його нема — число на початку імені сторінки
  String newsId(Document doc, String animeUrl) {
    final v = attrOf(doc, 'input[id=post_id]', 'value');
    if (v.isNotEmpty) return v;
    final m = RegExp(r'/(\d+)-[^/]*$').firstMatch(Uri.parse(absoluteUrl(animeUrl)).path);
    return m?.group(1) ?? '';
  }

  String _withScheme(String u) {
    final t = u.trim();
    if (t.startsWith('//')) return 'https:$t';
    return t;
  }

  /// Серії з відповіді AJAX-плейлиста. Однакові (озвучка, номер) з різних плеєрів зливаються в одну серію.
  List<SEpisode> parsePlaylist(String responseHtml) {
    final byKey = <String, List<EmbedLink>>{};
    final meta = <String, ({String name, String? voice})>{};
    final order = <String>[];
    for (final li in select(parseHtml(responseHtml), 'div.playlists-videos li')) {
      final file = _withScheme(li.attr('data-file'));
      if (file.isEmpty) continue;
      final label = elementText(li);
      final voice = li.attr('data-voice').trim();
      final key = '${voice.toLowerCase()}|${parseEpisodeNumber(label) ?? label}';
      if (!byKey.containsKey(key)) {
        order.add(key);
        meta[key] = (name: label, voice: voice.isEmpty ? null : voice);
      }
      byKey.putIfAbsent(key, () => []).add(EmbedLink(providerOf(file), file));
    }
    return [
      for (final k in order)
        SEpisode(
          url: byKey[k]!.first.url,
          name: meta[k]!.name,
          number: parseEpisodeNumber(meta[k]!.name),
          season: parseSeasonNumber(meta[k]!.name),
          voice: meta[k]!.voice,
          data: encodeEmbeds(byKey[k]!),
        ),
    ];
  }

  static final RegExp _ashdiFile = RegExp(r"file\s*:\s*'(.*?)'", dotAll: true);

  /// Серії серіалу з плеєра Ashdi: JSON «озвучка → сезон → серія»
  List<SEpisode> parseAshdiSerial(String scripts) {
    final m = _ashdiFile.firstMatch(scripts);
    if (m == null) return const [];
    Object? json;
    try {
      json = jsonDecode(m.group(1)!);
    } on FormatException {
      return const [];
    }
    final out = <SEpisode>[];
    void walk(Object? node, List<String> path) {
      if (node is List) {
        for (final x in node) {
          walk(x, path);
        }
      } else if (node is Map) {
        final title = '${node['title'] ?? ''}'.trim();
        final folder = node['folder'];
        final file = node['file'];
        if (folder is List) {
          walk(folder, [...path, title]);
        } else if (file is String && file.isNotEmpty) {
          // path: [озвучка, сезон?]; title — серія
          String? voice;
          String? seasonTitle;
          if (path.length >= 2) {
            voice = path.first;
            seasonTitle = path[1];
          } else if (path.length == 1) {
            voice = path.first;
          }
          final name = seasonTitle == null || seasonTitle.isEmpty ? title : '$seasonTitle · $title';
          final url = _withScheme(file);
          out.add(SEpisode(
            url: url,
            name: name,
            number: parseEpisodeNumber(title),
            season: seasonTitle == null ? null : parseSeasonNumber(seasonTitle),
            voice: voice == null || voice.isEmpty ? null : voice,
            data: encodeEmbeds([EmbedLink(providerOf(url), url)]),
          ));
        }
      }
    }

    walk(json, const []);
    return out;
  }

  @override
  Future<List<SEpisode>> episodes(SAnime anime) async {
    final pageUrl = absoluteUrl(anime.url);
    final doc = await document(pageUrl);
    final id = newsId(doc, anime.url);
    if (id.isNotEmpty) {
      final hash = RegExp(r'''dle_login_hash\s*=\s*['"]([0-9a-f]+)['"]''').firstMatch(scriptsOf(doc))?.group(1);
      final res = await http.get(
        '$baseUrl/engine/ajax/playlists.php?news_id=$id&xfield=playlist${hash == null ? '' : '&user_hash=$hash'}',
        headers: {'Referer': pageUrl, 'X-Requested-With': 'XMLHttpRequest', 'Accept': 'application/json, text/javascript, */*; q=0.01'},
      );
      Object? json;
      try {
        json = jsonDecode(res.text);
      } on FormatException {
        json = null;
      }
      if (json is Map && json['success'] == true && json['response'] is String) {
        final list = parsePlaylist(json['response'] as String);
        if (list.isNotEmpty) return list;
      }
    }
    // не серіал з плейлистом: плеєр у iframe
    final playerUrl = _withScheme(attrOf(doc, 'iframe#pre', 'src'));
    if (playerUrl.isEmpty) return const [];
    if (playerUrl.contains('/serial/')) {
      final res = await http.get(playerUrl, headers: embedHeaders(pageUrl));
      return parseAshdiSerial(scriptsOf(parseHtml(res.text)));
    }
    final title = textOf(doc, 'span.solototle');
    return [
      SEpisode(
        url: playerUrl,
        name: title.isEmpty ? 'Фільм' : title,
        voice: null,
        data: encodeEmbeds([EmbedLink(providerOf(playerUrl), playerUrl)]),
      ),
    ];
  }

  // ── Відео ───────────────────────────────────────────────────────────────────────

  @override
  Future<List<Video>> videos(SEpisode episode) async {
    if (hostersFor(episode).isNotEmpty) return videosOfEpisode(http, episode, referer: '$baseUrl/');
    // посилання на сам плейлист HLS чужого хоста (серіали Ashdi віддають прямі m3u8)
    final url = episode.url;
    if (url.split('?').first.toLowerCase().endsWith('.m3u8')) {
      final headers = {'Referer': '$baseUrl/', 'User-Agent': kBrowserUserAgent};
      return videosFromPlaylist(http, url, playHeaders: headers);
    }
    throw SourceException(SourceErrorKind.unsupported, 'UAKino: невідомий плеєр ${SourceHttp.parseUrl(url).host}');
  }
}
