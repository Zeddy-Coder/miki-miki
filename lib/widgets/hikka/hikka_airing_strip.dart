import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../models/hikka_models.dart';
import '../../services/hikka_api.dart';
import '../../services/hikka_nav.dart';
import '../../services/hikka_prefs.dart';
import '../../services/ui_theme_service.dart';
import '../../utils/platform_info.dart';
import '../app_animation_kit.dart';
import 'hikka_common.dart';
import '../../utils/app_clock.dart';

/// Episode label in the calendar feed: when it aired or will air and whether it is "just now"
class HikkaAiring {
  final String text;

  /// The episode has already aired (in recent hours): it is marked with the accent
  final bool live;

  const HikkaAiring(this.text, {required this.live});

  /// An episode that aired less than [recentWindow] ago counts as "just aired"; beyond that, the ordinary air time
  static const Duration recentWindow = Duration(hours: 4);

  /// The episode airs in the current clock hour (21:00–21:59 for 21:16), regardless of whether it has already aired
  static bool isCurrent(HikkaScheduleEntry e, DateTime now) {
    final t = e.time;
    return t.year == now.year && t.month == now.month && t.day == now.day && t.hour == now.hour;
  }

  static HikkaAiring of(HikkaScheduleEntry e, DateTime now) {
    final diff = e.time.difference(now);
    if (diff.isNegative) {
      final ago = -diff;
      if (ago < const Duration(minutes: 1)) return const HikkaAiring('вийшла щойно', live: true);
      if (ago < const Duration(hours: 1)) return HikkaAiring('вийшла ${ago.inMinutes} хв тому', live: true);
      return HikkaAiring('вийшла о ${HikkaText.hhmm(e.time)}', live: ago < recentWindow);
    }
    if (diff < const Duration(hours: 1)) return HikkaAiring('через ${diff.inMinutes.clamp(1, 59)} хв', live: false);
    return HikkaAiring(HikkaText.airingLabel(e.time, now), live: false);
  }
}

/// A thin calendar ticker on "Головна": one line in which episodes that just aired
/// or will air soon appear in turn (fading). The icon on the left opens the full schedule.
class HikkaAiringStrip extends StatelessWidget {
  final double scale;
  final double pad;
  final Object? token;

  const HikkaAiringStrip({super.key, required this.scale, required this.pad, this.token});

  /// How many episodes to take from the schedule
  static const int limit = 24;

  @override
  Widget build(BuildContext context) {
    final adult = HikkaPrefs.instance.allowAdult;
    return HikkaAsync<List<HikkaScheduleEntry>>(
      key: ValueKey('airing-$token-$adult'),
      scale: scale,
      compactError: true,
      load: () async => (await HikkaApi.instance.schedule(size: limit, allowAdult: adult)).items,
      loading: (context) => _StripSkeleton(scale: scale, pad: pad),
      builder: (context, list) {
        final now = AppClock.now();
        final entries = [...list]..sort((a, b) => a.airingAt.compareTo(b.airingAt));
        return _Strip(entries: entries, now: now, scale: scale, pad: pad);
      },
    );
  }
}

double _stripHeight(double scale) => AppPlatform.isMobile ? 44.0 : 40 * scale;

/// How often the ticker switches the episode
const Duration kAiringTick = Duration(seconds: 5);

class _Strip extends StatefulWidget {
  final List<HikkaScheduleEntry> entries;
  final DateTime now;
  final double scale;
  final double pad;

  const _Strip({required this.entries, required this.now, required this.scale, required this.pad});

  @override
  State<_Strip> createState() => _StripState();
}

/// A thin strip "like news services": one entry that softly gives way to another (fading), time and episode number at the side,
/// A tap on an entry opens the anime, on the icon the calendar.
class _StripState extends State<_Strip> {
  Timer? _timer;
  int _index = 0;

  /// The episode the ticker starts from: the first of this hour; if none, the nearest upcoming; if none, the last aired
  int get _startIndex {
    final e = widget.entries;
    if (e.isEmpty) return -1;
    final cur = e.indexWhere((x) => HikkaAiring.isCurrent(x, widget.now));
    if (cur >= 0) return cur;
    final next = e.indexWhere((x) => !x.time.isBefore(widget.now));
    return next >= 0 ? next : e.length - 1;
  }

