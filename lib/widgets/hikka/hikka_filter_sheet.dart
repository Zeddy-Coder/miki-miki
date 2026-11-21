import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../models/hikka_models.dart';
import '../../services/hikka_api.dart';
import '../../services/ui_theme_service.dart';
import '../../utils/platform_info.dart';
import '../app_animation_kit.dart';
import '../app_tones.dart';
import '../app_ui_kit.dart';
import '../line_icons.dart';
import '../settings_kit.dart' show kUiFontFallback;
import 'hikka_common.dart';

/// Catalog filter panel. Works with a copy of the conditions; applied by the button at the bottom.
class HikkaFilterSheet extends StatefulWidget {
  final double scale;
  final HikkaSearchFilters initial;
  final bool allowAdult;
  final ValueChanged<HikkaSearchFilters> onApply;
  final VoidCallback onClose;

  /// Sort options and what counts as "default" (user lists have their own)
  final List<HikkaSortOption> sortOptions;
  final String defaultSort;

  /// The sheet's title ("Сортування й фільтри" in the lists)
  final String title;

  /// How many titles the conditions leave: the button says "Показати N тайтлів" (asked a moment after the last change)
  final Future<int> Function(HikkaSearchFilters filters)? countOf;

  const HikkaFilterSheet({
    super.key,
    required this.scale,
    required this.initial,
    required this.allowAdult,
    required this.onApply,
    required this.onClose,
    this.sortOptions = HikkaSearchFilters.sorts,
    this.defaultSort = 'score',
    this.title = 'Фільтри',
    this.countOf,
  });

  /// The first year in the slider
  static const int firstYear = 1960;

  @override
  State<HikkaFilterSheet> createState() => _HikkaFilterSheetState();
}

class _HikkaFilterSheetState extends State<HikkaFilterSheet> {
  late HikkaSearchFilters _f = widget.initial;
  late final Future<List<HikkaGenre>> _genres = HikkaApi.instance.genres();
  final ScrollController _scroll = AppSmoothScrollController();

  /// How many titles the current conditions leave (null while unknown). Only the button listens: an answer used to
  /// rebuild the whole sheet with its hundred plates
  final ValueNotifier<int?> _count = ValueNotifier<int?>(null);
  Timer? _countTimer;
  int _countGen = 0;

  double get _scale => widget.scale;
  int get _lastYear => DateTime.now().year + 1;

  @override
  void initState() {
    super.initState();
    _recount(now: true);
  }

  @override
  void dispose() {
    _countTimer?.cancel();
    _scroll.dispose();
    _count.dispose();
    super.dispose();
  }

  @override
  void setState(VoidCallback fn) {
    final before = _f;
    super.setState(fn);
    if (!identical(before, _f)) _recount();
  }

  /// Asks how many titles are left, a moment after the last change (one request for a series of taps)
  void _recount({bool now = false}) {
    final count = widget.countOf;
    if (count == null) return;
    _countTimer?.cancel();
    final gen = ++_countGen;
    _count.value = null;
    _countTimer = Timer(now ? Duration.zero : const Duration(milliseconds: 500), () {
      count(_f).then((n) {
        if (mounted && gen == _countGen) _count.value = n;
      }, onError: (Object _) {});
    });
  }

  Set<String> _toggled(Set<String> set, String value) => set.contains(value) ? ({...set}..remove(value)) : {...set, value};

  bool get _hasChanges => _f.activeCount > 0 || _f.sort != widget.defaultSort || _f.ascending;

  double get _pad => AppPlatform.isMobile ? 16.0 : 20 * _scale;

