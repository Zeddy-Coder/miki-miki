// Episode downloads: HLS playlists, the worker (an in-memory server with ranges, expiring links, failures), the manager
// (queue, network rules, saving, smart downloads, offline playback) and the player's resolver. No real network.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:miki_miki/models/source_models.dart';
import 'package:miki_miki/services/downloads/download_manager.dart';
import 'package:miki_miki/services/downloads/download_models.dart';
import 'package:miki_miki/services/downloads/download_resolver.dart';
import 'package:miki_miki/services/downloads/download_worker.dart';
import 'package:miki_miki/services/downloads/hls_media.dart';
import 'package:miki_miki/services/network_status.dart';
import 'package:miki_miki/services/source_prefs.dart';
import 'package:miki_miki/services/source_registry.dart';
import 'package:miki_miki/services/sources/source_http.dart';
import 'package:miki_miki/services/watch_models.dart';

import 'support/remote_fakes.dart';

/// A tiny CDN in memory: files by path, ranges, links that expire by token, a switch to "lose" the network
class FakeCdn {
  final Map<String, List<int>> files = {};
  final Set<String> expired = {};
  final List<String> log = [];
  bool offline = false;

  /// Ignores Range (answers 200 with the whole file), as some servers do
  bool noRanges = false;

  /// Expires token [token] after this many successful answers (null: never)
  int? expireAfter;
  String? expiring;
  int _served = 0;

  Future<FetchResponse> fetch(Uri url, Map<String, String> headers, {int? offset, int? length}) async {
    log.add('${url.path}${offset == null ? '' : '@$offset'}');
    if (offline) throw const SocketException('offline');
    final token = url.queryParameters['t'];
    if (token != null && expired.contains(token)) return FetchResponse(403, 0, const Stream.empty(), () {});
    final data = files[url.path];
    if (data == null) return FetchResponse(404, 0, const Stream.empty(), () {});
    if (token != null && token == expiring && expireAfter != null && ++_served >= expireAfter!) expired.add(token);
    if (offset != null && !noRanges) {
      final end = length == null ? data.length : (offset + length).clamp(0, data.length);
      final part = data.sublist(offset.clamp(0, data.length), end);
      return FetchResponse(206, part.length, Stream.value(part), () {});
    }
    return FetchResponse(200, data.length, Stream.value(data), () {});
  }
}

List<int> bytes(String s) => utf8.encode(s);

