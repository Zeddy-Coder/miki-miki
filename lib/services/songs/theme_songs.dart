/// The songs of an anime's openings and endings: which one plays in which episode, who sings it, where to listen to it.
/// Pure logic: the model, reading the answers of AnimeThemes (GraphQL), MyAnimeList (through Tenrai) and Hikka and
/// putting them together, episode ranges, links to services, which store track is the song.
library;

import 'dart:convert';

import '../../models/hikka_models.dart';

/// An opening or an ending
enum SongKind { op, ed }

/// Where the player offers to listen to a song, in this order
enum MusicApp { spotify, youtubeMusic, appleMusic, youtube }

class ThemeSong {
  final SongKind kind;

  /// OP1, OP2 … (0: the only one, no number)
  final int sequence;

  /// The title in Latin letters (romaji or English)
  final String title;

  /// The original title (勇者), when known
  final String? native;
  final List<String> artists;

  /// The artists' original names (ヨルシカ), when known: Japanese stores list them so
  final List<String> nativeArtists;

  /// The episodes it plays in (inclusive ranges); empty: all of them
  final List<(int, int)> episodes;

  /// Direct links to the song by service; the others are searched for
  final Map<MusicApp, String> links;

  const ThemeSong({
    required this.kind,
    required this.title,
    this.sequence = 0,
    this.native,
    this.artists = const [],
    this.nativeArtists = const [],
    this.episodes = const [],
    this.links = const {},
  });

  String get artist => artists.join(', ');

  /// «Опенінґ 2», «Ендінґ»
  String get label => '${kind == SongKind.op ? 'Опенінґ' : 'Ендінґ'}${sequence > 0 ? ' $sequence' : ''}';

  bool covers(int episode) => episodes.isEmpty || episodes.any((r) => episode >= r.$1 && episode <= r.$2);

  /// How many episodes its ranges name (an open end counts as very many)
  int get span => episodes.fold(0, (n, r) => n + (r.$2 - r.$1 + 1));

  /// What to search for in a service: the artist and the title, the original ones when known (stores know them better
  /// than romaji)
  String get query => [
        if (nativeArtists.isNotEmpty) nativeArtists.first else if (artists.isNotEmpty) artists.first,
        native ?? title,
      ].join(' ');

  ThemeSong copyWith({
    int? sequence,
    String? native,
    List<String>? artists,
    List<String>? nativeArtists,
    List<(int, int)>? episodes,
    Map<MusicApp, String>? links,
  }) =>
      ThemeSong(
        kind: kind,
        title: title,
        sequence: sequence ?? this.sequence,
        native: native ?? this.native,
        artists: artists ?? this.artists,
        nativeArtists: nativeArtists ?? this.nativeArtists,
        episodes: episodes ?? this.episodes,
        links: links ?? this.links,
      );

  ThemeSong withLinks(Map<MusicApp, String> more) => copyWith(links: {...links, ...more});

  Map<String, Object> toJson() => {
        'k': kind.name,
        't': title,
        if (sequence > 0) 's': sequence,
        if (native != null) 'n': native!,
        if (artists.isNotEmpty) 'a': artists,
        if (nativeArtists.isNotEmpty) 'na': nativeArtists,
        if (episodes.isNotEmpty) 'e': [for (final r in episodes) [r.$1, r.$2]],
        if (links.isNotEmpty) 'l': {for (final e in links.entries) e.key.name: e.value},
      };

  static ThemeSong? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final kind = SongKind.values.asNameMap()[raw['k']];
    final title = raw['t'];
    if (kind == null || title is! String || title.isEmpty) return null;
    return ThemeSong(
      kind: kind,
      title: title,
      sequence: (raw['s'] as num?)?.toInt() ?? 0,
      native: raw['n'] as String?,
      artists: [for (final a in (raw['a'] as List?) ?? const []) '$a'],
      nativeArtists: [for (final a in (raw['na'] as List?) ?? const []) '$a'],
      episodes: [
        for (final r in (raw['e'] as List?) ?? const [])
          if (r is List && r.length == 2 && r[0] is num && r[1] is num) ((r[0] as num).toInt(), (r[1] as num).toInt()),
      ],
      links: {
        for (final e in ((raw['l'] as Map?) ?? const {}).entries)
          if (MusicApp.values.asNameMap()[e.key] case final s?) s: '${e.value}',
      },
    );
  }

  @override
  String toString() => '$label «$title»${artists.isEmpty ? '' : ' — $artist'}';
}

