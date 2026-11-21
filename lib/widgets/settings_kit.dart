import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../services/ui_theme_service.dart';
import '../utils/platform_info.dart';
import 'app_animation_kit.dart';
import 'design_kit.dart' show showAppPicker;

/// Settings building blocks: flat groups without cards. A muted caption above the rows; each row has an icon on the left,
/// a title with a grey line under it (the current value or a hint), a switch / mark on the right.
/// In a wide space (≥ [settingsWideWidth]) the caption with its hint stands in a column to the left of the rows.

/// The interface font where Arial is missing (Android): the bundled Liberation Sans with Arial's metrics.
/// Put into a subtree with [SettingsFont]; text fields need it in their own style.
const List<String> kUiFontFallback = ['MikiSans'];

/// Gives the subtree the Arial look on every platform (Arial on Windows, the bundled Liberation Sans elsewhere)
class SettingsFont extends StatelessWidget {
  final Widget child;

  const SettingsFont({super.key, required this.child});

  @override
  Widget build(BuildContext context) => DefaultTextStyle.merge(style: const TextStyle(fontFamilyFallback: kUiFontFallback), child: child);
}

/// From this width a group puts its caption into a left column
const double settingsWideWidth = 720;

/// Horizontal padding of a row; the text column starts at [settingsTextInset] (padding + icon + gap)
const double _rowPadH = 12;
const double settingsTextInset = _rowPadH + 24 + 16;

TextStyle _titleStyle(double scale) => TextStyle(fontFamily: 'Arial', color: uiTheme.textPrimary, fontSize: 15 * scale, fontWeight: FontWeight.w500, height: 1.25);
TextStyle _subStyle(double scale, {bool value = false}) =>
    TextStyle(fontFamily: 'Arial', color: value ? uiTheme.textMuted : uiTheme.textDarkMuted, fontSize: 12.5 * scale, height: 1.35);

// ───────── Spotlight (search result → the row flashes and scrolls into view) ─────────

/// Which row or group to spotlight: [target] is a row title or a group caption; [seq] grows with every new request.
/// [onShown] is called (after the frame) by the widget that played the spotlight.
class SettingsSpotlight extends InheritedWidget {
  final String? target;
  final int seq;
  final VoidCallback onShown;

  const SettingsSpotlight({super.key, required this.target, required this.seq, required this.onShown, required super.child});

  static SettingsSpotlight? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<SettingsSpotlight>();

  @override
  bool updateShouldNotify(SettingsSpotlight old) => target != old.target || seq != old.seq;
}

/// A place that can be spotlighted: scrolls into view and briefly lights up with the accent
class SettingsSpot extends StatefulWidget {
  final String id;
  final Widget child;
  final BorderRadius? radius;

  const SettingsSpot({super.key, required this.id, required this.child, this.radius});

  @override
  State<SettingsSpot> createState() => _SettingsSpotState();
}

