import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../services/app_updater.dart';
import '../services/system_controls.dart';
import '../services/ui_theme_service.dart';
import 'app_animation_kit.dart';
import 'app_tones.dart';
import 'app_ui_kit.dart';
import 'hikka/hikka_cards.dart' show HikkaProgressBar;
import 'hikka/hikka_common.dart';
import 'hikka/hikka_watch_dialogs.dart';

/// Bytes as megabytes for the update texts: `12.3 МБ`
String updateMegabytes(int bytes) => '${(bytes / 1048576).toStringAsFixed(1)} МБ';

/// The "Доступне оновлення" window. Appears after launch when GitHub has a newer version, on a tap on a "new version"
/// notification and from the settings: what is new and the update itself. The file downloads inside the app with
/// progress and goes to the system installer (on Windows the setup runs quietly and Miki Miki starts again); without a
/// file for this platform the release page opens in the browser.
class UpdatePrompt extends StatefulWidget {
  final double scale;
  final AppUpdater updater;

  /// The version to show until the updater's own state names one
  final UpdateInfo? info;

  /// Begin at once: download (or install a ready file). The "Оновити" button in the settings
  final bool start;

  const UpdatePrompt({super.key, required this.scale, required this.updater, this.info, this.start = false});

  static int _open = 0;

  /// The window is on the screen (it is not shown twice)
  static bool get isOpen => _open > 0;

  static Future<void> show(BuildContext context, {required double scale, UpdateInfo? info, AppUpdater? updater, bool start = false}) {
    final u = updater ?? AppUpdater.instance;
    return AppDialogs.show<void>(context, builder: (ctx) => UpdatePrompt(scale: scale, updater: u, info: info, start: start));
  }

  /// Release notes without markdown heading and emphasis markup
  static String cleanNotes(String raw) => raw
      .replaceAll('\r', '')
      .split('\n')
      .map((l) => l.replaceFirst(RegExp(r'^\s{0,3}#{1,6}\s*'), '').replaceAll('**', '').replaceAll('`', '').trimRight())
      .join('\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();

  /// `Завантаження… 12.3 з 36.0 МБ · 34%`
  static String progressText(DownloadRunning d) {
    final f = d.fraction;
    if (f == null) return 'Завантаження… ${updateMegabytes(d.received)}';
    return 'Завантаження… ${(d.received / 1048576).toStringAsFixed(1)} з ${updateMegabytes(d.total)} · ${(f * 100).floor()}%';
  }

  /// A short line about the update for the profile and the settings: loading, ready, available; null when there is none
  static String? statusLine(AppUpdater u) {
    final d = u.download.value;
    if (d is DownloadRunning) {
      final f = d.fraction;
      return f == null ? 'Завантаження оновлення…' : 'Завантаження оновлення… ${(f * 100).floor()}%';
    }
    final st = u.state.value;
    if (st is! UpdateAvailable) return null;
    if (u.readyFor(st.info.version) != null) return 'Оновлення ${st.info.version} готове до встановлення';
    return 'Є оновлення: версія ${st.info.version}';
  }

  @override
  State<UpdatePrompt> createState() => _UpdatePromptState();
}

class _UpdatePromptState extends State<UpdatePrompt> {
  AppUpdater get _u => widget.updater;
  late final Listenable _changes = Listenable.merge([_u.state, _u.download]);

  /// The download began in this window: the file installs as soon as it is ready
  bool _installWhenReady = false;

  /// Windows: the setup started and the app closes in a moment
  bool _installing = false;

