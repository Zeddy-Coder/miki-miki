import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;

import '../services/ui_theme_service.dart';
import '../utils/platform_info.dart';
import 'app_animation_kit.dart';
import 'app_tones.dart';
import 'app_ui_kit.dart' show onAccent;
import 'line_icons.dart';
import 'settings_kit.dart' show SettingsFont;

/// Building blocks of the new design shared by the main tabs and their windows: flat rows with line icons,
/// group captions, soft plates, sheets (a bottom sheet on a phone, a window on a PC), drop-down menus
/// and the confirmation window. Sizes are given before scaling, as in the concepts.

TextStyle _text(double size, {Color? color, FontWeight weight = FontWeight.normal, double? height}) =>
    TextStyle(fontFamily: 'Arial', fontFamilyFallback: const ['MikiSans'], color: color ?? uiTheme.textPrimary, fontSize: size, fontWeight: weight, height: height);

// ───────── Rows and captions ─────────

/// A grey group caption ("Список", "Застосунок"); [inset] is the distance from the screen edge
class AppGroupCaption extends StatelessWidget {
  final double scale;
  final String text;
  final double inset;
  final double top;

  const AppGroupCaption({super.key, required this.scale, required this.text, required this.inset, this.top = 18});

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(inset, top * scale, inset, 4 * scale),
        child: Text(text, style: _text(13 * scale, color: AppTones.caption, weight: FontWeight.w700)),
      );
}

/// A flat row: a line icon (or [leading]), a title with a grey line under it, [trailing] on the right
/// (a value, a chevron, a switch). [inset] is the distance from the screen edge to the icon.
class AppLineRow extends StatelessWidget {
  final double scale;
  final double inset;
  final String title;
  final String? subtitle;
  final LineIcon? icon;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// Red title and icon (destructive actions)
  final bool danger;

  /// Content under the title (score plates)
  final Widget? below;

  /// A value on the right in the row's grey ("12", "12 днів 4 год")
  final String? value;

  /// A chevron on the right: the row leads to another screen
  final bool chevron;

  /// The title in one line (a long one ends with "…")
  final bool singleLine;

