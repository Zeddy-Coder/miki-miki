/// Драйвер перегляду серій із сайтів: бере посилання на потрібну серію, відкриває його в плеєрі, памʼятає місце,
/// позначає «переглянуто», переходить до наступної серії, перемикає озвучки, плеєри й якість і виручає, коли відео
/// не запускається. Нічого не знає про media_kit і віджети: плеєр — це [RemoteEngine], тому все перевіряється тестами.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/media_models.dart';
import '../models/source_models.dart';
import 'episode_check.dart';
import 'hikka_lists.dart';
import 'lang_match.dart';
import 'remote_playback.dart';
import 'source_registry.dart';
import 'sources/source_http.dart';
import 'sources/hls_proxy.dart';
import 'sources/source_log.dart';
import 'storage_service.dart';
import 'stream_resolver.dart';
import 'watch_models.dart';
import 'watch_store.dart';

/// Те, що драйверу потрібно від плеєра
abstract class RemoteEngine {
  /// Відкриває пряме відео (попереднє відтворення скасовується); [start] — з якого місця почати
  Future<void> openVideo(Video video, {Duration? start});

  Duration get position;
  Duration get duration;

  /// Відео зараз відтворюється (не на паузі)
  bool get playing;

  /// Додає зовнішній субтитр; [select] — одразу показувати його
  Future<void> addSubtitle(Track track, {required bool select});

  /// Додає зовнішню звукову доріжку (наприклад, озвучення окремим файлом)
  Future<void> addAudio(Track track, {required bool select});
}

/// Стан відтворення серії
enum RemotePhase {
  /// Сесії немає
  idle,

  /// Шукаємо пряме посилання на відео
  resolving,

  /// Посилання передано плеєру, чекаємо початку відео
  opening,

  /// Відео йде
  playing,

  /// Не вдалося (є [RemoteDriver.error])
  failed,
}

class RemoteDriver extends ChangeNotifier {
  final RemoteEngine engine;
  final SourceRegistry registry;
  final StreamResolver resolver;
  final WatchStore store;

  /// Чи переходити до наступної серії, коли ця закінчилась
  final bool Function() autoNext;

  final int Function(String key) _readPosition;
  final void Function(String key, int positionMs, int durationMs) _writePosition;
  final DateTime Function() _now;

  /// Пріоритет мов субтитрів із налаштувань: з кількох зовнішніх доріжок вмикається найвища за ним
  final List<String> Function() _subPriorities;

  /// Скільки чекати на початок відео, перш ніж пробувати інший плеєр
  final Duration openTimeout;

  /// Скільки чекати після помилки плеєра (помилки бувають і дрібні — відео може все одно піти)
  final Duration errorGrace;

  RemoteDriver({
    required this.engine,
    required this.registry,
    required this.resolver,
    WatchStore? store,
    bool Function()? autoNext,
    int Function(String key)? readPosition,
    void Function(String key, int positionMs, int durationMs)? writePosition,
    DateTime Function()? now,
    List<String> Function()? subPriorities,
    this.openTimeout = const Duration(seconds: 30),
    this.errorGrace = const Duration(seconds: 6),
  }) : store = store ?? WatchStore.instance,
       autoNext = autoNext ?? (() => StorageService.getAutoplayNext()),
       _subPriorities = subPriorities ?? (() => StorageService.getSubLangPriorities()),
       _readPosition = readPosition ?? StorageService.getPlaybackPosition,
       _writePosition = writePosition ?? StorageService.savePlaybackPosition,
       _now = now ?? DateTime.now;

  // ── Зворотні виклики до контролера плеєра ────────────────────────────────────

  /// Змінилася поточна серія (назва, ключ позиції)
  void Function(int index)? onEntry;

  /// Змінилася черга (обрано іншу озвучку)
  VoidCallback? onSession;

  /// Коротке повідомлення для екрана («Наступна серія», «Це остання серія»)
  void Function(String text, {bool error})? onMessage;

  // ── Стан ────────────────────────────────────────────────────────────────────

  RemoteSession? _session;
  WatchTitle? _title;
  HikkaEpisodeInfo? _hikka;
  String _groupId = '';
  int _index = 0;
  RemotePhase _phase = RemotePhase.idle;
  String? _error;
  ResolvedStream? _stream;
  Video? _video;
  List<VideoChapter> _chapters = const [];

  RemoteSession? get session => _session;

  /// Усі варіанти перегляду аніме (для перемикання озвучок); `null`, якщо запуск був без них
  WatchTitle? get title => _title;

