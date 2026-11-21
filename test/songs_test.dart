// The songs of openings and endings: reading AnimeThemes' GraphQL answers, MyAnimeList's themes (through Tenrai) and
// Hikka's song lists and putting them together, which song plays in which episode, covers from the stores, links to the
// apps, the service with its disk copy. Real answers in test/data/songs (AnimeThemes and Tenrai for Frieren, Gintama,
// Black Clover…, Hikka's Gintama and Black Clover, Apple Music, Deezer, Spotify). No network.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:miki_miki/models/hikka_models.dart';
import 'package:miki_miki/services/songs/song_service.dart';
import 'package:miki_miki/services/songs/theme_songs.dart';

Object fixture(String name) => jsonDecode(File('test/data/songs/$name').readAsStringSync());

const yuusha = ThemeSong(kind: SongKind.op, title: 'Yuusha', native: '勇者', artists: ['YOASOBI'], sequence: 1);

/// Hikka's song lists: Frieren's (from the sample of its page) and Gintama's
List<HikkaOst> ostOf(Object json) => [for (final o in (json as Map)['ost'] as List) HikkaOst.fromJson(o as Map<String, dynamic>)];
final frierenOst = ostOf(jsonDecode(File('test/data/hikka_samples/info.json').readAsStringSync()));
final gintamaOst = ostOf(fixture('hikka_ost_gintama.json'));

/// The real Frieren answer with links on «Yuusha» (AnimeThemes has none for it yet)
String frierenWithLinks() {
  final j = fixture('animethemes_graphql_frieren.json') as Map;
  final themes = (j['data']['findAnimeByExternalSite'] as List).first['animethemes'] as List;
  final op = themes.firstWhere((t) => t['song']['title']['romaji'] == 'Yuusha');
  op['song']['resources'] = {
    'nodes': [
      {'site': 'Apple Music', 'link': 'https://music.apple.com/jp/album/x/1707001460?i=1707001466'},
      {'site': 'YouTube', 'link': 'https://www.youtube.com/watch?v=y'},
      {'site': 'Spotify', 'link': 'https://open.spotify.com/track/x'},
      {'site': 'AniDB', 'link': 'https://anidb.net/song/1'},
    ],
  };
  return jsonEncode(j);
}

/// A fake of the services by host and path
class FakeWeb {
  final List<Uri> asked = [];
  final List<String> bodies = [];
  bool down = false;
  bool themesDown = false;
  bool animeThemesKnows = true;
  bool tenraiDown = false;

  Future<(int, String)> get(Uri u, {String? body}) async {
    asked.add(u);
    if (body != null) bodies.add(body);
    if (down) throw const SocketException('offline');
    String file(String n) => File('test/data/songs/$n').readAsStringSync();
    switch ((u.host, u.path)) {
      case ('graphql.animethemes.moe', '/'):
        if (themesDown) return (503, '<html>Just a moment...</html>');
        if (!animeThemesKnows || body == null) return (200, '{"data":{"findAnimeByExternalSite":[]}}');
        if (body.contains('id: [918]')) return (200, file('animethemes_graphql_gintama.json'));
        if (body.contains('id: [52991]')) return (200, frierenWithLinks());
        return (200, '{"data":{"findAnimeByExternalSite":[]}}');
      case ('api.tenrai.org', final path):
        if (tenraiDown) return (429, '{"status":429}');
        final name = {'/v1/anime/52991/themes': 'frieren', '/v1/anime/918/themes': 'gintama', '/v1/anime/34572/themes': 'black_clover'}[path];
        return name == null ? (404, '{"status":404,"type":"ResourceNotFoundException"}') : (200, file('tenrai_$name.json'));
      case ('itunes.apple.com', '/lookup'):
        return (200, file('itunes_lookup.json'));
      case ('itunes.apple.com', '/search'):
        return (200, file('itunes_yuusha.json'));
      case ('api.deezer.com', _):
        return (200, file('deezer_yuusha.json'));
      case ('open.spotify.com', '/oembed'):
        return (200, file('spotify_oembed_pray.json'));
    }
    return (404, '{}');
  }
}

