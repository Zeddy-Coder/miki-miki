import 'dart:math' as math;
import 'package:flutter/physics.dart' show Simulation;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/services.dart' show SystemChannels;
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../constants/app_constants.dart';
import '../services/ui_theme_service.dart';
import '../utils/platform_info.dart';
import 'app_animation_kit.dart';

class EdgeToEdgeSliderTrackShape extends RoundedRectSliderTrackShape {
  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final double trackHeight = sliderTheme.trackHeight ?? 3.0;
    final double trackLeft = offset.dx;
    final double trackTop = offset.dy + (parentBox.size.height - trackHeight) / 2;
    final double trackWidth = parentBox.size.width;
    return Rect.fromLTWH(trackLeft, trackTop, trackWidth, trackHeight);
  }
}

class DotSliderThumbShape extends SliderComponentShape {
  final double enabledThumbRadius;
  final double innerDotRadius;

  const DotSliderThumbShape({
    this.enabledThumbRadius = 7.0,
    this.innerDotRadius = 3.0,
  });

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => Size.fromRadius(enabledThumbRadius);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final Canvas canvas = context.canvas;
    final Paint outerPaint = Paint()
      ..color = sliderTheme.thumbColor ?? uiTheme.accentColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, enabledThumbRadius, outerPaint);

    final Paint innerPaint = Paint()
      ..color = uiTheme.isLight ? const Color(0xFFFFFFFF) : const Color(0xFF111111)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, innerDotRadius, innerPaint);
  }
}

/// A range handle in the style of [DotSliderThumbShape]
class DotRangeSliderThumbShape extends RangeSliderThumbShape {
  final double enabledThumbRadius;
  final double innerDotRadius;

  const DotRangeSliderThumbShape({this.enabledThumbRadius = 7.0, this.innerDotRadius = 3.0});

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => Size.fromRadius(enabledThumbRadius);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    bool isDiscrete = false,
    bool isEnabled = false,
    bool? isOnTop,
    TextDirection? textDirection,
    required SliderThemeData sliderTheme,
    Thumb? thumb,
    bool? isPressed,
  }) {
    final canvas = context.canvas;
    canvas.drawCircle(center, enabledThumbRadius, Paint()..color = sliderTheme.thumbColor ?? uiTheme.accentColor);
    canvas.drawCircle(center, innerDotRadius, Paint()..color = uiTheme.isLight ? const Color(0xFFFFFFFF) : const Color(0xFF111111));
  }
}

class AppSegmentOption<T> {
  final T value;
  final String label;
  const AppSegmentOption({required this.value, required this.label});
}

class AppSegmentedBar<T> extends StatelessWidget {
  final double scale;
  final List<AppSegmentOption<T>> options;
  final T selectedValue;
  final ValueChanged<T> onSelected;

