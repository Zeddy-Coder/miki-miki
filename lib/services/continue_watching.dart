/// «Продовжити перегляд»: тайтли Hikka, які людина недавно відкривала в плеєрі, найновіші першими.
/// Дані беруться з `WatchStore` (що й коли відкривали) та `HikkaApi` (постер і назва); прогрес усередині
/// серії зберігає плеєр окремо.
library;

import '../models/hikka_models.dart';
import 'hikka_api.dart';
import 'watch_store.dart';

/// Тайтл у списку «Продовжити перегляд»
class ContinueItem {
  final HikkaAnime anime;

  /// Остання відкрита серія («3», «s2e5») або `null`, якщо номера немає
  final String? episodeKey;
  final DateTime at;

  const ContinueItem({required this.anime, required this.episodeKey, required this.at});

  /// «Серія 3» / «Сезон 2 · серія 5»; `null`, якщо серію не визначено
  String? get episodeLabel => episodeKey == null ? null : ContinueWatching.episodeCaption(episodeKey!);

  /// Коротка плашка для постера: «Серія 3» / «С2 · Е5»
  String? get episodeShort => episodeKey == null ? null : ContinueWatching.episodeShort(episodeKey!);
}

class ContinueWatching {
  const ContinueWatching._();

  /// Префікс ключа тайтлу Hikka у `WatchStore` (`hikka:<slug>`)
  static const String prefix = 'hikka:';

  /// Підпис за ключем серії: «3» → «Серія 3», «3.5» → «Серія 3.5», «s2e5» → «Сезон 2 · серія 5», «i7» → «Серія 7»
  static String? episodeCaption(String epKey) {
    final season = RegExp(r'^s(\d+)e(.+)$').firstMatch(epKey);
    if (season != null) return 'Сезон ${season.group(1)} · серія ${_number(season.group(2)!)}';
    final plain = _number(epKey);
    return plain.isEmpty ? null : 'Серія $plain';
  }

  /// Коротко для плашки на постері: «3» → «Серія 3», «s2e5» → «С2 · Е5»
  static String? episodeShort(String epKey) {
    final season = RegExp(r'^s(\d+)e(.+)$').firstMatch(epKey);
    if (season != null) return 'С${season.group(1)} · Е${_number(season.group(2)!)}';
    final plain = _number(epKey);
    return plain.isEmpty ? null : 'Серія $plain';
  }

  /// Порядковий номер «i7» показується як «7»
  static String _number(String key) => key.startsWith('i') ? key.substring(1) : key;

  /// Тайтли Hikka з недавніми переглядами: (slug, остання відкрита серія, коли), найновіші першими
  static List<(String slug, String? epKey, DateTime at)> recent({WatchStore? store, int limit = 12}) {
    final s = store ?? WatchStore.instance;
    final out = <(String, String?, DateTime)>[];
    for (final key in s.recentTitles(limit: 400)) {
      if (!key.startsWith(prefix)) continue;
      final slug = key.substring(prefix.length);
      if (slug.isEmpty) continue;
      final last = s.last(key);
      if (last == null) continue;
      out.add((slug, last.epKey.isEmpty ? null : last.epKey, last.at));
      if (out.length >= limit) break;
    }
    return out;
  }

  /// Завантажує тайтли (запити йдуть паралельно, збійні пропускаються). Завершені й повністю переглянуті не показуються.
  static Future<List<ContinueItem>> load({WatchStore? store, HikkaApi? api, int limit = 12, bool allowAdult = false}) async {
    final s = store ?? WatchStore.instance;
    final client = api ?? HikkaApi.instance;
    final entries = recent(store: s, limit: limit);
    final loaded = await Future.wait([
      for (final e in entries)
        () async {
          try {
            return await client.anime(e.$1);
          } catch (_) {
            return null;
          }
        }(),
    ]);
    final out = <ContinueItem>[];
    for (int i = 0; i < entries.length; i++) {
      final anime = loaded[i];
      if (anime == null) continue;
      if (anime.isAdult && !allowAdult) continue;
      final total = anime.episodesTotal ?? 0;
      final done = s.watched('$prefix${entries[i].$1}').length;
      if (anime.status == 'finished' && total > 0 && done >= total) continue;
      out.add(ContinueItem(anime: anime, episodeKey: entries[i].$2, at: entries[i].$3));
    }
    return out;
  }
}
