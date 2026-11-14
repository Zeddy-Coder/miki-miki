/// Мої списки Hikka: запис про тайтл (статус, серії, оцінка), улюблене й передача прогресу з плеєра.
/// Усе тримається в памʼяті лише поки людина ввійшла; при виході кеш скидається.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/hikka_models.dart';
import '../models/hikka_user_models.dart';
import 'app_log.dart';
import 'hikka_api.dart';
import 'hikka_auth.dart';
import 'storage_service.dart';

class HikkaMyList extends ChangeNotifier {
  /// Спільний екземпляр (у тестах підміняється)
  static HikkaMyList instance = HikkaMyList();

  final HikkaAuth? _authOverride;
  final HikkaApi? _apiOverride;
  final SectionLoader? _loadOverride;
  final SectionSaver? _saveOverride;

  /// Збережені статуси: позначки на постерах з'являються одразу, а оновлення з мережі — не частіше за раз на кілька годин
  static const String indexSection = 'hikka_status_index';
  static const Duration indexMaxAge = Duration(hours: 6);

  /// Запис про тайтл за slug (`null` — у списках його немає)
  final Map<String, HikkaWatchEntry?> _entries = {};
  final Map<String, Future<HikkaWatchEntry?>> _loading = {};
  final Map<String, bool> _favourites = {};

  /// Статус кожного тайтлу в моїх списках (для позначок на постерах): заповнюється одним проходом по всіх списках
  final Map<String, HikkaWatchStatus> _index = {};
  bool _indexed = false;
  int _indexAt = 0;
  Future<void>? _indexing;
  final Map<String, Future<void>> _syncing = {};
  HikkaWatchStats? _stats;
  int _version = 0;
  bool _wasSignedIn = false;

  HikkaMyList({HikkaAuth? auth, HikkaApi? api, SectionLoader? load, SectionSaver? save})
      : _authOverride = auth,
        _apiOverride = api,
        _loadOverride = load,
        _saveOverride = save {
    _wasSignedIn = _auth.signedIn;
    _auth.addListener(_onAuth);
  }

  HikkaAuth get _auth => _authOverride ?? HikkaAuth.instance;
  HikkaApi get _api => _apiOverride ?? HikkaApi.instance;

  /// Росте при кожній зміні списків: за ним сторінка «Списки» перезавантажується
  int get version => _version;

  bool get signedIn => _auth.signedIn;

  void _onAuth() {
    final now = _auth.signedIn;
    if (now == _wasSignedIn) return;
    _wasSignedIn = now;
    clear();
    if (now) unawaited(loadIndex());
  }

  /// Скидає все, що знаємо про списки (вихід, зміна акаунта)
  void clear() {
    _entries.clear();
    _loading.clear();
    _favourites.clear();
    _index.clear();
    _indexed = false;
    _indexAt = 0;
    _indexing = null;
    _stats = null;
    try {
      (_saveOverride ?? ((d) => StorageService.saveSection(indexSection, d)))({});
    } catch (_) {}
    _bump();
  }

  // ── Статуси для позначок на постерах ──────────────────────────────

  /// Статус тайтлу в моїх списках; `null` — його там немає або ще невідомо
  HikkaWatchStatus? statusOf(String slug) {
    if (!signedIn) return null;
    if (_entries.containsKey(slug)) return _entries[slug]?.status;
    return _index[slug];
  }

  /// Статуси всіх тайтлів зі списків: спершу з диска (миттєво), потім, якщо дані старші за [indexMaxAge], з мережі
  /// (по 100 за запит, після [delay], щоб не конкурувати з першим екраном); помилка не фатальна — позначок просто не буде
  Future<void> loadIndex({bool refresh = false, Duration delay = Duration.zero}) {
    final name = _auth.username;
    if (!signedIn || name.isEmpty) return Future.value();
    if (_indexed && !refresh) return Future.value();
    return _indexing ??= _loadIndex(name, refresh, delay).whenComplete(() => _indexing = null);
  }

