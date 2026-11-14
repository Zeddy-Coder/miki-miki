/// App name and technical identifiers in one place.
///
/// Everything the user sees (window, "About", log, request headers) takes the name from here
/// rather than from scattered strings. The data folder remains from the previous name only as `legacyDataDirName`:
/// its data is migrated on first launch ([AppIdentity.migrateLegacyData]).
library;

import 'dart:io';

class AppIdentity {
  const AppIdentity._();

  /// Human-readable name
  static const String name = 'Miki Miki';

  /// Short one-word name (file names, request headers)
  static const String shortName = 'MikiMiki';

  /// Dart package name / prefix for technical file and channel names
  static const String packageName = 'miki_miki';

  /// Data folders: `%APPDATA%/<dataDirName>` on Windows, `files/<dataDirName>` on Android
  static const String dataDirName = 'MikiMiki';

  /// Data folder under the previous name (migrated on first launch)
  static const String legacyDataDirName = 'MyPlayerFork';

  /// Label in the side menu and in "About"
  static const String tagline = 'Hikka · аніме українською';

  /// Human-readable version (kept in sync with `pubspec.yaml`)
  static const String version = '1.1.5';

  /// `User-Agent` of requests to sites and APIs (no personal data)
  static String userAgent(String purpose) => '$shortName/$version (Flutter; $purpose)';

  /// Moves data from the old folder to the new one if the new one does not exist yet. First tries renaming the folder
  /// (instant), and when that fails (another drive, locked files) it copies. Returns `true` if anything was moved.
  /// Never throws: a migration failure must not block startup (the app then starts with a clean folder).
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