  String get groupId => _groupId;

  int get index => _index;

  RemotePhase get phase => _phase;

  /// Повідомлення про невдачу для користувача (у фазі [RemotePhase.failed])
  String? get error => _error;

  /// Пряме відео, що відтворюється, і всі його варіанти якості / плеєри
  ResolvedStream? get stream => _stream;

  Video? get video => _video;

  /// Розділи з таймкодів сайту (опенінґ, ендінґ …)
  List<VideoChapter> get chapters => _chapters;

  bool get active => _session != null;

  /// Серію ще готують або вона не запустилась: плеєр показує екран стану замість відео
  bool get showsStatus => _session != null && (_phase == RemotePhase.resolving || _phase == RemotePhase.opening || _phase == RemotePhase.failed);

  /// Інший плеєр цієї серії, який варто спробувати після поточного (по колу); `null`, якщо вибору немає
  String? get alternativeHoster {
    final list = _stream?.hosters ?? const <String>[];
    if (list.length < 2) return null;
    final i = list.indexWhere((h) => h.toLowerCase() == hoster.toLowerCase());
    return list[(i + 1) % list.length];
  }

  RemoteEntry? get entry => _session == null || _index >= _session!.entries.length ? null : _session!.entries[_index];

  bool get hasNext => _session != null && _index + 1 < _session!.entries.length;

  bool get hasPrevious => _session != null && _index > 0;

  /// Усе, що можна показати користувачеві про поточний варіант
  WatchGroup? get group => _title?.groupById(_groupId);

  /// Субтитри, а не озвучення
  bool get isSub => group?.isSub ?? false;

  String get hoster => _stream?.hoster ?? '';

  /// Що зараз відтворюється одним рядком: «Озвучення: Amanogawa · Moon · 1080p» (без підпису — [withKind] = false)
  String nowPlaying({bool withKind = true}) {
    final g = group;
    final q = _video?.title ?? '';
    return [if (g != null) (withKind ? g.fullLabel : g.label), if (hoster.isNotEmpty) hoster, if (q.isNotEmpty) q].join(' · ');
  }

  /// Номер спроби (1 — перший плеєр), для підпису «Пробую інший плеєр»
  int get attempt => _tried.length;

  int _token = 0;
  Timer? _watchdog;
  Timer? _stallCheck;
  bool _marked = false;
  bool _disposed = false;
  DateTime _openedAt = DateTime.fromMillisecondsSinceEpoch(0);
  Duration _openStart = Duration.zero;
  DateTime? _lastRecover;
  final Set<String> _tried = {};
  String? _stickyHoster;
  int? _stickyHeight;

  // ── Запуск і навігація ──────────────────────────────────────────────────────

  /// Звірка серій варіанта з Hikka (для застережень у списку озвучок). Без даних Hikka — лише перевірка нумерації.
  EpisodeCheck checkOf(WatchGroup g) => checkEpisodes(g.episodes, _hikka ?? const HikkaEpisodeInfo());

  /// Починає перегляд: черга — усі серії обраної озвучки, відкривається стартова
  Future<void> start(RemoteLaunch launch) async {
    _savePosition();
    _session = launch.session;
    _title = launch.title;
    _hikka = launch.hikka;
    _groupId = launch.group.id;
    _stickyHoster = null;
    _stickyHeight = null;
    store.setPreferredGroup(launch.title.animeKey, launch.group.id);
    onSession?.call();
    await open(launch.startIndex, saveCurrent: false);
  }

  /// Відкриває серію [i] поточної черги. [startAt] — з якого місця (інакше зі збереженого, а якщо його немає — спочатку).
  Future<void> open(int i, {String? hoster, int? height, Duration? startAt, bool saveCurrent = true}) async {
    final s = _session;
    if (s == null || i < 0 || i >= s.entries.length) return;
    if (saveCurrent) _savePosition();
    final token = ++_token;
    _cancelTimers();
    _index = i;
    _error = null;
    _stream = null;
    _video = null;
    _chapters = const [];
    _marked = false;
    _tried.clear();
    _phase = RemotePhase.resolving;
    final e = s.entries[i];
    store.setLast(s.animeKey, e.epKey, e.groupId);
    onEntry?.call(i);
    _changed();
    await _resolveAndPlay(token, e, hoster: hoster ?? _stickyHoster, height: height ?? _stickyHeight, startAt: startAt);
  }