  Future<void> _loadIndex(String name, bool refresh, Duration delay) async {
    final fresh = !refresh && _restoreIndex(name);
    if (fresh) return;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (!signedIn || _auth.username != name) return;
    await _fillIndex(name);
  }

  /// Підхоплює збережені статуси; `true` — вони достатньо свіжі, мережа не потрібна
  bool _restoreIndex(String name) {
    try {
      final data = (_loadOverride ?? (() => StorageService.getSection(indexSection)))();
      if (data['user'] != name) return false;
      final map = data['map'];
      if (map is! Map) return false;
      for (final e in map.entries) {
        final st = HikkaWatchStatus.fromApi(e.value);
        if (st != null) _index[e.key as String] = st;
      }
      _indexed = true;
      notifyListeners();
      _indexAt = (data['at'] as num?)?.toInt() ?? 0;
      final at = DateTime.fromMillisecondsSinceEpoch(_indexAt);
      return DateTime.now().difference(at) < indexMaxAge;
    } catch (_) {
      return false;
    }
  }

  void _persistIndex() {
    if (_indexed && _auth.username.isNotEmpty) _saveIndex(_auth.username);
  }

  void _saveIndex(String name) {
    try {
      (_saveOverride ?? ((d) => StorageService.saveSection(indexSection, d)))({
        'user': name,
        'at': _indexAt,
        'map': {for (final e in _index.entries) e.key: e.value.api},
      });
    } catch (_) {}
  }

  Future<void> _fillIndex(String name) async {
    try {
      final fresh = <String, HikkaWatchStatus>{};
      for (final status in HikkaWatchStatus.values) {
        var page = 1;
        while (true) {
          final p = await _api.watchList(name, status: status, page: page, size: 100);
          for (final e in p.items) {
            final slug = e.anime?.slug;
            if (slug != null && slug.isNotEmpty) fresh[slug] = e.status;
          }
          if (page >= p.pages || p.items.isEmpty) break;
          page++;
        }
      }
      if (!signedIn || _auth.username != name) return;
      _index
        ..clear()
        ..addAll(fresh);
      _indexed = true;
      _indexAt = DateTime.now().millisecondsSinceEpoch;
      notifyListeners();
      _saveIndex(name);
    } catch (e) {
      AppLog.w('hikka', 'статуси списків не завантажено: $e');
    }
  }

  void _bump() {
    _version++;
    notifyListeners();
  }

  // ── Запис про тайтл ──────────────────────────────────────────────

  /// Те, що вже відомо без мережі: `null` у значенні — тайтлу в списках немає; ключа немає — невідомо
  bool knows(String slug) => _entries.containsKey(slug);
  HikkaWatchEntry? cached(String slug) => _entries[slug];

  /// Мій запис про тайтл (з мережі один раз, далі з памʼяті)
  Future<HikkaWatchEntry?> entry(String slug, {bool refresh = false}) {
    if (!signedIn) return Future.value(null);
    if (!refresh && _entries.containsKey(slug)) return Future.value(_entries[slug]);
    return _loading[slug] ??= _api.myWatch(slug).then((e) {
      _entries[slug] = e;
      return e;
    }).whenComplete(() {
      _loading.remove(slug);
    });
  }

  /// Зберігає запис і повертає те, що відповів сервер.
  /// [total] — скільки серій у тайтлі: для «Переглянуто» лічильник добивається до кінця, як на сайті.
  Future<HikkaWatchEntry> save(
    String slug, {
    HikkaWatchStatus? status,
    int? episodes,
    int? score,
    int? total,
    HikkaAnime? anime,
  }) async {
    final old = await entry(slug);
    var next = (old ?? const HikkaWatchEntry(status: HikkaWatchStatus.planned)).copyWith(status: status, episodes: episodes, score: score);
    if (status == HikkaWatchStatus.completed && total != null && total > 0 && next.episodes < total) {
      next = next.copyWith(episodes: total);
    }
    if (total != null && total > 0 && next.episodes > total) next = next.copyWith(episodes: total);
    final saved = await _api.saveWatch(slug, next);
    _entries[slug] = saved.anime == null && anime != null ? saved.copyWith(anime: anime) : saved;
    _index[slug] = saved.status;
    _persistIndex();
    _stats = null;
    _bump();
    return _entries[slug]!;
  }

