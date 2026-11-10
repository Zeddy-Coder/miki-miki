/// Дістає відтворюване відео для серії: перебирає плеєри (Moon → Ashdi …), перший робочий виграє,
/// якість добирається за налаштуванням. Нічого не знає про Flutter і media_kit.
library;

import '../models/source_models.dart';
import 'sources/anime_source.dart';
import 'sources/source_http.dart';
import 'sources/source_log.dart';

/// Відео, готове до відкриття в плеєрі, + усе, що потрібно для перемикання якості й плеєра
class ResolvedStream {
  final Video video;

  /// Усі варіанти якості з обраного плеєра («Авто», 1080p …)
  final List<Video> qualities;

  /// Обраний плеєр
  final String hoster;

  /// Усі плеєри серії (для ручного перемикання)
  final List<String> hosters;

  const ResolvedStream({required this.video, required this.qualities, required this.hoster, required this.hosters});

  List<TimeStamp> get timestamps => video.timestamps;
}

class StreamResolver {
  /// Найбільша висота кадру, яку вибираємо автоматично (0 — найвища)
  final int Function() maxHeight;

  /// Бажаний плеєр (порожньо — за порядком джерела)
  final String Function() preferredHoster;

  /// Умова домовленості з Moon: де в серії є Moon, Ashdi не пропонуємо й не підставляємо замість нього
  static List<Hoster> withoutAshdiWhereMoon(List<Hoster> all) {
    bool named(Hoster h, String n) => h.name.toLowerCase() == n;
    if (!all.any((h) => named(h, 'moon'))) return all;
    return [for (final h in all) if (!named(h, 'ashdi')) h];
  }

  const StreamResolver({this.maxHeight = _zero, this.preferredHoster = _empty});

  static int _zero() => 0;
  static String _empty() => '';

  /// [hoster] — примусово обраний плеєр (ручне перемикання), [height] — примусова якість
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
    // Якщо плеєр був один — віддаємо його власну помилку (вона точніша), інакше зведену
    if (ordered.length == 1 && first != null) throw first;
    throw SourceException(first?.kind ?? SourceErrorKind.badResponse, 'Не вдалося відкрити жоден плеєр: ${problems.join('; ')}');
  }
}