/// "1-12", "1-11, 13", "5", "13-", "158-???" → ranges; empty or unreadable: all episodes
List<(int, int)> parseEpisodes(String? spec) {
  if (spec == null) return const [];
  final out = <(int, int)>[];
  for (final part in spec.split(RegExp(r'[,;]'))) {
    final m = RegExp(r'^\s*(\d+)\s*(?:[-–—~]\s*(\d+|\?+)?)?\s*$').firstMatch(part);
    if (m == null) continue;
    final a = int.parse(m.group(1)!);
    final dash = part.contains(RegExp(r'[-–—~]'));
    final b = int.tryParse(m.group(2) ?? '') ?? (dash ? 9999 : a);
    out.add((a, b < a ? a : b));
  }
  return out;
}

/// The song of [kind] that plays in [episode]. Of the songs whose episodes are named, the narrowest (one named for
/// a single episode is surer there than the season's song); a song without episodes only when it is the one such song
/// of its kind — two of them, and which plays when is not known. Without a known episode number only a title's single
/// song counts
ThemeSong? pickSong(List<ThemeSong> all, SongKind kind, int? episode) {
  final list = [for (final s in all) if (s.kind == kind) s];
  if (list.isEmpty) return null;
  if (episode == null) return list.length == 1 ? list.single : null;
  ThemeSong? best;
  for (final s in list) {
    if (s.episodes.isNotEmpty && s.covers(episode) && (best == null || s.span < best.span)) best = s;
  }
  if (best != null) return best;
  final open = [for (final s in list) if (s.episodes.isEmpty) s];
  return open.length == 1 ? open.single : null;
}

/// Which app a link opens (by its address)
MusicApp? musicAppOf(String link) {
  final host = Uri.tryParse(link)?.host.toLowerCase() ?? '';
  if (host.endsWith('spotify.com')) return MusicApp.spotify;
  if (host == 'music.youtube.com') return MusicApp.youtubeMusic;
  if (host.endsWith('youtube.com') || host == 'youtu.be') return MusicApp.youtube;
  if (host == 'music.apple.com' || host.endsWith('itunes.apple.com')) return MusicApp.appleMusic;
  return null;
}

/// A search in [app] when there is no direct link
String searchLink(MusicApp app, String query) {
  final q = Uri.encodeComponent(query);
  return switch (app) {
    MusicApp.spotify => 'https://open.spotify.com/search/$q',
    MusicApp.youtubeMusic => 'https://music.youtube.com/search?q=$q',
    MusicApp.appleMusic => 'https://music.apple.com/search?term=$q',
    MusicApp.youtube => 'https://www.youtube.com/results?search_query=$q',
  };
}

String musicAppName(MusicApp s) => switch (s) {
      MusicApp.spotify => 'Spotify',
      MusicApp.youtubeMusic => 'YouTube Music',
      MusicApp.appleMusic => 'Apple Music',
      MusicApp.youtube => 'YouTube',
    };

// ── AnimeThemes ─────────────────────────────────────────────────────────────

/// AnimeThemes' GraphQL API (its REST API sits behind a browser check an app cannot pass: 503)
const String animeThemesGraphql = 'https://graphql.animethemes.moe/';

/// The request (a POST body) for the openings and endings of MyAnimeList's title [malId]: which plays in which
/// episodes, who sings them, links to the services
String animeThemesQuery(int malId) => jsonEncode({
      'query': '{ findAnimeByExternalSite(site: MAL, id: [$malId]) { slug animethemes { type sequence group { name } '
          'song { title { romaji native } performances { as alias artist { name { main native } } } resources { nodes { site link } } } '
          'animethemeentries { version episodes } } } }',
    });

/// The openings and endings in AnimeThemes' answer to [animeThemesQuery]. A theme of a group is another show's (the
/// «Yorinuki Gintama-san» reruns on Gintama's page, a dub's versions): only the title's own are taken while there are any
List<ThemeSong> songsOfAnimeThemes(Object? json) {
  final data = json is Map ? json['data'] : null;
  final found = data is Map ? data['findAnimeByExternalSite'] : null;
  final themes = <Map>[
    for (final a in found is List ? found : const [])
      if (a is Map)
        for (final t in (a['animethemes'] as List?) ?? const [])
          if (t is Map) t,
  ];
  final own = [for (final t in themes) if (t['group'] == null) t];
  return [
    for (final t in own.isEmpty ? themes : own)
      if (_songOfTheme(t) case final s?) s,
  ];
}

