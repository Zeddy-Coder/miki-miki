import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../constants/app_identity.dart';
import '../services/hikka_nav.dart';
import '../services/ui_theme_service.dart';
import '../utils/platform_info.dart';
import 'app_animation_kit.dart';
import 'app_ui_kit.dart';
import 'hikka/hikka_hub.dart';
import 'local_library.dart';

/// Оболонка застосунку Miki Miki: чотири головні вкладки («Головна», «Огляд», «Списки», «Профіль») із вмістом
/// Hikka. Телефон у портреті отримує нижню навігацію, ПК і широкі екрани — бічне меню. Сам вміст і відкриті
/// сторінки живуть у [HikkaHub]; цей віджет лише перемикає вкладки та віддає екрану плеєра обробник «Назад».
class HomeHub extends StatefulWidget {
  /// Висота нижньої навігації вузького екрана (телефон у портреті), dp
  static const double bottomNavHeight = 64;

  /// Обробник кнопки «Назад» головного екрана: true — натискання поглинуто (закрито сторінку чи панель,
  /// повернуто з іншої вкладки на «Головну»). Ставиться, поки екран на місці; його викликає екран плеєра.
  static bool Function()? backHandler;

  @visibleForTesting
  static void debugReset() {
    backHandler = null;
  }

  /// Телефон у портреті: бічне меню замінює нижня навігація, а картки стають у стовпчик
  static bool isCompact(BuildContext context) =>
      AppPlatform.isMobile && AppLayout(MediaQuery.sizeOf(context)).isCompactWidth;

  /// Значок головної вкладки (нижня навігація й бічне меню)
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

  /// Налаштування застосунку; [tab] — відразу відкрити потрібну вкладку (див. `AppSettingsDialog.tab*`)
  final void Function({int? tab}) onOpenSettings;

  /// Додатковий відступ знизу у списках (телефон: щоб згорнутий плеєр не закривав кінець списку)
  final double reserveBottom;

  /// Налаштування як сторінка всередині застосунку (телефон, портрет). Без нього налаштування відкриває вікно
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
  }

  @override
  void dispose() {
    _nav.removeListener(_onNav);
    if (HomeHub.backHandler == _handleBack) HomeHub.backHandler = null;
    super.dispose();
  }

  void _onNav() {
    if (mounted) setState(() {});
  }

  /// «Назад»: спершу закриває відкриту сторінку чи панель, з кореня іншої вкладки повертає на «Головну».
  /// false — уже на «Головній»: екран плеєра вирішує, чи виходити із застосунку.
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
    // Телефон: виріз камери й системні панелі не мають закривати вміст
    final EdgeInsets safe = AppPlatform.isMobile ? MediaQuery.paddingOf(context) : EdgeInsets.zero;

    final content = HikkaHub(
      scale: scale,
      bottomInset: widget.reserveBottom,
      onOpenSettings: ({int? tab}) {
        // Телефон у портреті: «Налаштування» без розділу — сторінка поверх вкладки (навігація видима), інакше вікно
        if (compact && tab == null && widget.settingsBuilder != null) {
          _nav.openSettings();
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
        padding: EdgeInsets.only(top: safe.top, left: safe.left, right: safe.right),
        child: Column(
          children: [
            Expanded(child: content),
            _buildBottomNav(safe.bottom),
          ],
        ),
      );
    }

    return Container(
      color: uiTheme.bgPrimary,
      padding: EdgeInsets.only(top: safe.top, left: safe.left, right: safe.right, bottom: safe.bottom),
      child: Row(
        children: [
          _buildSidebar(scale),
          Expanded(child: content),
        ],
      ),
    );
  }

  // ── Нижня навігація (телефон, портрет) ─────────────────────────────────────

  Widget _buildBottomNav(double bottomInset) {
    Widget item(MainTab tab) {
      final bool selected = _nav.main == tab;
      final Color fg = selected ? uiTheme.accentColor : uiTheme.textMuted;
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
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AppAnimatedContainer(
                    duration: AppAnim.fast,
                    width: 58,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected ? uiTheme.accentWash : Colors.transparent,
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Icon(HomeHub.iconOf(tab), color: fg, size: 25, fill: selected ? 1 : 0, weight: 300, opticalSize: 24),
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

  // ── Бічне меню (ПК, широкі екрани) ─────────────────────────────────────────

  Widget _buildSidebar(double scale) {
    return AppSidebar(
      scale: scale,
      header: Row(
        children: [
          // Тимчасовий знак: монограма. Маскот (чібі-мишка) замінить її, коли буде готовий
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
