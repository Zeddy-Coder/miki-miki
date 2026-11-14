import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../models/hikka_models.dart';
import '../../models/hikka_profile_models.dart';
import '../../models/hikka_user_models.dart';
import '../../services/hikka_api.dart';
import '../../services/hikka_nav.dart';
import '../../services/hikka_prefs.dart';
import '../../services/ui_theme_service.dart';
import '../../utils/platform_info.dart';
import '../app_animation_kit.dart';
import '../app_ui_kit.dart';
import 'hikka_cards.dart';
import 'hikka_common.dart';
import 'hikka_community_cards.dart';
import 'hikka_my_list_bar.dart' show hikkaStatusColor;
import 'hikka_page_kit.dart';
import 'hikka_shelf.dart';
import '../../utils/app_clock.dart';

/// A Hikka user profile as on `hikka.io/u/<name>`: cover, avatar, description and links, followers,
/// "Список" (status counters and watch time), a year of "Активність", favorite anime and characters, articles,
/// collections and "Історія". Returns the page blocks, to be put in [HikkaPageFrame].
///
/// [own] is one's own profile: the status counters and "Усі" in favorites lead to the "Списки" tab.
class HikkaUserProfile extends StatefulWidget {
  final String username;
  final HikkaUser? seed;
  final double scale;
  final bool own;

  /// Another value means load everything anew (page refresh)
  final Object? reloadKey;

  const HikkaUserProfile({super.key, required this.username, required this.scale, this.seed, this.own = false, this.reloadKey});

  @override
  State<HikkaUserProfile> createState() => _HikkaUserProfileState();
}

/// Main profile data: the header and counters (loaded together, the rest in separate blocks)
class _Core {
  final HikkaUser user;
  final HikkaFollowStats follow;
  final HikkaWatchStats watch;
  final HikkaUserStats stats;

  const _Core(this.user, this.follow, this.watch, this.stats);
}

class _HikkaUserProfileState extends State<HikkaUserProfile> {
  _Core? _core;
  Object? _error;
  int _generation = 0;

  HikkaApi get _api => HikkaApi.instance;
  double get _scale => widget.scale;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(HikkaUserProfile old) {
    super.didUpdateWidget(old);
    if (old.username != widget.username || old.reloadKey != widget.reloadKey) _load();
  }