  const AppSegmentedBar({
    super.key,
    required this.scale,
    required this.options,
    required this.selectedValue,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final bool touch = AppPlatform.isMobile;
    return Container(
      // Phone: segments no lower than 48 dp (touch zone)
      height: touch ? AppPlatform.touchTarget : 38 * scale,
      padding: EdgeInsets.all(3.0 * scale),
      decoration: BoxDecoration(
        color: uiTheme.bgElevated,
        borderRadius: uiTheme.borderRadius(20 * scale),
        border: Border.all(color: uiTheme.borderSubtle, width: 1.0),
      ),
      child: Row(
        children: options.map((opt) {
          final isSelected = opt.value == selectedValue;
          return Expanded(
            child: AppPressable(
              onTap: () => onSelected(opt.value),
              behavior: HitTestBehavior.opaque,
              child: AppAnimatedContainer(
                duration: AppAnim.fast,
                curve: AppAnim.easeOut,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isSelected
                      ? (uiTheme.isLight ? uiTheme.bgSurface : uiTheme.accentWash)
                      : Colors.transparent,
                  borderRadius: uiTheme.borderRadius(16 * scale),
                  border: Border.all(
                    color: isSelected ? uiTheme.accentBorder : Colors.transparent,
                    width: 1.0,
                  ),
                  boxShadow: isSelected && uiTheme.isLight
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 4 * scale,
                            offset: Offset(0, 1 * scale),
                          ),
                        ]
                      : null,
                ),
                // A long label on a narrow segment shrinks into one line instead of breaking into two
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4 * scale),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      opt.label,
                      maxLines: 1,
                      style: TextStyle(
                        fontFamily: 'Arial',
                        color: isSelected ? uiTheme.accentColor : uiTheme.textMuted,
                        fontSize: 12.5 * scale,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class AppDropdownOption<T> {
  final T value;
  final String label;

  /// An extended item view: a thumbnail on the left, a title in place of [label] and a small line under it with an icon
  final Widget? leading;
  final String? title;
  final String? subtitle;
  final IconData? subtitleIcon;

  /// Color of the small line (yellow is a warning)
  final Color? subtitleColor;

  const AppDropdownOption({required this.value, required this.label, this.leading, this.title, this.subtitle, this.subtitleIcon, this.subtitleColor});

  bool get rich => subtitle != null || leading != null;
}

/// Contents of an [AppDropdownOption] item: a plain line or "thumbnail + title + small line with an icon"
class _OptionBody extends StatelessWidget {
  final AppDropdownOption option;
  final double scale;
  final TextStyle titleStyle;

  const _OptionBody({required this.option, required this.scale, required this.titleStyle});

  @override
  Widget build(BuildContext context) {
    final title = Text(option.title ?? option.label, style: titleStyle, maxLines: 1, overflow: TextOverflow.ellipsis);
    if (!option.rich) return title;
    return Row(
      children: [
        if (option.leading != null) ...[SizedBox(width: 28 * scale, height: 28 * scale, child: option.leading), SizedBox(width: 10 * scale)],
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              title,
              if (option.subtitle != null)
                Padding(
                  padding: EdgeInsets.only(top: 2 * scale),
                  child: Row(
                    children: [
                      if (option.subtitleIcon != null) ...[
                        Icon(option.subtitleIcon, size: 13 * scale, color: option.subtitleColor ?? uiTheme.textDarkMuted, weight: 400),
                        SizedBox(width: 4 * scale),
                      ],
                      Expanded(
                        child: Text(
                          option.subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontFamily: 'Arial', color: option.subtitleColor ?? uiTheme.textDarkMuted, fontSize: 11 * scale),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Standard compact selector without a search field
class AppDropdown<T> extends StatefulWidget {
  final double scale;
  final String? label;
  final String? subtitle;
  final T value;
  final List<AppDropdownOption<T>> options;
  final ValueChanged<T> onChanged;

  const AppDropdown({
    super.key,
    required this.scale,
    this.label,
    this.subtitle,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  State<AppDropdown<T>> createState() => _AppDropdownState<T>();
}

class _AppDropdownState<T> extends State<AppDropdown<T>> {
  bool _isExpanded = false;

  void _closeDropdown() {
    if (_isExpanded) {
      setState(() => _isExpanded = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.scale;
    final currentOption = widget.options.firstWhere(
      (o) => o.value == widget.value,
      orElse: () => widget.options.first,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label != null) ...[
          Text(
            widget.label!,
            style: TextStyle(
              fontFamily: 'Arial',
              color: uiTheme.textPrimary,
              fontSize: 13.5 * scale,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (widget.subtitle != null) ...[
            SizedBox(height: 2 * scale),
            Text(
              widget.subtitle!,
              style: TextStyle(
                fontFamily: 'Arial',
                color: uiTheme.textDarkMuted,
                fontSize: 11.5 * scale,
              ),
            ),
          ],
          SizedBox(height: 8 * scale),
        ],
        AppPressable(
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          behavior: HitTestBehavior.opaque,
          child: AppAnimatedContainer(
            duration: AppAnim.fast,
            curve: AppAnim.easeOut,
            height: (currentOption.rich ? 58 : 44) * scale,
            padding: EdgeInsets.symmetric(horizontal: 14 * scale),
            decoration: BoxDecoration(
              color: uiTheme.bgSurface,
              borderRadius: uiTheme.borderRadius(12 * scale),
              border: Border.all(
                color: _isExpanded ? uiTheme.accentBorder : uiTheme.borderSubtle,
                width: 1.0,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: _OptionBody(
                    option: currentOption,
                    scale: scale,
                    titleStyle: TextStyle(fontFamily: 'Arial', color: uiTheme.textPrimary, fontSize: 13 * scale, fontWeight: FontWeight.w600),
                  ),
                ),
                AppRotate(
                  turns: _isExpanded ? 0.5 : 0.0,
                  duration: AppAnim.fast,
                  curve: AppAnim.easeOut,
                  child: Icon(
                    Symbols.keyboard_arrow_down_rounded,
                    color: _isExpanded ? uiTheme.accentColor : uiTheme.textMuted,
                    size: 20 * scale,
                  ),
                ),
              ],
            ),
          ),
        ),
        AppVerticalCollapse(
          isExpanded: _isExpanded,
          duration: AppAnim.normal,
          curve: AppAnim.easeOut,
          child: Padding(
            padding: EdgeInsets.only(top: 6 * scale),
            child: Container(
              padding: EdgeInsets.all(4 * scale),
              decoration: BoxDecoration(
                color: uiTheme.bgSurface,
                borderRadius: uiTheme.borderRadius(12 * scale),
                border: Border.all(color: uiTheme.borderSubtle, width: 1.0),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: uiTheme.isLight ? 0.08 : 0.50),
                    blurRadius: 16 * scale,
                    offset: Offset(0, 6 * scale),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: widget.options.map((opt) {
                  final isSelected = opt.value == widget.value;
                  return AppPressable(
                    onTap: () {
                      widget.onChanged(opt.value);
                      _closeDropdown();
                    },
                    behavior: HitTestBehavior.opaque,
                    child: AppAnimatedContainer(
                      duration: AppAnim.fast,
                      curve: AppAnim.easeOut,
                      height: (opt.rich ? 54 : 38) * scale,
                      padding: EdgeInsets.symmetric(horizontal: 12 * scale),
                      margin: EdgeInsets.only(bottom: 2 * scale),
                      decoration: BoxDecoration(
                        color: isSelected ? uiTheme.accentWash : Colors.transparent,
                        borderRadius: uiTheme.borderRadius(8 * scale),
                      ),
                      child: Row(
                        children: [
                          if (isSelected)
                            Icon(Symbols.check_rounded, color: uiTheme.accentColor, size: 16 * scale)
                          else
                            SizedBox(width: 16 * scale),
                          SizedBox(width: 8 * scale),
                          Expanded(
                            child: _OptionBody(
                              option: opt,
                              scale: scale,
                              titleStyle: TextStyle(
                                fontFamily: 'Arial',
                                color: isSelected ? (uiTheme.isLight ? uiTheme.accentColor : Colors.white) : uiTheme.textSecondary,
                                fontSize: 12.5 * scale,
                                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A special dropdown with a search line for long lists
class AppSearchDropdown<T> extends StatefulWidget {
  final double scale;
  final String? label;
  final String? subtitle;
  final String searchHint;
  final T value;
  final List<AppDropdownOption<T>> options;
  final ValueChanged<T> onChanged;

  /// The label in the closed field when the value is not among the items (the list only "adds" a value)
  final String? placeholder;

  /// If set, a search with no matches offers to add the entered text as a custom value
  final ValueChanged<String>? onAddCustom;

  /// "Ballot" mode: items with checkboxes, choosing does not close the list (it closes by tapping outside the block).
  /// Here, the set of values currently marked; [onChanged] toggles a value
  final Set<T>? multiSelected;

  const AppSearchDropdown({
    super.key,
    required this.scale,
    this.label,
    this.subtitle,
    this.searchHint = 'Пошук...',
    required this.value,
    required this.options,
    required this.onChanged,
    this.placeholder,
    this.onAddCustom,
    this.multiSelected,
  });

  @override
  State<AppSearchDropdown<T>> createState() => _AppSearchDropdownState<T>();
}

class _AppSearchDropdownState<T> extends State<AppSearchDropdown<T>> with WidgetsBindingObserver {
  bool _isExpanded = false;
  bool _keyboardOpen = false;
  final FocusNode _searchFocus = FocusNode();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String _searchQuery = "";

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchFocus.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  /// The keyboard appeared or disappeared: the search field rises to the top of the visible area so the list stays visible
  @override
  void didChangeMetrics() {
    if (!mounted) return;
    final open = View.of(context).viewInsets.bottom > 0;
    if (open != _keyboardOpen) setState(() => _keyboardOpen = open);
    if (_isExpanded) _revealList(delay: const Duration(milliseconds: 120));
  }

  /// Scrolls the page so the search field is at the top of the visible area and the list under it
  void _revealList({Duration? delay}) {
    Future.delayed(delay ?? AppAnim.normal + const Duration(milliseconds: 60), () {
      if (!mounted || !_isExpanded) return;
      Scrollable.ensureVisible(context, duration: AppAnim.normal, curve: AppAnim.easeOut, alignment: 0.0);
    });
  }

  void _closeDropdown() {
    setState(() {
      _isExpanded = false;
      _searchQuery = "";
      _searchController.clear();
    });
  }

  Widget _closedRow(double scale, String currentLabel, AppDropdownOption<T>? current) {
    return SizedBox.expand(
      child: GestureDetector(
              onTap: () {
                setState(() {
                  _isExpanded = true;
                  _searchQuery = "";
                  _searchController.clear();
                });
                _revealList();
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted || !_isExpanded) return;
                  _searchFocus.requestFocus();
                  SystemChannels.textInput.invokeMethod<void>('TextInput.show');
                });
              },
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 14 * scale),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        currentLabel,
                        style: TextStyle(
                          fontFamily: 'Arial',
                          color: current == null && widget.placeholder != null ? uiTheme.textMuted : uiTheme.textPrimary,
                          fontSize: 13 * scale,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(Symbols.unfold_more_rounded, color: uiTheme.textMuted, size: 18 * scale),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _searchRow(double scale) {
    return SizedBox.expand(
      child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 10 * scale),
              child: Row(
                children: [
                  Icon(Symbols.search_rounded, color: uiTheme.accentColor, size: 18 * scale),
                  SizedBox(width: 8 * scale),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      focusNode: _searchFocus,
                      style: TextStyle(
                        fontFamily: 'Arial',
                        color: uiTheme.textPrimary,
                        fontSize: 13 * scale,
                      ),
                      onChanged: (val) => setState(() => _searchQuery = val.trim()),
                      decoration: InputDecoration(
                        hintText: widget.searchHint,
                        hintStyle: TextStyle(
                          color: uiTheme.textDarkMuted,
                          fontSize: 12.5 * scale,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 8 * scale),
                      ),
                    ),
                  ),
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: Icon(Symbols.close_rounded, color: uiTheme.textMuted, size: 18 * scale),
                    onPressed: _closeDropdown,
                  ),
                ],
              ),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.scale;
    final current = widget.options.where((o) => o.value == widget.value).firstOrNull;
    final currentLabel = current?.label ?? widget.placeholder ?? (widget.options.isEmpty ? '' : widget.options.first.label);

    final filtered = widget.options.where((opt) {
      if (_searchQuery.isEmpty) return true;
      final query = _searchQuery.toLowerCase();
      return opt.label.toLowerCase().contains(query) ||
          opt.value.toString().toLowerCase().contains(query);
    }).toList();
    final multi = widget.multiSelected != null;

    return TapRegion(
      onTapOutside: (_) {
        if (_isExpanded) _closeDropdown();
      },
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label != null) ...[
          Text(
            widget.label!,
            style: TextStyle(
              fontFamily: 'Arial',
              color: uiTheme.textPrimary,
              fontSize: 13.5 * scale,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (widget.subtitle != null) ...[
            SizedBox(height: 2 * scale),
            Text(
              widget.subtitle!,
              style: TextStyle(
                fontFamily: 'Arial',
                color: uiTheme.textDarkMuted,
                fontSize: 11.5 * scale,
              ),
            ),
          ],
          SizedBox(height: 8 * scale),
        ],
        AppAnimatedContainer(
          duration: AppAnim.fast,
          curve: AppAnim.easeOut,
          height: 44 * scale,
          decoration: BoxDecoration(
            color: uiTheme.bgSurface,
            borderRadius: uiTheme.borderRadius(12 * scale),
            border: Border.all(
              color: _isExpanded ? uiTheme.accentBorder : uiTheme.borderSubtle,
              width: 1.0,
            ),
          ),
          child: AnimatedSwitcher(
            duration: AppAnim.fast,
            switchInCurve: AppAnim.easeOut,
            switchOutCurve: AppAnim.easeOut,
            child: _isExpanded ? KeyedSubtree(key: const ValueKey('open'), child: _searchRow(scale)) : KeyedSubtree(key: const ValueKey('closed'), child: _closedRow(scale, currentLabel, current)),
          ),
        ),
        AppVerticalCollapse(
          isExpanded: _isExpanded,
          duration: AppAnim.normal,
          curve: AppAnim.easeOut,
          child: Padding(
            // A bottom reserve only with the keyboard open: the page can raise the search field to the top
            padding: EdgeInsets.only(top: 6 * scale, bottom: _keyboardOpen ? 140 * scale : 0),
            child: Container(
              constraints: BoxConstraints(maxHeight: 230 * scale),
              padding: EdgeInsets.all(4 * scale),
              decoration: BoxDecoration(
                color: uiTheme.bgSurface,
                borderRadius: uiTheme.borderRadius(12 * scale),
                border: Border.all(color: uiTheme.borderSubtle, width: 1.0),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: uiTheme.isLight ? 0.08 : 0.50),
                    blurRadius: 16 * scale,
                    offset: Offset(0, 6 * scale),
                  ),
                ],
              ),
              child: filtered.isEmpty && widget.onAddCustom != null && _searchQuery.isNotEmpty
                  ? GestureDetector(
                      onTap: () {
                        final v = _searchQuery;
                        widget.onAddCustom!(v);
                        if (multi) {
                          setState(() {
                            _searchQuery = '';
                            _searchController.clear();
                          });
                        } else {
                          _closeDropdown();
                        }
                      },
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 12 * scale, horizontal: 12 * scale),
                        child: Row(
                          children: [
                            Icon(Symbols.add_rounded, color: uiTheme.accentColor, size: 18 * scale),
                            SizedBox(width: 8 * scale),
                            Expanded(
                              child: Text(
                                'Додати «$_searchQuery»',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontFamily: 'Arial', color: uiTheme.accentColor, fontSize: 13 * scale, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : filtered.isEmpty
                  ? Container(
                      width: double.infinity,
                      padding: EdgeInsets.symmetric(vertical: 20 * scale, horizontal: 16 * scale),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Symbols.search_off_rounded,
                            color: uiTheme.textDarkMuted,
                            size: 24 * scale,
                          ),
                          SizedBox(height: 8 * scale),
                          Text(
                            'Нічого не знайдено',
                            style: TextStyle(
                              fontFamily: 'Arial',
                              color: uiTheme.textSecondary,
                              fontSize: 13 * scale,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(height: 3 * scale),
                          Text(
                            'Спробуйте змінити пошуковий запит',
                            style: TextStyle(
                              fontFamily: 'Arial',
                              color: uiTheme.textDarkMuted,
                              fontSize: 11.5 * scale,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  : ScrollConfiguration(
                      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
                      child: KeyedSubtree(
                        child: ListView.builder(
                          controller: _scrollController,
                          shrinkWrap: true,
                          padding: EdgeInsets.zero,
                          itemCount: filtered.length,
                          itemBuilder: (context, idx) {
                            final opt = filtered[idx];
                            final isSelected = multi ? widget.multiSelected!.contains(opt.value) : opt.value == widget.value;
                            return AppPressable(
                              onTap: () {
                                widget.onChanged(opt.value);
                                if (!multi) _closeDropdown();
                              },
                              behavior: HitTestBehavior.opaque,
                              child: AppAnimatedContainer(
                                duration: AppAnim.fast,
                                curve: AppAnim.easeOut,
                                padding: EdgeInsets.symmetric(
                                  horizontal: 12 * scale,
                                  vertical: 8.5 * scale,
                                ),
                                margin: EdgeInsets.only(bottom: 2 * scale),
                                decoration: BoxDecoration(
                                  color: isSelected ? uiTheme.accentWash : Colors.transparent,
                                  borderRadius: uiTheme.borderRadius(8 * scale),
                                ),
                                child: Row(
                                  children: [
                                    if (!multi) ...[
                                      if (isSelected)
                                        Icon(Symbols.check_rounded, color: uiTheme.accentColor, size: 16 * scale)
                                      else
                                        SizedBox(width: 16 * scale),
                                      SizedBox(width: 8 * scale),
                                    ],
                                    if (opt.leading != null) ...[
                                      opt.leading!,
                                      SizedBox(width: 10 * scale),
                                    ],
                                    Expanded(
                                      child: Text(
                                        opt.label,
                                        style: TextStyle(
                                          fontFamily: 'Arial',
                                          color: isSelected
                                              ? (uiTheme.isLight ? uiTheme.accentColor : Colors.white)
                                              : uiTheme.textSecondary,
                                          fontSize: 12.5 * scale,
                                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (multi) ...[
                                      SizedBox(width: 10 * scale),
                                      Container(
                                        width: 20 * scale,
                                        height: 20 * scale,
                                        decoration: BoxDecoration(
                                          color: isSelected ? uiTheme.accentColor : Colors.transparent,
                                          borderRadius: uiTheme.borderRadius(6 * scale),
                                          border: Border.all(color: isSelected ? uiTheme.accentColor : uiTheme.borderSubtle, width: 1.5),
                                        ),
                                        child: isSelected ? Icon(Symbols.check_rounded, size: 15 * scale, color: Colors.black, weight: 700) : null,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ],
    ),
    );
  }
}

/// A language priority queue with drag-and-drop and delete buttons
class AppLanguagePriorityList extends StatefulWidget {
  final double scale;
  final List<String> languages;
  final ValueChanged<List<String>> onChanged;

  const AppLanguagePriorityList({
    super.key,
    required this.scale,
    required this.languages,
    required this.onChanged,
  });

  @override
  State<AppLanguagePriorityList> createState() => _AppLanguagePriorityListState();
}

class _AppLanguagePriorityListState extends State<AppLanguagePriorityList> {
  bool _isAdding = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _getLangName(String code) {
    return AppConstants.langMap[code] ?? code;
  }

  void _move(int oldIndex, int newIndex) {
    if (newIndex < 0 || newIndex >= widget.languages.length) return;
    final list = List<String>.from(widget.languages);
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    widget.onChanged(list);
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.scale;
    final currentList = List<String>.from(widget.languages);

    final available = AppConstants.langMap.entries
        .where((e) => e.key.length == 2 && !currentList.contains(e.key))
        .toList();

    final filtered = available.where((e) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return e.value.toLowerCase().contains(q) || e.key.toLowerCase().contains(q);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (currentList.isEmpty)
          Container(
            padding: EdgeInsets.symmetric(vertical: 14 * scale, horizontal: 16 * scale),
            margin: EdgeInsets.only(bottom: 8 * scale),
            decoration: BoxDecoration(
              color: uiTheme.bgSurface,
              borderRadius: uiTheme.borderRadius(10 * scale),
              border: Border.all(color: uiTheme.borderSubtle),
            ),
            child: Row(
              children: [
                Icon(Symbols.info_rounded, color: uiTheme.textDarkMuted, size: 18 * scale),
                SizedBox(width: 8 * scale),
                Text(
                  'Список порожній. Додайте мови пріоритету нижче.',
                  style: TextStyle(
                    fontFamily: 'Arial',
                    color: uiTheme.textMuted,
                    fontSize: 12 * scale,
                  ),
                ),
              ],
            ),
          )
        else
          ExcludeSemantics(
            child: Theme(
              data: Theme.of(context).copyWith(
                canvasColor: Colors.transparent,
                shadowColor: Colors.transparent,
              ),
              child: ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                itemCount: currentList.length,
                onReorder: (oldIndex, newIndex) {
                  if (newIndex > oldIndex) newIndex -= 1;
                  _move(oldIndex, newIndex);
                },
                itemBuilder: (context, index) {
                  final code = currentList[index];
                  final name = _getLangName(code);
                  final isFirst = index == 0;
                  final isLast = index == currentList.length - 1;

                  return Container(
                    key: ValueKey(code),
                    margin: EdgeInsets.only(bottom: 6 * scale),
                    padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 7 * scale),
                    decoration: BoxDecoration(
                      color: uiTheme.bgSurface,
                      borderRadius: uiTheme.borderRadius(10 * scale),
                      border: Border.all(color: uiTheme.borderSubtle, width: 1.0),
                    ),
                    child: Row(
                      children: [
                        AppDragHandle(scale: scale, index: index),
                        SizedBox(width: 4 * scale),
                        Container(
                          width: 22 * scale,
                          height: 22 * scale,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: isFirst ? uiTheme.accentWash : uiTheme.bgElevated,
                            borderRadius: uiTheme.borderRadius(6 * scale),
                            border: Border.all(
                              color: isFirst ? uiTheme.accentBorder : uiTheme.borderSubtle,
                            ),
                          ),
                          child: Text(
                            '${index + 1}',
                            style: TextStyle(
                              fontFamily: 'Arial',
                              color: isFirst ? uiTheme.accentColor : uiTheme.textMuted,
                              fontSize: 11 * scale,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        SizedBox(width: 10 * scale),
                        Expanded(
                          child: Text(
                            '$name ($code)',
                            style: TextStyle(
                              fontFamily: 'Arial',
                              color: uiTheme.textPrimary,
                              fontSize: 13 * scale,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        if (currentList.length > 1) ...[
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            splashColor: Colors.transparent,
                            highlightColor: uiTheme.touchHighlight,
                            icon: Icon(
                              Symbols.keyboard_arrow_up_rounded,
                              color: isFirst
                                  ? (uiTheme.isLight ? const Color(0xFFDDDDDD) : const Color(0xFF333333))
                                  : uiTheme.textMuted,
                              size: 18 * scale,
                            ),
                            onPressed: isFirst ? null : () => _move(index, index - 1),
                          ),
                          SizedBox(width: 4 * scale),
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            splashColor: Colors.transparent,
                            highlightColor: uiTheme.touchHighlight,
                            icon: Icon(
                              Symbols.keyboard_arrow_down_rounded,
                              color: isLast
                                  ? (uiTheme.isLight ? const Color(0xFFDDDDDD) : const Color(0xFF333333))
                                  : uiTheme.textMuted,
                              size: 18 * scale,
                            ),
                            onPressed: isLast ? null : () => _move(index, index + 1),
                          ),
                          SizedBox(width: 8 * scale),
                        ],
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          splashColor: Colors.transparent,
                          highlightColor: uiTheme.touchHighlight,
                          icon: Icon(
                            Symbols.close_rounded,
                            color: uiTheme.textDarkMuted,
                            size: 17 * scale,
                          ),
                          onPressed: () {
                            final list = List<String>.from(widget.languages);
                            list.removeAt(index);
                            widget.onChanged(list);
                          },
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        SizedBox(height: 6 * scale),
        if (!_isAdding)
          Material(
            color: Colors.transparent,
            borderRadius: uiTheme.borderRadius(8 * scale),
            child: InkWell(
              onTap: () => setState(() => _isAdding = true),
              borderRadius: uiTheme.borderRadius(8 * scale),
              splashColor: Colors.transparent,
              highlightColor: uiTheme.touchHighlight,
              hoverColor: uiTheme.isLight ? Colors.black.withValues(alpha: 0.04) : Colors.white.withValues(alpha: 0.05),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 14 * scale, vertical: 8 * scale),
                decoration: BoxDecoration(
                  borderRadius: uiTheme.borderRadius(8 * scale),
                  border: Border.all(color: uiTheme.borderSubtle, width: 1.0),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Symbols.add_rounded, color: uiTheme.accentColor, size: 18 * scale),
                    SizedBox(width: 6 * scale),
                    Text(
                      'Додати мову до пріоритетів',
                      style: TextStyle(
                        fontFamily: 'Arial',
                        color: uiTheme.accentColor,
                        fontSize: 12.5 * scale,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          Container(
            padding: EdgeInsets.all(10 * scale),
            decoration: BoxDecoration(
              color: uiTheme.bgSurface,
              borderRadius: uiTheme.borderRadius(12 * scale),
              border: Border.all(color: uiTheme.accentBorder, width: 1.0),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(Symbols.search_rounded, color: uiTheme.accentColor, size: 18 * scale),
                    SizedBox(width: 8 * scale),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        autofocus: true,
                        style: TextStyle(
                          fontFamily: 'Arial',
                          color: uiTheme.textPrimary,
                          fontSize: 13 * scale,
                        ),
                        onChanged: (val) => setState(() => _searchQuery = val.trim()),
                        decoration: InputDecoration(
                          hintText: 'Пошук мови (назва або код uk, ja, pl)...',
                          hintStyle: TextStyle(
                            color: uiTheme.textDarkMuted,
                            fontSize: 12 * scale,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 4 * scale),
                        ),
                      ),
                    ),
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      splashColor: Colors.transparent,
                      highlightColor: uiTheme.touchHighlight,
                      icon: Icon(Symbols.close_rounded, color: uiTheme.textMuted, size: 18 * scale),
                      onPressed: () => setState(() {
                        _isAdding = false;
                        _searchQuery = "";
                        _searchController.clear();
                      }),
                    ),
                  ],
                ),
                SizedBox(height: 8 * scale),
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: 140 * scale),
                  child: SingleChildScrollView(
                    child: Wrap(
                      spacing: 6 * scale,
                      runSpacing: 6 * scale,
                      children: filtered.take(15).map((e) {
                        return GestureDetector(
                          onTap: () {
                            final list = List<String>.from(widget.languages);
                            list.add(e.key);
                            setState(() {
                              _isAdding = false;
                              _searchQuery = "";
                              _searchController.clear();
                            });
                            widget.onChanged(list);
                          },
                          child: Container(
                            padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 5 * scale),
                            decoration: BoxDecoration(
                              color: uiTheme.bgElevated,
                              borderRadius: uiTheme.borderRadius(6 * scale),
                              border: Border.all(color: uiTheme.borderSubtle),
                            ),
                            child: Text(
                              '${e.value} (${e.key})',
                              style: TextStyle(
                                fontFamily: 'Arial',
                                color: uiTheme.textPrimary,
                                fontSize: 11.5 * scale,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Drag handle for rows in a ReorderableListView (the same look as the language priority)
class AppDragHandle extends StatelessWidget {
  final double scale;
  final int index;

  const AppDragHandle({super.key, required this.scale, required this.index});

  @override
  Widget build(BuildContext context) {
    return ReorderableDragStartListener(
      index: index,
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: Padding(
          // On a phone the handle is easier to hit with a finger: a wider and taller grab zone
          padding: AppPlatform.isMobile
              ? EdgeInsets.symmetric(horizontal: 8 * scale, vertical: 14 * scale)
              : EdgeInsets.symmetric(horizontal: 4 * scale, vertical: 4 * scale),
          child: Icon(
            Symbols.drag_indicator_rounded,
            color: uiTheme.isLight ? const Color(0xFFAAAAAA) : const Color(0xFF777777),
            size: 19 * scale,
          ),
        ),
      ),
    );
  }
}

/// A small action icon in a list row (up / down / remove). [onTap] == null means inactive.
class AppRowIconButton extends StatelessWidget {
  final double scale;
  final IconData icon;
  final VoidCallback? onTap;
  final bool muted; // "remove" is dimmer, as in settings
  final double size;

  const AppRowIconButton({
    super.key,
    required this.scale,
    required this.icon,
    required this.onTap,
    this.muted = false,
    this.size = 18,
  });

  /// Touch target size on a phone (dp)
  static const double touchSize = 44;

  @override
  Widget build(BuildContext context) {
    final Color color = onTap == null
        ? (uiTheme.isLight ? const Color(0xFFDDDDDD) : const Color(0xFF333333))
        : (muted ? uiTheme.textDarkMuted : uiTheme.textMuted);
    return IconButton(
      padding: EdgeInsets.zero,
      constraints: AppPlatform.isMobile
          ? const BoxConstraints.tightFor(width: touchSize, height: touchSize)
          : const BoxConstraints(),
      splashColor: Colors.transparent,
      highlightColor: uiTheme.touchHighlight,
      icon: Icon(icon, color: color, size: size * scale),
      onPressed: onTap,
    );
  }
}

class AppSelectableTile extends StatelessWidget {
  final double scale;
  final String title;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  /// A second line (description): the tile gets taller
  final String? subtitle;

  /// A widget on the right (e.g. [AppKeyCombo] with a hotkey)
  final Widget? trailing;

  const AppSelectableTile({
    super.key,
    required this.scale,
    required this.title,
    required this.icon,
    required this.isSelected,
    required this.onTap,
    this.subtitle,
    this.trailing,
  });

  /// The selected look is the same as in the settings navigation and the hub (AppNavItem):
  /// a raised tile, an accent "pill" on the left, an accent icon, bold text.
  @override
  Widget build(BuildContext context) {
    final radiusObj = uiTheme.borderRadius(10 * scale);
    return Container(
      margin: EdgeInsets.only(bottom: 4 * scale),
      child: Material(
        color: Colors.transparent,
        borderRadius: radiusObj,
        child: InkWell(
          borderRadius: radiusObj,
          splashColor: Colors.transparent,
          highlightColor: uiTheme.touchHighlight,
          hoverColor: uiTheme.hoverOverlay,
          onTap: onTap,
          child: AppAnimatedContainer(
            duration: AppAnim.fast,
            curve: AppAnim.easeOut,
            height: (subtitle == null ? 44 : 54) * scale,
            padding: EdgeInsets.symmetric(horizontal: 10 * scale),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              color: isSelected ? uiTheme.bgElevated : Colors.transparent,
              borderRadius: radiusObj,
              border: Border.all(color: isSelected ? uiTheme.borderSubtle : Colors.transparent, width: 1.0),
            ),
            child: Row(
              children: [
                AppActivePillIndicator(isSelected: isSelected, scale: scale, color: uiTheme.accentColor),
                SizedBox(width: 8 * scale),
                Icon(
                  isSelected ? Symbols.check_rounded : icon,
                  color: isSelected ? uiTheme.accentColor : uiTheme.textMuted,
                  size: 18 * scale,
                  weight: 300,
                  opticalSize: 24,
                ),
                SizedBox(width: 12 * scale),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontFamily: 'Arial',
                          color: isSelected ? uiTheme.accentColor : uiTheme.textMuted,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                          fontSize: 13.5 * scale,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (subtitle != null) ...[
                        SizedBox(height: 2 * scale),
                        Text(
                          subtitle!,
                          style: TextStyle(fontFamily: 'Arial', color: uiTheme.textDarkMuted, fontSize: 11.5 * scale),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  SizedBox(width: 8 * scale),
                  trailing!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Controls over the video
// ─────────────────────────────────────────────────────────────────────────────

/// A button over the video. Always dark "glass", independent of the app's light / dark
/// theme: it sits on a black gradient over the video, and white icons
/// on a light tile are unreadable.
///
/// The active state ([isActive]) means just one thing: this button's menu / panel is open.
/// A feature's state (e.g. "subtitles on") is shown by [showBadge].
class AppOverlayButton extends StatefulWidget {
  final double scale;
  final double? width;
  final double? height;
  final double borderRadius;
  final double opacity;
  final bool isActive;
  final bool showBadge;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final VoidCallback? onSecondaryTap;

  /// Long press (on a phone it replaces right click)
  final VoidCallback? onLongPress;
  final Widget child;

  const AppOverlayButton({
    super.key,
    required this.scale,
    required this.child,
    this.width,
    this.height,
    this.borderRadius = 8,
    this.opacity = 0.55,
    this.isActive = false,
    this.showBadge = false,
    this.padding,
    this.onTap,
    this.onSecondaryTap,
    this.onLongPress,
  });

  /// Color of the icons and text inside the button
  static Color foreground(bool isActive) => isActive ? uiTheme.accentOnDark : Colors.white;

  @override
  State<AppOverlayButton> createState() => _AppOverlayButtonState();
}

class _AppOverlayButtonState extends State<AppOverlayButton> {
  bool _hover = false;
  bool _pressed = false;

  void _setPressed(bool v) {
    if (_pressed != v && mounted) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.scale;
    final radius = uiTheme.borderRadius(widget.borderRadius);
    final interactive = widget.onTap != null || widget.onSecondaryTap != null || widget.onLongPress != null;

    final glass = const Color(0xFF16161A).withValues(alpha: widget.opacity);
    Color bg = widget.isActive
        ? Color.alphaBlend(uiTheme.accentOnDark.withValues(alpha: 0.30), glass)
        : glass;
    if (_hover && interactive) bg = Color.alphaBlend(Colors.white.withValues(alpha: 0.10), bg);
    // Touch feedback: without it on a phone it is unclear that the button was pressed
    if (_pressed && interactive) bg = Color.alphaBlend(Colors.white.withValues(alpha: 0.20), bg);

    final border = widget.isActive ? uiTheme.accentOnDark.withValues(alpha: 0.65) : Colors.white.withValues(alpha: 0.16);

    Widget tile = AppAnimatedContainer(
      duration: AppAnim.fast,
      curve: AppAnim.easeOut,
      width: widget.width,
      height: widget.height,
      padding: widget.padding,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: radius,
        border: Border.all(color: border, width: 1.0),
      ),
      child: widget.child,
    );

    if (widget.showBadge) {
      tile = Stack(
        clipBehavior: Clip.none,
        children: [
          tile,
          Positioned(
            top: -2 * scale,
            right: -2 * scale,
            child: Container(
              width: 7 * scale,
              height: 7 * scale,
              decoration: BoxDecoration(
                color: uiTheme.accentOnDark,
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF16161A), width: 1.2),
              ),
            ),
          ),
        ],
      );
    }

    return RepaintBoundary(
      child: MouseRegion(
        cursor: interactive ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onSecondaryTap: widget.onSecondaryTap,
          onLongPress: widget.onLongPress,
          onTapDown: interactive ? (_) => _setPressed(true) : null,
          onTapUp: interactive ? (_) => _setPressed(false) : null,
          onTapCancel: interactive ? () => _setPressed(false) : null,
          child: tile,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Panels (settings menu, playback queue, chapters, information)
// ─────────────────────────────────────────────────────────────────────────────

/// Panel surface: the background, border, radius and shadow are the same for all pop-out panels.
class AppPanelSurface extends StatelessWidget {
  final double scale;
  final double radius;
  final double? width;
  final EdgeInsetsGeometry? margin;
  final Offset shadowOffset;
  final Widget child;

  const AppPanelSurface({
    super.key,
    required this.scale,
    required this.child,
    this.radius = 14,
    this.width,
    this.margin,
    this.shadowOffset = const Offset(0, 4),
  });

  @override
  Widget build(BuildContext context) {
    final r = uiTheme.borderRadius(radius * scale);
    return Container(
      width: width,
      margin: margin,
      decoration: BoxDecoration(
        color: uiTheme.colors.drawerBg,
        borderRadius: r,
        border: Border.all(color: uiTheme.colors.drawerBorder, width: 1.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: uiTheme.isLight ? 0.12 : 0.50),
            blurRadius: 16 * scale,
            offset: Offset(shadowOffset.dx * scale, shadowOffset.dy * scale),
          ),
        ],
      ),
      child: ClipRRect(borderRadius: r, child: child),
    );
  }
}

/// Panel header: the title (or "Назад") and the close button.
class AppPanelHeader extends StatelessWidget {
  final double scale;
  final String title;
  final VoidCallback onClose;
  final VoidCallback? onBack;

  const AppPanelHeader({
    super.key,
    required this.scale,
    required this.title,
    required this.onClose,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final bool touch = AppPlatform.isMobile;
    return Container(
      // On a phone the header is taller and the buttons no smaller than 48 dp
      height: touch ? 56 : 48 * scale,
      padding: EdgeInsets.only(left: 18 * scale, right: touch ? 6 : 18 * scale),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (onBack != null)
            InkWell(
              onTap: onBack,
              borderRadius: uiTheme.borderRadius(6 * scale),
              splashColor: Colors.transparent,
              highlightColor: uiTheme.touchHighlight,
              hoverColor: uiTheme.hoverOverlay,
              child: Row(
                children: [
                  Icon(Symbols.chevron_left_rounded, color: uiTheme.textMuted, size: 20 * scale),
                  SizedBox(width: 4 * scale),
                  Text(
                    'Назад',
                    style: TextStyle(
                      fontFamily: 'Arial',
                      color: uiTheme.textMuted,
                      fontSize: 13.5 * scale,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            )
          else
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Arial',
                  color: uiTheme.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 14.5 * scale,
                ),
              ),
            ),
          IconButton(
            padding: EdgeInsets.zero,
            constraints: touch ? const BoxConstraints.tightFor(width: 48, height: 48) : const BoxConstraints(),
            highlightColor: uiTheme.touchHighlight,
            icon: Icon(
              Symbols.close_rounded,
              color: uiTheme.textDarkMuted,
              size: touch ? 24 : 19 * scale,
              weight: 300,
              opticalSize: 24,
            ),
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

/// A list row with the current item highlighted (the same look as [AppSelectableTile]).
class AppSelectableSurface extends StatelessWidget {
  final double scale;
  final bool isSelected;
  final VoidCallback? onTap;

  /// Long press (on a computer, the right mouse button)
  final VoidCallback? onLongPress;
  final double radius;
  final double? height;
  final EdgeInsetsGeometry padding;
  final Widget child;

  const AppSelectableSurface({
    super.key,
    required this.scale,
    required this.isSelected,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.radius = 10,
    this.height,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    final radiusObj = uiTheme.borderRadius(radius * scale);
    return Container(
      margin: EdgeInsets.only(bottom: 4 * scale),
      child: Material(
        color: Colors.transparent,
        borderRadius: radiusObj,
        child: InkWell(
          borderRadius: radiusObj,
          splashColor: Colors.transparent,
          highlightColor: uiTheme.touchHighlight,
          hoverColor: uiTheme.hoverOverlay,
          onTap: onTap,
          onLongPress: onLongPress,
          onSecondaryTap: onLongPress,
          child: AppAnimatedContainer(
            duration: AppAnim.fast,
            curve: AppAnim.easeOut,
            height: height,
            padding: padding,
            decoration: BoxDecoration(
              color: isSelected ? uiTheme.accentWash : Colors.transparent,
              borderRadius: radiusObj,
              border: Border.all(
                color: isSelected ? uiTheme.accentBorder : Colors.transparent,
                width: 1.0,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Secondary button. Full width by default ([expand]); compact for headers and action bars.
class AppSecondaryButton extends StatelessWidget {
  final double scale;
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool expand;
  final bool isSuccess;

  const AppSecondaryButton({
    super.key,
    required this.scale,
    required this.label,
    required this.icon,
    required this.onTap,
    this.expand = true,
    this.isSuccess = false,
  });

  static const Color successColor = Color(0xFF00FF66);

  @override
  Widget build(BuildContext context) {
    final radiusObj = uiTheme.borderRadius(10 * scale);
    final fg = isSuccess ? successColor : uiTheme.textPrimary;
    final iconColor = isSuccess ? successColor : uiTheme.accentColor;

    final double h = (expand ? 42 : 38) * scale;
    return SizedBox(
      // At least 48 dp tall on a phone
      height: AppPlatform.isMobile ? (h < AppPlatform.touchTarget ? AppPlatform.touchTarget : h) : h,
      child: AppAnimatedContainer(
        duration: AppAnim.normal,
        curve: AppAnim.easeOut,
        decoration: BoxDecoration(
          color: isSuccess ? successColor.withValues(alpha: 0.12) : uiTheme.bgElevated,
          borderRadius: radiusObj,
          border: Border.all(
            color: isSuccess ? successColor.withValues(alpha: 0.40) : uiTheme.colors.borderSubtle,
            width: 1.0,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: radiusObj,
          child: InkWell(
            borderRadius: radiusObj,
            splashColor: Colors.transparent,
            highlightColor: uiTheme.touchHighlight,
            hoverColor: uiTheme.hoverOverlay,
            onTap: onTap,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: (expand ? 0 : 14) * scale),
              child: Row(
                mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: iconColor, size: 18 * scale, weight: 300, opticalSize: 24),
                  SizedBox(width: 8 * scale),
                  Text(
                    label,
                    style: TextStyle(
                      fontFamily: 'Arial',
                      color: fg,
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5 * scale,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Empty list state.
class AppEmptyState extends StatelessWidget {
  final double scale;
  final IconData icon;
  final String text;

  const AppEmptyState({super.key, required this.scale, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 24 * scale),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: uiTheme.textDarkMuted, size: 30 * scale, weight: 300, opticalSize: 24),
            SizedBox(height: 10 * scale),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Arial', color: uiTheme.textMuted, fontSize: 13 * scale),
            ),
          ],
        ),
      ),
    );
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// "Sidebar + content" layout (settings, home, statistics)
// ─────────────────────────────────────────────────────────────────────────────

/// A menu row in the player window style: an icon in a square, a title, an optional value "pill" and a chevron.
class AppMenuRow extends StatelessWidget {
  final double scale;
  final IconData icon;
  final String title;
  final String? value;
  final bool chevron;
  final bool active;
  final VoidCallback onTap;

  const AppMenuRow({super.key, required this.scale, required this.icon, required this.title, required this.onTap, this.value, this.chevron = true, this.active = false});

  @override
  Widget build(BuildContext context) {
    final r = uiTheme.borderRadius(12 * scale);
    final fg = active ? uiTheme.accentColor : uiTheme.textPrimary;
    final mobile = AppPlatform.isMobile;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 2 * scale),
      child: Material(
        color: Colors.transparent,
        borderRadius: r,
        child: InkWell(
          borderRadius: r,
          splashColor: Colors.transparent,
          highlightColor: uiTheme.touchHighlight,
          hoverColor: uiTheme.hoverOverlay,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: mobile ? 52 : 50 * scale),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 6 * scale, vertical: 5 * scale),
              child: Row(
                children: [
                  Container(
                    width: 36 * scale,
                    height: 36 * scale,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: uiTheme.bgElevated,
                      borderRadius: uiTheme.borderRadius(18 * scale),
                      border: Border.all(color: uiTheme.borderSubtle),
                    ),
                    child: Icon(icon, color: fg, size: 19 * scale, weight: 300, opticalSize: 24),
                  ),
                  SizedBox(width: 14 * scale),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontFamily: 'Arial', color: fg, fontWeight: active ? FontWeight.w600 : FontWeight.w500, fontSize: 14.5 * scale),
                    ),
                  ),
                  if (value != null) ...[
                    SizedBox(width: 8 * scale),
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: 150 * scale),
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 4 * scale),
                        decoration: BoxDecoration(color: uiTheme.bgElevated, borderRadius: uiTheme.borderRadius(99), border: Border.all(color: uiTheme.borderSubtle)),
                        child: Text(value!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: 'Arial', color: uiTheme.textMuted, fontSize: 12 * scale)),
                      ),
                    ),
                  ],
                  if (chevron) ...[
                    SizedBox(width: 4 * scale),
                    Icon(Symbols.chevron_right_rounded, color: uiTheme.textDarkMuted, size: 20 * scale, weight: 300, opticalSize: 24),
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

/// Modal shell: the background, border, radius and shadow as in the settings window.
class AppModalShell extends StatelessWidget {
  final double scale;
  final double width;
  final double height;
  final Widget child;

  const AppModalShell({
    super.key,
    required this.scale,
    required this.width,
    required this.height,
    required this.child,
  });

  static const double cornerRadius = 22;

  @override
  Widget build(BuildContext context) {
    final r = uiTheme.borderRadius(cornerRadius * scale);
    return Material(
      color: Colors.transparent,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          // Player panel surface: all windows look the same
          color: uiTheme.colors.drawerBg,
          borderRadius: r,
          border: Border.all(color: uiTheme.colors.drawerBorder, width: 1.0),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: uiTheme.isLight ? 0.12 : 0.80),
              blurRadius: 40 * scale,
              offset: Offset(0, 12 * scale),
            ),
          ],
        ),
        child: ClipRRect(borderRadius: r, child: child),
      ),
    );
  }
}

/// Left sidebar: header, navigation, footer.
class AppSidebar extends StatelessWidget {
  final double scale;
  final Widget header;
  final List<Widget> children;
  final Widget? footer;
  final double width;

  const AppSidebar({
    super.key,
    required this.scale,
    required this.header,
    required this.children,
    this.footer,
    this.width = 220,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width * scale,
      padding: EdgeInsets.symmetric(horizontal: 14 * scale, vertical: 20 * scale),
      decoration: BoxDecoration(
        color: uiTheme.bgSidebar,
        border: Border(right: BorderSide(color: uiTheme.borderSubtle, width: 1.0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(left: 10 * scale, bottom: 16 * scale),
            child: header,
          ),
          Expanded(child: ListView(padding: EdgeInsets.zero, children: children)),
          if (footer != null) footer!,
        ],
      ),
    );
  }
}

class AppNavGroupLabel extends StatelessWidget {
  final double scale;
  final String text;

  const AppNavGroupLabel({super.key, required this.scale, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 10 * scale, bottom: 6 * scale, top: 4 * scale),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'Arial',
          color: uiTheme.textDarkMuted,
          fontSize: 10 * scale,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class AppNavItem extends StatelessWidget {
  final double scale;
  final IconData icon;
  final String label;
  final bool isSelected;
  final String? trailing;
  final VoidCallback onTap;

  const AppNavItem({
    super.key,
    required this.scale,
    required this.icon,
    required this.label,
    required this.onTap,
    this.isSelected = false,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final r = uiTheme.borderRadius(10 * scale);
    return Padding(
      padding: EdgeInsets.only(bottom: 4 * scale),
      child: Material(
        color: Colors.transparent,
        borderRadius: r,
        child: InkWell(
          borderRadius: r,
          splashColor: Colors.transparent,
          highlightColor: uiTheme.touchHighlight,
          hoverColor: uiTheme.hoverOverlay,
          onTap: onTap,
          child: AppAnimatedContainer(
            duration: AppAnim.fast,
            curve: AppAnim.easeOut,
            height: 42 * scale,
            padding: EdgeInsets.symmetric(horizontal: 10 * scale),
            decoration: BoxDecoration(
              color: isSelected ? uiTheme.bgElevated : Colors.transparent,
              borderRadius: r,
              border: Border.all(
                color: isSelected ? uiTheme.borderSubtle : Colors.transparent,
                width: 1.0,
              ),
            ),
            child: Row(
              children: [
                AppActivePillIndicator(isSelected: isSelected, scale: scale, color: uiTheme.accentColor),
                SizedBox(width: 8 * scale),
                Icon(
                  icon,
                  color: isSelected ? uiTheme.accentColor : uiTheme.textMuted,
                  size: 17 * scale,
                ),
                SizedBox(width: 10 * scale),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontFamily: 'Arial',
                      color: isSelected ? uiTheme.accentColor : uiTheme.textMuted,
                      fontSize: 12.5 * scale,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (trailing != null)
                  Text(
                    trailing!,
                    style: TextStyle(fontFamily: 'Arial', color: uiTheme.textDarkMuted, fontSize: 11 * scale),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Right panel header: a title, a subtitle and actions on the right.
class AppPaneHeader extends StatelessWidget {
  final double scale;
  final String title;
  final String subtitle;
  final List<Widget> actions;

  const AppPaneHeader({
    super.key,
    required this.scale,
    required this.title,
    required this.subtitle,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final titleBlock = SizedBox(
      height: 44 * scale,
      child: AppFadeSwitcher(
        duration: AppAnim.fast,
        child: Column(
          key: ValueKey<String>(title),
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Arial',
                color: uiTheme.textPrimary,
                fontSize: 17 * scale,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 2 * scale),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: 'Arial', color: uiTheme.textDarkMuted, fontSize: 12 * scale),
            ),
          ],
        ),
      ),
    );

    // Narrow phone screen: the actions do not fit to the right of the title, so they become a row under it
    final bool compact = AppPlatform.isMobile && AppLayout(MediaQuery.sizeOf(context)).isCompactWidth;
    if (compact) {
      return Padding(
        padding: EdgeInsets.fromLTRB(16, 14 * scale, 16, 10 * scale),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            titleBlock,
            if (actions.isNotEmpty) ...[
              SizedBox(height: 10 * scale),
              Wrap(spacing: 8 * scale, runSpacing: 8 * scale, children: actions),
            ],
          ],
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(left: 24 * scale, right: 20 * scale, top: 18 * scale, bottom: 12 * scale),
      child: Row(
        children: [
          Expanded(child: titleBlock),
          for (int i = 0; i < actions.length; i++) ...[
            if (i > 0) SizedBox(width: 8 * scale),
            actions[i],
          ],
        ],
      ),
    );
  }
}

/// Section heading inside content (title + description + an action on the right).
class AppSectionHeader extends StatelessWidget {
  final double scale;
  final String title;
  final String? subtitle;
  final Widget? trailing;

  const AppSectionHeader({
    super.key,
    required this.scale,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontFamily: 'Arial',
                  color: uiTheme.textPrimary,
                  fontSize: 13.5 * scale,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (subtitle != null) ...[
                SizedBox(height: 2 * scale),
                Text(
                  subtitle!,
                  style: TextStyle(fontFamily: 'Arial', color: uiTheme.textDarkMuted, fontSize: 11.5 * scale),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// Primary action button (like "Готово" in settings).
class AppAccentButton extends StatelessWidget {
  final double scale;
  final String label;
  final IconData? icon;
  final VoidCallback onTap;

  /// Stretch to the parent's full width (narrow phone screens)
  final bool expand;

  /// The page's main action: a solid bright accent fill, white text, a slightly larger button
  final bool solid;

  const AppAccentButton({
    super.key,
    required this.scale,
    required this.label,
    required this.onTap,
    this.icon,
    this.expand = false,
    this.solid = false,
  });

  @override
  Widget build(BuildContext context) {
    final accent = uiTheme.accentColor;
    final fg = solid ? Colors.white : (uiTheme.isLight ? accent : Colors.white);
    final r = uiTheme.borderRadius(12 * scale);
    return Material(
      color: solid ? accent : accent.withValues(alpha: uiTheme.isLight ? 0.15 : 0.18),
      shape: RoundedRectangleBorder(
        borderRadius: r,
        side: solid ? BorderSide.none : BorderSide(color: accent.withValues(alpha: 0.65), width: 1.0),
      ),
      child: InkWell(
        borderRadius: r,
        splashColor: Colors.transparent,
        highlightColor: uiTheme.touchHighlight,
        hoverColor: uiTheme.hoverOverlay,
        onTap: onTap,
        child: ConstrainedBox(
          // At least 48 dp tall on a phone
          constraints: BoxConstraints(minHeight: AppPlatform.isMobile ? AppPlatform.touchTarget : 0),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 20 * scale, vertical: (solid ? 14 : 11) * scale),
            child: Row(
              mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, color: fg, size: (solid ? 22 : 18) * scale, weight: 300, opticalSize: 24),
                  SizedBox(width: 8 * scale),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Arial',
                      color: fg,
                      fontWeight: FontWeight.bold,
                      fontSize: (solid ? 15 : 13) * scale,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A content container card (optionally clickable).
class AppCard extends StatelessWidget {
  final double scale;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final double radius;
  final bool isHighlighted;

  const AppCard({
    super.key,
    required this.scale,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.onTap,
    this.radius = 12,
    this.isHighlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final r = uiTheme.borderRadius(radius * scale);
    final content = Padding(padding: padding, child: child);
    return Material(
      color: isHighlighted ? uiTheme.accentWash : uiTheme.bgSurface,
      shape: RoundedRectangleBorder(
        borderRadius: r,
        side: BorderSide(
          color: isHighlighted ? uiTheme.accentBorder : uiTheme.colors.borderSubtle,
          width: 1.0,
        ),
      ),
      child: onTap == null
          ? content
          : InkWell(
              borderRadius: r,
              splashColor: Colors.transparent,
              highlightColor: uiTheme.touchHighlight,
              hoverColor: uiTheme.hoverOverlay,
              onTap: onTap,
              child: content,
            ),
    );
  }
}

/// A metric tile (label + value) with a warning mode.
class AppStatTile extends StatelessWidget {
  final double scale;
  final IconData icon;
  final String label;
  final String value;
  final bool isWarning;

  const AppStatTile({
    super.key,
    required this.scale,
    required this.icon,
    required this.label,
    required this.value,
    this.isWarning = false,
  });

  static const Color warningColor = Color(0xFFE5484D);

  @override
  Widget build(BuildContext context) {
    final r = uiTheme.borderRadius(10 * scale);
    final accent = isWarning ? warningColor : uiTheme.accentColor;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 10 * scale),
      decoration: BoxDecoration(
        color: isWarning ? warningColor.withValues(alpha: 0.10) : uiTheme.bgSurface,
        borderRadius: r,
        border: Border.all(
          color: isWarning ? warningColor.withValues(alpha: 0.50) : uiTheme.colors.borderSubtle,
          width: 1.0,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 32 * scale,
            height: 32 * scale,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: uiTheme.isLight ? 0.12 : 0.16),
              borderRadius: uiTheme.borderRadius(8 * scale),
            ),
            child: Icon(icon, color: accent, size: 17 * scale, weight: 300, opticalSize: 24),
          ),
          SizedBox(width: 10 * scale),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(fontFamily: 'Arial', color: uiTheme.textDarkMuted, fontSize: 10.5 * scale),
                ),
                SizedBox(height: 2 * scale),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Arial',
                    color: isWarning ? warningColor : uiTheme.textPrimary,
                    fontSize: 12.5 * scale,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A "keyboard key" for hotkey hints. A thin bottom edge gives the feel of a physical key;
/// [accent] highlights the key with the accent color (a combination that depends on the chosen scheme).
class AppKeyCap extends StatelessWidget {
  final double scale;
  final String text;
  final bool accent;

  const AppKeyCap({super.key, required this.scale, required this.text, this.accent = false});

  @override
  Widget build(BuildContext context) {
    final edge = accent ? uiTheme.accentBorder : uiTheme.colors.borderSubtle;
    // A Container with alignment stretches to the full height the parent gives (a tile row in the menu),
    // and the key would become a "pillar". So the text is centered through Center with widthFactor/heightFactor.
    return Container(
      constraints: BoxConstraints(minWidth: 22 * scale),
      padding: EdgeInsets.symmetric(horizontal: 7 * scale, vertical: 3 * scale),
      decoration: BoxDecoration(
        color: accent ? uiTheme.accentWash : uiTheme.bgElevated,
        borderRadius: uiTheme.borderRadius(6 * scale),
        border: Border.all(color: edge),
        boxShadow: [
          BoxShadow(color: edge.withValues(alpha: 0.55), offset: Offset(0, 1.5 * scale), blurRadius: 0),
        ],
      ),
      child: Center(
        widthFactor: 1,
        heightFactor: 1,
        child: Text(
          text,
          style: TextStyle(
            fontFamily: 'Arial',
            color: accent ? uiTheme.accentColor : uiTheme.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 10.5 * scale,
          ),
        ),
      ),
    );
  }
}

/// A key combination: a row of keyboard keys ("Ctrl" "1").
class AppKeyCombo extends StatelessWidget {
  final double scale;
  final List<String> keys;
  final bool accent;

  const AppKeyCombo({super.key, required this.scale, required this.keys, this.accent = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < keys.length; i++) ...[
          if (i > 0) SizedBox(width: 3 * scale),
          AppKeyCap(scale: scale, text: keys[i], accent: accent),
        ],
      ],
    );
  }
}

/// Search field: a magnifier, text and a clear button; the border lights up with the accent on focus.
/// The height matches [AppSegmentedBar], so they stand in one row. With a different [icon] and [hint] it is an ordinary
/// single-line text field (e.g. an API key).
class AppSearchField extends StatefulWidget {
  final double scale;
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String hint;
  final IconData icon;
  final ValueChanged<String> onChanged;

  const AppSearchField({
    super.key,
    required this.scale,
    required this.controller,
    required this.onChanged,
    this.focusNode,
    this.hint = 'Пошук…',
    this.icon = Symbols.search_rounded,
  });

  @override
  State<AppSearchField> createState() => _AppSearchFieldState();
}

class _AppSearchFieldState extends State<AppSearchField> {
  FocusNode? _ownFocus;
  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _focus.addListener(_refresh);
    widget.controller.addListener(_refresh);
  }

  @override
  void didUpdateWidget(AppSearchField old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_refresh);
      widget.controller.addListener(_refresh);
    }
    if (old.focusNode != widget.focusNode) {
      (old.focusNode ?? _ownFocus)?.removeListener(_refresh);
      _focus.addListener(_refresh);
    }
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    _focus.removeListener(_refresh);
    _ownFocus?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.scale;
    final focused = _focus.hasFocus;
    final hasText = widget.controller.text.isNotEmpty;

    return AppAnimatedContainer(
      duration: AppAnim.fast,
      curve: AppAnim.easeOut,
      height: 38 * scale,
      padding: EdgeInsets.only(left: 12 * scale, right: 6 * scale),
      decoration: BoxDecoration(
        color: uiTheme.bgElevated,
        borderRadius: uiTheme.borderRadius(20 * scale),
        border: Border.all(color: focused ? uiTheme.accentBorder : uiTheme.borderSubtle, width: 1.0),
      ),
      child: Row(
        children: [
          Icon(
            widget.icon,
            color: focused ? uiTheme.accentColor : uiTheme.textMuted,
            size: 18 * scale,
          ),
          SizedBox(width: 8 * scale),
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: _focus,
              onChanged: widget.onChanged,
              cursorColor: uiTheme.accentColor,
              style: TextStyle(fontFamily: 'Arial', color: uiTheme.textPrimary, fontSize: 12.5 * scale),
              decoration: InputDecoration(
                hintText: widget.hint,
                hintStyle: TextStyle(
                  fontFamily: 'Arial',
                  color: uiTheme.textDarkMuted,
                  fontSize: 12.5 * scale,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 8 * scale),
              ),
            ),
          ),
          if (hasText)
            IconButton(
              padding: EdgeInsets.zero,
              constraints: BoxConstraints.tightFor(width: 26 * scale, height: 26 * scale),
              splashColor: Colors.transparent,
              highlightColor: uiTheme.touchHighlight,
              icon: Icon(Symbols.close_rounded, color: uiTheme.textMuted, size: 16 * scale),
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

/// Soft fades at the top and bottom over scrollable content (they dissolve the text under the header and buttons).
class AppScrollEdgeFade extends StatelessWidget {
  final double scale;
  final Widget child;
  final Color? color;

  const AppScrollEdgeFade({super.key, required this.scale, required this.child, this.color});

  @override
  Widget build(BuildContext context) {
    final base = color ?? uiTheme.bgPrimary;
    Widget edge({required bool top}) => Positioned(
          top: top ? 0 : null,
          bottom: top ? null : 0,
          left: 0,
          right: 0,
          height: (top ? 14 : 16) * scale,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: top ? Alignment.topCenter : Alignment.bottomCenter,
                  end: top ? Alignment.bottomCenter : Alignment.topCenter,
                  colors: [base.withValues(alpha: 0.95), base.withValues(alpha: 0.0)],
                ),
              ),
            ),
          ),
        );

    return Stack(
      children: [
        Positioned.fill(child: child),
        edge(top: true),
        edge(top: false),
      ],
    );
  }
}

/// A wrapper of the former scrollbar: the app no longer has scroll bars (removed as unneeded), the widget remains
/// so as not to touch all usages. The controller must be attached to the child scroll.
class AppScrollbar extends StatelessWidget {
  final double scale;
  final ScrollController controller;
  final Widget child;

  const AppScrollbar({super.key, required this.scale, required this.controller, required this.child});

  @override
  Widget build(BuildContext context) => ScrollConfiguration(behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false), child: child);
}

/// Scrolling as in modern Android: a "stretch" effect at the edge instead of the old glow (Android 5)
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  /// A mouse drags lists too (desktop): horizontal shelves can be dragged, not only scrolled with arrows / Shift+wheel
  @override
  Set<PointerDeviceKind> get dragDevices => {...super.dragDevices, PointerDeviceKind.mouse};

  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) {
    return StretchingOverscrollIndicator(axisDirection: details.direction, child: child);
  }
}

/// A pull-down refresh area. The top edge here shows only the refresh indicator (otherwise the content stretches
/// and drags the indicator at once); the bottom and side edges get the "jelly" stretch as in Android 12.
/// The room at the top of scrollable content taken by the overlay header (see `HikkaCollapsingHeader`). The header lies over
/// the content and changes neither the size nor the scroll position, so lists leave the [inset] padding under it themselves.
class AppHeaderInset extends InheritedWidget {
  final double inset;

  /// Visibility of this level's header (0…1): nested headers sit under the outer one only while it is visible
  final Animation<double>? shown;

  const AppHeaderInset({super.key, required this.inset, this.shown, required super.child});

  /// Top padding for lists (0 if there is no header)
  static double of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppHeaderInset>()?.inset ?? 0;

  /// Subscribes: a nested header must follow the outer one when its height changes (e.g. the calendar's day tabs come and go)
  static AppHeaderInset? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppHeaderInset>();

  @override
  bool updateShouldNotify(AppHeaderInset old) => inset != old.inset;
}

class AppPullToRefresh extends StatefulWidget {
  final Future<void> Function() onRefresh;
  final Widget child;

  const AppPullToRefresh({super.key, required this.onRefresh, required this.child});

  @override
  State<AppPullToRefresh> createState() => _AppPullToRefreshState();
}

/// A custom "pull to refresh": the content stands still during the pull, the arrow follows the finger (down and back up),
/// stays while you hold your finger, and scrolling is locked while the refresh runs.
class _AppPullToRefreshState extends State<AppPullToRefresh> with SingleTickerProviderStateMixin {
  /// Visible arrow position (px) relative to the start; the finger pull is damped by this factor
  static const double _resistance = 0.5;
  static const double _maxVisual = 120;
  static const double _armedVisual = 60;
  static const double _restVisual = 56;

  final ValueNotifier<double> _visual = ValueNotifier(0);
  late final AnimationController _settle = AnimationController(vsync: this, duration: AppAnim.medium);
  double _from = 0;
  double _to = 0;

  bool _refreshing = false;
  bool _pulling = false;
  double _pull = 0;

  @override
  void initState() {
    super.initState();
    _settle.addListener(() => _visual.value = _from + (_to - _from) * AppAnim.easeOut.transform(_settle.value));
  }

  @override
  void dispose() {
    _settle.dispose();
    _visual.dispose();
    super.dispose();
  }

  void _animateTo(double v) {
    _from = _visual.value;
    _to = v;
    _settle.forward(from: 0);
  }

  void _setPull(double pull) {
    _pull = pull;
    _settle.stop();
    _visual.value = (pull * _resistance).clamp(0.0, _maxVisual);
  }

  void _startPull(double amount) {
    if (_pulling || _refreshing) return;
    _pulling = true;
    _setPull(amount);
  }

  /// Finger movement [offset] (> 0 is down) during the pull. Returns how much of it to apply to scrolling
  double _userOffset(ScrollMetrics m, double offset) {
    if (!_pulling) return offset;
    final next = _pull + offset;
    if (next <= 0) {
      // The arrow was returned to its place: the pull is cancelled, the leftover motion is ordinary scrolling
      _pulling = false;
      _setPull(0);
      return next;
    }
    _setPull(next);
    return 0;
  }

  Future<void> _release({required bool allowRefresh}) async {
    if (!_pulling) return;
    _pulling = false;
    final armed = _visual.value >= _armedVisual;
    _pull = 0;
    if (allowRefresh && armed && !_refreshing) {
      _refreshing = true;
      _animateTo(_restVisual);
      try {
        await widget.onRefresh();
      } finally {
        _refreshing = false;
        if (mounted) _animateTo(0);
      }
    } else {
      _animateTo(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final edge = AppHeaderInset.of(context);
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerUp: (_) => _release(allowRefresh: true),
      onPointerCancel: (_) => _release(allowRefresh: false),
      child: Stack(
        children: [
          Positioned.fill(
            child: ScrollConfiguration(
              behavior: _TopEdgeToRefreshBehavior(ScrollConfiguration.of(context), () => _refreshing, _startPull, _userOffset, () => _pulling),
              child: widget.child,
            ),
          ),
          Positioned(
            top: edge,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: ValueListenableBuilder<double>(
                valueListenable: _visual,
                builder: (context, v, _) {
                  if (v <= 0.5) return const SizedBox.shrink();
                  return Align(
                    alignment: Alignment.topCenter,
                    child: Transform.translate(
                      offset: Offset(0, v - 40),
                      child: Opacity(
                        opacity: (v / 16).clamp(0.0, 1.0),
                        child: Material(
                          type: MaterialType.circle,
                          elevation: 3,
                          color: uiTheme.bgElevated,
                          child: SizedBox(
                            width: 40,
                            height: 40,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.all(5),
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: uiTheme.accentColor,
                                    backgroundColor: uiTheme.borderSubtle,
                                    // The ring fills with the pull; it spins during the refresh
                                    value: _refreshing ? null : (v / _armedVisual).clamp(0.0, 1.0),
                                  ),
                                ),
                                if (!_refreshing)
                                  Transform.rotate(
                                    // The down arrow turns up when the pull is "charged"
                                    angle: (v / _armedVisual).clamp(0.0, 1.0) * math.pi,
                                    child: Icon(Symbols.arrow_downward_rounded, size: 18, color: uiTheme.accentColor),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Physics: while [locked] (refreshing) there is no scrolling; during the pull finger motion goes to [onOffset] and the content stands still
class _LockPhysics extends ScrollPhysics {
  final bool Function() locked;
  final double Function(ScrollMetrics, double) onOffset;
  final bool Function() pulling;

  const _LockPhysics(this.locked, this.onOffset, this.pulling, {super.parent});

  @override
  _LockPhysics applyTo(ScrollPhysics? ancestor) => _LockPhysics(locked, onOffset, pulling, parent: buildParent(ancestor));

  // Locking and pulling concern only the page's vertical scrolling. We do not touch horizontal carousels:
  // `shouldAcceptUserOffset` is computed once (at layout) and disabled the gesture for good in lists
  // that were rebuilt during the refresh.
  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    if (position.axis != Axis.vertical) return super.applyPhysicsToUserOffset(position, offset);
    if (locked()) return 0.0;
    if (pulling()) return onOffset(position, offset);
    return super.applyPhysicsToUserOffset(position, offset);
  }

  @override
  Simulation? createBallisticSimulation(ScrollMetrics position, double velocity) {
    if (position.axis != Axis.vertical) return super.createBallisticSimulation(position, velocity);
    return locked() || pulling() ? null : super.createBallisticSimulation(position, velocity);
  }
}

/// A top overscroll of a vertical list does not stretch the content but is only passed to the refresh indicator
class _TopEdgeToRefreshBehavior extends ScrollBehavior {
  final ScrollBehavior base;
  final bool Function() locked;
  final void Function(double amount) onTopPull;
  final double Function(ScrollMetrics, double) onOffset;
  final bool Function() pulling;

  const _TopEdgeToRefreshBehavior(this.base, this.locked, this.onTopPull, this.onOffset, this.pulling);

  @override
  Widget buildScrollbar(BuildContext context, Widget child, ScrollableDetails details) => base.buildScrollbar(context, child, details);

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) => _LockPhysics(locked, onOffset, pulling, parent: base.getScrollPhysics(context));

  @override
  Set<PointerDeviceKind> get dragDevices => base.dragDevices;

  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) {
    final vertical = axisDirectionToAxis(details.direction) == Axis.vertical;
    return base.buildOverscrollIndicator(context, vertical ? _gate(child) : child, details);
  }

  Widget _gate(Widget child) => NotificationListener<OverscrollNotification>(
        onNotification: (n) {
          if (n.overscroll < 0 && n.depth == 0) {
            // Top: no stretching; the start of the pull is passed to the refresh indicator
            if (n.dragDetails != null) onTopPull(-n.overscroll);
            return true;
          }
          return false;
        },
        child: child,
      );
}

/// Tap target with a visible press highlight: a translucent overlay is drawn above [child] while the finger is down,
/// so it shows on any background (unlike an ink splash that hides under an opaque decoration).
class AppPressable extends StatefulWidget {
  final VoidCallback? onTap;
  final HitTestBehavior behavior;
  final BorderRadius? radius;
  final Widget child;
  const AppPressable({super.key, required this.onTap, required this.child, this.behavior = HitTestBehavior.opaque, this.radius});

  @override
  State<AppPressable> createState() => _AppPressableState();
}

class _AppPressableState extends State<AppPressable> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final on = widget.onTap != null;
    return GestureDetector(
      behavior: widget.behavior,
      onTap: widget.onTap,
      onTapDown: on ? (_) => _set(true) : null,
      onTapUp: on ? (_) => _set(false) : null,
      onTapCancel: on ? () => _set(false) : null,
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          widget.child,
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedOpacity(
                duration: _down ? Duration.zero : AppAnim.fast,
                opacity: _down ? 1 : 0,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: uiTheme.isLight ? Colors.black.withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.10),
                    borderRadius: widget.radius,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
