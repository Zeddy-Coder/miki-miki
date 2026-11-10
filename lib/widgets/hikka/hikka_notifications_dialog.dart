import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../services/ui_theme_service.dart';
import '../../utils/platform_info.dart';
import '../app_animation_kit.dart';
import '../app_ui_kit.dart';
import 'hikka_common.dart';

/// Сповіщення: заглушка до інтеграції з акаунтом Hikka та Mikai. Пояснює, що тут з'явиться.
class HikkaNotificationsDialog extends StatelessWidget {
  final double scale;

  const HikkaNotificationsDialog({super.key, required this.scale});

  static Future<void> show(BuildContext context, {required double scale}) {
    return AppDialogs.show<void>(context, builder: (ctx) => HikkaNotificationsDialog(scale: scale));
  }

  Widget _plan(IconData icon, String title, String text) {
    return Padding(
      padding: EdgeInsets.only(bottom: 14 * scale),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36 * scale,
            height: 36 * scale,
            decoration: BoxDecoration(color: uiTheme.accentWash, borderRadius: uiTheme.borderRadius(10 * scale)),
            child: Icon(icon, color: uiTheme.accentColor, size: 20 * scale, weight: 300),
          ),
          SizedBox(width: 12 * scale),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: hikkaStyle(13.5 * scale, weight: FontWeight.w600)),
                SizedBox(height: 2 * scale),
                Text(text, style: hikkaStyle(12 * scale, color: uiTheme.textMuted, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final phone = AppPlatform.isMobile;
    final width = phone ? (mq.size.width - 32).clamp(280.0, 440.0) : 440 * scale;
    final pad = phone ? 18.0 : 22 * scale;
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: width,
          constraints: BoxConstraints(maxHeight: mq.size.height - (phone ? mq.padding.vertical + 32 : 80)),
          decoration: BoxDecoration(
            color: uiTheme.bgPrimary,
            borderRadius: uiTheme.borderRadius(20 * scale),
            border: Border.all(color: uiTheme.borderSubtle),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: uiTheme.isLight ? 0.12 : 0.70),
                blurRadius: 36 * scale,
                offset: Offset(0, 10 * scale),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(pad, 8 * scale, pad / 2, 4 * scale),
                child: Row(
                  children: [
                    Expanded(child: Text('Сповіщення', style: hikkaStyle(16 * scale, weight: FontWeight.bold))),
                    HikkaIconButton(icon: Symbols.close_rounded, tooltip: 'Закрити', scale: scale, onTap: () => Navigator.of(context).pop()),
                  ],
                ),
              ),
              Divider(height: 1, color: uiTheme.borderSubtle),
              Flexible(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(pad, 18 * scale, pad, 18 * scale),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Поки що сповіщень немає. Незабаром вони з’являться тут — після входу через акаунт Hikka й підключення Mikai:',
                        style: hikkaStyle(12.5 * scale, color: uiTheme.textMuted, height: 1.45),
                      ),
                      SizedBox(height: 16 * scale),
                      _plan(Symbols.new_releases_rounded, 'Нова серія', 'Вийшла нова серія тайтлу зі ваших списків.'),
                      _plan(Symbols.mic_rounded, 'Нова озвучка', 'Команда озвучення випустила серію або завершила тайтл.'),
                      SizedBox(height: 4 * scale),
                      AppAccentButton(scale: scale, label: 'Зрозуміло', expand: true, onTap: () => Navigator.of(context).pop()),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
