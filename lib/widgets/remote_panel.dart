import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../models/hikka_models.dart' show HikkaText;
import '../models/source_models.dart';
import '../services/downloads/download_manager.dart';
import '../services/downloads/download_models.dart';
import '../services/episode_check.dart';
import '../services/episode_guide.dart';
import '../services/hikka_images.dart';
import '../services/remote_driver.dart';
import '../services/sources/episode_naming.dart' show siteEpisodeTitle;
import '../services/ui_theme_service.dart';
import '../services/watch_models.dart';
import '../utils/formatters.dart';
import '../utils/platform_info.dart';
import 'app_animation_kit.dart';
import 'app_tones.dart';
import 'app_ui_kit.dart';
import 'design_kit.dart';
import 'line_icons.dart';
import 'player_kit.dart';
import 'settings_drawer.dart' show SettingsDrawer;
import 'watch_callout.dart';

enum _Page { main, voices, quality, player, episode }

/// How the episodes are shown: rows with TheMovieDB's stills, rows of titles when there are no stills, plates when
/// there are no titles either (a list of «Серія 14» says nothing the plates do not)
enum _Rows { stills, titles, plates }

/// The "Перегляд" panel of site episodes: the dub as a row, the episodes as a list (the still with the number, the
/// title — Ukrainian from TheMovieDB or the site, else MyAnimeList's English — the air date and length; watched ones
/// dimmed with a check mark, the current one lighter with its progress; a long series in ranges of [episodeRange]),
/// then the quality and the site's player. Titles and stills come from `EpisodeGuideService` by MyAnimeList's numbers
/// (`RemoteDriver.malNumbers`); without stills the rows are text only, without titles the episodes are plates. Choices
/// open as pages inside the panel and switch on the fly, from the same place. Holding a row (on a PC, the right button)
/// opens the episode's details — the still, titles, description, «Дивитися» and the watched mark — as a card over the
/// list on a phone held upright, as a page of the panel in a side panel; holding a plate marks it watched or not. While
/// the titles are on their way the rows are grey placeholders. The file queue is not here: site episodes are not
/// files, so nothing is added, removed or reordered.
class RemotePanelBody extends StatefulWidget {
  final double scale;
  final RemoteDriver driver;

  /// Phone: taller rows and plates for touch, a 48 dp header
  final bool sheet;
  final ValueChanged<int> onEpisodeSelected;

  /// The close button of the header (the panel draws its own header: its pages have their own titles)
  final VoidCallback? onClose;

  /// false: the main page has no "Перегляд" header (the panel is part of a page that names the title itself); inner
  /// pages keep theirs
  final bool header;

  /// A block at the top of the main page, scrolling with the episodes (the title and its description)
  final Widget? lead;

  const RemotePanelBody({
    super.key,
    required this.scale,
    required this.driver,
    required this.onEpisodeSelected,
    this.sheet = false,
    this.onClose,
    this.header = true,
    this.lead,
  });

  /// How many plates one range shows: a long series (One Piece) never builds a thousand of them
  static const int episodeRange = 100;

  /// Plates in a row (without titles)
  static const int columns = 7;

  @override
  State<RemotePanelBody> createState() => _RemotePanelBodyState();
}

class _RemotePanelBodyState extends State<RemotePanelBody> {
  final ScrollController _scroll = AppSmoothScrollController();
  final GlobalKey _currentKey = GlobalKey();
  final GlobalKey _topKey = GlobalKey();
  _Page _page = _Page.main;

  /// The chosen range of a long series (null: the one with the current episode)
  int? _range;
  int _shownIndex = -1;

  /// The titles and stills of the range shown ([_guideKey]: which numbers they are for; [_loading]: still asked for)
  EpisodeGuide? _guide;
  String? _guideKey;
  bool _loading = false;

  /// How the shown range is drawn, its episodes, the height of a row (rows are built as they come into view, so the
  /// current one's place is counted from it)
  _Rows _rows = _Rows.plates;

  /// The title whose episodes came without titles: while another range loads, its plates stay plates
  String? _platesOf;
  int _from = 0;
  int _to = 0;
  double _extent = 0;

  /// The episode whose details are open (holding its row; on a PC, the right button), its number as shown, and where
  /// the list was (it comes back there)
  _Episode? _detail;
  String _detailLabel = '';
  double _detailFrom = 0;
  bool _asCard = false;

  double get _s => widget.scale;
  double get _pad => (widget.sheet ? 20 : 16) * _s;
  RemoteDriver get _d => widget.driver;

  @override
  void initState() {
    super.initState();
    _revealCurrent(first: true);
    // Downloaded episodes carry a mark on their plates
    DownloadManager.instance.addListener(_downloads);
    _d.panelBack = _stepBack;
  }

  /// The system Back / Esc: from the details or an inner page back to the list (false: at the list — the panel closes)
  bool _stepBack() {
    if (_detail != null || _page == _Page.episode) {
      _closeDetail();
      return true;
    }
    if (_page != _Page.main) {
      _back();
      return true;
    }
    return false;
  }

  void _downloads() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(RemotePanelBody old) {
    super.didUpdateWidget(old);
    if (old.driver != widget.driver) {
      if (old.driver.panelBack == _stepBack) old.driver.panelBack = null;
      widget.driver.panelBack = _stepBack;
    }
    if (_d.index != _shownIndex) {
      _range = null;
      _revealCurrent();
    }
  }

  @override
  void dispose() {
    if (_d.panelBack == _stepBack) _d.panelBack = null;
    DownloadManager.instance.removeListener(_downloads);
    _scroll.dispose();
    super.dispose();
  }