void main() {
  group('Reading', () {
    test('episode ranges', () {
      expect(parseEpisodes('1-12'), [(1, 12)]);
      expect(parseEpisodes('1-14, 16'), [(1, 14), (16, 16)]);
      expect(parseEpisodes('5'), [(5, 5)]);
      expect(parseEpisodes('17-'), [(17, 9999)]);
      expect(parseEpisodes('2–4'), [(2, 4)]);
      expect(parseEpisodes(''), isEmpty);
      expect(parseEpisodes(null), isEmpty);
      expect(parseEpisodes('BD only'), isEmpty);
    });

    test('AnimeThemes: openings and endings with their episodes (Frieren)', () {
      final songs = songsOfAnimeThemes(fixture('animethemes_graphql_frieren.json'));
      expect(songs.map((s) => '$s'), [
        'Опенінґ 1 «Yuusha» — YOASOBI',
        'Ендінґ 1 «Anytime Anywhere» — milet',
        'Опенінґ 2 «Haru» — Yorushika',
      ], reason: '«bliss» of the first episode\'s TV version (a group) is not the episode\'s own ending');
      expect(songs[1].episodes, [(1, 14), (16, 16), (17, 27), (28, 28)], reason: 'every version counts');
      expect(songs.map((s) => s.native), everyElement(isNull), reason: 'AnimeThemes has no original titles here');
      expect(songsOfAnimeThemes(jsonDecode('{"data":{"findAnimeByExternalSite":[]}}')), isEmpty);
      expect(songsOfAnimeThemes(jsonDecode('{"errors":[{"message":"x"}]}')), isEmpty);
      final q = jsonDecode(animeThemesQuery(52991)) as Map;
      expect(q['query'], contains('findAnimeByExternalSite(site: MAL, id: [52991])'));
      expect(q['query'], contains('group { name }'));
    });

    test('AnimeThemes: another show\'s themes on the page (a group) are not taken; who sings', () {
      final songs = songsOfAnimeThemes(fixture('animethemes_graphql_gintama.json'));
      expect(songs.where((s) => s.kind == SongKind.op).length, 8);
      expect(songs.where((s) => s.kind == SongKind.ed).length, 16);
      expect(songs.any((s) => s.title == 'Bakuchi Dancer'), isFalse, reason: '«Yorinuki Gintama-san» is another show');
      expect(pickSong(songs, SongKind.op, 1)!.title, 'Pray');
      expect(pickSong(songs, SongKind.ed, 71)!.title, 'Kiseki');
      expect(pickSong(songs, SongKind.op, 183)!.title, 'Light Infection');
      expect(songs.firstWhere((s) => s.title == 'Wo Ai Ni').artists, ['BEAT CRUSADERS', 'Hitomi Takahashi']);
      expect('${songs.firstWhere((s) => s.title == 'Fuusen Gum')}', 'Ендінґ 1 «Fuusen Gum»', reason: 'nobody named');
      // A band of four members sings once; a name it was credited under goes first
      final band = songsOfAnimeThemes({
        'data': {
          'findAnimeByExternalSite': [
            {
              'animethemes': [
                {
                  'type': 'OP',
                  'sequence': null,
                  'group': null,
                  'song': {
                    'title': {'romaji': 'Seishun Complex', 'native': '青春コンプレックス'},
                    'performances': [
                      for (var i = 0; i < 4; i++) {'as': null, 'alias': null, 'artist': {'name': {'main': 'Kessoku Band'}}},
                      {'as': null, 'alias': 'Hitori Gotoh', 'artist': {'name': {'main': 'Yoshino Aoyama'}}},
                    ],
                    'resources': {'nodes': []},
                  },
                  'animethemeentries': [{'version': 1, 'episodes': null}],
                },
              ],
            },
          ],
        },
      }).single;
      expect(band.artists, ['Kessoku Band', 'Hitori Gotoh']);
      expect((band.sequence, band.native, band.label), (0, '青春コンプレックス', 'Опенінґ'));
      expect(band.episodes, isEmpty, reason: 'a version without episodes: all of them');
    });

    test('long shows: the opening of every arc (Black Clover, Naruto, «Монолог травниці» 2)', () {
      String? op(List<ThemeSong> l, int ep) => pickSong(l, SongKind.op, ep)?.title;
      String? ed(List<ThemeSong> l, int ep) => pickSong(l, SongKind.ed, ep)?.title;

      final bc = songsOfAnimeThemes(fixture('animethemes_graphql_black_clover.json'));
      expect(bc.where((s) => s.kind == SongKind.op).length, 13);
      expect([for (final e in [1, 13, 14, 19, 27, 28, 64, 65, 100, 128, 129, 170]) op(bc, e)], [
        'Haruka Mirai', 'Haruka Mirai', 'PAiNT it BLACK', 'PAiNT it BLACK', 'PAiNT it BLACK', 'Black Rover', //
        'Gamushara', 'Rakugaki Page', 'sky&blue', 'Black Catcher', 'Stories', 'Grandeur',
      ]);
      expect(ed(bc, 1), isNull, reason: 'the first ending starts with episode 2');
      expect((pickSong(bc, SongKind.ed, 49)!.artist, pickSong(bc, SongKind.ed, 50)!.artist), ('FAKY', 'Megumi Han'), reason: 'two «four»');
      expect(ed(bc, 118), isNull, reason: 'nothing is listed for it');

      final naruto = songsOfAnimeThemes(fixture('animethemes_graphql_naruto.json'));
      expect(naruto.firstWhere((s) => s.title == 'GO!!!').episodes, [(78, 103)], reason: 'its second version names no episodes');
      expect([op(naruto, 1), op(naruto, 90), op(naruto, 150), op(naruto, 220)], ['R★O★C★K★S', 'GO!!!', 'No Boy, No Cry', 'YURA YURA']);
      expect(ed(naruto, 60), 'Viva Rock ~Japanese Side~');
      expect(naruto.any((s) => s.title == 'LIFE GOES ON'), isFalse, reason: 'the «Naruto Shounen-hen» reruns');

      final kusuriya = songsOfAnimeThemes(fixture('animethemes_graphql_kusuriya2.json'));
      expect([op(kusuriya, 5), ed(kusuriya, 5), op(kusuriya, 15), ed(kusuriya, 15)], ['Hyakka Ryouran', 'Shiawase no Recipe', 'Kusushiki', 'Hitorigoto']);
      expect(kusuriya.length, 4, reason: 'an insert song is neither');
    });

    test('MyAnimeList through Tenrai: «1: "Haruka Mirai (ハルカミライ)" by Kankaku Piero (感覚ピエロ) (eps 1-13)»', () {
      final bc = songsOfMal(fixture('tenrai_black_clover.json'));
      final mirai = bc.first;
      expect((mirai.kind, mirai.sequence, mirai.title, mirai.native, mirai.artist), (SongKind.op, 1, 'Haruka Mirai', 'ハルカミライ', 'Kankaku Piero'));
      expect(mirai.nativeArtists, ['感覚ピエロ']);
      expect(mirai.episodes, [(1, 13)]);
      expect(mirai.query, '感覚ピエロ ハルカミライ', reason: 'the stores know the originals');
      expect(bc.firstWhere((s) => s.title == 'Grandeur').episodes, [(158, 9999)], reason: '«eps 158-???»: still airing');
      // Gintama: the reruns' songs («R1:») are another show's
      final gintama = songsOfMal(fixture('tenrai_gintama.json'));
      expect(gintama.where((s) => s.kind == SongKind.op).length, 8);
      expect(gintama.any((s) => s.title == 'Bakuchi Dancer'), isFalse);
      expect(gintama.firstWhere((s) => s.title == 'Fuusen Gum').artist, 'Captain Straydum');
      // Frieren: the special broadcast's ending («S1:») is not taken; «eps 1-14,16-28»
      final frieren = songsOfMal(fixture('tenrai_frieren.json'));
      expect(frieren.map((s) => '$s'), ['Опенінґ 1 «Yuusha» — YOASOBI', 'Опенінґ 2 «Haru» — Yorushika', 'Ендінґ 1 «Anytime Anywhere» — milet']);
      expect(frieren.last.episodes, [(1, 14), (16, 28)]);
      // Lines of other shapes
      final single = songOfMalLine('"AIYOU" by Eve', SongKind.ed)!;
      expect((single.sequence, single.title, single.artist, single.episodes.isEmpty), (0, 'AIYOU', 'Eve', true));
      expect(songOfMalLine('3: "Hitoribocchi Tokyo" by Hitori Gotou (CV: Yoshino Aoyama) (ep 5)', SongKind.ed)!.artist, 'Hitori Gotou');
      expect(songOfMalLine('#2: "Unravel" by TK from Ling tosite sigure (eps. 1-11, 25)', SongKind.op)!.episodes, [(1, 11), (25, 25)]);
      expect(songOfMalLine('no quotes here', SongKind.op), isNull);
      expect(songsOfMal(const {}), isEmpty, reason: 'Tenrai\'s 404');
    });

    test('all three together: AnimeThemes\' episodes, MyAnimeList\'s artists and originals, Hikka\'s Spotify', () {
      final bc = combineSongs(
        animeThemes: songsOfAnimeThemes(fixture('animethemes_graphql_black_clover.json')),
        mal: songsOfMal(fixture('tenrai_black_clover.json')),
        hikka: songsOfHikka(ostOf(fixture('hikka_ost_black_clover.json'))),
      );
      final mirai = bc.firstWhere((s) => s.title == 'Haruka Mirai');
      expect((mirai.artist, mirai.native), ('Kankaku Piero', 'ハルカミライ'), reason: 'AnimeThemes names no one; Hikka says «Kankaku»');
      expect(mirai.nativeArtists, ['感覚ピエロ']);
      expect(mirai.links[MusicApp.spotify], endsWith('6ytsH3HsHxz3TYVOiaBSA7'));
      expect(bc.firstWhere((s) => s.title == 'Rakugaki Page').episodes, [(65, 76)], reason: 'AnimeThemes\' episodes, not MyAnimeList\'s 65-79');
      // Two «four»: MyAnimeList and Hikka know FAKY's only
      final fours = bc.where((s) => s.title == 'four').toList();
      expect([for (final s in fours) s.artist], ['FAKY', 'Megumi Han']);
      expect([for (final s in fours) s.links[MusicApp.spotify] != null], [true, false]);
      expect([for (final s in fours) s.nativeArtists.length], [0, 0]);
      // AnimeThemes' artist stays as it writes it; the original name comes from MyAnimeList
      final guess = bc.firstWhere((s) => s.title == 'Guess Who Is Back');
      expect(guess.artist, 'Kumi Kouda');
      expect(guess.nativeArtists, ['倖田來未']);

      final gintama = combineSongs(
        animeThemes: songsOfAnimeThemes(fixture('animethemes_graphql_gintama.json')),
        mal: songsOfMal(fixture('tenrai_gintama.json')),
        hikka: songsOfHikka(gintamaOst),
      );
      expect(gintama.firstWhere((s) => s.title == 'Fuusen Gum').artist, 'Captain Straydum', reason: 'not Hikka\'s «Captain»');
      expect(gintama.firstWhere((s) => s.title == 'Pray').artist, 'Tommy heavenly⁶');
      expect(gintama.where((s) => s.links.isNotEmpty).length, 24);

      final naruto = combineSongs(animeThemes: songsOfAnimeThemes(fixture('animethemes_graphql_naruto.json')), mal: songsOfMal(fixture('tenrai_naruto.json')));
      final op150 = pickSong(naruto, SongKind.op, 150)!;
      expect('$op150', 'Опенінґ 6 «No Boy, No Cry» — Stance Punks');
      expect(op150.native, 'ノーボーイ・ノークライ');

      // AnimeThemes without the title: MyAnimeList's episodes; neither: Hikka's list (the only ending, of two openings none)
      final malOnly = combineSongs(animeThemes: const [], mal: songsOfMal(fixture('tenrai_frieren.json')), hikka: songsOfHikka(frierenOst));
      expect([pickSong(malOnly, SongKind.op, 5)?.title, pickSong(malOnly, SongKind.op, 20)?.title], ['Yuusha', 'Haru']);
      final hikkaOnly = combineSongs(hikka: songsOfHikka(frierenOst));
      expect([pickSong(hikkaOnly, SongKind.op, 5)?.title, pickSong(hikkaOnly, SongKind.ed, 5)?.title], [null, 'Anytime Anywhere']);
    });

    test('Hikka: «Yuusha (勇者)», a Spotify link; under AnimeThemes\' songs: originals and links, not its artists', () {
      expect(splitNative('Yuusha (勇者)'), ('Yuusha', '勇者'));
      expect(splitNative('勇者 (Yuusha)'), ('Yuusha', '勇者'));
      expect(splitNative('Shinzou wo Sasageyo! (Sasageyo)'), ('Shinzou wo Sasageyo! (Sasageyo)', null));
      expect(splitNative('Pray'), ('Pray', null));
      final frieren = songsOfHikka(frierenOst);
      expect(frieren.map((s) => '$s'), ['Опенінґ 1 «Yuusha» — YOASOBI', 'Опенінґ 2 «Haru» — Yorushika', 'Ендінґ «Anytime Anywhere» — milet']);
      expect(frieren.map((s) => s.native), ['勇者', '晴る', null]);
      final merged = enrichSongs(songsOfAnimeThemes(fixture('animethemes_graphql_frieren.json')), frieren);
      expect(merged.map((s) => s.native), ['勇者', null, '晴る']);
      expect(merged.map((s) => s.label), ['Опенінґ 1', 'Ендінґ 1', 'Опенінґ 2'], reason: 'AnimeThemes\' numbering');

      final gintama = enrichSongs(songsOfAnimeThemes(fixture('animethemes_graphql_gintama.json')), songsOfHikka(gintamaOst));
      final pray = gintama.firstWhere((s) => s.title == 'Pray');
      expect(pray.links, {MusicApp.spotify: 'https://open.spotify.com/track/5DBOBP2zmNUXSOzb7Syywd'});
      expect(pray.artists, ['Tommy heavenly⁶'], reason: 'Hikka cuts it to «Tommy»');
      expect(gintama.firstWhere((s) => s.title == 'Tooi Nioi').native, '遠い匂い');
      expect(gintama.firstWhere((s) => s.title == 'Fuusen Gum').artists, isEmpty, reason: 'not «Captain»');
      expect(gintama.where((s) => s.links.isNotEmpty).length, 24);
    });

    test('which song plays in which episode', () {
      final songs = songsOfAnimeThemes(fixture('animethemes_graphql_frieren.json'));
      expect(pickSong(songs, SongKind.op, 5)!.title, 'Yuusha');
      expect(pickSong(songs, SongKind.op, 20)!.title, 'Haru');
      expect(pickSong(songs, SongKind.ed, 20)!.title, 'Anytime Anywhere');
      expect(pickSong(songs, SongKind.ed, 15), isNull, reason: 'no song is named for it');
      expect(pickSong(songs, SongKind.op, null), isNull, reason: 'two openings, the number unknown');
      expect(pickSong(songs, SongKind.ed, null)!.title, 'Anytime Anywhere', reason: 'the only ending');
      // A song named for a single episode is surer there than the season's
      const special = [
        ThemeSong(kind: SongKind.ed, title: 'Season', sequence: 1, episodes: [(1, 14), (16, 16)]),
        ThemeSong(kind: SongKind.ed, title: 'Special', episodes: [(1, 1)]),
      ];
      expect(pickSong(special, SongKind.ed, 1)!.title, 'Special');
      expect(pickSong(special, SongKind.ed, 2)!.title, 'Season');
      // Hikka's list alone: no episodes, so of two openings neither; the only ending in every episode
      final hikka = songsOfHikka(frierenOst);
      expect(pickSong(hikka, SongKind.op, 5), isNull);
      expect(pickSong(hikka, SongKind.ed, 5)!.title, 'Anytime Anywhere');
      expect(pickSong(hikka, SongKind.ed, null)!.title, 'Anytime Anywhere');
      // Named episodes first; past them, the one song without
      const mixed = [ThemeSong(kind: SongKind.op, title: 'A', sequence: 1, episodes: [(1, 12)]), ThemeSong(kind: SongKind.op, title: 'B', sequence: 2)];
      expect(pickSong(mixed, SongKind.op, 5)!.title, 'A');
      expect(pickSong(mixed, SongKind.op, 15)!.title, 'B');
    });

    test('a song survives the disk', () {
      final s = yuusha.withLinks({MusicApp.spotify: 'https://open.spotify.com/track/x'});
      final back = ThemeSong.fromJson(jsonDecode(jsonEncode(s.toJson())))!;
      expect('$back', '$s');
      expect(back.native, '勇者');
      expect(back.links, {MusicApp.spotify: 'https://open.spotify.com/track/x'});
    });
  });

  group('Covers and links', () {
    test('Apple Music: the song itself (the single), not a live or a cover; a larger picture; a clean link', () {
      final art = artOfItunes(yuusha, fixture('itunes_yuusha.json'))!;
      expect(art.cover, endsWith('/300x300bb.jpg'));
      expect(art.appleMusic, startsWith('https://music.apple.com/jp/album/'));
      expect(art.appleMusic, contains('1707001460'), reason: 'the single, not THE BOOK 3');
      expect(art.appleMusic, isNot(contains('uo=')));
      // Another artist's song of that name is not it
      expect(artOfItunes(const ThemeSong(kind: SongKind.op, title: 'Yuusha', native: '勇者', artists: ['Somebody']), fixture('itunes_yuusha.json')), isNull);
    });

    test('Deezer: the same rules', () {
      final art = artOfDeezer(yuusha, fixture('deezer_yuusha.json'))!;
      expect(art.cover, contains('/500x500-'));
      expect(matchScore(yuusha, track: '勇者 (YOASOBI 5th ANNIVERSARY DOME LIVE 2024)', artist: 'YOASOBI')!, lessThan(matchScore(yuusha, track: '勇者', artist: 'YOASOBI')!));
      expect(matchScore(yuusha, track: 'アイドル', artist: 'YOASOBI'), isNull, reason: 'another song of the artist');
    });

    test('the song\'s own page: Apple Music\'s lookup (in its store), Spotify\'s embed', () {
      expect(coverOfItunesLookup(fixture('itunes_lookup.json')), endsWith('/197189862939.jpg/300x300bb.jpg'));
      expect(coverOfSpotify(fixture('spotify_oembed_pray.json')), startsWith('https://image-cdn-'));
      expect(appleTrackId('https://music.apple.com/jp/album/x/1707001460?i=1707001466'), '1707001466');
      expect(appleTrackId('https://music.apple.com/us/song/x/42'), '42');
      expect(appleCountry('https://music.apple.com/jp/album/x/1?i=2'), 'JP');
      expect(appleCountry('https://music.apple.com/album/x/1?i=2'), isNull);
    });

    test('where to listen: a direct link when known, else a search', () {
      final song = yuusha.withLinks({MusicApp.spotify: 'https://open.spotify.com/track/x', MusicApp.youtube: 'https://www.youtube.com/watch?v=y'});
      final links = SongService.linksFor(song, art: const SongArt(appleMusic: 'https://music.apple.com/jp/album/a/1?i=2'));
      expect(links.map((l) => (l.app, l.direct)), [
        (MusicApp.spotify, true),
        (MusicApp.youtubeMusic, false),
        (MusicApp.appleMusic, true),
        (MusicApp.youtube, true),
      ]);
      expect(links[1].url, 'https://music.youtube.com/search?q=YOASOBI%20%E5%8B%87%E8%80%85');
      expect(searchLink(MusicApp.spotify, 'milet Anytime Anywhere'), 'https://open.spotify.com/search/milet%20Anytime%20Anywhere');
      expect(musicAppOf('https://youtu.be/x'), MusicApp.youtube);
      expect(musicAppOf('https://music.youtube.com/watch?v=x'), MusicApp.youtubeMusic);
      expect(musicAppOf('https://anidb.net/song/1'), isNull);
      expect(linksOf({'nodes': [{'site': 'Spotify', 'link': 'https://open.spotify.com/track/z'}, {'site': 'AniDB', 'link': 'https://anidb.net/song/1'}]}), {MusicApp.spotify: 'https://open.spotify.com/track/z'});
    });
  });

  group('The service', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('songs'));
    tearDown(() => dir.deleteSync(recursive: true));

    const titles = {'hikka:frieren': 52991, 'hikka:gintama': 918};

    SongService make(FakeWeb web, {DateTime Function()? now}) => SongService(
          get: web.get,
          cachePath: '${dir.path}/songs.json',
          malId: (k) async => titles[k],
          ost: (k) async => switch (k) { 'hikka:frieren' => songsOfHikka(frierenOst), 'hikka:gintama' => songsOfHikka(gintamaOst), _ => null },
          now: now,
          enabled: () => true,
        );

    Future<void> settle(SongService s, {int covers = 1}) async {
      for (var i = 0; i < 50 && (s.current.value?.art.length ?? 0) < covers; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    }

    Iterable<Uri> graphql(FakeWeb web) => web.asked.where((u) => u.host == 'graphql.animethemes.moe');

    test('the episode playing: AnimeThemes\' songs with MyAnimeList\'s and Hikka\'s originals, links, a cover from the song\'s own page', () async {
      final web = FakeWeb();
      final s = make(web);
      await s.attach(animeKey: 'hikka:frieren', epKey: '5', number: 5);
      await settle(s);
      final eps = s.current.value!;
      expect(eps.key, 'hikka:frieren#5');
      expect((eps.op!.title, eps.op!.native, eps.ed!.title), ('Yuusha', '勇者', 'Anytime Anywhere'));
      expect(eps.op!.links.keys, unorderedEquals([MusicApp.spotify, MusicApp.appleMusic, MusicApp.youtube]));
      expect(eps.art[SongKind.op]!.cover, endsWith('/197189862939.jpg/300x300bb.jpg'));
      expect(eps.art[SongKind.ed], isNull, reason: 'the stores did not find milet in these answers');
      expect(web.bodies.first, contains('id: [52991]'), reason: 'one POST to the GraphQL API');
      expect(web.asked.where((u) => u.host == 'api.tenrai.org').map((u) => u.path), ['/v1/anime/52991/themes']);
      final lookup = web.asked.firstWhere((u) => u.path == '/lookup');
      expect((lookup.queryParameters['id'], lookup.queryParameters['country']), ('1707001466', 'JP'));

      // Another episode: the second opening; the title's songs are not asked again
      final before = graphql(web).length;
      await s.attach(animeKey: 'hikka:frieren', epKey: '20', number: 20);
      expect((s.current.value!.op!.title, s.current.value!.ed!.title), ('Haru', 'Anytime Anywhere'));
      expect(graphql(web).length, before);
      expect(web.asked.where((u) => u.host == 'api.tenrai.org').length, 1);

      // Unknown numbering: of two openings neither (rather than the wrong one); the only ending
      await s.attach(animeKey: 'hikka:frieren', epKey: 'i3', number: null);
      expect(s.current.value!.op, isNull);
      expect(s.current.value!.ed!.title, 'Anytime Anywhere');
      // Not a Hikka title: no MyAnimeList id, no list
      await s.attach(animeKey: 'src:x', epKey: '1', number: 1);
      expect(s.current.value, isNull);
      s.detach();
    });

    test('Hikka\'s Spotify links: the cover from Spotify; the artist AnimeThemes does not name — from MyAnimeList', () async {
      final web = FakeWeb();
      final s = make(web);
      await s.attach(animeKey: 'hikka:gintama', epKey: '1', number: 1);
      await settle(s, covers: 2);
      final eps = s.current.value!;
      expect(('${eps.op}', '${eps.ed}'), ('Опенінґ 1 «Pray» — Tommy heavenly⁶', 'Ендінґ 1 «Fuusen Gum» — Captain Straydum'));
      expect(eps.art[SongKind.op]!.cover, startsWith('https://image-cdn-'));
      expect(eps.art[SongKind.ed]!.cover, startsWith('https://image-cdn-'));
      expect(web.asked.where((u) => u.path == '/oembed').map((u) => u.queryParameters['url']), [
        'https://open.spotify.com/track/5DBOBP2zmNUXSOzb7Syywd',
        'https://open.spotify.com/track/6kltaRFHGDDyyvS6EvqMEx',
      ]);
      expect(web.asked.where((u) => u.path == '/search'), isEmpty, reason: 'its own page is enough');
    });

    test('a title AnimeThemes does not have: MyAnimeList\'s episodes; Tenrai down too: Hikka\'s list — its only ending', () async {
      final web = FakeWeb()..animeThemesKnows = false;
      final s = make(web);
      await s.attach(animeKey: 'hikka:frieren', epKey: '20', number: 20);
      expect((s.current.value!.op!.title, s.current.value!.ed!.title), ('Haru', 'Anytime Anywhere'));

      final down = FakeWeb()
        ..animeThemesKnows = false
        ..tenraiDown = true;
      final h = make(down);
      await h.attach(animeKey: 'hikka:frieren', epKey: '20', number: 20);
      expect(h.current.value!.op, isNull, reason: 'of two openings, which plays when is not known');
      expect(h.current.value!.ed!.title, 'Anytime Anywhere');
    });

    test('AnimeThemes unreachable: MyAnimeList\'s songs for now, AnimeThemes asked again next time', () async {
      final web = FakeWeb()..themesDown = true;
      final s = make(web);
      await s.attach(animeKey: 'hikka:frieren', epKey: '5', number: 5);
      expect((s.current.value!.op!.title, s.current.value!.ed!.title), ('Yuusha', 'Anytime Anywhere'));
      expect(s.current.value!.op!.links, isEmpty, reason: 'MyAnimeList and Hikka have no links for it');
      web.themesDown = false;
      await s.attach(animeKey: 'hikka:frieren', epKey: '6', number: 6);
      expect(s.current.value!.op!.links.keys, contains(MusicApp.appleMusic), reason: 'AnimeThemes\' this time');
      expect(graphql(web).length, 2);
    });

    test('remembered on disk; offline the old answer serves; refreshed after two weeks', () async {
      var now = DateTime(2026, 11, 1);
      final web = FakeWeb();
      final a = make(web, now: () => now);
      await a.attach(animeKey: 'hikka:frieren', epKey: '5', number: 5);
      await settle(a);
      await a.save();

      final offline = FakeWeb()..down = true;
      final b = make(offline, now: () => now);
      await b.attach(animeKey: 'hikka:frieren', epKey: '5', number: 5);
      await settle(b);
      expect(b.current.value!.op!.title, 'Yuusha');
      expect(b.current.value!.art[SongKind.op]!.cover, endsWith('300x300bb.jpg'));
      expect(offline.asked, isEmpty, reason: 'all of it fresh on disk');

      now = now.add(const Duration(days: 15));
      final c = make(offline, now: () => now);
      await c.attach(animeKey: 'hikka:frieren', epKey: '5', number: 5);
      expect(c.current.value!.op!.title, 'Yuusha', reason: 'old, but nothing better offline');
      expect(graphql(offline), isNotEmpty, reason: 'it was asked again');
    });

    test('turned off in the settings: nothing is asked', () async {
      final web = FakeWeb();
      final s = SongService(get: web.get, persist: false, malId: (k) async => 52991, ost: (k) async => songsOfHikka(frierenOst), enabled: () => false);
      await s.attach(animeKey: 'hikka:frieren', epKey: '5', number: 5);
      expect(s.current.value, isNull);
      expect(web.asked, isEmpty);
    });
  });
}
