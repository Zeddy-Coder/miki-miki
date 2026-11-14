import 'dart:async';

import 'hikka_lists.dart';
import 'watch_store.dart';

/// Позначки «переглянуто» для серій із сайтів: у застосунку й (для тайтлів каталогу, за входу) на Hikka.
class WatchMarks {
  static const String _prefix = 'hikka:';

  /// Номер серії для Hikka. Номер із сайту довіряється, якщо хоч одна серія варіанта лежить у межах тайтлу;
  /// наскрізна нумерація (13…24 для 12 серій) рахується за позицією
  static int hikkaNumber({required double? number, required int position, required Iterable<double?> allNumbers, int? total}) {
    final nums = allNumbers.whereType<double>().toList();
    final trust = nums.isEmpty || total == null || total <= 0 || nums.reduce((a, b) => a < b ? a : b) <= total;
    return HikkaMyList.episodeNumber(number: number, position: position, total: total, trustNumber: trust);
  }

  /// Передає прогрес у списки Hikka: лише для тайтлів каталогу Hikka, лише за входу й тихо
  static void syncToHikka(String animeKey, int episode, {int? total}) {
    if (!animeKey.startsWith(_prefix)) return;
    unawaited(HikkaMyList.instance.syncEpisode(animeKey.substring(_prefix.length), episode, total: total));
  }

  /// Ставить чи знімає позначку серії [epKey] (на Hikka — за номером [hikkaEpisode])
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