  /// The current episode comes into view (at once when the panel opens, smoothly when the episode changes)
  void _revealCurrent({bool first = false}) {
    _shownIndex = _d.index;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _page != _Page.main) return;
      final duration = first ? Duration.zero : AppAnim.medium;
      if (_rows == _Rows.plates) {
        final ctx = _currentKey.currentContext;
        if (ctx != null) Scrollable.ensureVisible(ctx, alignment: 0.4, duration: duration, curve: AppAnim.easeOut);
        return;
      }
      // Rows not in view are not built: the current one's place is counted (above it: the dub, the caption, the ranges)
      final k = _d.index - _from;
      if (!_scroll.hasClients || k < 0 || k >= _to - _from) return;
      final top = (_topKey.currentContext?.findRenderObject() as RenderBox?)?.size.height ?? 0;
      final pos = _scroll.position;
      final target = (top + k * _extent + _extent / 2 - pos.viewportDimension * 0.4).clamp(pos.minScrollExtent, pos.maxScrollExtent).toDouble();
      if (first) {
        pos.jumpTo(target);
      } else {
        unawaited(_scroll.animateTo(target, duration: duration, curve: AppAnim.easeOut));
      }
    });
  }

  void _open(_Page p) => setState(() => _page = p);

  void _back() {
    setState(() => _page = _Page.main);
    _revealCurrent(first: true);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.header || _page != _Page.main) _header(),
        Expanded(
          child: AppFadeSwitcher(
            duration: AppAnim.fast,
            child: KeyedSubtree(key: ValueKey(_page), child: _body()),
          ),
        ),
      ],
    );
  }

  // ── Header ──────────────────────────────────────────────────────────────────

  /// "Перегляд" with the anime's title under it; an inner page has its own title and a back arrow
  Widget _header() {
    final touch = widget.sheet;
    final s = _s;
    final String title;
    String? sub;
    switch (_page) {
      case _Page.main:
        title = 'Перегляд';
        sub = _d.session?.animeTitle;
      case _Page.voices:
        title = 'Озвучення й субтитри';
      case _Page.quality:
        title = 'Якість';
      case _Page.player:
        title = 'Плеєр';
      case _Page.episode:
        title = 'Серія $_detailLabel';
    }
    final inner = _page != _Page.main;
    return Container(
      constraints: BoxConstraints(minHeight: touch ? 64 : 52 * s),
      padding: EdgeInsets.fromLTRB(inner ? (touch ? 6 : 8 * s) : _pad, touch ? 8 : 8 * s, touch ? 6 : 8 * s, 4 * s),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          if (inner) _headerButton(LineIcon.back, 'Назад', _page == _Page.episode ? _closeDetail : _back, key: const ValueKey('watch-back')),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: playerText(touch ? 18 : 16 * s, weight: FontWeight.w700)),
                if (sub != null && sub.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.only(top: 2 * s),
                    child: Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: playerText(touch ? 12.5 : 12 * s, color: AppTones.rowSub)),
                  ),
              ],
            ),
          ),
          if (widget.onClose != null) _headerButton(LineIcon.close, 'Закрити', widget.onClose!),
        ],
      ),
    );
  }

  Widget _headerButton(LineIcon icon, String label, VoidCallback onTap, {Key? key}) {
    final double size = widget.sheet ? 48 : 36 * _s;
    return Semantics(
      button: true,
      label: label,
      child: Material(
        type: MaterialType.transparency,
        child: InkResponse(
          key: key,
          onTap: onTap,
          radius: size * 0.55,
          highlightColor: uiTheme.hoverOverlay,
          splashColor: uiTheme.hoverOverlay,
          child: SizedBox.square(
            dimension: size,
            child: Center(child: LineIconView(icon, size: (widget.sheet ? 22 : 19 * _s) * (icon == LineIcon.close ? 0.95 : 1), color: uiTheme.textSecondary)),
          ),
        ),
      ),
    );
  }

  Widget _body() {
    switch (_page) {
      case _Page.main:
        return _main();
      case _Page.voices:
        return _voices();
      case _Page.quality:
        return _qualities();
      case _Page.player:
        return _players();
      case _Page.episode:
        return _detailPage();
    }
  }

  Widget _list(List<Widget> children, {ScrollController? controller}) => ScrollConfiguration(
        behavior: const AppScrollBehavior().copyWith(scrollbars: false),
        child: ListView(
          controller: controller,
          padding: EdgeInsets.only(bottom: 12 * _s),
          children: children,
        ),
      );

  /// A grey caption over a group ("Серії", "Озвучення · 8")
  Widget _caption(String text, {double top = 12}) => Padding(
        padding: EdgeInsets.fromLTRB(_pad, top * _s, _pad, 8 * _s),
        child: Text(text, style: playerText(13 * _s, color: AppTones.caption, weight: FontWeight.w700)),
      );

  /// A grey hint over a page's list
  Widget _hint(String text) => Padding(
        padding: EdgeInsets.fromLTRB(_pad, 2 * _s, _pad, 6 * _s),
        child: Text(text, style: playerText(12.5 * _s, color: AppTones.rowSub, height: 1.35)),
      );

  // ── The main page ───────────────────────────────────────────────────────────

  Widget _main() {
    final d = _d;
    final s = d.session;
    if (s == null || s.entries.isEmpty) {
      return AppEmptyState(scale: _s, icon: Symbols.video_library_rounded, text: 'Серій немає');
    }
    final g = d.group;
    final groups = d.title?.groups ?? const <WatchGroup>[];
    final res = d.stream;
    final qualities = res?.qualities ?? const <Video>[];
    final hosters = res?.hosters ?? const <String>[];
    final total = s.entries.length;
    const size = RemotePanelBody.episodeRange;
    final ranges = (total + size - 1) ~/ size;
    final int range = (_range ?? (d.index ~/ size)).clamp(0, math.max(0, ranges - 1)).toInt();
    final from = ranges > 1 ? range * size : 0;
    final to = ranges > 1 ? math.min(total, from + size) : total;
    String label(int i) => episodeLabel(s.entries[i].episode, i);
    final rows = _rowsOf(s, from, to);
    final strip = ranges < 2
        ? null
        : Padding(
            padding: EdgeInsets.fromLTRB(_pad, 0, _pad, 10 * _s),
            child: AppRangeStrip(
              scale: _s,
              labels: [for (int r = 0; r < ranges; r++) '${label(r * size)}–${label(math.min(total, (r + 1) * size) - 1)}'],
              selected: range,
              onSelect: (r) => setState(() => _range = r),
            ),
          );
    final plates = _rows == _Rows.plates;
    final list = ScrollConfiguration(
      behavior: const AppScrollBehavior().copyWith(scrollbars: false),
      child: CustomScrollView(
        controller: _scroll,
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              key: _topKey,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.lead != null) widget.lead!,
                if (g != null) _variantRow(g, canPick: groups.length > 1),
                _caption('Серії'),
                // Over the rows the ranges belong to the top (the current row's place is counted under it); the plates
                // keep them in their own block
                if (strip != null && !plates) strip,
              ],
            ),
          ),
          KeyedSubtree(key: const ValueKey('watch-episodes'), child: _episodes(s, rows, strip: plates ? strip : null)),
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: 10 * _s),
                if (qualities.length > 1)
                  PlayerMenuRow(
                    key: const ValueKey('watch-quality'),
                    scale: _s,
                    sheet: widget.sheet,
                    icon: LineIcon.hd,
                    title: 'Якість',
                    value: d.video == null ? null : SettingsDrawer.qualityLabel(d.video!),
                    onTap: () => _open(_Page.quality),
                  ),
                if (hosters.isNotEmpty)
                  PlayerMenuRow(
                    key: const ValueKey('watch-player'),
                    scale: _s,
                    sheet: widget.sheet,
                    icon: LineIcon.monitor,
                    title: 'Плеєр',
                    value: res!.hoster,
                    chevron: hosters.length > 1,
                    dimWhenOff: false,
                    onTap: hosters.length > 1 ? () => _open(_Page.player) : null,
                  ),
                SizedBox(height: 12 * _s),
              ],
            ),
          ),
        ],
      ),
    );
    if (!widget.sheet) return list;
    // On a phone held upright the details are a card over the dimmed list (a tap on the list closes it)
    final detail = _asCard ? _detail : null;
    return Stack(
      children: [
        list,
        Positioned.fill(
          child: IgnorePointer(
            ignoring: detail == null,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _closeDetail,
              child: AnimatedOpacity(
                opacity: detail == null ? 0 : 1,
                duration: AppAnim.normal,
                curve: AppAnim.easeOut,
                child: ColoredBox(color: Colors.black.withValues(alpha: uiTheme.isLight ? 0.25 : 0.5)),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: AnimatedSwitcher(
            duration: AppAnim.normal,
            switchInCurve: AppAnim.easeOut,
            switchOutCurve: AppAnim.easeIn,
            transitionBuilder: (child, a) => FadeTransition(
              opacity: a,
              child: SlideTransition(position: Tween(begin: const Offset(0, 0.12), end: Offset.zero).animate(a), child: child),
            ),
            child: detail == null ? const SizedBox(width: double.infinity) : KeyedSubtree(key: ValueKey(detail.index), child: _detailCard(detail)),
          ),
        ),
      ],
    );
  }

  /// "оновлено 02.11" (the year only when it is not this one)
  static String _updated(DateTime d) {
    final now = DateTime.now();
    return 'оновлено ${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}${d.year != now.year ? '.${d.year}' : ''}';
  }

  /// "26 серпня" (the year only when it is not this one)
  static String _date(DateTime d) => '${d.day} ${HikkaText.monthsGenitive[d.month - 1]}${d.year != DateTime.now().year ? ' ${d.year}' : ''}';

  /// Which episodes a variant has: "28 з 28 серій" when it has all of them, else the ranges ("1–12 з 28", or
  /// "1–12 сер." while the total is unknown)
  String _episodesOf(WatchGroup g) {
    final total = _d.hikka?.total;
    final count = g.episodes.length;
    if (total != null && total > 0 && !g.isPartial && count == total) return '$count з $total ${_plural(total)}';
    return total != null && total > 0 ? '${g.coverage} з $total' : '${g.coverage} сер.';
  }

  static String _plural(int n) {
    final m10 = n % 10, m100 = n % 100;
    if (m10 == 1 && m100 != 11) return 'серії';
    return 'серій';
  }

  /// The dub (or subtitles) as the panel's first row: the team, which episodes, when updated; a tap opens the choice
  Widget _variantRow(WatchGroup g, {required bool canPick}) {
    final warn = episodeCheckWarns(_d.checkOf(g));
    return PlayerMenuRow(
      key: const ValueKey('watch-variant'),
      scale: _s,
      sheet: widget.sheet,
      icon: warn ? LineIcon.warning : (g.isSub ? LineIcon.subtitles : LineIcon.mic),
      iconColor: warn ? watchWarnColor() : null,
      title: g.teamLabel,
      sub: [_episodesOf(g), if (g.updatedAt != null) _updated(g.updatedAt!)].join(' · '),
      chevron: canPick,
      dimWhenOff: false,
      onTap: canPick ? () => _open(_Page.voices) : null,
    );
  }

  /// The guide of MyAnimeList's numbers [lo]–[hi]: what is known at once, else asked for (the rows change when it
  /// comes, and the current episode is brought into view again)
  EpisodeGuide? _guideOf(String animeKey, int lo, int hi) {
    final key = '$animeKey#$lo-$hi';
    if (_guideKey == key) return _guide;
    _guideKey = key;
    final service = EpisodeGuideService.instance;
    _guide = service.peek(animeKey, lo, hi);
    _loading = _guide == null;
    if (_loading) {
      unawaited(service.load(animeKey, lo, hi).then((g) {
        if (!mounted || _guideKey != key) return;
        setState(() {
          _guide = g;
          _loading = false;
        });
        _revealCurrent(first: true);
      }));
    }
    return _guide;
  }

  /// What every episode of [from]–[to] shows — the title (TheMovieDB's Ukrainian, the site's own Ukrainian, else
  /// MyAnimeList's English), the other name, the guide's data — and so how the range is drawn
  List<_Episode> _rowsOf(RemoteSession s, int from, int to) {
    final numbers = _d.malNumbers;
    int? lo, hi;
    for (var i = from; i < to && i < numbers.length; i++) {
      final n = numbers[i];
      if (n == null) continue;
      lo = lo == null ? n : math.min(lo, n);
      hi = hi == null ? n : math.max(hi, n);
    }
    if (lo == null || hi == null) _loading = false;
    final guide = lo == null || hi == null ? null : _guideOf(s.animeKey, lo, hi);
    final out = <_Episode>[];
    for (var i = from; i < to; i++) {
      final info = guide?[i < numbers.length ? numbers[i] : null];
      final site = siteEpisodeTitle(s.entries[i].title);
      final title = info?.uk ?? site ?? info?.en;
      final original = title == null ? null : (title == info?.en ? info?.ja : (info?.en ?? info?.ja));
      out.add(_Episode(i, title: title, original: original, info: info));
    }
    _from = from;
    _to = to;
    // While the titles are on their way the episodes are rows already — with stills, as most titles have them — whose
    // stills and lines are grey (`_row`), not plates that turn into rows a second later. Another range's rows keep
    // their kind; a title found to have no titles keeps its plates
    if (_loading && guide == null) {
      if (_rows == _Rows.plates && _platesOf != s.animeKey) _rows = _Rows.stills;
      return out;
    }
    _rows = out.any((x) => x.info?.still != null)
        ? _Rows.stills
        : out.any((x) => x.title != null)
            ? _Rows.titles
            : _Rows.plates;
    _platesOf = _rows == _Rows.plates ? s.animeKey : null;
    return out;
  }

  static const double _titleSize = 14;
  static const double _subSize = 12;
  static const double _stillW = 104;
  static const double _stillH = 58.5;

  /// A row's height: with stills, the still (16:9) or two lines of title and the date line, whichever is taller;
  /// without, a line of title and the date line; on a phone never under 56 dp. [ts]: the system's text scale
  double _rowExtent(_Rows mode, double ts) {
    final s = _s;
    final stills = mode == _Rows.stills;
    final text = (_titleSize * 1.25 * (stills ? 2 : 1) + _subSize * 1.35) * s * ts + 3 * s;
    final body = stills ? math.max(_stillH * s, text) + 14 * s : text + 18 * s;
    return math.max(body, widget.sheet ? 56.0 : 0) + 2;
  }

  /// The episodes of the range: rows (a long series builds only those in view) or, without titles, plates in
  /// [RemotePanelBody.columns] columns
  Widget _episodes(RemoteSession s, List<_Episode> rows, {Widget? strip}) {
    final d = _d;
    final seen = d.store.watched(s.animeKey);
    final cur = d.index;
    final downloads = DownloadManager.instance.byEpKey(s.animeKey, d.groupId);
    String label(int i) => episodeLabel(s.entries[i].episode, i);
    if (_rows == _Rows.plates) {
      final gap = 7 * _s;
      return SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (strip != null) strip,
            Padding(
              padding: EdgeInsets.symmetric(horizontal: _pad),
              child: LayoutBuilder(
                builder: (context, c) {
                  const cols = RemotePanelBody.columns;
                  final w = ((c.maxWidth - gap * (cols - 1)) / cols).floorToDouble();
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (final r in rows)
                        SizedBox(
                          width: w,
                          child: _plate(
                            s.entries[r.index],
                            r.index,
                            label(r.index),
                            watched: seen.contains(s.entries[r.index].epKey),
                            current: r.index == cur,
                            download: downloads[s.entries[r.index].epKey],
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      );
    }
    final ts = (MediaQuery.textScalerOf(context).scale(10) / 10).clamp(1.0, 1.6).toDouble();
    _extent = _rowExtent(_rows, ts);
    return SliverFixedExtentList(
      itemExtent: _extent,
      delegate: SliverChildBuilderDelegate(
        (context, k) {
          final r = rows[k];
          final e = s.entries[r.index];
          return _row(r, label(r.index), watched: seen.contains(e.epKey), current: r.index == cur, download: downloads[e.epKey]);
        },
        childCount: rows.length,
      ),
    );
  }

  /// An episode's length: «23:40» when MoonAnime knows it to the second, else TheMovieDB's «24 хв»
  static String? _lengthOf(GuideEpisode? info) {
    final s = info?.seconds;
    if (s != null) return AppFormatters.formatTime(Duration(seconds: s));
    final m = info?.runtime;
    return m == null ? null : '$m хв';
  }

  /// «ще 21 хв» of the current episode (null while its length is unknown)
  static String? _left(Duration position, Duration duration) {
    if (duration <= Duration.zero) return null;
    return 'ще ${math.max(1, ((duration - position).inSeconds / 60).ceil())} хв';
  }

  static double _part(Duration position, Duration duration) =>
      duration <= Duration.zero ? 0 : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0).toDouble();

  /// An episode as a row: the still with the number and length (without stills, the number), the title, under it
  /// the air date, length, filler / recap marks, the download and watched marks; the current one lighter with its
  /// progress. A tap opens the episode, holding it (the right button) opens its details
  Widget _row(_Episode r, String label, {required bool watched, required bool current, DownloadItem? download}) {
    final s = _s;
    final i = r.index;
    final info = r.info;
    final stills = _rows == _Rows.stills;
    final dim = watched && !current;
    final Color fg = current ? uiTheme.textPrimary : (dim ? AppTones.rowSub : AppTones.plateText);
    const tabular = [FontFeature.tabularFigures()];
    // The titles are on their way: grey lines where the title and the date will be
    final pending = _loading && info == null;
    final ts = (MediaQuery.textScalerOf(context).scale(10) / 10).clamp(1.0, 1.6).toDouble();
    Widget bar(double? factor, double width, double line, double height) => SizedBox(
          height: line * s * ts,
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: FractionallySizedBox(
              widthFactor: factor,
              child: Container(
                width: factor == null ? width * s : null,
                height: height * s,
                decoration: BoxDecoration(
                  color: current && !uiTheme.isLight ? const Color(0xFF45454D) : AppTones.plate,
                  borderRadius: uiTheme.borderRadius(4 * s),
                ),
              ),
            ),
          ),
        );

    final length = _lengthOf(info);
    Widget sub(String? left) {
      final parts = [
        if (info?.aired != null) _date(info!.aired!),
        if (left != null) left else if (!stills && length != null) length,
        if (info?.filler == true) 'філер',
        if (info?.recap == true) 'рекап',
      ];
      return Row(
        children: [
          if (parts.isNotEmpty)
            Flexible(
              child: Text(parts.join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: playerText(_subSize * s, color: AppTones.rowSub, height: 1.35)),
            )
          else if (pending)
            bar(null, 76, _subSize * 1.35, 9),
          // On the device (plays without internet) or on its way; watched
          if (download != null && download.state != DownloadState.failed) ...[
            SizedBox(width: 6 * s),
            LineIconView(LineIcon.download, size: 13 * s, color: download.isDone ? uiTheme.accentColor : AppTones.rowSub, stroke: 2),
          ],
          if (dim) ...[
            SizedBox(width: 6 * s),
            LineIconView(LineIcon.check, size: 13 * s, color: AppTones.rowSub, stroke: 2.2),
          ],
        ],
      );
    }

    final texts = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (r.title == null && pending)
          // (lines of different lengths, as titles are)
          bar(0.5 + (i * 7 % 5) * 0.08, 0, _titleSize * 1.25, 11)
        else
          Text(
            r.title ?? 'Серія $label',
            maxLines: stills ? 2 : 1,
            overflow: TextOverflow.ellipsis,
            style: playerText(_titleSize * s, color: fg, weight: current ? FontWeight.w700 : FontWeight.w500, height: 1.25),
          ),
        SizedBox(height: 3 * s),
        current ? _Live(driver: _d, builder: (p, dur) => sub(_left(p, dur))) : sub(null),
      ],
    );

    Widget badge(String text, {required bool start}) => _stillBadge(text, start: start);

    Widget lead;
    if (stills) {
      final url = info?.stillUrl;
      final px = (_stillW * s * MediaQuery.devicePixelRatioOf(context)).round();
      lead = ClipRRect(
        borderRadius: uiTheme.borderRadius(8 * s),
        child: SizedBox(
          width: _stillW * s,
          height: _stillH * s,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: AppTones.plate),
              if (url != null)
                Opacity(
                  opacity: dim ? 0.55 : 1,
                  child: Image(
                    image: ResizeImage.resizeIfNeeded(px, null, HikkaImage(url)),
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    errorBuilder: (context, error, stack) => const SizedBox.shrink(),
                  ),
                ),
              badge(label, start: true),
              if (current)
                _Live(
                  driver: _d,
                  builder: (p, dur) => Stack(
                    fit: StackFit.expand,
                    children: [
                      if (dur > Duration.zero) badge(AppFormatters.formatTime(dur), start: false),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: LinearProgressIndicator(value: _part(p, dur), minHeight: 3 * s, color: uiTheme.accentColor, backgroundColor: Colors.white30),
                      ),
                    ],
                  ),
                )
              else if (length != null)
                badge(length, start: false),
            ],
          ),
        ),
      );
    } else {
      lead = SizedBox(
        width: 34 * s,
        child: Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.fade,
          softWrap: false,
          style: playerText(15 * s, color: current ? uiTheme.accentColor : fg, weight: FontWeight.w700, features: tabular),
        ),
      );
    }

    final shape = RoundedRectangleBorder(borderRadius: uiTheme.borderRadius(12 * s));
    final row = Padding(
      padding: EdgeInsets.symmetric(horizontal: _pad - 8 * s, vertical: 1),
      child: Material(
        color: current ? AppTones.plateOn : Colors.transparent,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          customBorder: shape,
          splashColor: Colors.transparent,
          highlightColor: uiTheme.touchHighlight,
          hoverColor: uiTheme.hoverOverlay,
          onTap: () => widget.onEpisodeSelected(i),
          onLongPress: () => _openDetail(r, label),
          onSecondaryTap: () => _openDetail(r, label),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Padding(
                padding: stills ? EdgeInsets.all(7 * s) : EdgeInsets.fromLTRB(8 * s, 0, 10 * s, 0),
                child: Row(
                  children: [
                    lead,
                    SizedBox(width: stills ? 11 * s : 8 * s),
                    Expanded(child: texts),
                  ],
                ),
              ),
              if (current && !stills)
                Positioned(
                  left: 50 * s,
                  right: 10 * s,
                  bottom: 4 * s,
                  child: _Live(
                    driver: _d,
                    builder: (p, dur) => ClipRRect(
                      borderRadius: BorderRadius.circular(2 * s),
                      child: LinearProgressIndicator(value: _part(p, dur), minHeight: 2.5 * s, color: uiTheme.accentColor, backgroundColor: Colors.white24),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    final about = info?.about;
    final tip = [
      if (r.title != null) r.title!,
      if (r.original != null && r.original != r.title) r.original!,
      if (about != null) '\n${about.length > 300 ? '${about.substring(0, 300)}…' : about}',
    ].join('\n');
    return KeyedSubtree(
      key: ValueKey('ep-$i'),
      child: Semantics(
        key: current ? _currentKey : null,
        button: true,
        selected: current,
        label: 'Серія $label${r.title != null ? ': ${r.title}' : ''}${watched ? ', переглянуто' : ''}',
        onLongPressHint: 'опис серії',
        child: AppPlatform.isMobile || tip.isEmpty ? row : Tooltip(message: tip, waitDuration: const Duration(milliseconds: 600), child: row),
      ),
    );
  }

  /// A dark plate in a corner of a still: the number (bold, left) or the length (right); [big] for the details' still
  Widget _stillBadge(String text, {required bool start, double big = 1}) {
    final s = _s * big;
    return Positioned(
      left: start ? 5 * s : null,
      right: start ? null : 5 * s,
      bottom: 4 * s,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 5 * s, vertical: 1.5 * s),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.65), borderRadius: BorderRadius.circular(4 * s)),
        child: Text(
          text,
          style: playerText((start ? 11.5 : 10.5) * s, color: Colors.white, weight: start ? FontWeight.w700 : FontWeight.normal, features: const [FontFeature.tabularFigures()]),
        ),
      ),
    );
  }

  // ── An episode's details ────────────────────────────────────────────────────

  /// An episode's details: a card over the list on a phone held upright (the panel is a bottom sheet), a page of the
  /// panel in a side panel (a phone on its side, a PC)
  void _openDetail(_Episode r, String label) {
    final size = MediaQuery.sizeOf(context);
    _detailFrom = _scroll.hasClients ? _scroll.offset : 0;
    setState(() {
      _detail = r;
      _detailLabel = label;
      _asCard = widget.sheet && size.height > size.width;
      if (!_asCard) _page = _Page.episode;
    });
  }

  void _closeDetail() {
    if (_detail == null && _page != _Page.episode) return;
    final page = _page == _Page.episode;
    setState(() {
      _detail = null;
      _page = _Page.main;
    });
    if (!page) return;
    // Back where the list was, not at the current episode
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final pos = _scroll.position;
      pos.jumpTo(_detailFrom.clamp(pos.minScrollExtent, pos.maxScrollExtent).toDouble());
    });
  }

  /// Under the details' title: the air date, length, filler / recap
  static String _detailMeta(GuideEpisode? info) => [
        if (info?.aired != null) _date(info!.aired!),
        if (_lengthOf(info) case final l?) l,
        if (info?.filler == true) 'філер',
        if (info?.recap == true) 'рекап',
      ].join(' · ');

  /// The details' still (16:9, [width] wide) with the number and length on it; grey without a picture
  Widget _detailStill(GuideEpisode? info, String label, double width, {double big = 1}) {
    final url = info?.stillUrl;
    final length = _lengthOf(info);
    final px = (width * MediaQuery.devicePixelRatioOf(context)).round();
    return ClipRRect(
      borderRadius: uiTheme.borderRadius(10 * _s),
      child: SizedBox(
        width: width,
        height: width * 9 / 16,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: AppTones.plate),
            if (url != null)
              Image(
                image: ResizeImage.resizeIfNeeded(px, null, HikkaImage(url)),
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (context, error, stack) => const SizedBox.shrink(),
              ),
            _stillBadge(label, start: true, big: big),
            if (length != null) _stillBadge(length, start: false, big: big),
          ],
        ),
      ),
    );
  }

  bool _watched(int i) {
    final s = _d.session;
    return s != null && i < s.entries.length && _d.store.watched(s.animeKey).contains(s.entries[i].epKey);
  }

  /// The details as a page of a side panel: the still, the title and the other name, the date and length, what to do
  /// (watch it, mark it watched), the description
  Widget _detailPage() {
    final r = _detail;
    if (r == null) return const SizedBox.shrink();
    final s = _s;
    final i = r.index;
    final info = r.info;
    final watched = _watched(i);
    final meta = _detailMeta(info);
    final about = info?.about;
    final still = info?.stillUrl != null;
    return LayoutBuilder(builder: (context, c) {
      // A short panel (a phone on its side) puts a small still beside the title: what to do stays in view
      final short = c.maxHeight < 480;
      final texts = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(r.title ?? 'Серія $_detailLabel', style: playerText((short ? 15.5 : (widget.sheet ? 18 : 17)) * s, weight: FontWeight.w700, height: 1.25)),
          if (r.original != null && r.original != r.title)
            Padding(
              padding: EdgeInsets.only(top: 4 * s),
              child: Text(r.original!, style: playerText((short ? 12.5 : 13) * s, color: AppTones.rowSub, height: 1.3)),
            ),
          if (meta.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(top: (short ? 4 : 6) * s),
              child: Text(meta, style: playerText((short ? 12 : 12.5) * s, color: AppTones.rowSub)),
            ),
        ],
      );
      return _list([
        if (short)
          Padding(
            padding: EdgeInsets.fromLTRB(_pad, 2 * s, _pad, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (still) ...[_detailStill(info, _detailLabel, 132 * s), SizedBox(width: 12 * s)],
                Expanded(child: texts),
              ],
            ),
          )
        else ...[
          if (still)
            Padding(
              padding: EdgeInsets.fromLTRB(_pad, 2 * s, _pad, 0),
              child: _detailStill(info, _detailLabel, c.maxWidth - 2 * _pad, big: 1.2),
            ),
          Padding(padding: EdgeInsets.fromLTRB(_pad, 14 * s, _pad, 0), child: texts),
        ],
        SizedBox(height: 10 * s),
        if (i != _d.index)
          PlayerMenuRow(
            key: const ValueKey('detail-play'),
            scale: s,
            sheet: widget.sheet,
            icon: LineIcon.play,
            title: 'Дивитися',
            chevron: false,
            onTap: () {
              _closeDetail();
              widget.onEpisodeSelected(i);
            },
          ),
        PlayerMenuRow(
          key: const ValueKey('detail-watched'),
          scale: s,
          sheet: widget.sheet,
          icon: LineIcon.check,
          iconColor: watched ? uiTheme.accentColor : null,
          title: watched ? 'Переглянуто' : 'Позначити переглянутою',
          value: watched ? 'Зняти' : null,
          chevron: false,
          onTap: () {
            _d.toggleWatched(i);
            _closeDetail();
          },
        ),
        if (about != null)
          Padding(
            padding: EdgeInsets.fromLTRB(_pad, 10 * s, _pad, 4 * s),
            child: Text(about, style: playerText(14 * s, color: AppTones.plateText, height: 1.45)),
          ),
      ]);
    });
  }

  /// The details as a card over the dimmed list of a bottom sheet: the still and the title side by side, the
  /// description, two buttons
  Widget _detailCard(_Episode r) {
    final s = _s;
    final i = r.index;
    final info = r.info;
    final watched = _watched(i);
    final meta = _detailMeta(info);
    final about = info?.about;
    final light = uiTheme.isLight;
    return Container(
      key: const ValueKey('episode-card'),
      margin: EdgeInsets.fromLTRB(8 * s, 0, 8 * s, 8 * s),
      padding: EdgeInsets.fromLTRB(14 * s, 14 * s, 14 * s, 12 * s),
      decoration: BoxDecoration(
        color: light ? Colors.white : const Color(0xFF26262C),
        borderRadius: uiTheme.borderRadius(16 * s),
        border: Border.all(color: AppTones.menuLine),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: light ? 0.12 : 0.5), blurRadius: 24, offset: const Offset(0, -4))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _detailStill(info, _detailLabel, 132 * s),
              SizedBox(width: 12 * s),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(r.title ?? 'Серія $_detailLabel', maxLines: 3, overflow: TextOverflow.ellipsis, style: playerText(15.5 * s, weight: FontWeight.w700, height: 1.25)),
                    if (r.original != null && r.original != r.title)
                      Padding(
                        padding: EdgeInsets.only(top: 3 * s),
                        child: Text(r.original!, maxLines: 2, overflow: TextOverflow.ellipsis, style: playerText(12.5 * s, color: AppTones.rowSub, height: 1.3)),
                      ),
                    if (meta.isNotEmpty)
                      Padding(
                        padding: EdgeInsets.only(top: 4 * s),
                        child: Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: playerText(12 * s, color: AppTones.rowSub)),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (about != null) ...[
            SizedBox(height: 12 * s),
            Text(about, maxLines: 7, overflow: TextOverflow.ellipsis, style: playerText(13.5 * s, color: AppTones.plateText, height: 1.45)),
          ],
          SizedBox(height: 14 * s),
          Row(
            children: [
              if (i != _d.index) ...[
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: AppAccentButton(
                      key: const ValueKey('detail-play'),
                      scale: s,
                      label: 'Дивитися',
                      icon: Symbols.play_arrow_rounded,
                      solid: true,
                      compact: true,
                      expand: true,
                      onTap: () {
                        _closeDetail();
                        widget.onEpisodeSelected(i);
                      },
                    ),
                  ),
                ),
                SizedBox(width: 10 * s),
              ],
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: AppSecondaryButton(
                    key: const ValueKey('detail-watched'),
                    scale: s,
                    label: watched ? 'Зняти позначку' : 'Переглянуто',
                    icon: watched ? Symbols.undo_rounded : Symbols.check_rounded,
                    onTap: () {
                      _d.toggleWatched(i);
                      _closeDetail();
                    },
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _plate(RemoteEntry e, int i, String label, {required bool watched, required bool current, DownloadItem? download}) {
    final s = _s;
    final light = uiTheme.isLight;
    final Color fg = current ? uiTheme.textPrimary : (watched ? (light ? const Color(0xFFA0A0AC) : const Color(0xFF6D6D75)) : AppTones.plateText);
    final shape = RoundedRectangleBorder(
      borderRadius: uiTheme.borderRadius(10 * s),
      side: current ? BorderSide(color: AppTones.plateOutline) : BorderSide.none,
    );
    void toggle() => _d.toggleWatched(i);
    final plate = Material(
      color: current ? AppTones.plateOn : AppTones.plate,
      shape: shape,
      child: InkWell(
        customBorder: shape,
        splashColor: Colors.transparent,
        highlightColor: uiTheme.touchHighlight,
        hoverColor: uiTheme.hoverOverlay,
        onTap: () => widget.onEpisodeSelected(i),
        onLongPress: toggle,
        onSecondaryTap: toggle,
        child: SizedBox(
          height: math.max(36 * s, widget.sheet ? 40.0 : 0),
          child: Stack(
            children: [
              Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 3 * s),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    style: playerText(13.5 * s, color: fg, weight: current ? FontWeight.w700 : FontWeight.normal, features: const [FontFeature.tabularFigures()]),
                  ),
                ),
              ),
              if (watched && !current) Positioned(top: 3 * s, right: 4 * s, child: LineIconView(LineIcon.check, size: 10 * s, color: fg, stroke: 2.4)),
              // On the device (plays without internet): an arrow in the other corner; on its way: the same arrow dim
              if (download != null && download.state != DownloadState.failed)
                Positioned(
                  top: 3 * s,
                  left: 4 * s,
                  child: LineIconView(LineIcon.download, size: 10 * s, color: download.isDone ? uiTheme.accentColor : AppTones.rowSub, stroke: 2.2),
                ),
              if (current)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 4 * s,
                  child: Center(
                    child: Container(
                      width: 14 * s,
                      height: 2 * s,
                      decoration: BoxDecoration(color: uiTheme.accentColor, borderRadius: BorderRadius.circular(1 * s)),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    return KeyedSubtree(
      key: ValueKey('ep-$i'),
      child: Semantics(
        key: current ? _currentKey : null,
        button: true,
        selected: current,
        label: 'Серія $label${watched ? ', переглянуто' : ''}',
        child: AppPlatform.isMobile || e.title.isEmpty ? plate : Tooltip(message: e.title, child: plate),
      ),
    );
  }

  // ── Dubs and subtitles ──────────────────────────────────────────────────────

  Widget _voices() {
    final d = _d;
    final groups = d.title?.groups ?? const <WatchGroup>[];
    if (groups.isEmpty) {
      return AppEmptyState(scale: _s, icon: Symbols.record_voice_over_rounded, text: 'Інших озвучок для цього аніме немає');
    }
    // The current variant with an episode mismatch against Hikka: an explanation above the list (marks will not sync with it)
    EpisodeCheck? currentCheck;
    for (final g in groups) {
      if (g.id == d.groupId) currentCheck = d.checkOf(g);
    }
    final note = currentCheck != null && currentCheck.hasNote ? currentCheck : null;
    final dubs = [for (final g in groups) if (!g.isSub) g];
    final subs = [for (final g in groups) if (g.isSub) g];
    return _list([
      _hint('Перемикається з того ж місця. Вибір запамʼятовується'),
      if (note != null)
        Padding(
          padding: EdgeInsets.fromLTRB(_pad - 4 * _s, 4 * _s, _pad - 4 * _s, 6 * _s),
          child: EpisodeNote(scale: _s, check: note, compact: true),
        ),
      if (dubs.isNotEmpty) ...[_caption('Озвучення · ${dubs.length}', top: 8), for (final g in dubs) _variantChoice(g)],
      if (subs.isNotEmpty) ...[_caption('Субтитри · ${subs.length}'), for (final g in subs) _variantChoice(g)],
    ]);
  }

  Widget _variantChoice(WatchGroup g) {
    final d = _d;
    final source = d.registry.byId(g.sourceId)?.name ?? g.sourceId;
    final warn = episodeCheckWarns(d.checkOf(g));
    return AppCheckRow(
      key: ValueKey('watch-variant-${g.id}'),
      scale: _s,
      label: g.teamLabel,
      subtitle: [_episodesOf(g), source, if (g.updatedAt != null) _updated(g.updatedAt!)].join(' · '),
      selected: g.id == d.groupId,
      padH: widget.sheet ? 20 : 16,
      minHeight: widget.sheet ? 52 : 46,
      trailing: warn ? LineIconView(LineIcon.warning, key: ValueKey('watch-variant-warn-${g.id}'), size: 18 * _s, color: watchWarnColor()) : null,
      onTap: () {
        if (g.id != d.groupId) d.switchGroup(g);
        _back();
      },
    );
  }

  // ── Quality and the site's player ───────────────────────────────────────────

  Widget _qualities() {
    final d = _d;
    final res = d.stream;
    if (res == null || res.qualities.isEmpty) return _waiting();
    final cur = d.video?.url;
    return _list([
      _hint('Інша якість того ж плеєра: відео продовжиться з того ж місця'),
      for (final v in res.qualities)
        AppCheckRow(
          key: ValueKey('watch-quality-${SettingsDrawer.qualityLabel(v)}'),
          scale: _s,
          label: SettingsDrawer.qualityLabel(v),
          selected: v.url == cur,
          padH: widget.sheet ? 20 : 16,
          minHeight: widget.sheet ? 52 : 44,
          onTap: () {
            if (v.url != cur) d.switchQuality(v);
            _back();
          },
        ),
    ]);
  }

  Widget _players() {
    final d = _d;
    final res = d.stream;
    if (res == null || res.hosters.isEmpty) return _waiting();
    return _list([
      _hint('Якщо один не працює, спробуйте інший. Вибір діє й на наступні серії'),
      for (final h in res.hosters)
        AppCheckRow(
          key: ValueKey('watch-player-$h'),
          scale: _s,
          label: h,
          selected: h.toLowerCase() == res.hoster.toLowerCase(),
          padH: widget.sheet ? 20 : 16,
          minHeight: widget.sheet ? 52 : 44,
          onTap: () {
            if (h.toLowerCase() != res.hoster.toLowerCase()) d.switchHoster(h);
            _back();
          },
        ),
    ]);
  }

  Widget _waiting() => AppEmptyState(
        scale: _s,
        icon: Symbols.hourglass_top_rounded,
        text: _d.phase == RemotePhase.failed ? 'Плеєри не знайдено. Спробуйте іншу озвучку.' : 'Список зʼявиться, коли серія завантажиться',
      );
}

/// One episode of the list: its place in the queue, the title shown and the other name (a tooltip on a PC), the
/// guide's data
class _Episode {
  final int index;
  final String? title;
  final String? original;
  final GuideEpisode? info;

  const _Episode(this.index, {this.title, this.original, this.info});
}

/// The current episode's position, followed through the driver's ticks (every few seconds): only this part rebuilds
class _Live extends StatelessWidget {
  final RemoteDriver driver;
  final Widget Function(Duration position, Duration duration) builder;

  const _Live({required this.driver, required this.builder});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: driver.progress,
        builder: (context, tick, child) => builder(driver.engine.position, driver.engine.duration),
      );
}
