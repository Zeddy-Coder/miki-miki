import 'package:flutter/services.dart';

/// Схема гарячих клавіш. Відрізняються лише клавіші, які в mpv і в цьому плеєрі означають різне.
enum KeyScheme {
  standard(
    'Стандартна',
    '↑ / ↓ — гучність, J / L — перемотка на крок, O — відкрити файл',
  ),
  mpv(
    'Як у mpv',
    '↑ / ↓ — перемотка на хвилину, J — субтитри, L — цикл A–B, O — прогрес',
  );

  const KeyScheme(this.title, this.summary);

  final String title;
  final String summary;

  static KeyScheme parse(String? raw) =>
      KeyScheme.values.firstWhere((s) => s.name == raw, orElse: () => KeyScheme.standard);
}

/// У якій схемі діє комбінація
enum KeyScope {
  both,
  standardOnly,
  mpvOnly;

  bool appliesTo(KeyScheme scheme) =>
      this == KeyScope.both ||
      (this == KeyScope.standardOnly && scheme == KeyScheme.standard) ||
      (this == KeyScope.mpvOnly && scheme == KeyScheme.mpv);
}

enum ShortcutGroup {
  playback('Відтворення'),
  seek('Перемотка'),
  speed('Швидкість'),
  audio('Звук'),
  subtitles('Субтитри'),
  picture('Зображення'),
  anime4k('Anime4K'),
  window('Вікно та сервіс');

  const ShortcutGroup(this.title);
  final String title;
}

/// Комбінація: фізична клавіша + модифікатори. Фізичні клавіші дають однакову поведінку
/// незалежно від розкладки (українська / англійська).
class KeyChord {
  const KeyChord(
    this.key,
    this.caps, {
    this.ctrl = false,
    this.shift = false,
    this.alt = false,
    this.scope = KeyScope.both,
    this.hidden = false,
  });

  final PhysicalKeyboardKey key;

  /// Підписи для «кнопок клавіатури» в довідці: ['Ctrl', '1'], ['>'] …
  final List<String> caps;
  final bool ctrl;
  final bool shift;
  final bool alt;
  final KeyScope scope;

  /// Не показувати в довідці (медіаклавіші, дублікати)
  final bool hidden;

  (int, bool, bool, bool) get lookupKey => (key.usbHidUsage, ctrl, shift, alt);
}

class ShortcutDef {
  const ShortcutDef(
    this.id,
    this.group,
    this.label,
    this.chords, {
    this.repeat = false,
  });

  final String id;
  final ShortcutGroup group;
  final String label;
  final List<KeyChord> chords;

  /// Дію можна повторювати утриманням клавіші
  final bool repeat;

  Iterable<KeyChord> chordsFor(KeyScheme scheme) => chords.where((c) => c.scope.appliesTo(scheme));
}

class ShortcutCatalog {
  ShortcutCatalog._();

  static const _std = KeyScope.standardOnly;
  static const _mpv = KeyScope.mpvOnly;

