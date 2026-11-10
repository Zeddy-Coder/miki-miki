import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:media_kit/media_kit.dart';

import '../utils/formatters.dart';
import '../widgets/side_panel.dart';
import 'anime4k_service.dart';
import 'app_log.dart';
import 'player_state_controller.dart';
import 'shortcut_catalog.dart';
import 'storage_service.dart';

/// Виконує дії гарячих клавіш. Ідентифікатори збігаються з [ShortcutCatalog].
/// Команди mpv ідуть напряму в рушій, а результат показується екранним сповіщенням.
class PlayerActions {
  PlayerActions(this.c);

  final PlayerStateController c;

  Player get _p => c.player;

  late final Map<String, FutureOr<void> Function()> table = _buildTable();

  bool has(String id) => table.containsKey(id);

  /// Виконує дію. Повертає `false`, якщо клавіша нічого не зробила (щоб віддати її далі).
  Future<bool> run(String id) async {
    if (id == 'escape') return escape();
    final action = table[id];
    if (action == null) return false;
    AppLog.d('клавіші', 'дія $id');
    await action();
    return true;
  }

  // ───────────────────────── допоміжні ─────────────────────────

  static String _num(double v) => v == v.truncateToDouble() ? v.toInt().toString() : v.toString();

  static String _signedMs(String rawSeconds) {
    final ms = ((double.tryParse(rawSeconds) ?? 0) * 1000).round();
    if (ms > 0) return '+$ms мс';
    if (ms < 0) return '−${-ms} мс';
    return '0 мс';
  }

  static String _durationLabel(int seconds) {
    final s = seconds.abs();
    if (s < 60) return '$s с';
    final m = s ~/ 60, rest = s % 60;
    return rest == 0 ? '$m хв' : '$m хв $rest с';
  }

  static String _clock(double seconds) => AppFormatters.formatTime(Duration(milliseconds: (seconds * 1000).round()));

  Duration? _lastSeekTarget;
  DateTime? _lastSeekAt;

  Future<void> _seekBy(int seconds) async {
    final dur = _p.state.duration;
    // Під час швидких натискань позиція плеєра ще не оновилась — рахуємо від попередньої цілі
    final now = DateTime.now();
    final recent = _lastSeekAt != null &&
        _lastSeekTarget != null &&
        now.difference(_lastSeekAt!) < const Duration(milliseconds: 600);
    var target = (recent ? _lastSeekTarget! : _p.state.position) + Duration(seconds: seconds);
    if (target < Duration.zero) target = Duration.zero;
    if (dur > Duration.zero && target > dur) target = dur;
    _lastSeekTarget = target;
    _lastSeekAt = now;
    _p.seek(target);
    c.showOsd(
      '${seconds >= 0 ? '+' : '−'}${_durationLabel(seconds)}',
      icon: seconds >= 0 ? Symbols.fast_forward_rounded : Symbols.fast_rewind_rounded,
      detail: dur > Duration.zero
          ? '${AppFormatters.formatTime(target)} / ${AppFormatters.formatTime(dur)}'
          : AppFormatters.formatTime(target),
      progress: dur > Duration.zero ? target.inMilliseconds / dur.inMilliseconds : null,
      onlyWhenControlsHidden: true,
    );
  }

  /// `add <prop> <delta>` і сповіщення зі значенням, яке повернув mpv
  Future<void> _addProp(
    String prop,
    double delta, {
    required String title,
    required IconData icon,
    String Function(String raw)? format,
  }) async {
    await c.mpv(['add', prop, _num(delta)]);
    final raw = await c.mpvGet(prop);
    c.showOsd(title, icon: icon, detail: raw.isEmpty ? null : (format != null ? format(raw) : raw));
  }

  Future<void> _cycleProp(
    String prop, {
    required String title,
    required IconData icon,
    String Function(String raw)? format,
  }) async {
    await c.mpv(['cycle', prop]);
    final raw = await c.mpvGet(prop);
    c.showOsd(title, icon: icon, detail: raw.isEmpty ? null : (format != null ? format(raw) : raw));
  }

  static String _onOff(String raw) => (raw == 'yes' || raw == 'inf' || raw == 'true') ? 'увімкнено' : 'вимкнено';

  void _setSpeed(double value) {
    final v = double.parse(value.clamp(0.1, 8.0).toStringAsFixed(2));
    _p.setRate(v);
    c.showOsd('Швидкість', icon: Symbols.speed_rounded, detail: AppFormatters.formatSpeed(v));
  }

