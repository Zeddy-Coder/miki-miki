import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../constants/app_identity.dart';
import '../../services/hikka_auth.dart';
import '../../services/system_controls.dart';
import '../../services/ui_theme_service.dart';
import '../app_animation_kit.dart';
import '../app_ui_kit.dart';
import 'hikka_common.dart';
import 'hikka_watch_dialogs.dart';

const Color _errorColor = Color(0xFFE57373);

/// Вікно входу в Hikka: відкриває сторінку дозволу в браузері й чекає відповідь. Якщо автоматично не вийшло
/// (порт зайнятий, застосунок вбило в фоні) — можна вставити адресу, на яку перекинув сайт.
class HikkaLoginDialog extends StatefulWidget {
  final double scale;

  const HikkaLoginDialog({super.key, required this.scale});

  /// Відкриває вікно й одразу починає вхід; `true`, якщо людина ввійшла
  static Future<bool> show(BuildContext context, {required double scale}) async {
    final ok = await AppDialogs.show<bool>(context, builder: (_) => HikkaLoginDialog(scale: scale));
    return ok == true;
  }

  @override
  State<HikkaLoginDialog> createState() => _HikkaLoginDialogState();
}

class _HikkaLoginDialogState extends State<HikkaLoginDialog> {
  final TextEditingController _paste = TextEditingController();
  bool _manual = false;
  bool _closing = false;

  double get _scale => widget.scale;
  HikkaAuth get _auth => HikkaAuth.instance;

  @override
  void initState() {
    super.initState();
    _auth.addListener(_onAuth);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_auth.startLogin());
    });
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuth);
    if (_auth.phase == HikkaAuthPhase.waiting) _auth.cancelLogin();
    _paste.dispose();
    super.dispose();
  }

  void _onAuth() {
    if (_auth.signedIn && !_closing) {
      _closing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop(true);
      });
    }
  }

  void _submit() {
    if (_auth.submit(_paste.text)) _paste.clear();
  }

  Widget _status(String text, {bool spinner = true}) {
    final scale = _scale;
    return Row(
      children: [
        if (spinner)
          SizedBox(width: 18 * scale, height: 18 * scale, child: CircularProgressIndicator(strokeWidth: 2.2, color: uiTheme.accentColor))
        else
          Icon(Symbols.error_rounded, color: _errorColor, size: 20 * scale, weight: 300),
        SizedBox(width: 12 * scale),
        Expanded(child: Text(text, style: hikkaStyle(13.5 * scale, weight: FontWeight.w600, color: spinner ? null : _errorColor, height: 1.3))),
      ],
    );
  }

  Widget _hint(String text) => Padding(
        padding: EdgeInsets.only(top: 10 * _scale),
        child: Text(text, style: hikkaStyle(12 * _scale, color: uiTheme.textDarkMuted, height: 1.45)),
      );

  Widget _manualBlock() {
    final scale = _scale;
    return Padding(
      padding: EdgeInsets.only(top: 14 * scale),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Після підтвердження скопіюйте адресу сторінки з рядка браузера (вона містить reference=…) і вставте сюди.',
            style: hikkaStyle(12 * scale, color: uiTheme.textDarkMuted, height: 1.45),
          ),
          SizedBox(height: 10 * scale),
          AppSearchField(scale: scale, controller: _paste, icon: Symbols.link_rounded, hint: 'Адреса або код входу', onChanged: (_) {}),
          SizedBox(height: 10 * scale),
          AppSecondaryButton(scale: scale, expand: true, icon: Symbols.check_rounded, label: 'Підтвердити', onTap: _submit),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scale = _scale;
    return ListenableBuilder(
      listenable: _auth,
      builder: (context, _) {
        final phase = _auth.phase;
        final error = _auth.error;
        final waiting = phase == HikkaAuthPhase.waiting;
        final exchanging = phase == HikkaAuthPhase.exchanging;
        final failed = !_auth.busy && !_auth.signedIn && error != null;
        final showManual = waiting && (_manual || !_auth.loopbackReady);

        return WatchDialogFrame(
          scale: scale,
          title: 'Вхід у Hikka',
          icon: Symbols.login_rounded,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (exchanging) _status('Завершую вхід…'),
              if (waiting) ...[
                _status('Чекаю на підтвердження в браузері…'),
                _hint(
                  'Відкрилась сторінка hikka.io. Увійдіть, якщо потрібно, і натисніть «Продовжити», щоб дозволити '
                  '${AppIdentity.name} доступ до профілю, списків і улюбленого. Після цього вхід завершиться сам.',
                ),
                if (!_auth.loopbackReady)
                  _hint('Автоматично повернутись не вдалося (порт зайнятий), тож вставте адресу вручну після підтвердження.'),
                if (showManual) _manualBlock(),
              ],
              if (failed) _status(error, spinner: false),
              if (failed) _hint('Можна спробувати ще раз: сторінка дозволу відкриється заново.'),
            ],
          ),
          actions: [
            if (waiting && !showManual) QuietAction(label: 'Не спрацювало? Вставити адресу', scale: scale, onTap: () => setState(() => _manual = true)),
            if (waiting)
              AppSecondaryButton(
                scale: scale,
                expand: false,
                icon: Symbols.open_in_new_rounded,
                label: 'Відкрити знову',
                onTap: () => unawaited(SystemControls.openUrl(_auth.authorizeUrl)),
              ),
            if (failed)
              AppAccentButton(scale: scale, solid: true, icon: Symbols.refresh_rounded, label: 'Спробувати ще раз', onTap: () => unawaited(_auth.startLogin())),
            if (!exchanging)
              QuietAction(
                label: waiting ? 'Скасувати' : 'Закрити',
                scale: scale,
                onTap: () => Navigator.of(context).pop(false),
              ),
          ],
        );
      },
    );
  }
}