DownloadItem itemFor(String id, {int height = 0, String folder = ''}) => DownloadItem(
      id: id,
      animeKey: 'hikka:frieren',
      animeTitle: 'Фрірен',
      groupId: 'g1',
      groupLabel: 'Inari',
      sourceId: 'mikai',
      episode: SEpisode(url: 'ep-$id', name: 'Серія 1', number: 1),
      epKey: '1',
      title: 'Серія 1',
      order: 0,
      count: 12,
      height: height,
      addedAt: DateTime(2026, 11, 1),
      folder: folder,
    );

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('miki_dl_');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  group('плейлисти HLS', () {
    test('медіаплейлист: тривалості, ключі, init-секція, діапазони байтів без явного зсуву', () {
      const text = '#EXTM3U\n#EXT-X-TARGETDURATION:6\n#EXT-X-MEDIA-SEQUENCE:10\n'
          '#EXT-X-MAP:URI="init.mp4",BYTERANGE="700@0"\n'
          '#EXT-X-KEY:METHOD=AES-128,URI="https://k.test/key?id=1"\n'
          '#EXTINF:5.5,\n#EXT-X-BYTERANGE:1000@700\nmain.mp4\n'
          '#EXTINF:6.0,\n#EXT-X-BYTERANGE:900\nmain.mp4\n'
          '#EXT-X-DISCONTINUITY\n#EXT-X-KEY:METHOD=NONE\n#EXTINF:4,\nhttps://cdn.test/b/last.ts\n#EXT-X-ENDLIST\n';
      final m = parseHlsMedia(text, Uri.parse('https://cdn.test/a/media.m3u8'))!;
      expect(m.ended, isTrue);
      expect(m.segments, hasLength(3));
      expect(m.duration, closeTo(15.5, 1e-9));
      expect(m.segments[0].uri.toString(), 'https://cdn.test/a/main.mp4');
      expect((m.segments[0].offset, m.segments[0].length), (700, 1000));
      // The second range goes on right after the first one of the same file
      expect((m.segments[1].offset, m.segments[1].length), (1700, 900));
      expect(m.segments[0].sequence, 10);
      expect(m.segments[2].key, isNull);
      expect(m.segments[2].discontinuity, isTrue);
      expect(m.keys.single.uri.toString(), 'https://k.test/key?id=1');
      expect(m.maps.single.length, 700);
      expect(m.unsupportedEncryption, isNull);
    });

    test('майстер-плейлист і не-HLS не є медіаплейлистом; SAMPLE-AES не підтримується', () {
      expect(parseHlsMedia('#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1\nv.m3u8\n', Uri.parse('https://x.test/')), isNull);
      expect(parseHlsMedia('<html>', Uri.parse('https://x.test/')), isNull);
      final m = parseHlsMedia('#EXTM3U\n#EXT-X-KEY:METHOD=SAMPLE-AES,URI="skd://x"\n#EXTINF:4,\na.ts\n#EXT-X-ENDLIST\n', Uri.parse('https://x.test/'))!;
      expect(m.unsupportedEncryption, 'SAMPLE-AES');
    });

    test('локальний плейлист: нумерація з 0, неявний IV виписано явно, ключі й init — локальні файли', () {
      const text = '#EXTM3U\n#EXT-X-TARGETDURATION:4\n#EXT-X-MEDIA-SEQUENCE:7\n#EXT-X-MAP:URI="init.mp4"\n'
          '#EXT-X-KEY:METHOD=AES-128,URI="k.bin"\n#EXTINF:4,\na.m4s\n#EXTINF:4.2,\nb.m4s\n#EXT-X-ENDLIST\n';
      final m = parseHlsMedia(text, Uri.parse('https://cdn.test/v/media.m3u8'))!;
      final local = buildLocalPlaylist(m, segmentFile: (i) => 'seg_$i.m4s');
      expect(local, contains('#EXT-X-MEDIA-SEQUENCE:0'));
      expect(local, contains('#EXT-X-TARGETDURATION:5'));
      expect(local, contains('#EXT-X-MAP:URI="init_0.mp4"'));
      expect(local, contains('#EXT-X-KEY:METHOD=AES-128,URI="key_0.bin",IV=0x00000000000000000000000000000007'));
      expect(local, contains('IV=0x00000000000000000000000000000008'));
      expect(local, contains('seg_1.m4s'));
      expect(local.trim().endsWith('#EXT-X-ENDLIST'), isTrue);
      expect(segmentExtension(Uri.parse('https://x.test/a.jpg?x=1')), 'ts');
      expect(segmentExtension(Uri.parse('https://x.test/a.m4s')), 'm4s');
    });
  });

  group('завантаження однієї серії', () {
    late FakeCdn cdn;

    setUp(() {
      cdn = FakeCdn()
        ..files['/v/master.m3u8'] = bytes('#EXTM3U\n'
            '#EXT-X-STREAM-INF:BANDWIDTH=4000000,RESOLUTION=1920x1080\nhi.m3u8\n'
            '#EXT-X-STREAM-INF:BANDWIDTH=1000000,RESOLUTION=854x480\nlo.m3u8\n')
        ..files['/v/hi.m3u8'] = bytes('#EXTM3U\n#EXT-X-TARGETDURATION:4\n#EXTINF:4,\nhi0.ts\n#EXTINF:4,\nhi1.ts\n#EXT-X-ENDLIST\n')
        ..files['/v/lo.m3u8'] = bytes('#EXTM3U\n#EXT-X-TARGETDURATION:4\n#EXT-X-KEY:METHOD=AES-128,URI="key.bin",IV=0x01\n'
            '#EXTINF:4,\nlo0.ts?t=a\n#EXTINF:4,\nlo1.ts?t=a\n#EXTINF:4,\nlo2.ts?t=a\n#EXT-X-ENDLIST\n')
        ..files['/v/key.bin'] = List.filled(16, 7)
        ..files['/v/lo0.ts'] = List.filled(100, 0)
        ..files['/v/lo1.ts'] = List.filled(100, 1)
        ..files['/v/lo2.ts'] = List.filled(100, 2)
        ..files['/v/hi0.ts'] = List.filled(300, 9)
        ..files['/v/hi1.ts'] = List.filled(300, 9)
        ..files['/s/uk.vtt'] = bytes('WEBVTT\n\n00:00.000 --> 00:01.000\nПривіт\n')
        ..files['/f/video.mp4'] = List.generate(1000, (i) => i % 251);
    });

    DownloadWorker worker(Directory dir, {String url = 'https://cdn.test/v/master.m3u8', int height = 720, List<Track> subs = const [], DownloadCancel? cancel, int Function()? onResolve}) =>
        DownloadWorker(
          item: itemFor('1', height: height),
          dir: dir,
          fetch: cdn.fetch,
          resolve: (_) async {
            onResolve?.call();
            return ResolvedVideo(Video(url: url, title: 'Авто', subtitleTracks: subs), 'Moon');
          },
          onProgress: (_) {},
          cancel: cancel,
          retryDelay: const Duration(milliseconds: 1),
        );

    test('HLS: якість за висотою, ключ, сегменти, субтитри, локальний плейлист і опис серії', () async {
      final dir = Directory('${tmp.path}/ep');
      final done = await worker(dir, subs: const [Track('https://cdn.test/s/uk.vtt', 'Українська')]).run();
      expect(done.state, DownloadState.done);
      expect(done.quality, '480p');
      expect(done.hoster, 'Moon');
      expect(done.file, 'index.m3u8');
      expect(done.parts, 3);
      expect(done.partsDone, 3);
      expect(done.duration, 12);
      expect(done.subtitles.single.file, 'sub_0.vtt');
      expect(done.subtitles.single.lang, 'Українська');
      expect(cdn.log.where((l) => l.contains('hi')), isEmpty, reason: 'the other quality is not touched');
      expect(await File('${dir.path}/key_0.bin').readAsBytes(), List.filled(16, 7));
      expect(await File('${dir.path}/seg_00002.ts').readAsBytes(), List.filled(100, 2));
      final local = await File('${dir.path}/index.m3u8').readAsString();
      expect(local, contains('URI="key_0.bin",IV=0x01'));
      expect(local, contains('seg_00000.ts'));
      final saved = DownloadItem.fromJson(jsonDecode(await File('${dir.path}/episode.json').readAsString()))!;
      expect(saved.isDone, isTrue);
      expect(saved.bytes, done.bytes);
    });

    test('докачує: сегменти, що вже на диску, не завантажуються вдруге', () async {
      final dir = Directory('${tmp.path}/ep')..createSync(recursive: true);
      File('${dir.path}/seg_00000.ts').writeAsBytesSync(List.filled(100, 0));
      File('${dir.path}/seg_00001.ts').writeAsBytesSync(List.filled(100, 1));
      await worker(dir).run();
      expect(cdn.log.where((l) => l.startsWith('/v/lo0') || l.startsWith('/v/lo1')), isEmpty);
      expect(cdn.log.where((l) => l.startsWith('/v/lo2')), hasLength(1));
    });

    test('посилання протухло посеред завантаження: нове від сайту, готові сегменти лишаються', () async {
      cdn
        ..expiring = 'a'
        ..expireAfter = 1;
      var resolves = 0;
      // The second link has another token: the source gives a fresh playlist
      final dir = Directory('${tmp.path}/ep');
      final w = DownloadWorker(
        item: itemFor('1', height: 480),
        dir: dir,
        fetch: cdn.fetch,
        resolve: (_) async {
          resolves++;
          if (resolves > 1) {
            cdn.files['/v/lo.m3u8'] = bytes(utf8.decode(cdn.files['/v/lo.m3u8']!).replaceAll('?t=a', '?t=b'));
          }
          return const ResolvedVideo(Video(url: 'https://cdn.test/v/master.m3u8', title: 'Авто'), 'Moon');
        },
        onProgress: (_) {},
        parallel: 1,
        retryDelay: const Duration(milliseconds: 1),
      );
      final done = await w.run();
      expect(resolves, 2);
      expect(done.partsDone, 3);
      expect(cdn.log.where((l) => l.startsWith('/v/lo0')), hasLength(1), reason: 'the first segment was already on disk');
    });

    test('звичайний файл: докачка з .part діапазоном; сервер без діапазонів — заново', () async {
      final dir = Directory('${tmp.path}/ep')..createSync(recursive: true);
      final full = cdn.files['/f/video.mp4']!;
      File('${dir.path}/video.mp4.part').writeAsBytesSync(full.sublist(0, 400));
      final done = await worker(dir, url: 'https://cdn.test/f/video.mp4').run();
      expect(done.file, 'video.mp4');
      expect(cdn.log, contains('/f/video.mp4@400'));
      expect(await File('${dir.path}/video.mp4').readAsBytes(), full);

      final dir2 = Directory('${tmp.path}/ep2')..createSync(recursive: true);
      File('${dir2.path}/video.mp4.part').writeAsBytesSync(full.sublist(0, 400));
      cdn.noRanges = true;
      await worker(dir2, url: 'https://cdn.test/f/video.mp4').run();
      expect(await File('${dir2.path}/video.mp4').readAsBytes(), full);
    });

    test('без мережі — збій «мережа» (менеджер почекає й повторить); пряма трансляція — зрозуміла відмова', () async {
      cdn.offline = true;
      await expectLater(worker(Directory('${tmp.path}/a')).run(), throwsA(isA<DownloadFailure>().having((e) => e.network, 'network', isTrue)));
      cdn
        ..offline = false
        ..files['/v/live.m3u8'] = bytes('#EXTM3U\n#EXT-X-TARGETDURATION:4\n#EXTINF:4,\nx.ts\n');
      await expectLater(
        worker(Directory('${tmp.path}/b'), url: 'https://cdn.test/v/live.m3u8').run(),
        throwsA(isA<DownloadFailure>().having((e) => e.message, 'message', contains('пряма трансляція'))),
      );
    });

    test('скасування зупиняє завантаження', () async {
      final cancel = DownloadCancel()..cancel();
      await expectLater(worker(Directory('${tmp.path}/c'), cancel: cancel).run(), throwsA(isA<DownloadCancelled>()));
    });
  });

  group('менеджер завантажень', () {
    late FakeCdn cdn;
    late NetworkStatus net;
    late FakeSource source;
    late SourceRegistry registry;
    final managers = <DownloadManager>[];

    WatchGroup group({int count = 4}) => WatchGroup(
          id: 'mikai|1|inari',
          sourceId: 'mikai',
          label: 'Inari',
          episodes: [for (var i = 1; i <= count; i++) SEpisode(url: 'ep$i', name: 'Серія $i', number: i.toDouble())],
        );

    DownloadManager make({Future<(int, int)?> Function(String)? storage, Duration retryBase = const Duration(milliseconds: 20)}) {
      final m = DownloadManager(
        indexPath: '${tmp.path}/downloads.json',
        root: '${tmp.path}/root',
        fetch: cdn.fetch,
        resolve: (item) async => ResolvedVideo(Video(url: 'https://cdn.test/${item.episode.url}.mp4', title: '720p', resolution: 720), 'Moon'),
        network: net,
        registry: registry,
        loadPrefs: () => {},
        savePrefs: (_) {},
        watchHeight: () => 720,
        watchHoster: () => '',
        storage: storage ?? (_) async => null,
        retryBase: retryBase,
        partRetryDelay: const Duration(milliseconds: 1),
        trashDelay: const Duration(milliseconds: 30),
      );
      managers.add(m);
      return m;
    }

    Future<void> settle(DownloadManager m) async {
      for (var i = 0; i < 400 && (m.busy || m.pending.any((x) => x.state == DownloadState.running)); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      await m.save();
    }

    setUp(() {
      cdn = FakeCdn();
      for (var i = 1; i <= 6; i++) {
        cdn.files['/ep$i.mp4'] = List.filled(500 + i, i);
      }
      net = NetworkStatus(probe: () async => true);
      source = FakeSource('mikai', const {});
      registry = SourceRegistry(sources: [source], prefs: SourcePrefs(load: () => {}, save: (_) {}));
    });

    tearDown(() {
      for (final m in managers) {
        m.dispose();
      }
      managers.clear();
      net.dispose();
    });

    test('завантажує по черзі в теку «назва / озвучка / серія», зберігає список і читає його знову', () async {
      final m = make();
      await m.init();
      final n = await m.enqueue(animeKey: 'hikka:frieren', animeTitle: 'Фрірен: Похоронна процесія', group: group(), indexes: [0, 1]);
      expect(n, 2);
      await settle(m);
      expect(m.done, hasLength(2));
      final first = m.done.first;
      expect(first.folder, '${tmp.path}/root/Фрірен_ Похоронна процесія/Озвучення Inari/Серія 1');
      expect(File('${first.folder}/video.mp4').readAsBytesSync(), List.filled(501, 1));
      expect(m.byEpKey('hikka:frieren', 'mikai|1|inari').keys, ['1', '2']);
      // The same episodes again: nothing new
      expect(await m.enqueue(animeKey: 'hikka:frieren', animeTitle: 'Фрірен', group: group(), indexes: [0, 1]), 0);

      final again = make();
      await again.init();
      expect(again.done.map((i) => i.epKey), ['1', '2']);
      expect(again.group('hikka:frieren', 'mikai|1|inari')!.episodes, hasLength(4));
    });

    test('серію, файли якої видалили поза застосунком, забуто при запуску', () async {
      final m = make();
      await m.init();
      await m.enqueue(animeKey: 'hikka:frieren', animeTitle: 'Фрірен', group: group(), indexes: [0, 1]);
      await settle(m);
      await Directory(m.done.first.folder).delete(recursive: true);
      final again = make();
      await again.init();
      expect(again.done.map((i) => i.epKey), ['2']);
    });

    test('«Лише через Wi-Fi»: на мобільному інтернеті чекає, на Wi-Fi продовжує', () async {
      net.apply(online: true, metered: true, type: 'cellular', certain: true);
      final m = make();
      await m.init();
      await m.enqueue(animeKey: 'hikka:frieren', animeTitle: 'Фрірен', group: group(), indexes: [0]);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(m.done, isEmpty);
      expect(m.waitReason, contains('Wi-Fi'));
      expect(cdn.log, isEmpty);
      net.apply(online: true, metered: false, type: 'wifi', certain: true);
      await settle(m);
      expect(m.done, hasLength(1));
    });

    test('без інтернету чекає; збій мережі — повтор, а повернення мережі запускає одразу', () async {
      net.apply(online: false, certain: true);
      final m = make(retryBase: const Duration(minutes: 5));
      await m.init();
      await m.enqueue(animeKey: 'hikka:frieren', animeTitle: 'Фрірен', group: group(), indexes: [0]);
      expect(m.waitReason, startsWith('Немає інтернету'));
      cdn.offline = true;
      net.apply(online: true, certain: true);
      for (var i = 0; i < 200 && m.items.single.error == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(m.items.single.state, DownloadState.queued);
      expect(m.waitReason, startsWith('Звʼязок перервався'));
      // The network "came back": no waiting out five minutes
      cdn.offline = false;
      net.apply(online: false, certain: true);
      net.apply(online: true, certain: true);
      await settle(m);
      expect(m.done, hasLength(1));
    });

    test('пауза, продовження, видалення файлів разом із теками', () async {
      final m = make();
      await m.init();
      await m.enqueue(animeKey: 'hikka:frieren', animeTitle: 'Фрірен', group: group(), indexes: [0, 1]);
      final second = m.items[1];
      m.pause(second.id);
      await settle(m);
      expect(m.item(second.id)!.state, DownloadState.paused);
      m.resume(second.id);
      await settle(m);
      expect(m.done, hasLength(2));
      final folder = m.done.first.folder;
      await m.remove(m.done.first.id);
      expect(Directory(folder).existsSync(), isFalse);
      await m.removeGroup('hikka:frieren', 'mikai|1|inari');
      expect(m.items, isEmpty);
      expect(m.group('hikka:frieren', 'mikai|1|inari'), isNull);
      expect(Directory('${tmp.path}/root/Фрірен').existsSync(), isFalse, reason: 'empty title folders go too');
    });

    test('замало місця: не починає й каже чому; «Продовжити» пробує знову', () async {
      var free = 10;
      final m = make(storage: (_) async => (free, 1 << 40));
      await m.init();
      await m.enqueue(animeKey: 'hikka:frieren', animeTitle: 'Фрірен', group: group(), indexes: [0]);
      await settle(m);
      expect(m.items.single.state, DownloadState.failed);
      expect(m.items.single.error, 'Замало місця на пристрої');
      free = 1 << 40;
      m.resumeAll();
      await settle(m);
      expect(m.done, hasLength(1));
    });

    test('розумні завантаження: після перегляду — наступна серія; переглянута видаляється, коли ввімкнено іншу', () async {
      final m = make();
      await m.init();
      m.prefs = m.prefs.copyWith(deleteWatched: true);
      await m.enqueue(animeKey: 'hikka:frieren', animeTitle: 'Фрірен', group: group(), indexes: [0, 1]);
      await settle(m);
      m.onWatched('hikka:frieren', '1');
      await Future<void>.delayed(Duration.zero);
      await settle(m);
      expect(m.done.map((i) => i.epKey), containsAll(['1', '2', '3']));
      m.markPlaying(m.done.firstWhere((i) => i.epKey == '2').id);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(m.done.map((i) => i.epKey), ['2', '3']);
    });

    test('перегляд без мережі: черга озвучки з копії, старт — із завантаженої серії', () async {
      final m = make();
      await m.init();
      await m.enqueue(animeKey: 'hikka:frieren', animeTitle: 'Фрірен', poster: 'p.jpg', group: group(), indexes: [2, 3]);
      await settle(m);
      final launch = m.launch('hikka:frieren', 'mikai|1|inari', epKey: '3')!;
      expect(launch.group.episodes, hasLength(4));
      expect(launch.session.entries[launch.startIndex].epKey, '3');
      expect(launch.title.offers.single.source.id, 'mikai');
      final keys = m.group('hikka:frieren', 'mikai|1|inari')!.keys;
      expect(m.offlineStart('hikka:frieren', 'mikai|1|inari', keys, 0, {}), '3');
      expect(m.offlineStart('hikka:frieren', 'mikai|1|inari', keys, 3, {}), '4');
      expect(m.offlineStart('hikka:frieren', 'mikai|1|inari', keys, 0, {'3'}), '3', reason: 'the nearest downloaded after the continue point');
    });

    test('плеєр бере завантажену серію з пристрою, а без мережі не чекає сайту', () async {
      final m = make();
      await m.init();
      await m.enqueue(animeKey: 'hikka:frieren', animeTitle: 'Фрірен', group: group(), indexes: [0]);
      await settle(m);
      final resolver = DownloadAwareResolver(downloads: () => m, network: () => net);
      final local = await resolver.resolve(source, group().episodes[0]);
      expect(local.hoster, DownloadAwareResolver.deviceHoster);
      expect(local.video.url, '${m.done.single.folder}/video.mp4');
      expect(local.hosters, [DownloadAwareResolver.deviceHoster, 'Moon']);
      // Another player chosen by hand while online: the site
      await expectLater(resolver.resolve(source, group().episodes[0], hoster: 'Moon'), throwsA(isA<SourceException>()));
      expect(source.hosterCalls, 1);
      net.apply(online: false, certain: true);
      // Offline the copy wins even over the chosen player; a missing episode says so at once
      expect((await resolver.resolve(source, group().episodes[0], hoster: 'Moon')).hoster, DownloadAwareResolver.deviceHoster);
      await expectLater(
        resolver.resolve(source, group().episodes[1]),
        throwsA(isA<SourceException>().having((e) => e.message, 'message', contains('не завантажено'))),
      );
      expect(source.hosterCalls, 1);
    });
  });

  group('стан мережі', () {
    test('система каже точно; успішний запит повертає «онлайн»; Wi-Fi only зважає на тарифікацію', () {
      final n = NetworkStatus(probe: () async => false);
      expect(n.online, isTrue);
      expect(n.certain, isFalse);
      n.apply(online: true, metered: true, type: 'cellular', certain: true);
      expect(n.certain, isTrue);
      expect(n.allows(wifiOnly: true), isFalse);
      expect(n.allows(wifiOnly: false), isTrue);
      n.apply(online: false);
      expect(n.allows(wifiOnly: false), isFalse);
      n.reportSuccess();
      expect(n.online, isTrue);
      n.dispose();
    });
  });
}
