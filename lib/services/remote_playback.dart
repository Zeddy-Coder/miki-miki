/// Чиста логіка відтворення серій із сайтів (без media_kit і Flutter): розділи плеєра з таймкодів сайту,
/// ознака «серію переглянуто» й запуск із боку сторінки аніме. Усе, що торкається mpv, робить `PlayerStateController`.
library;

import '../models/media_models.dart';
import '../models/source_models.dart';
import 'episode_check.dart';
import 'watch_models.dart';

/// Найкоротший проміжок між таймкодами, який вартує окремого розділу (секунди)
const double _minGap = 1.0;

Duration _sec(double s) => Duration(milliseconds: (s * 1000).round());

/// Назви розділів — англійські ключові слова, які `AppFormatters.translateChapterTitle` перекладає
/// («Opening» → «Опенінґ»): за ними кнопка «Пропустити» знає, що розділ можна пропускати.
String _title(TimeStamp t) {
  switch (t.type) {
    case ChapterType.opening:
    case ChapterType.mixedOp:
      return 'Opening';
    case ChapterType.ending:
      return 'Ending';
    case ChapterType.recap:
      return 'Recap';
    case ChapterType.other:
      final n = t.name.trim();
      return n.isEmpty ? 'Part' : n;
  }
}

/// Розділи з таймкодів сайту. Плеєр вважає розділи суцільними (кожен триває до початку наступного),
/// тому проміжки між таймкодами заповнюються розділами «Серія», які не пропонуються до пропуску.
/// Без жодного коректного таймкода розділів немає.
List<VideoChapter> chaptersFromTimestamps(List<TimeStamp> stamps, Duration total) {
  final totalSec = total.inMilliseconds / 1000.0;
  final list = [
    for (final s in stamps)
      if (s.start >= 0 && s.end > s.start && (totalSec <= 0 || s.start < totalSec)) s,
  ]..sort((a, b) => a.start.compareTo(b.start));
  if (list.isEmpty) return const [];

  final out = <VideoChapter>[];
  var cursor = 0.0;
  for (final s in list) {
    var start = s.start < cursor ? cursor : s.start; // накладені таймкоди підрізаємо
    final end = (totalSec > 0 && s.end > totalSec) ? totalSec : s.end;
    if (end - start < _minGap) continue;
    if (start - cursor >= _minGap) {
      out.add(VideoChapter(title: 'Episode', startTime: _sec(cursor), endTime: _sec(start)));
    } else {
      start = cursor; // крихітний проміжок приєднуємо до розділу
    }
    out.add(VideoChapter(title: _title(s), startTime: _sec(start), endTime: _sec(end)));
    cursor = end;
  }
  if (out.isEmpty) return const [];
  if (totalSec > 0 && totalSec - cursor >= _minGap) {
    out.add(VideoChapter(title: 'Episode', startTime: _sec(cursor), endTime: total));
  }
  return out;
}

/// Чи можна вважати серію переглянутою: дивилися понад [fraction] тривалості або дійшли до титрів
/// (ендінґ, що починається в другій половині серії).
bool episodeSeen(Duration position, Duration total, List<TimeStamp> stamps, {double fraction = 0.85}) {
  if (total <= Duration.zero) return false;
  final pos = position.inMilliseconds;
  final dur = total.inMilliseconds;
  if (pos >= dur * fraction) return true;
  for (final s in stamps) {
    if (s.type == ChapterType.ending && s.start * 1000 >= dur * 0.6 && pos >= s.start * 1000) return true;
  }
  return false;
}

/// Усе, що потрібно плеєру, щоб почати відтворення серій із сайту
class RemoteLaunch {
  /// Що знайдено для аніме (усі озвучки — для перемикання під час перегляду)
  final WatchTitle title;

  /// Обрана озвучка
  final WatchGroup group;

  /// З якої серії почати (ключ `episodeKey`); `null` — з першої
  final String? epKey;

  final String animeTitle;
  final String? poster;

  /// Що Hikka каже про кількість серій: за цим плеєр показує, де нумерація може не збігатися
  final HikkaEpisodeInfo? hikka;

  const RemoteLaunch({
    required this.title,
    required this.group,
    required this.animeTitle,
    this.epKey,
    this.poster,
    this.hikka,
  });

  RemoteSession get session => RemoteSession.fromGroup(
        animeKey: title.animeKey,
        animeTitle: animeTitle,
        group: group,
        poster: poster,
      );

  /// Індекс початкової серії в [session]
  int get startIndex {
    final i = epKey == null ? -1 : session.indexOfKey(epKey!);
    return i < 0 ? 0 : i;
  }
}

/// Міст між сторінками застосунку (Hikka, джерела) і плеєром: плеєр реєструє обробник, решта лише викликає `play`.
class WatchLauncher {
  WatchLauncher._();

  static Future<void> Function(RemoteLaunch launch)? _handler;

  static void attach(Future<void> Function(RemoteLaunch launch) handler) => _handler = handler;

  static void detach(Future<void> Function(RemoteLaunch launch) handler) {
    if (identical(_handler, handler) || _handler == handler) _handler = null;
  }

  static bool get available => _handler != null;

  /// Запускає перегляд; `false` — плеєр ще не готовий
  static Future<bool> play(RemoteLaunch launch) async {
    final h = _handler;
    if (h == null) return false;
    await h(launch);
    return true;
  }
}