/// Картка акаунта Hikka: гість із кнопкою входу або профіль із виходом і перемикачем синхронізації.
class HikkaAccountCard extends StatelessWidget {
  final double scale;

  const HikkaAccountCard({super.key, required this.scale});

  Widget _avatar(String? url) {
    final size = 56 * scale;
    return SizedBox(
      width: size,
      height: size,
      child: (url == null || url.isEmpty)
          ? Container(
              decoration: BoxDecoration(shape: BoxShape.circle, color: uiTheme.accentWash, border: Border.all(color: uiTheme.accentBorder)),
              child: Icon(Symbols.person_rounded, color: uiTheme.accentColor, size: 30 * scale, weight: 300),
            )
          : HikkaPoster(url: url, scale: scale, aspect: 1, radius: 28, icon: Symbols.person_rounded, alignment: Alignment.center),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = HikkaAuth.instance;
    return ListenableBuilder(
      listenable: auth,
      builder: (context, _) {
        final me = auth.me;
        final signedIn = auth.signedIn;
        return AppCard(
          scale: scale,
          radius: 16,
          padding: EdgeInsets.all(16 * scale),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _avatar(signedIn ? me?.avatar : null),
                  SizedBox(width: 14 * scale),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(signedIn ? (me?.username.isNotEmpty == true ? me!.username : 'Акаунт Hikka') : 'Гість',
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: hikkaStyle(17 * scale, weight: FontWeight.bold)),
                        SizedBox(height: 2 * scale),
                        Text(signedIn ? 'Акаунт Hikka підключено' : 'Ви ще не увійшли', style: hikkaStyle(12.5 * scale, color: uiTheme.textMuted)),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: 14 * scale),
              if (signedIn) ...[
                HikkaToggleRow(
                  scale: scale,
                  title: 'Передавати прогрес у списки',
                  subtitle: 'Переглянута серія додається в «Дивлюсь» і збільшує лічильник серій на Hikka.',
                  value: auth.syncProgress,
                  onChanged: (v) => auth.syncProgress = v,
                ),
                SizedBox(height: 14 * scale),
                AppSecondaryButton(scale: scale, expand: true, icon: Symbols.logout_rounded, label: 'Вийти з акаунта', onTap: () => unawaited(auth.signOut())),
              ] else ...[
                Text(
                  'Увійдіть через Hikka, щоб бачити свої списки, ставити статуси й оцінки та зберігати прогрес перегляду. Дані синхронізуються з сайтом.',
                  style: hikkaStyle(12.5 * scale, color: uiTheme.textMuted, height: 1.45),
                ),
                if (auth.error != null) ...[
                  SizedBox(height: 10 * scale),
                  Text(auth.error!, style: hikkaStyle(12 * scale, color: _errorColor, height: 1.4)),
                ],
                SizedBox(height: 14 * scale),
                AppAccentButton(
                  scale: scale,
                  solid: true,
                  expand: true,
                  icon: Symbols.login_rounded,
                  label: 'Увійти через Hikka',
                  onTap: () => unawaited(HikkaLoginDialog.show(context, scale: scale)),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