  void _load() {
    final gen = ++_generation;
    final name = widget.username;
    // Without the profile header there is no page; counters are optional, a failure leaves zeros
    Future<T> soft<T>(Future<T> f, T fallback) => f.catchError((Object _) => fallback);
    Future.wait<Object>([
      _api.user(name),
      soft(_api.followStats(name), const HikkaFollowStats()),
      soft(_api.watchStats(name), const HikkaWatchStats()),
      soft(_api.userStats(name), const HikkaUserStats()),
    ]).then<void>((r) {
      if (!mounted || gen != _generation) return;
      setState(() {
        _core = _Core(r[0] as HikkaUser, r[1] as HikkaFollowStats, r[2] as HikkaWatchStats, r[3] as HikkaUserStats);
        _error = null;
      });
    }, onError: (Object e) {
      if (!mounted || gen != _generation) return;
      setState(() => _error = e);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scale = _scale;
    final pad = HikkaLayout.sidePad(context, scale);
    final core = _core;
    final user = core?.user ?? widget.seed;
    if (user == null) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: pad, vertical: 24 * scale),
        child: _error != null
            ? HikkaErrorView(scale: scale, error: _error!, onRetry: () => setState(() {
                  _error = null;
                  _load();
                }))
            : HikkaLoading(scale: scale),
      );
    }
    final name = user.username.isNotEmpty ? user.username : widget.username;
    final token = '${widget.reloadKey}';
    final adult = HikkaPrefs.instance.allowAdult;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HikkaProfileHeader(user: user, follow: core?.follow, scale: scale, pad: pad),
        SizedBox(height: 22 * scale),
        if (core != null) ...[
          HikkaSection(
            scale: scale,
            pad: pad,
            title: 'Список',
            child: HikkaWatchSummary(stats: core.watch, scale: scale, onStatus: widget.own ? (s) => HikkaNav.instance.openLists(status: s) : null),
          ),
          HikkaSection(
            scale: scale,
            pad: pad,
            title: 'Активність',
            child: _ActivityCard(username: name, stats: core.stats, scale: scale, token: token),
          ),
          if (core.stats.favouriteAnime > 0)
            HikkaShelfAsync<HikkaAnime>(
              scale: scale,
              pad: pad,
              title: 'Улюблені аніме',
              subtitle: HikkaText.count(core.stats.favouriteAnime),
              token: '$name-$token',
              onMore: widget.own ? () => HikkaNav.instance.openLists(favourites: true) : null,
              load: () async => [for (final a in (await _api.favourites(name, size: 20)).items) if (adult || !a.isAdult) a],
              itemBuilder: (context, a) => HikkaAnimeCard(anime: a, scale: scale),
            ),
          if (core.stats.favouriteCharacters > 0)
            HikkaShelfAsync<HikkaCharacter>(
              scale: scale,
              pad: pad,
              title: 'Улюблені персонажі',
              subtitle: HikkaText.count(core.stats.favouriteCharacters),
              token: '$name-$token',
              load: () async => (await _api.favouriteCharacters(name, size: 20)).items,
              itemBuilder: (context, c) => HikkaCharacterCard(character: c, scale: scale),
            ),
          _AuthoredList<HikkaArticle>(
            key: ValueKey('articles-$name-$token'),
            scale: scale,
            pad: pad,
            title: 'Статті',
            load: () => _api.articles(author: name, size: 3),
            itemBuilder: (a) => HikkaArticleCard(article: a, scale: scale),
          ),
          _AuthoredList<HikkaCollection>(
            key: ValueKey('collections-$name-$token'),
            scale: scale,
            pad: pad,
            title: 'Колекції',
            load: () => _api.collections(author: name, sort: 'new', size: 3, contentType: null, allowAdult: adult),
            itemBuilder: (c) => HikkaCollectionCard(collection: c, scale: scale),
          ),
          HikkaSection(
            scale: scale,
            pad: pad,
            title: 'Історія',
            child: HikkaHistoryList(key: ValueKey('history-$name-$token'), username: name, scale: scale),
          ),
        ] else if (_error != null)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: pad),
            child: HikkaErrorView(scale: scale, error: _error!, compact: true, onRetry: () => setState(() {
                  _error = null;
                  _load();
                })),
          )
        else
          Padding(padding: EdgeInsets.symmetric(vertical: 24 * scale), child: HikkaLoading(scale: scale)),
      ],
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────────

/// Cover, avatar, name with a role, description, links and followers
class HikkaProfileHeader extends StatelessWidget {
  final HikkaUser user;
  final HikkaFollowStats? follow;
  final double scale;
  final double pad;

  const HikkaProfileHeader({super.key, required this.user, required this.scale, required this.pad, this.follow});