  const AppLineRow({
    super.key,
    required this.scale,
    required this.inset,
    required this.title,
    this.subtitle,
    this.icon,
    this.leading,
    this.trailing,
    this.onTap,
    this.danger = false,
    this.below,
    this.value,
    this.chevron = false,
    this.singleLine = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppTones.danger : uiTheme.textPrimary;
    final lead = leading ?? (icon == null ? null : LineIconView(icon!, size: 22 * scale, color: danger ? AppTones.danger : AppTones.rowIcon));
    final right = trailing ??
        (value != null
            ? Text(value!, style: _text(14 * scale, color: AppTones.plateText))
            : (chevron ? LineIconView(LineIcon.chevronRight, size: 18 * scale, color: AppTones.chevron) : null));
    final content = ConstrainedBox(
      // As tall as the text; a tappable row is at least 48 dp on a phone
      constraints: BoxConstraints(minHeight: AppPlatform.isMobile && onTap != null ? AppPlatform.touchTarget : 0),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: inset, vertical: 10 * scale),
        child: Row(
          crossAxisAlignment: below == null ? CrossAxisAlignment.center : CrossAxisAlignment.start,
          children: [
            if (lead != null) ...[SizedBox(width: 24 * scale, child: Center(child: lead)), SizedBox(width: 16 * scale)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: singleLine ? 1 : null,
                    overflow: singleLine ? TextOverflow.ellipsis : null,
                    style: _text(15 * scale, color: color, height: 1.25),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty)
                    Padding(
                      padding: EdgeInsets.only(top: 2 * scale),
                      child: Text(
                        subtitle!,
                        maxLines: singleLine ? 1 : null,
                        overflow: singleLine ? TextOverflow.ellipsis : null,
                        style: _text(12.5 * scale, color: AppTones.rowSub, height: 1.3),
                      ),
                    ),
                  if (below != null) Padding(padding: EdgeInsets.only(top: 10 * scale), child: below!),
                ],
              ),
            ),
            if (right != null) ...[SizedBox(width: 12 * scale), right],
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

/// A row led by a picture instead of a line icon (a round photo, a poster, a video frame): the title, a grey line
/// under it (or [below]), [trailing] on the right. Voice actors, the crew, notifications, recent files.
class AppMediaRow extends StatelessWidget {
  final double scale;
  final double inset;
  final Widget leading;
  final String title;
  final String? subtitle;
  final Widget? below;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final void Function(Offset global)? onSecondaryTap;

  /// A chevron on the right: the row leads to another page
  final bool chevron;

  /// A bold title (an unread notification)
  final bool bold;
  final int titleLines;
  final int subtitleLines;

  /// Space between the picture and the text
  final double gap;

  /// The text sits at the top of a tall picture (a poster), otherwise in the middle
  final bool top;

  const AppMediaRow({
    super.key,
    required this.scale,
    required this.inset,
    required this.leading,
    required this.title,
    this.subtitle,
    this.below,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.onSecondaryTap,
    this.chevron = false,
    this.bold = false,
    this.titleLines = 2,
    this.subtitleLines = 2,
    this.gap = 14,
    this.top = false,
  });

  @override
  Widget build(BuildContext context) {
    final right = trailing ?? (chevron ? LineIconView(LineIcon.chevronRight, size: 18 * scale, color: AppTones.chevron) : null);
    final content = Padding(
      padding: EdgeInsets.symmetric(horizontal: inset, vertical: 8 * scale),
      child: Row(
        crossAxisAlignment: top ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          leading,
          SizedBox(width: gap * scale),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: top ? 2 * scale : 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: titleLines,
                    overflow: TextOverflow.ellipsis,
                    style: _text(15 * scale, weight: bold ? FontWeight.w700 : FontWeight.normal, height: 1.25),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty)
                    Padding(
                      padding: EdgeInsets.only(top: 3 * scale),
                      child: Text(
                        subtitle!,
                        maxLines: subtitleLines,
                        overflow: TextOverflow.ellipsis,
                        style: _text(12.5 * scale, color: AppTones.rowSub, height: 1.3),
                      ),
                    ),
                  if (below != null) below!,
                ],
              ),
            ),
          ),
          if (right != null) ...[SizedBox(width: 10 * scale), right],
        ],
      ),
    );
    if (onTap == null && onLongPress == null && onSecondaryTap == null) return content;
    return Semantics(
      button: onTap != null,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        onSecondaryTapUp: onSecondaryTap == null ? null : (d) => onSecondaryTap!(d.globalPosition),
        splashColor: Colors.transparent,
        highlightColor: uiTheme.isLight ? Colors.black.withValues(alpha: 0.06) : Colors.white.withValues(alpha: 0.07),
        hoverColor: uiTheme.hoverOverlay,
        child: content,
      ),
    );
  }
}

// ───────── Plates ─────────

/// A soft plate: a status, a score, a filter. The chosen one is lighter, outlined, with bold white text;
/// [leading] gets the text color. [check] puts the accent check mark before the label of a chosen plate (filters).
class AppPlate extends StatelessWidget {
  final double scale;
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final Widget Function(Color color)? leading;
  final double height;
  final double radius;
  final bool check;

  /// Fills the given width with the label in the middle (score plates in a grid)
  final bool expand;

  const AppPlate({
    super.key,
    required this.scale,
    required this.label,
    this.selected = false,
    this.onTap,
    this.leading,
    this.height = 38,
    this.radius = 12,
    this.check = false,
    this.expand = false,
  });

