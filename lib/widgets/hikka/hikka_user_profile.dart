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
import '../app_tones.dart';
import '../app_ui_kit.dart';
import '../design_kit.dart';
import '../line_icons.dart';
import 'hikka_cards.dart';
import 'hikka_common.dart';
import 'hikka_community_cards.dart';
import 'hikka_my_list_bar.dart' show hikkaStatusColor, HikkaListMark;
import 'hikka_page_kit.dart';
import 'hikka_shelf.dart';
import '../../utils/app_clock.dart';

/// A Hikka user profile: the account block (avatar, name, role, followers, description and links), "Список" (a bar of
/// the statuses, a row per status, watch time), [extra], a year of "Активність", favorite anime and characters,
/// articles, collections and "Історія". Returns the page blocks, to be put in [HikkaPageFrame].
///
/// [own] is one's own profile: the status counters and "Усі" in favorites lead to the "Списки" tab.
class HikkaUserProfile extends StatefulWidget {
  final String username;
  final HikkaUser? seed;
  final double scale;
  final bool own;

  /// Another value means load everything anew (page refresh)
  final Object? reloadKey;

  /// Blocks right after "Список" (one's own profile: "Застосунок" and "Акаунт")
  final List<Widget> extra;

  const HikkaUserProfile({super.key, required this.username, required this.scale, this.seed, this.own = false, this.reloadKey, this.extra = const []});

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
    final inset = pad + 2 * scale;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HikkaProfileHeader(user: user, follow: core?.follow, scale: scale, pad: pad),
        if (core != null) ...[
          AppGroupCaption(scale: scale, text: 'Список', inset: inset),
          HikkaListSummary(stats: core.watch, scale: scale, inset: inset, onStatus: widget.own ? (s) => HikkaNav.instance.openLists(status: s) : null),
          ...widget.extra,
          SizedBox(height: 22 * scale),
          _ActivityCard(username: name, stats: core.stats, scale: scale, pad: pad, token: token),
          if (core.stats.favouriteAnime > 0)
            HikkaShelfAsync<HikkaAnime>(
              scale: scale,
              pad: pad,
              title: 'Улюблені аніме',
              subtitle: '${HikkaText.count(core.stats.favouriteAnime)} ${HikkaText.plural(core.stats.favouriteAnime, 'тайтл', 'тайтли', 'тайтлів')}',
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
              subtitle: '${HikkaText.count(core.stats.favouriteCharacters)} ${HikkaText.plural(core.stats.favouriteCharacters, 'персонаж', 'персонажі', 'персонажів')}',
              token: '$name-$token',
              load: () async => (await _api.favouriteCharacters(name, size: 20)).items,
              itemBuilder: (context, c) => HikkaCharacterCard(character: c, scale: scale),
            ),
          _AuthoredList<HikkaArticle>(
            key: ValueKey('articles-$name-$token'),
            scale: scale,
            pad: pad,
            title: 'Статті',
            words: const ('стаття', 'статті', 'статей'),
            load: () => _api.articles(author: name, size: 3),
            itemBuilder: (a) => HikkaArticleRow(article: a, scale: scale, pad: pad),
          ),
          _AuthoredList<HikkaCollection>(
            key: ValueKey('collections-$name-$token'),
            scale: scale,
            pad: pad,
            title: 'Колекції',
            words: const ('колекція', 'колекції', 'колекцій'),
            load: () => _api.collections(author: name, sort: 'new', size: 3, contentType: null, allowAdult: adult),
            itemBuilder: (c) => HikkaCollectionRow(collection: c, scale: scale, pad: pad),
          ),
          HikkaSection(
            scale: scale,
            pad: pad,
            title: 'Історія',
            titleSize: 15,
            child: HikkaHistoryList(key: ValueKey('history-$name-$token'), username: name, scale: scale),
          ),
        ] else if (_error != null) ...[
          SizedBox(height: 22 * scale),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: pad),
            child: HikkaErrorView(scale: scale, error: _error!, compact: true, onRetry: () => setState(() {
                  _error = null;
                  _load();
                })),
          ),
          ...widget.extra,
        ] else ...[
          Padding(padding: EdgeInsets.symmetric(vertical: 24 * scale), child: HikkaLoading(scale: scale)),
          ...widget.extra,
        ],
      ],
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────────

/// The account block: a round avatar (or the first letter on a gradient), the name with a grey role plate,
/// "На Hikka з …" and the followers; the description and links under it, when the person has them
class HikkaProfileHeader extends StatelessWidget {
  final HikkaUser user;
  final HikkaFollowStats? follow;
  final double scale;
  final double pad;

  const HikkaProfileHeader({super.key, required this.user, required this.scale, required this.pad, this.follow});

