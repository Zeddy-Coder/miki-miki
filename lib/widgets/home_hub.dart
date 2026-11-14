import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../constants/app_identity.dart';
import '../services/app_updater.dart';
import '../services/hikka_nav.dart';
import '../services/ui_theme_service.dart';
import '../utils/platform_info.dart';
import 'app_animation_kit.dart';
import 'app_ui_kit.dart';
import 'hikka/hikka_hub.dart';
import 'local_library.dart';
import 'update_prompt.dart';

/// The Miki Miki app shell: four main tabs ("Головна", "Огляд", "Списки", "Профіль") with Hikka
/// content. A phone in portrait gets the bottom navigation, PC and wide screens a side menu. The content itself and open
/// pages live in [HikkaHub]; this widget only switches tabs and gives the player screen a "Back" handler.
class HomeHub extends StatefulWidget {
  /// Height of the narrow-screen bottom navigation (phone in portrait), dp
  static const double bottomNavHeight = 64;

  /// The main screen's "Back" button handler: true means the press was consumed (a page or panel closed,
  /// returned from another tab to "Головна"). Set while the screen is in place; the player screen calls it.
  static bool Function()? backHandler;

  @visibleForTesting
  static void debugReset() {
    backHandler = null;
  }

  /// Phone in portrait: the bottom navigation replaces the side menu, and the cards stack in a column
  static bool isCompact(BuildContext context) =>
      AppPlatform.isMobile && AppLayout(MediaQuery.sizeOf(context)).isCompactWidth;

  /// The main tab icon (bottom navigation and side menu)
  static IconData iconOf(MainTab tab) => switch (tab) {
        MainTab.home => Symbols.home_rounded,
        MainTab.discover => Symbols.explore_rounded,
        MainTab.lists => Symbols.bookmarks_rounded,
        MainTab.profile => Symbols.account_circle_rounded,
      };

  final double scale;
  final ValueChanged<String> onOpenFile;
  final ValueChanged<List<String>> onOpenMultipleFiles;
  final void Function(List<Map<String, String>> items, int startIndex) onOpenQueue;

  /// App settings; [tab] opens the needed tab at once (see `AppSettingsDialog.tab*`)
  final void Function({int? tab}) onOpenSettings;

  /// Extra bottom padding in lists (phone: so the collapsed player does not cover the end of the list)
  final double reserveBottom;

  /// Settings as a page inside the app (phone, portrait). Without it, settings open as a window
  final WidgetBuilder? settingsBuilder;

  const HomeHub({
    super.key,
    required this.scale,
    required this.onOpenFile,
    required this.onOpenMultipleFiles,
    required this.onOpenQueue,
    required this.onOpenSettings,
    this.reserveBottom = 0,
    this.settingsBuilder,
  });

  @override
  State<HomeHub> createState() => _HomeHubState();
}

class _HomeHubState extends State<HomeHub> {
  final HikkaNav _nav = HikkaNav.instance;

