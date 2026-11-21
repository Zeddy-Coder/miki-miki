import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../models/hikka_models.dart';
import '../../services/downloads/download_manager.dart';
import '../../services/downloads/download_models.dart';
import '../../services/episode_check.dart';
import '../../services/hikka_lists.dart';
import '../../services/watch_marks.dart';
import '../../services/hikka_nav.dart';
import '../../services/hikka_prefs.dart';
import '../../services/network_status.dart';
import '../../services/remote_playback.dart';
import '../../services/ui_theme_service.dart';
import '../../services/watch_models.dart';
import '../../services/watch_service.dart';
import '../../services/watch_store.dart';
import '../../utils/platform_info.dart';
import '../app_animation_kit.dart';
import '../app_ui_kit.dart';
import '../design_kit.dart';
import '../downloads/download_kit.dart';
import '../downloads/download_picker.dart';
import '../watch_callout.dart';
import 'hikka_common.dart';
import 'hikka_page_kit.dart';
import 'hikka_watch_dialogs.dart';
import '../../services/source_prefs.dart';
import '../../utils/app_clock.dart';
import '../line_icons.dart';
import '../settings_kit.dart';
import 'sources_dialog.dart';

/// "Дивитись" on the anime page (right under the header): the main button "Дивитись / Продовжити · серія N" and one
/// quiet line under it (the team, how much is watched, the quality) with the gray "Перегляд" button. Everything else (the
/// dub choice, the episodes, quality, player, sources) is in the "Перегляд" panel. The choice (here or in the player)
/// is remembered. A licensed title first shows the license card; a badge under the line warns about episode numbering
/// mismatch with Hikka; an airing title shows when the next episode comes out.
class HikkaWatchSection extends StatefulWidget {
  final HikkaAnime anime;
  final HikkaRoute route;
  final double scale;
  final double pad;

  /// Space under the block before scaling (the phone layout puts the description right under it)
  final double bottom;

  const HikkaWatchSection({super.key, required this.anime, required this.route, required this.scale, required this.pad, this.bottom = 22});

  @override
  State<HikkaWatchSection> createState() => _HikkaWatchSectionState();
}

class _HikkaWatchSectionState extends State<HikkaWatchSection> {
  static const String _memoLoad = 'watch';

  late WatchLoad _load;
  bool _ack = false; // confirmation of watching a licensed title: only for this showing of the page
  String? _notice;

  double get _scale => widget.scale;
  WatchService get _service => WatchService.instance;
  WatchStore get _store => _service.store;

  @override
  void initState() {
    super.initState();
    final memo = widget.route.memo[_memoLoad];
    _load = memo is WatchLoad ? memo : _begin();
    _load.addListener(_changed);
    _store.addListener(_changed);
    // How many episodes are marked on Hikka: "Дивитись" offers the next one after them
    HikkaMyList.instance.addListener(_changed);
    // Downloaded episodes: marks on the plates, the line under the button; offline the button starts from them
    DownloadManager.instance.addListener(_changed);
    NetworkStatus.instance.addListener(_changed);
    unawaited(HikkaMyList.instance.entry(widget.anime.slug, refresh: true).then((_) {}, onError: (_) {}));
  }

  /// How many episodes are already watched (more from the app's history and Hikka)
  int get _seen => math.max(_hikkaEpisodes, _store.watched(_load.title.animeKey).length);

  int get _hikkaEpisodes => HikkaMyList.instance.cached(widget.anime.slug)?.episodes ?? 0;

  @override
  void dispose() {
    _load.removeListener(_changed);
    _store.removeListener(_changed);
    HikkaMyList.instance.removeListener(_changed);
    DownloadManager.instance.removeListener(_changed);
    NetworkStatus.instance.removeListener(_changed);
    super.dispose();
  }

