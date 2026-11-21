import 'dart:async';

import 'package:flutter/material.dart';

import '../../constants/app_identity.dart';
import '../../models/hikka_profile_models.dart';
import '../../services/admin_api.dart';
import '../../services/app_updater.dart';
import '../../services/downloads/download_manager.dart';
import '../../services/hikka_auth.dart';
import '../../services/settings_sync.dart';
import '../../services/hikka_nav.dart';
import '../../services/storage_service.dart';
import '../../services/ui_theme_service.dart';
import '../app_animation_kit.dart';
import '../app_settings_dialog.dart';
import '../app_tones.dart';
import '../design_kit.dart';
import '../downloads/download_kit.dart';
import '../line_icons.dart';
import '../settings_kit.dart' show SettingsSwitch;
import '../update_prompt.dart';
import 'hikka_account_ui.dart';
import 'hikka_common.dart';
import 'hikka_page_kit.dart';
import 'hikka_user_profile.dart';

/// The "Профіль" tab with the gear in the header. After sign-in, the Hikka profile ([HikkaUserProfile]: the account
/// block, "Список"), then "Застосунок" (settings, the local media library when enabled in "Розробник") and "Акаунт"
/// (sync switches, signing out after a question), then "Активність", favorites, articles, collections and "Історія".
/// A guest sees a sign-in block, "Застосунок" with "Про Miki Miki".
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

  /// "Застосунок": settings, "Про Miki Miki" for a guest, and (when switched on in "Розробник") the local media library
  List<Widget> _app(double scale, double inset, {required bool guest}) => [
        AppGroupCaption(scale: scale, text: 'Застосунок', inset: inset),
        ListenableBuilder(
          listenable: DownloadManager.instance,
          builder: (context, _) => AppLineRow(
            key: const ValueKey('profile-downloads'),
            scale: scale,
            inset: inset,
            icon: LineIcon.download,
            title: 'Завантаження',
            subtitle: downloadsSummary(DownloadManager.instance),
            chevron: true,
            onTap: HikkaNav.instance.openDownloads,
          ),
        ),
        ListenableBuilder(
          listenable: Listenable.merge([AppUpdater.instance.state, AppUpdater.instance.download]),
          builder: (context, _) {
            // An update (found, loading, ready to install) shows in the subtitle and opens "Про застосунок"
            final update = guest ? null : UpdatePrompt.statusLine(AppUpdater.instance);
            return AppLineRow(
              key: const ValueKey('profile-settings'),
              scale: scale,
              inset: inset,
              icon: LineIcon.gear,
              title: 'Налаштування',
              subtitle: update ?? 'Вигляд, субтитри, відтворення',
              chevron: true,
              onTap: () => widget.onOpenSettings(tab: update != null ? AppSettingsDialog.tabAbout : null),
            );
          },
        ),
        ValueListenableBuilder<bool>(
          valueListenable: StorageService.localLibraryListenable,
          builder: (context, on, _) => !on
              ? const SizedBox.shrink()
              : AppLineRow(
                  scale: scale,
                  inset: inset,
                  icon: LineIcon.folder,
                  title: 'Локальна медіатека',
                  subtitle: 'Файли, папки, потоки',
                  chevron: true,
                  onTap: HikkaNav.instance.openLocalLibrary,
                ),
        ),
        // Only the account the server knows as the admin sees the panel (the server checks it again on every request)
        if (!guest && AdminApi.instance.visible)
          AppLineRow(
            key: const ValueKey('profile-admin'),
            scale: scale,
            inset: inset,
            icon: LineIcon.shield,
            title: 'Адмін-панель',
            subtitle: 'Сповіщення користувачам застосунку',
            chevron: true,
            onTap: HikkaNav.instance.openAdmin,
          ),
        if (guest)
          ValueListenableBuilder<UpdateState>(
            valueListenable: AppUpdater.instance.state,
            builder: (context, up, _) => AppLineRow(
              scale: scale,
              inset: inset,
              icon: LineIcon.info,
              title: 'Про ${AppIdentity.name}',
              subtitle: up is UpdateAvailable ? 'Версія ${AppIdentity.version} · доступна ${up.info.version}' : 'Версія ${AppIdentity.version}',
              chevron: true,
              onTap: () => widget.onOpenSettings(tab: AppSettingsDialog.tabAbout),
            ),
          ),
      ];

  /// "Акаунт": the sync switches and signing out (after a question)
  List<Widget> _account(double scale, double inset) {
    final auth = HikkaAuth.instance;
    final sync = SettingsSync.instance;
    return [
      AppGroupCaption(scale: scale, text: 'Акаунт', inset: inset),
      ListenableBuilder(
        listenable: Listenable.merge([auth, sync]),
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              toggled: sync.enabled,
              child: AppLineRow(
                scale: scale,
                inset: inset,
                icon: LineIcon.sync,
                title: 'Синхронізувати налаштування й теми',
                subtitle: 'Вигляд, мови, субтитри й місце зупинки однакові на телефоні та ПК',
                trailing: SettingsSwitch(scale: scale, value: sync.enabled),
                onTap: () => sync.enabled = !sync.enabled,
              ),
            ),
            Semantics(
              toggled: auth.syncProgress,
              child: AppLineRow(
                scale: scale,
                inset: inset,
                icon: LineIcon.list,
                title: 'Передавати прогрес у списки',
                subtitle: 'Переглянута серія додається в «Дивлюсь» і рахується на Hikka',
                trailing: SettingsSwitch(scale: scale, value: auth.syncProgress),
                onTap: () => auth.syncProgress = !auth.syncProgress,
              ),
            ),
            AppLineRow(
              scale: scale,
              inset: inset,
              icon: LineIcon.logout,
              title: 'Вийти з акаунта',
              danger: true,
              onTap: () async {
                final ok = await showAppConfirm(
                  context,
                  scale: scale,
                  title: 'Вийти з акаунта Hikka?',
                  message: 'Прогрес перегляду на цьому пристрої лишиться, але перестане передаватися на Hikka.',
                  action: 'Вийти',
                  destructive: true,
                );
                if (ok) unawaited(auth.signOut());
              },
            ),
          ],
        ),
      ),
    ];
  }

  /// A guest: a grey avatar, "Гість", what signing in gives and the one accent button
  Widget _guest(double scale, double pad) {
    final auth = HikkaAuth.instance;
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 14 * scale, pad, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 62 * scale,
                height: 62 * scale,
                decoration: BoxDecoration(shape: BoxShape.circle, color: AppTones.plate),
                alignment: Alignment.center,
                child: LineIconView(LineIcon.person, size: 28 * scale, color: uiTheme.textMuted),
              ),
              SizedBox(width: 14 * scale),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Гість', style: hikkaStyle(20 * scale, weight: FontWeight.bold)),
                    SizedBox(height: 4 * scale),
                    Text('Ви ще не увійшли в Hikka', style: hikkaStyle(12.5 * scale, color: uiTheme.textMuted)),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 14 * scale),
          Text(
            'Увійдіть через Hikka, щоб бачити свої списки, ставити статуси й оцінки та зберігати прогрес перегляду.',
            style: hikkaStyle(13.5 * scale, color: uiTheme.textMuted, height: 1.45),
          ),
          if (auth.error != null) ...[
            SizedBox(height: 10 * scale),
            Text(auth.error!, style: hikkaStyle(12.5 * scale, color: AppTones.danger, height: 1.4)),
          ],
          SizedBox(height: 14 * scale),
          HikkaLoginButton(scale: scale),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.scale;
    final pad = HikkaLayout.sidePad(context, scale);
    final inset = pad + 2 * scale;
    final auth = HikkaAuth.instance;
    return HikkaCollapsingHeader(
      header: ValueListenableBuilder<UpdateState>(
        valueListenable: AppUpdater.instance.state,
        builder: (context, up, _) {
          final update = up is UpdateAvailable;
          // "Про застосунок" is a tab in settings: a dot on the gear when an update exists
          return HikkaTabHeader(
            scale: scale,
            title: 'Профіль',
            actions: [
              HikkaLineButton(
                scale: scale,
                icon: LineIcon.gear,
                tooltip: update ? 'Налаштування застосунку · є оновлення' : 'Налаштування застосунку',
                dot: update,
                onTap: () => widget.onOpenSettings(tab: update ? AppSettingsDialog.tabAbout : null),
              ),
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
              Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: profile ? double.infinity : hikkaReadableWidth(scale) + pad * 2),
                  child: profile
                      ? HikkaUserProfile(
                          key: ValueKey('me-$name'),
                          username: name,
                          seed: HikkaUser.fromMe(me!),
                          scale: scale,
                          own: true,
                          reloadKey: widget.refreshToken,
                          extra: [..._app(scale, inset, guest: false), ..._account(scale, inset)],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _guest(scale, pad),
                            ..._app(scale, inset, guest: true),
                            SizedBox(height: 18 * scale),
                            Center(child: Text('Дані: Hikka · зображення: AniList', style: hikkaStyle(11 * scale, color: uiTheme.textDarkMuted))),
                            SizedBox(height: 16 * scale),
                          ],
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
