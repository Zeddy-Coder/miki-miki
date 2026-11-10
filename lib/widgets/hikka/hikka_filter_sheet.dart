import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../models/hikka_models.dart';
import '../../services/hikka_api.dart';
import '../../services/ui_theme_service.dart';
import '../../utils/platform_info.dart';
import '../app_animation_kit.dart';
import '../app_ui_kit.dart';
import 'hikka_common.dart';

/// Панель фільтрів каталогу. Працює з копією умов; застосовується кнопкою внизу.
class HikkaFilterSheet extends StatefulWidget {
  final double scale;
  final HikkaSearchFilters initial;
  final bool allowAdult;
  final ValueChanged<HikkaSearchFilters> onApply;
  final VoidCallback onClose;

  /// Варіанти сортування й те, що вважається «за замовчуванням» (для списків користувача — свої)
  final List<HikkaSortOption> sortOptions;
  final String defaultSort;

  const HikkaFilterSheet({
    super.key,
    required this.scale,
    required this.initial,
    required this.allowAdult,
    required this.onApply,
    required this.onClose,
    this.sortOptions = HikkaSearchFilters.sorts,
    this.defaultSort = 'score',
  });

  /// Перший рік у повзунку
  static const int firstYear = 1960;

  @override
  State<HikkaFilterSheet> createState() => _HikkaFilterSheetState();
}

class _HikkaFilterSheetState extends State<HikkaFilterSheet> {
  late HikkaSearchFilters _f = widget.initial;
  late final Future<List<HikkaGenre>> _genres = HikkaApi.instance.genres();
  final ScrollController _scroll = AppSmoothScrollController();

  double get _scale => widget.scale;
  int get _lastYear => DateTime.now().year + 1;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Set<String> _toggled(Set<String> set, String value) => set.contains(value) ? ({...set}..remove(value)) : {...set, value};

  bool get _hasChanges => _f.activeCount > 0 || _f.sort != widget.defaultSort || _f.ascending;