  @override
  Widget build(BuildContext context) {
    final fg = selected ? uiTheme.textPrimary : AppTones.plateText;
    final shape = RoundedRectangleBorder(
      borderRadius: uiTheme.borderRadius(radius * scale),
      side: selected ? BorderSide(color: AppTones.plateOutline) : BorderSide.none,
    );
    final row = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (check && selected) ...[LineIconView(LineIcon.check, size: 15 * scale, color: uiTheme.accentColor, stroke: 2), SizedBox(width: 7 * scale)],
        if (leading != null) ...[leading!(fg), if (label.isNotEmpty) SizedBox(width: 8 * scale)],
        if (label.isNotEmpty)
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _text(13.5 * scale, color: fg, weight: selected ? FontWeight.w700 : FontWeight.normal),
            ),
          ),
      ],
    );
    return Semantics(
      button: onTap != null,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: selected ? AppTones.plateOn : AppTones.plate,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          splashColor: Colors.transparent,
          highlightColor: uiTheme.touchHighlight,
          hoverColor: uiTheme.hoverOverlay,
          onTap: onTap,
          child: SizedBox(
            height: height * scale,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: (expand ? 4 : 13) * scale),
              child: row,
            ),
          ),
        ),
      ),
    );
  }
}

/// A pill tab of the main tabs ("Усе", "Дивлюсь 6"): a line icon, a label and a grey counter; the chosen one is
/// washed with the accent and outlined, its text bold
class AppPillTab extends StatelessWidget {
  final double scale;
  final String label;
  final Widget Function(Color color)? icon;
  final String? count;
  final bool selected;
  final VoidCallback onTap;

  const AppPillTab({super.key, required this.scale, required this.label, required this.selected, required this.onTap, this.icon, this.count});

  @override
  Widget build(BuildContext context) {
    final accent = uiTheme.accentColor;
    final fg = selected ? accent : AppTones.plateText;
    final shape = RoundedRectangleBorder(
      borderRadius: uiTheme.borderRadius(18 * scale),
      side: BorderSide(color: selected ? accent : Colors.transparent),
    );
    return Semantics(
      button: true,
      selected: selected,
      label: count == null ? label : '$label: $count',
      excludeSemantics: true,
      child: Material(
        color: selected ? AppTones.accentWash : uiTheme.bgElevated,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          splashColor: Colors.transparent,
          highlightColor: uiTheme.touchHighlight,
          hoverColor: uiTheme.hoverOverlay,
          onTap: onTap,
          child: SizedBox(
            height: 36 * scale,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 14 * scale),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[icon!(fg), SizedBox(width: 7 * scale)],
                  Text(label, style: _text(13 * scale, color: fg, weight: selected ? FontWeight.w700 : FontWeight.normal)),
                  if (count != null) ...[
                    SizedBox(width: 5 * scale),
                    Text(count!, style: _text(13 * scale, color: selected ? accent.withValues(alpha: 0.75) : uiTheme.textDarkMuted)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ───────── Sheets ─────────

/// The close button of a sheet or a window
class AppSheetClose extends StatelessWidget {
  final double scale;

  const AppSheetClose({super.key, required this.scale});

  @override
  Widget build(BuildContext context) => Tooltip(
        message: 'Закрити',
        child: Semantics(
          button: true,
          label: 'Закрити',
          child: InkResponse(
            radius: 22 * scale,
            onTap: () => Navigator.of(context).pop(),
            child: SizedBox.square(
              dimension: 44 * scale,
              child: Center(child: LineIconView(LineIcon.close, size: 20 * scale, color: uiTheme.textDarkMuted)),
            ),
          ),
        ),
      );
}

/// The phone frame of a sheet: a handle, the title with a close button, a grey hint, the scrolling content
class AppSheetFrame extends StatelessWidget {
  final double scale;
  final String title;
  final String? hint;
  final Widget child;

  const AppSheetFrame({super.key, required this.scale, required this.title, required this.child, this.hint});

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: mq.size.height * 0.9),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 38 * scale,
              height: 4 * scale,
              margin: EdgeInsets.fromLTRB(0, 9 * scale, 0, 4 * scale),
              decoration: BoxDecoration(color: AppTones.dot, borderRadius: BorderRadius.circular(2 * scale)),
            ),
          ),
          _SheetTitle(scale: scale, title: title, hint: hint),
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.only(bottom: 20 * scale + mq.viewPadding.bottom),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetTitle extends StatelessWidget {
  final double scale;
  final String title;
  final String? hint;

  const _SheetTitle({required this.scale, required this.title, this.hint});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(18 * scale, 2 * scale, 8 * scale, 0),
          child: Row(
            children: [
              Expanded(child: Text(title, style: _text(18 * scale, weight: FontWeight.bold))),
              AppSheetClose(scale: scale),
            ],
          ),
        ),
        if (hint != null && hint!.isNotEmpty)
          Padding(
            padding: EdgeInsets.fromLTRB(18 * scale, 0, 18 * scale, 8 * scale),
            child: Text(hint!, style: _text(13 * scale, color: uiTheme.textMuted, height: 1.35)),
          ),
      ],
    );
  }
}

