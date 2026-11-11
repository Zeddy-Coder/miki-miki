import '../../services/app_layers.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../models/hikka_models.dart';
import '../../services/hikka_api.dart';
import '../../services/hikka_nav.dart';
import '../../services/hikka_prefs.dart';
import '../../services/ui_theme_service.dart';
import '../../utils/platform_info.dart';
import '../app_animation_kit.dart';
import '../app_ui_kit.dart';
import 'hikka_anime_characters_page.dart';
import 'hikka_anime_page.dart';
import 'hikka_article_page.dart';
import 'hikka_character_page.dart';
import 'hikka_collection_page.dart';
import 'hikka_common.dart';
import 'hikka_page_kit.dart';
import 'hikka_discover_page.dart';
import 'hikka_franchise_page.dart';
import 'hikka_home_page.dart';
import 'hikka_lists_page.dart';
import 'hikka_profile_page.dart';

/// Вміст застосунку на основі Hikka: чотири головні вкладки («Головна», «Огляд», «Списки», «Профіль» — їх
/// перемикає нижня навігація чи бічне меню `HomeHub`) і стек відкритих сторінок поверх них (аніме, персонаж,
/// колекція, стаття…). Відкриті вкладки не руйнуються, тож пошук і прокрутка лишаються на місці.
class HikkaHub extends StatefulWidget {
  final double scale;

  /// Відступ знизу під згорнутий плеєр
  final double bottomInset;

  /// Налаштування застосунку (за потреби — відразу з потрібної вкладки)
  final void Function({int? tab}) onOpenSettings;

  /// Сторінка локальної медіатеки (прихована; відкривається з «Профілю», коли ввімкнена в «Розробник»)
  final WidgetBuilder localLibraryBuilder;

  /// Вміст вкладки «Налаштування» (телефон у портреті)
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

  /// Вкладки, які вже відкривали: їх не руйнуємо, щоб пошук і прокрутка лишались на місці
  final Set<MainTab> _mounted = {};

  /// Збільшується, коли користувач просить оновити дані вкладок
  int _refresh = 0;

  /// Те саме для відкритих поверх сторінок (кнопка «Оновити» у їхньому заголовку не чіпає вкладки під ними)
  int _routeRefresh = 0;

  double get _scale => widget.scale;

  @override
  void initState() {
    super.initState();
    _mounted.add(_nav.main);
    _nav.addListener(_onChanged);
    _prefs.addListener(_onChanged);
    _nav.refreshAll = _refreshAll;
  }

  @override
  void dispose() {
    _nav.removeListener(_onChanged);
    _prefs.removeListener(_onChanged);
    if (_nav.refreshAll == _refreshAll) _nav.refreshAll = null;
    super.dispose();
  }

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

  /// Забуває завантажене сторінкою, крім дозволу показати 18+ (інакше «Оновити» знову закривало б її)
  static void _forget(HikkaRoute r) {
    final revealed = r.memo['revealed'];
    r.memo.clear();
    if (revealed != null) r.memo['revealed'] = revealed;
  }

  void _refreshAll() {
    HikkaApi.instance.clearCache();
    // Відкриті сторінки забувають завантажене й підтягують усе заново
    for (final r in _nav.routes) {
      _forget(r);
    }
    setState(() {
      _refresh++;
      _routeRefresh++;
    });
  }

  /// Оновлення потягом вниз: індикатор лишається на мить, поки сторінки починають вантажитись
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

  // ── Заголовок відкритої сторінки ───────────────────────────────────────────

  static String _routeTitle(HikkaRoute r) => switch (r.kind) {
        HikkaRouteKind.anime => 'Аніме',
        HikkaRouteKind.character => 'Персонаж',
        HikkaRouteKind.franchise => 'Франшиза',
        HikkaRouteKind.animeCharacters => 'Персонажі',
        HikkaRouteKind.collection => 'Колекція',
        HikkaRouteKind.article => 'Стаття',
        HikkaRouteKind.localLibrary => 'Локальна медіатека',
        HikkaRouteKind.settings => 'Налаштування',
      };

  String? _routeSubtitle(HikkaRoute r) {
    final lang = _prefs.titleLang;
    switch (r.kind) {
      case HikkaRouteKind.character:
        final c = r.memo['character'] ?? r.seed;
        return c is HikkaCharacter ? c.name : null;
      case HikkaRouteKind.collection:
        final c = r.memo['collection'] ?? r.seed;
        return c is HikkaCollection ? c.title : null;
      case HikkaRouteKind.article:
        final a = r.memo['article'] ?? r.seed;
        return a is HikkaArticle ? a.title : null;
      case HikkaRouteKind.localLibrary || HikkaRouteKind.settings:
        return null;
      case HikkaRouteKind.anime || HikkaRouteKind.franchise || HikkaRouteKind.animeCharacters:
        final a = r.memo['anime'] ?? r.seed;
        return a is HikkaAnime ? a.title(lang) : null;
    }
  }

