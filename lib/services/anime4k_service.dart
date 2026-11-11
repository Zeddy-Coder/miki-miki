import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;

import 'storage_service.dart';

/// Виконує команду mpv (`change-list glsl-shaders …`). У застосунку це `NativePlayer.command`.
typedef MpvCommand = Future<void> Function(List<String> args);

/// Якість ланцюжка шейдерів Anime4K.
enum Anime4kQuality {
  fast('Fast', 'Швидкий', 'Для слабших відеокарт: GTX 980, GTX 1060, RX 570 та подібних', 'Для слабших пристроїв: менше навантаження й нагрів'),
  hq('HQ', 'Висока якість', 'Для потужних відеокарт: GTX 1080, RTX 2070, RTX 3060, RX 5700 XT та вище', 'Для потужних пристроїв: краща картинка, більше навантаження');

  const Anime4kQuality(this.label, this.title, this.gpuHint, this.deviceHint);

  final String label;
  final String title;

  /// Підказка для ПК (відеокарти)
  final String gpuHint;

  /// Підказка для телефона (без назв відеокарт)
  final String deviceHint;

  static Anime4kQuality parse(String? raw) =>
      Anime4kQuality.values.firstWhere((q) => q.name == raw, orElse: () => Anime4kQuality.fast);
}

/// Режими Anime4K (офіційні комбінації v4). Вибирати треба той, що виглядає найкраще.
enum Anime4kMode {
  a(
    label: 'A',
    digit: 1,
    tagline: 'Відновлення та апскейл',
    bestFor: 'Більшість 1080p, старіші 720p та SD: розмиття, артефакти стиснення, шум',
    note: 'Найвиразніший ефект. За неправильного вибору може підсилити «дзвін» і бандинг.',
  ),
  b(
    label: 'B',
    digit: 2,
    tagline: 'М’яке відновлення та апскейл',
    bestFor: 'Більшість 720p і аніме, зменшене з 1080p до 720p: «дзвін», зубчасті краї, легке розмиття',
    note: 'Обережніший за A, але частина артефактів може залишитися.',
  ),
  c(
    label: 'C',
    digit: 3,
    tagline: 'Апскейл із шумозаглушенням',
    bestFor: 'Відео, зменшене до 480p, чисті зображення, шпалери та арт',
    note: 'Найвища точність, проте лінії не відновлюються.',
  ),
  aa(
    label: 'A+A',
    digit: 4,
    tagline: 'A з другим проходом відновлення',
    bestFor: 'Те саме, що й A, коли потрібна максимальна якість',
    note: 'Лише для апскейлу від ×2: на 1080p-екрані може перешарпити. Повільніше за A.',
    needsUpscale: true,
  ),
  bb(
    label: 'B+B',
    digit: 5,
    tagline: 'B з другим проходом відновлення',
    bestFor: 'Те саме, що й B, коли потрібна вища якість',
    note: 'Лише для апскейлу від ×2. Повільніше за B.',
    needsUpscale: true,
  ),
  ca(
    label: 'C+A',
    digit: 6,
    tagline: 'C з додатковим відновленням',
    bestFor: 'Те саме, що й C, трохи вища сприйнята якість',
    note: 'Лише для апскейлу від ×2. Повільніше за C.',
    needsUpscale: true,
  );

  const Anime4kMode({
    required this.label,
    required this.digit,
    required this.tagline,
    required this.bestFor,
    required this.note,
    this.needsUpscale = false,
  });

  /// Коротка назва: A, B+B …
  final String label;

  /// Цифра в комбінації Ctrl+цифра (як в офіційному input.conf Anime4K)
  final int digit;
  final String tagline;
  final String bestFor;
  final String note;

  /// Режими з другим проходом мають сенс лише при збільшенні картинки від ×2
  final bool needsUpscale;

  String get title => 'Режим $label';

  /// Ідентифікатор дії клавіші в каталозі гарячих клавіш
  String get shortcutId => 'a4k_mode_$digit';

  static Anime4kMode parse(String? raw) =>
      Anime4kMode.values.firstWhere((m) => m.name == raw, orElse: () => Anime4kMode.a);
}

/// Нативна підтримка Anime4K: шейдери лежать у assets, при першому використанні розпаковуються
/// в `%APPDATA%/MikiMiki/shaders/anime4k` (mpv читає шейдери лише з диска) і підключаються
/// до рушія командою `change-list glsl-shaders`.
///
/// Шейдери: bloc97/Anime4K v4.0.1, ліцензія MIT (assets/shaders/anime4k/LICENSE.txt).
class Anime4kService {
  Anime4kService._();

  static const String assetDir = 'assets/shaders/anime4k';

  static const String _clamp = 'Anime4K_Clamp_Highlights.glsl';
  static const String _down2 = 'Anime4K_AutoDownscalePre_x2.glsl';
  static const String _down4 = 'Anime4K_AutoDownscalePre_x4.glsl';