  Future<bool> next({bool save = true}) async {
    if (!hasNext) return false;
    await open(_index + 1, saveCurrent: save);
    return true;
  }

  Future<bool> previous() async {
    if (!hasPrevious) return false;
    await open(_index - 1);
    return true;
  }

  /// Спробувати ще раз (після невдачі): з тим самим місцем, без запамʼятованих невдалих плеєрів
  Future<void> retry() async {
    if (!active) return;
    final at = engine.position > const Duration(seconds: 5) ? engine.position : null;
    await open(_index, startAt: at ?? _fallbackStart(), saveCurrent: false);
  }

  Duration? _fallbackStart() => _openStart > const Duration(seconds: 5) ? _openStart : null;

  /// Перемикає озвучку / субтитри: та сама серія (за номером) в іншому варіанті, з того ж місця
  Future<void> switchGroup(WatchGroup g) async {
    final s = _session;
    final t = _title;
    final cur = entry;
    if (s == null || t == null || cur == null || g.id == _groupId || g.episodes.isEmpty) return;
    final at = engine.position;
    _savePosition();
    final ns = RemoteSession.fromGroup(animeKey: s.animeKey, animeTitle: s.animeTitle, group: g, poster: s.poster);
    var ni = ns.indexOfKey(cur.epKey);
    if (ni < 0) ni = _index.clamp(0, ns.entries.length - 1);
    _session = ns;
    _groupId = g.id;
    _stickyHoster = null;
    // Свідомий вибір: запамʼятовується для цього тайтлу й стає типовим для нових (див. `pickGroup`)
    store.setPreferredGroup(s.animeKey, g.id);
    store.setPinnedGroup(s.animeKey, g.id);
    store.setFavoriteChoice(choiceKeyOf(g));
    onSession?.call();
    await open(ni, startAt: at > const Duration(seconds: 5) ? at : null, saveCurrent: false);
  }

  /// Вручну обраний плеєр (Moon, Ashdi …): діє й на наступні серії цієї сесії
  Future<void> switchHoster(String name) async {
    if (!active || name.isEmpty || name == hoster) return;
    _stickyHoster = name;
    final at = engine.position;
    await open(_index, hoster: name, startAt: at > const Duration(seconds: 5) ? at : _fallbackStart());
  }

  /// Інша якість того самого плеєра: посилання вже відоме, повторного пошуку немає
  Future<void> switchQuality(Video v) async {
    final res = _stream;
    if (!active || res == null || _phase == RemotePhase.resolving || v.url == _video?.url) return;
    _stickyHeight = v.resolution; // «Авто» (без висоти) повертає налаштування за замовчуванням
    final at = engine.position;
    final token = ++_token;
    _cancelTimers();
    await _launch(token, res, v, at > const Duration(seconds: 5) ? at : null);
  }

  // ── Події плеєра ────────────────────────────────────────────────────────────

  /// Плеєр дізнався тривалість — відео справді запустилось
  void onDuration(Duration d) {
    if (!active || d <= Duration.zero || _phase != RemotePhase.opening) return;
    final v = _video;
    _watchdog?.cancel();
    _phase = RemotePhase.playing;
    _chapters = chaptersFromTimestamps(v?.timestamps ?? const [], d);
    _changed();
    final token = _token;
    if (v != null) unawaited(_applyExtras(token, v));
  }

  /// Раз на кілька секунд: зберігає місце й позначає серію переглянутою
  void tick() {
    if (!active || _phase != RemotePhase.playing) return;
    _savePosition();
    final e = entry;
    if (!_marked && e != null && episodeSeen(engine.position, engine.duration, _video?.timestamps ?? const [], fraction: StorageService.getWatchedPercent() / 100, byEnding: StorageService.getWatchedByEnding())) {
      _markWatched(e);
    }
  }

  /// Серія дограла до кінця
  Future<void> onCompleted() async {
    final e = entry;
    if (!active || e == null || _phase != RemotePhase.playing) return;
    // Відео скінчилося за мить після старту з середини — збережена позиція не підійшла цій озвучці: починаємо спочатку
    if (_openStart > Duration.zero && _now().difference(_openedAt) < const Duration(seconds: 6)) {
      _openStart = Duration.zero;
      final token = ++_token;
      final res = _stream, v = _video;
      if (res != null && v != null) await _launch(token, res, v, Duration.zero);
      return;
    }
    if (!_marked) _markWatched(e);
    final dur = engine.duration.inMilliseconds;
    if (dur > 0) _writePosition(e.key, dur, dur); // дивитись спочатку, а не з кінця
    if (!hasNext) {
      onMessage?.call('Це остання серія');
      return;
    }
    if (autoNext()) {
      onMessage?.call('Наступна серія');
      await next(save: false); // підсумок серії вже записано вище
    }
  }

