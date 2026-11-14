import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../constants/app_identity.dart';
import '../../models/hikka_profile_models.dart';
import '../../services/app_updater.dart';
import '../../services/hikka_auth.dart';
import '../../services/hikka_nav.dart';
import '../../services/storage_service.dart';
import '../../services/ui_theme_service.dart';
import '../app_animation_kit.dart';
import '../app_settings_dialog.dart';
import '../app_ui_kit.dart';
import 'hikka_account_ui.dart';
import 'hikka_common.dart';
import 'hikka_page_kit.dart';
import 'hikka_user_profile.dart';

/// The "Профіль" tab. After sign-in, the Hikka profile as on `hikka.io/u/<name>` ([HikkaUserProfile]: header, "Список",
/// "Активність", favorites, articles, collections, "Історія"), below it "Акаунт" (progress sync, sign-out).
/// A guest sees a sign-in card. Then app settings and "Про застосунок"; the hidden local media library
/// appears here when enabled in "Розробник".
class HikkaProfilePage extends StatefulWidget {
  final double scale;
  final double bottomInset;

  /// App settings (from a specific tab if needed, see `AppSettingsDialog.tabAbout`)
  final void Function({int? tab}) onOpenSettings;

  /// Another value means the profile loads anew ("Оновити дані")
  final int refreshToken;

  /// Pull-down refresh (phone)
  final Future<void> Function()? onRefresh;

  const HikkaProfilePage({
    super.key,
    required this.scale,
    required this.onOpenSettings,
    this.bottomInset = 0,
    this.refreshToken = 0,
    this.onRefresh,
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
    if (rows.isEmpty) return const SizedBox.shrink();
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
    final auth = HikkaAuth.instance;
    return HikkaCollapsingHeader(
      header: ListenableBuilder(
        listenable: Listenable.merge([auth, AppUpdater.instance.state]),
        builder: (context, _) {
          final signedIn = auth.signedIn && auth.username.isNotEmpty;
          final update = AppUpdater.instance.state.value is UpdateAvailable;
          // After sign-in, settings, "Про застосунок" and the account are icons in the header: the page is taken by the profile only
          return HikkaTabHeader(
            scale: scale,
            title: 'Профіль',
            subtitle: AppIdentity.tagline,
            actions: [
              if (signedIn) ...[
                HikkaIconButton(
                  icon: Symbols.manage_accounts_rounded,
                  tooltip: 'Акаунт',
                  scale: scale,
                  onTap: () => HikkaAccountDialog.show(context, scale: scale),
                ),
                // "Про застосунок" is a tab in settings; a dot on the gear when an update exists
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    HikkaIconButton(
                      icon: Symbols.settings_rounded,
                      tooltip: update ? 'Налаштування застосунку · є оновлення' : 'Налаштування застосунку',
                      scale: scale,
                      onTap: () => widget.onOpenSettings(tab: update ? AppSettingsDialog.tabAbout : null),
                    ),
                    if (update)
                      Positioned(
                        right: 8 * scale,
                        top: 8 * scale,
                        child: Container(width: 9 * scale, height: 9 * scale, decoration: BoxDecoration(color: uiTheme.accentColor, shape: BoxShape.circle)),
                      ),
                  ],
                ),
              ],
            ],
          );
        },
      ),
      body: ListenableBuilder(
        listenable: auth,
        builder: (context, _) {
          final me = auth.signedIn ? auth.me : null;
          final name = me?.username ?? '';
          final profile = name.isNotEmpty;
          return HikkaPageFrame(
            scale: scale,
            controller: _scroll,
            bottomInset: widget.bottomInset,
            onRefresh: profile ? widget.onRefresh : null,
            children: [
              if (profile) ...[
                HikkaUserProfile(
                  key: ValueKey('me-$name'),
                  username: name,
                  seed: HikkaUser.fromMe(me!),
                  scale: scale,
                  own: true,
                  reloadKey: widget.refreshToken,
                ),
                SizedBox(height: 6 * scale),
              ],
              Padding(
                padding: EdgeInsets.fromLTRB(pad, profile ? 0 : 8 * scale, pad, 16 * scale),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: hikkaReadableWidth(scale)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!profile) ...[
                          HikkaAccountCard(scale: scale),
                          SizedBox(height: 18 * scale),
                          _group(scale, [
                            _MenuRow(
                              scale: scale,
                              icon: Symbols.settings_rounded,
                              title: 'Налаштування застосунку',
                              subtitle: 'Вигляд, плеєр, каталог, джерела перегляду',
                              onTap: () => widget.onOpenSettings(),
                            ),
                          ]),
                          SizedBox(height: 14 * scale),
                        ],
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
                            if (!profile)
                              ValueListenableBuilder<UpdateState>(
                                valueListenable: AppUpdater.instance.state,
                                builder: (context, up, _) => _MenuRow(
                                  scale: scale,
                                  icon: Symbols.info_rounded,
                                  title: 'Про ${AppIdentity.name}',
                                  subtitle: up is UpdateAvailable
                                      ? 'Версія ${AppIdentity.version} · доступна ${up.info.version}'
                                      : 'Версія ${AppIdentity.version}',
                                  onTap: () => widget.onOpenSettings(tab: AppSettingsDialog.tabAbout),
                                ),
                              ),
                          ]),
                        ),
                        if (!profile) ...[
                          SizedBox(height: 18 * scale),
                          Center(
                            child: Text(
                              'Дані: Hikka · зображення: AniList',
                              style: hikkaStyle(11 * scale, color: uiTheme.textDarkMuted),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
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