  void _picture(String prop, String title, IconData icon, double delta) =>
      unawaited(_addProp(prop, delta, title: title, icon: icon, format: (raw) {
        final v = int.tryParse(raw.split('.').first) ?? 0;
        return v > 0 ? '+$v' : '$v';
      }));

  void _volume(double delta) => c.setVolumeDelta(delta);

  // ───────────────────────── субтитри / аудіо ─────────────────────────

  void _cycleSubtitle(int dir) {
    final tracks = c.cachedSubtitleTracks;
    if (tracks.isEmpty) {
      c.showOsd('Субтитрів немає', icon: Symbols.subtitles_off_rounded);
      return;
    }
    final cur = _p.state.track.subtitle;
    // 0 — «вимкнено», далі доріжки
    int index;
    if (cur.id == 'no') {
      index = 0;
    } else {
      final found = tracks.indexWhere((t) => t.track.id == cur.id);
      index = found >= 0 ? found + 1 : 1; // 'auto' — перша доріжка
    }
    final count = tracks.length + 1;
    index = (index + dir) % count;
    if (index < 0) index += count;
    if (index == 0) {
      c.setSubtitleTrack(SubtitleTrack.no(), closeMenu: false);
      c.showOsd('Субтитри', icon: Symbols.subtitles_off_rounded, detail: 'Вимкнено');
    } else {
      final t = tracks[index - 1];
      c.setSubtitleTrack(t.track, closeMenu: false);
      c.showOsd('Субтитри', icon: Symbols.subtitles_rounded, detail: t.formattedTitle);
    }
  }

  void _cycleAudio() {
    final tracks = c.cachedAudioTracks;
    if (tracks.isEmpty) {
      c.showOsd('Аудіодоріжок немає', icon: Symbols.music_off_rounded);
      return;
    }
    final cur = _p.state.track.audio;
    final found = tracks.indexWhere((t) => t.track.id == cur.id);
    final next = tracks[((found >= 0 ? found : 0) + 1) % tracks.length];
    c.setAudioTrack(next.track, closeMenu: false);
    c.showOsd('Аудіо', icon: Symbols.music_note_rounded, detail: next.formattedTitle);
  }

  // ───────────────────────── розділи, черга ─────────────────────────

  void _chapter(int dir) {
    final chapters = c.currentChapters;
    if (chapters.isEmpty) {
      c.showOsd('Розділів немає', icon: Symbols.bookmark_rounded);
      return;
    }
    final pos = _p.state.position;
    int cur = 0;
    for (int i = 0; i < chapters.length; i++) {
      if (pos >= chapters[i].startTime) cur = i;
    }
    int target;
    if (dir > 0) {
      if (cur + 1 >= chapters.length) {
        c.showOsd('Це останній розділ', icon: Symbols.bookmark_rounded);
        return;
      }
      target = cur + 1;
    } else {
      // Як у mpv: якщо відтворення пішло далі за кілька секунд — спершу на початок поточного розділу
      target = (pos - chapters[cur].startTime > const Duration(seconds: 5) || cur == 0) ? cur : cur - 1;
    }
    _p.seek(chapters[target].startTime);
    c.showOsd(
      'Розділ ${target + 1} з ${chapters.length}',
      icon: Symbols.bookmark_rounded,
      detail: AppFormatters.translateChapterTitle(chapters[target].title),
    );
  }

  void _file(int dir) {
    final items = c.playlistItems;
    if (items.length < 2) {
      c.showOsd('У черзі лише один файл', icon: Symbols.queue_music_rounded);
      return;
    }
    final next = c.currentPlaylistIndex + dir;
    if (next < 0 || next >= items.length) {
      c.showOsd(dir > 0 ? 'Це останній файл' : 'Це перший файл', icon: Symbols.queue_music_rounded);
      return;
    }
    c.selectEpisode(next);
    c.showOsd(
      dir > 0 ? 'Наступний файл' : 'Попередній файл',
      icon: dir > 0 ? Symbols.skip_next_rounded : Symbols.skip_previous_rounded,
      detail: (items[next].extras?['title'] ?? '').toString(),
    );
  }