class _SettingsSpotState extends State<SettingsSpot> with SingleTickerProviderStateMixin {
  late final AnimationController _flash = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800), value: 1);
  int _seen = -1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = SettingsSpotlight.maybeOf(context);
    if (s == null || s.target != widget.id || s.seq == _seen) return;
    _seen = s.seq;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      s.onShown();
      Scrollable.ensureVisible(context, alignment: 0.3, duration: AppAnim.medium, curve: AppAnim.easeOut);
      _flash.forward(from: 0);
    });
  }

  @override
  void dispose() {
    _flash.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _flash,
      builder: (context, child) {
        final t = _flash.value;
        // Holds for a moment, then fades out
        final a = t >= 1 ? 0.0 : (t < 0.35 ? 1.0 : 1 - (t - 0.35) / 0.65);
        if (a <= 0) return child!;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: uiTheme.accentColor.withValues(alpha: 0.16 * a),
            borderRadius: widget.radius ?? uiTheme.borderRadius(12),
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

// ───────── Groups and rows ─────────

/// A group of rows with a caption and a hint. Narrow: the caption above, the hint below; wide: both in a left column.
class SettingsGroup extends StatelessWidget {
  final double scale;
  final String? label;
  final String? hint;
  final List<Widget> rows;

  const SettingsGroup({super.key, required this.scale, required this.rows, this.label, this.hint});

  @override
  Widget build(BuildContext context) {
    final body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= settingsWideWidth * scale;
      if (wide) {
        return Container(
          padding: EdgeInsets.symmetric(vertical: 8 * scale),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: uiTheme.borderSubtle.withValues(alpha: 0.6)))),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 190 * scale,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(_rowPadH * scale, 14 * scale, 8 * scale, 8 * scale),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (label != null) _caption(scale, label!),
                      if (hint != null) ...[
                        SizedBox(height: 4 * scale),
                        Text(hint!, style: TextStyle(fontFamily: 'Arial', color: uiTheme.textDarkMuted, fontSize: 12 * scale, height: 1.4)),
                      ],
                    ],
                  ),
                ),
              ),
              SizedBox(width: 16 * scale),
              Expanded(child: body),
            ],
          ),
        );
      }
      return Padding(
        padding: EdgeInsets.only(bottom: 4 * scale),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (label != null)
              Padding(padding: EdgeInsets.fromLTRB(_rowPadH * scale, 16 * scale, _rowPadH * scale, 4 * scale), child: _caption(scale, label!))
            else
              SizedBox(height: 6 * scale),
            body,
            if (hint != null)
              Padding(
                padding: EdgeInsets.fromLTRB(_rowPadH * scale, 2 * scale, _rowPadH * scale, 6 * scale),
                child: Text(hint!, style: TextStyle(fontFamily: 'Arial', color: uiTheme.textDarkMuted, fontSize: 12 * scale, height: 1.35)),
              ),
          ],
        ),
      );
    });
  }

  Widget _caption(double scale, String text) => SettingsSpot(
        id: text,
        child: Text(text, style: TextStyle(fontFamily: 'Arial', color: uiTheme.textMuted, fontSize: 13 * scale, fontWeight: FontWeight.w700)),
      );
}

/// Padding for arbitrary content inside a group (lists, fields): aligned with the rows
class SettingsPad extends StatelessWidget {
  final double scale;
  final Widget child;

  /// Start at the text column (under the titles) instead of the icon column
  final bool indent;

  const SettingsPad({super.key, required this.scale, required this.child, this.indent = false});

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB((indent ? settingsTextInset : _rowPadH) * scale, 6 * scale, _rowPadH * scale, 10 * scale),
        child: child,
      );
}

/// One row: an icon (or [leading]), a title with a grey line under it, [trailing] on the right. With [onTap] the whole row is pressable.
class SettingsRow extends StatelessWidget {
  final double scale;
  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// The grey line is the current value (a bit brighter than a hint)
  final bool subtitleIsValue;

  /// Content under the title (a field, a slider) in the text column
  final Widget? below;

  /// Part of the title to emphasize (a search query)
  final String? highlight;

  const SettingsRow({
    super.key,
    required this.scale,
    required this.title,
    this.subtitle,
    this.icon,
    this.leading,
    this.trailing,
    this.onTap,
    this.subtitleIsValue = false,
    this.below,
    this.highlight,
  });

  Widget _title(double scale) {
    final style = _titleStyle(scale);
    final q = highlight?.trim().toLowerCase() ?? '';
    final at = q.isEmpty ? -1 : title.toLowerCase().indexOf(q);
    if (at < 0) return Text(title, style: style);
    return Text.rich(TextSpan(style: style, children: [
      TextSpan(text: title.substring(0, at)),
      TextSpan(text: title.substring(at, at + q.length), style: TextStyle(color: uiTheme.accentColor, fontWeight: FontWeight.w700)),
      TextSpan(text: title.substring(at + q.length)),
    ]));
  }