ThemeSong? _songOfTheme(Map t) {
  final type = '${t['type'] ?? ''}'.toUpperCase();
  final kind = type == 'OP' ? SongKind.op : (type == 'ED' ? SongKind.ed : null);
  final song = t['song'];
  if (kind == null || song is! Map) return null;
  final names = song['title'];
  final romaji = '${(names is Map ? names['romaji'] : names) ?? ''}'.trim();
  final native = '${(names is Map ? names['native'] : null) ?? ''}'.trim();
  final title = romaji.isNotEmpty ? romaji : native;
  if (title.isEmpty) return null;
  final performances = [for (final p in (song['performances'] as List?) ?? const []) if (p is Map) p];
  final artists = <String>{
    for (final p in performances)
      if (_performer(p) case final name?) name,
  };
  final nativeArtists = <String>{
    for (final p in performances)
      if (_nativeName(p) case final name?) name,
  };
  // The episodes of all its versions (v1 in 1–12, v2 in 13–24). A version without them adds none (Naruto's «GO!!!»:
  // v1 in 78–103 and a v2 nobody marked); none named at all: all episodes
  final eps = <(int, int)>[
    for (final e in (t['animethemeentries'] as List?) ?? const [])
      if (e is Map) ...parseEpisodes(e['episodes'] is String ? e['episodes'] as String : null),
  ];
  return ThemeSong(
    kind: kind,
    title: title,
    sequence: (t['sequence'] as num?)?.toInt() ?? 0,
    native: native.isEmpty || native == title ? null : native,
    artists: artists.toList(),
    nativeArtists: nativeArtists.toList(),
    episodes: eps,
    links: linksOf(song['resources']),
  );
}

/// Who sings: the name it was credited under, else the artist's name
String? _performer(Map p) {
  final alias = '${p['alias'] ?? ''}'.trim();
  if (alias.isNotEmpty) return alias;
  final a = p['artist'];
  final n = a is Map ? a['name'] : null;
  final main = '${(n is Map ? n['main'] : n) ?? ''}'.trim();
  return main.isEmpty ? null : main;
}

/// The artist's original name (ヨルシカ), when it differs from the Latin one
String? _nativeName(Map p) {
  final a = p['artist'];
  final n = a is Map ? a['name'] : null;
  final native = '${(n is Map ? n['native'] : null) ?? ''}'.trim();
  return native.isEmpty || native == '${(n is Map ? n['main'] : null) ?? ''}'.trim() ? null : native;
}

/// The services among a song's resources (`{nodes: [{site, link}]}` or the list itself)
Map<MusicApp, String> linksOf(Object? resources) {
  final list = resources is Map ? resources['nodes'] : resources;
  final out = <MusicApp, String>{};
  for (final r in list is List ? list : const []) {
    if (r is! Map) continue;
    final link = '${r['link'] ?? ''}';
    final app = musicAppOf(link);
    if (app != null) out[app] = link;
  }
  return out;
}

// ── Original titles ─────────────────────────────────────────────────────────

/// Japanese, Chinese or Korean letters
final RegExp _cjk = RegExp(r'[\u3040-\u30FF\u3400-\u9FFF\uAC00-\uD7AF\uFF00-\uFFEF]');

/// "Yuusha (勇者)" → ("Yuusha", "勇者"), "勇者 (Yuusha)" the same; brackets of the same script stay in the title
(String, String?) splitNative(String raw) {
  final s = raw.trim();
  final m = RegExp(r'^(.*\S)\s*\(([^()]+)\)$').firstMatch(s);
  if (m == null) return (s, null);
  final outer = m.group(1)!.trim();
  final inner = m.group(2)!.trim();
  final o = _cjk.hasMatch(outer);
  final i = _cjk.hasMatch(inner);
  if (i && !o) return (outer, inner);
  if (o && !i) return (inner, outer);
  return (s, null);
}

// ── MyAnimeList (through Tenrai) ────────────────────────────────────────────

