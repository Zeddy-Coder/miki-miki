/// The player's way to an episode when downloads exist: a downloaded episode plays from the device (no network, no
/// expiring links, the same position and "watched" marks), everything else goes to the site as before.
library;

import '../../models/source_models.dart';
import '../network_status.dart';
import '../sources/anime_source.dart';
import '../sources/source_http.dart';
import '../sources/source_log.dart';
import '../stream_resolver.dart';
import 'download_manager.dart';

class DownloadAwareResolver extends StreamResolver {
  /// The "player" of a downloaded episode in the player's lists
  static const String deviceHoster = 'Пристрій';

  final DownloadManager Function() _downloads;
  final NetworkStatus Function() _network;

  const DownloadAwareResolver({
    super.maxHeight,
    super.preferredHoster,
    DownloadManager Function()? downloads,
    NetworkStatus Function()? network,
  })  : _downloads = downloads ?? _manager,
        _network = network ?? _status;

  static DownloadManager _manager() => DownloadManager.instance;
  static NetworkStatus _status() => NetworkStatus.instance;

  /// The downloaded copy wins unless another player was chosen by hand (and the network is there for it)
  @override
  Future<ResolvedStream> resolve(AnimeSource source, SEpisode episode, {String? hoster, int? height}) async {
    final dm = _downloads();
    final net = _network();
    // Without internet the copy wins even over a player chosen by hand
    final offline = !net.online;
    final item = dm.playable(source.id, episode);
    final wantsLocal = hoster == null || hoster.isEmpty || hoster == deviceHoster || offline;
    if (item != null && wantsLocal) {
      final v = dm.localVideo(item);
      if (v != null) {
        dm.markPlaying(item.id);
        SourceLog.add('Серія «${episode.name}»: з пристрою (${item.quality.isEmpty ? 'завантажено' : item.quality})');
        return ResolvedStream(
          video: v,
          qualities: [v],
          hoster: deviceHoster,
          hosters: [deviceHoster, if (item.hoster.isNotEmpty) item.hoster],
        );
      }
    }
    dm.markPlaying(null);
    // The system says there is no internet (Android): a clear word at once instead of the site's timeout. A PC only
    // guesses, so there the site is tried anyway
    if (offline && net.certain) {
      throw SourceException(
        SourceErrorKind.network,
        'offline, not downloaded: ${episode.url}',
        note: dm.done.isNotEmpty
            ? 'Немає інтернету, а цю серію не завантажено. Завантажені серії позначено в списку серій.'
            : 'Немає інтернету. Серії можна завантажити заздалегідь: «Перегляд» → «Завантажити серії».',
      );
    }
    return super.resolve(source, episode, hoster: hoster == deviceHoster ? null : hoster, height: height);
  }
}