  @override
  Widget build(BuildContext context) {
    final mobile = AppPlatform.isMobile;
    final coverH = mobile ? 128.0 : 180 * scale;
    final avatar = mobile ? 84.0 : 104 * scale;
    final ring = 4 * scale;
    final cover = user.cover;
    final role = user.roleLabel;
    final f = follow;
    final since = user.created > 0 ? DateTime.fromMillisecondsSinceEpoch(user.created * 1000) : null;

    Widget count(int n, String label) => Text.rich(
          TextSpan(children: [
            TextSpan(text: HikkaText.count(n), style: hikkaStyle(13.5 * scale, weight: FontWeight.bold)),
            TextSpan(text: ' $label', style: hikkaStyle(13 * scale, color: uiTheme.textMuted)),
          ]),
        );

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: pad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              SizedBox(
                height: coverH,
                width: double.infinity,
                child: LayoutBuilder(
                  builder: (context, c) => cover == null
                      ? DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: uiTheme.borderRadius(16 * scale),
                            gradient: LinearGradient(colors: [uiTheme.accentWash, uiTheme.bgElevated]),
                            border: Border.all(color: uiTheme.borderSubtle),
                          ),
                        )
                      : HikkaPoster(url: cover, scale: scale, aspect: c.maxWidth / coverH, radius: 16, alignment: Alignment.center),
                ),
              ),
              Positioned(
                left: 16 * scale,
                bottom: -avatar / 2,
                child: Container(
                  width: avatar + ring * 2,
                  height: avatar + ring * 2,
                  padding: EdgeInsets.all(ring),
                  decoration: BoxDecoration(borderRadius: uiTheme.borderRadius(avatar / 2 + ring), color: uiTheme.bgPrimary),
                  child: user.avatar.isEmpty
                      ? DecoratedBox(
                          decoration: BoxDecoration(borderRadius: uiTheme.borderRadius(avatar / 2), color: uiTheme.accentWash),
                          child: Icon(Symbols.person_rounded, color: uiTheme.accentColor, size: avatar * 0.5, weight: 300),
                        )
                      : HikkaPoster(url: user.avatar, scale: scale, aspect: 1, radius: avatar / 2 / scale, icon: Symbols.person_rounded, alignment: Alignment.center),
                ),
              ),
            ],
          ),
          SizedBox(height: avatar / 2 + 12 * scale),
          Wrap(
            spacing: 8 * scale,
            runSpacing: 4 * scale,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(user.username, style: hikkaStyle(22 * scale, weight: FontWeight.bold)),
              if (role != null) HikkaPill(text: role, scale: scale, background: uiTheme.accentWash, foreground: uiTheme.accentColor),
            ],
          ),
          if (user.description != null) ...[
            SizedBox(height: 6 * scale),
            Text(user.description!, style: hikkaStyle(13.5 * scale, color: uiTheme.textSecondary, height: 1.4)),
          ],
          SizedBox(height: 10 * scale),
          Wrap(
            spacing: 16 * scale,
            runSpacing: 6 * scale,
            children: [
              if (f != null) count(f.followers, HikkaText.plural(f.followers, 'стежить', 'стежать', 'стежать')),
              if (f != null) count(f.following, 'відстежує'),
              if (since != null)
                Text('На Hikka з ${HikkaText.monthsGenitive[since.month - 1]} ${since.year}', style: hikkaStyle(13 * scale, color: uiTheme.textMuted)),
            ],
          ),
          if (user.links.isNotEmpty) ...[
            SizedBox(height: 12 * scale),
            Wrap(
              spacing: 8 * scale,
              runSpacing: 8 * scale,
              children: [
                for (final l in user.links)
                  HikkaChip(
                    label: l.label,
                    scale: scale,
                    icon: l.icon == 'telegram' ? Symbols.send_rounded : Symbols.link_rounded,
                    onTap: () => HikkaNav.instance.openLink(l.url),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ── List ───────────────────────────────────────────────────────────────────

/// "Список": a donut chart of statuses with the total in the center, a legend on the right (color, status, count,
/// share) and "Час перегляду" at the bottom. [onStatus] is a tap on a legend status or the center (`null` means no filter).
class HikkaWatchSummary extends StatelessWidget {
  final HikkaWatchStats stats;
  final double scale;
  final void Function(HikkaWatchStatus? status)? onStatus;

  const HikkaWatchSummary({super.key, required this.stats, required this.scale, this.onStatus});

  /// Order as on hikka.io
  static const List<HikkaWatchStatus> order = [
    HikkaWatchStatus.completed,
    HikkaWatchStatus.watching,
    HikkaWatchStatus.planned,
    HikkaWatchStatus.dropped,
    HikkaWatchStatus.onHold,
  ];

  @override
  Widget build(BuildContext context) {
    final total = stats.total;
    final donut = (AppPlatform.isMobile ? 124.0 : 150 * scale);
    return AppCard(
      scale: scale,
      radius: 14,
      padding: EdgeInsets.all(14 * scale),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              HikkaStatusDonut(
                size: donut,
                scale: scale,
                values: [for (final s in order) stats.of(s)],
                colors: [for (final s in order) hikkaStatusColor(s)],
                labels: [for (final s in order) s.label],
                total: total,
                // A tap on an arc means that status, on the center means all
                onTap: onStatus == null ? null : (i) => onStatus!(i == null ? null : order[i]),
              ),
              SizedBox(width: 16 * scale),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final s in order)
                      _legendRow(s.label, stats.of(s), hikkaStatusColor(s), onStatus == null ? null : () => onStatus!(s)),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 12 * scale),
          Row(
            children: [
              Icon(Symbols.schedule_rounded, size: 18 * scale, color: uiTheme.textMuted, weight: 300),
              SizedBox(width: 8 * scale),
              Expanded(child: Text('Час перегляду', style: hikkaStyle(13 * scale, color: uiTheme.textMuted))),
              Text(HikkaProfileText.watchTime(stats.duration), style: hikkaStyle(13.5 * scale, weight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legendRow(String label, int value, Color color, VoidCallback? onTap) {
    return _tappable(
      label: '$label: $value',
      onTap: onTap,
      radius: 8 * scale,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 5 * scale, horizontal: 4 * scale),
        child: Row(
          children: [
            Container(width: 9 * scale, height: 9 * scale, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            SizedBox(width: 8 * scale),
            Expanded(
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: hikkaStyle(12.5 * scale, color: uiTheme.textSecondary)),
            ),
            SizedBox(width: 6 * scale),
            Text(HikkaText.count(value), style: hikkaStyle(13 * scale, weight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _tappable({required String label, required VoidCallback? onTap, required double radius, required Widget child}) {
    return Semantics(
      button: onTap != null,
      label: label,
      excludeSemantics: true,
      child: onTap == null
          ? child
          : InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(radius),
              splashColor: Colors.transparent,
              highlightColor: uiTheme.touchHighlight,
              hoverColor: uiTheme.hoverOverlay,
              child: child,
            ),
    );
  }
}

/// Donut chart layout (angles in radians, from 12 o'clock clockwise). Each arc has rounded ends and
/// takes at least a "drop": a circle with the diameter of the line thickness; neighboring arcs have the same gap [gap].
/// The rest of the circle is divided proportionally to the values (small ones that fall short of a drop get a drop).
class HikkaDonutLayout {
  /// Indices of non-zero values and their arcs: [start] is the start of the visible arc accounting for the end cap, [length] is the length
  final List<int> indices;
  final List<double> starts;
  final List<double> lengths;

  /// The angle taken by a rounded end (half the thickness)
  final double cap;

  /// The angle of the gap between arcs
  final double gapAngle;

  const HikkaDonutLayout._(this.indices, this.starts, this.lengths, this.cap, this.gapAngle);

  static const double top = -math.pi / 2;

  /// [radius] is the radius of the ring's center line, [thickness] the thickness, [gap] the gap between arc ends (in pixels)
  factory HikkaDonutLayout.compute(List<int> values, {required double radius, required double thickness, required double gap}) {
    final idx = [for (int i = 0; i < values.length; i++) if (values[i] > 0) i];
    final n = idx.length;
    final cap = (thickness / 2) / radius;
    if (n == 0) return HikkaDonutLayout._(const [], const [], const [], cap, 0);
    if (n == 1) return HikkaDonutLayout._(idx, const [top], const [math.pi * 2], cap, 0);
    var gapA = gap / radius;
    var minL = cap * 2;
    var avail = math.pi * 2 - n * gapA;
    if (avail < n * minL) {
      // Very many small ones: we shrink proportionally, the gaps stay equal
      final k = (math.pi * 2) / (n * (gapA + minL));
      gapA *= k;
      minL *= k;
      avail = math.pi * 2 - n * gapA;
    }
    // Distribution with a minimum: those that fall short of a drop get a drop, the others share the rest
    final lengths = List<double>.filled(n, 0);
    final fixed = List<bool>.filled(n, false);
    while (true) {
      final rest = avail - fixed.where((f) => f).length * minL;
      final sum = [for (int j = 0; j < n; j++) if (!fixed[j]) values[idx[j]]].fold<int>(0, (a, b) => a + b);
      var changed = false;
      for (int j = 0; j < n; j++) {
        if (fixed[j]) continue;
        final l = sum > 0 ? rest * values[idx[j]] / sum : minL;
        if (l < minL) {
          fixed[j] = true;
          changed = true;
        }
      }
      if (!changed) {
        for (int j = 0; j < n; j++) {
          lengths[j] = fixed[j] ? minL : (sum > 0 ? rest * values[idx[j]] / sum : minL);
        }
        break;
      }
    }
    final starts = <double>[];
    var at = top + gapA / 2;
    for (int j = 0; j < n; j++) {
      starts.add(at);
      at += lengths[j] + gapA;
    }
    return HikkaDonutLayout._(idx, starts, lengths, cap, gapA);
  }

  /// The index of the value at angle [angle] (a gap belongs half to each neighbor); `null` means empty
  int? hit(double angle) {
    if (indices.isEmpty) return null;
    if (indices.length == 1) return indices.first;
    var a = (angle - top) % (math.pi * 2);
    for (int j = 0; j < indices.length; j++) {
      final from = (starts[j] - gapAngle / 2 - top) % (math.pi * 2);
      final to = from + lengths[j] + gapAngle;
      if (a >= from && a < to) return indices[j];
      if (a + math.pi * 2 >= from && a + math.pi * 2 < to) return indices[j];
    }
    return indices.last;
  }
}

/// A status donut chart: arcs with rounded ends and equal gaps, the total count in the center.
/// A tap on an arc gives [onTap] its index, on the center `null`.
class HikkaStatusDonut extends StatelessWidget {
  final double size;
  final double scale;
  final List<int> values;
  final List<Color> colors;
  final List<String> labels;
  final int total;
  final void Function(int? index)? onTap;

  const HikkaStatusDonut({
    super.key,
    required this.size,
    required this.scale,
    required this.values,
    required this.colors,
    required this.labels,
    required this.total,
    this.onTap,
  });

  double get thickness => size * 0.1;

  HikkaDonutLayout get layout => HikkaDonutLayout.compute(values, radius: (size - thickness) / 2, thickness: thickness, gap: thickness * 0.8);

  /// What is under point [p] (relative to the top-left corner): `-1` is the center, an arc index, `null` is outside
  int? hitAt(Offset p) {
    final c = Offset(size / 2, size / 2);
    final d = (p - c).distance;
    final r = (size - thickness) / 2;
    if (d <= r - thickness * 1.5) return -1;
    if (d > size / 2 + thickness) return null;
    final angle = math.atan2(p.dy - c.dy, p.dx - c.dx);
    return layout.hit(angle);
  }

  @override
  Widget build(BuildContext context) {
    final l = layout;
    final body = SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(size: Size.square(size), painter: _DonutPainter(layout: l, colors: colors, track: uiTheme.bgElevated, thickness: thickness)),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(HikkaText.count(total), maxLines: 1, style: hikkaStyle(size * 0.2, weight: FontWeight.bold, height: 1.1)),
              Text('Всього', style: hikkaStyle(11.5 * scale, color: uiTheme.textMuted)),
            ],
          ),
        ],
      ),
    );
    final tap = onTap;
    return Semantics(
      label: [
        'Всього: $total',
        for (int i = 0; i < values.length; i++) '${labels[i]}: ${values[i]}',
      ].join(', '),
      button: tap != null,
      excludeSemantics: true,
      child: tap == null
          ? body
          : MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (e) {
                  final h = hitAt(e.localPosition);
                  if (h == null) return;
                  tap(h == -1 ? null : h);
                },
                child: body,
              ),
            ),
    );
  }
}

/// Draws a [HikkaDonutLayout]: the track, arcs with rounded ends, "drops" for the smallest
class _DonutPainter extends CustomPainter {
  final HikkaDonutLayout layout;
  final List<Color> colors;
  final Color track;
  final double thickness;

  _DonutPainter({required this.layout, required this.colors, required this.track, required this.thickness});

  @override
  void paint(Canvas canvas, Size size) {
    final r = (size.width - thickness) / 2;
    final c = Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromCircle(center: c, radius: r);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..isAntiAlias = true;
    canvas.drawCircle(c, r, paint..color = track);
    final l = layout;
    if (l.indices.isEmpty) return;
    if (l.indices.length == 1) {
      canvas.drawCircle(c, r, paint..color = colors[l.indices.first]);
      return;
    }
    paint.strokeCap = StrokeCap.round;
    for (int j = 0; j < l.indices.length; j++) {
      final color = colors[l.indices[j]];
      final sweep = l.lengths[j] - l.cap * 2;
      if (sweep <= 0.0005) {
        // A drop: a circle with the diameter of the line thickness
        final a = l.starts[j] + l.lengths[j] / 2;
        canvas.drawCircle(c + Offset(math.cos(a), math.sin(a)) * r, thickness / 2, Paint()..color = color..isAntiAlias = true);
      } else {
        canvas.drawArc(rect, l.starts[j] + l.cap, sweep, false, paint..color = color);
      }
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.layout.lengths.join(',') != layout.lengths.join(',') ||
      old.layout.indices.join(',') != layout.indices.join(',') ||
      old.track != track ||
      old.thickness != thickness ||
      old.colors.join(',') != colors.join(',');
}

// ── Activity ───────────────────────────────────────────────────────────────

class _ActivityCard extends StatelessWidget {
  final String username;
  final HikkaUserStats stats;
  final double scale;
  final String token;

  const _ActivityCard({required this.username, required this.stats, required this.scale, required this.token});

  @override
  Widget build(BuildContext context) {
    Widget counter(String label, int n) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(HikkaText.count(n), style: hikkaStyle(16 * scale, weight: FontWeight.bold)),
              SizedBox(height: 2 * scale),
              Text(label, style: hikkaStyle(11.5 * scale, color: uiTheme.textMuted)),
            ],
          ),
        );
    return AppCard(
      scale: scale,
      radius: 14,
      padding: EdgeInsets.all(12 * scale),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HikkaAsync<List<HikkaActivityDay>>(
            key: ValueKey('activity-$username-$token'),
            scale: scale,
            compactError: true,
            load: () => HikkaApi.instance.userActivity(username),
            loading: (context) => HikkaLoading(scale: scale, height: 7 * 14 * scale),
            builder: (context, days) => days.isEmpty ? const SizedBox.shrink() : HikkaActivityHeatmap(days: days, scale: scale),
          ),
          SizedBox(height: 14 * scale),
          Row(
            children: [
              counter('Коментарі', stats.comments),
              counter('Відгуки', stats.reviews),
              counter('Правки', stats.edits),
            ],
          ),
        ],
      ),
    );
  }
}

/// A heat map of actions per day (weeks are columns, Mon…Sun are rows). Fits as many recent weeks as
/// fit the width; a tap or hover on a day shows the number of actions.
class HikkaActivityHeatmap extends StatefulWidget {
  final List<HikkaActivityDay> days;
  final double scale;

  const HikkaActivityHeatmap({super.key, required this.days, required this.scale});

  /// Brightness level 0…4 relative to the most active day
  static int level(int actions, int max) => actions <= 0 || max <= 0 ? 0 : math.max(1, (4 * actions / max).ceil()).clamp(1, 4);

  @override
  State<HikkaActivityHeatmap> createState() => _HikkaActivityHeatmapState();
}

class _HikkaActivityHeatmapState extends State<HikkaActivityHeatmap> {
  HikkaActivityDay? _picked;

  double get _scale => widget.scale;

  static Color colorOf(int level) => level == 0
      ? uiTheme.bgElevated
      : uiTheme.accentColor.withValues(alpha: const [0.0, 0.3, 0.5, 0.75, 1.0][level]);

  @override
  Widget build(BuildContext context) {
    final scale = _scale;
    final days = widget.days;
    final max = days.fold<int>(0, (m, d) => math.max(m, d.actions));
    final total = days.fold<int>(0, (s, d) => s + d.actions);
    final gap = 3 * scale;
    final last = days.last.day;
    // The Monday of the week with the last day is the start of the last column
    final lastWeek = last.subtract(Duration(days: last.weekday - 1));
    final byDay = {for (final d in days) d.day: d};
    final picked = _picked;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(builder: (context, c) {
          final minCell = AppPlatform.isMobile ? 10.0 : 11 * scale;
          final cols = math.max(1, math.min(53, ((c.maxWidth + gap) / (minCell + gap)).floor()));
          final cell = math.min(22 * scale, (c.maxWidth - gap * (cols - 1)) / cols);
          final width = cell * cols + gap * (cols - 1);
          final height = cell * 7 + gap * 6;
          HikkaActivityDay? at(Offset p) {
            final col = (p.dx / (cell + gap)).floor();
            final row = (p.dy / (cell + gap)).floor();
            if (col < 0 || col >= cols || row < 0 || row > 6) return null;
            final day = lastWeek.subtract(Duration(days: 7 * (cols - 1 - col))).add(Duration(days: row));
            return byDay[day];
          }

          void pick(Offset p) {
            final d = at(p);
            if (d != _picked) setState(() => _picked = d);
          }

          return Align(
            alignment: Alignment.centerRight,
            child: MouseRegion(
              onHover: (e) => pick(e.localPosition),
              onExit: (_) => setState(() => _picked = null),
              child: GestureDetector(
                onTapDown: (e) => pick(e.localPosition),
                child: CustomPaint(
                  size: Size(width, height),
                  painter: _HeatmapPainter(
                    cols: cols,
                    cell: cell,
                    gap: gap,
                    radius: 2.5 * scale,
                    lastWeek: lastWeek,
                    byDay: byDay,
                    max: max,
                    picked: picked?.day,
                    pickedColor: uiTheme.textPrimary,
                  ),
                ),
              ),
            ),
          );
        }),
        SizedBox(height: 10 * scale),
        Row(
          children: [
            Expanded(
              child: Text(
                picked != null
                    ? '${HikkaText.dayMonth(picked.day, now: AppClock.now())}: ${HikkaText.count(picked.actions)} ${HikkaText.plural(picked.actions, 'дія', 'дії', 'дій')}'
                    : '${HikkaText.count(total)} ${HikkaText.plural(total, 'дія', 'дії', 'дій')} за рік',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: hikkaStyle(12 * scale, color: uiTheme.textMuted),
              ),
            ),
            Text('Менше', style: hikkaStyle(11 * scale, color: uiTheme.textDarkMuted)),
            SizedBox(width: 5 * scale),
            for (int l = 0; l <= 4; l++)
              Container(
                width: 10 * scale,
                height: 10 * scale,
                margin: EdgeInsets.only(right: 3 * scale),
                decoration: BoxDecoration(color: colorOf(l), borderRadius: BorderRadius.circular(2.5 * scale)),
              ),
            SizedBox(width: 2 * scale),
            Text('Більше', style: hikkaStyle(11 * scale, color: uiTheme.textDarkMuted)),
          ],
        ),
      ],
    );
  }
}