  void _fileAt(bool last) {
    final items = c.playlistItems;
    if (items.length < 2) {
      c.showOsd('У черзі лише один файл', icon: Symbols.queue_music_rounded);
      return;
    }
    final idx = last ? items.length - 1 : 0;
    c.selectEpisode(idx);
    c.showOsd(last ? 'Останній файл' : 'Перший файл',
        icon: Symbols.queue_music_rounded, detail: (items[idx].extras?['title'] ?? '').toString());
  }

  // ───────────────────────── цикли ─────────────────────────

  Future<void> _abLoop() async {
    await c.mpv(['ab-loop']);
    final a = await c.mpvGet('ab-loop-a');
    final b = await c.mpvGet('ab-loop-b');
    final hasA = a.isNotEmpty && a != 'no';
    final hasB = b.isNotEmpty && b != 'no';
    if (!hasA) {
      c.showOsd('Цикл A–B вимкнено', icon: Symbols.repeat_rounded);
    } else if (!hasB) {
      c.showOsd('Початок циклу (A)', icon: Symbols.repeat_rounded, detail: _clock(double.tryParse(a) ?? 0));
    } else {
      c.showOsd('Цикл A–B',
          icon: Symbols.repeat_rounded,
          detail: '${_clock(double.tryParse(a) ?? 0)} – ${_clock(double.tryParse(b) ?? 0)}');
    }
  }

  void _loopFile() {
    final on = _p.state.playlistMode == PlaylistMode.single;
    _p.setPlaylistMode(on ? PlaylistMode.none : PlaylistMode.single);
    c.showOsd('Повтор файлу',
        icon: on ? Symbols.repeat_rounded : Symbols.repeat_one_rounded, detail: on ? 'вимкнено' : 'увімкнено');
  }

  static const List<String> _aspects = ['16:9', '4:3', '2.35:1', 'no'];
  int _aspectIndex = _aspects.length - 1;

  Future<void> _cycleAspect() async {
    _aspectIndex = (_aspectIndex + 1) % _aspects.length;
    final value = _aspects[_aspectIndex];
    await c.mpv(['set', 'video-aspect-override', value == 'no' ? '-1' : value]);
    c.showOsd('Співвідношення сторін',
        icon: Symbols.aspect_ratio_rounded, detail: value == 'no' ? 'Початкове' : value);
  }

  void _showProgress() {
    final pos = _p.state.position, dur = _p.state.duration;
    final pct = dur > Duration.zero ? (pos.inMilliseconds * 100 / dur.inMilliseconds).round() : 0;
    c.showOsd(
      dur > Duration.zero
          ? '${AppFormatters.formatTime(pos)} / ${AppFormatters.formatTime(dur)}'
          : AppFormatters.formatTime(pos),
      icon: Symbols.schedule_rounded,
      detail: dur > Duration.zero ? '$pct%' : null,
      progress: dur > Duration.zero ? pos.inMilliseconds / dur.inMilliseconds : null,
    );
  }

  Future<void> _resetZoom() async {
    for (final prop in const ['video-zoom', 'panscan', 'video-pan-x', 'video-pan-y', 'video-align-x', 'video-align-y']) {
      await c.mpv(['set', prop, '0']);
    }
    c.showOsd('Масштаб і зсув скинуто', icon: Symbols.zoom_out_map_rounded);
  }

  /// Esc: закриває статистику, меню, бічну панель, а потім виходить із повного екрана.
  /// Повертає `false`, якщо закривати нічого — тоді клавіша йде далі.
  bool escape() {
    if (c.showStatsOverlay) {
      c.closeStatsOverlay();
      return true;
    }
    if (c.activeDrawer != null) {
      c.closeDrawers();
      return true;
    }
    if (c.activeSidePanel != null) {
      c.closeSidePanel();
      return true;
    }
    if (c.isFullscreen) {
      c.toggleFullscreen();
      return true;
    }
    return false;
  }

  // ───────────────────────── таблиця дій ─────────────────────────

