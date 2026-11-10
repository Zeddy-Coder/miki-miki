import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import '../models/media_models.dart';
import '../utils/formatters.dart';

/// Єдиний «годинник відтворення» для інтерфейсу.
///
/// mpv повідомляє позицію 24–60+ разів на секунду. Якщо кожен віджет сам підписується на
/// `player.stream.position` і перебудовується на кожну подію, то під час перегляду інтерфейс
/// постійно працює вхолосту (навіть коли панель керування прихована). Годинник підписується
/// на потоки плеєра **один раз** і віддає віджетам готові похідні значення, які змінюються
/// лише тоді, коли їх справді видно: цілі секунди, проміле прогресу, номер розділу тощо.
///
/// Один годинник на плеєр: [PlaybackClock.of].
class PlaybackClock {
  PlaybackClock._(this.player)
      : position = ValueNotifier<Duration>(player.state.position),
        duration = ValueNotifier<Duration>(player.state.duration),
        buffer = ValueNotifier<Duration>(player.state.buffer),
        playing = ValueNotifier<bool>(player.state.playing),
        seconds = ValueNotifier<int>(player.state.position.inSeconds),
        permille = ValueNotifier<int>(_permille(player.state.position, player.state.duration)) {
    _subs.addAll([
      player.stream.position.listen(_onPosition),
      player.stream.duration.listen(_onDuration),
      player.stream.buffer.listen((b) => buffer.value = b),
      player.stream.playing.listen((p) => playing.value = p),
    ]);
  }

  static final Expando<PlaybackClock> _registry = Expando<PlaybackClock>('PlaybackClock');

  /// Спільний годинник плеєра (створюється при першому зверненні)
  static PlaybackClock of(Player player) => _registry[player] ??= PlaybackClock._(player);

  /// Відписує годинник від потоків плеєра. Викликати перед `player.dispose()`.
  static void release(Player player) {
    final clock = _registry[player];
    if (clock == null) return;
    _registry[player] = null;
    clock._cancel();
  }

  final Player player;

  /// Позиція «як є», на кожну подію mpv. Слухати лише дешевими слухачами (без setState).
  final ValueNotifier<Duration> position;

  /// Тривалість поточного файлу
  final ValueNotifier<Duration> duration;

  /// Скільки вже в буфері демультиплексора
  final ValueNotifier<Duration> buffer;

  final ValueNotifier<bool> playing;

  /// Ціла кількість секунд позиції: змінюється раз на секунду (для підписів часу)
  final ValueNotifier<int> seconds;

  /// Прогрес у проміле (0..1000): для тонких смужок прогресу, де піксельна точність не потрібна
  final ValueNotifier<int> permille;

  final List<StreamSubscription<dynamic>> _subs = [];

  static int _permille(Duration pos, Duration dur) {
    if (dur <= Duration.zero) return 0;
    return (pos.inMicroseconds * 1000 ~/ dur.inMicroseconds).clamp(0, 1000).toInt();
  }

  void _onPosition(Duration p) {
    position.value = p;
    seconds.value = p.inSeconds;
    permille.value = _permille(p, duration.value);
  }

  void _onDuration(Duration d) {
    duration.value = d;
    permille.value = _permille(position.value, d);
  }

  /// Похідне значення: слухачі отримують сповіщення лише коли результат [select] змінився
  ClockValue<T> derive<T>(T Function(Duration position, Duration duration) select) => ClockValue<T>(this, select);

  void _cancel() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
  }
}

/// Значення, обчислене з позиції та тривалості, що сповіщає лише при зміні результату.
/// Власник (State) мусить викликати [dispose].
class ClockValue<T> extends ChangeNotifier implements ValueListenable<T> {
  ClockValue(this._clock, this._select) {
    _value = _select(_clock.position.value, _clock.duration.value);
    _clock.position.addListener(_update);
    _clock.duration.addListener(_update);
  }

  final PlaybackClock _clock;
  final T Function(Duration position, Duration duration) _select;
  late T _value;

  @override
  T get value => _value;

  /// Перераховує значення після зміни вхідних даних віджета (наприклад, списку розділів).
  /// Без [notify] слухачі не сповіщаються — для виклику з `didUpdateWidget`, коли власник
  /// усе одно перебудовується.
  void refresh({bool notify = false}) {
    final v = _select(_clock.position.value, _clock.duration.value);
    if (v == _value) return;
    _value = v;
    if (notify) notifyListeners();
  }

  void _update() {
    final v = _select(_clock.position.value, _clock.duration.value);
    if (v == _value) return;
    _value = v;
    notifyListeners();
  }