  @override
  void initState() {
    super.initState();
    HomeHub.backHandler = _handleBack;
    _nav.addListener(_onNav);
    AppUpdater.instance.state.addListener(_maybePromptUpdate);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybePromptUpdate());
  }

  /// The update window is shown once per version per launch: when a newer version is known that was not skipped
  static String _promptedVersion = '';

  void _maybePromptUpdate() {
    if (!mounted) return;
    final st = AppUpdater.instance.state.value;
    if (st is! UpdateAvailable || !AppUpdater.instance.shouldPrompt(st.info) || _promptedVersion == st.info.version) return;
    _promptedVersion = st.info.version;
    UpdatePrompt.show(context, scale: widget.scale, info: st.info);
  }

  @override
  void dispose() {
    _nav.removeListener(_onNav);
    AppUpdater.instance.state.removeListener(_maybePromptUpdate);
    if (HomeHub.backHandler == _handleBack) HomeHub.backHandler = null;
    super.dispose();
  }

  void _onNav() {
    if (mounted) setState(() {});
  }

  /// "Back": first closes an open page or panel, from another tab's root returns to "Головна".
  /// false: already on "Головна": the player screen decides whether to exit the app.
  bool _handleBack() => _nav.back();

  Widget _localLibrary(BuildContext context) => LocalLibrary(
        scale: widget.scale,
        onOpenFile: widget.onOpenFile,
        onOpenMultipleFiles: widget.onOpenMultipleFiles,
        onOpenQueue: widget.onOpenQueue,
        reserveBottom: widget.reserveBottom,
      );

  @override
  Widget build(BuildContext context) {
    final scale = widget.scale;
    final compact = HomeHub.isCompact(context);
    // Phone: the camera cutout and system bars must not cover the content
    final EdgeInsets safe = AppPlatform.isMobile ? MediaQuery.paddingOf(context) : EdgeInsets.zero;
    // The title page lays itself under the status bar
    final double topPad = HikkaNav.immersive(_nav.top) ? 0 : safe.top;

    final content = HikkaHub(
      scale: scale,
      bottomInset: widget.reserveBottom,
      onOpenSettings: ({int? tab}) {
        // Phone in portrait: settings (from the needed section if required) are a page over the tab, navigation visible; otherwise a window
        if (compact && widget.settingsBuilder != null) {
          _nav.openSettings(tab: tab ?? 0);
        } else {
          widget.onOpenSettings(tab: tab);
        }
      },
      settingsBuilder: widget.settingsBuilder,
      localLibraryBuilder: _localLibrary,
    );

    if (compact) {
      return Container(
        color: uiTheme.bgPrimary,
        padding: EdgeInsets.only(top: topPad, left: safe.left, right: safe.right),
        child: Column(
          children: [
            Expanded(child: content),
            // With the keyboard open the navigation is not needed: otherwise it rises with it and covers the content
            if (MediaQuery.viewInsetsOf(context).bottom == 0) _buildBottomNav(safe.bottom),
          ],
        ),
      );
    }

    return Container(
      color: uiTheme.bgPrimary,
      padding: EdgeInsets.only(top: topPad, left: safe.left, right: safe.right, bottom: safe.bottom),
      child: Row(
        children: [
          _buildSidebar(scale),
          Expanded(child: content),
        ],
      ),
    );
  }

  // ── Bottom navigation (phone, portrait) ─────────────────────────────────────

  Widget _buildBottomNav(double bottomInset) {
    Widget item(MainTab tab) {
      final bool selected = _nav.main == tab;
      return Expanded(
        child: Semantics(
          button: true,
          selected: selected,
          label: tab.label,
          excludeSemantics: true,
          child: InkWell(
            onTap: () => _nav.setMain(tab),
            splashColor: Colors.transparent,
            highlightColor: uiTheme.touchHighlight,
            child: SizedBox(
              height: HomeHub.bottomNavHeight,
              // 0 → 1 on selection: the pill grows from the center, the icon and label smoothly change color, the icon "bounces"
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(end: selected ? 1 : 0),
                duration: AppAnim.medium,
                curve: AppAnim.easeOut,
                builder: (context, t, _) {
                  final Color fg = Color.lerp(uiTheme.textMuted, uiTheme.accentColor, t)!;
                  final double pop = 1 + 0.14 * math.sin(math.pi * t.clamp(0.0, 1.0));
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 58,
                        height: 30,
                        alignment: Alignment.center,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              width: 22 + 36 * t,
                              height: 30,
                              decoration: BoxDecoration(
                                color: uiTheme.accentWash.withValues(alpha: uiTheme.accentWash.a * t),
                                borderRadius: uiTheme.borderRadius(15),
                              ),
                            ),
                            Transform.scale(
                              scale: pop,
                              child: Icon(HomeHub.iconOf(tab), color: fg, size: 25, fill: t > 0.5 ? 1 : 0, weight: 300, opticalSize: 24),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 3),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            tab.label,
                            maxLines: 1,
                            style: TextStyle(fontFamily: 'Arial', color: fg, fontSize: 11.5, fontWeight: selected ? FontWeight.w700 : FontWeight.w500),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: EdgeInsets.only(bottom: bottomInset),
      decoration: BoxDecoration(
        color: uiTheme.bgSidebar,
        border: Border(top: BorderSide(color: uiTheme.borderSubtle, width: 1.0)),
      ),
      child: Row(children: [for (final tab in MainTab.values) item(tab)]),
    );
  }

  // ── Side menu (PC, wide screens) ─────────────────────────────────────────

  Widget _buildSidebar(double scale) {
    return AppSidebar(
      scale: scale,
      header: Row(
        children: [
          // A temporary mark: a monogram. The mascot (a chibi mouse) will replace it when ready
          Container(
            width: 32 * scale,
            height: 32 * scale,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: uiTheme.accentColor, borderRadius: uiTheme.borderRadius(9 * scale)),
            child: Text(
              'M',
              style: TextStyle(fontFamily: 'Arial', color: uiTheme.onAccent, fontSize: 18 * scale, fontWeight: FontWeight.w800, height: 1),
            ),
          ),
          SizedBox(width: 10 * scale),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppIdentity.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: 'Arial', color: uiTheme.textPrimary, fontSize: 16 * scale, fontWeight: FontWeight.bold),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    AppIdentity.tagline,
                    maxLines: 1,
                    style: TextStyle(fontFamily: 'Arial', color: uiTheme.textDarkMuted, fontSize: 11 * scale),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppNavItem(
            scale: scale,
            icon: Symbols.settings_rounded,
            label: 'Налаштування',
            onTap: () => widget.onOpenSettings(),
          ),
          Padding(
            padding: EdgeInsets.only(left: 8 * scale, top: 4 * scale),
            child: Text(
              'v${AppIdentity.version}',
              style: TextStyle(fontFamily: 'Arial', color: uiTheme.textDarkMuted, fontSize: 11 * scale),
            ),
          ),
        ],
      ),
      children: [
        for (final tab in MainTab.values)
          AppNavItem(
            scale: scale,
            icon: HomeHub.iconOf(tab),
            label: tab.label,
            isSelected: _nav.main == tab,
            onTap: () => _nav.setMain(tab),
          ),
      ],
    );
  }
}