/// MyAnimeList's openings and endings of a title through Tenrai (a free API of MyAnimeList's pages in Jikan's format;
/// Jikan itself is gone)
Uri tenraiThemes(int malId) => Uri.parse('https://api.tenrai.org/v1/anime/$malId/themes');

final RegExp _malLine = RegExp(r'^\s*(?:#?([A-Za-z]*)(\d+)\s*:\s*)?"(.+)"\s+by\s+(.+?)\s*$');
final RegExp _malEps = RegExp(r'\s*\((?:eps?|episodes?)\b\.?\s*([^)]*)\)', caseSensitive: false);
final RegExp _bracket = RegExp(r'\s*\(([^()]*)\)');
final RegExp _voice = RegExp(r'^CV\s*[:：.]', caseSensitive: false);

/// One line of MyAnimeList's themes: `1: "Haruka Mirai (ハルカミライ)" by Kankaku Piero (感覚ピエロ) (eps 1-13)`. A song of
/// the reruns or of a special broadcast («R1:», «S1:») is not the series' own: null
ThemeSong? songOfMalLine(String line, SongKind kind) {
  var s = line.trim();
  List<(int, int)> eps = const [];
  final em = _malEps.allMatches(s).lastOrNull;
  if (em != null) {
    eps = parseEpisodes(em.group(1));
    s = (s.substring(0, em.start) + s.substring(em.end)).trim();
  }
  final m = _malLine.firstMatch(s);
  if (m == null || (m.group(1) ?? '').isNotEmpty) return null;
  final (title, native) = splitNative(m.group(3)!);
  // "Kumi Koda (倖田來未)": the original name aside; a character's voice «(CV: …)» dropped
  final natives = <String>[];
  final artist = m.group(4)!.replaceAllMapped(_bracket, (b) {
    final inner = b.group(1)!.trim();
    if (_voice.hasMatch(inner)) return '';
    if (!_cjk.hasMatch(inner)) return b.group(0)!;
    natives.add(inner);
    return '';
  }).trim();
  if (title.isEmpty) return null;
  return ThemeSong(
    kind: kind,
    title: title,
    native: native,
    sequence: int.tryParse(m.group(2) ?? '') ?? 0,
    artists: artist.isEmpty ? const [] : [artist],
    nativeArtists: natives,
    episodes: eps,
  );
}

/// MyAnimeList's openings and endings in Tenrai's (Jikan's) answer: `{data: {openings: [...], endings: [...]}}`
List<ThemeSong> songsOfMal(Object? json) {
  final data = json is Map ? json['data'] : null;
  if (data is! Map) return const [];
  return [
    for (final l in (data['openings'] as List?) ?? const [])
      if (songOfMalLine('$l', SongKind.op) case final s?) s,
    for (final l in (data['endings'] as List?) ?? const [])
      if (songOfMalLine('$l', SongKind.ed) case final s?) s,
  ];
}

// ── Hikka ───────────────────────────────────────────────────────────────────

/// Hikka's songs of a title (its `ost`: «Yuusha (勇者)» by YOASOBI, opening 1, a Spotify link). Hikka does not say
/// which episodes they play in, and cuts the artist to the first word («Tommy» for Tommy heavenly⁶)
List<ThemeSong> songsOfHikka(List<HikkaOst> ost) {
  final out = <ThemeSong>[];
  for (final o in ost) {
    final kind = switch (o.type) { 'opening' => SongKind.op, 'ending' => SongKind.ed, _ => null };
    final raw = (o.title ?? '').trim();
    if (kind == null || raw.isEmpty) continue;
    final (title, native) = splitNative(raw);
    final author = (o.author ?? '').trim();
    final spotify = o.spotify;
    out.add(ThemeSong(
      kind: kind,
      title: title,
      native: native,
      sequence: o.index,
      artists: author.isEmpty ? const [] : [author],
      links: spotify != null && musicAppOf(spotify) == MusicApp.spotify ? {MusicApp.spotify: spotify} : const {},
    ));
  }
  // A title's only opening has no number (as AnimeThemes writes it)
  return [
    for (final s in out)
      if (s.sequence == 1 && out.where((x) => x.kind == s.kind).length == 1) s.copyWith(sequence: 0) else s,
  ];
}