  Widget _section(String title, Widget child, {String? hint}) {
    return Padding(
      padding: EdgeInsets.only(bottom: 20 * _scale),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontFamily: 'Arial', color: uiTheme.textPrimary, fontSize: 13.5 * _scale, fontWeight: FontWeight.bold)),
          if (hint != null)
            Padding(
              padding: EdgeInsets.only(top: 2 * _scale),
              child: Text(hint, style: TextStyle(fontFamily: 'Arial', color: uiTheme.textDarkMuted, fontSize: 11.5 * _scale)),
            ),
          SizedBox(height: 10 * _scale),
          child,
        ],
      ),
    );
  }

  Widget _chips(Map<String, String> options, Set<String> selected, ValueChanged<Set<String>> onChanged) {
    return Wrap(
      spacing: 8 * _scale,
      runSpacing: 8 * _scale,
      children: [
        for (final e in options.entries)
          HikkaChip(label: e.value, scale: _scale, selected: selected.contains(e.key), onTap: () => onChanged(_toggled(selected, e.key))),
      ],
    );
  }

  SliderThemeData _sliderTheme(BuildContext context) => SliderTheme.of(context).copyWith(
        trackHeight: 3,
        activeTrackColor: uiTheme.accentColor,
        inactiveTrackColor: uiTheme.borderSubtle,
        thumbColor: uiTheme.accentColor,
        overlayColor: uiTheme.accentColor.withValues(alpha: 0.14),
        rangeThumbShape: const RoundRangeSliderThumbShape(enabledThumbRadius: 9),
        rangeTrackShape: const RoundedRectRangeSliderTrackShape(),
      );

  Widget _rangeRow({
    required String valueText,
    required double min,
    required double max,
    required RangeValues values,
    required ValueChanged<RangeValues> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(valueText, style: TextStyle(fontFamily: 'Arial', color: uiTheme.accentColor, fontSize: 12.5 * _scale, fontWeight: FontWeight.w600)),
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
    return _rangeRow(
      valueText: text,
      min: min,
      max: max,
      values: RangeValues(from, to),
      onChanged: (v) => setState(() {
        final a = v.start.round();
        final b = v.end.round();
        _f = _f.copyWith(yearFrom: a <= HikkaFilterSheet.firstYear ? null : a, yearTo: b >= _lastYear ? null : b);
      }),
    );
  }

  Widget _scores() {
    final from = (_f.scoreFrom ?? 0).toDouble().clamp(0.0, 10.0);
    final to = (_f.scoreTo ?? 10).toDouble().clamp(0.0, 10.0);
    final text = _f.scoreFrom == null && _f.scoreTo == null ? 'Будь-яка оцінка' : '${_f.scoreFrom ?? 0} – ${_f.scoreTo ?? 10}';
    return _rangeRow(
      valueText: text,
      min: 0,
      max: 10,
      values: RangeValues(from, to),
      onChanged: (v) => setState(() {
        final a = v.start.round();
        final b = v.end.round();
        _f = _f.copyWith(scoreFrom: a <= 0 ? null : a, scoreTo: b >= 10 ? null : b);
      }),
    );
  }

  Widget _genreGroups() {
    return FutureBuilder<List<HikkaGenre>>(
      future: _genres,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return HikkaLoading(scale: _scale, height: 70);
        if (snap.hasError) {
          return HikkaErrorView(
            scale: _scale,
            error: snap.error!,
            compact: true,
            onRetry: () => setState(() {}),
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
                  Wrap(
                    spacing: 8 * _scale,
                    runSpacing: 8 * _scale,
                    children: [
                      for (final g in all.where((g) => g.type == type))
                        HikkaChip(
                          label: g.name,
                          scale: _scale,
                          selected: _f.genres.contains(g.slug),
                          onTap: () => setState(() => _f = _f.copyWith(genres: _toggled(_f.genres, g.slug))),
                        ),
                    ],
                  ),
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
    final pad = AppPlatform.isMobile ? 16.0 : 20 * scale;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(pad, 4 * scale, pad / 2, 4 * scale),
          child: Row(
            children: [
              Expanded(
                child: Text('Фільтри', style: TextStyle(fontFamily: 'Arial', color: uiTheme.textPrimary, fontSize: 16 * scale, fontWeight: FontWeight.bold)),
              ),
              if (_hasChanges)
                HikkaLinkButton(label: 'Скинути', scale: scale, onTap: () => setState(() => _f = HikkaSearchFilters(query: _f.query, sort: widget.defaultSort))),
              HikkaIconButton(icon: Symbols.close_rounded, tooltip: 'Закрити', scale: scale, onTap: widget.onClose),
            ],
          ),
        ),
        Divider(height: 1, color: uiTheme.borderSubtle),
        Flexible(
          child: AppScrollbar(
            scale: scale,
            controller: _scroll,
            child: SingleChildScrollView(
              controller: _scroll,
              padding: EdgeInsets.fromLTRB(pad, 16 * scale, pad, 8 * scale),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _section(
                    'Сортування',
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AppDropdown<String>(
                          scale: scale,
                          value: _f.sort,
                          options: [for (final s in widget.sortOptions) AppDropdownOption(value: s.key, label: s.label)],
                          onChanged: (v) => setState(() => _f = _f.copyWith(sort: v)),
                        ),
                        SizedBox(height: 8 * scale),
                        AppSegmentedBar<bool>(
                          scale: scale,
                          selectedValue: _f.ascending,
                          options: const [
                            AppSegmentOption(value: false, label: 'За спаданням'),
                            AppSegmentOption(value: true, label: 'За зростанням'),
                          ],
                          onSelected: (v) => setState(() => _f = _f.copyWith(ascending: v)),
                        ),
                      ],
                    ),
                  ),
                  _section('Тип', _chips(HikkaText.mediaTypes, _f.mediaTypes, (v) => setState(() => _f = _f.copyWith(mediaTypes: v)))),
                  _section(
                    'Статус',
                    _chips(
                      {for (final s in const ['ongoing', 'finished', 'announced']) s: HikkaText.status(s)},
                      _f.statuses,
                      (v) => setState(() => _f = _f.copyWith(statuses: v)),
                    ),
                  ),
                  _section('Сезон', _chips(HikkaText.seasons, _f.seasons, (v) => setState(() => _f = _f.copyWith(seasons: v))),
                      hint: 'Разом з роком виходу'),
                  _section('Рік виходу', _years()),
                  _section('Оцінка MyAnimeList', _scores()),
                  _genreGroups(),
                  _section('Вікова категорія', _chips(ratings, _f.ratings, (v) => setState(() => _f = _f.copyWith(ratings: v)))),
                  Padding(
                    padding: EdgeInsets.only(bottom: 12 * scale),
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
        Divider(height: 1, color: uiTheme.borderSubtle),
        Padding(
          padding: EdgeInsets.fromLTRB(pad, 10 * scale, pad, 10 * scale),
          child: AppAccentButton(
            scale: scale,
            expand: true,
            icon: Symbols.check_rounded,
            label: _f.activeCount == 0 ? 'Показати результати' : 'Показати результати · ${_f.activeCount}',
            onTap: () => widget.onApply(_f),
          ),
        ),
      ],
    );
  }
}
