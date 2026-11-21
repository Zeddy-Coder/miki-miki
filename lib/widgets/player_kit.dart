import 'package:flutter/material.dart';

import '../services/ui_theme_service.dart';
import 'app_tones.dart';
import 'line_icons.dart';

/// The player chrome in the new style: line icons straight on the video, without plates (a soft circle shows only
/// under the finger or cursor); the transport in translucent circles; pills for "1×" and "Серії". Always light on
/// dark, whatever the app's theme: it sits on a dark gradient over the video.
class PlayerTones {
  PlayerTones._();

  /// Icons and text over the video
  static const Color fg = Color(0xFFF2F2F4);

  /// The grey line under the title ("Серія 6 з 28 · Inari")
  static const Color sub = Color(0xFFCFCFD4);

  /// A disabled button (no previous episode)
  static const Color disabled = Color(0x61FFFFFF);

  /// A pill over the video
  static const Color pill = Color(0x9E18181C);
  static const Color pillLine = Color(0x14FFFFFF);

  /// The translucent circles of the transport
  static const Color circle = Color(0x4D000000);
  static const Color circleBig = Color(0x61000000);

  /// The open menu's button, an engaged feature: the accent
  static Color get active => uiTheme.accentOnDark;
}

/// The touch / hover feedback shared by the player's buttons: a light circle (or pill) under the finger or cursor
class _Press extends StatefulWidget {
  final Widget Function(bool hover, bool pressed) builder;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onSecondaryTap;

  const _Press({required this.builder, this.onTap, this.onLongPress, this.onSecondaryTap});

  @override
  State<_Press> createState() => _PressState();
}

class _PressState extends State<_Press> {
  bool _hover = false;
  bool _pressed = false;

  bool get _interactive => widget.onTap != null || widget.onLongPress != null || widget.onSecondaryTap != null;

  void _setPressed(bool v) {
    if (_pressed != v && mounted) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final interactive = _interactive;
    return MouseRegion(
      cursor: interactive ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        onSecondaryTap: widget.onSecondaryTap,
        onTapDown: interactive ? (_) => _setPressed(true) : null,
        onTapUp: interactive ? (_) => _setPressed(false) : null,
        onTapCancel: interactive ? () => _setPressed(false) : null,
        child: widget.builder(_hover && interactive, _pressed && interactive),
      ),
    );
  }
}

/// A line icon over the video ([size] is the touch area, [iconSize] the glyph). [active] paints it in the accent (its
/// menu is open, rotation is locked); [badge] adds a small accent dot (Anime4K or subtitles are on).
class PlayerIconButton extends StatelessWidget {
  final LineIcon icon;

  /// Its own drawing in place of [icon] (the ±N s arrow)
  final Widget? glyph;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onSecondaryTap;
  final bool active;
  final bool badge;
  final String? label;
  final double size;
  final double iconSize;
  final double stroke;

  const PlayerIconButton({
    super.key,
    required this.icon,
    this.glyph,
    this.onTap,
    this.onLongPress,
    this.onSecondaryTap,
    this.active = false,
    this.badge = false,
    this.label,
    this.size = 48,
    this.iconSize = 24,
    this.stroke = 1.7,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null || onLongPress != null || onSecondaryTap != null;
    final color = !enabled ? PlayerTones.disabled : (active ? PlayerTones.active : PlayerTones.fg);
    return Semantics(
      button: true,
      enabled: enabled,
      selected: active,
      label: label,
      child: _Press(
        onTap: onTap,
        onLongPress: onLongPress,
        onSecondaryTap: onSecondaryTap,
        builder: (hover, pressed) => SizedBox.square(
          dimension: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: size * 0.84,
                height: size * 0.84,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: pressed ? 0.18 : (hover ? 0.10 : 0)),
                ),
              ),
              glyph ?? LineIconView(icon, size: iconSize, color: color, stroke: stroke),
              if (badge)
                Positioned(
                  top: size / 2 - iconSize / 2 - 1,
                  right: size / 2 - iconSize / 2 - 3,
                  child: Container(
                    width: 7.5,
                    height: 7.5,
                    decoration: BoxDecoration(
                      color: PlayerTones.active,
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF111111), width: 1.4),
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

/// A translucent circle of the transport (previous, −10, pause, +10, next); [child] is the glyph
class PlayerCircleButton extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double size;
  final bool big;
  final String? label;

  const PlayerCircleButton({super.key, required this.child, required this.onTap, this.size = 50, this.big = false, this.label});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: _Press(
        onTap: onTap,
        builder: (hover, pressed) => AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Color.alphaBlend(
              Colors.white.withValues(alpha: pressed ? 0.16 : (hover ? 0.08 : 0)),
              big ? PlayerTones.circleBig : PlayerTones.circle,
            ),
          ),
          child: Opacity(opacity: enabled ? 1 : 0.4, child: child),
        ),
      ),
    );
  }
}