  @override
  void dispose() {
    _clock.position.removeListener(_update);
    _clock.duration.removeListener(_update);
    super.dispose();
  }
}

/// Прогрес відтворення для смужки: сповіщає лише коли смужка зсунулась хоча б на один
/// крок квантування ([steps] — зазвичай ширина смужки у фізичних пікселях).
///
/// Для 90-хвилинного фільму на смужці в 1500 пікселів це ~0,3 перемальовування на секунду
/// замість 24–60. Поки [live] вимкнено (панель прихована), нічого не сповіщається, а при
/// увімкненні смужка одразу догоняє актуальний стан.
class ClockProgress extends ChangeNotifier {
  ClockProgress(this._clock, {double steps = 1000, bool live = true})
      : _steps = steps,
        _live = live {
    _recalc();
    _lastPlayedStep = _step(_played);
    _lastBufferedStep = _step(_buffered);
    _clock.position.addListener(_onSource);
    _clock.duration.addListener(_onSource);
    _clock.buffer.addListener(_onSource);
  }

  final PlaybackClock _clock;
  double _steps;
  bool _live;
  double _played = 0;
  double _buffered = 0;
  int _lastPlayedStep = 0;
  int _lastBufferedStep = 0;
  bool _pending = false;

  /// Частка відтвореного (0..1), точна
  double get played => _played;

  /// Частка буфера (0..1), точна
  double get buffered => _buffered;

  bool get live => _live;

  /// Скільки різних положень має смужка (ширина у фізичних пікселях)
  set steps(double v) {
    if (v <= 0 || v == _steps) return;
    _steps = v;
  }

  set live(bool v) {
    if (v == _live) return;
    _live = v;
    if (v && _pending) {
      _pending = false;
      _lastPlayedStep = _step(_played);
      _lastBufferedStep = _step(_buffered);
      notifyListeners();
    }
  }

  int _step(double fraction) => (fraction * _steps).round();

  void _recalc() {
    final total = _clock.duration.value.inMicroseconds;
    if (total <= 0) {
      _played = 0;
      _buffered = 0;
      return;
    }
    _played = (_clock.position.value.inMicroseconds / total).clamp(0.0, 1.0).toDouble();
    _buffered = (_clock.buffer.value.inMicroseconds / total).clamp(0.0, 1.0).toDouble();
  }

  void _onSource() {
    _recalc();
    final p = _step(_played);
    final b = _step(_buffered);
    if (p == _lastPlayedStep && b == _lastBufferedStep) return;
    if (!_live) {
      _pending = true;
      return;
    }
    _lastPlayedStep = p;
    _lastBufferedStep = b;
    notifyListeners();
  }

  @override
  void dispose() {
    _clock.position.removeListener(_onSource);
    _clock.duration.removeListener(_onSource);
    _clock.buffer.removeListener(_onSource);
    super.dispose();
  }
}

/// Прості обчислення над розділами (чисті функції, зручно перевіряти тестами)
class ChapterMath {
  const ChapterMath._();

  /// Розділ, що почався востаннє до [pos]; -1, якщо позиція ще до першого розділу
  static int indexAt(List<VideoChapter> chapters, Duration pos) {
    for (int i = chapters.length - 1; i >= 0; i--) {
      if (pos >= chapters[i].startTime) return i;
    }
    return -1;
  }

  static const List<String> _skipMarkers = ['опенінґ', 'ендінґ', 'рекап', 'титри'];

  static bool isSkippable(VideoChapter chapter) {
    final t = AppFormatters.translateChapterTitle(chapter.title).toLowerCase();
    for (final m in _skipMarkers) {
      if (t.contains(m)) return true;
    }
    return false;
  }

  /// Для кожного розділу: чи пропонувати для нього «Пропустити» (рахується раз на список)
  static List<bool> skippableFlags(List<VideoChapter> chapters) => [for (final c in chapters) isSkippable(c)];

  /// Розділ, для якого зараз треба показувати «Пропустити» (перші 15 с і ще щонайменше 2 с до кінця), або -1.
  /// [flags] — результат [skippableFlags] для того самого списку.
  static int skipIndexAt(List<VideoChapter> chapters, List<bool> flags, Duration pos, Duration total) {
    for (int i = 0; i < chapters.length; i++) {
      final start = chapters[i].startTime;
      final end = (i + 1 < chapters.length) ? chapters[i + 1].startTime : total;
      if (pos >= start && pos < end && i < flags.length && flags[i]) {
        final fromStart = pos - start;
        if (fromStart.inSeconds < 15 && (end - pos).inSeconds >= 2) return i;
        return -1;
      }
    }
    return -1;
  }
}