  @override
  void initState() {
    super.initState();
    _index = math.max(0, _startIndex);
    if (widget.entries.length > 1) {
      _timer = Timer.periodic(kAiringTick, (_) {
        if (mounted) setState(() => _index = (_index + 1) % widget.entries.length);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.scale;
    final entries = widget.entries;
    if (entries.isEmpty) return const SizedBox.shrink();
    final r = uiTheme.borderRadius(12 * scale);
    final entry = entries[_index.clamp(0, entries.length - 1)];
    return Padding(
      padding: EdgeInsets.fromLTRB(widget.pad, 0, widget.pad, 14 * scale),
      child: Container(
        height: _stripHeight(scale),
        decoration: BoxDecoration(color: uiTheme.bgSurface, borderRadius: r, border: Border.all(color: uiTheme.borderSubtle)),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Row(
              children: [
                _CalendarButton(scale: scale),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: AppAnim.medium,
                    switchInCurve: AppAnim.easeOut,
                    switchOutCurve: Curves.easeIn,
                    layoutBuilder: (current, previous) => Stack(fit: StackFit.expand, children: [...previous, if (current != null) current]),
                    transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
                    child: _EpisodeLine(key: ValueKey('${entry.anime.slug}-${entry.episode}-$_index'), entry: entry, now: widget.now, scale: scale),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CalendarButton extends StatelessWidget {
  final double scale;

  const _CalendarButton({required this.scale});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Календар виходу серій',
      excludeSemantics: true,
      child: Material(
        color: uiTheme.bgElevated,
        child: InkWell(
          splashColor: Colors.transparent,
          highlightColor: uiTheme.touchHighlight,
          hoverColor: uiTheme.hoverOverlay,
          onTap: () => HikkaNav.instance.setTab(HikkaTab.schedule),
          child: SizedBox(
            width: 46 * (AppPlatform.isMobile ? 1.0 : scale),
            height: double.infinity,
            child: Icon(Symbols.calendar_month_rounded, color: uiTheme.textMuted, size: 21 * scale, weight: 300),
          ),
        ),
      ),
    );
  }
}

/// One ticker entry: the title on the left, the episode number and time at the right
class _EpisodeLine extends StatelessWidget {
  final HikkaScheduleEntry entry;
  final DateTime now;
  final double scale;

  const _EpisodeLine({super.key, required this.entry, required this.now, required this.scale});

  @override
  Widget build(BuildContext context) {
    final a = entry.anime;
    final airing = HikkaAiring.of(entry, now);
    final title = a.title(HikkaPrefs.instance.titleLang);
    final episode = entry.episode > 0 ? 'Серія ${entry.episode}' : 'Нова серія';
    final accent = uiTheme.accentColor;
    // Only the time at the side (saving room); an episode of another day with the day name
    final t = entry.time;
    final today = t.year == now.year && t.month == now.month && t.day == now.day;
    final when = today ? HikkaText.hhmm(t) : HikkaText.airingLabel(t, now);
    return Semantics(
      button: true,
      label: '$title. $episode, ${airing.text}',
      excludeSemantics: true,
      child: InkWell(
        splashColor: Colors.transparent,
        highlightColor: uiTheme.touchHighlight,
        hoverColor: uiTheme.hoverOverlay,
        onTap: () => HikkaNav.instance.openAnime(a.slug, seed: a),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 12 * scale),
          child: Row(
            children: [
              // A dot only for episodes airing in this hour
              if (HikkaAiring.isCurrent(entry, now)) ...[
                Container(
                  width: 7 * scale,
                  height: 7 * scale,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: accent),
                ),
                SizedBox(width: 9 * scale),
              ],
              Expanded(
                child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: hikkaStyle(12.5 * scale, weight: FontWeight.w600)),
              ),
              SizedBox(width: 10 * scale),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 150 * (AppPlatform.isMobile ? 1.0 : scale)),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(episode, maxLines: 1, overflow: TextOverflow.ellipsis, style: hikkaStyle(10.5 * scale, color: uiTheme.textMuted, height: 1.15)),
                    Text(when, maxLines: 1, overflow: TextOverflow.ellipsis, style: hikkaStyle(11.5 * scale, color: uiTheme.textPrimary, weight: FontWeight.w600, height: 1.2)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StripSkeleton extends StatelessWidget {
  final double scale;
  final double pad;

  const _StripSkeleton({required this.scale, required this.pad});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 0, pad, 14 * scale),
      child: Container(
        height: _stripHeight(scale),
        decoration: BoxDecoration(color: uiTheme.bgElevated, borderRadius: uiTheme.borderRadius(12 * scale)),
      ),
    );
  }
}
