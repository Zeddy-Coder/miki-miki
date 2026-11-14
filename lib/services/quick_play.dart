/// Швидкий перегляд з «Продовжити перегляд»: шукає озвучки, обирає ту саму серію, на якій людина зупинилась,
/// і одразу відкриває плеєр, не показуючи сторінку тайтлу.
library;

import 'dart:async';
import 'dart:math' as math;

import '../models/hikka_models.dart';
import 'app_log.dart';
import '../models/hikka_user_models.dart';
import 'hikka_lists.dart';
import 'hikka_prefs.dart';
import 'remote_playback.dart';
import 'watch_models.dart';
import 'watch_service.dart';

class QuickPlay {
  const QuickPlay._();

  /// Скільки чекаємо, поки знайдеться хоч одна озвучка
  static const Duration timeout = Duration(seconds: 25);

  /// Продовжує перегляд [anime]. `false` — з першого разу не вдалося (нічого не знайдено, тайтл ліцензований,
  /// плеєр ще не готовий): тоді викликач відкриває сторінку тайтлу, де видно причину й можна обрати вручну.
  static Future<bool> resume(
    HikkaAnime anime, {
    WatchService? service,
    Duration wait = timeout,
    Future<WatchGroup?> Function(MissingNext plan, int next)? onMissingNext,
  }) async {
    final svc = service ?? WatchService.instance;
    final load = svc.start(anime);
    try {
      // Прогрес на Hikka беремо свіжим: його могли змінити на сайті чи іншому пристрої, а запис у памʼяті застарів би;
      // без мережі лишається те, що вже було
      final mine = await HikkaMyList.instance.entry(anime.slug, refresh: true).then<HikkaWatchEntry?>((e) => e, onError: (_) => HikkaMyList.instance.cached(anime.slug));
      final seen = math.max(mine?.episodes ?? 0, svc.store.watched(load.animeKey).length);
      final done = Completer<void>();
      void check() {
        if (done.isCompleted) return;
        // Є варіант, де вже є наступна серія, або всі джерела вже відповіли (неповна озвучка першою не береться)
        final ready = load.title.groups.any((g) => g.hasEpisode(seen + 1)) && load.defaultGroup(svc.store, seen: seen) != null;
        if (ready || !load.busy) done.complete();
      }

      load.addListener(check);
      check();
      await done.future.timeout(wait, onTimeout: () {});
      load.removeListener(check);

      final title = load.title;
      var group = load.defaultGroup(svc.store, seen: seen);
      if (group == null || title.licensed) return false;
      // Обрана вручну озвучка не має наступної серії: питаємо, куди перейти (скасування — нічого не відкриваємо)
      final plan = onMissingNext == null ? null : load.missingNext(svc.store, seen: seen);
      if (plan != null) {
        final picked = await onMissingNext!(plan, seen + 1);
        if (picked == null) return true;
        svc.store.clearPinnedGroup(title.animeKey);
        group = picked;
      }
      final point = continuePoint(episodeKeysOf(group), svc.store.watched(title.animeKey), svc.store.last(title.animeKey)?.epKey, hikkaEpisodes: mine?.episodes ?? 0);
      return await WatchLauncher.play(
        RemoteLaunch(
          title: title,
          group: group,
          animeTitle: anime.title(HikkaPrefs.instance.titleLang),
          epKey: point.epKey,
          poster: anime.image,
          hikka: load.hikka,
        ),
      );
    } catch (e) {
      AppLog.w('перегляд', 'швидкий старт не вдався: $e');
      return false;
    } finally {
      load.dispose();
    }
  }
}