  /// Помилка плеєра: до початку відео — пробуємо інший плеєр; під час перегляду — перевіряємо, чи потік не завис
  void onPlayerError(String text) {
    if (!active) return;
    final token = _token;
    if (_phase == RemotePhase.opening) {
      _armWatchdog(token, errorGrace, text);
    } else if (_phase == RemotePhase.playing) {
      final at = engine.position;
      _stallCheck?.cancel();
      _stallCheck = Timer(errorGrace, () {
        if (token != _token || _phase != RemotePhase.playing || !engine.playing) return;
        if ((engine.position - at).inMilliseconds.abs() > 500) return; // відео йде — помилка була дрібна
        unawaited(_recover());
      });
    }
  }

  /// Потік міг протухнути (посилання живуть пару годин): беремо нове й продовжуємо з того ж місця
  Future<void> _recover() async {
    final now = _now();
    final last = _lastRecover;
    if (last != null && now.difference(last) < const Duration(seconds: 30)) return;
    _lastRecover = now;
    final at = engine.position;
    onMessage?.call('Оновлюю посилання на відео…');
    await open(_index, hoster: _stream?.hoster, startAt: at > const Duration(seconds: 5) ? at : null, saveCurrent: false);
  }

  /// Зупиняє сесію (закрили плеєр або відкрили інший файл)
  void stop({bool save = true}) {
    if (!active) return;
    if (save) _savePosition();
    _token++;
    _cancelTimers();
    _session = null;
    _title = null;
    _stream = null;
    _video = null;
    _chapters = const [];
    _error = null;
    _phase = RemotePhase.idle;
    _changed();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelTimers();
    super.dispose();
  }

  // ── Внутрішнє ───────────────────────────────────────────────────────────────

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void _cancelTimers() {
    _watchdog?.cancel();
    _stallCheck?.cancel();
    _blockedSub?.cancel();
    _blockedSub = null;
  }

  StreamSubscription<int>? _blockedSub;

  /// Локальний проксі повідомляє, що сервер відхиляє сегменти: чекати 30 с марно, одразу пробуємо інший плеєр
  void _watchBlocked(int token) {
    _blockedSub?.cancel();
    final baseline = HlsProxy.instance.blockedCount;
    _blockedSub = HlsProxy.instance.blocked.listen((n) {
      if (token != _token || _phase != RemotePhase.opening || n - baseline < 3) return;
      _blockedSub?.cancel();
      unawaited(_failOver(token, 'Сервер відхиляє сегменти відео'));
    });
  }

  void _markWatched(RemoteEntry e) {
    _marked = true;
    final s = _session!;
    store.setWatched(s.animeKey, e.epKey, true);
    _syncToHikka(s, e);
    _changed(); // у панелі серій зʼявляється позначка «переглянуто»
  }

  /// Передає прогрес у списки Hikka: лише для тайтлів із каталогу Hikka, лише за входу й тихо
  void _syncToHikka(RemoteSession s, RemoteEntry e) {
    const prefix = 'hikka:';
    if (!s.animeKey.startsWith(prefix)) return;
    final total = _hikka?.total;
    // Номер серії довірений, якщо хоч одна серія варіанта лежить у межах тайтлу; наскрізна нумерація (13…24
    // для 12 серій) рахується за позицією
    final nums = s.entries.map((x) => x.episode.number).whereType<double>().toList();
    final trust = nums.isEmpty || total == null || total <= 0 || nums.reduce((a, b) => a < b ? a : b) <= total;
    final n = HikkaMyList.episodeNumber(number: e.episode.number, position: s.entries.indexOf(e) + 1, total: total, trustNumber: trust);
    unawaited(HikkaMyList.instance.syncEpisode(s.animeKey.substring(prefix.length), n, total: total));
  }

  void _savePosition() {
    final e = entry;
    if (e == null || _phase != RemotePhase.playing) return;
    final dur = engine.duration;
    if (dur <= Duration.zero) return;
    _writePosition(e.key, engine.position.inMilliseconds, dur.inMilliseconds);
  }

  Duration? _resumePoint(RemoteEntry e) {
    final ms = _readPosition(e.key);
    return ms > 5000 ? Duration(milliseconds: ms) : null;
  }

