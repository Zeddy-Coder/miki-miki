// Спільні імітації для тестів серій із сайтів: плеєр, джерело, сховище й «стенд» із драйвером.
import 'dart:async';
import 'dart:convert';

import 'package:miki_miki/models/source_models.dart';
import 'package:miki_miki/services/remote_driver.dart';
import 'package:miki_miki/services/remote_playback.dart';
import 'package:miki_miki/services/source_prefs.dart';
import 'package:miki_miki/services/source_registry.dart';
import 'package:miki_miki/services/sources/anime_source.dart';
import 'package:miki_miki/services/sources/source_http.dart';
import 'package:miki_miki/services/stream_resolver.dart';
import 'package:miki_miki/services/watch_models.dart';
import 'package:miki_miki/services/watch_store.dart';

/// Плеєр-імітація: записує, що йому відкривали й додавали
class FakeEngine implements RemoteEngine {
  final List<({Video video, Duration? start})> opens = [];
  final List<({Track track, bool select})> subs = [];
  final List<({Track track, bool select})> audios = [];
  Object? failOpen;

  @override
  Duration position = Duration.zero;
  @override
  Duration duration = Duration.zero;
  @override
  bool playing = true;

  @override
  Future<void> openVideo(Video video, {Duration? start}) async {
    if (failOpen != null) throw failOpen!;
    opens.add((video: video, start: start));
  }

  @override
  Future<void> addSubtitle(Track track, {required bool select}) async => subs.add((track: track, select: select));

  @override
  Future<void> addAudio(Track track, {required bool select}) async => audios.add((track: track, select: select));

  String get lastUrl => opens.last.video.url;
}

/// Джерело-імітація: плеєри серії задаються в `hosters` за адресою серії
class FakeSource extends AnimeSource {
  FakeSource(this.sid, this.byEpisode);

  final String sid;
  final Map<String, List<Hoster>> byEpisode;
  int hosterCalls = 0;
  Completer<void>? gate; // затримує відповідь, поки тест не дозволить

  @override
  String get id => sid;
  @override
  String get name => sid;
  @override
  String get lang => 'uk';
  @override
  String get baseUrl => 'https://$sid.test';
  @override
  Future<SAnimePage> popular(int page) async => SAnimePage.empty;
  @override
  Future<SAnimePage> latest(int page) async => SAnimePage.empty;
  @override
  Future<SAnimePage> search(int page, String query) async => SAnimePage.empty;
  @override
  Future<SAnime> details(SAnime anime) async => anime;
  @override
  Future<List<SEpisode>> episodes(SAnime anime) async => const [];
  @override
  Future<List<Video>> videos(SEpisode episode) async => const [];
  @override
  String animeWebUrl(SAnime anime) => 'https://$sid.test/${anime.url}';

  @override
  Future<List<Hoster>> hosters(SEpisode episode) async {
    hosterCalls++;
    if (gate != null) await gate!.future;
    final h = byEpisode[episode.url];
    if (h == null) throw const SourceException(SourceErrorKind.notFound, 'нема серії');
    return h;
  }
}

Video vid(
  String url, {
  String title = '1080p',
  int? height = 1080,
  List<TimeStamp> stamps = const [],
  List<Track> subs = const [],
  List<Track> audios = const [],
}) => Video(url: url, title: title, resolution: height, timestamps: stamps, subtitleTracks: subs, audioTracks: audios);

SEpisode ep(int n, {String? voice}) => SEpisode(url: 'e$n', name: 'Серія $n', number: n.toDouble(), voice: voice);

WatchStore memoryStore() {
  var data = <String, dynamic>{};
  return WatchStore(load: () => data, save: (d) => data = jsonDecode(jsonEncode(d)) as Map<String, dynamic>);
}

class Rig {
  Rig({
    List<int> episodes = const [1, 2, 3],
    Map<String, List<Hoster>>? hosters,
    bool autoNext = true,
    Duration openTimeout = const Duration(milliseconds: 100),
    Duration errorGrace = const Duration(milliseconds: 30),
    Map<String, int>? positions,
    this.subLangs = const ['uk', 'ja', 'en'],
  }) : positions = positions ?? {},
       saved = [] {
    source = FakeSource(
      'src',
      hosters ??
          {
            for (final n in episodes)
              'e$n': [
                Hoster(
                  name: 'Moon',
                  videos: [
                    vid('https://moon/e$n/auto.m3u8', title: 'Авто', height: null),
                    vid('https://moon/e$n/1080.m3u8'),
                    vid('https://moon/e$n/720.m3u8', title: '720p', height: 720),
                  ],
                ),
                Hoster(name: 'Sibnet', videos: [vid('https://sibnet/e$n.m3u8')]),
              ],
          },
    );
    registry = SourceRegistry(
      sources: [source],
      prefs: SourcePrefs(load: () => {}, save: (_) {}),
      http: SourceHttp(sender: (r) async => throw StateError('мережі нема')),
    );
    store = memoryStore();
    group = WatchGroup(id: 'g1', sourceId: 'src', label: 'Команда А', episodes: [for (final n in episodes) ep(n)]);
    title = WatchTitle(
      animeKey: 'hikka:test',
      offers: [
        WatchOffer(source: source, anime: const SAnime(url: 'a', title: 'A'), groups: [group]),
      ],
    );
    driver = RemoteDriver(
      engine: engine,
      registry: registry,
      resolver: const StreamResolver(),
      store: store,
      autoNext: () => autoNextOn,
      readPosition: (k) => this.positions[k] ?? 0,
      writePosition: (k, p, d) {
        saved.add((key: k, pos: p, dur: d));
        this.positions[k] = p;
      },
      openTimeout: openTimeout,
      errorGrace: errorGrace,
      subPriorities: () => subLangs,
    );
    autoNextOn = autoNext;
    driver.onEntry = entries.add;
    driver.onSession = () => sessions++;
    driver.onMessage = (text, {bool error = false}) => messages.add(error ? '!$text' : text);
  }

  final engine = FakeEngine();
  late final FakeSource source;
  late final SourceRegistry registry;
  late final WatchStore store;
  late final WatchGroup group;
  late final WatchTitle title;
  late final RemoteDriver driver;
  final Map<String, int> positions;

  /// Пріоритет мов субтитрів («налаштування»): з кількох зовнішніх доріжок вмикається найвища за ним
  List<String> subLangs;
  final List<({String key, int pos, int dur})> saved;
  final List<int> entries = [];
  final List<String> messages = [];
  int sessions = 0;
  bool autoNextOn = true;

  RemoteLaunch launch({String? epKey, WatchGroup? g}) => RemoteLaunch(title: title, group: g ?? group, animeTitle: 'Аніме', epKey: epKey);

  /// Імітує, що плеєр дізнався тривалість (відео почалося)
  void started({Duration dur = const Duration(minutes: 24)}) {
    engine.duration = dur;
    driver.onDuration(dur);
  }

  Future<void> wait([int ms = 220]) => Future<void>.delayed(Duration(milliseconds: ms));
}