  @override
  Widget build(BuildContext context) {
    final avatar = 62 * scale;
    final role = user.roleLabel;
    final f = follow;
    final since = user.created > 0 ? DateTime.fromMillisecondsSinceEpoch(user.created * 1000) : null;
    final bright = uiTheme.isLight ? uiTheme.textPrimary : const Color(0xFFDDDDDD);
    final grey = hikkaStyle(12.5 * scale, color: uiTheme.textMuted);
    final initial = user.username.isEmpty ? '?' : user.username.characters.first.toUpperCase();
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 8 * scale, pad, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox.square(
                dimension: avatar,
                child: ClipOval(
                  child: user.avatar.isEmpty
                      ? DecoratedBox(
                          decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFC9607A), Color(0xFF6A4AD0)])),
                          child: Center(child: Text(initial, style: hikkaStyle(24 * scale, weight: FontWeight.bold, color: Colors.white))),
                        )
                      : HikkaPoster(url: user.avatar, scale: scale, aspect: 1, radius: 0, border: false, icon: Symbols.person_rounded, alignment: Alignment.center),
                ),
              ),
              SizedBox(width: 14 * scale),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8 * scale,
                      runSpacing: 4 * scale,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(user.username, style: hikkaStyle(20 * scale, weight: FontWeight.bold)),
                        if (role != null)
                          Container(
                            height: 22 * scale,
                            padding: EdgeInsets.symmetric(horizontal: 8 * scale),
                            decoration: BoxDecoration(color: AppTones.plate, borderRadius: uiTheme.borderRadius(7 * scale)),
                            child: Center(widthFactor: 1, child: Text(role, style: hikkaStyle(11.5 * scale, color: AppTones.plateText))),
                          ),
                      ],
                    ),
                    if (since != null) ...[
                      SizedBox(height: 4 * scale),
                      Text('На Hikka з ${HikkaText.monthsGenitive[since.month - 1]} ${since.year}', style: grey),
                    ],
                    if (f != null) ...[
                      SizedBox(height: 2 * scale),
                      Text.rich(
                        TextSpan(
                          style: grey,
                          children: [
                            TextSpan(text: HikkaText.count(f.followers), style: TextStyle(color: bright, fontWeight: FontWeight.bold)),
                            TextSpan(text: ' ${HikkaText.plural(f.followers, 'стежить', 'стежать', 'стежать')} · '),
                            TextSpan(text: HikkaText.count(f.following), style: TextStyle(color: bright, fontWeight: FontWeight.bold)),
                            const TextSpan(text: ' відстежує'),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (user.description != null && user.description!.trim().isNotEmpty) ...[
            SizedBox(height: 12 * scale),
            Text(user.description!, style: hikkaStyle(13.5 * scale, color: uiTheme.textSecondary, height: 1.4)),
          ],
          if (user.links.isNotEmpty) ...[
            SizedBox(height: 12 * scale),
            Wrap(
              spacing: 8 * scale,
              runSpacing: 8 * scale,
              children: [
                for (final l in user.links)
                  AppPlate(
                    scale: scale,
                    label: l.label,
                    height: 34,
                    leading: (c) => LineIconView(l.icon == 'telegram' ? LineIcon.send : LineIcon.link, size: 16 * scale, color: c),
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

/// "Список": a bar of the statuses' shares, then a row per status with its glyph and number and "Час перегляду".
/// [onStatus] is a tap on a status row (one's own profile opens "Списки" there).
class HikkaListSummary extends StatelessWidget {
  final HikkaWatchStats stats;
  final double scale;
  final double inset;
  final void Function(HikkaWatchStatus status)? onStatus;

  const HikkaListSummary({super.key, required this.stats, required this.scale, required this.inset, this.onStatus});

  @override
  Widget build(BuildContext context) {
    final total = stats.total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(inset, 6 * scale, inset, 4 * scale),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4 * scale),
            child: SizedBox(
              key: const ValueKey('list-bar'),
              height: 8 * scale,
              child: total <= 0
                  ? ColoredBox(color: AppTones.track)
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final s in HikkaWatchStatus.values)
                          if (stats.of(s) > 0) Expanded(flex: stats.of(s), child: ColoredBox(color: hikkaStatusColor(s))),
                      ],
                    ),
            ),
          ),
        ),
        for (final s in HikkaWatchStatus.values)
          AppLineRow(
            key: ValueKey('list-row-${s.name}'),
            scale: scale,
            inset: inset,
            leading: HikkaListMark(status: s, size: 20 * scale, color: AppTones.rowIcon),
            title: s.label,
            value: HikkaText.count(stats.of(s)),
            onTap: onStatus == null ? null : () => onStatus!(s),
          ),
        AppLineRow(scale: scale, inset: inset, icon: LineIcon.clock, title: 'Час перегляду', value: HikkaProfileText.watchTime(stats.duration)),
      ],
    );
  }
}

