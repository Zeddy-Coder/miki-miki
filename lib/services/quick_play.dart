/// Quick watching from "Продовжити перегляд": finds the dubs, picks the same episode where the person stopped,
/// and opens the player right away without showing the title page.
library;

import 'dart:async';
import 'dart:math' as math;

import '../models/hikka_models.dart';
import 'app_log.dart';
import 'downloads/download_manager.dart';
import 'network_status.dart';
import '../models/hikka_user_models.dart';
import 'hikka_lists.dart';
import 'hikka_prefs.dart';
import 'remote_playback.dart';
import 'watch_models.dart';
import 'watch_service.dart';

class QuickPlay {
  const QuickPlay._();

  /// How long we wait for at least one dub to be found
  static const Duration timeout = Duration(seconds: 25);

  /// Continues watching [anime]. `false`: failed on the first try (nothing found, the title is licensed,
  /// the player is not ready): then the caller opens the title page, where the reason is visible and a manual choice is possible.
  static Future<bool> resume(
    HikkaAnime anime, {
    WatchService? service,
    Duration wait = timeout,
    Future<WatchGroup?> Function(MissingNext plan, int next)? onMissingNext,
  }) async {
    final svc = service ?? WatchService.instance;
    final load = svc.start(anime);
    try {
      // We take Hikka progress fresh: it could have changed on the site or another device, and the in-memory record would be stale;
      // without a network, what we had stays
      final mine = await HikkaMyList.instance.entry(anime.slug, refresh: true).then<HikkaWatchEntry?>((e) => e, onError: (_) => HikkaMyList.instance.cached(anime.slug));
      final seen = math.max(mine?.episodes ?? 0, svc.store.watched(load.animeKey).length);
      final done = Completer<void>();
      void check() {
        if (done.isCompleted) return;
        // There is a variant that already has the next episode, or all sources have already answered (an incomplete dub is not taken first)
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
      // The manually chosen dub has no next episode: we ask where to go (cancelling opens nothing)
      final plan = onMissingNext == null ? null : load.missingNext(svc.store, seen: seen);
      if (plan != null) {
        final picked = await onMissingNext!(plan, seen + 1);
        if (picked == null) return true;
        svc.store.clearPinnedGroup(title.animeKey);
        group = picked;
      }
      final keys = episodeKeysOf(group);
      final watched = svc.store.watched(title.animeKey);
      final point = continuePoint(keys, watched, svc.store.last(title.animeKey)?.epKey, hikkaEpisodes: mine?.episodes ?? 0);
      var epKey = point.epKey;
      // No internet: from the nearest downloaded episode
      if (!NetworkStatus.instance.online) {
        epKey = DownloadManager.instance.offlineStart(title.animeKey, group.id, keys, point.allWatched ? 0 : point.index, watched) ?? epKey;
      }
      return await WatchLauncher.play(
        RemoteLaunch(
          title: title,
          group: group,
          animeTitle: anime.title(HikkaPrefs.instance.titleLang),
          epKey: epKey,
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