  /// Єдине джерело правди: за цим списком працює обробник клавіш і сторінка довідки.
  /// Комбінації взято зі стандартного input.conf mpv; Anime4K — з офіційного конфігу Anime4K.
  static const List<ShortcutDef> all = [
    // ── Відтворення ──────────────────────────────────────────────
    ShortcutDef('play_pause', ShortcutGroup.playback, 'Пауза / відтворення', [
      KeyChord(PhysicalKeyboardKey.space, ['Space']),
      KeyChord(PhysicalKeyboardKey.keyK, ['K']),
      KeyChord(PhysicalKeyboardKey.keyP, ['P']),
      KeyChord(PhysicalKeyboardKey.mediaPlayPause, ['Play'], hidden: true),
    ]),
    ShortcutDef('frame_step', ShortcutGroup.playback, 'Наступний кадр', [
      KeyChord(PhysicalKeyboardKey.period, ['.']),
    ], repeat: true),
    ShortcutDef('frame_back', ShortcutGroup.playback, 'Попередній кадр', [
      KeyChord(PhysicalKeyboardKey.comma, [',']),
    ], repeat: true),
    ShortcutDef('next_file', ShortcutGroup.playback, 'Наступний файл', [
      KeyChord(PhysicalKeyboardKey.period, ['>'], shift: true),
      KeyChord(PhysicalKeyboardKey.enter, ['Enter']),
      KeyChord(PhysicalKeyboardKey.numpadEnter, ['Enter'], hidden: true),
      KeyChord(PhysicalKeyboardKey.mediaTrackNext, ['Next'], hidden: true),
    ]),
    ShortcutDef('prev_file', ShortcutGroup.playback, 'Попередній файл', [
      KeyChord(PhysicalKeyboardKey.comma, ['<'], shift: true),
      KeyChord(PhysicalKeyboardKey.mediaTrackPrevious, ['Prev'], hidden: true),
    ]),
    ShortcutDef('first_file', ShortcutGroup.playback, 'Перший файл у черзі', [
      KeyChord(PhysicalKeyboardKey.home, ['Shift', 'Home'], shift: true),
    ]),
    ShortcutDef('last_file', ShortcutGroup.playback, 'Останній файл у черзі', [
      KeyChord(PhysicalKeyboardKey.end, ['Shift', 'End'], shift: true),
    ]),
    ShortcutDef('ab_loop', ShortcutGroup.playback, 'Цикл A–B: початок → кінець → скинути', [
      KeyChord(PhysicalKeyboardKey.keyL, ['L'], scope: _mpv),
    ]),
    ShortcutDef('loop_file', ShortcutGroup.playback, 'Нескінченний повтор файлу', [
      KeyChord(PhysicalKeyboardKey.keyL, ['Shift', 'L'], shift: true, scope: _mpv),
    ]),
    ShortcutDef('revert_seek', ShortcutGroup.playback, 'Повернутися до місця до перемотки', [
      KeyChord(PhysicalKeyboardKey.backspace, ['Shift', 'Backspace'], shift: true),
    ]),
    ShortcutDef('mark_seek', ShortcutGroup.playback, 'Позначити місце для повернення', [
      KeyChord(PhysicalKeyboardKey.backspace, ['Ctrl', 'Shift', 'Backspace'], ctrl: true, shift: true),
    ]),
    ShortcutDef('show_progress', ShortcutGroup.playback, 'Показати прогрес відтворення', [
      KeyChord(PhysicalKeyboardKey.keyP, ['Shift', 'P'], shift: true),
      KeyChord(PhysicalKeyboardKey.keyO, ['O'], scope: _mpv),
    ]),
    ShortcutDef('quit_video', ShortcutGroup.playback, 'Закрити відео (на головну)', [
      KeyChord(PhysicalKeyboardKey.keyQ, ['Q']),
      KeyChord(PhysicalKeyboardKey.keyQ, ['Shift', 'Q'], shift: true, hidden: true),
      KeyChord(PhysicalKeyboardKey.keyW, ['Ctrl', 'W'], ctrl: true),
    ]),

    // ── Перемотка ────────────────────────────────────────────────
    ShortcutDef('seek_back_5', ShortcutGroup.seek, 'Назад на 5 секунд', [
      KeyChord(PhysicalKeyboardKey.arrowLeft, ['←']),
      KeyChord(PhysicalKeyboardKey.arrowDown, ['Shift', '↓'], shift: true),
    ], repeat: true),
    ShortcutDef('seek_fwd_5', ShortcutGroup.seek, 'Вперед на 5 секунд', [
      KeyChord(PhysicalKeyboardKey.arrowRight, ['→']),
      KeyChord(PhysicalKeyboardKey.arrowUp, ['Shift', '↑'], shift: true),
    ], repeat: true),
    ShortcutDef('seek_back_1', ShortcutGroup.seek, 'Назад на 1 секунду', [
      KeyChord(PhysicalKeyboardKey.arrowLeft, ['Shift', '←'], shift: true),
    ], repeat: true),
    ShortcutDef('seek_fwd_1', ShortcutGroup.seek, 'Вперед на 1 секунду', [
      KeyChord(PhysicalKeyboardKey.arrowRight, ['Shift', '→'], shift: true),
    ], repeat: true),
    ShortcutDef('seek_step_back', ShortcutGroup.seek, 'Назад на крок з налаштувань', [
      KeyChord(PhysicalKeyboardKey.keyJ, ['J'], scope: _std),
    ], repeat: true),
    ShortcutDef('seek_step_fwd', ShortcutGroup.seek, 'Вперед на крок з налаштувань', [
      KeyChord(PhysicalKeyboardKey.keyL, ['L'], scope: _std),
    ], repeat: true),
    ShortcutDef('seek_back_60', ShortcutGroup.seek, 'Назад на 1 хвилину', [
      KeyChord(PhysicalKeyboardKey.arrowDown, ['↓'], scope: _mpv),
    ], repeat: true),
    ShortcutDef('seek_fwd_60', ShortcutGroup.seek, 'Вперед на 1 хвилину', [
      KeyChord(PhysicalKeyboardKey.arrowUp, ['↑'], scope: _mpv),
    ], repeat: true),
    ShortcutDef('seek_back_600', ShortcutGroup.seek, 'Назад на 10 хвилин', [
      KeyChord(PhysicalKeyboardKey.pageDown, ['Shift', 'PgDn'], shift: true),
    ]),
    ShortcutDef('seek_fwd_600', ShortcutGroup.seek, 'Вперед на 10 хвилин', [
      KeyChord(PhysicalKeyboardKey.pageUp, ['Shift', 'PgUp'], shift: true),
    ]),
    ShortcutDef('seek_start', ShortcutGroup.seek, 'На початок', [
      KeyChord(PhysicalKeyboardKey.home, ['Home']),
    ]),
    ShortcutDef('chapter_prev', ShortcutGroup.seek, 'Попередній розділ', [
      KeyChord(PhysicalKeyboardKey.pageDown, ['PgDn']),
    ]),
    ShortcutDef('chapter_next', ShortcutGroup.seek, 'Наступний розділ', [
      KeyChord(PhysicalKeyboardKey.pageUp, ['PgUp']),
    ]),
    ShortcutDef('sub_seek_prev', ShortcutGroup.seek, 'До попереднього субтитру', [
      KeyChord(PhysicalKeyboardKey.arrowLeft, ['Ctrl', '←'], ctrl: true),
    ]),
    ShortcutDef('sub_seek_next', ShortcutGroup.seek, 'До наступного субтитру', [
      KeyChord(PhysicalKeyboardKey.arrowRight, ['Ctrl', '→'], ctrl: true),
    ]),
    ShortcutDef('sub_step_prev', ShortcutGroup.seek, 'Підігнати субтитри під попередню репліку', [
      KeyChord(PhysicalKeyboardKey.arrowLeft, ['Ctrl', 'Shift', '←'], ctrl: true, shift: true),
    ]),
    ShortcutDef('sub_step_next', ShortcutGroup.seek, 'Підігнати субтитри під наступну репліку', [
      KeyChord(PhysicalKeyboardKey.arrowRight, ['Ctrl', 'Shift', '→'], ctrl: true, shift: true),
    ]),

    // ── Швидкість ────────────────────────────────────────────────
    ShortcutDef('speed_down', ShortcutGroup.speed, 'Повільніше (÷ 1,1)', [
      KeyChord(PhysicalKeyboardKey.bracketLeft, ['[']),
    ], repeat: true),
    ShortcutDef('speed_up', ShortcutGroup.speed, 'Швидше (× 1,1)', [
      KeyChord(PhysicalKeyboardKey.bracketRight, [']']),
    ], repeat: true),
    ShortcutDef('speed_half', ShortcutGroup.speed, 'Удвічі повільніше', [
      KeyChord(PhysicalKeyboardKey.bracketLeft, ['{'], shift: true),
    ]),
    ShortcutDef('speed_double', ShortcutGroup.speed, 'Удвічі швидше', [
      KeyChord(PhysicalKeyboardKey.bracketRight, ['}'], shift: true),
    ]),
    ShortcutDef('speed_reset', ShortcutGroup.speed, 'Звичайна швидкість', [
      KeyChord(PhysicalKeyboardKey.backspace, ['Backspace']),
    ]),

    // ── Звук ─────────────────────────────────────────────────────
    ShortcutDef('volume_up_5', ShortcutGroup.audio, 'Гучніше на 5%', [
      KeyChord(PhysicalKeyboardKey.arrowUp, ['↑'], scope: _std),
    ], repeat: true),
    ShortcutDef('volume_down_5', ShortcutGroup.audio, 'Тихіше на 5%', [
      KeyChord(PhysicalKeyboardKey.arrowDown, ['↓'], scope: _std),
    ], repeat: true),
    ShortcutDef('volume_up_2', ShortcutGroup.audio, 'Гучніше на 2%', [
      KeyChord(PhysicalKeyboardKey.digit0, ['0']),
      KeyChord(PhysicalKeyboardKey.digit8, ['*'], shift: true),
      KeyChord(PhysicalKeyboardKey.numpadMultiply, ['*'], hidden: true),
    ], repeat: true),
    ShortcutDef('volume_down_2', ShortcutGroup.audio, 'Тихіше на 2%', [
      KeyChord(PhysicalKeyboardKey.digit9, ['9']),
      KeyChord(PhysicalKeyboardKey.slash, ['/']),
      KeyChord(PhysicalKeyboardKey.numpadDivide, ['/'], hidden: true),
    ], repeat: true),
    ShortcutDef('mute', ShortcutGroup.audio, 'Вимкнути / увімкнути звук', [
      KeyChord(PhysicalKeyboardKey.keyM, ['M']),
    ]),
    ShortcutDef('audio_delay_down', ShortcutGroup.audio, 'Звук раніше на 0,1 с', [
      KeyChord(PhysicalKeyboardKey.minus, ['Ctrl', '−'], ctrl: true),
      KeyChord(PhysicalKeyboardKey.numpadSubtract, ['Ctrl', '−'], ctrl: true, hidden: true),
    ], repeat: true),
    ShortcutDef('audio_delay_up', ShortcutGroup.audio, 'Звук пізніше на 0,1 с', [
      KeyChord(PhysicalKeyboardKey.equal, ['Ctrl', '+'], ctrl: true),
      KeyChord(PhysicalKeyboardKey.equal, ['Ctrl', '+'], ctrl: true, shift: true, hidden: true),
      KeyChord(PhysicalKeyboardKey.numpadAdd, ['Ctrl', '+'], ctrl: true, hidden: true),
    ], repeat: true),
    ShortcutDef('audio_cycle', ShortcutGroup.audio, 'Наступна аудіодоріжка', [
      KeyChord(PhysicalKeyboardKey.digit3, ['#'], shift: true),
    ]),

    // ── Субтитри ─────────────────────────────────────────────────
    ShortcutDef('sub_toggle', ShortcutGroup.subtitles, 'Показати / сховати субтитри', [
      KeyChord(PhysicalKeyboardKey.keyV, ['V']),
    ]),
    ShortcutDef('sub_cycle', ShortcutGroup.subtitles, 'Наступна доріжка субтитрів', [
      KeyChord(PhysicalKeyboardKey.keyJ, ['J'], scope: _mpv),
    ]),
    ShortcutDef('sub_cycle_prev', ShortcutGroup.subtitles, 'Попередня доріжка субтитрів', [
      KeyChord(PhysicalKeyboardKey.keyJ, ['Shift', 'J'], shift: true, scope: _mpv),
    ]),
    ShortcutDef('sub_delay_down', ShortcutGroup.subtitles, 'Субтитри раніше на 0,1 с', [
      KeyChord(PhysicalKeyboardKey.keyZ, ['Z']),
    ], repeat: true),
    ShortcutDef('sub_delay_up', ShortcutGroup.subtitles, 'Субтитри пізніше на 0,1 с', [
      KeyChord(PhysicalKeyboardKey.keyX, ['X']),
      KeyChord(PhysicalKeyboardKey.keyZ, ['Shift', 'Z'], shift: true),
    ], repeat: true),
    ShortcutDef('sub_pos_up', ShortcutGroup.subtitles, 'Субтитри вище', [
      KeyChord(PhysicalKeyboardKey.keyR, ['R']),
    ], repeat: true),
    ShortcutDef('sub_pos_down', ShortcutGroup.subtitles, 'Субтитри нижче', [
      KeyChord(PhysicalKeyboardKey.keyT, ['T']),
      KeyChord(PhysicalKeyboardKey.keyR, ['Shift', 'R'], shift: true),
    ], repeat: true),
    ShortcutDef('sub_scale_down', ShortcutGroup.subtitles, 'Менший розмір субтитрів', [
      KeyChord(PhysicalKeyboardKey.keyF, ['Shift', 'F'], shift: true),
    ], repeat: true),
    ShortcutDef('sub_scale_up', ShortcutGroup.subtitles, 'Більший розмір субтитрів', [
      KeyChord(PhysicalKeyboardKey.keyG, ['Shift', 'G'], shift: true),
    ], repeat: true),

    // ── Зображення ───────────────────────────────────────────────
    ShortcutDef('contrast_down', ShortcutGroup.picture, 'Контраст −', [
      KeyChord(PhysicalKeyboardKey.digit1, ['1']),
    ], repeat: true),
    ShortcutDef('contrast_up', ShortcutGroup.picture, 'Контраст +', [
      KeyChord(PhysicalKeyboardKey.digit2, ['2']),
    ], repeat: true),
    ShortcutDef('brightness_down', ShortcutGroup.picture, 'Яскравість −', [
      KeyChord(PhysicalKeyboardKey.digit3, ['3']),
    ], repeat: true),
    ShortcutDef('brightness_up', ShortcutGroup.picture, 'Яскравість +', [
      KeyChord(PhysicalKeyboardKey.digit4, ['4']),
    ], repeat: true),
    ShortcutDef('gamma_down', ShortcutGroup.picture, 'Гамма −', [
      KeyChord(PhysicalKeyboardKey.digit5, ['5']),
    ], repeat: true),
    ShortcutDef('gamma_up', ShortcutGroup.picture, 'Гамма +', [
      KeyChord(PhysicalKeyboardKey.digit6, ['6']),
    ], repeat: true),
    ShortcutDef('saturation_down', ShortcutGroup.picture, 'Насиченість −', [
      KeyChord(PhysicalKeyboardKey.digit7, ['7']),
    ], repeat: true),
    ShortcutDef('saturation_up', ShortcutGroup.picture, 'Насиченість +', [
      KeyChord(PhysicalKeyboardKey.digit8, ['8']),
    ], repeat: true),
    ShortcutDef('deband', ShortcutGroup.picture, 'Деббандинг (прибирає смуги в градієнтах)', [
      KeyChord(PhysicalKeyboardKey.keyB, ['B']),
    ]),
    ShortcutDef('deinterlace', ShortcutGroup.picture, 'Деінтерлейс (цикл)', [
      KeyChord(PhysicalKeyboardKey.keyD, ['D']),
    ]),
    ShortcutDef('aspect', ShortcutGroup.picture, 'Співвідношення сторін (цикл)', [
      KeyChord(PhysicalKeyboardKey.keyA, ['Shift', 'A'], shift: true),
    ]),
    ShortcutDef('panscan_down', ShortcutGroup.picture, 'Менше обрізання по краях', [
      KeyChord(PhysicalKeyboardKey.keyW, ['W']),
    ], repeat: true),
    ShortcutDef('panscan_up', ShortcutGroup.picture, 'Більше обрізання (без чорних смуг)', [
      KeyChord(PhysicalKeyboardKey.keyE, ['E']),
      KeyChord(PhysicalKeyboardKey.keyW, ['Shift', 'W'], shift: true),
    ], repeat: true),
    ShortcutDef('zoom_in', ShortcutGroup.picture, 'Збільшити', [
      KeyChord(PhysicalKeyboardKey.equal, ['Alt', '+'], alt: true),
      KeyChord(PhysicalKeyboardKey.equal, ['Alt', '+'], alt: true, shift: true, hidden: true),
      KeyChord(PhysicalKeyboardKey.numpadAdd, ['Alt', '+'], alt: true, hidden: true),
    ], repeat: true),
    ShortcutDef('zoom_out', ShortcutGroup.picture, 'Зменшити', [
      KeyChord(PhysicalKeyboardKey.minus, ['Alt', '−'], alt: true),
      KeyChord(PhysicalKeyboardKey.numpadSubtract, ['Alt', '−'], alt: true, hidden: true),
    ], repeat: true),
    ShortcutDef('pan_right', ShortcutGroup.picture, 'Посунути відео вправо', [
      KeyChord(PhysicalKeyboardKey.arrowLeft, ['Alt', '←'], alt: true),
    ], repeat: true),
    ShortcutDef('pan_left', ShortcutGroup.picture, 'Посунути відео вліво', [
      KeyChord(PhysicalKeyboardKey.arrowRight, ['Alt', '→'], alt: true),
    ], repeat: true),
    ShortcutDef('pan_down', ShortcutGroup.picture, 'Посунути відео вниз', [
      KeyChord(PhysicalKeyboardKey.arrowUp, ['Alt', '↑'], alt: true),
    ], repeat: true),
    ShortcutDef('pan_up', ShortcutGroup.picture, 'Посунути відео вгору', [
      KeyChord(PhysicalKeyboardKey.arrowDown, ['Alt', '↓'], alt: true),
    ], repeat: true),
    ShortcutDef('zoom_reset', ShortcutGroup.picture, 'Скинути масштаб і зсув', [
      KeyChord(PhysicalKeyboardKey.backspace, ['Alt', 'Backspace'], alt: true),
    ]),

    // ── Anime4K ──────────────────────────────────────────────────
    ShortcutDef('a4k_mode_1', ShortcutGroup.anime4k, 'Режим A', [
      KeyChord(PhysicalKeyboardKey.digit1, ['Ctrl', '1'], ctrl: true),
    ]),
    ShortcutDef('a4k_mode_2', ShortcutGroup.anime4k, 'Режим B', [
      KeyChord(PhysicalKeyboardKey.digit2, ['Ctrl', '2'], ctrl: true),
    ]),
    ShortcutDef('a4k_mode_3', ShortcutGroup.anime4k, 'Режим C', [
      KeyChord(PhysicalKeyboardKey.digit3, ['Ctrl', '3'], ctrl: true),
    ]),
    ShortcutDef('a4k_mode_4', ShortcutGroup.anime4k, 'Режим A+A', [
      KeyChord(PhysicalKeyboardKey.digit4, ['Ctrl', '4'], ctrl: true),
    ]),
    ShortcutDef('a4k_mode_5', ShortcutGroup.anime4k, 'Режим B+B', [
      KeyChord(PhysicalKeyboardKey.digit5, ['Ctrl', '5'], ctrl: true),
    ]),
    ShortcutDef('a4k_mode_6', ShortcutGroup.anime4k, 'Режим C+A', [
      KeyChord(PhysicalKeyboardKey.digit6, ['Ctrl', '6'], ctrl: true),
    ]),
    ShortcutDef('a4k_off', ShortcutGroup.anime4k, 'Вимкнути Anime4K (скинути шейдери)', [
      KeyChord(PhysicalKeyboardKey.digit0, ['Ctrl', '0'], ctrl: true),
    ]),
    ShortcutDef('a4k_toggle', ShortcutGroup.anime4k, 'Увімкнути / вимкнути (останній режим)', [
      KeyChord(PhysicalKeyboardKey.digit8, ['Ctrl', '8'], ctrl: true),
    ]),
    ShortcutDef('a4k_quality', ShortcutGroup.anime4k, 'Якість: Fast ↔ HQ', [
      KeyChord(PhysicalKeyboardKey.digit9, ['Ctrl', '9'], ctrl: true),
    ]),

    // ── Вікно та сервіс ──────────────────────────────────────────
    ShortcutDef('fullscreen', ShortcutGroup.window, 'Повноекранний режим', [
      KeyChord(PhysicalKeyboardKey.keyF, ['F']),
      KeyChord(PhysicalKeyboardKey.enter, ['Alt', 'Enter'], alt: true, hidden: true),
    ]),
    ShortcutDef('escape', ShortcutGroup.window, 'Закрити меню / панель / вийти з повного екрана', [
      KeyChord(PhysicalKeyboardKey.escape, ['Esc']),
    ]),
    ShortcutDef('ontop', ShortcutGroup.window, 'Поверх усіх вікон', [
      KeyChord(PhysicalKeyboardKey.keyT, ['Shift', 'T'], shift: true),
    ]),
    ShortcutDef('stats', ShortcutGroup.window, 'Статистика відтворення', [
      KeyChord(PhysicalKeyboardKey.keyI, ['I']),
      KeyChord(PhysicalKeyboardKey.keyI, ['Shift', 'I'], shift: true, hidden: true),
    ]),
    ShortcutDef('open_file', ShortcutGroup.window, 'Відкрити файл', [
      KeyChord(PhysicalKeyboardKey.keyO, ['Ctrl', 'O'], ctrl: true),
      KeyChord(PhysicalKeyboardKey.keyO, ['O'], scope: _std),
    ]),
    ShortcutDef('queue_panel', ShortcutGroup.window, 'Черга відтворення', [
      KeyChord(PhysicalKeyboardKey.f8, ['F8']),
    ]),
    ShortcutDef('info_panel', ShortcutGroup.window, 'Інформація про відео та доріжки', [
      KeyChord(PhysicalKeyboardKey.f9, ['F9']),
    ]),
    ShortcutDef('screenshot', ShortcutGroup.window, 'Знімок екрана (із субтитрами)', [
      KeyChord(PhysicalKeyboardKey.keyS, ['S']),
    ]),
    ShortcutDef('screenshot_clean', ShortcutGroup.window, 'Знімок екрана (без субтитрів)', [
      KeyChord(PhysicalKeyboardKey.keyS, ['Shift', 'S'], shift: true),
    ]),
    ShortcutDef('help', ShortcutGroup.window, 'Довідка з гарячих клавіш', [
      KeyChord(PhysicalKeyboardKey.slash, ['?'], shift: true),
      KeyChord(PhysicalKeyboardKey.f1, ['F1']),
    ]),
  ];

  static final Map<String, ShortcutDef> byId = {for (final d in all) d.id: d};

  static final Map<KeyScheme, Map<(int, bool, bool, bool), ShortcutDef>> _lookup = {
    for (final scheme in KeyScheme.values)
      scheme: {
        for (final def in all)
          for (final chord in def.chordsFor(scheme)) chord.lookupKey: def,
      },
  };

  /// Яка дія прив'язана до комбінації у схемі [scheme]
  static ShortcutDef? find(KeyScheme scheme, PhysicalKeyboardKey key,
      {required bool ctrl, required bool shift, required bool alt}) {
    return _lookup[scheme]![(key.usbHidUsage, ctrl, shift, alt)];
  }

  /// Комбінації, які діють у схемі, згруповані для довідки
  static Map<ShortcutGroup, List<ShortcutDef>> grouped(KeyScheme scheme) {
    final out = <ShortcutGroup, List<ShortcutDef>>{};
    for (final def in all) {
      if (def.chordsFor(scheme).where((c) => !c.hidden).isEmpty) continue;
      out.putIfAbsent(def.group, () => []).add(def);
    }
    return out;
  }
}