  @override
  Widget build(BuildContext context) {
    final lead = leading ?? (icon == null ? null : Icon(icon, size: 22 * scale, color: uiTheme.textSecondary, weight: 300, opticalSize: 24));
    final content = ConstrainedBox(
      constraints: BoxConstraints(minHeight: (AppPlatform.isMobile ? 56 : 50) * scale),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: _rowPadH * scale, vertical: 10 * scale),
        child: Row(
          crossAxisAlignment: below == null ? CrossAxisAlignment.center : CrossAxisAlignment.start,
          children: [
            if (lead != null) ...[SizedBox(width: 24 * scale, child: Center(child: lead)), SizedBox(width: 16 * scale)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _title(scale),
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    SizedBox(height: 2 * scale),
                    Text(subtitle!, style: _subStyle(scale, value: subtitleIsValue)),
                  ],
                  if (below != null) ...[SizedBox(height: 8 * scale), below!],
                ],
              ),
            ),
            if (trailing != null) ...[SizedBox(width: 12 * scale), trailing!],
          ],
        ),
      ),
    );
    final radius = uiTheme.borderRadius(12 * scale);
    final Widget row = onTap == null
        ? content
        : InkWell(
            onTap: onTap,
            borderRadius: radius,
            splashColor: Colors.transparent,
            highlightColor: uiTheme.isLight ? Colors.black.withValues(alpha: 0.06) : Colors.white.withValues(alpha: 0.07),
            hoverColor: uiTheme.hoverOverlay,
            child: content,
          );
    return SettingsSpot(id: title, radius: radius, child: row);
  }
}

/// The switch of a [SettingsToggleRow]
class SettingsSwitch extends StatelessWidget {
  final double scale;
  final bool value;

  const SettingsSwitch({super.key, required this.scale, required this.value});

  @override
  Widget build(BuildContext context) => AppAnimatedContainer(
        duration: AppAnim.fast,
        curve: AppAnim.easeOut,
        width: 46 * scale,
        height: 26 * scale,
        padding: EdgeInsets.all(3 * scale),
        decoration: BoxDecoration(
          color: value ? uiTheme.accentColor : (uiTheme.isLight ? const Color(0xFFD4D4DE) : const Color(0xFF2E2E34)),
          borderRadius: BorderRadius.circular(13 * scale),
        ),
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(width: 20 * scale, height: 20 * scale, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
      );
}

/// A row with a switch; the whole row toggles it.
class SettingsToggleRow extends StatelessWidget {
  final double scale;
  final String title;
  final String? subtitle;
  final IconData? icon;
  final bool value;
  final ValueChanged<bool> onChanged;

  const SettingsToggleRow({super.key, required this.scale, required this.title, required this.value, required this.onChanged, this.subtitle, this.icon});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      toggled: value,
      label: title,
      child: SettingsRow(
        scale: scale,
        title: title,
        subtitle: subtitle,
        icon: icon,
        onTap: () => onChanged(!value),
        trailing: SettingsSwitch(scale: scale, value: value),
      ),
    );
  }
}

/// The radio mark (sits in the icon column of a row)
class SettingsRadioMark extends StatelessWidget {
  final double scale;
  final bool selected;

  const SettingsRadioMark({super.key, required this.scale, required this.selected});

  @override
  Widget build(BuildContext context) => AppAnimatedContainer(
        duration: AppAnim.fast,
        curve: AppAnim.easeOut,
        width: 22 * scale,
        height: 22 * scale,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: selected ? uiTheme.accentColor : uiTheme.textMuted, width: 2),
        ),
        child: Center(
          child: AppAnimatedContainer(
            duration: AppAnim.fast,
            curve: AppAnim.easeOut,
            width: selected ? 10 * scale : 0,
            height: selected ? 10 * scale : 0,
            decoration: BoxDecoration(color: uiTheme.accentColor, shape: BoxShape.circle),
          ),
        ),
      );
}

/// A row with a radio mark in the icon column.
class SettingsRadioRow extends StatelessWidget {
  final double scale;
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;
  final Widget? trailing;

  const SettingsRadioRow({super.key, required this.scale, required this.title, required this.selected, required this.onTap, this.subtitle, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      button: true,
      child: SettingsRow(
        scale: scale,
        title: title,
        subtitle: subtitle,
        onTap: onTap,
        leading: SettingsRadioMark(scale: scale, selected: selected),
        trailing: trailing,
      ),
    );
  }
}

/// A group of radio rows: the choice is made right there.
class SettingsRadioGroup<T> extends StatelessWidget {
  final double scale;
  final String? label;
  final String? hint;
  final List<(T, String, String?)> options;
  final T value;
  final ValueChanged<T> onChanged;

  const SettingsRadioGroup({super.key, required this.scale, required this.options, required this.value, required this.onChanged, this.label, this.hint});