/// The PC frame of the same content: a window in the middle
class _SheetWindow extends StatelessWidget {
  final double scale;
  final String title;
  final String? hint;
  final Widget child;

  const _SheetWindow({required this.scale, required this.title, required this.child, this.hint});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Center(
      child: Padding(
        padding: EdgeInsets.all(24 * scale),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 460 * scale, maxHeight: size.height * 0.86),
          child: Material(
            color: uiTheme.bgSurface,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(borderRadius: uiTheme.borderRadius(22 * scale), side: BorderSide(color: AppTones.menuLine)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: 10 * scale),
                _SheetTitle(scale: scale, title: title, hint: hint),
                Flexible(child: SingleChildScrollView(padding: EdgeInsets.only(bottom: 14 * scale), child: child)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens a sheet: on a phone it slides up from the bottom, on a PC the same content is a window in the middle.
/// [builder] gets the sheet's context (to close it with a value: `Navigator.of(ctx).pop(value)`).
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required double scale,
  required String title,
  required WidgetBuilder builder,
  String? hint,
}) {
  if (AppPlatform.isMobile) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: uiTheme.bgSurface,
      barrierColor: Colors.black.withValues(alpha: 0.62),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24 * scale)),
        side: BorderSide(color: AppTones.menuLine),
      ),
      builder: (ctx) => SettingsFont(child: AppSheetFrame(scale: scale, title: title, hint: hint, child: Builder(builder: builder))),
    );
  }
  return AppDialogs.show<T>(
    context,
    builder: (ctx) => SettingsFont(child: _SheetWindow(scale: scale, title: title, hint: hint, child: Builder(builder: builder))),
  );
}

/// A choice row of a sheet: the chosen one is bold with the accent check mark on the right
class AppCheckRow extends StatelessWidget {
  final double scale;
  final String label;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  /// Something before the check mark: a key hint on a PC, the start time of a chapter
  final Widget? trailing;

  /// Something before the label: the cover of a chapter's song
  final Widget? leading;

  /// The side padding and the least height (the player's drop-down menu is tighter than a sheet)
  final double padH;
  final double minHeight;

  const AppCheckRow({
    super.key,
    required this.scale,
    required this.label,
    required this.selected,
    required this.onTap,
    this.subtitle,
    this.trailing,
    this.leading,
    this.padH = 18,
    this.minHeight = 52,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: InkWell(
        onTap: onTap,
        splashColor: Colors.transparent,
        highlightColor: uiTheme.isLight ? Colors.black.withValues(alpha: 0.06) : Colors.white.withValues(alpha: 0.07),
        hoverColor: uiTheme.hoverOverlay,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: minHeight * scale),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: padH * scale, vertical: 8 * scale),
            child: Row(
              children: [
                if (leading != null) ...[leading!, SizedBox(width: 14 * scale)],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: _text((minHeight < 52 ? 14 : 15) * scale, weight: selected ? FontWeight.w700 : FontWeight.normal)),
                      if (subtitle != null && subtitle!.isNotEmpty)
                        Padding(
                          padding: EdgeInsets.only(top: 2 * scale),
                          child: Text(subtitle!, style: _text(12.5 * scale, color: AppTones.rowSub, height: 1.3)),
                        ),
                    ],
                  ),
                ),
                if (trailing != null) ...[SizedBox(width: 12 * scale), trailing!],
                if (selected) ...[
                  SizedBox(width: 12 * scale),
                  LineIconView(LineIcon.check, size: (minHeight < 52 ? 20 : 22) * scale, color: uiTheme.accentColor, stroke: 2),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A picker as a sheet: the hint in grey, rows with a check mark; returns the chosen value (null when closed)
Future<T?> showAppPicker<T>(
  BuildContext context, {
  required double scale,
  required String title,
  required List<(T, String)> options,
  required T value,
  String? hint,
}) {
  return showAppSheet<T>(
    context,
    scale: scale,
    title: title,
    hint: hint,
    builder: (ctx) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (v, label) in options) AppCheckRow(scale: scale, label: label, selected: v == value, onTap: () => Navigator.of(ctx).pop(v)),
      ],
    ),
  );
}