  Future<void> _resolveAndPlay(int token, RemoteEntry e, {String? hoster, int? height, Duration? startAt}) async {
    try {
      final source = registry.byId(e.sourceId);
      if (source == null) {
        _fail(token, 'Джерело «${e.sourceId}» не знайдено. Оновіть застосунок або відкрийте серію з іншого джерела.');
        return;
      }
      final res = await resolver.resolve(source, e.episode, hoster: hoster, height: height);
      if (token != _token) return; // за цей час обрали іншу серію
      if (_tried.contains(res.hoster.toLowerCase())) {
        _fail(token, 'Жоден із плеєрів не запустив це відео');
        return;
      }
      await _launch(token, res, res.video, startAt ?? _resumePoint(e));
    } on SourceException catch (ex) {
      _fail(token, ex.message);
    } catch (ex) {
      _fail(token, 'Не вдалося відкрити серію: $ex');
    }
  }

  /// Передає відео плеєру й чекає на його початок
  Future<void> _launch(int token, ResolvedStream res, Video v, Duration? start) async {
    if (token != _token) return;
    _stream = res;
    _video = v;
    _tried.add(res.hoster.toLowerCase());
    SourceLog.add('Відкриваю в плеєрі (${res.hoster}): ${v.url}; заголовки: ${v.headers.keys.isEmpty ? 'нема' : v.headers.keys.join(', ')}; з ${start ?? Duration.zero}');
    _openStart = start ?? Duration.zero;
    _openedAt = _now();
    _chapters = const [];
    _phase = RemotePhase.opening;
    _error = null;
    _armWatchdog(token, openTimeout, 'Відео довго не запускається');
    _watchBlocked(token);
    _changed();
    try {
      await engine.openVideo(v, start: start);
    } catch (ex) {
      if (token == _token) await _failOver(token, 'Плеєр не прийняв відео: $ex');
    }
  }

  void _armWatchdog(int token, Duration after, String reason) {
    _watchdog?.cancel();
    _watchdog = Timer(after, () {
      if (token != _token || _phase != RemotePhase.opening) return;
      SourceLog.add('Таймер відкриття спрацював: $reason (${after.inSeconds} с)');
      unawaited(_failOver(token, reason));
    });
  }

  /// Відео не запустилось: пробуємо наступний плеєр серії, а як їх більше немає — повідомляємо про невдачу
  Future<void> _failOver(int token, String reason) async {
    if (token != _token) return;
    SourceLog.add('Збій відкриття: $reason');
    final res = _stream;
    final e = entry;
    if (res != null && e != null) {
      String? other;
      for (final h in res.hosters) {
        if (!_tried.contains(h.toLowerCase())) {
          other = h;
          break;
        }
      }
      if (other != null) {
        onMessage?.call('Плеєр ${res.hoster} не відповідає, пробую $other', error: true);
        final next = ++_token;
        _cancelTimers();
        _phase = RemotePhase.resolving;
        _stream = null;
        _video = null;
        _changed();
        await _resolveAndPlay(next, e, hoster: other, height: _stickyHeight, startAt: _fallbackStart());
        return;
      }
    }
    _fail(token, '$reason. Спробуйте іншу озвучку чи плеєр або повторіть пізніше.');
  }

  void _fail(int token, String message) {
    if (token != _token) return;
    SourceLog.add('ПОМИЛКА: $message');
    _cancelTimers();
    _phase = RemotePhase.failed;
    _error = message;
    _changed();
  }

  /// Зовнішні доріжки (субтитри, окрема озвучка) додаються, коли відео вже завантажилось
  Future<void> _applyExtras(int token, Video v) async {
    try {
      final subs = v.subtitleTracks;
      // Субтитри обрано свідомо (варіант «Субтитри»): вмикаємо доріжку за мовою з налаштувань, а не просто першу
      final pick = subs.isEmpty ? 0 : LangMatch.pickByLabel([for (final t in subs) t.lang], _subPriorities());
      for (int i = 0; i < subs.length; i++) {
        if (token != _token) return;
        await engine.addSubtitle(subs[i], select: isSub && i == pick);
      }
      final audios = v.audioTracks;
      for (int i = 0; i < audios.length; i++) {
        if (token != _token) return;
        await engine.addAudio(audios[i], select: i == 0);
      }
    } catch (ex) {
      debugPrint('[Remote] зовнішні доріжки: $ex');
    }
  }
}
