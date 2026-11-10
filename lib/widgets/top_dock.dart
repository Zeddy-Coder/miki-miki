import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:media_kit/media_kit.dart';
import '../services/playback_clock.dart';
import '../services/ui_theme_service.dart';
import '../utils/formatters.dart';
import 'app_ui_kit.dart';

class TopDock extends StatelessWidget {
  final double scale;
  final String title;
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
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        height: 60 * scale,
        padding: EdgeInsets.symmetric(horizontal: 35 * scale),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.black.withValues(alpha: 0.85), Colors.transparent],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Row(
          children: [
            AppOverlayButton(
              scale: scale,
              width: 36 * scale,
              height: 32 * scale,
              borderRadius: 8 * scale,
              onTap: onCollapse,
              child: Icon(
                Symbols.keyboard_arrow_down_rounded,
                color: Colors.white,
                size: 24 * scale,
                weight: 300,
                opticalSize: 24,
              ),
            ),
            SizedBox(width: 10 * scale),
            Expanded(
              child: InkWell(
                onTap: onInfoTap,
                borderRadius: uiTheme.borderRadius(6 * scale),
                splashColor: Colors.transparent,
                highlightColor: Colors.transparent,
                hoverColor: Colors.white.withValues(alpha: 0.08),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontFamily: 'Arial',
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                        fontSize: 14.5 * scale,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: 2 * scale),
                    ValueListenableBuilder<Duration>(
                      valueListenable: PlaybackClock.of(player).duration,
                      builder: (context, dur, _) {
                        return Text(
                          '${AppFormatters.formatTime(dur)} · YouTube Mobile',
                          style: TextStyle(
                            fontFamily: 'Arial',
                            color: Colors.white70,
                            fontSize: 11.5 * scale,
                            fontWeight: FontWeight.w300,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(width: 16 * scale),
            AppOverlayButton(
              scale: scale,
              width: 36 * scale,
              height: 32 * scale,
              borderRadius: 8 * scale,
              onTap: onOpenFile,
              child: Icon(
                Symbols.file_open_rounded,
                color: Colors.white,
                size: 19 * scale,
                weight: 300,
                opticalSize: 24,
              ),
            ),
            SizedBox(width: 8 * scale),
            AppOverlayButton(
              key: settingsKey,
              scale: scale,
              width: 36 * scale,
              height: 32 * scale,
              borderRadius: 8 * scale,
              isActive: isSettingsOpen,
              onTap: onSettingsTap,
              child: Icon(
                Symbols.settings_rounded,
                color: AppOverlayButton.foreground(isSettingsOpen),
                size: 19 * scale,
                weight: 300,
                opticalSize: 24,
              ),
            ),
            SizedBox(width: 8 * scale),
            AppOverlayButton(
              scale: scale,
              width: 36 * scale,
              height: 32 * scale,
              borderRadius: 8 * scale,
              onTap: onClose,
              child: Icon(
                Symbols.close_rounded,
                color: Colors.white,
                size: 20 * scale,
                weight: 300,
                opticalSize: 24,
              ),
            ),
          ],
        ),
      ),
    );
  }
}