/// Швидкий перегляд з «Продовжити перегляд»: шукає озвучки, обирає ту саму серію, на якій людина зупинилась,
/// і одразу відкриває плеєр, не показуючи сторінку тайтлу.
library;

import 'dart:async';

import '../models/hikka_models.dart';
import 'app_log.dart';
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
  static Future<bool> resume(HikkaAnime anime, {WatchService? service, Duration wait = timeout}) async {
    final svc = service ?? WatchService.instance;
    final load = svc.start(anime);
    try {
      final done = Completer<void>();
      void check() {
        if (done.isCompleted) return;
        // Є що запускати, або всі джерела вже відповіли
        if (load.defaultGroup(svc.store) != null || !load.busy) done.complete();
      }

      load.addListener(check);
      check();
      await done.future.timeout(wait, onTimeout: () {});
      load.removeListener(check);

      final title = load.title;
      final group = load.defaultGroup(svc.store);
      if (group == null || title.licensed) return false;
      final point = continuePoint(episodeKeysOf(group), svc.store.watched(title.animeKey), svc.store.last(title.animeKey)?.epKey);
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