// ── Together ────────────────────────────────────────────────────────────────

/// A title's songs from all three: AnimeThemes' when it has the title (the episodes of every version), else
/// MyAnimeList's (episodes too, a little rougher), else Hikka's list (none). MyAnimeList fills in what AnimeThemes
/// lacks — artists (AnimeThemes names no one for Black Clover's «Haruka Mirai»), original titles and names; Hikka adds
/// Spotify links
List<ThemeSong> combineSongs({List<ThemeSong>? animeThemes, List<ThemeSong>? mal, List<ThemeSong>? hikka}) {
  final at = animeThemes ?? const <ThemeSong>[];
  final m = mal ?? const <ThemeSong>[];
  final h = hikka ?? const <ThemeSong>[];
  final base = at.isNotEmpty ? enrichSongs(at, m, full: true) : m;
  return base.isEmpty ? h : enrichSongs(base, h);
}

/// [base] with what [other] knows of the same songs: original titles and artist names, links; with [full] also the
/// artists and episodes [base] does not name (not from Hikka: its artists are cut short)
List<ThemeSong> enrichSongs(List<ThemeSong> base, List<ThemeSong> other, {bool full = false}) => [
      for (final s in base)
        if (_twinIn(s, base, other) case final o?)
          s.copyWith(
            native: s.native ?? o.native,
            nativeArtists: s.nativeArtists.isEmpty ? o.nativeArtists : null,
            artists: full && s.artists.isEmpty ? o.artists : null,
            episodes: full && s.episodes.isEmpty ? o.episodes : null,
            links: {...o.links, ...s.links},
          )
        else
          s,
    ];

/// [s] (one of [base]) among [other]: by its title, and by the artist when the title is not enough (Black Clover has
/// «four» by FAKY and «four» by Megumi Han); else, romanized another way, by its number and artist
ThemeSong? _twinIn(ThemeSong s, List<ThemeSong> base, List<ThemeSong> other) {
  final found = [for (final o in other) if (o.kind == s.kind && _sameTitle(s, o)) o];
  final namesakes = base.where((b) => b.kind == s.kind && _sameTitle(s, b)).length;
  if (found.length == 1 && namesakes == 1) return found.single;
  for (final o in found) {
    if (_sameArtist(s, o)) return o;
  }
  if (found.isNotEmpty) return null;
  for (final o in other) {
    if (o.kind == s.kind && s.sequence > 0 && o.sequence == s.sequence && _sameArtist(s, o)) return o;
  }
  return null;
}

bool _sameTitle(ThemeSong a, ThemeSong b) {
  final names = {_norm(a.title), if (a.native != null) _norm(a.native!)}..remove('');
  return names.contains(_norm(b.title)) || (b.native != null && names.contains(_norm(b.native!)));
}

bool _sameArtist(ThemeSong a, ThemeSong b) {
  for (final x in [...a.artists, ...a.nativeArtists].map(_norm)) {
    for (final y in [...b.artists, ...b.nativeArtists].map(_norm)) {
      if (x.isNotEmpty && y.isNotEmpty && (x.contains(y) || y.contains(x))) return true;
    }
  }
  return false;
}

// ── Covers: the stores ──────────────────────────────────────────────────────

/// A cover and a store link found for a song
class SongArt {
  final String? cover;
  final String? appleMusic;
  const SongArt({this.cover, this.appleMusic});

  Map<String, Object> toJson() => {if (cover != null) 'c': cover!, if (appleMusic != null) 'am': appleMusic!};
  static SongArt fromJson(Object? raw) => raw is Map ? SongArt(cover: raw['c'] as String?, appleMusic: raw['am'] as String?) : const SongArt();
}

String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[\s\p{P}\p{S}]+', unicode: true), '');

/// Versions of a song that are not it: live, instrumental, covers, music boxes…
final RegExp _notTheSong = RegExp(
  r'live|instrumental|off vocal|karaoke|tv size|tv ver|cover|piano|acoustic|remix|orgel|music box|inst\.|ライブ|オルゴール|カラオケ|ピアノ',
  caseSensitive: false,
);