// ───────── Menus ─────────

/// A drop-down menu entry: a value with a label (and maybe a line icon), or a divider
class AppMenuEntry<T> {
  final T? value;
  final String label;
  final Widget Function(Color color)? icon;
  final bool selected;
  final bool danger;
  final bool divider;

  const AppMenuEntry(T this.value, this.label, {this.icon, this.selected = false, this.danger = false}) : divider = false;

  const AppMenuEntry.divider()
      : value = null,
        label = '',
        icon = null,
        selected = false,
        danger = false,
        divider = true;
}

/// Where a widget is on the screen (for [showAppMenu])
Rect appRectOf(BuildContext context) {
  final box = context.findRenderObject() as RenderBox;
  final overlay = Navigator.of(context).overlay?.context.findRenderObject() as RenderBox?;
  final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
  return topLeft & box.size;
}

/// A drop-down menu: one dark tile for all menus. A grey [caption] above the rows or a [title] (what the menu is about),
/// the chosen entry in bold with the accent check mark, destructive ones in red. It opens under [anchor] (above it
/// when there is no room) on a slightly dimmed screen. [lift] is drawn over the dimming in place of [anchor]
/// on a dark plate (the long-pressed card).
Future<T?> showAppMenu<T>(
  BuildContext context, {
  required double scale,
  required Rect anchor,
  required List<AppMenuEntry<T>> entries,
  String? caption,
  String? title,
  double width = 240,
  Widget? lift,
}) {
  return Navigator.of(context).push<T>(_AppMenuRoute<T>(
    scale: scale,
    anchor: anchor,
    entries: entries,
    caption: caption,
    title: title,
    width: width,
    lift: lift,
  ));
}

class _AppMenuRoute<T> extends PopupRoute<T> {
  final double scale;
  final Rect anchor;
  final List<AppMenuEntry<T>> entries;
  final String? caption;
  final String? title;
  final double width;
  final Widget? lift;

  _AppMenuRoute({
    required this.scale,
    required this.anchor,
    required this.entries,
    required this.caption,
    required this.title,
    required this.width,
    required this.lift,
  });

  @override
  Color? get barrierColor => Colors.black.withValues(alpha: lift != null ? 0.55 : 0.25);

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => 'Закрити меню';

  @override
  Duration get transitionDuration => const Duration(milliseconds: 160);

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
    final a = CurvedAnimation(parent: animation, curve: AppAnim.easeOut, reverseCurve: AppAnim.easeIn);
    return FadeTransition(opacity: a, child: child);
  }

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) {
    final s = scale;
    final menu = _MenuTile<T>(scale: s, entries: entries, caption: caption, title: title, width: width * s);
    return SettingsFont(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (lift != null) ...[
            Positioned.fromRect(
              rect: anchor.inflate(5 * s),
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppTones.menu,
                    borderRadius: uiTheme.borderRadius(15 * s),
                    border: Border.all(color: AppTones.plateOn),
                  ),
                ),
              ),
            ),
            Positioned.fromRect(rect: anchor, child: IgnorePointer(child: Material(type: MaterialType.transparency, child: lift!))),
          ],
          CustomSingleChildLayout(
            delegate: _MenuPlacement(anchor: lift != null ? anchor.inflate(5 * s) : anchor, gap: 6 * s, margin: 12 * s),
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.96, end: 1).animate(CurvedAnimation(parent: animation, curve: AppAnim.easeOut)),
              alignment: Alignment.topCenter,
              child: menu,
            ),
          ),
        ],
      ),
    );
  }
}

/// Puts the menu under the anchor, left edges aligned; above it when there is no room below; always inside the screen
class _MenuPlacement extends SingleChildLayoutDelegate {
  final Rect anchor;
  final double gap;
  final double margin;