  static String _restore(String v) => 'Anime4K_Restore_CNN_$v.glsl';
  static String _restoreSoft(String v) => 'Anime4K_Restore_CNN_Soft_$v.glsl';
  static String _upscale(String v) => 'Anime4K_Upscale_CNN_x2_$v.glsl';
  static String _upscaleDenoise(String v) => 'Anime4K_Upscale_Denoise_CNN_x2_$v.glsl';

  /// Ланцюжок шейдерів режиму — точно як в офіційних шаблонах input.conf
  /// (Low-end → Fast: M та S, High-end → HQ: VL та M).
  static List<String> chain(Anime4kMode mode, Anime4kQuality quality) {
    final big = quality == Anime4kQuality.hq ? 'VL' : 'M';
    final small = quality == Anime4kQuality.hq ? 'M' : 'S';
    switch (mode) {
      case Anime4kMode.a:
        return [_clamp, _restore(big), _upscale(big), _down2, _down4, _upscale(small)];
      case Anime4kMode.b:
        return [_clamp, _restoreSoft(big), _upscale(big), _down2, _down4, _upscale(small)];
      case Anime4kMode.c:
        return [_clamp, _upscaleDenoise(big), _down2, _down4, _upscale(small)];
      case Anime4kMode.aa:
        return [_clamp, _restore(big), _upscale(big), _restore(small), _down2, _down4, _upscale(small)];
      case Anime4kMode.bb:
        return [_clamp, _restoreSoft(big), _upscale(big), _down2, _down4, _restoreSoft(small), _upscale(small)];
      case Anime4kMode.ca:
        return [_clamp, _upscaleDenoise(big), _down2, _down4, _restore(small), _upscale(small)];
    }
  }

  /// Усі файли, які можуть знадобитися (для перевірки збірки)
  static Set<String> get allShaderFiles => {
        for (final q in Anime4kQuality.values)
          for (final m in Anime4kMode.values) ...chain(m, q),
      };

  /// «Режим A (Fast)»
  static String describe(Anime4kMode mode, Anime4kQuality quality) => '${mode.title} (${quality.label})';

  static Directory get shaderDir => Directory('${StorageService.appBasePath}/shaders/anime4k');

  static final Set<String> _verified = {};

  /// Розпаковує потрібні шейдери з assets (лише відсутні чи змінені) і повертає шляхи з прямими слешами.
  static Future<List<String>> ensureExtracted(List<String> names) async {
    final dir = shaderDir;
    if (!await dir.exists()) await dir.create(recursive: true);
    final paths = <String>[];
    for (final name in names) {
      final file = File('${dir.path}/$name');
      // Розмір звіряється раз за запуск, наявність файлу — щоразу (папку могли очистити, поки плеєр працює)
      if (!_verified.contains(file.path) || !await file.exists()) {
        final data = await rootBundle.load('$assetDir/$name');
        final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        if (!await file.exists() || await file.length() != bytes.length) {
          await file.writeAsBytes(bytes, flush: true);
        }
        _verified.add(file.path);
      }
      paths.add(file.path.replaceAll('\\', '/'));
    }
    return paths;
  }

  /// Підключає ланцюжок до mpv. Повертає текст помилки або `null`, якщо все гаразд.
  static Future<String?> apply(MpvCommand command, Anime4kMode mode, Anime4kQuality quality) async {
    final List<String> paths;
    try {
      paths = await ensureExtracted(chain(mode, quality));
    } on FileSystemException catch (e) {
      return 'Не вдалося розпакувати шейдери: ${e.osError?.message ?? e.message}';
    } catch (_) {
      return 'Шейдери Anime4K не знайдено в збірці. Закрийте застосунок і запустіть його заново (не hot reload)';
    }

    try {
      // Роздільник списку шляхів у mpv: «;» на Windows, «:» в інших системах
      final sep = Platform.isWindows ? ';' : ':';
      if (paths.any((p) => p.contains(sep))) {
        // Шлях містить роздільник — додаємо по одному (append не розбиває рядок)
        await command(const ['change-list', 'glsl-shaders', 'clr', '']);
        for (final p in paths) {
          await command(['change-list', 'glsl-shaders', 'append', p]);
        }
      } else {
        await command(['change-list', 'glsl-shaders', 'set', paths.join(sep)]);
      }
      return null;
    } catch (e) {
      return 'Рушій відхилив шейдери: $e';
    }
  }

  /// Вимикає всі GLSL-шейдери (як CTRL+0 в офіційному конфігу)
  static Future<void> clear(MpvCommand command) async {
    try {
      await command(const ['change-list', 'glsl-shaders', 'clr', '']);
    } catch (_) {}
  }

  /// Чи схожий рядок логу mpv на помилку шейдера (компіляція, відсутній файл)
  static bool looksLikeShaderFailure(String level, String text) {
    if (level != 'error' && level != 'fatal') return false;
    final t = text.toLowerCase();
    return t.contains('shader') || t.contains('glsl') || t.contains('anime4k');
  }
}
