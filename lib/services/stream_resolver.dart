/// Gets a playable video for an episode: goes through the players (Moon → Ashdi …), the first working one wins,
/// quality is picked by the setting. Knows nothing about Flutter and media_kit.
library;

import '../models/source_models.dart';
import 'sources/anime_source.dart';
import 'sources/source_http.dart';
import 'sources/source_log.dart';

/// A video ready to open in the player, plus everything needed to switch quality and player
class ResolvedStream {
  final Video video;

  /// All quality variants from the chosen player ("Авто", 1080p …)
  final List<Video> qualities;

  /// The chosen player
  final String hoster;

  /// All players of the episode (for manual switching)
  final List<String> hosters;

  const ResolvedStream({required this.video, required this.qualities, required this.hoster, required this.hosters});

  List<TimeStamp> get timestamps => video.timestamps;
}

class StreamResolver {
  /// The largest frame height we pick automatically (0 is the highest)
  final int Function() maxHeight;

  /// Preferred player (empty means by the source's order)
  final String Function() preferredHoster;

  /// Agreement with Moon: where an episode has Moon, we do not offer or substitute Ashdi for it
  static List<Hoster> withoutAshdiWhereMoon(List<Hoster> all) {
    bool named(Hoster h, String n) => h.name.toLowerCase() == n;
    if (!all.any((h) => named(h, 'moon'))) return all;
    return [for (final h in all) if (!named(h, 'ashdi')) h];
  }

  const StreamResolver({this.maxHeight = _zero, this.preferredHoster = _empty});

  static int _zero() => 0;
  static String _empty() => '';

  /// [hoster] is a forcibly chosen player (manual switching), [height] is a forced quality
  Future<ResolvedStream> resolve(AnimeSource source, SEpisode episode, {String? hoster, int? height}) async {
    final all = withoutAshdiWhereMoon(await source.hosters(episode));
    if (all.isEmpty) {
      throw const SourceException(SourceErrorKind.unsupported, 'Для цієї серії немає плеєрів, які ми вміємо відкривати');
    }
    final want = (hoster != null && hoster.isNotEmpty) ? hoster : preferredHoster();
    final ordered = [
      ...all.where((h) => want.isNotEmpty && h.name.toLowerCase() == want.toLowerCase()),
      ...all.where((h) => want.isEmpty || h.name.toLowerCase() != want.toLowerCase()),
    ];
    final problems = <String>[];
    SourceException? first;
    SourceLog.add('Серія «${episode.name}»: плеєри ${[for (final h in ordered) h.name].join(', ')}');
    for (final h in ordered) {
      try {
        SourceLog.add('Плеєр ${h.name}: ${h.url}');
        final videos = h.videos ?? await source.hosterVideos(h);
        final pick = pickVideo(videos, maxHeight: height ?? maxHeight());
        SourceLog.add('Плеєр ${h.name}: знайдено ${videos.length} відео${pick == null ? ', вибрати нічого' : ', обрано ${pick.title} ${pick.url}'}');
        if (pick == null) {
          problems.add('${h.name}: порожньо');
          continue;
        }
        return ResolvedStream(video: pick, qualities: videos.where((v) => v.url.isNotEmpty).toList(), hoster: h.name, hosters: [for (final x in all) x.name]);
      } on SourceException catch (e) {
        first ??= e;
        SourceLog.add('Плеєр ${h.name}: помилка ${e.kind.name}: ${e.detail}');
        problems.add('${h.name}: ${e.message}');
      } catch (e, st) {
        SourceLog.add('Плеєр ${h.name}: збій $e\n${st.toString().split('\n').take(4).join('\n')}');
        problems.add('${h.name}: $e');
      }
    }
    // If there was only one player, we return its own error (it is more precise), otherwise the combined one
    if (ordered.length == 1 && first != null) throw first;
    throw SourceException(first?.kind ?? SourceErrorKind.badResponse, 'Не вдалося відкрити жоден плеєр: ${problems.join('; ')}');
  }
}
