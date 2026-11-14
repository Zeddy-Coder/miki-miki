import 'package:flutter/foundation.dart';

import '../models/hikka_models.dart';
import 'app_log.dart';
import '../models/hikka_user_models.dart';
import 'hikka_auth.dart';
import 'hikka_markdown.dart';
import 'system_controls.dart';
import '../utils/platform_info.dart';

/// Main tabs of the app (bottom navigation on a phone, side menu on PC)
enum MainTab {
  home('Головна'),
  discover('Огляд'),
  lists('Списки'),
  profile('Профіль');

  final String label;
  const MainTab(this.label);
}

/// Sections of the "Огляд" tab
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

enum HikkaRouteKind { notifications, anime, character, person, animeStaff, franchise, animeCharacters, collection, article, user, localLibrary, settings }

/// A page opened over the root: anime, character, franchise, collection, article…
class HikkaRoute {
  static int _counter = 0;

  /// Unique number: widgets use it to tell two openings of the same page apart
  final int id = ++_counter;
  final HikkaRouteKind kind;

  /// Page identifier: anime / character / article slug, collection `reference`
  final String slug;

  /// Data from the list (`HikkaAnime` / `HikkaCharacter` / `HikkaCollection` / `HikkaArticle`): the page header
  /// appears immediately, before the API responds
  final Object? seed;

  /// Scroll position: on "Back" the page returns to where it was left
  double scroll = 0;

  /// Arbitrary page state (selected tab etc.)
  final Map<String, Object?> memo = {};

  HikkaRoute(this.kind, this.slug, {this.seed});

  @override
  String toString() => 'HikkaRoute(${kind.name}, $slug)';
}

/// App navigation: the main tab, the "Огляд" section and the stack of open pages. A custom stack (not
/// `Navigator`) is needed so pages stay inside the tabs with the bottom navigation, and "Back" on a phone
/// first closes a page, then returns to "Головна", rather than leaving the app.
class HikkaNav extends ChangeNotifier {
  /// Title page on a phone without a header: the banner goes under the status bar, "Back" is a round button over it
  static bool immersive(HikkaRoute? r) => AppPlatform.isMobile && r?.kind == HikkaRouteKind.anime;

  /// Shared instance (replaced in tests)
  static HikkaNav instance = HikkaNav();

  /// How many pages the stack remembers (the oldest are forgotten beyond that)
  static const int maxDepth = 40;

  MainTab _main = MainTab.home;

  /// Tab, "Огляд" tab and open pages before a jump to the catalog with ready conditions
  (MainTab, HikkaTab, List<HikkaRoute>)? _catalogReturn;
  HikkaTab _tab = HikkaTab.overview;
  final List<HikkaRoute> _stack = [];
  HikkaSearchFilters? _pendingFilters;
  bool _focusSearch = false;

  /// Opening external links (replaced in tests)
  Future<bool> Function(String url) urlOpener = SystemControls.openUrl;

  MainTab get main => _main;

  /// Open "Огляд" section (meaningful when [main] is `discover`)
  HikkaTab get tab => _tab;
  List<HikkaRoute> get routes => List.unmodifiable(_stack);
  HikkaRoute? get top => _stack.isEmpty ? null : _stack.last;
  bool get canGoBack => _stack.isNotEmpty || _main != MainTab.home;

  /// Switches the main tab; open pages are closed (a repeated tap on the current tab
  /// also returns to its root)
  void setMain(MainTab tab) {
    if (tab == _main && _stack.isEmpty) return;
    AppLog.i('навігація', 'вкладка «${tab.label}»');
    _main = tab;
    _catalogReturn = null;
    _stack.clear();
    notifyListeners();
  }

  /// Opens a "Огляд" section
  void setTab(HikkaTab tab) {
    if (_main == MainTab.discover && tab == _tab && _stack.isEmpty) return;
    AppLog.i('навігація', 'огляд: «${tab.label}»');
    _main = MainTab.discover;
    _tab = tab;
    _catalogReturn = null;
    _stack.clear();
    notifyListeners();
  }

  /// Catalog with ready conditions (the "Усі" button by a shelf on home, a genre on the anime page)
  void openCatalog(HikkaSearchFilters filters, {bool focusSearch = false}) {
    AppLog.i('навігація', 'відкрито каталог${focusSearch ? ' з пошуком' : ' з готовими умовами'}');
    // Where the catalog was opened from: "Back" returns there (to the title page, not to "Головна")
    if (!(_main == MainTab.discover && _tab == HikkaTab.anime && _stack.isEmpty)) {
      _catalogReturn = (_main, _tab, List.of(_stack));
    }
    _pendingFilters = filters;
    _focusSearch = focusSearch;
    _main = MainTab.discover;
    _tab = HikkaTab.anime;
    _stack.clear();
    notifyListeners();
  }

