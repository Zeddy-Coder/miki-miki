import '../../services/app_layers.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../services/hikka_api.dart';
import '../../services/hikka_nav.dart';
import '../../services/hikka_prefs.dart';
import '../../services/ui_theme_service.dart';
import '../../utils/platform_info.dart';
import '../app_animation_kit.dart';
import '../app_ui_kit.dart';
import '../line_icons.dart';
import '../downloads/downloads_page.dart';
import 'hikka_admin_page.dart';
import 'hikka_anime_characters_page.dart';
import 'hikka_anime_page.dart';
import 'hikka_article_page.dart';
import 'hikka_character_page.dart';
import 'hikka_notifications_page.dart';
import 'hikka_person_page.dart';
import 'hikka_collection_page.dart';
import 'hikka_common.dart';
import 'hikka_page_kit.dart';
import 'hikka_discover_page.dart';
import 'hikka_franchise_page.dart';
import 'hikka_home_page.dart';
import 'hikka_lists_page.dart';
import 'hikka_profile_page.dart';
import 'hikka_user_profile.dart';

/// Hikka-based app content: four main tabs ("Головна", "Огляд", "Списки", "Профіль"; the bottom navigation
/// or the `HomeHub` side menu switches them) and a stack of open pages over them (anime, character,
/// collection, article…). Open tabs are not destroyed, so search and scroll stay in place.
class HikkaHub extends StatefulWidget {
  final double scale;

  /// Bottom padding for the collapsed player
  final double bottomInset;

  /// App settings (opened directly on the needed tab if needed)
  final void Function({int? tab}) onOpenSettings;

  /// Local media library page (hidden; opens from "Профіль" when enabled in "Розробник")
  final WidgetBuilder localLibraryBuilder;

  /// Contents of the "Налаштування" tab (phone in portrait)
  final WidgetBuilder? settingsBuilder;

  const HikkaHub({
    super.key,
    required this.scale,
    required this.onOpenSettings,
    required this.localLibraryBuilder,
    this.settingsBuilder,
    this.bottomInset = 0,
  });

  @override
  State<HikkaHub> createState() => _HikkaHubState();
}

class _HikkaHubState extends State<HikkaHub> {
  final HikkaNav _nav = HikkaNav.instance;
  final HikkaPrefs _prefs = HikkaPrefs.instance;

  /// Tabs already opened: we do not destroy them so search and scroll stay in place
  final Set<MainTab> _mounted = {};

  /// Grows when the user asks to refresh tab data
  int _refresh = 0;

  /// The same for pages opened over them (the "Оновити" button in their heading does not touch the tabs underneath)
  int _routeRefresh = 0;

  /// How far the title page under the status bar is scrolled: the veil behind the clock appears only once the content goes under it
  final ValueNotifier<double> _immersiveScroll = ValueNotifier(0);

  /// The tab pages, built once per set of inputs ([_rootKey]). Opening a page or switching a tab rebuilds the hub,
  /// and handing Flutter the very same widget keeps it from rebuilding the hidden pages underneath (on a phone that
  /// was ~2 000 widgets per tap: the "Головна" shelves while the title page opened)
  final Map<MainTab, (Object, Widget)> _roots = {};

  /// Bumped by the catalog settings and the theme: the tab pages read them while building, so then all of them rebuild
  int _prefsTick = 0;
  int _themeTick = 0;

  double get _scale => widget.scale;

  Object get _rootKey => (_scale, widget.bottomInset, _refresh, _prefsTick, _themeTick);

  @override
  void initState() {
    super.initState();
    _mounted.add(_nav.main);
    _nav.addListener(_onChanged);
    _prefs.addListener(_onPrefs);
    uiTheme.addListener(_onTheme);
    _nav.refreshAll = _refreshAll;
  }

  @override
  void dispose() {
    _nav.removeListener(_onChanged);
    _prefs.removeListener(_onPrefs);
    uiTheme.removeListener(_onTheme);
    if (_nav.refreshAll == _refreshAll) _nav.refreshAll = null;
    _immersiveScroll.dispose();
    super.dispose();
  }

  void _onPrefs() {
    _prefsTick++;
    _onChanged();
  }

  void _onTheme() {
    if (!mounted) return;
    setState(() => _themeTick++);
  }

  /// The settings opener handed to the pages: one tear-off for the hub's life, so a new callback from the shell does not
  /// count as a change of the cached pages
  void _openSettings({int? tab}) => widget.onOpenSettings(tab: tab);

