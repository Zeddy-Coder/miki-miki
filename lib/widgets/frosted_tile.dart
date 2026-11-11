import 'package:flutter/material.dart';
import '../services/ui_theme_service.dart';

class FrostedTile extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final double opacity;
  final Color? borderColor;
  final Color? backgroundColor;
  final double? width;
  final double? height;
  final VoidCallback? onTap;
  final VoidCallback? onSecondaryTap;

  const FrostedTile({
    super.key,
    required this.child,
    this.borderRadius = 8.0,
    this.padding,
    this.opacity = 0.35,
    this.borderColor,
    this.backgroundColor,
    this.width,
    this.height,
    this.onTap,
    this.onSecondaryTap,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveRadius = uiTheme.radius(borderRadius);
    final radiusObj = uiTheme.borderRadius(effectiveRadius);

    final defaultBg = uiTheme.isLight
        ? uiTheme.colors.tileBg.withValues(alpha: opacity.clamp(0.60, 0.95))
        : uiTheme.colors.tileBg.withValues(alpha: opacity);

    final defaultBorder = uiTheme.isLight
        ? uiTheme.colors.borderSubtle
        : uiTheme.colors.tileBorder.withValues(alpha: 0.85);

    final content = ClipRRect(
      borderRadius: radiusObj,
      child: Container(
        width: width,
        height: height,
        padding: padding,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: backgroundColor ?? defaultBg,
          borderRadius: radiusObj,
          border: Border.all(
            color: borderColor ?? defaultBorder,
            width: 1.0,
          ),
        ),
        child: child,
      ),
    );

    if (onTap != null || onSecondaryTap != null) {
      return RepaintBoundary(
        child: Material(
          color: Colors.transparent,
          borderRadius: radiusObj,
          child: InkWell(
            borderRadius: radiusObj,
            splashColor: Colors.transparent,
            highlightColor: uiTheme.touchHighlight,
            hoverColor: uiTheme.isLight
                ? Colors.black.withValues(alpha: 0.05)
                : Colors.white.withValues(alpha: 0.08),
            onTap: onTap,
            onSecondaryTap: onSecondaryTap,
            child: content,
          ),
        ),
      );
    }

    return RepaintBoundary(child: content);
  }
}