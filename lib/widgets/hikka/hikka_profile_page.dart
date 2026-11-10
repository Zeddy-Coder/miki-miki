import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../constants/app_identity.dart';
import '../../services/hikka_nav.dart';
import '../../services/storage_service.dart';
import '../../services/ui_theme_service.dart';
import '../../services/watch_service.dart';
import '../app_animation_kit.dart';
import '../app_settings_dialog.dart';
import '../app_ui_kit.dart';
import 'hikka_account_ui.dart';
import 'hikka_common.dart';
import 'hikka_page_kit.dart';
import 'sources_dialog.dart';

/// Вкладка «Профіль»: обліковий запис Hikka (вхід, вихід, синхронізація прогресу) і вхід до налаштувань застосунку,
/// каталогу, джерел перегляду та «Про застосунок». Прихована локальна медіатека з'являється тут, коли її
/// ввімкнено в «Розробник».
class HikkaProfilePage extends StatefulWidget {
  final double scale;
  final double bottomInset;

  /// Налаштування застосунку (за потреби — з певної вкладки, див. `AppSettingsDialog.tabAbout`)
  final void Function({int? tab}) onOpenSettings;

  /// Налаштування каталогу (мова назв, 18+, дані)
  final VoidCallback onOpenCatalogSettings;

  const HikkaProfilePage({
    super.key,
    required this.scale,
    required this.onOpenSettings,
    required this.onOpenCatalogSettings,
    this.bottomInset = 0,
  });

  @override
  State<HikkaProfilePage> createState() => _HikkaProfilePageState();
}

class _HikkaProfilePageState extends State<HikkaProfilePage> {
  final ScrollController _scroll = AppSmoothScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Widget _group(double scale, List<Widget> rows) {
    return AppCard(
      scale: scale,
      radius: 14,
      child: Column(
        children: [
          for (int i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 1, indent: 52 * scale, color: uiTheme.borderSubtle),
            rows[i],
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.scale;
    final pad = HikkaLayout.sidePad(context, scale);
    return HikkaCollapsingHeader(
      header: HikkaTabHeader(scale: scale, title: 'Профіль', subtitle: AppIdentity.tagline),
      body: HikkaPageFrame(
            scale: scale,
            controller: _scroll,
            bottomInset: widget.bottomInset,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(pad, 8 * scale, pad, 16 * scale),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: hikkaReadableWidth(scale)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        HikkaAccountCard(scale: scale),
                        SizedBox(height: 18 * scale),
                        _group(scale, [
                          _MenuRow(
                            scale: scale,
                            icon: Symbols.settings_rounded,
                            title: 'Налаштування застосунку',
                            subtitle: 'Вигляд, плеєр, субтитри, звук',
                            onTap: () => widget.onOpenSettings(),
                          ),
                          _MenuRow(
                            scale: scale,
                            icon: Symbols.tune_rounded,
                            title: 'Каталог і дані',
                            subtitle: 'Мова назв, контент 18+, оновлення даних, кеш',
                            onTap: widget.onOpenCatalogSettings,
                          ),
                          _MenuRow(
                            scale: scale,
                            icon: Symbols.play_circle_rounded,
                            title: 'Джерела перегляду',
                            subtitle: 'Де шукати українські озвучки й субтитри',
                            onTap: () => SourcesDialog.show(context, scale: scale, registry: WatchService.instance.registry),
                          ),
                        ]),
                        SizedBox(height: 14 * scale),
                        ValueListenableBuilder<bool>(
                          valueListenable: StorageService.localLibraryListenable,
                          builder: (context, localLibrary, _) => _group(scale, [
                            if (localLibrary)
                              _MenuRow(
                                scale: scale,
                                icon: Symbols.video_library_rounded,
                                title: 'Локальна медіатека',
                                subtitle: 'Відкрити файл чи посилання, історія й плейлисти',
                                onTap: HikkaNav.instance.openLocalLibrary,
                              ),
                            _MenuRow(
                              scale: scale,
                              icon: Symbols.info_rounded,
                              title: 'Про ${AppIdentity.name}',
                              subtitle: 'Версія ${AppIdentity.version}',
                              onTap: () => widget.onOpenSettings(tab: AppSettingsDialog.tabAbout),
                            ),
                          ]),
                        ),
                        SizedBox(height: 18 * scale),
                        Center(
                          child: Text(
                            'Дані: Hikka · зображення: AniList',
                            style: hikkaStyle(11 * scale, color: uiTheme.textDarkMuted),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  final double scale;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _MenuRow({required this.scale, required this.icon, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$title. $subtitle',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        splashColor: Colors.transparent,
        highlightColor: uiTheme.touchHighlight,
        hoverColor: uiTheme.hoverOverlay,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 14 * scale, vertical: 10 * scale),
            child: Row(
              children: [
                Icon(icon, color: uiTheme.accentColor, size: 24 * scale, weight: 300),
                SizedBox(width: 14 * scale),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: hikkaStyle(13.5 * scale, weight: FontWeight.w600)),
                      SizedBox(height: 2 * scale),
                      Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: hikkaStyle(11.5 * scale, color: uiTheme.textDarkMuted, height: 1.3)),
                    ],
                  ),
                ),
                Icon(Symbols.chevron_right_rounded, color: uiTheme.textDarkMuted, size: 22 * scale),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