  MainTab _shownMain = MainTab.values.first;
  double _tabDir = 1;

  void _onChanged() {
    if (!mounted) return;
    if (_nav.main != _shownMain) {
      _tabDir = _nav.main.index > _shownMain.index ? 1 : -1;
      _shownMain = _nav.main;
    }
    setState(() => _mounted.add(_nav.main));
  }

  /// Forgets what the page loaded, except the 18+ permission (otherwise "Оновити" would close it again)
  static void _forget(HikkaRoute r) {
    final revealed = r.memo['revealed'];
    r.memo.clear();
    if (revealed != null) r.memo['revealed'] = revealed;
  }

  void _refreshAll() {
    HikkaApi.instance.clearCache();
    // Open pages forget what they loaded and fetch everything anew
    for (final r in _nav.routes) {
      _forget(r);
    }
    setState(() {
      _refresh++;
      _routeRefresh++;
    });
  }

  /// Pull-down refresh: the indicator stays for a moment while pages start loading
  Future<void> _pullRefresh() async {
    _refreshAll();
    await Future<void>.delayed(const Duration(milliseconds: 700));
  }

  void _refreshRoute() {
    final r = _nav.top;
    if (r == null) return;
    HikkaApi.instance.clearCache();
    _forget(r);
    setState(() => _routeRefresh++);
  }

  // ── Open page heading ───────────────────────────────────────────

  static String _routeTitle(HikkaRoute r) => switch (r.kind) {
        HikkaRouteKind.anime => 'Аніме',
        HikkaRouteKind.character => 'Персонаж',
        HikkaRouteKind.person => 'Людина',
        HikkaRouteKind.animeStaff => 'Автори',
        HikkaRouteKind.franchise => 'Франшиза',
        HikkaRouteKind.animeCharacters => 'Персонажі',
        HikkaRouteKind.collection => 'Колекція',
        HikkaRouteKind.article => 'Стаття',
        HikkaRouteKind.user => 'Користувач',
        HikkaRouteKind.notifications => 'Сповіщення',
        HikkaRouteKind.localLibrary => 'Локальна медіатека',
        HikkaRouteKind.settings => 'Налаштування',
        HikkaRouteKind.admin => 'Адмін-панель',
        HikkaRouteKind.downloads || HikkaRouteKind.downloadShelf => 'Завантаження',
      };

  /// Page address on hikka.io; `null` means the site has no corresponding page
  static String? _routeUrl(HikkaRoute r) => switch (r.kind) {
        HikkaRouteKind.character => 'https://hikka.io/characters/${Uri.encodeComponent(r.slug)}',
        HikkaRouteKind.animeCharacters => 'https://hikka.io/anime/${Uri.encodeComponent(r.slug)}/characters',
        HikkaRouteKind.animeStaff => 'https://hikka.io/anime/${Uri.encodeComponent(r.slug)}/staff',
        HikkaRouteKind.person => 'https://hikka.io/people/${Uri.encodeComponent(r.slug)}',
        HikkaRouteKind.collection => 'https://hikka.io/collections/${Uri.encodeComponent(r.slug)}',
        HikkaRouteKind.article => 'https://hikka.io/articles/${Uri.encodeComponent(r.slug)}',
        HikkaRouteKind.user => 'https://hikka.io/u/${Uri.encodeComponent(r.slug)}',
        HikkaRouteKind.localLibrary ||
        HikkaRouteKind.settings ||
        HikkaRouteKind.notifications ||
        HikkaRouteKind.admin ||
        HikkaRouteKind.downloads ||
        HikkaRouteKind.downloadShelf =>
          null,
        _ => 'https://hikka.io/anime/${Uri.encodeComponent(r.slug)}',
      };

  /// Pages of the app itself (no Hikka data to refresh): an ordinary "Back" row that does not hide on scrolling
  static bool _local(HikkaRoute r) => switch (r.kind) {
        HikkaRouteKind.localLibrary || HikkaRouteKind.settings || HikkaRouteKind.admin || HikkaRouteKind.downloads || HikkaRouteKind.downloadShelf => true,
        _ => false,
      };