/// How well a store's track ([track], [artist], [album]) is [song]: null — not it
int? matchScore(ThemeSong song, {required String track, required String artist, String album = ''}) {
  final a = _norm(artist);
  final ours = [for (final x in [...song.artists, ...song.nativeArtists]) _norm(x)];
  if (a.isEmpty || !ours.any((o) => o.isNotEmpty && (a == o || a.contains(o) || o.contains(a)))) return null;
  final t = _norm(track);
  final titles = [_norm(song.title), if (song.native != null) _norm(song.native!)]..removeWhere((x) => x.isEmpty);
  final exact = titles.any((x) => t == x);
  final starts = titles.any((x) => t.startsWith(x));
  if (!exact && !starts) return null;
  var score = exact ? 10 : 5;
  final ourText = '${song.title} ${song.native ?? ''}';
  if (_notTheSong.hasMatch('$track $album') && !_notTheSong.hasMatch(ourText)) score -= 8;
  if (album.endsWith('- Single') || _norm(album) == t) score += 2;
  return score;
}

/// The song in an iTunes Search answer (`results`: trackName, artistName, collectionName, artworkUrl100, trackViewUrl)
SongArt? artOfItunes(ThemeSong song, Object? json) {
  if (json is! Map) return null;
  Map? best;
  var top = 0;
  for (final r in (json['results'] as List?) ?? const []) {
    if (r is! Map || (r['kind'] != null && r['kind'] != 'song')) continue;
    final s = matchScore(song, track: '${r['trackName'] ?? ''}', artist: '${r['artistName'] ?? ''}', album: '${r['collectionName'] ?? ''}');
    if (s != null && s > top) {
      top = s;
      best = r;
    }
  }
  if (best == null || top <= 0) return null;
  final art = best['artworkUrl100'] as String?;
  final link = (best['trackViewUrl'] as String?)?.replaceAll(RegExp(r'[&?]uo=\d+'), '');
  return SongArt(cover: art?.replaceAll(RegExp(r'/\d+x\d+bb\.'), '/300x300bb.'), appleMusic: link);
}

/// The song in a Deezer search answer (`data`: title, artist.name, album.title, album.cover_big)
SongArt? artOfDeezer(ThemeSong song, Object? json) {
  if (json is! Map) return null;
  Map? best;
  var top = 0;
  for (final r in (json['data'] as List?) ?? const []) {
    if (r is! Map) continue;
    final artist = r['artist'] is Map ? '${(r['artist'] as Map)['name'] ?? ''}' : '';
    final album = r['album'] is Map ? r['album'] as Map : const {};
    final s = matchScore(song, track: '${r['title'] ?? ''}', artist: artist, album: '${album['title'] ?? ''}');
    if (s != null && s > top) {
      top = s;
      best = album;
    }
  }
  if (best == null || top <= 0) return null;
  final cover = (best['cover_big'] ?? best['cover_medium']) as String?;
  return cover == null ? null : SongArt(cover: cover);
}

/// The track id in an Apple Music link (`…/album/x/123?i=456` → 456, `…/song/x/456` → 456)
String? appleTrackId(String link) {
  final uri = Uri.tryParse(link);
  if (uri == null) return null;
  final i = uri.queryParameters['i'];
  if (i != null && RegExp(r'^\d+$').hasMatch(i)) return i;
  final segs = uri.pathSegments;
  final at = segs.indexOf('song');
  if (at >= 0 && segs.isNotEmpty && RegExp(r'^\d+$').hasMatch(segs.last)) return segs.last;
  return null;
}

/// The store of an Apple Music link (`music.apple.com/jp/…` → `JP`): a lookup finds a track only in its own store
String? appleCountry(String link) {
  final segs = Uri.tryParse(link)?.pathSegments ?? const <String>[];
  return segs.isNotEmpty && RegExp(r'^[a-z]{2}$').hasMatch(segs.first) ? segs.first.toUpperCase() : null;
}

/// The cover of an iTunes lookup answer (by the track's id)
String? coverOfItunesLookup(Object? json) {
  if (json is! Map) return null;
  for (final r in (json['results'] as List?) ?? const []) {
    if (r is Map && r['artworkUrl100'] is String) return (r['artworkUrl100'] as String).replaceAll(RegExp(r'/\d+x\d+bb\.'), '/300x300bb.');
  }
  return null;
}

/// The cover of a Spotify oEmbed answer
String? coverOfSpotify(Object? json) => json is Map && json['thumbnail_url'] is String ? json['thumbnail_url'] as String : null;