  _MenuPlacement({required this.anchor, required this.gap, required this.margin});

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(Size(constraints.maxWidth - margin * 2, constraints.maxHeight - margin * 2));

  @override
  Offset getPositionForChild(Size size, Size child) {
    final x = anchor.left.clamp(margin, math.max(margin, size.width - child.width - margin));
    double y = anchor.bottom + gap;
    if (y + child.height > size.height - margin) {
      final above = anchor.top - gap - child.height;
      y = above >= margin ? above : math.max(margin, size.height - margin - child.height);
    }
    return Offset(x.toDouble(), y);
  }

  @override
  bool shouldRelayout(_MenuPlacement old) => old.anchor != anchor || old.gap != gap || old.margin != margin;
}

class _MenuTile<T> extends StatelessWidget {
  final double scale;
  final List<AppMenuEntry<T>> entries;
  final String? caption;
  final String? title;
  final double width;

  const _MenuTile({required this.scale, required this.entries, required this.caption, required this.title, required this.width});

  @override
  Widget build(BuildContext context) {
    final s = scale;
    final withIcons = entries.any((e) => e.icon != null);
    Widget row(AppMenuEntry<T> e) {
      final color = e.danger ? AppTones.danger : uiTheme.textPrimary;
      final iconColor = e.danger ? AppTones.danger : (e.selected ? uiTheme.accentColor : AppTones.menuIcon);
      return Semantics(
        button: true,
        selected: e.selected,
        child: InkWell(
          onTap: () => Navigator.of(context).pop(e.value),
          splashColor: Colors.transparent,
          highlightColor: uiTheme.isLight ? Colors.black.withValues(alpha: 0.06) : Colors.white.withValues(alpha: 0.07),
          hoverColor: uiTheme.hoverOverlay,
          child: SizedBox(
            height: (withIcons ? 46 : 44) * s,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16 * s),
              child: Row(
                children: [
                  if (e.icon != null) ...[SizedBox(width: 20 * s, child: Center(child: e.icon!(iconColor))), SizedBox(width: 14 * s)],
                  Expanded(
                    child: Text(
                      e.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _text(14.5 * s, color: color, weight: e.selected ? FontWeight.w700 : FontWeight.normal),
                    ),
                  ),
                  if (e.selected) LineIconView(LineIcon.check, size: 20 * s, color: uiTheme.accentColor, stroke: 2),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Material(
      color: AppTones.menu,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: uiTheme.borderRadius(16 * s), side: BorderSide(color: AppTones.menuLine)),
      clipBehavior: Clip.antiAlias,
      child: DecoratedBox(
        decoration: BoxDecoration(
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: uiTheme.isLight ? 0.18 : 0.6), blurRadius: 40, offset: const Offset(0, 12))],
        ),
        child: SizedBox(
          width: width,
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(vertical: 6 * s),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (title != null)
                  Padding(
                    padding: EdgeInsets.fromLTRB(16 * s, 8 * s, 16 * s, 6 * s),
                    child: Text(title!, maxLines: 1, overflow: TextOverflow.ellipsis, style: _text(13 * s, color: AppTones.plateText, weight: FontWeight.w700)),
                  ),
                if (caption != null)
                  Padding(
                    padding: EdgeInsets.fromLTRB(16 * s, 8 * s, 16 * s, 4 * s),
                    child: Text(caption!, style: _text(12 * s, color: AppTones.caption, weight: FontWeight.w700)),
                  ),
                for (final e in entries)
                  if (e.divider) Container(height: 1, margin: EdgeInsets.symmetric(vertical: 6 * s), color: AppTones.menuLine) else row(e),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ───────── Confirmation ─────────

/// A question with two equal buttons: "Скасувати" on a grey plate and the action: a destructive one in red text on
/// a dark red plate, an ordinary one on the accent. Returns true when the action is chosen.
Future<bool> showAppConfirm(
  BuildContext context, {
  required double scale,
  required String title,
  String? message,
  required String action,
  bool destructive = false,
  String cancel = 'Скасувати',
}) async {
  final s = scale;
  final result = await AppDialogs.show<bool>(
    context,
    barrierColor: Colors.black.withValues(alpha: 0.62),
    builder: (ctx) {
      Widget button(String label, {required bool primary}) {
        final Color bg = !primary ? AppTones.plate : (destructive ? AppTones.dangerPlate : uiTheme.accentColor);
        final Color fg = !primary ? uiTheme.textPrimary : (destructive ? AppTones.dangerText : onAccent(uiTheme.accentColor));
        final shape = RoundedRectangleBorder(borderRadius: uiTheme.borderRadius(12 * s));
        return Expanded(
          child: Material(
            color: bg,
            shape: shape,
            child: InkWell(
              customBorder: shape,
              splashColor: Colors.transparent,
              highlightColor: uiTheme.touchHighlight,
              hoverColor: uiTheme.hoverOverlay,
              onTap: () => Navigator.of(ctx).pop(primary),
              child: SizedBox(
                height: 44 * s,
                child: Center(
                  child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: _text(14.5 * s, color: fg, weight: primary ? FontWeight.w700 : FontWeight.normal)),
                ),
              ),
            ),
          ),
        );
      }

      return SettingsFont(
        child: Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 24 * s, vertical: 24 * s),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 400 * s),
              child: Material(
                color: uiTheme.bgSurface,
                shape: RoundedRectangleBorder(borderRadius: uiTheme.borderRadius(22 * s), side: BorderSide(color: AppTones.menuLine)),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20 * s, 22 * s, 20 * s, 18 * s),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(title, style: _text(18 * s, weight: FontWeight.bold, height: 1.25)),
                      if (message != null && message.isNotEmpty)
                        Padding(
                          padding: EdgeInsets.only(top: 8 * s),
                          child: Text(message, style: _text(14 * s, color: uiTheme.textMuted, height: 1.45)),
                        ),
                      SizedBox(height: 20 * s),
                      Row(children: [button(cancel, primary: false), SizedBox(width: 10 * s), button(action, primary: true)]),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
  return result ?? false;
}

// ───────── Episode ranges ─────────

/// The ranges of a long series ("1–100", "101–200"…) as a row of plates that scrolls sideways; the chosen one is in view
class AppRangeStrip extends StatefulWidget {
  final double scale;
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelect;

  const AppRangeStrip({super.key, required this.scale, required this.labels, required this.selected, required this.onSelect});

  @override
  State<AppRangeStrip> createState() => _AppRangeStripState();
}

class _AppRangeStripState extends State<AppRangeStrip> {
  final Map<int, GlobalKey> _keys = {};
  final ScrollController _strip = ScrollController();
  int? _shown;

  @override
  void dispose() {
    _strip.dispose();
    super.dispose();
  }

  /// Brings the chosen range into the middle of the strip. Only the strip scrolls: `Scrollable.ensureVisible` would
  /// also scroll the list around it (back to the top, away from the current episode)
  void _reveal() {
    final i = widget.selected;
    if (_shown == i) return;
    final first = _shown == null;
    _shown = i;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ro = _keys[i]?.currentContext?.findRenderObject();
      if (!mounted || ro == null || !_strip.hasClients) return;
      final viewport = RenderAbstractViewport.maybeOf(ro);
      if (viewport == null) return;
      final p = _strip.position;
      final target = viewport.getOffsetToReveal(ro, 0.5).offset.clamp(p.minScrollExtent, p.maxScrollExtent);
      if (first) {
        _strip.jumpTo(target);
      } else {
        _strip.animateTo(target, duration: AppAnim.medium, curve: AppAnim.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    _reveal();
    final scale = widget.scale;
    return SingleChildScrollView(
      key: const ValueKey('episode-ranges'),
      controller: _strip,
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (int i = 0; i < widget.labels.length; i++)
            Padding(
              key: _keys.putIfAbsent(i, GlobalKey.new),
              padding: EdgeInsets.only(right: 8 * scale),
              child: AppPlate(
                scale: scale,
                label: widget.labels[i],
                height: 34,
                radius: 10,
                selected: i == widget.selected,
                onTap: () => widget.onSelect(i),
              ),
            ),
        ],
      ),
    );
  }
}
