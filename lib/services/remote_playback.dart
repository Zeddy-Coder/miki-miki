/// Pure logic of playing site episodes (without media_kit and Flutter): player chapters from the site's timestamps,
/// the "episode watched" criterion and launching from the anime page. Everything that touches mpv is done by `PlayerStateController`.
library;

import '../models/media_models.dart';
import '../models/source_models.dart';
import 'episode_check.dart';
import 'watch_models.dart';

/// The shortest gap between timestamps worth a separate chapter (seconds)
const double _minGap = 1.0;

Duration _sec(double s) => Duration(milliseconds: (s * 1000).round());

/// Chapter names are English keywords that `AppFormatters.translateChapterTitle` translates
/// ("Opening" → "Опенінґ"): the "Skip" button uses them to know that a chapter can be skipped.
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

/// Chapters from the site's timestamps. The player treats chapters as continuous (each lasts until the next starts),
/// so gaps between timestamps are filled with "Серія" chapters that are not offered for skipping.
/// Without a single valid timestamp there are no chapters.
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
    var start = s.start < cursor ? cursor : s.start; // overlapping timestamps are trimmed
    final end = (totalSec > 0 && s.end > totalSec) ? totalSec : s.end;
    if (end - start < _minGap) continue;
    if (start - cursor >= _minGap) {
      out.add(VideoChapter(title: 'Episode', startTime: _sec(cursor), endTime: _sec(start)));
    } else {
      start = cursor; // a tiny gap is attached to the chapter
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

/// Whether the episode can be considered watched: more than [fraction] of the duration was watched or (if [byEnding]) the credits were reached
/// (an ending that starts in the second half of the episode).
bool episodeSeen(Duration position, Duration total, List<TimeStamp> stamps, {double fraction = 0.85, bool byEnding = true}) {
  if (total <= Duration.zero) return false;
  final pos = position.inMilliseconds;
  final dur = total.inMilliseconds;
  if (pos >= dur * fraction) return true;
  if (!byEnding) return false;
  for (final s in stamps) {
    if (s.type == ChapterType.ending && s.start * 1000 >= dur * 0.6 && pos >= s.start * 1000) return true;
  }
  return false;
}

/// Everything the player needs to start playing site episodes
class RemoteLaunch {
  /// What was found for the anime (all dubs, for switching while watching)
  final WatchTitle title;

  /// The chosen dub
  final WatchGroup group;

  /// Which episode to start from (the `episodeKey`); `null` means the first
  final String? epKey;

  final String animeTitle;
  final String? poster;

  /// What Hikka says about the episode count: the player uses it to show where numbering may not match
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

  /// Index of the starting episode in [session]
  int get startIndex {
    final i = epKey == null ? -1 : session.indexOfKey(epKey!);
    return i < 0 ? 0 : i;
  }
}

/// A bridge between the app's pages (Hikka, sources) and the player: the player registers a handler, the rest only call `play`.
class WatchLauncher {
  WatchLauncher._();

  static Future<void> Function(RemoteLaunch launch)? _handler;

  static void attach(Future<void> Function(RemoteLaunch launch) handler) => _handler = handler;

  static void detach(Future<void> Function(RemoteLaunch launch) handler) {
    if (identical(_handler, handler) || _handler == handler) _handler = null;
  }

  static bool get available => _handler != null;

  /// Starts watching; `false`: the player is not ready yet
  static Future<bool> play(RemoteLaunch launch) async {
    final h = _handler;
    if (h == null) return false;
    await h(launch);
    return true;
  }
}