class _HeatmapPainter extends CustomPainter {
  final int cols;
  final double cell;
  final double gap;
  final double radius;
  final DateTime lastWeek;
  final Map<DateTime, HikkaActivityDay> byDay;
  final int max;
  final DateTime? picked;
  final Color pickedColor;

  _HeatmapPainter({
    required this.cols,
    required this.cell,
    required this.gap,
    required this.radius,
    required this.lastWeek,
    required this.byDay,
    required this.max,
    required this.picked,
    required this.pickedColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (int col = 0; col < cols; col++) {
      final monday = lastWeek.subtract(Duration(days: 7 * (cols - 1 - col)));
      for (int row = 0; row < 7; row++) {
        final day = monday.add(Duration(days: row));
        final d = byDay[day];
        if (d == null) continue; // outside the year or not yet arrived
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(col * (cell + gap), row * (cell + gap), cell, cell),
          Radius.circular(radius),
        );
        paint
          ..style = PaintingStyle.fill
          ..color = _HikkaActivityHeatmapState.colorOf(HikkaActivityHeatmap.level(d.actions, max));
        canvas.drawRRect(rect, paint);
        if (picked == day) {
          paint
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = pickedColor;
          canvas.drawRRect(rect, paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_HeatmapPainter old) =>
      old.cols != cols || old.cell != cell || old.picked != picked || old.byDay != byDay || old.pickedColor != pickedColor;
}

// ── Author's articles and collections ─────────────────────────────────────────

class _AuthoredList<T> extends StatelessWidget {
  final double scale;
  final double pad;
  final String title;
  final Future<HikkaPage<T>> Function() load;
  final Widget Function(T item) itemBuilder;

  const _AuthoredList({super.key, required this.scale, required this.pad, required this.title, required this.load, required this.itemBuilder});

  @override
  Widget build(BuildContext context) {
    return HikkaAsync<HikkaPage<T>>(
      scale: scale,
      compactError: true,
      load: load,
      // A failure or empty: the block is simply not shown, it is not the main thing on the page
      loading: (context) => const SizedBox.shrink(),
      stateFrame: (context, child) => const SizedBox.shrink(),
      builder: (context, page) {
        if (page.items.isEmpty) return const SizedBox.shrink();
        return HikkaSection(
          scale: scale,
          pad: pad,
          title: title,
          subtitle: HikkaText.count(page.total),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: hikkaReadableWidth(scale)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (int i = 0; i < page.items.length; i++) ...[
                  if (i > 0) SizedBox(height: 10 * scale),
                  itemBuilder(page.items[i]),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── History ──────────────────────────────────────────────────────────────────

/// "Історія": list changes by day ("Сьогодні", "11 листопада, середа"), a "Показати ще" button
class HikkaHistoryList extends StatefulWidget {
  final String username;
  final double scale;

  /// Entries per request page
  final int pageSize;

  const HikkaHistoryList({super.key, required this.username, required this.scale, this.pageSize = 10});

  @override
  State<HikkaHistoryList> createState() => _HikkaHistoryListState();
}

class _HikkaHistoryListState extends State<HikkaHistoryList> {
  final List<HikkaHistoryEntry> _items = [];
  int _page = 0;
  int _pages = 1;
  bool _loading = false;
  Object? _error;

  double get _scale => widget.scale;

  @override
  void initState() {
    super.initState();
    _more();
  }

  Future<void> _more() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // A page with only manga gives empty: we take the next one so "Показати ще" shows something
      var added = 0;
      while (added == 0 && _page < _pages) {
        final p = await HikkaApi.instance.userHistory(widget.username, page: _page + 1, size: widget.pageSize);
        if (!mounted) return;
        _page = p.page;
        _pages = p.pages;
        final known = {for (final e in _items) e.reference};
        for (final e in p.items) {
          if (known.add(e.reference)) {
            _items.add(e);
            added++;
          }
        }
        if (p.items.isEmpty && p.page >= p.pages) break;
      }
    } catch (e) {
      if (!mounted) return;
      _error = e;
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final scale = _scale;
    if (_items.isEmpty) {
      if (_error != null) return HikkaErrorView(scale: scale, error: _error!, compact: true, onRetry: _more);
      if (_loading) return HikkaLoading(scale: scale);
      return Text('Історія порожня', style: hikkaStyle(13 * scale, color: uiTheme.textMuted));
    }
    final now = AppClock.now();
    final lang = HikkaPrefs.instance.titleLang;
    final rows = <Widget>[];
    String? day;
    for (final e in _items) {
      final label = HikkaProfileText.historyDay(e.when, now);
      if (label != day) {
        day = label;
        rows.add(Padding(
          padding: EdgeInsets.only(top: rows.isEmpty ? 0 : 14 * scale, bottom: 6 * scale),
          child: Text(label, style: hikkaStyle(12.5 * scale, weight: FontWeight.bold, color: uiTheme.textSecondary)),
        ));
      }
      rows.add(_HistoryRow(entry: e, scale: scale, title: e.anime!.title(lang)));
    }
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: hikkaReadableWidth(scale)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...rows,
          if (_page < _pages) ...[
            SizedBox(height: 10 * scale),
            AppSecondaryButton(
              scale: scale,
              icon: _loading ? Symbols.hourglass_top_rounded : Symbols.expand_more_rounded,
              label: _error != null ? 'Повторити' : 'Показати ще',
              onTap: () => unawaited(_more()),
            ),
          ],
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final HikkaHistoryEntry entry;
  final double scale;
  final String title;

  const _HistoryRow({required this.entry, required this.scale, required this.title});

  @override
  Widget build(BuildContext context) {
    final a = entry.anime!;
    final what = entry.describe();
    final time = HikkaText.hhmm(entry.when);
    return Semantics(
      button: true,
      label: '$title. $what. $time',
      excludeSemantics: true,
      child: InkWell(
        onTap: () => HikkaNav.instance.openAnime(a.slug, seed: a),
        borderRadius: uiTheme.borderRadius(10 * scale),
        splashColor: Colors.transparent,
        highlightColor: uiTheme.touchHighlight,
        hoverColor: uiTheme.hoverOverlay,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 5 * scale, horizontal: 4 * scale),
          child: Row(
            children: [
              SizedBox(width: 40 * scale, child: HikkaPoster(url: a.image, malId: a.malId, scale: scale, radius: 6)),
              SizedBox(width: 12 * scale),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: hikkaStyle(13.5 * scale, weight: FontWeight.w600)),
                    SizedBox(height: 3 * scale),
                    Text(what, maxLines: 2, overflow: TextOverflow.ellipsis, style: hikkaStyle(12 * scale, color: uiTheme.textMuted, height: 1.3)),
                  ],
                ),
              ),
              SizedBox(width: 10 * scale),
              Text(time, style: hikkaStyle(11.5 * scale, color: uiTheme.textDarkMuted)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Another user's profile page ──────────────────────────────────────────────────

/// Another user's profile over a tab (`HikkaNav.openUser`)
class HikkaUserPage extends StatefulWidget {
  final HikkaRoute route;
  final double scale;
  final double bottomInset;

  const HikkaUserPage({super.key, required this.route, required this.scale, this.bottomInset = 0});

  @override
  State<HikkaUserPage> createState() => _HikkaUserPageState();
}

class _HikkaUserPageState extends State<HikkaUserPage> {
  late final ScrollController _scroll = AppSmoothScrollController(initialScrollOffset: widget.route.scroll);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_saveScroll);
  }

  void _saveScroll() {
    if (_scroll.hasClients) widget.route.scroll = _scroll.offset;
  }

  @override
  void dispose() {
    _scroll.removeListener(_saveScroll);
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final seed = widget.route.seed;
    return HikkaPageFrame(
      scale: widget.scale,
      controller: _scroll,
      bottomInset: widget.bottomInset,
      children: [
        HikkaUserProfile(username: widget.route.slug, seed: seed is HikkaUser ? seed : null, scale: widget.scale),
      ],
    );
  }
}
