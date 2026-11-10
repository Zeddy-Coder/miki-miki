import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../models/hikka_models.dart';
import '../../services/hikka_api.dart';
import '../../services/hikka_nav.dart';
import '../../services/hikka_pager.dart';
import '../../services/hikka_prefs.dart';
import '../../services/ui_theme_service.dart';
import '../../utils/platform_info.dart';
import '../app_animation_kit.dart';
import '../app_ui_kit.dart';
import 'hikka_common.dart';
import 'hikka_page_kit.dart';

/// Вкладка «Календар»: вкладки днів тижня (Пн–Нд), під ними серії вибраного дня. Відкривається на сьогоднішньому дні;
/// дні гортаються свайпом. Показуються серії найближчих семи діб; решта розкладу підвантажується, поки не покриє тиждень.
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

  /// Вибраний день тижня: 0 — понеділок
  late int _day = DateTime.now().weekday - 1;

  @override
  void initState() {
    super.initState();
    _adult = HikkaPrefs.instance.allowAdult;
    _token = widget.refreshToken;
    _pager = HikkaPager<HikkaScheduleEntry>(
      // Відповідь важка (≈3 КБ на серію: з описом аніме), тож береться порціями
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

  @override
  void dispose() {
    _pager.removeListener(_onPager);
    _scroll.dispose();
    _pager.dispose();
    super.dispose();
  }

  /// Початок сьогоднішньої доби
  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  void _onPager() {
    if (!mounted) return;
    setState(() {});
    // Докантажуємо розклад, поки він не покриє найближчі сім діб
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pager.hasMore || _pager.loading || _pager.error != null || _pager.items.isEmpty) return;
      final last = _pager.items.map((e) => e.time).reduce((a, b) => a.isAfter(b) ? a : b);
      if (last.isBefore(_today().add(const Duration(days: 7)))) _pager.loadMore();
    });
  }

  /// Серії вибраного дня тижня в межах найближчих семи діб, за часом
  List<HikkaScheduleEntry> _entriesOf(int day) {
    final from = _today();
    final to = from.add(const Duration(days: 7));
    final list = [
      for (final e in _pager.items)
        if (e.time.weekday - 1 == day && !e.time.isBefore(from) && e.time.isBefore(to)) e,
    ]..sort((a, b) => a.time.compareTo(b.time));
    return list;
  }

  Widget _tabs(double pad) {
    final scale = widget.scale;
    final today = DateTime.now().weekday - 1;
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 4 * scale, pad, 10 * scale),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 780 * (AppPlatform.isMobile ? 1 : scale)),
          child: Container(
            padding: EdgeInsets.all(4 * scale),
            decoration: BoxDecoration(
              color: uiTheme.bgElevated.withValues(alpha: 0.5),
              borderRadius: uiTheme.borderRadius(14 * scale),
              border: Border.all(color: uiTheme.borderSubtle),
            ),
            child: Row(
              children: [
                for (int i = 0; i < _days.length; i++)
                  Expanded(
                    child: Semantics(
                      button: true,
                      selected: i == _day,
                      label: _days[i],
                      excludeSemantics: true,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => setState(() => _day = i),
                        child: AppAnimatedContainer(
                          duration: AppAnim.normal,
                          curve: AppAnim.easeOut,
                          padding: EdgeInsets.symmetric(vertical: 15 * scale),
                          decoration: BoxDecoration(
                            color: i == _day ? uiTheme.accentColor.withValues(alpha: 0.18) : Colors.transparent,
                            borderRadius: uiTheme.borderRadius(10 * scale),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _days[i],
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontFamily: 'Arial',
                                  color: i == _day ? uiTheme.accentColor : (i == today ? uiTheme.textPrimary : uiTheme.textMuted),
                                  fontSize: 13.5 * scale,
                                  fontWeight: i == _day || i == today ? FontWeight.bold : FontWeight.w500,
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
        ),
      ),
    );
  }

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
    return AppScrollbar(
      scale: scale,
      controller: _scroll,
      child: ListView.builder(
        controller: _scroll,
        padding: EdgeInsets.fromLTRB(pad, 4 * scale, pad, 24 * scale + widget.bottomInset),
        itemCount: entries.length,
        itemBuilder: (context, i) => Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 780 * (AppPlatform.isMobile ? 1 : scale)),
            child: _EpisodeTile(entry: entries[i], scale: scale),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.scale;
    final pad = HikkaLayout.sidePad(context, scale);

    if (_pager.error != null && _pager.items.isEmpty) {
      return HikkaErrorView(scale: scale, error: _pager.error!, onRetry: _pager.retry);
    }
    if (_pager.items.isEmpty) {
      if (_pager.isEmpty) {
        return AppEmptyState(scale: scale, icon: Symbols.event_busy_rounded, text: 'Розклад поки порожній');
      }
      return _ScheduleSkeleton(scale: scale, pad: pad);
    }
    return HikkaCollapsingHeader(
      resetOn: _day,
      header: _tabs(pad),
      body: HikkaSwipeTabs(
        swipe: false, // свайп убік — для вкладок «Огляду» вище, дні перемикаються тапом
        index: _day,
        count: _days.length,
        onChanged: (i) => setState(() => _day = i),
        child: _list(pad),
      ),
    );
  }
}

class _EpisodeTile extends StatelessWidget {
  final HikkaScheduleEntry entry;
  final double scale;

  const _EpisodeTile({required this.entry, required this.scale});

  @override
  Widget build(BuildContext context) {
    final a = entry.anime;
    final title = a.title(HikkaPrefs.instance.titleLang);
    final now = DateTime.now();
    final muted = uiTheme.textMuted;
    Widget fact(IconData icon, String text, {bool accent = false}) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16 * scale, color: accent ? uiTheme.accentColor : muted),
            SizedBox(width: 5 * scale),
            Text(text, style: TextStyle(fontFamily: 'Arial', color: accent ? uiTheme.accentColor : uiTheme.textPrimary, fontSize: 13 * scale, fontWeight: accent ? FontWeight.bold : FontWeight.w500)),
          ],
        );
    return Padding(
      padding: EdgeInsets.only(bottom: 10 * scale),
      child: AppCard(
        scale: scale,
        radius: 12,
        onTap: () => HikkaNav.instance.openAnime(a.slug, seed: a),
        padding: EdgeInsets.all(10 * scale),
        child: Row(
          children: [
            SizedBox(width: 62 * scale, child: HikkaPoster(url: a.image, scale: scale, radius: 8, icon: Symbols.movie_rounded)),
            SizedBox(width: 14 * scale),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontFamily: 'Arial', color: uiTheme.textPrimary, fontSize: 14.5 * scale, fontWeight: FontWeight.bold, height: 1.25),
                  ),
                  SizedBox(height: 8 * scale),
                  if (entry.episode > 0)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 8 * scale, vertical: 3 * scale),
                        decoration: BoxDecoration(color: uiTheme.accentWash, borderRadius: uiTheme.borderRadius(6 * scale)),
                        child: Text(
                          '${entry.episode} серія${a.episodesTotal != null && a.episodesTotal! > 0 ? ' з ${a.episodesTotal}' : ''}',
                          style: TextStyle(fontFamily: 'Arial', color: uiTheme.accentColor, fontSize: 12 * scale, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  SizedBox(height: 8 * scale),
                  Wrap(
                    spacing: 14 * scale,
                    runSpacing: 4 * scale,
                    children: [
                      fact(Symbols.calendar_today_rounded, HikkaText.dayName(entry.time, now)),
                      fact(Symbols.schedule_rounded, HikkaText.hhmm(entry.time), accent: true),
                    ],
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

/// Заглушка розкладу: заголовок дня й кілька рядків серій
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
      padding: EdgeInsets.fromLTRB(pad, 8 * scale, pad, 0),
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
