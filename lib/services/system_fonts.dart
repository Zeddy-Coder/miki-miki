import 'dart:io';

/// Bundled fonts that really exist on the device: we do not list what is missing (on Android only Roboto)
class SystemFonts {
  SystemFonts._();

  /// Fonts bundled into the app (assets/fonts). Commercial fonts (Trebuchet MS, Impress BT) are not
  /// in the repository for licensing reasons; you can add your own free fonts here.
  static const Map<String, String> embedded = {};

  static const Map<String, List<String>> _files = {
    'Arial': ['arial.ttf', 'Arial.ttf'],
    'Roboto': ['Roboto-Regular.ttf', 'Roboto.ttf', 'RobotoStatic-Regular.ttf'],
    'Segoe UI': ['segoeui.ttf'],
    'Tahoma': ['tahoma.ttf', 'Tahoma.ttf'],
    'Consolas': ['consola.ttf'],
  };

  static List<String>? _cached;

  static List<String> get available => _cached ??= _scan();

  static List<String> _scan() {
    final dirs = <String>[
      if (Platform.isWindows) '${Platform.environment['WINDIR'] ?? r'C:\Windows'}\\Fonts',
      if (Platform.isAndroid) '/system/fonts',
      if (Platform.isAndroid) '/system/font',
      if (Platform.isLinux) '/usr/share/fonts/truetype',
      if (Platform.isMacOS) '/System/Library/Fonts',
      if (Platform.isMacOS) '/Library/Fonts',
    ];
    final found = <String>[];
    for (final e in _files.entries) {
      var ok = false;
      for (final d in dirs) {
        for (final f in e.value) {
          if (File('$d${Platform.isWindows ? '\\' : '/'}$f').existsSync()) {
            ok = true;
            break;
          }
        }
        if (ok) break;
      }
      if (ok) found.add(e.key);
    }
    return [...embedded.keys, ...found];
  }

  /// Default subtitle font: Arial on PC, Roboto on phone (the only system one)
  static String get defaultFont => Platform.isAndroid ? 'Roboto' : 'Arial';
}
