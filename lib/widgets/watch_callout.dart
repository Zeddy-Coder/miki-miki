import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../services/episode_check.dart';
import '../services/ui_theme_service.dart';

/// Жовтий для застережень про серії: на світлій темі темніший, щоб текст читався на білому
Color watchWarnColor() => uiTheme.isLight ? const Color(0xFFB45309) : const Color(0xFFFFC23D);

/// Варіант варто показати із застереженням: нумерація не збігається з Hikka або тайтл завершено, а серій менше
bool episodeCheckWarns(EpisodeCheck c) => c.isWarning || c.level == EpisodeCheckLevel.incomplete;

/// Плашка з іконкою й тлом кольору [color]: застереження, підказки, нагадування про ліцензію
class WatchCallout extends StatelessWidget {
  final double scale;
  final IconData icon;
  final Color color;
  final Widget child;

  const WatchCallout({super.key, required this.scale, required this.icon, required this.color, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 10 * scale),
      decoration: BoxDecoration(
        color: color.withValues(alpha: uiTheme.isLight ? 0.12 : 0.10),
        borderRadius: uiTheme.borderRadius(10 * scale),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(top: 1 * scale),
            child: Icon(icon, color: color, size: 18 * scale, fill: 1, weight: 300),
          ),
          SizedBox(width: 10 * scale),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// Пояснення розбіжності кількості / нумерації серій із Hikka ([EpisodeCheck.note]); без розбіжності нічого не малює
class EpisodeNote extends StatelessWidget {
  final double scale;
  final EpisodeCheck check;

  /// Дрібніший текст (для вузької бічної панелі)
  final bool compact;

  const EpisodeNote({super.key, required this.scale, required this.check, this.compact = false});

  @override
  Widget build(BuildContext context) {
    if (!check.hasNote) return const SizedBox.shrink();
    final warn = episodeCheckWarns(check);
    return WatchCallout(
      scale: scale,
      icon: warn ? Symbols.warning_rounded : Symbols.info_rounded,
      color: warn ? watchWarnColor() : uiTheme.accentColor,
      child: Text(
        check.note,
        style: TextStyle(fontFamily: 'Arial', color: uiTheme.textPrimary, fontSize: (compact ? 11.5 : 12.5) * scale, height: 1.45),
      ),
    );
  }
}
