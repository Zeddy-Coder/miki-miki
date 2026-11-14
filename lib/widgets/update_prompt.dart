import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../services/app_updater.dart';
import '../services/system_controls.dart';
import '../services/ui_theme_service.dart';
import 'app_animation_kit.dart';
import 'app_ui_kit.dart';
import 'hikka/hikka_common.dart';
import 'hikka/hikka_watch_dialogs.dart';

/// Вікно «Доступне оновлення»: з'являється після запуску, коли на GitHub є новіша версія. Показує, що нового
/// (нотатки релізу), і пропонує завантажити, відкласти або більше не нагадувати про цю версію.
class UpdatePrompt extends StatelessWidget {
  final double scale;
  final UpdateInfo info;
  final String current;
  final AppUpdater updater;

  const UpdatePrompt({super.key, required this.scale, required this.info, required this.current, required this.updater});

  static Future<void> show(BuildContext context, {required double scale, required UpdateInfo info, AppUpdater? updater}) {
    final u = updater ?? AppUpdater.instance;
    return AppDialogs.show<void>(context, builder: (ctx) => UpdatePrompt(scale: scale, info: info, current: u.currentVersion, updater: u));
  }

  /// Нотатки релізу без markdown-розмітки заголовків і виділення
  static String cleanNotes(String raw) => raw
      .replaceAll('\r', '')
      .split('\n')
      .map((l) => l.replaceFirst(RegExp(r'^\s{0,3}#{1,6}\s*'), '').replaceAll('**', '').replaceAll('`', '').trimRight())
      .join('\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();

  @override
  Widget build(BuildContext context) {
    final size = info.size > 0 ? ' · ${(info.size / 1048576).toStringAsFixed(1)} МБ' : '';
    final notes = cleanNotes(info.notes);
    return WatchDialogFrame(
      scale: scale,
      title: 'Доступне оновлення',
      icon: Symbols.system_update_rounded,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Версія ${info.version}$size', style: hikkaStyle(14.5 * scale, weight: FontWeight.bold)),
          SizedBox(height: 2 * scale),
          Text('Зараз встановлено $current', style: hikkaStyle(12 * scale, color: uiTheme.textMuted)),
          if (notes.isNotEmpty) ...[
            SizedBox(height: 14 * scale),
            Text('Що нового', style: hikkaStyle(12.5 * scale, weight: FontWeight.bold)),
            SizedBox(height: 6 * scale),
            Text(notes, style: hikkaStyle(12.5 * scale, color: uiTheme.textMuted, height: 1.45)),
          ],
        ],
      ),
      actions: [
        QuietAction(
          label: 'Пропустити версію',
          scale: scale,
          onTap: () {
            updater.skip(info.version);
            Navigator.of(context).pop();
          },
        ),
        QuietAction(label: 'Пізніше', scale: scale, onTap: () => Navigator.of(context).pop()),
        AppAccentButton(
          scale: scale,
          icon: Symbols.download_rounded,
          label: 'Завантажити',
          onTap: () {
            SystemControls.openUrl(info.target);
            Navigator.of(context).pop();
          },
        ),
      ],
    );
  }
}
