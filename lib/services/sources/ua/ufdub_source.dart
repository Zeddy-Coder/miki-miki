/// UFDub (ufdub.com) — українська озвучка аніме та донхуа студією Ukraine Fast Dub.
/// Порт розширення Aniyomi «UFDub» (yuzono/anime-repo), звірений з живим сайтом: у нього змінилися
/// назва в списку (`a.short-t`), перехід на сторінку плеєра V2 і кінцеві посилання (api.ufdub.com).
library;

import 'package:html/dom.dart';

import '../../../models/source_models.dart';
import '../anime_source.dart';
import '../episode_naming.dart';
import '../extractors.dart';
import '../html_select.dart';
import '../source_http.dart';

class UfDubSource extends HttpAnimeSource {
  UfDubSource({super.http});

  @override
  String get id => 'ufdub';
  @override
  String get name => 'UFDub';
  @override
  String get lang => 'uk';
  @override
  String get baseUrl => 'https://ufdub.com';
  @override
  String get about => 'Студія Ukraine Fast Dub: аніме й донхуа з українською озвучкою';

  static const String _section = '/anime';
  static const String _items = 'div.short';

  /// «Наступна» — кнопка `pnext` з посиланням (на останній сторінці в ній лише `span`)
  static const String _next = 'div.pagi-nav .pnext a';

  /// Скільки аніме на сторінці видачі — потрібно для зсуву сторінок пошуку (`result_from`)
  static const int _pageSize = 16;

  // ── Списки ──────────────────────────────────────────────────────────────────────

  @override
  Future<SAnimePage> popular(int page) async {
    final res = await http.postForm('$baseUrl$_section/page/$page', {
      'dlenewssortby': 'rating',
      'dledirection': 'desc',
      'set_new_sort': 'dle_sort_cat_12',
      'set_direction_sort': 'dle_direction_cat_12',
    });
    return parsePage(parseHtml(res.text));
  }

  @override
  Future<SAnimePage> latest(int page) async {
    final res = await http.get('$baseUrl$_section$_section/page/$page');
    return parsePage(parseHtml(res.text));
  }

  @override
  Future<SAnimePage> search(int page, String query) async {
    final form = <String, String>{
      'do': 'search',
      'subaction': 'search',
      'full_search': '1',
      'result_from': '${(page - 1) * _pageSize + 1}',
      if (page > 1) 'search_start': '$page',
      'story': query,
    };
    final res = await http.postForm('$baseUrl/index.php?do=search', form);
    return parsePage(parseHtml(res.text));
  }

  SAnimePage parsePage(Document doc) => parseList(doc, selector: _items, fromElement: fromElement, nextSelector: _next);

  SAnime fromElement(Element e) {
    var link = attrOf(e, 'div.m-views', 'data-link');
    if (link.isEmpty) link = attrOf(e, 'a.short-t', 'href');
    if (link.isEmpty) link = attrOf(e, 'div.ps-link', 'data-link');
    if (link.isEmpty) {
      final m = RegExp(r"location\.href='([^']+)'").firstMatch(e.attributes['onclick'] ?? '');
      link = m?.group(1) ?? '';
    }
    final titleEl = selectFirst(e, 'a.short-t');
    var title = titleEl == null ? '' : ownText(titleEl);
    var original = titleEl == null ? '' : textOf(titleEl, 'span');
    if (original.isEmpty) original = textOf(e, 'div.short-t-or');
    if (title.isEmpty) title = original;
    if (title.isEmpty) title = attrOf(e, 'div.short-i > img', 'alt');
    title = _withoutOriginal(title, original);
    final genres = select(e, 'div.short-c a').map(elementText).where(_isGenre).toList();
    final thumb = attrOf(e, 'div.short-i > img', 'src');
    final desc = textOf(e, 'div.short-d');
    return SAnime(
      url: urlWithoutDomain(link),
      title: title,
      originalTitle: original.isEmpty || original == title ? null : original,
      thumbnailUrl: thumb.isEmpty ? null : absoluteUrl(thumb),
      description: desc.isEmpty ? null : desc,
      genres: genres,
    );
  }

  /// У видачі пошуку назва йде як «Українська / Original» — відрізаємо оригінал, він уже окремо
  static String _withoutOriginal(String title, String original) {
    if (original.isNotEmpty && title.endsWith(' / $original')) return title.substring(0, title.length - original.length - 3).trim();
    return title;
  }

  static bool _isGenre(String g) => g.isNotEmpty && g != 'Аніме' && g != 'Завершені проєкти';

  // ── Сторінка аніме ──────────────────────────────────────────────────────────────

  @override
  Future<SAnime> details(SAnime anime) async {
    final doc = await document(absoluteUrl(anime.url));
    return anime.mergedWith(parseDetails(doc));
  }

  SAnime parseDetails(Document doc) {
    final h1 = selectFirst(doc, 'h1.top-title');
    var title = h1 == null ? '' : ownText(h1);
    if (title.isEmpty && h1 != null) title = elementText(h1);
    final original = textOf(doc, 'h1.top-title .short-t-or');
    title = _withoutOriginal(title, original);
    final thumb = attrOf(doc, 'div.f-poster img', 'src');
    final paragraphs = select(doc, 'div.full-text > p').map(elementText).where((s) => s.isNotEmpty).toList();
    String? studio;
    var genres = <String>[];
    int? year;
    var finished = false;
    for (final item in select(doc, '.full-info div.fi-col-item')) {
      final label = textOf(item, 'span');
      final links = select(item, 'a').map(elementText).where((s) => s.isNotEmpty).toList();
      if (label.startsWith('Студія')) {
        studio = links.join(', ');
      } else if (label.startsWith('Жанр')) {
        finished = links.contains('Завершені проєкти');
        genres = links.where(_isGenre).toList();
      } else if (label.startsWith('Рік')) {
        year = int.tryParse(links.isNotEmpty ? links.first : '');
      }
    }
    return SAnime(
      url: '',
      title: title,
      originalTitle: original.isEmpty ? null : original,
      thumbnailUrl: thumb.isEmpty ? null : absoluteUrl(thumb),
      description: paragraphs.isEmpty ? null : paragraphs.join('\n\n'),
      author: studio == null || studio.isEmpty ? null : studio,
      genres: genres,
      status: finished ? SAnimeStatus.completed : SAnimeStatus.unknown,
      year: year,
    );
  }