  @override
  Widget build(BuildContext context) => SettingsGroup(
        scale: scale,
        label: label,
        hint: hint,
        rows: [
          for (final (v, title, sub) in options) SettingsRadioRow(scale: scale, title: title, subtitle: sub, selected: v == value, onTap: () => onChanged(v)),
        ],
      );
}

/// A row that shows the current value as the grey line; a tap opens a picker. [subtitle] is the hint shown in the picker.
class SettingsChoiceRow<T> extends StatelessWidget {
  final double scale;
  final String title;
  final String? subtitle;
  final IconData? icon;

  /// Its own drawing in place of [icon]
  final Widget? leading;
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;

  const SettingsChoiceRow({super.key, required this.scale, required this.title, required this.options, required this.value, required this.onChanged, this.subtitle, this.icon, this.leading});

  String get _current {
    for (final (v, l) in options) {
      if (v == value) return l;
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return SettingsRow(
      scale: scale,
      title: title,
      subtitle: _current,
      subtitleIsValue: true,
      icon: icon,
      leading: leading,
      onTap: () async {
        final picked = await showSettingsPicker<T>(context, scale: scale, title: title, hint: subtitle, options: options, value: value);
        if (picked != null && picked != value) onChanged(picked);
      },
    );
  }
}

/// The picker of [SettingsChoiceRow]: on a phone a sheet, on a PC a window in the middle, with check-mark rows;
/// returns the chosen value (null when closed).
Future<T?> showSettingsPicker<T>(
  BuildContext context, {
  required double scale,
  required String title,
  required List<(T, String)> options,
  required T value,
  String? hint,
}) =>
    showAppPicker<T>(context, scale: scale, title: title, options: options, value: value, hint: hint);

/// A row with a slider under the title; the current value is shown on the right of the title.
class SettingsSliderRow extends StatelessWidget {
  final double scale;
  final String title;
  final String? subtitle;
  final IconData? icon;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double> onChanged;

  /// The finger is lifted (for values applied only at the end of the drag)
  final ValueChanged<double>? onChangeEnd;

  const SettingsSliderRow({
    super.key,
    required this.scale,
    required this.title,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.subtitle,
    this.icon,
    this.divisions,
    this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    return SettingsSpot(
      id: title,
      child: Padding(
        padding: EdgeInsets.fromLTRB(_rowPadH * scale, 12 * scale, _rowPadH * scale, 2 * scale),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 24 * scale,
              child: icon == null ? null : Icon(icon, size: 22 * scale, color: uiTheme.textSecondary, weight: 300, opticalSize: 24),
            ),
            SizedBox(width: 16 * scale),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(title, style: _titleStyle(scale))),
                      Text(valueLabel, style: _subStyle(scale, value: true).copyWith(fontSize: 13.5 * scale)),
                    ],
                  ),
                  if (subtitle != null)
                    Padding(padding: EdgeInsets.only(top: 2 * scale), child: Text(subtitle!, style: _subStyle(scale))),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      activeTrackColor: uiTheme.accentColor,
                      inactiveTrackColor: uiTheme.borderSubtle,
                      thumbColor: uiTheme.accentColor,
                      overlayShape: SliderComponentShape.noOverlay,
                    ),
                    child: Slider(value: value.clamp(min, max), min: min, max: max, divisions: divisions, onChanged: onChanged, onChangeEnd: onChangeEnd),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// How much of a limit is used: a bar with parts and a legend under it (e.g. the image cache)
class SettingsStorageBar extends StatelessWidget {
  final double scale;

  /// (label, bytes, color)
  final List<(String, int, Color)> parts;
  final int total;
  final String Function(int bytes) format;
  final String? totalLabel;

  const SettingsStorageBar({super.key, required this.scale, required this.parts, required this.total, required this.format, this.totalLabel});

