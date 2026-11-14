import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import '../models/media_models.dart';
import '../utils/formatters.dart';

/// A single "playback clock" for the UI.
///
/// mpv reports the position 24–60+ times per second. If every widget subscribes to
/// `player.stream.position` itself and rebuilds on every event, the UI constantly
/// idles while watching (even when the control panel is hidden). The clock subscribes
/// to the player streams **once** and hands widgets ready derived values that change
/// only when they are actually visible: whole seconds, progress per mille, chapter number, etc.
///
/// One clock per player: [PlaybackClock.of].
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

  /// The player's shared clock (created on first access)
  static PlaybackClock of(Player player) => _registry[player] ??= PlaybackClock._(player);

  /// Unsubscribes the clock from the player streams. Call before `player.dispose()`.
  static void release(Player player) {
    final clock = _registry[player];
    if (clock == null) return;
    _registry[player] = null;
    clock._cancel();
  }

  final Player player;

  /// The position "as is", on every mpv event. Listen only with cheap listeners (no setState).
  final ValueNotifier<Duration> position;

  /// Duration of the current file
  final ValueNotifier<Duration> duration;

  /// How much is already in the demuxer buffer
  final ValueNotifier<Duration> buffer;

  final ValueNotifier<bool> playing;

  /// Whole seconds of the position: changes once per second (for time labels)
  final ValueNotifier<int> seconds;

  /// Progress in per mille (0..1000): for thin progress bars where pixel precision is not needed
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

  /// Derived value: listeners are notified only when the result of [select] changed
  ClockValue<T> derive<T>(T Function(Duration position, Duration duration) select) => ClockValue<T>(this, select);

  void _cancel() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
  }
}

/// A value computed from position and duration that notifies only when the result changes.
/// The owner (State) must call [dispose].
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

  /// Recomputes the value after the widget's inputs change (e.g. the chapter list).
  /// Without [notify] listeners are not notified: for calling from `didUpdateWidget` when the owner
  /// rebuilds anyway.
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

/// Playback progress for the bar: notifies only when the bar shifted by at least one
/// quantization step ([steps] is usually the bar width in physical pixels).
///
/// For a 90-minute film on a 1500-pixel bar that is ~0.3 repaints per second
/// instead of 24–60. While [live] is off (the panel is hidden), nothing is notified, and when
/// it is turned on the bar catches up with the current state at once.
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

  /// Fraction played (0..1), exact
  double get played => _played;

  /// Fraction buffered (0..1), exact
  double get buffered => _buffered;

  bool get live => _live;

  /// How many distinct positions the bar has (width in physical pixels)
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

/// Simple computations over chapters (pure functions, easy to test)
class ChapterMath {
  const ChapterMath._();

  /// The chapter that last started before [pos]; -1 if the position is before the first chapter
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

  /// For each chapter: whether to offer "Skip" for it (computed once per list)
  static List<bool> skippableFlags(List<VideoChapter> chapters) => [for (final c in chapters) isSkippable(c)];

  /// The chapter for which "Skip" should be shown now (the first 15 s and at least 2 s before the end), or -1.
  /// [flags] is the result of [skippableFlags] for the same list.
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
