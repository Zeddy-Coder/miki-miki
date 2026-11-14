import 'dart:async';

import 'hikka_lists.dart';
import 'watch_store.dart';

/// "Watched" marks for site episodes: in the app and (for catalog titles, when signed in) on Hikka.
class WatchMarks {
  static const String _prefix = 'hikka:';

  /// Episode number for Hikka. The site's number is trusted if at least one episode of the variant lies within the title;
  /// continuous numbering (13…24 for 12 episodes) is counted by position
  static int hikkaNumber({required double? number, required int position, required Iterable<double?> allNumbers, int? total}) {
    final nums = allNumbers.whereType<double>().toList();
    final trust = nums.isEmpty || total == null || total <= 0 || nums.reduce((a, b) => a < b ? a : b) <= total;
    return HikkaMyList.episodeNumber(number: number, position: position, total: total, trustNumber: trust);
  }

  /// Sends progress to Hikka lists: only for Hikka catalog titles, only when signed in, and quietly
  static void syncToHikka(String animeKey, int episode, {int? total}) {
    if (!animeKey.startsWith(_prefix)) return;
    unawaited(HikkaMyList.instance.syncEpisode(animeKey.substring(_prefix.length), episode, total: total));
  }

  /// Sets or clears the mark of episode [epKey] (on Hikka by number [hikkaEpisode])
  static void set(WatchStore store, String animeKey, String epKey, bool value, {required int hikkaEpisode, int? total}) {
    store.setWatched(animeKey, epKey, value);
    if (!animeKey.startsWith(_prefix)) return;
    final slug = animeKey.substring(_prefix.length);
    if (value) {
      unawaited(HikkaMyList.instance.syncEpisode(slug, hikkaEpisode, total: total));
    } else {
      unawaited(HikkaMyList.instance.unmarkEpisode(slug, hikkaEpisode, total: total));
    }
  }
}