  Widget _routeBar(HikkaRoute r) {
    final url = _routeUrl(r);
    final local = _local(r);
    // Only the kind of the page: the page itself starts with the name, title or anime it is about
    return HikkaBackBar(
      scale: _scale,
      title: _routeTitle(r),
      onBack: _nav.back,
      actions: [
        // On a phone a pull-down refreshes the page
        if (!local && !AppPlatform.isMobile) HikkaLineButton(scale: _scale, icon: LineIcon.refresh, tooltip: 'Оновити', iconSize: 21, onTap: _refreshRoute),
        if (url != null) HikkaLineButton(scale: _scale, icon: LineIcon.openOut, tooltip: 'Відкрити на hikka.io', iconSize: 21, onTap: () => _nav.urlOpener(url)),
      ],
    );
  }

  /// Round "Back" over the banner: a darkened circle so it is visible on any image. The circle is [floatingButtonSize],
  /// the touch area around it is at least 48 dp
  Widget _floatingBack() {
    final size = floatingButtonSize(_scale);
    final hit = floatingButtonHit(_scale);
    return Semantics(
      button: true,
      label: 'Назад',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _nav.back,
        child: SizedBox(
          width: hit,
          height: hit,
          child: Center(
            child: Material(
              color: Colors.black.withValues(alpha: .55),
              shape: RoundedRectangleBorder(borderRadius: uiTheme.borderRadius(size / 2)),
              child: InkWell(
                key: const ValueKey('anime-floating-back'),
                customBorder: RoundedRectangleBorder(borderRadius: uiTheme.borderRadius(size / 2)),
                onTap: _nav.back,
                child: SizedBox(
                  width: size,
                  height: size,
                  child: Center(child: LineIconView(LineIcon.back, size: 22 * _scale, color: Colors.white)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Pages ───────────────────────────────────────────────────────────────

  Widget _root(MainTab tab) {
    final scale = _scale;
    final inset = widget.bottomInset;
    return switch (tab) {
      MainTab.home => HikkaHomePage(scale: scale, bottomInset: inset, refreshToken: _refresh, onRefresh: _pullRefresh),
      MainTab.discover => HikkaDiscoverPage(scale: scale, bottomInset: inset, refreshToken: _refresh, onRefresh: _refreshAll),
      MainTab.lists => HikkaListsPage(scale: scale, bottomInset: inset),
      MainTab.profile => HikkaProfilePage(
          scale: scale,
          bottomInset: inset,
          refreshToken: _refresh,
          onRefresh: _pullRefresh,
          onOpenSettings: _openSettings,
        ),
    };
  }

  /// [_root] from the cache while its inputs are the same (see [_roots])
  Widget _cachedRoot(MainTab tab) {
    final key = _rootKey;
    final hit = _roots[tab];
    if (hit != null && hit.$1 == key) return hit.$2;
    final page = _root(tab);
    _roots[tab] = (key, page);
    return page;
  }

  Widget _withRouteRefresh(HikkaRoute r) {
    if (!AppPlatform.isMobile || _local(r)) return _page(r);
    return AppPullToRefresh(onRefresh: () async => _refreshRoute(), child: _page(r));
  }

  Widget _page(HikkaRoute r) {
    final scale = _scale;
    final inset = widget.bottomInset;
    return switch (r.kind) {
      HikkaRouteKind.anime => HikkaAnimePage(route: r, scale: scale, bottomInset: inset),
      HikkaRouteKind.character => HikkaCharacterPage(route: r, scale: scale, bottomInset: inset),
      HikkaRouteKind.person => HikkaPersonPage(route: r, scale: scale, bottomInset: inset),
      HikkaRouteKind.animeStaff => HikkaAnimeStaffPage(route: r, scale: scale, bottomInset: inset),
      HikkaRouteKind.franchise => HikkaFranchisePage(route: r, scale: scale, bottomInset: inset),
      HikkaRouteKind.animeCharacters => HikkaAnimeCharactersPage(route: r, scale: scale, bottomInset: inset),
      HikkaRouteKind.collection => HikkaCollectionPage(route: r, scale: scale, bottomInset: inset),
      HikkaRouteKind.article => HikkaArticlePage(route: r, scale: scale, bottomInset: inset),
      HikkaRouteKind.user => HikkaUserPage(route: r, scale: scale, bottomInset: inset),
      HikkaRouteKind.notifications => HikkaNotificationsPage(route: r, scale: scale, bottomInset: inset),
      HikkaRouteKind.localLibrary => widget.localLibraryBuilder(context),
      HikkaRouteKind.settings => AppLayerClaim(child: widget.settingsBuilder?.call(context) ?? const SizedBox.shrink()),
      HikkaRouteKind.admin => HikkaAdminPage(route: r, scale: scale, bottomInset: inset),
      HikkaRouteKind.downloads => DownloadsPage(route: r, scale: scale, bottomInset: inset),
      HikkaRouteKind.downloadShelf => DownloadShelfPage(route: r, scale: scale, bottomInset: inset),
    };
  }

  @override
  Widget build(BuildContext context) {
    final top = _nav.top;
    // Scrolling pages have an overlay header that hides on scrolling down; the rest (library, settings) have an ordinary row
    final immersive = HikkaNav.immersive(top);
    final overlayBar = top != null && !immersive && !_local(top);

    return Listener(
      // The side "Back" mouse button works as in a browser
      onPointerDown: (e) {
        if (e.kind == PointerDeviceKind.mouse && (e.buttons & kBackMouseButton) != 0) _nav.back();
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Tab headings live in the tabs themselves; here only the "Back" row of an open page
          AppFadeSwitcher(
            duration: AppAnim.fast,
            // The "Back" row disappears and the tab under it takes its place at once, not jumping after the fade
            overlayPrevious: true,
            child: KeyedSubtree(
              key: ValueKey(top == null || overlayBar || immersive ? 'no-bar' : 'route-bar'),
              child: top == null || overlayBar || immersive ? const SizedBox.shrink() : _routeBar(top),
            ),
          ),
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                for (final tab in MainTab.values)
                  if (_mounted.contains(tab))
                    // Keys are needed so that when a new tab appears the already opened ones do not lose state
                    Offstage(
                      key: ValueKey('tab-${tab.name}'),
                      offstage: top != null || _nav.main != tab,
                      // A new tab slides in from the transition side and fades in (opening a page over it does not touch this)
                      child: HikkaTabEnter(
                        active: _nav.main == tab,
                        direction: _tabDir,
                        animateOnMount: _mounted.length > 1,
                        child: TickerMode(
                          enabled: top == null && _nav.main == tab,
                          child: _cachedRoot(tab),
                        ),
                      ),
                    ),
                AppFadeSwitcher(
                  key: const ValueKey('route-layer'),
                  expand: true,
                  duration: AppAnim.normal,
                  child: top == null
                      ? const SizedBox.shrink(key: ValueKey('no-route'))
                      : KeyedSubtree(
                          key: ValueKey('route-${top.id}-$_routeRefresh'),
                          child: ColoredBox(
                            color: uiTheme.bgPrimary,
                            child: overlayBar
                                ? HikkaCollapsingHeader(header: _routeBar(top), body: _withRouteRefresh(top))
                                : immersive
                                    ? Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          NotificationListener<ScrollMetricsNotification>(
                                            onNotification: (n) {
                                              if (n.depth == 0 && n.metrics.axis == Axis.vertical) _immersiveScroll.value = n.metrics.pixels;
                                              return false;
                                            },
                                            child: NotificationListener<ScrollUpdateNotification>(
                                              onNotification: (n) {
                                                if (n.depth == 0 && n.metrics.axis == Axis.vertical) _immersiveScroll.value = n.metrics.pixels;
                                                return false;
                                              },
                                              child: _withRouteRefresh(top),
                                            ),
                                          ),
                                          // Content that scrolls under the status bar does not blend with the clock; at the very top the banner
                                          // shows through as is
                                          Positioned(
                                            left: 0,
                                            right: 0,
                                            top: 0,
                                            height: MediaQuery.paddingOf(context).top + 6,
                                            child: IgnorePointer(
                                              child: ValueListenableBuilder<double>(
                                                valueListenable: _immersiveScroll,
                                                builder: (context, y, child) => Opacity(opacity: (y / (90 * _scale)).clamp(0.0, 1.0), child: child),
                                                child: DecoratedBox(
                                                  decoration: BoxDecoration(
                                                    gradient: LinearGradient(
                                                      begin: Alignment.topCenter,
                                                      end: Alignment.bottomCenter,
                                                      colors: [uiTheme.bgPrimary.withValues(alpha: .92), uiTheme.bgPrimary.withValues(alpha: 0)],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          Positioned(
                                            left: floatingButtonInset(context, _scale),
                                            top: floatingButtonTop(context, _scale),
                                            child: _floatingBack(),
                                          ),
                                        ],
                                      )
                                    : _withRouteRefresh(top),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
