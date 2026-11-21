import 'dart:io' show Platform;

import 'package:flutter/widgets.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../utils/platform_info.dart';

/// One searchable setting: the tab it lives on, its group caption and the row title (as shown on screen).
/// [spot] is what to spotlight when the row itself may be hidden (e.g. behind a switch); by default the title.
class SettingsSearchEntry {
  final int tab;
  final String group;
  final String title;
  final IconData icon;
  final List<String> keywords;
  final String? spot;
  final bool Function()? when;

  const SettingsSearchEntry(this.tab, this.group, this.title, this.icon, {this.keywords = const [], this.spot, this.when});

  bool get available => when?.call() ?? true;
}

bool _mobile() => AppPlatform.isMobile;
bool _desktop() => !AppPlatform.isMobile;
bool _windows() => Platform.isWindows;
bool _android() => Platform.isAndroid;
bool _notAndroid() => !Platform.isAndroid;

/// Everything the settings search knows about. Titles must match the rows exactly (checked by a test).
/// Tabs: 0 Вигляд, 1 Субтитри, 2 Відтворення, 3 Відео & GPU, 4 Звук, 5 Розробник, 6 Про програму, 7 Anime4K, 8 Гарячі клавіші, 9 Каталог
final List<SettingsSearchEntry> settingsSearchIndex = [
  // Вигляд
  const SettingsSearchEntry(0, 'Оформлення', 'Тема оформлення', Symbols.dark_mode_rounded, keywords: ['темна', 'світла', 'нічна', 'theme']),
  const SettingsSearchEntry(0, 'Оформлення', 'Радіус заокруглення', Symbols.rounded_corner_rounded, keywords: ['кути', 'округлення']),
  const SettingsSearchEntry(0, 'Основний колір', 'Акцентний колір', Symbols.format_color_fill_rounded, keywords: ['колір', 'акцент', 'accent']),
  SettingsSearchEntry(0, 'Оформлення', 'Масштаб налаштувань', Symbols.zoom_in_rounded, keywords: ['розмір', 'шрифт', 'dpi', 'zoom'], when: _mobile),
  // Субтитри
  const SettingsSearchEntry(1, 'Субтитри', 'Автоматичне ввімкнення субтитрів', Symbols.subtitles_rounded, keywords: ['мова субтитрів', 'пріоритет мов']),
  const SettingsSearchEntry(1, 'Стилі SSA / ASS', 'Вигляд субтитрів SSA', Symbols.style_rounded, keywords: ['ass', 'ssa', 'стилі']),
  const SettingsSearchEntry(1, 'Шрифт', 'Шрифт субтитрів', Symbols.font_download_rounded, keywords: ['font']),
  const SettingsSearchEntry(1, 'Шрифт', 'Додати свій шрифт', Symbols.upload_file_rounded, keywords: ['ttf', 'otf']),
  SettingsSearchEntry(1, 'Шрифт', 'Додати кілька шрифтів', Symbols.create_new_folder_rounded, when: _android),
  SettingsSearchEntry(1, 'Шрифт', 'Додати теку зі шрифтами', Symbols.create_new_folder_rounded, when: _notAndroid),
  const SettingsSearchEntry(1, 'Вигляд тексту', 'Розмір шрифту', Symbols.format_size_rounded, keywords: ['розмір субтитрів']),
  const SettingsSearchEntry(1, 'Вигляд тексту', 'Товщина обводки', Symbols.border_style_rounded, keywords: ['обведення', 'контур']),
  const SettingsSearchEntry(1, 'Вигляд тексту', 'Тінь', Symbols.blur_on_rounded, keywords: ['тінь субтитрів']),
  const SettingsSearchEntry(1, 'Вигляд тексту', 'Відступ знизу', Symbols.vertical_align_bottom_rounded, keywords: ['позиція субтитрів', 'висота']),
  // Відтворення
  const SettingsSearchEntry(2, 'Відтворення', 'Автовідтворення наступного епізоду', Symbols.autoplay_rounded, keywords: ['наступна серія', 'автоплей']),
  const SettingsSearchEntry(2, 'Відтворення', 'Швидкість за замовчуванням', Symbols.speed_rounded, keywords: ['швидкість відтворення']),
  SettingsSearchEntry(2, 'Відтворення', 'Орієнтація плеєра', Symbols.screen_rotation_rounded, keywords: ['поворот', 'альбомна', 'портрет'], when: _mobile),
  const SettingsSearchEntry(2, 'Перемотування', 'Крок перемотування', Symbols.fast_forward_rounded, keywords: ['перемотка', 'секунд']),
  const SettingsSearchEntry(2, 'Перемотування', 'Перемотування подвійним дотиком', Symbols.touch_app_rounded, keywords: ['подвійний тап', 'жести']),
  SettingsSearchEntry(2, 'Перемотування', 'Кнопки перемотування на екрані', Symbols.forward_10_rounded, when: _mobile),
  SettingsSearchEntry(2, 'Перемотування', 'Кнопки перемотування на панелі', Symbols.forward_10_rounded, when: _desktop),
  const SettingsSearchEntry(2, 'Прискорення', 'Прискорення утримуванням', Symbols.pan_tool_rounded, keywords: ['утримання', 'x2']),
  const SettingsSearchEntry(2, 'Прискорення', 'Швидкість прискорення', Symbols.bolt_rounded, spot: 'Прискорення утримуванням'),
  const SettingsSearchEntry(2, 'Опенінґ та ендінґ', 'Кнопка пропуску опенінґу й ендінґу', Symbols.skip_next_rounded, keywords: ['опенінг', 'ендінг', 'пропустити', 'opening']),
  const SettingsSearchEntry(2, 'Опенінґ та ендінґ', 'Автоматичний пропуск', Symbols.keyboard_double_arrow_right_rounded, keywords: ['опенінг', 'ендінг']),
  const SettingsSearchEntry(2, 'Опенінґ та ендінґ', 'Шукати опенінґ за звуком', Symbols.graphic_eq_rounded, keywords: ['опенінг', 'aniskip', 'таймкоди', 'заставка', 'аналіз']),
  const SettingsSearchEntry(2, 'Опенінґ та ендінґ', 'Пісня опенінґу й ендінґу', Symbols.album_rounded, keywords: ['пісня', 'обкладинка', 'spotify', 'youtube music', 'apple music', 'музика']),
  // Відео & GPU
  const SettingsSearchEntry(3, 'Декодування', 'Апаратний декодер відео', Symbols.memory_rounded, keywords: ['hwdec', 'gpu', 'mediacodec', 'd3d11', 'декодування']),
  // Звук
  const SettingsSearchEntry(4, 'Звук', 'Корекція висоти тону', Symbols.graphic_eq_rounded, keywords: ['pitch', 'голос']),
  const SettingsSearchEntry(4, 'Пріоритет мов звукових доріжок', 'Мови звукових доріжок', Symbols.translate_rounded,
      keywords: ['аудіо', 'озвучка', 'доріжка'], spot: 'Пріоритет мов звукових доріжок'),
  // Anime4K
  const SettingsSearchEntry(7, 'Anime4K', 'Anime4K', Symbols.auto_awesome_rounded, keywords: ['шейдери', 'покращення', 'апскейл']),
  const SettingsSearchEntry(7, 'Режим', 'Режим Anime4K', Symbols.tune_rounded, spot: 'Anime4K'),
  const SettingsSearchEntry(7, 'Якість', 'Якість шейдерів', Symbols.high_quality_rounded, spot: 'Anime4K'),
  const SettingsSearchEntry(7, 'Якість', 'Вимикати для високої роздільності', Symbols.aspect_ratio_rounded, spot: 'Anime4K'),
  // Гарячі клавіші
  SettingsSearchEntry(8, 'Схема клавіш', 'Схема клавіш', Symbols.keyboard_rounded, keywords: ['hotkeys', 'клавіатура'], when: _desktop),
  SettingsSearchEntry(8, 'Усі комбінації', 'Усі комбінації', Symbols.keyboard_command_key_rounded, keywords: ['гарячі клавіші', 'shortcut'], when: _desktop),
  // Каталог
  const SettingsSearchEntry(9, 'Назви', 'Мова назв', Symbols.translate_rounded, keywords: ['українська', 'english', 'ромаджі']),
  const SettingsSearchEntry(9, 'Назви', 'Друга назва', Symbols.title_rounded),
  const SettingsSearchEntry(9, 'Назви', 'Мова другої назви', Symbols.language_rounded, spot: 'Друга назва'),
  const SettingsSearchEntry(9, 'Вміст', 'Контент 18+', Symbols.explicit_rounded, keywords: ['дорослий', 'nsfw', 'хентай']),
  const SettingsSearchEntry(9, 'Перегляд', 'Максимальна якість відео', Symbols.high_quality_rounded, keywords: ['1080', '720', 'роздільність']),
  const SettingsSearchEntry(9, 'Перегляд', 'Плеєр за замовчуванням', Symbols.smart_display_rounded, keywords: ['moon', 'хостинг']),
  const SettingsSearchEntry(9, 'Прогрес', 'Серія вважається переглянутою після', Symbols.task_alt_rounded, keywords: ['переглянуто', 'відсоток', 'hikka']),
  const SettingsSearchEntry(9, 'Прогрес', 'Зараховувати за ендінґом', Symbols.sports_score_rounded, keywords: ['ендінг']),
  const SettingsSearchEntry(9, 'Озвучення', 'Спершу повні озвучення', Symbols.mic_rounded, keywords: ['команди озвучення', 'пріоритет', 'фандаб']),
  const SettingsSearchEntry(9, 'Дані', 'Оновити дані', Symbols.refresh_rounded),
  const SettingsSearchEntry(9, 'Дані', 'Очистити кеш зображень', Symbols.delete_outline_rounded, keywords: ['кеш', 'обкладинки', 'пам’ять']),
  // Розробник
  const SettingsSearchEntry(5, 'Експериментальні функції', 'Локальна медіатека', Symbols.video_file_rounded, keywords: ['файли', 'плейлисти']),
  const SettingsSearchEntry(5, 'Ключі', 'Ключ TheMovieDB', Symbols.key_rounded, keywords: ['tmdb', 'банери']),
  const SettingsSearchEntry(5, 'Ключі', 'Ключ Mikai', Symbols.key_rounded),
  const SettingsSearchEntry(5, 'Ключі', 'Ключ Moon', Symbols.key_rounded),
  const SettingsSearchEntry(5, 'Власний клієнт Hikka', 'Референс клієнта', Symbols.badge_rounded),
  const SettingsSearchEntry(5, 'Журнал', 'Детальний журнал', Symbols.description_rounded, keywords: ['лог', 'логи']),
  const SettingsSearchEntry(5, 'Журнал', 'Зберегти журнал у файл', Symbols.download_rounded, keywords: ['лог', 'логи']),
  const SettingsSearchEntry(5, 'Журнал', 'Очистити журнали', Symbols.delete_outline_rounded, keywords: ['лог', 'логи']),
  SettingsSearchEntry(5, 'Журнал', 'Відкрити папку журналів', Symbols.folder_open_rounded, when: _windows),
  SettingsSearchEntry(5, 'Конфігурація та кеш', 'Відкрити папку конфігів', Symbols.folder_open_rounded, keywords: ['mpv.conf'], when: _windows),
  const SettingsSearchEntry(5, 'Конфігурація та кеш', 'Очистити історію перегляду', Symbols.history_rounded),
];