  @override
  void initState() {
    super.initState();
    UpdatePrompt._open++;
    _u.download.addListener(_onDownload);
    if (widget.start) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _update();
      });
    }
  }

  @override
  void dispose() {
    UpdatePrompt._open--;
    _u.download.removeListener(_onDownload);
    super.dispose();
  }

  UpdateInfo? get _info {
    final st = _u.state.value;
    return st is UpdateAvailable ? st.info : widget.info;
  }

  void _onDownload() {
    final info = _info;
    if (!_installWhenReady || info == null) return;
    final d = _u.download.value;
    if (d is DownloadReady && d.version == info.version) {
      _installWhenReady = false;
      unawaited(_install());
    } else if (d is! DownloadRunning) {
      // Failed or cancelled: nothing installs by itself any more
      _installWhenReady = false;
    }
  }

  /// "Оновити": the file downloads and installs when ready; a ready one installs at once. Without a file for this
  /// platform the browser opens
  void _update() {
    final info = _info;
    if (info == null) return;
    if (!_u.canInstallInApp(info)) {
      SystemControls.openUrl(info.target);
      Navigator.of(context).pop();
      return;
    }
    if (_u.readyFor(info.version) != null) {
      unawaited(_install());
      return;
    }
    _installWhenReady = true;
    unawaited(_u.startDownload(info));
  }

  Future<void> _install() async {
    if (_u.installRestartsApp) setState(() => _installing = true);
    final r = await _u.install();
    if (mounted && r != UpdateInstall.started && _installing) setState(() => _installing = false);
  }

  void _close() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: _changes,
        builder: (context, _) {
          final info = _info;
          return info == null ? _checking(context) : _available(context, info);
        },
      );

  Widget _muted(String text) => Text(text, style: hikkaStyle(12.5 * widget.scale, color: uiTheme.textMuted, height: 1.45));

  Widget _spinnerLine(String text) {
    final scale = widget.scale;
    return Row(
      children: [
        SizedBox(width: 16 * scale, height: 16 * scale, child: CircularProgressIndicator(strokeWidth: 2, color: uiTheme.accentColor)),
        SizedBox(width: 10 * scale),
        Expanded(child: _muted(text)),
      ],
    );
  }

  /// A highlighted note: what to do now (the permission) or why it did not work
  Widget _note(IconData icon, String text, {bool error = false}) {
    final scale = widget.scale;
    final color = error ? AppTones.danger : uiTheme.accentColor;
    return Container(
      padding: EdgeInsets.all(12 * scale),
      decoration: BoxDecoration(
        color: color.withValues(alpha: uiTheme.isLight ? 0.08 : 0.12),
        borderRadius: uiTheme.borderRadius(12 * scale),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18 * scale, color: color),
          SizedBox(width: 10 * scale),
          Expanded(child: Text(text, style: hikkaStyle(12.5 * scale, color: uiTheme.textPrimary, height: 1.45))),
        ],
      ),
    );
  }

  /// The window before a version is known: checking, "найновіша", or the check failed
  Widget _checking(BuildContext context) {
    final scale = widget.scale;
    final st = _u.state.value;
    return WatchDialogFrame(
      scale: scale,
      title: 'Оновлення',
      icon: Symbols.system_update_rounded,
      body: switch (st) {
        UpdateUpToDate() => Text('У вас найновіша версія — ${_u.currentVersion}.', style: hikkaStyle(14 * scale, weight: FontWeight.bold)),
        UpdateFailed(:final message) => Text(message, style: hikkaStyle(12.5 * scale, color: AppTones.danger, height: 1.45)),
        _ => _spinnerLine('Перевіряємо, чи є нова версія…'),
      },
      actions: [
        if (st is UpdateFailed) ...[
          QuietAction(label: 'Закрити', scale: scale, onTap: _close),
          AppAccentButton(scale: scale, icon: Symbols.refresh_rounded, label: 'Спробувати ще', onTap: () => unawaited(_u.check())),
        ],
        if (st is UpdateUpToDate) AppAccentButton(scale: scale, label: 'Гаразд', onTap: _close),
      ],
    );
  }

  Widget _available(BuildContext context, UpdateInfo info) {
    final scale = widget.scale;
    final size = info.size > 0 ? ' · ${updateMegabytes(info.size)}' : '';
    final notes = UpdatePrompt.cleanNotes(info.notes);
    final d = _u.download.value;
    final mine = switch (d) {
      DownloadRunning(:final version) || DownloadReady(:final version) || DownloadFailed(:final version) => version == info.version,
      DownloadIdle() => false,
    };
    final restarts = _u.installRestartsApp;

    Widget? progress;
    List<Widget> actions;
    if (_installing) {
      progress = _spinnerLine('Встановлюємо… Miki Miki закриється й за мить відкриється вже оновленим.');
      actions = const [];
    } else if (mine && d is DownloadRunning) {
      final f = d.fraction;
      progress = Semantics(
        label: 'Завантаження оновлення',
        value: f == null ? null : '${(f * 100).floor()}%',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(3 * scale),
              child: HikkaProgressBar(value: f ?? 0, height: 6 * scale),
            ),
            SizedBox(height: 7 * scale),
            _muted(UpdatePrompt.progressText(d)),
          ],
        ),
      );
      actions = [
        QuietAction(label: 'Скасувати', scale: scale, onTap: _u.cancelDownload),
        AppAccentButton(scale: scale, label: 'У фоні', onTap: _close),
      ];
    } else if (mine && d is DownloadReady) {
      if (d.waitingPermission) {
        progress = _note(
          Symbols.shield_rounded,
          'Дозвольте Miki Miki встановлювати застосунки: у налаштуваннях, що відкрилися, увімкніть «Дозволити з цього джерела» й поверніться назад — встановлення продовжиться.',
        );
      } else if (d.error != null) {
        progress = _note(Symbols.error_rounded, d.error!, error: true);
      } else {
        progress = _note(
          Symbols.check_circle_rounded,
          restarts ? 'Завантажено. Під час встановлення Miki Miki закриється й відкриється знову.' : 'Завантажено. Залишилось підтвердити встановлення.',
        );
      }
      actions = [
        QuietAction(label: 'Пізніше', scale: scale, onTap: _close),
        d.waitingPermission
            ? AppAccentButton(scale: scale, icon: Symbols.settings_rounded, label: 'Відкрити налаштування', onTap: () => unawaited(_install()))
            : AppAccentButton(
                scale: scale,
                icon: restarts ? Symbols.restart_alt_rounded : Symbols.system_update_rounded,
                label: restarts ? 'Встановити й перезапустити' : 'Встановити',
                onTap: () => unawaited(_install()),
              ),
      ];
    } else if (mine && d is DownloadFailed) {
      progress = _note(Symbols.error_rounded, d.message, error: true);
      actions = [
        QuietAction(label: 'Сторінка релізу', scale: scale, onTap: () => SystemControls.openUrl(info.pageUrl)),
        QuietAction(label: 'Пізніше', scale: scale, onTap: _close),
        AppAccentButton(scale: scale, icon: Symbols.refresh_rounded, label: 'Спробувати ще', onTap: _update),
      ];
    } else {
      final inApp = _u.canInstallInApp(info);
      actions = [
        QuietAction(
          label: 'Пропустити версію',
          scale: scale,
          onTap: () {
            _u.skip(info.version);
            _close();
          },
        ),
        QuietAction(label: 'Пізніше', scale: scale, onTap: _close),
        AppAccentButton(scale: scale, icon: Symbols.download_rounded, label: inApp ? 'Оновити' : 'Завантажити', onTap: _update),
      ];
    }

    return WatchDialogFrame(
      scale: scale,
      title: 'Доступне оновлення',
      icon: Symbols.system_update_rounded,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Версія ${info.version}$size', style: hikkaStyle(14.5 * scale, weight: FontWeight.bold)),
          SizedBox(height: 2 * scale),
          Text('Зараз встановлено ${_u.currentVersion}', style: hikkaStyle(12 * scale, color: uiTheme.textMuted)),
          if (progress != null) ...[
            SizedBox(height: 14 * scale),
            progress,
          ],
          if (notes.isNotEmpty) ...[
            SizedBox(height: 14 * scale),
            Text('Що нового', style: hikkaStyle(12.5 * scale, weight: FontWeight.bold)),
            SizedBox(height: 6 * scale),
            Text(notes, style: hikkaStyle(12.5 * scale, color: uiTheme.textMuted, height: 1.45)),
          ],
        ],
      ),
      actions: actions,
    );
  }
}
