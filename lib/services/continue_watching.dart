/// «Продовжити перегляд»: тайтли Hikka, які людина недавно відкривала в плеєрі, найновіші першими.
/// Дані беруться з `WatchStore` (що й коли відкривали) та `HikkaApi` (постер і назва); прогрес усередині
/// серії зберігає плеєр окремо.
library;

import 'dart:async';

import '../models/hikka_models.dart';
import '../models/hikka_user_models.dart';
import 'hikka_api.dart';
import 'hikka_auth.dart';
import 'hikka_lists.dart';
import 'watch_service.dart';
import 'watch_store.dart';

/// Тайтл у списку «Продовжити перегляд»
class ContinueItem {
  final HikkaAnime anime;

  /// Остання відкрита серія («3», «s2e5») або `null`, якщо номера немає
  final String? episodeKey;
  final DateTime at;

  /// Тайтл дивились, але його немає в жодному зі списків Hikka (показується з позначкою)
  final bool notInList;

  /// Скільки серій уже переглянуто і скільки їх у озвучці, яку обрано під час перегляду (`null` — невідомо)
  final int watched;
  final int? dubCount;

  /// Скільки серій було в озвучці до останнього збільшення (див. [hasNew])
  final int? dubPrev;

  /// Назва обраної озвучки (для підпису «Нова серія · Inari»)
  final String dubName;

  const ContinueItem({required this.anime, required this.episodeKey, required this.at, this.notInList = false, this.watched = 0, this.dubCount, this.dubPrev, this.dubName = ''});

  /// «Нова серія»: лише для онґоїнгу й лише якщо глядач дивився усе, що було доступно в обраній озвучці до виходу
  /// нової серії (`watched >= dubPrev`). Хто не додивився попередні, «нових» не бачить, поки не наздожене. Серії,
  /// що вийшли в інших командах, не рахуються
  bool get hasNew => anime.isOngoing && dubCount != null && dubCount! > watched && watched >= (dubPrev ?? dubCount!);

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

  /// Скільки серій у озвучці, яку людина обрала під час перегляду цього тайтлу: (кількість, назва) або (`null`, '').
  /// Лише для тієї самої озвучки, що й остання відкрита (чи обрана на сторінці): дані іншої команди не підходять.
  static (int?, String, int?) dubOf(WatchStore s, String animeKey) {
    final av = s.available(animeKey);
    if (av == null) return (null, '', null);
    final chosen = (s.last(animeKey)?.groupId ?? '').isNotEmpty ? s.last(animeKey)!.groupId : s.preferredGroup(animeKey);
    if (chosen != av.groupId) return (null, '', null);
    return (av.count, av.label, av.prev);
  }

  /// Підпис кількості серій обраних озвучок: зміна означає, що полицю треба перебудувати
  static String availabilitySignature({WatchStore? store}) {
    final s = store ?? WatchStore.instance;
    return [for (final r in recent(store: s, limit: 24)) () {
      final d = dubOf(s, '$prefix${r.$1}');
      return '${r.$1}:${d.$1}:${d.$3}';
    }()].join(',');
  }

  /// Тихо перевіряє, чи з'явились нові серії в обраній озвучці онґоїнгів зі списку (результат осідає в `WatchStore`).
  /// Не частіше ніж раз на [maxAge] для тайтлу й не більше [max] за раз, по черзі.
  static Future<void> refreshAvailability(
    List<ContinueItem> items, {
    WatchStore? store,
    WatchService? service,
    Duration maxAge = const Duration(hours: 3),
    int max = 4,
  }) async {
    final s = store ?? WatchStore.instance;
    final svc = service ?? WatchService.instance;
    var n = 0;
    for (final it in items) {
      if (n >= max) break;
      final a = it.anime;
      if (!a.isOngoing) continue;
      final key = '$prefix${a.slug}';
      final gid = (s.last(key)?.groupId ?? '').isNotEmpty ? s.last(key)!.groupId : s.preferredGroup(key);
      if (gid == null || gid.isEmpty) continue;
      final av = s.available(key);
      if (av != null && av.groupId == gid && DateTime.now().difference(av.at) < maxAge) continue;
      n++;
      final load = svc.start(a, searchOthers: !gid.startsWith('mikai|'));
      final done = Completer<void>();
      void check() {
        if (!load.busy && !done.isCompleted) done.complete();
      }
      load.addListener(check);
      check();
      await done.future.timeout(const Duration(seconds: 25), onTimeout: () {});
      load.removeListener(check);
      load.dispose();
    }
  }

