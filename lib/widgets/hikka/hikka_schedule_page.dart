import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../models/hikka_models.dart';
import '../../services/hikka_api.dart';
import '../../services/hikka_nav.dart';
import '../../services/hikka_pager.dart';
import '../../services/hikka_prefs.dart';
import '../../services/ui_theme_service.dart';
import '../../utils/platform_info.dart';
import '../../services/hikka_lists.dart';
import '../app_animation_kit.dart';
import '../app_tones.dart';
import '../app_ui_kit.dart';
import 'hikka_common.dart';
import 'hikka_my_list_bar.dart' show HikkaListMark;
import 'hikka_page_kit.dart';
import '../../utils/app_clock.dart';

/// The "Календар" tab: weekday tabs (Mon–Sun) with the selected day's episodes below. Opens on today;
/// days flip by swipe. Episodes of the next seven days are shown; the rest of the schedule loads until it covers a week.
class HikkaSchedulePage extends StatefulWidget {
  final double scale;
  final double bottomInset;
  final int refreshToken;

  const HikkaSchedulePage({super.key, required this.scale, this.bottomInset = 0, this.refreshToken = 0});

  @override
  State<HikkaSchedulePage> createState() => _HikkaSchedulePageState();
}

class _HikkaSchedulePageState extends State<HikkaSchedulePage> {
  static const List<String> _days = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Нд'];

  late final HikkaPager<HikkaScheduleEntry> _pager;
  final ScrollController _scroll = AppSmoothScrollController();
  late bool _adult;
  late int _token;

  /// Selected day: 0 is today, 6 is the last of the next seven days
  int _day = 0;

  @override
  void initState() {
    super.initState();
    _adult = HikkaPrefs.instance.allowAdult;
    _token = widget.refreshToken;
    _pager = HikkaPager<HikkaScheduleEntry>(
      // The response is heavy (≈3 KB per episode: with the anime description), so it is fetched in portions
      (page) => HikkaApi.instance.schedule(page: page, size: 50, allowAdult: HikkaPrefs.instance.allowAdult),
      keyOf: (e) => '${e.anime.slug}#${e.episode}',
    );
    _pager.addListener(_onPager);
    _pager.reload();
  }

  @override
  void didUpdateWidget(HikkaSchedulePage old) {
    super.didUpdateWidget(old);
    final adult = HikkaPrefs.instance.allowAdult;
    if (adult != _adult || widget.refreshToken != _token) {
      _adult = adult;
      _token = widget.refreshToken;
      _pager.reload();
    }
  }

  HikkaHeaderSlot? _slot;

  @override
  void dispose() {
    // Not right now: the tree is being torn down, and a rebuild requested at this point of the frame would wait for the next
    // (unscheduled) frame, leaving the day tabs hanging in the header of another tab
    final slot = _slot;
    if (slot != null) WidgetsBinding.instance.addPostFrameCallback((_) => slot.clear());
    _pager.removeListener(_onPager);
    _scroll.dispose();
    _pager.dispose();
    super.dispose();
  }

  /// Start of today
  static DateTime _today() {
    final n = AppClock.now();
    return DateTime(n.year, n.month, n.day);
  }

  /// What the last rebuild showed: the pager notifies twice per page (loading starts, the page arrives), and only
  /// the second one changes the page once something is shown (the first one rebuilt every visible row for nothing)
  Object? _shown;