  // ── Серії ───────────────────────────────────────────────────────────────────────

  /// Адреса плеєра на сторінці аніме: поле «Посилання на плеєр» (`<input value=…>`, як у розширенні), а як його нема —
  /// `<iframe src=…>` чи `var input_player="…"` (плеєр V2). Серії в обох однакові.
  String playerUrl(Document doc) {
    var u = attrOf(doc, 'input[value*=https://video.ufdub.com]', 'value');
    if (u.isEmpty) u = attrOf(doc, 'iframe#input_video_player', 'src');
    if (u.isEmpty) u = attrOf(doc, 'iframe[src*=video.ufdub.com]', 'src');
    if (u.isEmpty) {
      final m = RegExp(r'''input_player\s*=\s*["']([^"']+)["']''').firstMatch(scriptsOf(doc));
      u = m?.group(1) ?? '';
    }
    return u.trim();
  }

  static final RegExp _entry = RegExp(
    r"""\[\s*'((?:[^'\\]|\\.)*)'\s*,\s*'((?:[^'\\]|\\.)*)'\s*,\s*'((?:[^'\\]|\\.)*)'\s*(?:,\s*'((?:[^'\\]|\\.)*)'\s*)?\]""",
  );
  static final RegExp _videosUrl = RegExp(r"""https:\/\/ufdub\.com\/video\/VIDEOS\.php\?[^'"]*""");

  /// Серії зі сторінки плеєра V2 — масив `a=[['Назва','mp4','посилання'], …]`
  List<SEpisode> parsePlayer(String scripts) {
    final out = <SEpisode>[];
    for (final m in _entry.allMatches(scripts)) {
      final title = _unescapeJs(m.group(1)!);
      final type = m.group(2)!;
      final url = _unescapeJs(m.group(3)!);
      if (!url.contains('VIDEOS.php') && type != 'web') continue;
      if (type == 'web' && VideoExtractors.forUrl(url) == null) continue; // чужі iframe без екстрактора не відтворити
      String? tab;
      if (url.contains('TAB=')) tab = SourceHttp.parseUrl(url).queryParameters['TAB'];
      final label = title.isNotEmpty ? title : (SourceHttp.parseUrl(url).queryParameters['Seriya'] ?? '');
      out.add(SEpisode(
        url: url,
        name: tab == null || tab == 'Основа' || tab.isEmpty ? label : '$tab · $label',
        number: parseEpisodeNumber(label),
        season: parseSeasonNumber(label),
        voice: 'UFDub',
        data: type == 'mp4|Audio' ? m.group(4) : null,
      ));
    }
    if (out.isNotEmpty) return out;
    // запасний шлях (як у розширенні): шукаємо лише посилання VIDEOS.php
    for (final m in _videosUrl.allMatches(scripts)) {
      final url = m.group(0)!;
      final q = SourceHttp.parseUrl(url).queryParameters;
      final label = q['Seriya'] ?? '';
      if (label.isEmpty) continue;
      out.add(SEpisode(url: url, name: label, number: parseEpisodeNumber(label), season: parseSeasonNumber(label), voice: 'UFDub'));
    }
    return out;
  }

  static String _unescapeJs(String s) => s.replaceAll(r"\'", "'").replaceAll(r'\"', '"').replaceAll(r'\\', r'\');

  @override
  Future<List<SEpisode>> episodes(SAnime anime) async {
    final page = await document(absoluteUrl(anime.url));
    final player = playerUrl(page);
    if (player.isEmpty) return const [];
    final res = await http.get(player, headers: {'Referer': '$baseUrl/'});
    return parsePlayer(scriptsOf(parseHtml(res.text)));
  }

  // ── Відео ───────────────────────────────────────────────────────────────────────

  @override
  Future<List<Video>> videos(SEpisode episode) async {
    final ex = VideoExtractors.forUrl(episode.url);
    if (ex != null) return ex.extract(http, episode.url, referer: '$baseUrl/');
    final headers = {'Referer': '$baseUrl/', 'User-Agent': kBrowserUserAgent};
    final r = await http.resolve(episode.url, headers: {'Referer': '$baseUrl/'});
    if (r.status >= 400) {
      throw SourceException(r.status == 404 ? SourceErrorKind.notFound : SourceErrorKind.server, '${r.url} → ${r.status}', status: r.status);
    }
    if (r.contentType.toLowerCase().contains('text/html')) {
      throw SourceException(SourceErrorKind.badResponse, 'замість відео — сторінка: ${r.url}');
    }
    final url = r.url.toString().replaceAll('dl=1', 'raw=1'); // Dropbox: пряме посилання замість «завантаження»
    final audio = episode.data;
    return [
      Video(
        url: url,
        title: 'Відео',
        headers: headers,
        audioTracks: audio != null && audio.startsWith('http') ? [Track(audio, 'uk')] : const [],
      ),
    ];
  }
}
