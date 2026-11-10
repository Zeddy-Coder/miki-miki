import 'package:flutter/foundation.dart';

import '../models/hikka_models.dart';
import 'app_log.dart';
import 'hikka_markdown.dart';
import 'system_controls.dart';

/// Головні вкладки застосунку (нижня навігація на телефоні, бічне меню на ПК)
enum MainTab {
  home('Головна'),
  discover('Огляд'),
  lists('Списки'),
  profile('Профіль');

  final String label;
  const MainTab(this.label);
}

/// Розділи вкладки «Огляд»
enum HikkaTab {
  overview('Усе'),
  schedule('Календар'),
  anime('Каталог'),
  collections('Колекції'),
  articles('Статті'),
  characters('Персонажі');

  final String label;
  const HikkaTab(this.label);
}

enum HikkaRouteKind { anime, character, franchise, animeCharacters, collection, article, localLibrary, settings }

/// Відкрита сторінка поверх кореневої: аніме, персонаж, франшиза, колекція, стаття…
class HikkaRoute {
  static int _counter = 0;

  /// Унікальний номер: за ним віджети відрізняють два відкриття однієї сторінки
  final int id = ++_counter;
  final HikkaRouteKind kind;

  /// Ідентифікатор сторінки: slug аніме, персонажа чи статті, `reference` колекції
  final String slug;

  /// Дані зі списку (`HikkaAnime` / `HikkaCharacter` / `HikkaCollection` / `HikkaArticle`): шапка сторінки
  /// з'являється одразу, до відповіді API
  final Object? seed;

  /// Положення прокрутки: повертаючись «Назад», сторінка стає там, де її залишили
  double scroll = 0;

  /// Довільний стан сторінки (вибрана вкладка тощо)
  final Map<String, Object?> memo = {};

  HikkaRoute(this.kind, this.slug, {this.seed});

  @override
  String toString() => 'HikkaRoute(${kind.name}, $slug)';
}

/// Навігація застосунку: головна вкладка, розділ «Огляду» й стек відкритих сторінок. Власний стек (а не
/// `Navigator`) потрібен, щоб сторінки лишались усередині вкладок із нижньою навігацією, а «Назад» на телефоні
/// спершу закривав сторінку, потім повертав на «Головну», а не виходив із застосунку.
class HikkaNav extends ChangeNotifier {
  /// Спільний екземпляр (у тестах підміняється)
  static HikkaNav instance = HikkaNav();

  /// Скільки сторінок пам'ятає стек (далі найстаріші забуваються)
  static const int maxDepth = 40;

  MainTab _main = MainTab.home;
  HikkaTab _tab = HikkaTab.overview;
  final List<HikkaRoute> _stack = [];
  HikkaSearchFilters? _pendingFilters;
  bool _focusSearch = false;

  /// Відкриття зовнішніх посилань (у тестах підміняється)
  Future<bool> Function(String url) urlOpener = SystemControls.openUrl;

  MainTab get main => _main;

  /// Відкритий розділ «Огляду» (має сенс, коли [main] — `discover`)
  HikkaTab get tab => _tab;
  List<HikkaRoute> get routes => List.unmodifiable(_stack);
  HikkaRoute? get top => _stack.isEmpty ? null : _stack.last;
  bool get canGoBack => _stack.isNotEmpty || _main != MainTab.home;

  /// Перемикає головну вкладку; відкриті сторінки закриваються (повторний тап по поточній вкладці
  /// теж повертає на її корінь)
  void setMain(MainTab tab) {
    if (tab == _main && _stack.isEmpty) return;
    AppLog.i('навігація', 'вкладка «${tab.label}»');
    _main = tab;
    _stack.clear();
    notifyListeners();
  }

  /// Відкриває розділ «Огляду»
  void setTab(HikkaTab tab) {
    if (_main == MainTab.discover && tab == _tab && _stack.isEmpty) return;
    AppLog.i('навігація', 'огляд: «${tab.label}»');
    _main = MainTab.discover;
    _tab = tab;
    _stack.clear();
    notifyListeners();
  }

  /// Каталог з готовими умовами (кнопка «Усі» біля полиці на головній, жанр на сторінці аніме)
  void openCatalog(HikkaSearchFilters filters, {bool focusSearch = false}) {
    AppLog.i('навігація', 'відкрито каталог${focusSearch ? ' з пошуком' : ' з готовими умовами'}');
    _pendingFilters = filters;
    _focusSearch = focusSearch;
    _main = MainTab.discover;
    _tab = HikkaTab.anime;
    _stack.clear();
    notifyListeners();
  }

