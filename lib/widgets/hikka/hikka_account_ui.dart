import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';


import '../../constants/app_identity.dart';
import '../../utils/platform_info.dart';
import '../../services/hikka_auth.dart';
import '../../services/system_controls.dart';
import '../../services/ui_theme_service.dart';
import '../app_animation_kit.dart';
import '../app_ui_kit.dart';
import 'hikka_common.dart';
import 'hikka_watch_dialogs.dart';

const Color _errorColor = Color(0xFFE57373);

/// Hikka sign-in window: opens the consent page in a browser and waits for the response. If that did not work automatically
/// (the port is busy, the app was killed in the background), you can paste the address the site redirected to.
class HikkaLoginDialog extends StatefulWidget {
  final double scale;

  const HikkaLoginDialog({super.key, required this.scale});

  /// Opens the window and starts sign-in at once; `true` if the person signed in
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
              if (exchanging) _hint('Якщо мережа блокує службу входу, це може тривати до хвилини: застосунок обходить блокування сам.'),
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
            // The default browser may not be the one where the person is signed in on hikka.io: an app picker or a manual link
            if (waiting && AppPlatform.isAndroid)
              AppSecondaryButton(
                scale: scale,
                expand: false,
                icon: Symbols.public_rounded,
                label: 'В іншому браузері',
                onTap: () => unawaited(SystemControls.openUrl(_auth.authorizeUrl, chooser: true)),
              ),
            if (waiting)
              AppSecondaryButton(
                scale: scale,
                expand: false,
                icon: Symbols.content_copy_rounded,
                label: 'Копіювати посилання',
                onTap: () {
                  Clipboard.setData(ClipboardData(text: _auth.authorizeUrl));
                  ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('Посилання скопійовано')));
                },
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

/// The one accent button "Увійти через Hikka" (opens the sign-in window)
class HikkaLoginButton extends StatelessWidget {
  final double scale;

  const HikkaLoginButton({super.key, required this.scale});

  @override
  Widget build(BuildContext context) {
    final accent = uiTheme.accentColor;
    final shape = RoundedRectangleBorder(borderRadius: uiTheme.borderRadius(14 * scale));
    return Semantics(
      button: true,
      label: 'Увійти через Hikka',
      excludeSemantics: true,
      child: Material(
        color: accent,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          splashColor: Colors.transparent,
          highlightColor: Colors.black.withValues(alpha: 0.08),
          onTap: () => unawaited(HikkaLoginDialog.show(context, scale: scale)),
          child: SizedBox(
            height: math.max(44 * scale, AppPlatform.isMobile ? AppPlatform.touchTarget : 0.0),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 22 * scale),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Увійти через Hikka', style: hikkaStyle(14.5 * scale, weight: FontWeight.bold, color: onAccent(accent))),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
