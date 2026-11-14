/// Назва й технічні ідентифікатори застосунку в одному місці.
///
/// Усе, що користувач бачить (вікно, «Про програму», журнал, заголовки запитів), бере назву звідси,
/// а не з розкиданих рядків. Тека даних лишилася від попередньої назви лише як `legacyDataDirName`:
/// дані з неї переносяться при першому запуску ([AppIdentity.migrateLegacyData]).
library;

import 'dart:io';

class AppIdentity {
  const AppIdentity._();

  /// Назва для людей
  static const String name = 'Miki Miki';

  /// Коротка назва в одне слово (імена файлів, заголовки запитів)
  static const String shortName = 'MikiMiki';

  /// Ім'я пакета Dart / префікс технічних назв файлів і каналів
  static const String packageName = 'miki_miki';

  /// Теки даних: `%APPDATA%/<dataDirName>` на Windows, `files/<dataDirName>` на Android
  static const String dataDirName = 'MikiMiki';

  /// Тека даних під попередньою назвою (перенос при першому запуску)
  static const String legacyDataDirName = 'MyPlayerFork';

  /// Підпис у боковому меню й у «Про програму»
  static const String tagline = 'Hikka · аніме українською';

  /// Версія для людей (синхронна з `pubspec.yaml`)
  static const String version = '1.1.3';

  /// `User-Agent` запитів до сайтів і API (без особистих даних)
  static String userAgent(String purpose) => '$shortName/$version (Flutter; $purpose)';

  /// Переносить дані зі старої теки в нову, якщо нової ще немає. Спершу пробує перейменувати теку
  /// (миттєво), а коли не вийшло (інший диск, зайняті файли) — копіює. Повертає `true`, якщо щось перенесено.
  /// Ніколи не кидає винятків: збій переносу не має заважати запуску (тоді застосунок почне з чистої теки).
  static Future<bool> migrateLegacyData(Directory legacy, Directory current) async {
    try {
      if (await current.exists() || !await legacy.exists()) return false;
      await current.parent.create(recursive: true);
      try {
        await legacy.rename(current.path);
        return true;
      } catch (_) {
        await _copyTree(legacy, current);
        return true;
      }
    } catch (_) {
      return false;
    }
  }

  static Future<void> _copyTree(Directory from, Directory to) async {
    await to.create(recursive: true);
    await for (final e in from.list(followLinks: false)) {
      final name = e.uri.pathSegments.where((s) => s.isNotEmpty).last;
      final target = '${to.path}${Platform.pathSeparator}$name';
      if (e is Directory) {
        await _copyTree(e, Directory(target));
      } else if (e is File) {
        await e.copy(target);
      }
    }
  }
}