  /// Пошукова панель «Головної»: каталог із курсором у полі пошуку
  void openSearch() => openCatalog(const HikkaSearchFilters(), focusSearch: true);

  /// Умови, з якими відкрито каталог; віддаються один раз
  HikkaSearchFilters? takePendingFilters() {
    final f = _pendingFilters;
    _pendingFilters = null;
    return f;
  }

  bool get hasPendingFilters => _pendingFilters != null;

  /// Чи треба одразу поставити курсор у поле пошуку каталогу; віддається один раз
  bool takeFocusSearch() {
    final v = _focusSearch;
    _focusSearch = false;
    return v;
  }

  bool get wantsSearchFocus => _focusSearch;

  void _push(HikkaRoute route) {
    final last = top;
    if (last != null && last.kind == route.kind && last.slug == route.slug) return; // подвійний тап
    AppLog.i('навігація', 'відкрито ${route.kind.name}: ${route.slug} (глибина ${_stack.length + 1})');
    _stack.add(route);
    if (_stack.length > maxDepth) _stack.removeAt(0);
    notifyListeners();
  }

  void openAnime(String slug, {HikkaAnime? seed}) {
    if (slug.isNotEmpty) _push(HikkaRoute(HikkaRouteKind.anime, slug, seed: seed));
  }

  void openCharacter(String slug, {HikkaCharacter? seed}) {
    if (slug.isNotEmpty) _push(HikkaRoute(HikkaRouteKind.character, slug, seed: seed));
  }

  void openFranchise(String slug, {HikkaAnime? seed}) {
    if (slug.isNotEmpty) _push(HikkaRoute(HikkaRouteKind.franchise, slug, seed: seed));
  }

  void openAnimeCharacters(String slug, {HikkaAnime? seed}) {
    if (slug.isNotEmpty) _push(HikkaRoute(HikkaRouteKind.animeCharacters, slug, seed: seed));
  }

  void openCollection(String reference, {HikkaCollection? seed}) {
    if (reference.isNotEmpty) _push(HikkaRoute(HikkaRouteKind.collection, reference, seed: seed));
  }

  /// Налаштування як сторінка поверх вкладки (телефон у портреті): нижня навігація лишається на місці
  void openSettings() => _push(HikkaRoute(HikkaRouteKind.settings, 'settings'));

  void openArticle(String slug, {HikkaArticle? seed}) {
    if (slug.isNotEmpty) _push(HikkaRoute(HikkaRouteKind.article, slug, seed: seed));
  }

  /// Стара локальна медіатека (відкрити файл, історія файлів, плейлисти): прихована в налаштуваннях розробника
  void openLocalLibrary() => _push(HikkaRoute(HikkaRouteKind.localLibrary, 'local'));

  /// Посилання з опису: сторінки Hikka відкриваються тут, решта — у браузері
  Future<void> openLink(String url) async {
    final target = HikkaLinkTarget.classify(url);
    switch (target.kind) {
      case HikkaLinkKind.anime:
        openAnime(target.slug);
      case HikkaLinkKind.character:
        openCharacter(target.slug);
      case HikkaLinkKind.collection:
        openCollection(target.slug);
      case HikkaLinkKind.article:
        openArticle(target.slug);
      case HikkaLinkKind.external:
        await urlOpener(target.url);
    }
  }

  final List<bool Function()> _backGuards = [];

  /// Додатковий обробник «Назад» (наприклад, відкрита панель фільтрів). Обробники викликаються від
  /// останнього доданого; той, що повернув true, поглинає натискання.
  void addBackGuard(bool Function() guard) => _backGuards.add(guard);

  void removeBackGuard(bool Function() guard) => _backGuards.remove(guard);

  /// Закриває верхню сторінку; на корені іншої вкладки повертає на «Головну».
  /// false — застосунок уже на «Головній», закривати нічого.
  bool back() {
    for (final guard in _backGuards.reversed.toList()) {
      if (guard()) return true;
    }
    if (_stack.isNotEmpty) {
      final closed = _stack.removeLast();
      AppLog.i('навігація', 'назад: закрито ${closed.kind.name} ${closed.slug}');
      notifyListeners();
      return true;
    }
    if (_main != MainTab.home) {
      AppLog.i('навігація', 'назад: повернення на «Головну»');
      _main = MainTab.home;
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Лише для тестів: повертає початковий стан
  @visibleForTesting
  void reset() {
    _main = MainTab.home;
    _tab = HikkaTab.overview;
    _stack.clear();
    _pendingFilters = null;
    _focusSearch = false;
    notifyListeners();
  }
}