  @override
  Widget build(BuildContext context) {
    final legend = TextStyle(fontFamily: 'Arial', color: uiTheme.textDarkMuted, fontSize: 12 * scale);
    Widget dot(Color c) => Container(width: 9 * scale, height: 9 * scale, margin: EdgeInsets.only(right: 6 * scale), decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2.5 * scale)));
    return Padding(
      padding: EdgeInsets.fromLTRB(settingsTextInset * scale, 4 * scale, _rowPadH * scale, 6 * scale),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4 * scale),
            child: SizedBox(
              height: 8 * scale,
              child: LayoutBuilder(builder: (context, box) {
                var left = box.maxWidth;
                return Stack(
                  children: [
                    Positioned.fill(child: ColoredBox(color: uiTheme.isLight ? const Color(0xFFDDDDE6) : const Color(0xFF26262B))),
                    Row(
                      children: [
                        for (final (_, bytes, color) in parts)
                          Builder(builder: (_) {
                            final w = total <= 0 ? 0.0 : (box.maxWidth * bytes / total).clamp(bytes > 0 ? 3.0 : 0.0, left);
                            left -= w;
                            return Container(width: w, color: color);
                          }),
                      ],
                    ),
                  ],
                );
              }),
            ),
          ),
          SizedBox(height: 8 * scale),
          Wrap(
            spacing: 14 * scale,
            runSpacing: 4 * scale,
            children: [
              for (final (label, bytes, color) in parts)
                Row(mainAxisSize: MainAxisSize.min, children: [dot(color), Text('$label ${format(bytes)}', style: legend)]),
              if (totalLabel != null)
                Row(mainAxisSize: MainAxisSize.min, children: [dot(uiTheme.isLight ? const Color(0xFFDDDDE6) : const Color(0xFF26262B)), Text(totalLabel!, style: legend)]),
            ],
          ),
        ],
      ),
    );
  }
}

// ───────── Navigation: search, section tiles and the tab strip ─────────

/// The settings search field: a wide pill (start screen) or a compact one (window title row)
class SettingsSearchBar extends StatefulWidget {
  final double scale;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final bool compact;

  const SettingsSearchBar({super.key, required this.scale, required this.controller, required this.onChanged, this.compact = false});

  @override
  State<SettingsSearchBar> createState() => _SettingsSearchBarState();
}

class _SettingsSearchBarState extends State<SettingsSearchBar> {
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_refresh);
    widget.controller.addListener(_refresh);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    _focus.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.scale;
    final h = (widget.compact ? 38 : 48) * scale;
    final focused = _focus.hasFocus;
    final font = (widget.compact ? 13 : 14.5) * scale;
    return AppAnimatedContainer(
      key: const ValueKey('settings-search'),
      duration: AppAnim.fast,
      curve: AppAnim.easeOut,
      height: h,
      padding: EdgeInsets.only(left: (widget.compact ? 12 : 16) * scale, right: 6 * scale),
      decoration: BoxDecoration(
        color: uiTheme.bgElevated,
        borderRadius: BorderRadius.circular(h / 2),
        border: Border.all(color: focused ? uiTheme.accentBorder : uiTheme.borderSubtle),
      ),
      child: Row(
        children: [
          Icon(Symbols.search_rounded, size: (widget.compact ? 18 : 21) * scale, color: focused ? uiTheme.accentColor : uiTheme.textMuted),
          SizedBox(width: 10 * scale),
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: _focus,
              onChanged: widget.onChanged,
              cursorColor: uiTheme.accentColor,
              style: TextStyle(fontFamily: 'Arial', fontFamilyFallback: kUiFontFallback, color: uiTheme.textPrimary, fontSize: font),
              decoration: InputDecoration(
                hintText: 'Пошук налаштувань',
                hintStyle: TextStyle(fontFamily: 'Arial', fontFamilyFallback: kUiFontFallback, color: uiTheme.textDarkMuted, fontSize: font),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 8 * scale),
              ),
            ),
          ),
          if (widget.controller.text.isNotEmpty)
            IconButton(
              padding: EdgeInsets.zero,
              constraints: BoxConstraints.tightFor(width: h - 8 * scale, height: h - 8 * scale),
              splashColor: Colors.transparent,
              highlightColor: uiTheme.touchHighlight,
              icon: Icon(Symbols.close_rounded, color: uiTheme.textMuted, size: 18 * scale),
              onPressed: () {
                widget.controller.clear();
                widget.onChanged('');
              },
            ),
        ],
      ),
    );
  }
}