String _norm(String s) => s.toLowerCase().replaceAll('ґ', 'г').replaceAll('’', "'").replaceAll('ʼ', "'");

/// Settings matching the query: first those whose title starts with it, then contains it, then by group or keywords
List<SettingsSearchEntry> searchSettings(String query) {
  final q = _norm(query.trim());
  if (q.isEmpty) return const [];
  final scored = <(int, int, SettingsSearchEntry)>[];
  for (var i = 0; i < settingsSearchIndex.length; i++) {
    final e = settingsSearchIndex[i];
    if (!e.available) continue;
    final t = _norm(e.title);
    int? score;
    if (t.startsWith(q)) {
      score = 0;
    } else if (t.contains(' $q') || t.contains(q)) {
      score = t.contains(' $q') ? 1 : 2;
    } else if (_norm(e.group).contains(q) || e.keywords.any((k) => _norm(k).contains(q))) {
      score = 3;
    }
    if (score != null) scored.add((score, i, e));
  }
  scored.sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));
  return [for (final s in scored) s.$3];
}

/// "1 результат" / "3 результати" / "7 результатів"
String settingsResultsLabel(int n) {
  final m10 = n % 10, m100 = n % 100;
  final word = (m10 == 1 && m100 != 11)
      ? 'результат'
      : (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14))
          ? 'результати'
          : 'результатів';
  return '$n $word';
}
