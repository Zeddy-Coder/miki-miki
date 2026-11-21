import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'line_icons.dart';
import 'player_kit.dart';

/// The PC player's top bar: "collapse", the title with the grey "серія · озвучка · якість" line (a click opens the
/// information), then open a file, settings and close — line icons straight on the video, on a soft dark gradient
class TopDock extends StatelessWidget {
  final double scale;
  final String title;

  /// The grey line under the title ("Серія 6 з 28 · Inari · 1080p"); empty — the title alone
  final String subtitle;
  final Player player;
  final GlobalKey settingsKey;
  final bool isSettingsOpen;
  final VoidCallback onCollapse;
  final VoidCallback onClose;
  final VoidCallback onOpenFile;
  final VoidCallback onSettingsTap;
  final VoidCallback onInfoTap;

  const TopDock({
    super.key,
    required this.scale,
    required this.title,
    this.subtitle = '',
    required this.player,
    required this.settingsKey,
    required this.isSettingsOpen,
    required this.onCollapse,
    required this.onClose,
    required this.onOpenFile,
    required this.onSettingsTap,
    required this.onInfoTap,
  });

  @override
  Widget build(BuildContext context) {
    final s = scale;
    Widget button(LineIcon icon, String label, VoidCallback onTap, {Key? key, bool active = false}) => PlayerIconButton(
          key: key,
          icon: icon,
          label: label,
          active: active,
          onTap: onTap,
          size: 40 * s,
          iconSize: 21 * s,
        );
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        height: 104 * s,
        alignment: Alignment.topCenter,
        padding: EdgeInsets.fromLTRB(12 * s, 10 * s, 14 * s, 0),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.black.withValues(alpha: 0.62), Colors.transparent],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Row(
          children: [
            button(LineIcon.chevronDown, 'Згорнути', onCollapse),
            SizedBox(width: 6 * s),
            Expanded(
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onInfoTap,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: playerText(15.5 * s, color: PlayerTones.fg, weight: FontWeight.w700, height: 1.2),
                      ),
                      if (subtitle.isNotEmpty)
                        Padding(
                          padding: EdgeInsets.only(top: 2 * s),
                          child: Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: playerText(12 * s, color: PlayerTones.sub, height: 1.2),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            SizedBox(width: 12 * s),
            button(LineIcon.doc, 'Відкрити файл', onOpenFile),
            button(LineIcon.gear, 'Налаштування', onSettingsTap, key: settingsKey, active: isSettingsOpen),
            button(LineIcon.close, 'Закрити плеєр', onClose),
          ],
        ),
      ),
    );
  }
}
