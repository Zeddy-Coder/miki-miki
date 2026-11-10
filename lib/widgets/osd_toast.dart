import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/osd_message.dart';
import '../services/ui_theme_service.dart';
import 'app_animation_kit.dart';

/// Екранне сповіщення поверх відео (гучність, швидкість, Anime4K, клавіші mpv…).
/// Завжди темне «скляне» — лежить на відео, тому не залежить від світлої / темної теми.
class OsdToast extends StatelessWidget {
  final double scale;
  final ValueListenable<OsdMessage?> message;

  /// Додатковий відступ згори (телефон: виріз / рядок стану)
  final double topInset;

  const OsdToast({super.key, required this.scale, required this.message, this.topInset = 0});

  static const Color _errorColor = Color(0xFFE5484D);

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

  @override
  Widget build(BuildContext context) {
    final accent = msg.isError ? OsdToast._errorColor : uiTheme.accentOnDark;
    final radius = uiTheme.borderRadius(14 * scale);

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: 460 * scale, minWidth: 150 * scale),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 9 * scale),
        decoration: BoxDecoration(
          color: const Color(0xFF16161A).withValues(alpha: 0.84),
          borderRadius: radius,
          border: Border.all(
            color: msg.isError ? OsdToast._errorColor.withValues(alpha: 0.55) : Colors.white.withValues(alpha: 0.14),
            width: 1.0,
          ),
        ),
        child: IntrinsicWidth(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 32 * scale,
                    height: 32 * scale,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.16),
                      borderRadius: uiTheme.borderRadius(9 * scale),
                    ),
                    child: Icon(msg.icon, color: accent, size: 19 * scale, weight: 300, opticalSize: 24),
                  ),
                  SizedBox(width: 11 * scale),
                  Flexible(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          msg.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Arial',
                            color: Colors.white,
                            fontSize: 13.5 * scale,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (msg.detail != null && msg.detail!.isNotEmpty) ...[
                          SizedBox(height: 1 * scale),
                          Text(
                            msg.detail!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Arial',
                              color: Colors.white.withValues(alpha: 0.72),
                              fontSize: 12 * scale,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (msg.keys.isNotEmpty) ...[
                    SizedBox(width: 14 * scale),
                    for (int i = 0; i < msg.keys.length; i++) ...[
                      if (i > 0) SizedBox(width: 4 * scale),
                      _OverlayKeyCap(scale: scale, text: msg.keys[i]),
                    ],
                  ],
                ],
              ),
              if (msg.progress != null) ...[
                SizedBox(height: 8 * scale),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2 * scale),
                  child: SizedBox(
                    height: 3 * scale,
                    child: Stack(
                      children: [
                        Positioned.fill(child: ColoredBox(color: Colors.white.withValues(alpha: 0.18))),
                        Positioned.fill(
                          child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: msg.progress!.clamp(0.0, 1.0),
                            child: ColoredBox(color: accent),
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
      ),
    );
  }
}

/// Кнопка клавіатури для темних оверлеїв
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