  Map<String, FutureOr<void> Function()> _buildTable() {
    return {
      // Відтворення
      'play_pause': () => _p.playOrPause(),
      'frame_step': () => c.mpv(['frame-step']),
      'frame_back': () => c.mpv(['frame-back-step']),
      'next_file': () => _file(1),
      'prev_file': () => _file(-1),
      'first_file': () => _fileAt(false),
      'last_file': () => _fileAt(true),
      'ab_loop': _abLoop,
      'loop_file': _loopFile,
      'revert_seek': () async {
        await c.mpv(['revert-seek']);
        c.showOsd('Повернення до попередньої позиції', icon: Symbols.undo_rounded);
      },
      'mark_seek': () async {
        await c.mpv(['revert-seek', 'mark']);
        c.showOsd('Позицію позначено', icon: Symbols.bookmark_add_rounded, detail: AppFormatters.formatTime(_p.state.position));
      },
      'show_progress': _showProgress,
      'quit_video': () => c.returnToHome(),

      // Перемотка
      'seek_back_5': () => _seekBy(-5),
      'seek_fwd_5': () => _seekBy(5),
      'seek_back_1': () => _seekBy(-1),
      'seek_fwd_1': () => _seekBy(1),
      'seek_step_back': () => _seekBy(-StorageService.getSeekStep()),
      'seek_step_fwd': () => _seekBy(StorageService.getSeekStep()),
      'seek_back_60': () => _seekBy(-60),
      'seek_fwd_60': () => _seekBy(60),
      'seek_back_600': () => _seekBy(-600),
      'seek_fwd_600': () => _seekBy(600),
      'seek_start': () {
        _p.seek(Duration.zero);
        c.showOsd('На початок', icon: Symbols.first_page_rounded, onlyWhenControlsHidden: true);
      },
      'chapter_prev': () => _chapter(-1),
      'chapter_next': () => _chapter(1),
      'sub_seek_prev': () => c.mpv(['sub-seek', '-1']),
      'sub_seek_next': () => c.mpv(['sub-seek', '1']),
      'sub_step_prev': () async {
        await c.mpv(['sub-step', '-1']);
        c.showOsd('Затримка субтитрів', icon: Symbols.sync_rounded, detail: _signedMs(await c.mpvGet('sub-delay')));
      },
      'sub_step_next': () async {
        await c.mpv(['sub-step', '1']);
        c.showOsd('Затримка субтитрів', icon: Symbols.sync_rounded, detail: _signedMs(await c.mpvGet('sub-delay')));
      },

      // Швидкість
      'speed_down': () => _setSpeed(_p.state.rate / 1.1),
      'speed_up': () => _setSpeed(_p.state.rate * 1.1),
      'speed_half': () => _setSpeed(_p.state.rate * 0.5),
      'speed_double': () => _setSpeed(_p.state.rate * 2.0),
      'speed_reset': () => _setSpeed(1.0),

      // Звук
      'volume_up_5': () => _volume(5),
      'volume_down_5': () => _volume(-5),
      'volume_up_2': () => _volume(2),
      'volume_down_2': () => _volume(-2),
      'mute': () => c.toggleMute(),
      'audio_delay_down': () =>
          _addProp('audio-delay', -0.1, title: 'Затримка звуку', icon: Symbols.sync_rounded, format: _signedMs),
      'audio_delay_up': () =>
          _addProp('audio-delay', 0.1, title: 'Затримка звуку', icon: Symbols.sync_rounded, format: _signedMs),
      'audio_cycle': _cycleAudio,

      // Субтитри
      'sub_toggle': () => _cycleProp('sub-visibility',
          title: 'Субтитри', icon: Symbols.subtitles_rounded, format: (raw) => raw == 'yes' ? 'показано' : 'сховано'),
      'sub_cycle': () => _cycleSubtitle(1),
      'sub_cycle_prev': () => _cycleSubtitle(-1),
      'sub_delay_down': () =>
          _addProp('sub-delay', -0.1, title: 'Затримка субтитрів', icon: Symbols.sync_rounded, format: _signedMs),
      'sub_delay_up': () =>
          _addProp('sub-delay', 0.1, title: 'Затримка субтитрів', icon: Symbols.sync_rounded, format: _signedMs),
      'sub_pos_up': () => _addProp('sub-pos', -1,
          title: 'Позиція субтитрів', icon: Symbols.vertical_align_top_rounded, format: (raw) => '${double.tryParse(raw)?.round() ?? raw}%'),
      'sub_pos_down': () => _addProp('sub-pos', 1,
          title: 'Позиція субтитрів', icon: Symbols.vertical_align_bottom_rounded, format: (raw) => '${double.tryParse(raw)?.round() ?? raw}%'),
      'sub_scale_down': () => _addProp('sub-scale', -0.1,
          title: 'Розмір субтитрів', icon: Symbols.format_size_rounded, format: (raw) => '${((double.tryParse(raw) ?? 1) * 100).round()}%'),
      'sub_scale_up': () => _addProp('sub-scale', 0.1,
          title: 'Розмір субтитрів', icon: Symbols.format_size_rounded, format: (raw) => '${((double.tryParse(raw) ?? 1) * 100).round()}%'),

      // Зображення
      'contrast_down': () => _picture('contrast', 'Контраст', Symbols.contrast_rounded, -1),
      'contrast_up': () => _picture('contrast', 'Контраст', Symbols.contrast_rounded, 1),
      'brightness_down': () => _picture('brightness', 'Яскравість', Symbols.light_mode_rounded, -1),
      'brightness_up': () => _picture('brightness', 'Яскравість', Symbols.light_mode_rounded, 1),
      'gamma_down': () => _picture('gamma', 'Гамма', Symbols.tonality_rounded, -1),
      'gamma_up': () => _picture('gamma', 'Гамма', Symbols.tonality_rounded, 1),
      'saturation_down': () => _picture('saturation', 'Насиченість', Symbols.palette_rounded, -1),
      'saturation_up': () => _picture('saturation', 'Насиченість', Symbols.palette_rounded, 1),
      'deband': () => _cycleProp('deband', title: 'Деббандинг', icon: Symbols.grain_rounded, format: _onOff),
      'deinterlace': () => _cycleProp('deinterlace', title: 'Деінтерлейс', icon: Symbols.view_stream_rounded, format: _onOff),
      'aspect': _cycleAspect,
      'panscan_down': () => _addProp('panscan', -0.1,
          title: 'Обрізання по краях', icon: Symbols.crop_rounded, format: (raw) => '${((double.tryParse(raw) ?? 0) * 100).round()}%'),
      'panscan_up': () => _addProp('panscan', 0.1,
          title: 'Обрізання по краях', icon: Symbols.crop_rounded, format: (raw) => '${((double.tryParse(raw) ?? 0) * 100).round()}%'),
      'zoom_in': () => _addProp('video-zoom', 0.1, title: 'Масштаб', icon: Symbols.zoom_in_rounded, format: _zoomLabel),
      'zoom_out': () => _addProp('video-zoom', -0.1, title: 'Масштаб', icon: Symbols.zoom_out_rounded, format: _zoomLabel),
      'pan_right': () => _addProp('video-pan-x', 0.1, title: 'Зсув по горизонталі', icon: Symbols.open_with_rounded, format: _panLabel),
      'pan_left': () => _addProp('video-pan-x', -0.1, title: 'Зсув по горизонталі', icon: Symbols.open_with_rounded, format: _panLabel),
      'pan_down': () => _addProp('video-pan-y', 0.1, title: 'Зсув по вертикалі', icon: Symbols.open_with_rounded, format: _panLabel),
      'pan_up': () => _addProp('video-pan-y', -0.1, title: 'Зсув по вертикалі', icon: Symbols.open_with_rounded, format: _panLabel),
      'zoom_reset': _resetZoom,

      // Anime4K
      for (final mode in Anime4kMode.values) mode.shortcutId: () => c.anime4k.setMode(mode),
      'a4k_off': () => c.anime4k.disable(),
      'a4k_toggle': () => c.anime4k.toggle(),
      'a4k_quality': () => c.anime4k.toggleQuality(),

      // Вікно та сервіс
      'escape': () => escape(),
      'fullscreen': () => c.toggleFullscreen(),
      'ontop': () => c.toggleAlwaysOnTop(),
      'stats': () => c.showStatsOverlay ? c.closeStatsOverlay() : c.openStatsOverlay(),
      'open_file': () => c.pickAndOpenFile(),
      'queue_panel': () => c.toggleSidePanel(SidePanelType.episodes),
      'info_panel': () => c.toggleSidePanel(SidePanelType.info),
      'screenshot': () => c.takeScreenshot(withSubtitles: true),
      'screenshot_clean': () => c.takeScreenshot(withSubtitles: false),
      'help': () => c.onShowShortcuts?.call(),
    };
  }

  static String _zoomLabel(String raw) => '${(math.pow(2, double.tryParse(raw) ?? 0) * 100).round()}%';

  static String _panLabel(String raw) => '${((double.tryParse(raw) ?? 0) * 100).round()}%';
}
