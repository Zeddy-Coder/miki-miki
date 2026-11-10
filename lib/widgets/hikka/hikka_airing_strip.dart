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

/// Підпис серії в стрічці календаря: коли вийшла чи вийде і чи це «просто зараз»
class HikkaAiring {
  final String text;

  /// Серія вже вийшла (в останні години) — її позначено акцентом
  final bool live;

  const HikkaAiring(this.text, {required this.live});

  /// Серія, що вийшла менше [recentWindow] тому, вважається «щойно вийшла»; далі — звичайний час виходу
  static const Duration recentWindow = Duration(hours: 4);

  /// Серія виходить у поточну годину за годинником (21:00–21:59 для 21:16), незалежно від того, вийшла вона вже чи ні
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

/// Тонка стрічка календаря на «Головній»: один рядок, у якому по черзі (фейдом) з'являються серії, що щойно вийшли
/// чи вийдуть найближчим часом. Іконка ліворуч відкриває повний розклад.
class HikkaAiringStrip extends StatelessWidget {
  final double scale;
  final double pad;
  final Object? token;

  const HikkaAiringStrip({super.key, required this.scale, required this.pad, this.token});

  /// Скільки серій брати з розкладу
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
        final now = DateTime.now();
        final entries = [...list]..sort((a, b) => a.airingAt.compareTo(b.airingAt));
        return _Strip(entries: entries, now: now, scale: scale, pad: pad);
      },
    );
  }
}

double _stripHeight(double scale) => AppPlatform.isMobile ? 44.0 : 40 * scale;

/// Як часто стрічка перемикає серію
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

/// Тонка смужка «як у службах новин»: один запис, що м'яко змінюється іншим (фейдом), час і номер серії збоку,
/// Тап по запису відкриває аніме, по іконці — календар.
class _StripState extends State<_Strip> {
  Timer? _timer;
  int _index = 0;

  /// Серія, з якої починає стрічка: перша цієї години; немає такої — найближча наступна; немає й її — остання вийшла
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

/// Один запис стрічки: назва ліворуч, номер серії й час збоку праворуч
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
    // Збоку лише час (економимо місце); серія іншого дня — з назвою дня
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
              // Крапка лише в серій, що виходять у цю годину
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