// ── Activity ───────────────────────────────────────────────────────────────

/// "Активність": the heading with the year's total in grey, the day map without a frame, three numbers under it
class _ActivityCard extends StatelessWidget {
  final String username;
  final HikkaUserStats stats;
  final double scale;
  final double pad;
  final String token;

  const _ActivityCard({required this.username, required this.stats, required this.scale, required this.pad, required this.token});

  @override
  Widget build(BuildContext context) {
    Widget counter(int n, String one, String few, String many) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(HikkaText.count(n), style: hikkaStyle(17 * scale, weight: FontWeight.bold)),
              SizedBox(height: 2 * scale),
              Text(HikkaText.plural(n, one, few, many), style: hikkaStyle(12 * scale, color: uiTheme.textMuted)),
            ],
          ),
        );
    Widget heading(String? total) => AppSectionHeader(scale: scale, title: 'Активність', subtitle: total, titleSize: 15, calm: true);
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 0, pad, 22 * scale),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: hikkaReadableWidth(scale)),
        child: HikkaAsync<List<HikkaActivityDay>>(
          key: ValueKey('activity-$username-$token'),
          scale: scale,
          compactError: true,
          load: () => HikkaApi.instance.userActivity(username),
          loading: (context) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [heading(null), SizedBox(height: 10 * scale), HikkaLoading(scale: scale, height: 7 * 14 * scale)],
          ),
          builder: (context, days) {
            final total = days.fold<int>(0, (s, d) => s + d.actions);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                heading(days.isEmpty ? null : '${HikkaText.count(total)} ${HikkaText.plural(total, 'дія', 'дії', 'дій')} за рік'),
                SizedBox(height: 10 * scale),
                if (days.isNotEmpty) HikkaActivityHeatmap(days: days, scale: scale),
                SizedBox(height: 14 * scale),
                Row(
                  children: [
                    counter(stats.comments, 'коментар', 'коментарі', 'коментарів'),
                    counter(stats.reviews, 'відгук', 'відгуки', 'відгуків'),
                    counter(stats.edits, 'правка', 'правки', 'правок'),
                  ],
                ),
              ],
            );
          },
        ),
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
      ? AppTones.plate
      : uiTheme.accentColor.withValues(alpha: const [0.0, 0.25, 0.45, 0.7, 1.0][level]);

  @override
  Widget build(BuildContext context) {
    final scale = _scale;
    final days = widget.days;
    final max = days.fold<int>(0, (m, d) => math.max(m, d.actions));
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
                picked != null ? '${HikkaText.dayMonth(picked.day, now: AppClock.now())}: ${HikkaText.count(picked.actions)} ${HikkaText.plural(picked.actions, 'дія', 'дії', 'дій')}' : '',
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

  /// "стаття / статті / статей" for the grey count under the heading
  final (String, String, String) words;
  final Future<HikkaPage<T>> Function() load;
  final Widget Function(T item) itemBuilder;

  const _AuthoredList({super.key, required this.scale, required this.pad, required this.title, required this.words, required this.load, required this.itemBuilder});

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
        final n = page.total;
        return Padding(
          padding: EdgeInsets.only(bottom: 16 * scale),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: pad),
                child: AppSectionHeader(scale: scale, title: title, subtitle: '${HikkaText.count(n)} ${HikkaText.plural(n, words.$1, words.$2, words.$3)}', titleSize: 15, calm: true),
              ),
              SizedBox(height: 2 * scale),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: hikkaReadableWidth(scale) + pad * 2),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [for (final item in page.items) itemBuilder(item)]),
              ),
            ],
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
          padding: EdgeInsets.only(top: rows.isEmpty ? 0 : 14 * scale, bottom: 4 * scale),
          child: Text(label, style: hikkaStyle(13 * scale, weight: FontWeight.w700, color: AppTones.caption)),
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
              SizedBox(width: 40 * scale, child: HikkaPoster(url: a.image, malId: a.malId, scale: scale, radius: 7, aspect: 40 / 56)),
              SizedBox(width: 12 * scale),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: hikkaStyle(14.5 * scale)),
                    SizedBox(height: 3 * scale),
                    Text(what, maxLines: 2, overflow: TextOverflow.ellipsis, style: hikkaStyle(12.5 * scale, color: AppTones.rowSub, height: 1.3)),
                  ],
                ),
              ),
              SizedBox(width: 10 * scale),
              Text(time, style: hikkaStyle(12 * scale, color: uiTheme.textMuted)),
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