  /// Адреса сторінки на hikka.io; `null` — відповідної сторінки на сайті немає
  static String? _routeUrl(HikkaRoute r) => switch (r.kind) {
        HikkaRouteKind.character => 'https://hikka.io/characters/${Uri.encodeComponent(r.slug)}',
        HikkaRouteKind.animeCharacters => 'https://hikka.io/anime/${Uri.encodeComponent(r.slug)}/characters',
        HikkaRouteKind.collection => 'https://hikka.io/collections/${Uri.encodeComponent(r.slug)}',
        HikkaRouteKind.article => 'https://hikka.io/articles/${Uri.encodeComponent(r.slug)}',
        HikkaRouteKind.localLibrary || HikkaRouteKind.settings => null,
        _ => 'https://hikka.io/anime/${Uri.encodeComponent(r.slug)}',
      };

  Widget _routeBar(HikkaRoute r) {
    final url = _routeUrl(r);
    final local = r.kind == HikkaRouteKind.localLibrary || r.kind == HikkaRouteKind.settings;
    return HikkaBackBar(
      scale: _scale,
      title: _routeTitle(r),
      subtitle: _routeSubtitle(r),
      onBack: _nav.back,
      actions: [
        // На телефоні сторінку оновлює потяг вниз
        if (!local && !AppPlatform.isMobile) HikkaIconButton(icon: Symbols.refresh_rounded, tooltip: 'Оновити', scale: _scale, onTap: _refreshRoute),
        if (url != null)
          HikkaIconButton(icon: Symbols.open_in_new_rounded, tooltip: 'Відкрити на hikka.io', scale: _scale, onTap: () => _nav.urlOpener(url)),
      ],
    );
  }

  // ── Сторінки ───────────────────────────────────────────────────────────────

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
          onOpenSettings: widget.onOpenSettings,
        ),
    };
  }

  Widget _withRouteRefresh(HikkaRoute r) {
    final local = r.kind == HikkaRouteKind.localLibrary || r.kind == HikkaRouteKind.settings;
    if (!AppPlatform.isMobile || local) return _page(r);
    return AppPullToRefresh(onRefresh: () async => _refreshRoute(), child: _page(r));
  }

  Widget _page(HikkaRoute r) {
    final scale = _scale;
    final inset = widget.bottomInset;
    return switch (r.kind) {
      HikkaRouteKind.anime => HikkaAnimePage(route: r, scale: scale, bottomInset: inset),
      HikkaRouteKind.character => HikkaCharacterPage(route: r, scale: scale, bottomInset: inset),
      HikkaRouteKind.franchise => HikkaFranchisePage(route: r, scale: scale, bottomInset: inset),
      HikkaRouteKind.animeCharacters => HikkaAnimeCharactersPage(route: r, scale: scale, bottomInset: inset),
      HikkaRouteKind.collection => HikkaCollectionPage(route: r, scale: scale, bottomInset: inset),
      HikkaRouteKind.article => HikkaArticlePage(route: r, scale: scale, bottomInset: inset),
      HikkaRouteKind.localLibrary => widget.localLibraryBuilder(context),
      HikkaRouteKind.settings => AppLayerClaim(child: widget.settingsBuilder?.call(context) ?? const SizedBox.shrink()),
    };
  }

  @override
  Widget build(BuildContext context) {
    final top = _nav.top;
    // Сторінки з прокруткою мають шапку-накладку, що ховається при прокрутці вниз; решта (бібліотека, налаштування) — звичайний рядок
    final overlayBar = top != null && top.kind != HikkaRouteKind.localLibrary && top.kind != HikkaRouteKind.settings;

    return Listener(
      // Бокова кнопка миші «Назад» працює як у браузері
      onPointerDown: (e) {
        if (e.kind == PointerDeviceKind.mouse && (e.buttons & kBackMouseButton) != 0) _nav.back();
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Заголовки вкладок живуть у самих вкладках; тут лише рядок «Назад» відкритої сторінки
          AppFadeSwitcher(
            duration: AppAnim.fast,
            child: KeyedSubtree(
              key: ValueKey(top == null || overlayBar ? 'no-bar' : 'route-bar'),
              child: top == null || overlayBar ? const SizedBox.shrink() : _routeBar(top),
            ),
          ),
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                for (final tab in MainTab.values)
                  if (_mounted.contains(tab))
                    // Ключі потрібні, щоб при появі нової вкладки вже відкриті не втрачали стан
                    Offstage(
                      key: ValueKey('tab-${tab.name}'),
                      offstage: top != null || _nav.main != tab,
                      // Нова вкладка виїжджає з боку переходу й проявляється (відкриття сторінки поверх цього не чіпає)
                      child: HikkaTabEnter(
                        active: _nav.main == tab,
                        direction: _tabDir,
                        animateOnMount: _mounted.length > 1,
                        child: TickerMode(
                          enabled: top == null && _nav.main == tab,
                          child: _root(tab),
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