  /// Список «Продовжити перегляд»: усе зі списку «Дивлюсь» на Hikka (якщо є вхід) плюс тайтли, які дивились
  /// локально, але не додали до жодного списку (з позначкою [ContinueItem.notInList]). Порядок — за останнім
  /// переглядом (у кого його немає — за часом оновлення запису на Hikka), тож і онґоїнги без нових серій стоять
  /// там, де ви на них зупинились. Завершені й повністю переглянуті локальні тайтли не показуються.
  static Future<List<ContinueItem>> load({WatchStore? store, HikkaApi? api, HikkaAuth? auth, HikkaMyList? lists, int limit = 20, bool allowAdult = false}) async {
    final s = store ?? WatchStore.instance;
    final client = api ?? HikkaApi.instance;
    final user = auth ?? HikkaAuth.instance;
    final myList = lists ?? HikkaMyList.instance;
    final recents = recent(store: s, limit: 400);
    final local = {for (final r in recents) r.$1: r};

    // Список «Дивлюсь» (помилка мережі не фатальна: лишаються локальні перегляди)
    final watching = <HikkaWatchEntry>[];
    if (user.signedIn && user.username.isNotEmpty) {
      try {
        for (var page = 1; page <= 5; page++) {
          final p = await client.watchList(user.username, status: HikkaWatchStatus.watching, page: page, size: 100);
          watching.addAll(p.items.where((e) => e.anime != null));
          if (page >= p.pages || p.items.isEmpty) break;
        }
      } catch (_) {}
    }

    final out = <ContinueItem>[];
    final seen = <String>{};
    for (final e in watching) {
      final a = e.anime!;
      if (a.isAdult && !allowAdult) continue;
      if (!seen.add(a.slug)) continue;
      final l = local[a.slug];
      final done = s.watched('$prefix${a.slug}').length;
      final dub = dubOf(s, '$prefix${a.slug}');
      // Прогрес на Hikka попереду за локальним (дивились на сайті): підпис і продовження йдуть від нього
      final localNum = int.tryParse((l?.$2 ?? '').replaceAll(RegExp(r'^s\d+e'), '')) ?? 0;
      out.add(ContinueItem(
        anime: a,
        episodeKey: e.episodes > localNum ? '${e.episodes}' : l?.$2,
        at: l?.$3 ?? DateTime.fromMillisecondsSinceEpoch(e.updated * 1000),
        watched: done > e.episodes ? done : e.episodes,
        dubCount: dub.$1,
        dubPrev: dub.$3,
        dubName: dub.$2,
      ));
    }

    // Локальні перегляди поза списком «Дивлюсь»
    final extra = [for (final r in recents) if (!seen.contains(r.$1)) r].take(limit).toList();
    final loaded = await Future.wait([
      for (final r in extra)
        () async {
          try {
            return await client.anime(r.$1);
          } catch (_) {
            return null;
          }
        }(),
    ]);
    for (int i = 0; i < extra.length; i++) {
      final anime = loaded[i];
      if (anime == null) continue;
      if (anime.isAdult && !allowAdult) continue;
      final total = anime.episodesTotal ?? 0;
      final done = s.watched('$prefix${extra[i].$1}').length;
      if (anime.status == 'finished' && total > 0 && done >= total) continue;
      // Тайтли з інших списків (заплановане, відкладене…) не вважаються «поза списком»
      final inList = user.signedIn && myList.statusOf(extra[i].$1) != null;
      out.add(ContinueItem(
        anime: anime,
        episodeKey: extra[i].$2,
        at: extra[i].$3,
        notInList: !inList,
        watched: done,
        dubCount: dubOf(s, '$prefix${extra[i].$1}').$1,
        dubPrev: dubOf(s, '$prefix${extra[i].$1}').$3,
        dubName: dubOf(s, '$prefix${extra[i].$1}').$2,
      ));
    }
    out.sort((a, b) => b.at.compareTo(a.at));
    return out.take(limit).toList();
  }
}