  void _onPager() {
    if (!mounted) return;
    final p = _pager;
    final shown = (p.items, p.error, p.isEmpty, p.items.isEmpty || _entriesOf(_day).isEmpty ? p.loading : false);
    if (shown != _shown) {
      _shown = shown;
      setState(() {});
    }
    // We load the schedule until it covers the next seven days
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pager.hasMore || _pager.loading || _pager.error != null || _pager.items.isEmpty) return;
      final last = _pager.items.map((e) => e.time).reduce((a, b) => a.isAfter(b) ? a : b);
      if (last.isBefore(_today().add(const Duration(days: 7)))) _pager.loadMore();
    });
  }

  /// The day [offset] days from today (by the calendar, so a clock change does not shift it)
  static DateTime _dateOf(int offset) {
    final t = _today();
    return DateTime(t.year, t.month, t.day + offset);
  }

  /// Episodes of the day [offset] days from today, by time
  List<HikkaScheduleEntry> _entriesOf(int offset) {
    final from = _dateOf(offset);
    final to = _dateOf(offset + 1);
    final list = [
      for (final e in _pager.items)
        if (!e.time.isBefore(from) && e.time.isBefore(to)) e,
    ]..sort((a, b) => a.time.compareTo(b.time));
    return list;
  }

  /// Seven day plates from today: the weekday and the date; today has an accent dot
  Widget _tabs(double pad) {
    final scale = widget.scale;
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 6 * scale, pad, 8 * scale),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 780 * (AppPlatform.isMobile ? 1 : scale)),
          child: Row(
            children: [
              for (int i = 0; i < _days.length; i++) ...[
                if (i > 0) SizedBox(width: 5 * scale),
                Expanded(
                  child: _DayPlate(
                    key: ValueKey('schedule-day-$i'),
                    date: _dateOf(i),
                    today: i == 0,
                    selected: i == _day,
                    scale: scale,
                    onTap: () => setState(() => _day = i),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// The day's caption ("Сьогодні · 15 серій"), the episodes by time and, today, a thin "now" line before the first
  /// episode still to come
  Widget _list(double pad) {
    final scale = widget.scale;
    final entries = _entriesOf(_day);
    if (entries.isEmpty) {
      return AppEmptyState(
        scale: scale,
        icon: Symbols.event_busy_rounded,
        text: _pager.loading ? 'Завантажую розклад…' : 'На цей день серій немає',
      );
    }
    final now = AppClock.now();
    final date = _dateOf(_day);
    final day = switch (_day) {
      0 => 'Сьогодні',
      1 => 'Завтра',
      _ => '${HikkaText.weekdays[date.weekday - 1]}, ${HikkaText.dayMonth(date, now: now)}',
    };
    final caption = '$day · ${entries.length} ${HikkaText.plural(entries.length, 'серія', 'серії', 'серій')}';
    final next = _day == 0 ? entries.indexWhere((e) => e.time.isAfter(now)) : -1;
    // Rows: the caption, the episodes, the "now" line among them (only when something has already come out today)
    final rows = <Object>['caption'];
    for (int i = 0; i < entries.length; i++) {
      if (i == next && i > 0) rows.add('now');
      rows.add(i);
    }
    // Builder: the header inset is provided by `HikkaCollapsingHeader`, so it can be read only from a context below it
    // (with the page's own context it was 0, and the first episode stayed under the day tabs)
    return Builder(
      builder: (context) => AppScrollbar(
        scale: scale,
        controller: _scroll,
        child: ListView.builder(
          controller: _scroll,
          padding: EdgeInsets.fromLTRB(0, 2 * scale + AppHeaderInset.of(context), 0, 24 * scale + widget.bottomInset),
          itemCount: rows.length,
          itemBuilder: (context, k) {
            final r = rows[k];
            final Widget child;
            if (r == 'caption') {
              child = Padding(
                padding: EdgeInsets.fromLTRB(pad, 8 * scale, pad, 6 * scale),
                child: Text(caption, style: hikkaStyle(13 * scale, color: AppTones.caption, weight: FontWeight.w700)),
              );
            } else if (r == 'now') {
              child = _NowLine(key: const ValueKey('schedule-now'), time: now, scale: scale, pad: pad);
            } else {
              final i = r as int;
              final e = entries[i];
              child = _EpisodeTile(
                entry: e,
                scale: scale,
                pad: pad,
                showTime: i == 0 || HikkaText.hhmm(entries[i - 1].time) != HikkaText.hhmm(e.time),
              );
            }
            return Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(constraints: BoxConstraints(maxWidth: 780 * (AppPlatform.isMobile ? 1 : scale) + pad * 2), child: child),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.scale;
    final pad = HikkaLayout.sidePad(context, scale);

    // Sections of "Огляд" stay mounted (offstage) when you leave them, so the day tabs must be taken out of the shared header by hand
    final visible = TickerMode.valuesOf(context).enabled;
    final slot = hikkaHeaderSlot(context);
    _slot = slot;
    void release() {
      if (slot != null) WidgetsBinding.instance.addPostFrameCallback((_) => slot.clear());
    }

    if (_pager.error != null && _pager.items.isEmpty) {
      release();
      return HikkaErrorView(scale: scale, error: _pager.error!, onRetry: _pager.retry);
    }
    if (_pager.items.isEmpty) {
      release();
      if (_pager.isEmpty) {
        return AppEmptyState(scale: scale, icon: Symbols.event_busy_rounded, text: 'Розклад поки порожній');
      }
      return _ScheduleSkeleton(scale: scale, pad: pad);
    }
    final body = HikkaSwipeTabs(
      swipe: false, // a sideways swipe belongs to the "Огляд" tabs above, days switch by tap
      index: _day,
      count: _days.length,
      onChanged: (i) => setState(() => _day = i),
      child: _list(pad),
    );
    // The day tabs are a part of the page's header (the nearest collapsing header above): they hide and show with it as one block.
    // Without such a header (the page on its own) it keeps its own.
    if (slot == null) return HikkaCollapsingHeader(resetOn: _day, header: _tabs(pad), body: body);
    if (!visible) {
      release(); // another tab is open: its header must not carry our tabs
      return body;
    }
    final tabs = KeyedSubtree(key: const ValueKey('schedule-tabs'), child: _tabs(pad));
    final same = (_day, _dateOf(0), scale, pad, uiTheme.isLight, uiTheme.accentColor);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && TickerMode.valuesOf(context).enabled) slot.put(tabs, resetOn: _day, same: same);
    });
    return body;
  }
}

/// A day plate of the calendar: the short weekday over the date; the chosen one lighter and outlined
class _DayPlate extends StatelessWidget {
  final DateTime date;
  final bool today;
  final bool selected;
  final double scale;
  final VoidCallback onTap;

  const _DayPlate({super.key, required this.date, required this.today, required this.selected, required this.scale, required this.onTap});

  static const List<String> _short = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Нд'];

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: uiTheme.borderRadius(12 * scale),
      side: selected ? BorderSide(color: AppTones.plateOutline) : BorderSide.none,
    );
    final day = _short[date.weekday - 1];
    return Semantics(
      button: true,
      selected: selected,
      label: today ? 'Сьогодні, $day ${date.day}' : '$day ${date.day}',
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
            height: 52 * scale,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(day, style: hikkaStyle(11 * scale, color: selected ? AppTones.plateText : uiTheme.textMuted)),
                    SizedBox(height: 1 * scale),
                    Text('${date.day}', style: hikkaStyle(15 * scale, weight: FontWeight.bold, color: selected ? uiTheme.textPrimary : AppTones.plateText)),
                  ],
                ),
                if (today)
                  Positioned(
                    bottom: 5 * scale,
                    child: Container(
                      key: const ValueKey('schedule-today-dot'),
                      width: 4 * scale,
                      height: 4 * scale,
                      decoration: BoxDecoration(color: uiTheme.accentColor, shape: BoxShape.circle),
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

/// A thin accent line "now" between what has come out today and what is still to come
class _NowLine extends StatelessWidget {
  final DateTime time;
  final double scale;
  final double pad;

  const _NowLine({super.key, required this.time, required this.scale, required this.pad});

  @override
  Widget build(BuildContext context) {
    final accent = uiTheme.accentColor;
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 4 * scale, pad, 4 * scale),
      child: Row(
        children: [
          Container(width: 7 * scale, height: 7 * scale, decoration: BoxDecoration(color: accent, shape: BoxShape.circle)),
          SizedBox(width: 8 * scale),
          Text(HikkaText.hhmm(time), style: hikkaStyle(12 * scale, color: accent)),
          SizedBox(width: 8 * scale),
          Expanded(child: Container(height: 1, color: accent.withValues(alpha: 0.55))),
        ],
      ),
    );
  }
}

/// An episode row: the time (once for several at the same minute), a small poster, the title and "Серія 6 з 12";
/// a title from my lists has its bookmark glyph on the right
class _EpisodeTile extends StatelessWidget {
  final HikkaScheduleEntry entry;
  final double scale;
  final double pad;
  final bool showTime;

  const _EpisodeTile({required this.entry, required this.scale, required this.pad, required this.showTime});

  @override
  Widget build(BuildContext context) {
    final a = entry.anime;
    final title = a.title(HikkaPrefs.instance.titleLang);
    final total = a.episodesTotal ?? 0;
    final episode = entry.episode > 0 ? 'Серія ${entry.episode}${total > 0 ? ' з $total' : ''}' : '';
    final status = HikkaMyList.instance.statusOf(a.slug);
    return Semantics(
      button: true,
      label: '${HikkaText.hhmm(entry.time)}. $title. $episode',
      excludeSemantics: true,
      child: InkWell(
        onTap: () => HikkaNav.instance.openAnime(a.slug, seed: a),
        splashColor: Colors.transparent,
        highlightColor: uiTheme.touchHighlight,
        hoverColor: uiTheme.hoverOverlay,
        child: Padding(
          padding: EdgeInsets.fromLTRB(pad, 6 * scale, pad, 6 * scale),
          child: Row(
            children: [
              SizedBox(
                width: 46 * scale,
                child: Text(showTime ? HikkaText.hhmm(entry.time) : '', style: hikkaStyle(13.5 * scale, color: uiTheme.textMuted)),
              ),
              SizedBox(width: 6 * scale),
              SizedBox(
                width: 44 * scale,
                child: HikkaPoster(url: a.image, malId: a.malId, scale: scale, radius: 8, aspect: 44 / 62, icon: Symbols.movie_rounded),
              ),
              SizedBox(width: 12 * scale),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: hikkaStyle(14.5 * scale, height: 1.25)),
                    if (episode.isNotEmpty)
                      Padding(
                        padding: EdgeInsets.only(top: 3 * scale),
                        child: Text(episode, style: hikkaStyle(12.5 * scale, color: AppTones.rowSub)),
                      ),
                  ],
                ),
              ),
              if (status != null) ...[
                SizedBox(width: 10 * scale),
                HikkaListMark(status: status, size: 18 * scale, color: AppTones.rowSub),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Schedule placeholder: a day heading and a few episode rows
class _ScheduleSkeleton extends StatelessWidget {
  final double scale;
  final double pad;

  const _ScheduleSkeleton({required this.scale, required this.pad});

  @override
  Widget build(BuildContext context) {
    Widget row() => Padding(
          padding: EdgeInsets.only(bottom: 8 * scale),
          child: Container(
            padding: EdgeInsets.all(10 * scale),
            decoration: BoxDecoration(
              color: uiTheme.bgElevated.withValues(alpha: 0.5),
              borderRadius: uiTheme.borderRadius(10 * scale),
              border: Border.all(color: uiTheme.borderSubtle),
            ),
            child: Row(
              children: [
                hikkaSkeletonBar(40 * scale, 12 * scale),
                SizedBox(width: 12 * scale),
                Container(
                  width: 46 * scale,
                  height: 46 * scale / 0.7,
                  decoration: BoxDecoration(color: uiTheme.bgElevated, borderRadius: uiTheme.borderRadius(6 * scale)),
                ),
                SizedBox(width: 12 * scale),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      hikkaSkeletonBar(null, 11 * scale, factor: 0.7),
                      SizedBox(height: 7 * scale),
                      hikkaSkeletonBar(null, 9 * scale, factor: 0.4),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(pad, 8 * scale + AppHeaderInset.of(context), pad, 0),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 780 * (AppPlatform.isMobile ? 1 : scale)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              hikkaSkeletonBar(110 * scale, 14 * scale),
              SizedBox(height: 12 * scale),
              for (int i = 0; i < 4; i++) row(),
              SizedBox(height: 10 * scale),
              hikkaSkeletonBar(130 * scale, 14 * scale),
              SizedBox(height: 12 * scale),
              for (int i = 0; i < 3; i++) row(),
            ],
          ),
        ),
      ),
    );
  }
}