  /// "Головна" search bar: the catalog with the cursor in the search field
  void openSearch() => openCatalog(const HikkaSearchFilters(), focusSearch: true);

  /// Conditions the catalog was opened with; handed out once
  HikkaSearchFilters? takePendingFilters() {
    final f = _pendingFilters;
    _pendingFilters = null;
    return f;
  }

  bool get hasPendingFilters => _pendingFilters != null;

  /// Whether to put the cursor into the catalog search field right away; handed out once
  bool takeFocusSearch() {
    final v = _focusSearch;
    _focusSearch = false;
    return v;
  }

  bool get wantsSearchFocus => _focusSearch;

  void _push(HikkaRoute route) {
    final last = top;
    if (last != null && last.kind == route.kind && last.slug == route.slug) return; // double tap
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

  /// Notifications: a page over the tab
  void openNotifications() => _push(HikkaRoute(HikkaRouteKind.notifications, 'notifications'));

  void openPerson(String slug, {HikkaPerson? seed}) {
    if (slug.isNotEmpty) _push(HikkaRoute(HikkaRouteKind.person, slug, seed: seed));
  }

  void openAnimeStaff(String slug, {HikkaAnime? seed}) {
    if (slug.isNotEmpty) _push(HikkaRoute(HikkaRouteKind.animeStaff, slug, seed: seed));
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

  /// Settings as a page over the tab (phone in portrait): the bottom navigation stays in place
  /// "Оновити дані": resets the response cache and reloads open pages. Set by the catalog hub while it is alive.
  VoidCallback? refreshAll;

  /// The tab from which the settings page opens (see `AppSettingsDialog.tab*`)
  int settingsTab = 0;

  void openSettings({int tab = 0}) {
    settingsTab = tab;
    _push(HikkaRoute(HikkaRouteKind.settings, 'settings'));
  }

  void openArticle(String slug, {HikkaArticle? seed}) {
    if (slug.isNotEmpty) _push(HikkaRoute(HikkaRouteKind.article, slug, seed: seed));
  }

  /// The "Списки" tab to open from outside (profile counters): status index in the order of
  /// [HikkaListsPage] (0…4 is `HikkaWatchStatus.values`, 5 is favorites). The lists page takes the value and resets it to `null`.
  final ValueNotifier<int?> listsTab = ValueNotifier<int?>(null);

  /// Opens "Списки" on status [status] (`null` means the current one) or on "Улюблене"
  void openLists({HikkaWatchStatus? status, bool favourites = false}) {
    if (favourites) {
      listsTab.value = 5;
    } else if (status != null) {
      listsTab.value = status.index;
    }
    setMain(MainTab.lists);
  }

  /// Hikka user profile (`hikka.io/u/<name>`). One's own profile lives in the "Профіль" tab.
  void openUser(String username, {Object? seed}) {
    final name = username.trim();
    if (name.isEmpty) return;
    final me = HikkaAuth.instance;
    if (me.signedIn && me.username.toLowerCase() == name.toLowerCase()) {
      setMain(MainTab.profile);
      return;
    }
    _push(HikkaRoute(HikkaRouteKind.user, name, seed: seed));
  }

  /// The old local media library (open a file, file history, playlists): hidden in developer settings
  void openLocalLibrary() => _push(HikkaRoute(HikkaRouteKind.localLibrary, 'local'));

  /// Link from a description: Hikka pages open here, the rest in the browser
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
      case HikkaLinkKind.user:
        openUser(target.slug);
      case HikkaLinkKind.external:
        await urlOpener(target.url);
    }
  }

  final List<bool Function()> _backGuards = [];

  /// An extra "Back" handler (e.g. an open filter panel). Handlers are called from
  /// the last added; the one that returned true consumes the press.
  void addBackGuard(bool Function() guard) => _backGuards.add(guard);

  void removeBackGuard(bool Function() guard) => _backGuards.remove(guard);

  /// Closes the top page; at the root of another tab returns to "Головна".
  /// false: the app is already on "Головна", nothing to close.
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
    final back = _catalogReturn;
    if (back != null && _main == MainTab.discover && _tab == HikkaTab.anime) {
      AppLog.i('навігація', 'назад: повернення з каталогу');
      _catalogReturn = null;
      _main = back.$1;
      _tab = back.$2;
      _stack.addAll(back.$3);
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

  /// Tests only: returns the initial state
  @visibleForTesting
  void reset() {
    _main = MainTab.home;
    _tab = HikkaTab.overview;
    _stack.clear();
    _catalogReturn = null;
    _pendingFilters = null;
    _focusSearch = false;
    notifyListeners();
  }
}