/// The ±N s glyph: a round arrow with the step in the middle
class PlayerSeekGlyph extends StatelessWidget {
  final bool forward;
  final int seconds;
  final double size;

  const PlayerSeekGlyph({super.key, required this.forward, required this.seconds, this.size = 26});

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            LineIconView(forward ? LineIcon.forward : LineIcon.replay, size: size, color: PlayerTones.fg, stroke: 1.7),
            Padding(
              padding: EdgeInsets.only(top: size * 0.06),
              child: Text(
                '$seconds',
                style: TextStyle(fontFamily: 'Arial', color: PlayerTones.fg, fontSize: size * (seconds >= 100 ? 0.24 : 0.3), fontWeight: FontWeight.w700, height: 1),
              ),
            ),
          ],
        ),
      );
}

/// A pill over the video ("1×", "Серії"): a dark translucent plate with a thin light edge; [active] — the accent
class PlayerPill extends StatelessWidget {
  final String? text;
  final LineIcon? icon;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onSecondaryTap;
  final bool active;
  final String? label;
  final double height;
  final double fontSize;

  /// The touch area (≥ [height]): on a phone the pill is 40 dp tall but catches a 48 × 48 dp finger
  final double? hitHeight;

  /// Without a plate and an edge: only the text, a soft plate under the cursor ("1×" in the PC dock)
  final bool plain;

  const PlayerPill({
    super.key,
    this.text,
    this.icon,
    this.onTap,
    this.onLongPress,
    this.onSecondaryTap,
    this.active = false,
    this.label,
    this.height = 40,
    this.fontSize = 14,
    this.hitHeight,
    this.plain = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? PlayerTones.active : PlayerTones.fg;
    return Semantics(
      button: true,
      selected: active,
      label: label ?? text,
      excludeSemantics: label != null,
      child: _Press(
        onTap: onTap,
        onLongPress: onLongPress,
        onSecondaryTap: onSecondaryTap,
        builder: (hover, pressed) => _hit(AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: height,
          constraints: BoxConstraints(minWidth: height),
          padding: EdgeInsets.symmetric(horizontal: text == null ? 0 : height * 0.36),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: plain
                ? Colors.white.withValues(alpha: pressed ? 0.16 : (hover ? 0.10 : 0))
                : Color.alphaBlend(Colors.white.withValues(alpha: pressed ? 0.16 : (hover ? 0.08 : 0)), PlayerTones.pill),
            borderRadius: BorderRadius.circular(height / 2),
            border: Border.all(color: plain ? Colors.transparent : (active ? color.withValues(alpha: 0.7) : PlayerTones.pillLine)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) LineIconView(icon!, size: height * 0.46, color: color),
              if (icon != null && text != null) SizedBox(width: height * 0.18),
              if (text != null)
                Text(text!, maxLines: 1, style: TextStyle(fontFamily: 'Arial', fontFamilyFallback: const ['MikiSans'], color: color, fontSize: fontSize, fontWeight: FontWeight.w700)),
            ],
          ),
        )),
      ),
    );
  }

  /// A finger-sized touch area around the pill: at least [hitHeight] both ways, the pill centred in it
  Widget _hit(Widget pill) {
    final h = hitHeight;
    if (h == null || h <= height) return pill;
    return ConstrainedBox(constraints: BoxConstraints(minWidth: h, minHeight: h, maxHeight: h), child: Center(child: pill));
  }
}