  WatchLoad _begin() {
    final l = _service.start(widget.anime);
    widget.route.memo[_memoLoad] = l;
    return l;
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  /// Searches anew (the sources changed, something did not respond)
  void _restart() {
    _load.removeListener(_changed);
    setState(() {
      _load = _begin();
      _load.addListener(_changed);
      _notice = null;
    });
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _sourceName(String id) => _service.registry.byId(id)?.name ?? id;

  /// From where and with which dub to start: "Продовжити" or the first episode; `null` while nothing is found
  ({WatchTitle title, WatchGroup group, ContinuePoint point})? _target() {
    final t = _load.title;
    final g = _load.defaultGroup(_store, seen: _seen);
    if (g == null) return null;
    final keys = episodeKeysOf(g);
    final watched = _store.watched(t.animeKey);
    var point = continuePoint(keys, watched, _store.last(t.animeKey)?.epKey, hikkaEpisodes: _hikkaEpisodes);
    // No internet: start from what is on the device (the continue point when it is there, else the nearest downloaded)
    if (!NetworkStatus.instance.online) {
      final k = DownloadManager.instance.offlineStart(t.animeKey, g.id, keys, point.index, watched);
      if (k != null && k != point.epKey) point = ContinuePoint(keys.indexOf(k), k, started: true);
    }
    return (title: t, group: g, point: point);
  }

  Future<void> _play(WatchTitle t, WatchGroup g, String epKey) async {
    final a = widget.anime;
    // The manually chosen dub has no next episode: we ask where to go
    final plan = _load.missingNext(_store, seen: _seen);
    if (plan != null) {
      final picked = await WatchDialogs.missingNext(context, scale: _scale, plan: plan, next: _seen + 1);
      if (picked == null || !mounted) return;
      _store.clearPinnedGroup(t.animeKey);
      g = picked;
      epKey = continuePoint(episodeKeysOf(g), _store.watched(t.animeKey), _store.last(t.animeKey)?.epKey, hikkaEpisodes: _hikkaEpisodes).epKey;
    }
    final started = await WatchLauncher.play(
      RemoteLaunch(title: t, group: g, animeTitle: a.title(HikkaPrefs.instance.titleLang), epKey: epKey, poster: a.image, hikka: _load.hikka),
    );
    if (!started && mounted) setState(() => _notice = 'Плеєр ще не готовий. Спробуйте за мить.');
  }

  /// A licensed title: after confirmation we open the player at once, since the person has clearly expressed intent
  Future<void> _confirmLicensed(WatchTitle t) async {
    final go = await WatchDialogs.confirmLicensed(context, scale: _scale, license: t.license);
    if (!go || !mounted) return;
    setState(() => _ack = true);
    final target = _target();
    if (target != null) await _play(target.title, target.group, target.point.epKey);
  }

  Future<void> _showTeams(WatchGroup g) => WatchDialogs.teams(context, scale: _scale, teams: g.teams, source: _service.registry.mikai);

  /// Source settings; if what is polled changed, we search anew
  Future<void> _openSources() async {
    final registry = _service.registry;
    final before = SourcesDialog.searchSignature(registry);
    await SourcesDialog.show(context, scale: _scale, registry: registry);
    if (mounted && SourcesDialog.searchSignature(registry) != before) _restart();
  }

  // ── Building ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final t = _load.title;
    // No heading: the button speaks for itself
    return Padding(
      padding: EdgeInsets.fromLTRB(widget.pad, 0, widget.pad, widget.bottom * _scale),
      child: ConstrainedBox(constraints: BoxConstraints(maxWidth: hikkaReadableWidth(_scale)), child: _body(t)),
    );
  }

  Widget _body(WatchTitle t) {
    final next = _nextEpisodeRow();
    if (t.licensed && !_ack) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_licenseCard(t), if (next != null) next]);
    }
    final groups = t.groups;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _mainButton(t, groups),
        if (_notice != null)
          Padding(padding: EdgeInsets.only(top: 8 * _scale), child: Text(_notice!, style: hikkaStyle(12 * _scale, color: uiTheme.textMuted))),
        if (groups.isEmpty) ...[SizedBox(height: 14 * _scale), _noGroups(t)] else _content(t, groups),
        if (next != null) next,
      ],
    );
  }

  /// The main button: "Дивитись / Продовжити · серія N / Дивитись знову". Visible from the first moment; until something
  /// is found the gray "Перегляд" button stands next to it, afterwards it moves into the summary line under it
  Widget _mainButton(WatchTitle t, List<WatchGroup> groups) {
    final scale = _scale;
    final Widget play;
    if (groups.isEmpty) {
      play = AppAccentButton(scale: scale, solid: true, expand: true, compact: true, icon: Symbols.play_arrow_rounded, leading: _playGlyph, label: 'Дивитись', onTap: _noTarget);
    } else {
      final g = _load.defaultGroup(_store, seen: _seen) ?? groups.first;
      final keys = episodeKeysOf(g);
      final p = continuePoint(keys, _store.watched(t.animeKey), _store.last(t.animeKey)?.epKey, hikkaEpisodes: _hikkaEpisodes);
      final label = p.allWatched ? 'Дивитись знову' : '${p.started ? 'Продовжити' : 'Дивитись'} · серія ${episodeLabel(g.episodes[p.index], p.index)}';
      play = AppAccentButton(scale: scale, solid: true, expand: true, compact: true, icon: Symbols.play_arrow_rounded, leading: _playGlyph, label: label, onTap: () => _play(t, g, p.epKey));
    }
    if (groups.isNotEmpty) return play;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: play),
          SizedBox(width: 8 * scale),
          _panelButton(t, groups),
        ],
      ),
    );
  }

  Widget _playGlyph(Color color) => LineIconView(LineIcon.play, size: 18 * _scale, color: color);

  /// Icons of the panel rows: the design's line drawings
  Widget _rowIcon(LineIcon icon, {Color? color}) => LineIconView(icon, size: 22 * _scale, color: color ?? uiTheme.textSecondary);

  /// The gray square button that opens the "Перегляд" panel (dub, episodes, quality, player, sources): a 44×38 plate
  /// in the summary line, the button's full height next to the main button
  Widget _panelButton(WatchTitle t, List<WatchGroup> groups, {double? plateHeight}) {
    final scale = _scale;
    final r = uiTheme.borderRadius(10 * scale);
    final plate = DecoratedBox(
      decoration: BoxDecoration(color: uiTheme.bgElevated, borderRadius: r),
      child: SizedBox(
        width: 44 * scale,
        height: plateHeight,
        child: Center(child: LineIconView(LineIcon.sliders, size: 20 * scale, color: Color.lerp(uiTheme.textSecondary, uiTheme.textPrimary, 0.5)!)),
      ),
    );
    return Tooltip(
      message: 'Ще',
      child: Semantics(
        button: true,
        label: 'Перегляд: озвучка, серії, якість, плеєр і джерела',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: r,
            splashColor: Colors.transparent,
            highlightColor: uiTheme.touchHighlight,
            hoverColor: uiTheme.hoverOverlay,
            onTap: () => _openMenu(t, groups),
            child: plate,
          ),
        ),
      ),
    );
  }

  /// When the next episode comes out (an airing title): a quiet line in the same style as the summary
  Widget? _nextEpisodeRow() {
    final now = AppClock.now();
    final slot = widget.anime.nextEpisode(now);
    if (slot == null) return null;
    final scale = _scale;
    return Padding(
      padding: EdgeInsets.fromLTRB(2 * scale, 10 * scale, 2 * scale, 2 * scale),
      child: Row(
        children: [
          LineIconView(LineIcon.clock, size: 18 * scale, color: uiTheme.textMuted),
          SizedBox(width: 10 * scale),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: hikkaStyle(13 * scale, color: uiTheme.textMuted),
                children: [
                  const TextSpan(text: 'Наступна серія '),
                  TextSpan(text: '${slot.episode}', style: TextStyle(color: _bright, fontWeight: FontWeight.w600)),
                  TextSpan(text: ' · ${HikkaText.airingLabel(slot.time, now)}'),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// The bright part of quiet lines (a team name, an episode number)
  Color get _bright => Color.lerp(uiTheme.textSecondary, uiTheme.textPrimary, 0.6)!;

  /// "Дивитись" was pressed when there is nothing to watch yet: sources are off: a modal, otherwise an explanation under the button
  Future<void> _noTarget() async {
    if (_service.registry.enabled.isEmpty) {
      final open = await WatchDialogs.noSources(context, scale: _scale);
      if (open && mounted) await _openSources();
      return;
    }
    setState(() => _notice = _load.busy
        ? 'Ще шукаю озвучки, зачекайте мить.'
        : 'Не знайшли, де це дивитись українською. Спробуйте «Оновити» або змініть джерела.');
  }

  // Licensed title ----------------------------------------------------------

  Widget _licenseCard(WatchTitle t) {
    final scale = _scale;
    final license = t.license;
    final links = license?.links ?? const <({String title, String url})>[];
    final holder = license?.holder;
    // "Все одно дивитись" makes sense only if there is something to show (or we are still searching)
    final canWatch = t.groups.isNotEmpty || _load.busy;
    return AppCard(
      scale: scale,
      radius: 12,
      padding: EdgeInsets.all(16 * scale),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Symbols.verified_rounded, color: uiTheme.accentColor, size: 24 * scale, fill: 1, weight: 300),
              SizedBox(width: 10 * scale),
              Expanded(child: Text('Ліцензовано в Україні', style: hikkaStyle(15 * scale, weight: FontWeight.bold))),
            ],
          ),
          SizedBox(height: 8 * scale),
          Text(
            holder == null || holder.isEmpty
                ? 'Це аніме має офіційну ліцензію. Дивіться його легально: так ви підтримуєте тих, хто привозить аніме в Україну.'
                : 'Правовласник: $holder. Дивіться це аніме легально: так ви підтримуєте тих, хто привозить аніме в Україну.',
            style: hikkaStyle(12.5 * scale, color: uiTheme.textMuted, height: 1.45),
          ),
          if (links.isNotEmpty) ...[
            SizedBox(height: 14 * scale),
            Wrap(
              spacing: 10 * scale,
              runSpacing: 8 * scale,
              children: [
                for (int i = 0; i < links.length; i++)
                  i == 0
                      ? AppAccentButton(
                        scale: scale,
                        icon: Symbols.open_in_new_rounded,
                        label: links[i].title.isEmpty ? 'Дивитись легально' : links[i].title,
                        onTap: () => HikkaNav.instance.openLink(links[i].url),
                      )
                      : AppSecondaryButton(
                        scale: scale,
                        expand: false,
                        icon: Symbols.open_in_new_rounded,
                        label: links[i].title.isEmpty ? 'Ще одне посилання' : links[i].title,
                        onTap: () => HikkaNav.instance.openLink(links[i].url),
                      ),
              ],
            ),
          ],
          if (canWatch) ...[SizedBox(height: 8 * scale), QuietAction(label: 'Все одно дивитись', scale: scale, onTap: () => _confirmLicensed(t))],
        ],
      ),
    );
  }

  Widget _licensedBanner(WatchTitle t) {
    final scale = _scale;
    final links = t.license?.links ?? const <({String title, String url})>[];
    return Padding(
      padding: EdgeInsets.only(bottom: 12 * scale),
      child: WatchCallout(
        scale: scale,
        icon: Symbols.verified_rounded,
        color: uiTheme.accentColor,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ліцензовано в Україні. Якщо можете, дивіться легально.', style: hikkaStyle(12.5 * scale, height: 1.4)),
            if (links.isNotEmpty) ...[
              SizedBox(height: 8 * scale),
              Wrap(
                spacing: 8 * scale,
                runSpacing: 6 * scale,
                children: [
                  for (final l in links)
                    HikkaChip(
                      label: l.title.isEmpty ? 'Правовласник' : l.title,
                      scale: scale,
                      icon: Symbols.open_in_new_rounded,
                      onTap: () => HikkaNav.instance.openLink(l.url),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // Empty / loading -----------------------------------------------------

  Widget _noGroups(WatchTitle t) {
    final scale = _scale;
    if (_load.busy) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 6 * scale),
        child: Row(
          children: [
            SizedBox(width: 18 * scale, height: 18 * scale, child: CircularProgressIndicator(strokeWidth: 2.2, color: uiTheme.accentColor)),
            SizedBox(width: 12 * scale),
            Expanded(
              child: Text('Шукаю озвучки: ${_load.pending.map(_sourceName).join(', ')}…', style: hikkaStyle(13 * scale, color: uiTheme.textMuted)),
            ),
          ],
        ),
      );
    }
    final allOff = _service.registry.enabled.isEmpty;
    return AppCard(
      scale: scale,
      radius: 12,
      padding: EdgeInsets.all(16 * scale),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Symbols.video_library_rounded, color: uiTheme.textDarkMuted, size: 24 * scale, weight: 300),
              SizedBox(width: 10 * scale),
              Expanded(
                child: Text(
                  allOff ? 'Усі джерела вимкнено' : 'Не знайшли, де це дивитись українською',
                  style: hikkaStyle(14 * scale, weight: FontWeight.bold),
                ),
              ),
            ],
          ),
          if (allOff) _noteLine(Symbols.info_rounded, watchWarnColor(), 'Увімкніть хоча б одне джерело перегляду.'),
          ..._offerNotes(t, always: true),
          SizedBox(height: 12 * scale),
          Wrap(
            spacing: 10 * scale,
            runSpacing: 8 * scale,
            children: [
              if (!allOff) AppSecondaryButton(scale: scale, expand: false, icon: Symbols.refresh_rounded, label: 'Спробувати ще', onTap: _restart),
              AppSecondaryButton(scale: scale, expand: false, icon: Symbols.tune_rounded, label: 'Джерела', onTap: _openSources),
            ],
          ),
        ],
      ),
    );
  }

  Widget _noteLine(IconData icon, Color color, String text) {
    final scale = _scale;
    return Padding(
      padding: EdgeInsets.only(top: 8 * scale),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: EdgeInsets.only(top: 1 * scale), child: Icon(icon, color: color, size: 16 * scale, weight: 300)),
          SizedBox(width: 8 * scale),
          Expanded(child: Text(text, style: hikkaStyle(12 * scale, color: uiTheme.textMuted, height: 1.4))),
        ],
      ),
    );
  }

  /// What else is known about sources: a page without episodes (with an explanation of the mismatch), errors, sources still searching
  List<Widget> _offerNotes(WatchTitle t, {bool always = false}) {
    final out = <Widget>[];
    for (final o in t.offers) {
      if (o.groups.isNotEmpty) continue;
      final c = checkEpisodes(const [], _load.hikka);
      out.add(
        _noteLine(
          Symbols.info_rounded,
          watchWarnColor(),
          '${o.source.name}: ${c.hasNote ? c.note : 'сторінку знайдено, але серій на ній поки немає.'}',
        ),
      );
    }
    t.errors.forEach((id, message) => out.add(_noteLine(Symbols.cloud_off_rounded, uiTheme.textDarkMuted, '${_sourceName(id)}: $message')));
    if (_load.busy && !always) {
      out.add(_noteLine(Symbols.hourglass_top_rounded, uiTheme.textDarkMuted, 'Ще шукаю: ${_load.pending.map(_sourceName).join(', ')}…'));
    }
    return out;
  }

  // Main content --------------------------------------------------------------

  Widget _content(WatchTitle t, List<WatchGroup> groups) {
    final g = _load.defaultGroup(_store, seen: _seen) ?? groups.first;
    final check = _load.checkOf(g);
    final scale = _scale;
    final keys = episodeKeysOf(g);
    final watched = _store.watched(t.animeKey);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (t.licensed) Padding(padding: EdgeInsets.only(top: 12 * scale), child: _licensedBanner(t)),
        _summary(t, groups, g, keys, watched),
        // "Не всі серії" / "озвучено не всі" is already visible in the dub line (a yellow icon): we keep the badge for numbering and OVAs
        if (check.hasNote && check.level != EpisodeCheckLevel.incomplete && check.level != EpisodeCheckLevel.lag) ...[
          SizedBox(height: 10 * scale),
          EpisodeNote(scale: scale, check: check),
        ],
      ],
    );
  }

  /// One quiet line under the button: the chosen team, how much is watched, the quality, and the gray "Перегляд" button
  /// at its end; a tap anywhere on it opens the panel
  Widget _summary(WatchTitle t, List<WatchGroup> groups, WatchGroup g, List<String> keys, Set<String> watched) {
    final scale = _scale;
    final seen = keys.where(watched.contains).length;
    final warn = episodeCheckWarns(_load.checkOf(g));
    final rest = [
      if (seen > 0) 'переглянуто $seen з ${keys.length}',
      SourcePrefs.heightLabel(_service.registry.prefs.maxHeight),
    ].join(' · ');
    final dl = _downloadSpan(t.animeKey, g);
    return Padding(
      padding: EdgeInsets.fromLTRB(2 * scale, 12 * scale, 2 * scale, 2 * scale),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              button: true,
              label: 'Озвучка та параметри перегляду',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _openMenu(t, groups),
                child: Row(
                  children: [
                    LineIconView(
                      warn ? LineIcon.warning : (g.isSub ? LineIcon.subtitles : LineIcon.mic),
                      size: 18 * scale,
                      color: warn ? watchWarnColor() : uiTheme.textMuted,
                    ),
                    SizedBox(width: 10 * scale),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          style: hikkaStyle(13 * scale, color: uiTheme.textMuted),
                          children: [
                            TextSpan(text: g.teamLabel, style: TextStyle(color: _bright, fontWeight: FontWeight.w600)),
                            TextSpan(text: ' · $rest'),
                            if (dl != null) dl,
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(width: 10 * scale),
          _panelButton(t, groups, plateHeight: 38 * scale),
        ],
      ),
    );
  }

  /// " · ⬇ 3" (episodes of this dub on the device) or " · ⬇ 45 %" (downloading now) at the end of the summary line
  InlineSpan? _downloadSpan(String animeKey, WatchGroup g) {
    final items = DownloadManager.instance.byEpKey(animeKey, g.id).values;
    if (items.isEmpty) return null;
    final scale = _scale;
    final running = items.where((i) => i.state == DownloadState.running).firstOrNull;
    final done = items.where((i) => i.isDone).length;
    final waiting = items.where((i) => i.isActive).length;
    final f = running?.fraction;
    final text = running != null && f != null ? '${(f * 100).floor()} %' : (done > 0 ? '$done' : (waiting > 0 ? 'у черзі' : null));
    if (text == null) return null;
    return TextSpan(children: [
      const TextSpan(text: ' · '),
      WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: LineIconView(LineIcon.download, size: 14 * scale, color: done > 0 || running != null ? uiTheme.accentColor : uiTheme.textMuted, stroke: 1.9),
      ),
      TextSpan(text: ' $text'),
    ]);
  }

  /// "оновлено 02.11" (with the year when it is not this one)
  String _updated(DateTime d) {
    final now = DateTime.now();
    return 'оновлено ${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}${d.year != now.year ? '.${d.year}' : ''}';
  }

  /// Which episodes a variant has: "28 з 28 серій" when it has all of them, else the ranges ("1–12 з 28", or
  /// "1–12 сер." while the total is unknown)
  String _episodesOf(WatchGroup g) {
    final total = _load.hikka.total;
    final count = g.episodes.length;
    if (total != null && total > 0 && !g.isPartial && count == total) return '$count з $total ${HikkaText.plural(total, 'серії', 'серій', 'серій')}';
    return total != null && total > 0 ? '${g.coverage} з $total' : '${g.coverage} сер.';
  }

  /// The line under "Озвучення" in the panel: the team, which episodes, when updated
  String _variantLine(WatchGroup g) => [g.teamLabel, _episodesOf(g), if (g.updatedAt != null) _updated(g.updatedAt!)].join(' · ');

  /// Picks a dub or subtitles: a sheet of its own (on a PC, a window) with "Озвучення · N / Субтитри · N" plates and the
  /// teams of the chosen kind; the chosen one has a yellow check, incomplete ones a small yellow dot. The choice is
  /// remembered for this title and as a favorite for others
  Future<void> _pickVariant(BuildContext context, WatchTitle t, List<WatchGroup> groups, WatchGroup current) async {
    final scale = _scale;
    final dubs = [for (final v in groups) if (!v.isSub) v];
    final subs = [for (final v in groups) if (v.isSub) v];
    var sub = current.isSub && subs.isNotEmpty;
    Widget body(BuildContext ctx) => StatefulBuilder(
          builder: (ctx, setTab) {
            final list = sub ? subs : dubs;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (dubs.isNotEmpty && subs.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.fromLTRB(18 * scale, 10 * scale, 18 * scale, 6 * scale),
                    child: Row(
                      children: [
                        _kindPlate('Озвучення · ${dubs.length}', selected: !sub, onTap: () => setTab(() => sub = false)),
                        SizedBox(width: 8 * scale),
                        _kindPlate('Субтитри · ${subs.length}', selected: sub, onTap: () => setTab(() => sub = true)),
                      ],
                    ),
                  )
                else
                  SizedBox(height: 6 * scale),
                for (final v in list) _variantRow(ctx, v, selected: v.id == current.id),
              ],
            );
          },
        );
    const title = 'Озвучення й субтитри';
    final WatchGroup? picked;
    if (AppPlatform.isMobile) {
      picked = await showAppSheet<WatchGroup>(context, scale: scale, title: title, builder: body);
    } else {
      picked = await AppDialogs.show<WatchGroup>(
        context,
        builder: (ctx) => WatchDialogFrame(scale: scale, title: title, icon: Symbols.mic_rounded, body: SettingsFont(child: body(ctx))),
      );
    }
    if (picked == null || picked.id == current.id) return;
    _store.setPreferredGroup(t.animeKey, picked.id);
    _store.setPinnedGroup(t.animeKey, picked.id);
    _store.setFavoriteChoice(choiceKeyOf(picked));
  }

  /// "Озвучення · 8" / "Субтитри · 1": the same soft plates as the filters, the chosen one lighter and outlined
  Widget _kindPlate(String label, {required bool selected, required VoidCallback onTap}) {
    final scale = _scale;
    final light = uiTheme.isLight;
    final shape = RoundedRectangleBorder(
      borderRadius: uiTheme.borderRadius(17 * scale),
      side: selected ? BorderSide(color: light ? const Color(0xFF7A7A88) : const Color(0xFF6A6A76)) : BorderSide.none,
    );
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? (light ? Colors.white : const Color(0xFF34343B)) : (light ? const Color(0xFFE6E6EE) : const Color(0xFF232328)),
        shape: shape,
        child: InkWell(
          customBorder: shape,
          splashColor: Colors.transparent,
          highlightColor: uiTheme.touchHighlight,
          hoverColor: uiTheme.hoverOverlay,
          onTap: onTap,
          child: Container(
            height: 34 * scale,
            padding: EdgeInsets.symmetric(horizontal: 14 * scale),
            alignment: Alignment.center,
            child: Text(
              label,
              style: hikkaStyle(13 * scale, weight: selected ? FontWeight.bold : FontWeight.normal, color: selected ? uiTheme.textPrimary : uiTheme.textSecondary),
            ),
          ),
        ),
      ),
    );
  }

  /// A team in the picker: the avatar, the name, and under it which episodes and when updated
  Widget _variantRow(BuildContext ctx, WatchGroup v, {required bool selected}) {
    final scale = _scale;
    final warn = episodeCheckWarns(_load.checkOf(v));
    final sub = [_episodesOf(v), if (v.updatedAt != null) _updated(v.updatedAt!)].join(' · ');
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        key: ValueKey('variant-${v.id}'),
        onTap: () => Navigator.of(ctx).pop(v),
        splashColor: Colors.transparent,
        highlightColor: uiTheme.touchHighlight,
        hoverColor: uiTheme.hoverOverlay,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 18 * scale, vertical: 9 * scale),
          child: Row(
            children: [
              SizedBox(width: 34 * scale, child: HikkaPoster(url: v.teams.isEmpty ? null : v.teams.first.avatarUrl, scale: scale, aspect: 1, radius: 17, icon: Symbols.groups_rounded)),
              SizedBox(width: 14 * scale),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(v.teamLabel, maxLines: 1, overflow: TextOverflow.ellipsis, style: hikkaStyle(15 * scale, weight: selected ? FontWeight.bold : FontWeight.normal)),
                    SizedBox(height: 2 * scale),
                    Row(
                      children: [
                        if (warn) ...[
                          Container(
                            key: ValueKey('variant-warn-${v.id}'),
                            width: 6 * scale,
                            height: 6 * scale,
                            decoration: BoxDecoration(color: watchWarnColor(), shape: BoxShape.circle),
                          ),
                          SizedBox(width: 6 * scale),
                        ],
                        Flexible(child: Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: hikkaStyle(12.5 * scale, color: uiTheme.textMuted))),
                      ],
                    ),
                  ],
                ),
              ),
              if (selected) ...[SizedBox(width: 12 * scale), LineIconView(LineIcon.check, size: 22 * scale, color: uiTheme.accentColor)],
            ],
          ),
        ),
      ),
    );
  }

  /// How many episode plates "Показати всі" shows at once: a long series (One Piece) is split into ranges
  static const int episodeRange = 100;

  /// The episode plates (in the panel, under "Серії"): six in a row, the watched ones dimmed with a check mark, the next
  /// one lighter with an outline. Until [all], two rows around the next episode; with [all], a long series shows one
  /// range of [episodeRange] at a time ("1–100", "101–200"…: [range], by default the one with the next episode), so
  /// the panel never builds a thousand plates. A tap plays the episode ([onStart] closes the panel first), holding it
  /// (on a PC, the right button) marks it watched or not
  Widget _episodeGrid(
    WatchTitle t,
    WatchGroup g,
    List<String> keys,
    Set<String> watched,
    ContinuePoint p, {
    required bool all,
    required VoidCallback onMore,
    required void Function(String key) onStart,
    int? range,
    ValueChanged<int>? onRange,
  }) {
    final scale = _scale;
    final total = g.episodes.length;
    const cols = 6, shown = 12;
    var from = 0, to = total;
    final ranges = (total + episodeRange - 1) ~/ episodeRange;
    final int current = (range ?? ((p.allWatched ? 0 : p.index) ~/ episodeRange)).clamp(0, math.max(0, ranges - 1)).toInt();
    if (!all && total > shown) {
      final row = p.allWatched ? 0 : p.index ~/ cols;
      from = math.max(0, row - 1) * cols;
      from = math.min(from, ((total - shown + cols - 1) ~/ cols) * cols);
      to = math.min(total, from + shown);
    } else if (all && ranges > 1) {
      from = current * episodeRange;
      to = math.min(total, from + episodeRange);
    }
    final gap = 8 * scale;
    final downloads = DownloadManager.instance.byEpKey(t.animeKey, g.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (all && ranges > 1)
          Padding(
            padding: EdgeInsets.only(bottom: 10 * scale),
            child: AppRangeStrip(
              scale: scale,
              labels: [
                for (int r = 0; r < ranges; r++)
                  '${episodeLabel(g.episodes[r * episodeRange], r * episodeRange)}–'
                      '${episodeLabel(g.episodes[math.min(total, (r + 1) * episodeRange) - 1], math.min(total, (r + 1) * episodeRange) - 1)}',
              ],
              selected: current,
              onSelect: (r) => onRange?.call(r),
            ),
          ),
        LayoutBuilder(
          builder: (context, c) {
            final w = ((c.maxWidth - gap * (cols - 1)) / cols).floorToDouble();
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (int i = from; i < to; i++)
                  SizedBox(
                    width: w,
                    child: _episodeButton(t, g, i, keys[i], watched: watched.contains(keys[i]), isNext: i == p.index && !p.allWatched, onStart: () => onStart(keys[i]), download: downloads[keys[i]]),
                  ),
              ],
            );
          },
        ),
        if (total > shown)
          Semantics(
            button: true,
            child: InkWell(
              onTap: onMore,
              borderRadius: uiTheme.borderRadius(6 * scale),
              splashColor: Colors.transparent,
              highlightColor: uiTheme.touchHighlight,
              hoverColor: uiTheme.hoverOverlay,
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 8 * scale),
                child: Text(all ? 'Згорнути' : 'Показати всі $total ›', style: hikkaStyle(12 * scale, color: uiTheme.textDarkMuted)),
              ),
            ),
          ),
      ],
    );
  }

  Widget _episodeButton(WatchTitle t, WatchGroup g, int i, String key, {required bool watched, required bool isNext, required VoidCallback onStart, DownloadItem? download}) {
    final scale = _scale;
    final light = uiTheme.isLight;
    // The same plates as the filters: a plain one is lighter than the panel, the next one lighter still and outlined
    final Color plain = light ? const Color(0xFFE6E6EE) : const Color(0xFF232328);
    final Color dim = light ? const Color(0xFFEFEFF4) : const Color(0xFF1A1A1D);
    final Color on = light ? const Color(0xFFFFFFFF) : const Color(0xFF34343B);
    final Color outline = light ? const Color(0xFF7A7A88) : const Color(0xFF6A6A76);
    final label = episodeLabel(g.episodes[i], i);
    final fg = isNext ? uiTheme.textPrimary : (watched ? uiTheme.textDarkMuted.withValues(alpha: 0.75) : uiTheme.textMuted);
    void toggle() {
      final total = _load.hikka.total;
      final n = WatchMarks.hikkaNumber(number: g.episodes[i].number, position: i + 1, allNumbers: g.episodes.map((x) => x.number), total: total);
      WatchMarks.set(_store, t.animeKey, key, !watched, hikkaEpisode: n, total: total);
    }
    final name = g.episodes[i].name;
    final shape = RoundedRectangleBorder(borderRadius: uiTheme.borderRadius(10 * scale), side: isNext ? BorderSide(color: outline) : BorderSide.none);
    final button = Material(
      color: isNext ? on : (watched ? dim : plain),
      shape: shape,
      child: InkWell(
        customBorder: shape,
        splashColor: Colors.transparent,
        highlightColor: uiTheme.touchHighlight,
        hoverColor: uiTheme.hoverOverlay,
        onTap: onStart,
        onLongPress: toggle,
        onSecondaryTap: toggle,
        child: SizedBox(
          height: math.max(38 * scale, AppPlatform.isMobile ? 40.0 : 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (watched) ...[LineIconView(LineIcon.check, size: 13 * scale, color: fg), SizedBox(width: 3 * scale)],
              Flexible(
                child: Text(label, maxLines: 1, overflow: TextOverflow.fade, softWrap: false, style: hikkaStyle(14 * scale, color: fg, weight: isNext ? FontWeight.bold : FontWeight.normal)),
              ),
            ],
          ),
        ),
      ),
    );
    final plate = download == null ? button : Stack(children: [button, DownloadPlateMark(item: download, scale: scale, radius: 10 * scale)]);
    return Semantics(
      button: true,
      label: 'Серія $label${watched ? ', переглянуто' : ''}${download?.isDone == true ? ', завантажено' : ''}',
      child: name.isEmpty || AppPlatform.isMobile ? plate : Tooltip(message: name, child: plate),
    );
  }

  // The "Перегляд" panel ----------------------------------------------------------

  /// The title page on the source site. In Mikai the address looks like `/anime/<id>-<name>`: we take the ready link
  /// from the Hikka data (it is exact there), and without it `/anime/<id>`
  String _siteUrl(WatchOffer offer) {
    if (offer.source.id == 'mikai') {
      final id = offer.anime.url;
      for (final l in widget.anime.external) {
        if (l.isWatch && Uri.tryParse(l.url)?.host.endsWith('mikai.me') == true && RegExp('/anime/$id(-|\$|/)').hasMatch(l.url)) return l.url;
      }
    }
    return offer.webUrl;
  }

  /// The "Перегляд" panel: the dub, the episodes (as plates right in it), quality, player, sources, and the rest
  /// (about the team, the site, a new search). On a phone it slides up from the bottom, on a PC it is a window.
  /// Choices apply at once; what leads elsewhere (playing, other windows) closes it first.
  Future<void> _openMenu(WatchTitle t, List<WatchGroup> groups) async {
    final scale = _scale;
    var all = false;
    int? range;
    Widget body(BuildContext ctx) => StatefulBuilder(
          builder: (ctx2, setPanel) => ListenableBuilder(
            listenable: Listenable.merge([_store, _load, _service.registry.prefs, DownloadManager.instance]),
            builder: (ctx3, _) => _panelBody(
              ctx,
              t,
              all: all,
              onMore: () => setPanel(() => all = !all),
              range: range,
              onRange: (r) => setPanel(() => range = r),
            ),
          ),
        );
    final String? choice;
    if (AppPlatform.isMobile) {
      choice = await showAppSheet<String>(context, scale: scale, title: 'Перегляд', builder: body);
    } else {
      choice = await AppDialogs.show<String>(
        context,
        builder: (ctx) => WatchDialogFrame(scale: scale, title: 'Перегляд', icon: Symbols.tune_rounded, body: SettingsFont(child: body(ctx))),
      );
    }
    if (!mounted || choice == null) return;
    final g = _load.defaultGroup(_store, seen: _seen);
    if (choice.startsWith('play:')) {
      if (g != null) await _play(_load.title, g, choice.substring(5));
      return;
    }
    switch (choice) {
      case 'download':
        if (g != null) await _openDownloads(g);
      case 'teams':
        if (g != null) await _showTeams(g);
      case 'sources':
        await _openSources();
      case 'refresh':
        _restart();
      case 'site':
        final offer = g == null ? null : _load.title.offerOfGroup(g);
        if (offer != null) HikkaNav.instance.openLink(_siteUrl(offer));
    }
  }

  /// «Завантажити серії» for dub [g]: the "next" ones start at the continue point
  Future<void> _openDownloads(WatchGroup g) async {
    final t = _load.title;
    final keys = episodeKeysOf(g);
    final watched = _store.watched(t.animeKey);
    final p = continuePoint(keys, watched, _store.last(t.animeKey)?.epKey, hikkaEpisodes: _hikkaEpisodes);
    final a = widget.anime;
    await DownloadPicker.show(
      context,
      scale: _scale,
      animeKey: t.animeKey,
      animeTitle: a.title(HikkaPrefs.instance.titleLang),
      poster: a.image,
      group: g,
      hikka: _load.hikka,
      watched: {
        ...watched,
        // Episodes marked on Hikka count as watched too: by number, the rest by order (as "Продовжити" does)
        for (var i = 0; i < keys.length; i++)
          if (_hikkaSeen(keys[i], i)) keys[i],
      },
      from: p.allWatched ? 0 : p.index,
    );
  }

  bool _hikkaSeen(String key, int index) {
    final h = _hikkaEpisodes;
    if (h <= 0) return false;
    final m = RegExp(r'^(\d+)(?:~\d+)?$').firstMatch(key);
    return m != null ? int.parse(m.group(1)!) <= h : index < h;
  }

  /// The line of the "Завантажити серії" row: what of the dub is on the device or on its way
  String _downloadsLine(String animeKey, WatchGroup g, int total) {
    final items = DownloadManager.instance.byEpKey(animeKey, g.id).values.toList();
    if (items.isEmpty) return 'Щоб дивитися без інтернету';
    final done = items.where((i) => i.isDone).toList();
    final active = items.where((i) => i.isActive).length;
    final failed = items.where((i) => i.state == DownloadState.failed).length;
    return [
      if (done.isNotEmpty) 'На пристрої ${done.length} з $total · ${formatBytes(done.fold(0, (a, i) => a + i.bytes))}',
      if (active > 0) 'завантажується ${DownloadText.episodes(active)}',
      if (failed > 0) 'не вдалося: $failed',
    ].join(' · ');
  }

  /// The rows of the panel. [ctx] is the panel's own context: it closes with the chosen action
  Widget _panelBody(BuildContext ctx, WatchTitle t, {required bool all, required VoidCallback onMore, int? range, ValueChanged<int>? onRange}) {
    final scale = _scale;
    final groups = _load.title.groups;
    final g = groups.isEmpty ? null : (_load.defaultGroup(_store, seen: _seen) ?? groups.first);
    final offer = g == null ? null : _load.title.offerOfGroup(g);
    final keys = g == null ? const <String>[] : episodeKeysOf(g);
    final watched = _store.watched(t.animeKey);
    final seen = keys.where(watched.contains).length;
    final prefs = _service.registry.prefs;
    final canRefresh = !_load.busy && _service.registry.enabled.isNotEmpty;
    final chevron = LineIconView(LineIcon.chevronRight, size: 18 * scale, color: uiTheme.textDarkMuted);
    void close(String action) => Navigator.of(ctx).pop(action);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 6 * scale),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (g != null) ...[
            SettingsRow(
              scale: scale,
              // Not all episodes or a numbering mismatch: a yellow sign, as in the line under the button
              leading: episodeCheckWarns(_load.checkOf(g))
                  ? _rowIcon(LineIcon.warning, color: watchWarnColor())
                  : _rowIcon(g.isSub ? LineIcon.subtitles : LineIcon.mic),
              title: g.isSub ? 'Субтитри' : 'Озвучення',
              subtitle: _variantLine(g),
              subtitleIsValue: true,
              onTap: groups.length > 1 ? () => _pickVariant(ctx, t, groups, g) : null,
            ),
            SettingsRow(
              scale: scale,
              leading: _rowIcon(LineIcon.list),
              title: 'Серії',
              subtitle: seen > 0 ? 'Переглянуто $seen з ${keys.length}' : '${keys.length} ${HikkaText.plural(keys.length, 'серія', 'серії', 'серій')}',
              subtitleIsValue: true,
              below: _episodeGrid(
                t,
                g,
                keys,
                watched,
                continuePoint(keys, watched, _store.last(t.animeKey)?.epKey, hikkaEpisodes: _hikkaEpisodes),
                all: all,
                onMore: onMore,
                onStart: (key) => close('play:$key'),
                range: range,
                onRange: onRange,
              ),
            ),
            SettingsRow(
              scale: scale,
              leading: _rowIcon(LineIcon.download),
              title: 'Завантажити серії',
              subtitle: _downloadsLine(t.animeKey, g, keys.length),
              subtitleIsValue: true,
              trailing: chevron,
              onTap: () => close('download'),
            ),
          ],
          SettingsChoiceRow<int>(
            scale: scale,
            leading: _rowIcon(LineIcon.hd),
            title: 'Якість',
            subtitle: 'Найбільша висота відео; можна змінити й під час перегляду',
            options: [for (final h in SourcePrefs.heights) (h, SourcePrefs.heightLabel(h))],
            value: prefs.maxHeight,
            onChanged: (v) => prefs.maxHeight = v,
          ),
          SettingsChoiceRow<String>(
            scale: scale,
            leading: _rowIcon(LineIcon.monitor),
            title: 'Плеєр',
            subtitle: 'Якщо серія доступна в Moon, використовується він, інакше — інший наявний',
            options: [for (final h in SourcesDialog.hosters) (h, h.isEmpty ? 'Авто' : h)],
            value: SourcesDialog.hosters.contains(prefs.hoster) ? prefs.hoster : '',
            onChanged: (v) => prefs.hoster = v,
          ),
          SettingsRow(
            scale: scale,
            leading: _rowIcon(LineIcon.sliders),
            title: 'Джерела перегляду',
            subtitle: _service.registry.enabled.isEmpty ? 'Усі вимкнено' : _service.registry.enabled.map((s) => s.name).join(', '),
            subtitleIsValue: true,
            trailing: chevron,
            onTap: () => close('sources'),
          ),
          if (g != null && g.teams.isNotEmpty)
            SettingsRow(
              scale: scale,
              leading: _rowIcon(LineIcon.groups),
              title: g.teams.length == 1 ? 'Про команду' : 'Про команди',
              subtitle: g.teams.map((x) => x.name).join(', '),
              subtitleIsValue: true,
              trailing: chevron,
              onTap: () => close('teams'),
            ),
          if (offer != null)
            SettingsRow(scale: scale, leading: _rowIcon(LineIcon.openOut), title: 'Відкрити на сайті', subtitle: _sourceName(g!.sourceId), subtitleIsValue: true, onTap: () => close('site')),
          if (canRefresh) SettingsRow(scale: scale, leading: _rowIcon(LineIcon.refresh), title: 'Оновити пошук', onTap: () => close('refresh')),
          ..._offerNotes(t).map((w) => Padding(padding: EdgeInsets.symmetric(horizontal: 12 * scale), child: w)),
        ],
      ),
    );
  }
}
