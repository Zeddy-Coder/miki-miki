import 'package:flutter/material.dart';

import '../../models/hikka_models.dart';
import '../../services/hikka_api.dart';
import '../../services/hikka_nav.dart';
import '../../services/hikka_prefs.dart';
import '../../services/ui_theme_service.dart';
import '../design_kit.dart';
import '../line_icons.dart';
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

/// The quiet "today" row on "Головна": the episode airing this hour (or the nearest one) with its time and how many more
/// come out today; a tap opens the calendar.
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
        return HikkaTodayRow(entries: entries, now: now, scale: scale, pad: pad);
      },
    );
  }
}

/// The row itself (the entries are sorted by time)
class HikkaTodayRow extends StatelessWidget {
  final List<HikkaScheduleEntry> entries;
  final DateTime now;
  final double scale;
  final double pad;

  const HikkaTodayRow({super.key, required this.entries, required this.now, required this.scale, required this.pad});

  /// The episode to show: the first of this hour; if none, the nearest upcoming; if none, the last aired
  static int pick(List<HikkaScheduleEntry> e, DateTime now) {
    if (e.isEmpty) return -1;
    final cur = e.indexWhere((x) => HikkaAiring.isCurrent(x, now));
    if (cur >= 0) return cur;
    final next = e.indexWhere((x) => !x.time.isBefore(now));
    return next >= 0 ? next : e.length - 1;
  }

  static bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  /// "Сьогодні о 10:00 · ще 8 серій до кінця дня"
  static String subtitleOf(List<HikkaScheduleEntry> e, int i, DateTime now) {
    final t = e[i].time;
    final tomorrow = now.add(const Duration(days: 1));
    final when = _sameDay(t, now)
        ? 'Сьогодні о ${HikkaText.hhmm(t)}'
        : (_sameDay(t, tomorrow) ? 'Завтра о ${HikkaText.hhmm(t)}' : HikkaText.airingLabel(t, now));
    if (!_sameDay(t, now)) return when;
    final later = e.skip(i + 1).where((x) => _sameDay(x.time, now)).length;
    if (later == 0) return when;
    return '$when · ще $later ${HikkaText.plural(later, 'серія', 'серії', 'серій')} до кінця дня';
  }

  @override
  Widget build(BuildContext context) {
    final i = pick(entries, now);
    if (i < 0) return const SizedBox.shrink();
    final e = entries[i];
    final title = e.anime.title(HikkaPrefs.instance.titleLang);
    final episode = e.episode > 0 ? 'серія ${e.episode}' : 'нова серія';
    return Padding(
      padding: EdgeInsets.only(bottom: 10 * scale),
      child: AppLineRow(
        key: const ValueKey('today-row'),
        scale: scale,
        inset: pad + 2 * scale,
        icon: LineIcon.clock,
        title: '$title · $episode',
        subtitle: subtitleOf(entries, i, now),
        singleLine: true,
        chevron: true,
        onTap: () => HikkaNav.instance.setTab(HikkaTab.schedule),
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
    final inset = pad + 2 * scale;
    return Padding(
      padding: EdgeInsets.fromLTRB(inset, 14 * scale, inset, 20 * scale),
      child: Row(
        children: [
          Container(width: 22 * scale, height: 22 * scale, decoration: BoxDecoration(color: uiTheme.bgElevated, shape: BoxShape.circle)),
          SizedBox(width: 16 * scale),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                hikkaSkeletonBar(null, 13 * scale, factor: 0.75),
                SizedBox(height: 7 * scale),
                hikkaSkeletonBar(null, 10 * scale, factor: 0.5),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