/// The text of the player's menus: Arial with the bundled fallback (MikiSans on a phone)
TextStyle playerText(double size, {Color? color, FontWeight weight = FontWeight.normal, double? height, List<FontFeature>? features}) => TextStyle(
      fontFamily: 'Arial',
      fontFamilyFallback: const ['MikiSans'],
      color: color ?? uiTheme.textPrimary,
      fontSize: size,
      fontWeight: weight,
      height: height,
      fontFeatures: features,
    );

/// A row of the player's menus (settings, "Перегляд"): a line icon, the title (and a grey line under it), the value on
/// the right, a chevron. [sheet] — a phone (taller rows, wider side padding). Without [onTap] the row is quiet (nothing
/// to open: no chapters). Follows the app's light / dark theme, like the menus themselves
class PlayerMenuRow extends StatelessWidget {
  final double scale;
  final bool sheet;
  final LineIcon icon;
  final String title;
  final String? sub;
  final String? value;
  final bool chevron;
  final bool active;
  final VoidCallback? onTap;

  /// The icon's own colour (a yellow warning instead of the microphone)
  final Color? iconColor;

  /// Without [onTap] the row is greyed out (nothing to open); false keeps its normal look (a single dub: nothing to
  /// choose, but it is the main line of the panel)
  final bool dimWhenOff;

  /// In place of [icon]: a picture of its own (a streaming app's emblem)
  final Widget? leading;

  const PlayerMenuRow({
    super.key,
    required this.scale,
    required this.sheet,
    required this.icon,
    required this.title,
    this.sub,
    this.value,
    this.chevron = true,
    this.active = false,
    this.onTap,
    this.iconColor,
    this.dimWhenOff = true,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    final s = scale;
    final enabled = onTap != null || !dimWhenOff;
    final double titleSize = (sheet ? 15 : 14) * s;
    final Color titleColor = enabled ? uiTheme.textPrimary : uiTheme.textMuted;
    final Color valueColor = active ? uiTheme.accentColor : (enabled ? uiTheme.textSecondary : uiTheme.textMuted);
    final List<Widget> text;
    if (sub != null) {
      text = [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: playerText(titleSize, color: titleColor)),
              SizedBox(height: 2 * s),
              Text(sub!, maxLines: 1, overflow: TextOverflow.ellipsis, style: playerText(12.5 * s, color: AppTones.rowSub)),
            ],
          ),
        ),
      ];
    } else {
      text = [
        Text(title, maxLines: 1, style: playerText(titleSize, color: titleColor)),
        SizedBox(width: 12 * s),
        Expanded(
          child: value == null
              ? const SizedBox.shrink()
              : Text(value!, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.right, style: playerText((sheet ? 14 : 13.5) * s, color: valueColor)),
        ),
      ];
    }
    final content = ConstrainedBox(
      // A phone: the concept's density (≈ 48 dp per row, a finger's size), not stretched by the scale
      constraints: BoxConstraints(minHeight: sheet ? 48.0 : 42 * s),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: (sheet ? 20 : 16) * s, vertical: 7 * s),
        child: Row(
          children: [
            leading ??
                SizedBox(
                  width: 24 * s,
                  child: Center(child: LineIconView(icon, size: (sheet ? 22 : 20) * s, color: iconColor ?? (active ? uiTheme.accentColor : (enabled ? AppTones.rowIcon : AppTones.chevron)))),
                ),
            SizedBox(width: (sheet ? 16 : 14) * s),
            ...text,
            if (chevron) ...[SizedBox(width: 6 * s), LineIconView(LineIcon.chevronRight, size: 18 * s, color: AppTones.chevron)],
          ],
        ),
      ),
    );
    if (onTap == null) return content;
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        splashColor: Colors.transparent,
        highlightColor: uiTheme.isLight ? Colors.black.withValues(alpha: 0.06) : Colors.white.withValues(alpha: 0.07),
        hoverColor: uiTheme.hoverOverlay,
        child: content,
      ),
    );
  }
}