  /// Прибирає тайтл зі списків
  Future<void> remove(String slug) async {
    await _api.removeWatch(slug);
    _entries[slug] = null;
    _index.remove(slug);
    _persistIndex();
    _stats = null;
    _bump();
  }

  /// Скільки тайтлів у кожному статусі
  Future<HikkaWatchStats> stats({bool refresh = false}) async {
    final name = _auth.username;
    if (name.isEmpty) return const HikkaWatchStats();
    if (!refresh && _stats != null) return _stats!;
    return _stats = await _api.watchStats(name);
  }

  // ── Улюблене ─────────────────────────────────────────────────────

  bool? favouriteCached(String slug) => _favourites[slug];

  Future<bool> isFavourite(String slug) async {
    if (!signedIn) return false;
    final known = _favourites[slug];
    if (known != null) return known;
    return _favourites[slug] = await _api.isFavourite(slug);
  }

  Future<void> setFavourite(String slug, bool value) async {
    await _api.setFavourite(slug, value);
    _favourites[slug] = value;
    _bump();
  }

  // ── Прогрес із плеєра ────────────────────────────────────────────

  /// Яку серію вважати переглянутою у списку Hikka: номер серії з джерела (12-та серія — це 12), але не більше
  /// за кількість серій тайтлу на Hikka («13 з 12» — відмічено 12). Якщо всі номери варіанта лежать за межами
  /// тайтлу (наскрізна нумерація 13…24) або номера немає — [position], теж із стелею [total].
  static int episodeNumber({double? number, required int position, int? total, bool trustNumber = true}) {
    var r = position;
    final n = number;
    if (trustNumber && n != null && n >= 1 && n == n.roundToDouble()) r = n.toInt();
    if (total != null && total > 0 && r > total) r = total;
    return r < 1 ? 1 : r;
  }

  /// Серію [episode] тайтлу [slug] переглянуто. Додає тайтл у «Дивлюсь», піднімає лічильник серій і
  /// переводить у «Переглянуто» після останньої. Ніколи не зменшує прогрес і не чіпає вже завершене.
  /// Усі збої тихі: перегляд важливіший за синхронізацію.
  Future<void> syncEpisode(String slug, int episode, {int? total}) {
    if (!signedIn || !_auth.syncProgress || episode < 1) return Future.value();
    final prev = _syncing[slug] ?? Future<void>.value();
    final run = prev.then((_) => _syncOne(slug, episode, total));
    _syncing[slug] = run;
    return run.whenComplete(() {
      if (identical(_syncing[slug], run)) _syncing.remove(slug);
    });
  }

  Future<void> _syncOne(String slug, int episode, int? total) async {
    try {
      // Свіжий запис: на сайті прогрес міг піти вперед, а за застарілим кешем ми б його занизили
      final old = await entry(slug, refresh: true);
      if (old != null) {
        if (old.status == HikkaWatchStatus.completed) return;
        if (episode <= old.episodes && old.status == HikkaWatchStatus.watching) return;
      }
      final done = total != null && total > 0 && episode >= total;
      final episodes = old == null ? episode : (episode > old.episodes ? episode : old.episodes);
      await save(
        slug,
        status: done ? HikkaWatchStatus.completed : HikkaWatchStatus.watching,
        episodes: episodes,
        total: total,
      );
      AppLog.d('hikka', 'прогрес передано: $slug, серія $episode${done ? ' (завершено)' : ''}');
    } on HikkaException catch (e) {
      AppLog.w('hikka', 'прогрес не передано ($slug, серія $episode): $e');
    } catch (e) {
      AppLog.w('hikka', 'прогрес не передано ($slug, серія $episode): $e');
    }
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuth);
    super.dispose();
  }
}
