import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/osd_message.dart';
import '../services/ui_theme_service.dart';
import '../utils/platform_info.dart';
import 'app_animation_kit.dart';
import 'player_kit.dart';

/// An on-screen notification over the video (volume, speed, Anime4K, mpv keys…): a dark plate with a white icon,
/// "Назва · значення" in bold and a thin accent bar for levels. Always dark: it sits on the video, so it does not
/// depend on the light / dark theme.
class OsdToast extends StatelessWidget {
  final double scale;
  final ValueListenable<OsdMessage?> message;

  /// Extra top padding (phone: the cutout / status bar)
  final double topInset;

  const OsdToast({super.key, required this.scale, required this.message, this.topInset = 0});

  static const Color _errorColor = Color(0xFFE5484D);

  /// The dark plate of the new player chrome (rgba 24, 24, 28, .86) and the grey of a long value under the title
  static const Color _plate = Color(0xDB18181C);
  static const Color _detail = Color(0xFFBDBDC4);

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: EdgeInsets.only(top: 78 * scale + topInset),
            child: ValueListenableBuilder<OsdMessage?>(
              valueListenable: message,
              builder: (context, msg, _) => AppPresence(
                visible: msg != null,
                duration: AppAnim.normal,
                slide: const Offset(0, -0.25),
                child: msg == null ? const SizedBox.shrink() : _OsdPill(scale: scale, msg: msg),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OsdPill extends StatelessWidget {
  final double scale;
  final OsdMessage msg;

  const _OsdPill({required this.scale, required this.msg});

  /// A short value reads as part of the title ("Гучність · 65%"); a long one goes under it in grey
  static bool inline(OsdMessage msg) {
    final d = msg.detail;
    return d != null && d.isNotEmpty && !msg.isError && d.length <= 16 && !d.contains('\n');
  }

  @override
  Widget build(BuildContext context) {
    final detail = msg.detail;
    final oneLine = inline(msg);
    final title = oneLine ? '${msg.title} · $detail' : msg.title;
    final progress = msg.progress;
    final showKeys = msg.keys.isNotEmpty && !AppPlatform.isMobile;

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: 460 * scale, minWidth: (progress != null ? 230 : 150) * scale),
      child: Container(
        key: const ValueKey('osd-plate'),
        padding: EdgeInsets.symmetric(horizontal: 16 * scale, vertical: 12 * scale),
        decoration: BoxDecoration(
          color: OsdToast._plate,
          borderRadius: BorderRadius.circular(16 * scale),
          border: Border.all(color: msg.isError ? OsdToast._errorColor.withValues(alpha: 0.55) : PlayerTones.pillLine),
        ),
        child: IntrinsicWidth(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(msg.icon, color: msg.isError ? OsdToast._errorColor : PlayerTones.fg, size: 26 * scale, weight: 300, opticalSize: 24),
              SizedBox(width: 12 * scale),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontFamily: 'Arial', fontFamilyFallback: const ['MikiSans'], color: PlayerTones.fg, fontSize: 14 * scale, fontWeight: FontWeight.w700),
                    ),
                    if (!oneLine && detail != null && detail.isNotEmpty) ...[
                      SizedBox(height: 2 * scale),
                      Text(
                        detail,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontFamily: 'Arial', fontFamilyFallback: const ['MikiSans'], color: OsdToast._detail, fontSize: 12.5 * scale),
                      ),
                    ],
                    if (progress != null) ...[
                      SizedBox(height: 8 * scale),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2 * scale),
                        child: SizedBox(
                          height: 3 * scale,
                          child: Stack(
                            children: [
                              Positioned.fill(child: ColoredBox(color: Colors.white.withValues(alpha: 0.2))),
                              Positioned.fill(
                                child: FractionallySizedBox(
                                  alignment: Alignment.centerLeft,
                                  widthFactor: progress.clamp(0.0, 1.0),
                                  child: ColoredBox(color: msg.isError ? OsdToast._errorColor : PlayerTones.active),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (showKeys) ...[
                SizedBox(width: 14 * scale),
                for (int i = 0; i < msg.keys.length; i++) ...[
                  if (i > 0) SizedBox(width: 4 * scale),
                  _OverlayKeyCap(scale: scale, text: msg.keys[i]),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Keyboard key for dark overlays
class _OverlayKeyCap extends StatelessWidget {
  final double scale;
  final String text;

  const _OverlayKeyCap({required this.scale, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(minWidth: 22 * scale),
      padding: EdgeInsets.symmetric(horizontal: 7 * scale, vertical: 3 * scale),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: uiTheme.borderRadius(6 * scale),
        border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'Arial',
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 11 * scale,
        ),
      ),
    );
  }
}