/// A section on the settings start screen: an icon in a rounded tile, a title, what is inside, an arrow
class SettingsSectionTile extends StatelessWidget {
  final double scale;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const SettingsSectionTile({super.key, required this.scale, required this.icon, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final radius = uiTheme.borderRadius(14 * scale);
    return InkWell(
      onTap: onTap,
      borderRadius: radius,
      splashColor: Colors.transparent,
      highlightColor: uiTheme.isLight ? Colors.black.withValues(alpha: 0.06) : Colors.white.withValues(alpha: 0.07),
      hoverColor: uiTheme.hoverOverlay,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: 62 * scale),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: _rowPadH * scale, vertical: 9 * scale),
          child: Row(
            children: [
              Container(
                width: 40 * scale,
                height: 40 * scale,
                decoration: BoxDecoration(color: uiTheme.bgElevated, borderRadius: uiTheme.borderRadius(12 * scale), border: Border.all(color: uiTheme.borderSubtle)),
                child: Icon(icon, size: 21 * scale, color: uiTheme.textPrimary, weight: 300, opticalSize: 24),
              ),
              SizedBox(width: 14 * scale),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: _titleStyle(scale).copyWith(fontSize: 15.5 * scale)),
                    SizedBox(height: 2 * scale),
                    Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: _subStyle(scale)),
                  ],
                ),
              ),
              Icon(Symbols.chevron_right_rounded, size: 22 * scale, color: uiTheme.textDarkMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// A row of pill tabs with icons: scrolls sideways and keeps the active tab in view (centered)
class SettingsTabStrip extends StatefulWidget {
  final double scale;

  /// (id, icon, label)
  final List<(int, IconData, String)> tabs;
  final int active;
  final ValueChanged<int> onChanged;
  final EdgeInsets padding;

  const SettingsTabStrip({super.key, required this.scale, required this.tabs, required this.active, required this.onChanged, this.padding = EdgeInsets.zero});

  @override
  State<SettingsTabStrip> createState() => _SettingsTabStripState();
}

class _SettingsTabStripState extends State<SettingsTabStrip> {
  final Map<int, GlobalKey> _keys = {};
  int? _centered;

  void _center() {
    final tab = widget.active;
    if (_centered == tab) return;
    final first = _centered == null;
    _centered = tab;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _keys[tab]?.currentContext;
      if (!mounted || ctx == null) return;
      Scrollable.ensureVisible(ctx, alignment: 0.5, duration: first ? Duration.zero : AppAnim.medium, curve: AppAnim.easeOut);
    });
  }

  @override
  Widget build(BuildContext context) {
    _center();
    final mobile = AppPlatform.isMobile;
    final scale = widget.scale;
    final h = mobile ? 52.0 : 44 * scale;
    return SizedBox(
      height: h,
      // All tabs are built (a few of them): the active one can be scrolled to even when it is far to the right
      child: SingleChildScrollView(
        key: const ValueKey('settings-tab-strip'),
        scrollDirection: Axis.horizontal,
        padding: widget.padding,
        child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (id, icon, label) in widget.tabs)
            Padding(
              key: _keys.putIfAbsent(id, GlobalKey.new),
              padding: EdgeInsets.only(right: 8 * scale, top: 2, bottom: 2),
              child: Material(
                color: widget.active == id ? uiTheme.accentWash : uiTheme.bgElevated,
                shape: RoundedRectangleBorder(
                  borderRadius: uiTheme.borderRadius(26),
                  side: BorderSide(color: widget.active == id ? uiTheme.accentBorder : uiTheme.borderSubtle),
                ),
                child: InkWell(
                  key: ValueKey('settings-tab-$id'),
                  customBorder: RoundedRectangleBorder(borderRadius: uiTheme.borderRadius(26)),
                  splashColor: Colors.transparent,
                  highlightColor: uiTheme.touchHighlight,
                  hoverColor: uiTheme.hoverOverlay,
                  onTap: () => widget.onChanged(id),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: (mobile ? 14 : 13) * scale),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, size: (mobile ? 20 : 18) * scale, color: widget.active == id ? uiTheme.accentColor : uiTheme.textMuted, weight: 300, opticalSize: 24),
                        SizedBox(width: 8 * scale),
                        Text(
                          label,
                          style: TextStyle(
                            fontFamily: 'Arial',
                            color: widget.active == id ? uiTheme.accentColor : uiTheme.textMuted,
                            fontSize: (mobile ? 14 : 13) * scale,
                            fontWeight: widget.active == id ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
        ),
      ),
    );
  }
}