  /// A group: a muted caption (with a note or an action on the right) and the content under it.
  /// [bleed]: the content goes edge to edge (a chip row that scrolls sideways).
  Widget _section(String title, Widget child, {String? hint, Widget? trailing, bool bleed = false}) {
    return Padding(
      padding: EdgeInsets.only(bottom: 16 * _scale),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: _pad),
            child: Row(
              children: [
                Expanded(
                  child: Text(title, style: TextStyle(fontFamily: 'Arial', fontFamilyFallback: kUiFontFallback, color: AppTones.caption, fontSize: 13 * _scale, fontWeight: FontWeight.w700)),
                ),
                if (trailing != null)
                  trailing
                else if (hint != null)
                  Text(hint, style: TextStyle(fontFamily: 'Arial', color: uiTheme.textDarkMuted, fontSize: 12 * _scale)),
              ],
            ),
          ),
          SizedBox(height: 8 * _scale),
          bleed ? child : Padding(padding: EdgeInsets.symmetric(horizontal: _pad), child: child),
        ],
      ),
    );
  }

  String? _selected(int n) => n == 0 ? null : '$n вибрано';

  /// A soft round plate: quiet when off; the chosen one is lighter, with an outline, white bold text and an accent check mark
  Widget _pill(String label, bool selected, VoidCallback onTap, {IconData? icon}) {
    final h = 36 * _scale;
    final shape = RoundedRectangleBorder(
      borderRadius: uiTheme.borderRadius(18 * _scale),
      side: BorderSide(color: selected ? AppTones.plateOutline : Colors.transparent),
    );
    final color = selected ? uiTheme.textPrimary : AppTones.plateText;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? AppTones.plateOn : AppTones.plate,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          splashColor: Colors.transparent,
          highlightColor: uiTheme.touchHighlight,
          hoverColor: uiTheme.hoverOverlay,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: math.max(h, AppPlatform.isMobile ? 40.0 : 0.0)),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 14 * _scale),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // The chosen plate carries an accent check mark
                  if (selected) ...[LineIconView(LineIcon.check, size: 15 * _scale, color: uiTheme.accentColor, stroke: 2), SizedBox(width: 7 * _scale)],
                  if (icon != null) ...[Icon(icon, size: 17 * _scale, color: color), SizedBox(width: 6 * _scale)],
                  Text(label, style: TextStyle(fontFamily: 'Arial', fontFamilyFallback: kUiFontFallback, color: color, fontSize: 13.5 * _scale, fontWeight: selected ? FontWeight.w700 : FontWeight.normal)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Pills of one group in wrapped lines
  Widget _pillRow(List<Widget> pills) =>
      Padding(padding: EdgeInsets.symmetric(horizontal: _pad), child: Wrap(spacing: 8 * _scale, runSpacing: 8 * _scale, children: pills));

  Widget _chips(Map<String, String> options, Set<String> selected, ValueChanged<Set<String>> onChanged) {
    return _pillRow([
      for (final e in options.entries) _pill(e.value, selected.contains(e.key), () => onChanged(_toggled(selected, e.key))),
    ]);
  }

  /// The same look as the sliders in settings
  SliderThemeData _sliderTheme(BuildContext context) => SliderTheme.of(context).copyWith(
        trackHeight: 4.0 * _scale,
        activeTrackColor: uiTheme.accentColor,
        inactiveTrackColor: uiTheme.isLight ? const Color(0xFFDDDDE6) : const Color(0xFF2A2A30),
        thumbColor: Colors.white,
        overlayColor: uiTheme.accentColor.withValues(alpha: 0.14),
        rangeThumbShape: RoundRangeSliderThumbShape(enabledThumbRadius: 10 * _scale, elevation: 1, pressedElevation: 2),
        rangeTrackShape: const RoundedRectRangeSliderTrackShape(),
        overlayShape: RoundSliderOverlayShape(overlayRadius: 14.0 * _scale),
        rangeTickMarkShape: const RoundRangeSliderTickMarkShape(tickMarkRadius: 0),
        activeTickMarkColor: Colors.transparent,
        inactiveTickMarkColor: Colors.transparent,
      );

  Widget _rangeRow({
    required double min,
    required double max,
    required RangeValues values,
    required ValueChanged<RangeValues> onChanged,
  }) {
    final ends = TextStyle(fontFamily: 'Arial', fontFamilyFallback: kUiFontFallback, color: uiTheme.textMuted, fontSize: 12.5 * _scale);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SliderTheme(
          data: _sliderTheme(context),
          child: RangeSlider(
            min: min,
            max: max,
            divisions: (max - min).round(),
            values: values,
            onChanged: onChanged,
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 24 * _scale),
          child: Row(
            children: [
              Text(values.start.round().toString(), style: ends),
              const Spacer(),
              Text(values.end.round().toString(), style: ends),
            ],
          ),
        ),
      ],
    );
  }

  Widget _years() {
    final min = HikkaFilterSheet.firstYear.toDouble();
    final max = _lastYear.toDouble();
    final from = (_f.yearFrom ?? HikkaFilterSheet.firstYear).toDouble().clamp(min, max);
    final to = (_f.yearTo ?? _lastYear).toDouble().clamp(min, max);
    final text = _f.yearFrom == null && _f.yearTo == null
        ? 'Будь-який рік'
        : '${_f.yearFrom ?? HikkaFilterSheet.firstYear} – ${_f.yearTo ?? _lastYear}';
    return _section('Роки', hint: text, _rangeRow(
      min: min,
      max: max,
      values: RangeValues(from, to),
      onChanged: (v) => setState(() {
        final a = v.start.round();
        final b = v.end.round();
        _f = _f.copyWith(yearFrom: a <= HikkaFilterSheet.firstYear ? null : a, yearTo: b >= _lastYear ? null : b);
      }),
    ));
  }

  Widget _scores() {
    final from = (_f.scoreFrom ?? 0).toDouble().clamp(0.0, 10.0);
    final to = (_f.scoreTo ?? 10).toDouble().clamp(0.0, 10.0);
    final text = _f.scoreFrom == null && _f.scoreTo == null ? 'Будь-яка оцінка' : '${_f.scoreFrom ?? 0} – ${_f.scoreTo ?? 10}';
    return _section('Оцінка MyAnimeList', hint: text, _rangeRow(
      min: 0,
      max: 10,
      values: RangeValues(from, to),
      onChanged: (v) => setState(() {
        final a = v.start.round();
        final b = v.end.round();
        _f = _f.copyWith(scoreFrom: a <= 0 ? null : a, scoreTo: b >= 10 ? null : b);
      }),
    ));
  }

  Widget _genreGroups() {
    return FutureBuilder<List<HikkaGenre>>(
      future: _genres,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return HikkaLoading(scale: _scale, height: 70);
        if (snap.hasError) {
          return Padding(
            padding: EdgeInsets.symmetric(horizontal: _pad),
            child: HikkaErrorView(scale: _scale, error: snap.error!, compact: true, onRetry: () => setState(() {})),
          );
        }
        final all = snap.data ?? const [];
        final groups = <String>['genre', 'theme', 'demographic', if (widget.allowAdult) 'explicit'];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final type in groups)
              if (all.any((g) => g.type == type))
                _section(
                  HikkaText.genreTypes[type] ?? type,
                  hint: _selected(all.where((g) => g.type == type && _f.genres.contains(g.slug)).length),
                  bleed: true,
                  _pillRow([
                    for (final g in all.where((g) => g.type == type))
                      _pill(g.name, _f.genres.contains(g.slug), () => setState(() => _f = _f.copyWith(genres: _toggled(_f.genres, g.slug)))),
                  ]),
                ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final scale = _scale;
    final ratings = {
      for (final r in HikkaSearchFilters.safeRatings) r: HikkaText.rating(r),
      if (widget.allowAdult) 'rx': HikkaText.rating('rx'),
    };
    final pad = _pad;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(pad, 0, pad / 2, 4 * scale),
          child: Row(
            children: [
              Expanded(
                child: Text(widget.title, style: TextStyle(fontFamily: 'Arial', fontFamilyFallback: kUiFontFallback, color: uiTheme.textPrimary, fontSize: 18 * scale, fontWeight: FontWeight.bold)),
              ),
              if (_hasChanges)
                HikkaLinkButton(label: 'Скинути', icon: Symbols.restart_alt_rounded, scale: scale, onTap: () => setState(() => _f = HikkaSearchFilters(query: _f.query, sort: widget.defaultSort))),
              Tooltip(
                message: 'Закрити',
                child: Semantics(
                  button: true,
                  label: 'Закрити',
                  child: InkResponse(
                    radius: 22 * scale,
                    onTap: widget.onClose,
                    child: SizedBox.square(
                      dimension: math.max(44 * scale, AppPlatform.isMobile ? AppPlatform.touchTarget : 0.0),
                      child: Center(child: LineIconView(LineIcon.close, size: 20 * scale, color: uiTheme.textDarkMuted)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Flexible(
          child: AppScrollbar(
            scale: scale,
            controller: _scroll,
            child: SingleChildScrollView(
              controller: _scroll,
              padding: EdgeInsets.only(top: 12 * scale, bottom: 8 * scale),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _section(
                    'Сортування',
                    bleed: true,
                    // The direction is switched right in the caption
                    trailing: Semantics(
                      button: true,
                      child: InkWell(
                        onTap: () => setState(() => _f = _f.copyWith(ascending: !_f.ascending)),
                        borderRadius: uiTheme.borderRadius(6 * scale),
                        splashColor: Colors.transparent,
                        highlightColor: uiTheme.touchHighlight,
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 6 * scale, horizontal: 2 * scale),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Transform.rotate(
                                angle: _f.ascending ? math.pi : 0,
                                child: LineIconView(LineIcon.chevronDown, size: 14 * scale, color: AppTones.plateText),
                              ),
                              SizedBox(width: 4 * scale),
                              Text(
                                _f.ascending ? 'за зростанням' : 'за спаданням',
                                style: TextStyle(fontFamily: 'Arial', fontFamilyFallback: kUiFontFallback, color: AppTones.plateText, fontSize: 12.5 * scale),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    _pillRow([for (final o in widget.sortOptions) _pill(o.label, _f.sort == o.key, () => setState(() => _f = _f.copyWith(sort: o.key)))]),
                  ),
                  _section('Тип', hint: _selected(_f.mediaTypes.length), bleed: true, _chips(HikkaText.mediaTypes, _f.mediaTypes, (v) => setState(() => _f = _f.copyWith(mediaTypes: v)))),
                  _section(
                    'Статус виходу',
                    hint: _selected(_f.statuses.length),
                    bleed: true,
                    _chips(
                      {for (final s in const ['ongoing', 'finished', 'announced']) s: HikkaText.status(s)},
                      _f.statuses,
                      (v) => setState(() => _f = _f.copyWith(statuses: v)),
                    ),
                  ),
                  _section('Сезон', hint: _selected(_f.seasons.length) ?? 'разом з роком виходу', bleed: true, _chips(HikkaText.seasons, _f.seasons, (v) => setState(() => _f = _f.copyWith(seasons: v)))),
                  _years(),
                  _scores(),
                  if (_f.studios.isNotEmpty)
                    _section(
                      'Студія',
                      hint: 'натисніть, щоб прибрати',
                      bleed: true,
                      _pillRow([
                        for (final slug in _f.studios)
                          _pill(_f.studioNames[slug] ?? slug, true, () => setState(() => _f = _f.copyWith(studios: _toggled(_f.studios, slug))), icon: Symbols.apartment_rounded),
                      ]),
                    ),
                  _genreGroups(),
                  _section('Вікова категорія', hint: _selected(_f.ratings.length), bleed: true, _chips(ratings, _f.ratings, (v) => setState(() => _f = _f.copyWith(ratings: v)))),
                  Padding(
                    padding: EdgeInsets.fromLTRB(pad, 0, pad, 12 * scale),
                    child: HikkaToggleRow(
                      scale: scale,
                      title: 'Лише з українським перекладом',
                      subtitle: 'Приховує тайтли, яких ще не переклали',
                      value: _f.onlyTranslated,
                      onChanged: (v) => setState(() => _f = _f.copyWith(onlyTranslated: v)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(pad, 8 * scale, pad, 10 * scale),
          child: ValueListenableBuilder<int?>(
            valueListenable: _count,
            builder: (context, n, _) => _ShowButton(
              scale: scale,
              label: n == null ? 'Показати результати' : 'Показати ${HikkaText.count(n)} ${HikkaText.plural(n, 'тайтл', 'тайтли', 'тайтлів')}',
              onTap: () => widget.onApply(_f),
            ),
          ),
        ),
      ],
    );
  }
}

/// The sheet's main button: an accent wash with an outline, the accent check mark and white bold text
class _ShowButton extends StatelessWidget {
  final double scale;
  final String label;
  final VoidCallback onTap;

  const _ShowButton({required this.scale, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final accent = uiTheme.accentColor;
    final shape = RoundedRectangleBorder(borderRadius: uiTheme.borderRadius(14 * scale), side: BorderSide(color: accent));
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: AppTones.accentWash,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          splashColor: Colors.transparent,
          highlightColor: uiTheme.touchHighlight,
          hoverColor: uiTheme.hoverOverlay,
          onTap: onTap,
          child: SizedBox(
            height: math.max(46 * scale, AppPlatform.isMobile ? AppPlatform.touchTarget : 0.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                LineIconView(LineIcon.check, size: 18 * scale, color: accent, stroke: 2),
                SizedBox(width: 8 * scale),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontFamily: 'Arial', fontFamilyFallback: kUiFontFallback, color: uiTheme.textPrimary, fontSize: 14.5 * scale, fontWeight: FontWeight.bold),
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
