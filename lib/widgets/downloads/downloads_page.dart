/// «Завантаження»: what is on the device and what is on its way. Not a file list: titles with their dub, "Продовжити"
/// right there (it plays without internet), the queue with its progress and the reason it waits, the room it takes,
/// and the downloads' settings at the bottom. A title opens [DownloadShelfPage] — its episodes, more of them, deleting.
library;

import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../services/downloads/download_manager.dart';
import '../../services/downloads/download_models.dart';
import '../../services/hikka_lists.dart';
import '../../services/hikka_nav.dart';
import '../../services/network_status.dart';
import '../../services/remote_playback.dart';
import '../../services/source_prefs.dart';
import '../../services/ui_theme_service.dart';
import '../../services/watch_models.dart';
import '../../services/watch_service.dart';
import '../../services/watch_store.dart';
import '../../utils/platform_info.dart';
import '../app_animation_kit.dart';
import '../app_tones.dart';
import '../app_ui_kit.dart';
import '../design_kit.dart';
import '../hikka/hikka_cards.dart' show HikkaProgressBar;
import '../hikka/hikka_common.dart';
import '../hikka/hikka_continue_card.dart' show HikkaContinueCard;
import '../hikka/hikka_page_kit.dart';
import '../hikka/hikka_shelf.dart' show HikkaShelf;
import '../hikka/hikka_watch_dialogs.dart' show QuietAction;
import '../line_icons.dart';
import '../settings_kit.dart';
import 'download_kit.dart';
import 'download_picker.dart';

/// Where to start a downloaded dub: the continue point when it is on the device, else the nearest downloaded episode
/// after it (the person is in the downloads, so the downloaded ones come first). (key, index, "Продовжити" or not)
(String, int, bool)? downloadsStart(DownloadManager m, DownloadGroup g, {WatchStore? store}) {
  final s = store ?? WatchService.instance.store;
  final keys = g.keys;
  final watched = s.watched(g.animeKey);
  final slug = g.animeKey.startsWith('hikka:') ? g.animeKey.substring(6) : null;
  final hikka = slug == null ? 0 : (HikkaMyList.instance.cached(slug)?.episodes ?? 0);
  final p = continuePoint(keys, watched, s.last(g.animeKey)?.epKey, hikkaEpisodes: hikka);
  final k = m.offlineStart(g.animeKey, g.id, keys, p.allWatched ? 0 : p.index, watched);
  if (k == null) return null;
  return (k, keys.indexOf(k), p.started);
}

/// Plays dub [g] from [epKey] out of the downloads (the episodes not on the device go online, as usual)
Future<void> playDownloaded(DownloadManager m, DownloadGroup g, String epKey) async {
  final launch = m.launch(g.animeKey, g.id, epKey: epKey);
  if (launch != null) await WatchLauncher.play(launch);
}

class DownloadsPage extends StatefulWidget {
  final HikkaRoute route;
  final double scale;
  final double bottomInset;

  /// For tests: its own manager
  final DownloadManager? manager;

  const DownloadsPage({super.key, required this.route, required this.scale, this.bottomInset = 0, this.manager});

  @override
  State<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends State<DownloadsPage> {
  final ScrollController _scroll = AppSmoothScrollController();
  final WatchStore _store = WatchService.instance.store;
  Future<(int, int)?>? _space;

  DownloadManager get _m => widget.manager ?? DownloadManager.instance;
  double get _scale => widget.scale;

  @override
  void initState() {
    super.initState();
    unawaited(_m.init());
    _m.addListener(_changed);
    NetworkStatus.instance.addListener(_changed);
    _store.addListener(_changed);
    _space = _m.storageInfo();
  }

  @override
  void dispose() {
    _m.removeListener(_changed);
    NetworkStatus.instance.removeListener(_changed);
    _store.removeListener(_changed);
    _scroll.dispose();
    super.dispose();
  }

  int _doneCount = -1;

  void _changed() {
    if (!mounted) return;
    // Something finished or was deleted: the free space changed
    final done = _m.done.length;
    if (done != _doneCount) {
      _doneCount = done;
      _space = _m.storageInfo();
    }
    setState(() {});
  }

  // ── Parts ─────────────────────────────────────────────────────────────────

  /// Why nothing goes (no internet, waiting for Wi-Fi, no room) with what can be done about it
  Widget? _status(double pad) {
    final scale = _scale;
    final net = NetworkStatus.instance;
    final waiting = _m.pending.any((i) => i.isActive);
    String? title;
    String? text;
    Widget? action;
    if (!net.online) {
      title = 'Немає інтернету';
      text = waiting ? 'Завантаження продовжаться, щойно він зʼявиться. Усе, що на пристрої, можна дивитися.' : 'Усе, що на пристрої, можна дивитися.';
    } else if (waiting && _m.prefs.wifiOnly && net.metered) {
      title = 'Чекаю на Wi-Fi';
      text = 'Зараз мобільний інтернет, а завантаження йдуть лише через Wi-Fi.';
      action = QuietAction(scale: scale, label: 'Завантажувати й через мобільний', onTap: () => _m.prefs = _m.prefs.copyWith(wifiOnly: false));
    } else if (waiting && _m.waitReason == 'Замало місця на пристрої') {
      title = 'Замало місця';
      text = 'Видаліть переглянуте або звільніть місце, а тоді продовжте завантаження.';
      action = QuietAction(scale: scale, label: 'Продовжити', onTap: _m.resumeAll);
    }
    if (title == null) return null;
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 6 * scale, pad, 4 * scale),
      child: Container(
        padding: EdgeInsets.fromLTRB(14 * scale, 12 * scale, 14 * scale, action == null ? 12 * scale : 4 * scale),
        decoration: BoxDecoration(color: AppTones.plate, borderRadius: uiTheme.borderRadius(14 * scale)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(top: 1 * scale),
              child: LineIconView(LineIcon.wifiOff, size: 22 * scale, color: uiTheme.textSecondary),
            ),
            SizedBox(width: 12 * scale),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: hikkaStyle(14.5 * scale, color: uiTheme.textPrimary, weight: FontWeight.w700)),
                  SizedBox(height: 3 * scale),
                  Text(text!, style: hikkaStyle(13 * scale, color: uiTheme.textMuted, height: 1.3)),
                  if (action != null) Transform.translate(offset: Offset(-10 * scale, 0), child: action),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _poster(String? url, double width) => SizedBox(width: width * _scale, child: HikkaPoster(url: url, scale: _scale, radius: 8));

  Future<void> _itemMenu(DownloadItem i, Rect anchor) async {
    final slug = i.slug;
    final pick = await showAppMenu<String>(
      context,
      scale: _scale,
      anchor: anchor,
      title: '${i.animeTitle} · ${i.title}',
      entries: [
        if (i.isActive) AppMenuEntry('pause', 'Призупинити', icon: (c) => LineIconView(LineIcon.pause, size: 18 * _scale, color: c)),
        if (!i.isActive) AppMenuEntry('resume', i.state == DownloadState.failed ? 'Спробувати ще' : 'Продовжити', icon: (c) => LineIconView(LineIcon.download, size: 18 * _scale, color: c)),
        if (slug != null) AppMenuEntry('title', 'Сторінка тайтлу', icon: (c) => LineIconView(LineIcon.openOut, size: 18 * _scale, color: c)),
        AppMenuEntry('delete', 'Скасувати й видалити', danger: true, icon: (c) => LineIconView(LineIcon.trash, size: 18 * _scale, color: c)),
      ],
    );
    switch (pick) {
      case 'pause':
        _m.pause(i.id);
      case 'resume':
        _m.resume(i.id);
      case 'title':
        HikkaNav.instance.openAnime(slug!);
      case 'delete':
        await _m.remove(i.id);
    }
  }

  /// A downloading (or waiting, paused, failed) episode: the poster, what it is, where it is, pause / go on
  Widget _queueRow(DownloadItem i, double inset) {
    final scale = _scale;
    final f = i.fraction;
    final showBar = (i.state == DownloadState.running || i.state == DownloadState.paused) && f != null && f > 0;
    return Builder(
      builder: (rowContext) => AppMediaRow(
        key: ValueKey('dl-queue-${i.id}'),
        scale: scale,
        inset: inset,
        leading: _poster(i.poster, 40),
        title: i.animeTitle,
        titleLines: 1,
        subtitle: '${i.title} · ${DownloadText.status(i, _m)}',
        subtitleLines: 2,
        gap: 12,
        below: showBar
            ? Padding(
                padding: EdgeInsets.only(top: 7 * scale, right: 4 * scale),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2 * scale),
                  child: HikkaProgressBar(value: f, height: 3 * scale),
                ),
              )
            : null,
        trailing: DownloadRing(item: i, scale: scale, onTap: () => i.isActive ? _m.pause(i.id) : _m.resume(i.id)),
        onLongPress: () => _itemMenu(i, appRectOf(rowContext)),
        onSecondaryTap: (_) => _itemMenu(i, appRectOf(rowContext)),
        onTap: i.slug == null ? null : () => _itemMenu(i, appRectOf(rowContext)),
      ),
    );
  }

  /// A title of one dub on the device: "Продовжити" plays at once, the row opens its episodes
  Widget _shelfRow(DownloadShelf s, double inset) {
    final scale = _scale;
    final g = _m.group(s.animeKey, s.groupId);
    final done = s.done;
    final start = g == null ? null : downloadsStart(_m, g, store: _store);
    final busy = s.items.where((i) => !i.isDone).length;
    final lines = [
      '${s.isSub ? 'Субтитри' : 'Озвучення'} ${s.groupLabel.replaceAll(RegExp(r'\s*\(суб\.\)\s*$'), '')}',
      [
        DownloadText.episodes(done.length),
        formatBytes(done.fold(0, (a, i) => a + i.bytes)),
        if (busy > 0) 'ще $busy у черзі',
      ].join(' · '),
    ];
    return AppMediaRow(
      key: ValueKey('dl-shelf-${s.animeKey}-${s.groupId}'),
      scale: scale,
      inset: inset,
      top: true,
      leading: _poster(s.poster, 58),
      title: s.animeTitle,
      subtitle: lines.join('\n'),
      subtitleLines: 3,
      chevron: true,
      below: g == null || start == null
          ? null
          : Padding(
              padding: EdgeInsets.only(top: 8 * scale),
              child: _ContinueChip(
                scale: scale,
                label: '${start.$3 ? 'Продовжити' : 'Дивитись'} · серія ${episodeLabel(g.episodes[start.$2], start.$2)}',
                onTap: () => playDownloaded(_m, g, start.$1),
              ),
            ),
      onTap: () => HikkaNav.instance.openDownloadShelf(s.animeKey, s.groupId),
    );
  }

  Widget _empty(double pad) {
    final scale = _scale;
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 36 * scale, pad, 12 * scale),
      child: Column(
        children: [
          LineIconView(LineIcon.downloaded, size: 46 * scale, color: uiTheme.textDarkMuted, stroke: 1.4),
          SizedBox(height: 14 * scale),
          Text('Тут будуть серії для перегляду без інтернету',
              textAlign: TextAlign.center, style: hikkaStyle(16 * scale, color: uiTheme.textPrimary, weight: FontWeight.w700)),
          SizedBox(height: 8 * scale),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 420 * scale),
            child: Text(
              'Відкрийте тайтл, натисніть «Перегляд» → «Завантажити серії». Серії завантажуються у фоні, '
              'а коли зникає інтернет — чекають і продовжують самі.',
              textAlign: TextAlign.center,
              style: hikkaStyle(13 * scale, color: uiTheme.textMuted, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }

  Widget _storage() {
    final scale = _scale;
    final used = _m.usedBytes;
    return FutureBuilder<(int, int)?>(
      future: _space,
      builder: (context, snap) {
        final s = snap.data;
        if (s == null) {
          return SettingsRow(
            scale: scale,
            leading: LineIconView(LineIcon.folder, size: 22 * scale, color: uiTheme.textSecondary),
            title: 'Серії займають ${formatBytes(used)}',
            subtitle: _m.root,
            subtitleIsValue: true,
          );
        }
        final (free, total) = s;
        final other = (total - free - used).clamp(0, total);
        return SettingsStorageBar(
          scale: scale,
          parts: [('Серії', used, uiTheme.accentColor), ('Інше', other, AppTones.plateOutline)],
          total: total,
          format: formatBytes,
          totalLabel: 'Вільно ${formatBytes(free)}',
        );
      },
    );
  }

  Future<void> _pickFolder() async {
    final dir = await FilePicker.getDirectoryPath(dialogTitle: 'Тека для завантажених серій', initialDirectory: _m.root);
    if (dir == null || dir.isEmpty) return;
    _m.prefs = _m.prefs.copyWith(folder: dir == DownloadManager.defaultRoot ? '' : dir);
    setState(() => _space = _m.storageInfo());
  }

  Future<void> _removeAll() async {
    final n = _m.items.length;
    if (n == 0) return;
    final ok = await showAppConfirm(
      context,
      scale: _scale,
      title: 'Видалити всі завантаження?',
      message: '${DownloadText.episodes(n)} (${formatBytes(_m.usedBytes)}) зникнуть із пристрою. Позначки «переглянуто» й місця перегляду залишаться.',
      action: 'Видалити',
      destructive: true,
    );
    if (ok) await _m.removeAll();
  }

  /// The quality of new downloads: a menu under the row
  Future<void> _pickHeight(BuildContext rowContext) async {
    final watchH = SourcePrefs.instance.maxHeight;
    final cur = SourcePrefs.heights.contains(_m.prefs.height) ? _m.prefs.height : 0;
    final pick = await showAppMenu<int>(
      rowContext,
      scale: _scale,
      anchor: appRectOf(rowContext),
      caption: 'Якість нових завантажень',
      entries: [
        AppMenuEntry(0, 'Як для перегляду (${SourcePrefs.heightLabel(watchH)})', selected: cur == 0),
        for (final h in SourcePrefs.heights.where((h) => h > 0)) AppMenuEntry(h, '${h}p', selected: cur == h),
      ],
    );
    if (pick != null) _m.prefs = _m.prefs.copyWith(height: pick);
  }

  List<Widget> _settings(double inset) {
    final scale = _scale;
    final p = _m.prefs;
    final watchH = SourcePrefs.instance.maxHeight;
    Widget toggle({required LineIcon icon, required String title, required String subtitle, required bool value, required ValueChanged<bool> onChanged}) =>
        Semantics(
          toggled: value,
          child: AppLineRow(
            scale: scale,
            inset: inset,
            icon: icon,
            title: title,
            subtitle: subtitle,
            trailing: SettingsSwitch(scale: scale, value: value),
            onTap: () => onChanged(!value),
          ),
        );
    return [
      AppGroupCaption(scale: scale, text: 'Налаштування завантажень', inset: inset, top: 26),
      if (AppPlatform.isMobile)
        toggle(
          icon: LineIcon.wifi,
          title: 'Лише через Wi-Fi',
          subtitle: 'Мобільний інтернет не витрачається: завантаження чекають на Wi-Fi',
          value: p.wifiOnly,
          onChanged: (v) => _m.prefs = p.copyWith(wifiOnly: v),
        ),
      Builder(
        builder: (rowContext) => AppLineRow(
          scale: scale,
          inset: inset,
          icon: LineIcon.hd,
          title: 'Якість',
          subtitle: SourcePrefs.heights.contains(p.height) && p.height > 0 ? '${p.height}p' : 'Як для перегляду (${SourcePrefs.heightLabel(watchH)})',
          chevron: true,
          onTap: () => _pickHeight(rowContext),
        ),
      ),
      toggle(
        icon: LineIcon.playlist,
        title: 'Наступна серія сама',
        subtitle: 'Коли завантажену серію переглянуто, завантажується наступна',
        value: p.autoNext,
        onChanged: (v) => _m.prefs = p.copyWith(autoNext: v),
      ),
      toggle(
        icon: LineIcon.checks,
        title: 'Видаляти переглянуті',
        subtitle: 'Переглянута завантажена серія зникає, коли вмикається інша',
        value: p.deleteWatched,
        onChanged: (v) => _m.prefs = p.copyWith(deleteWatched: v),
      ),
      if (AppPlatform.isDesktop)
        AppLineRow(
          scale: scale,
          inset: inset,
          icon: LineIcon.folder,
          title: 'Тека',
          subtitle: '${_m.root}\nУже завантажене лишається там, де є',
          trailing: QuietAction(scale: scale, label: 'Змінити', onTap: _pickFolder),
          onTap: _pickFolder,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final scale = _scale;
    final pad = HikkaLayout.sidePad(context, scale);
    final inset = pad - 6 * scale;
    final pending = _m.pending;
    final shelves = [for (final s in _m.shelves) if (s.done.isNotEmpty) s];
    final anyActive = pending.any((i) => i.isActive);
    final status = _status(pad);
    return HikkaPageFrame(
      scale: scale,
      controller: _scroll,
      bottomInset: widget.bottomInset,
      children: [
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: hikkaReadableWidth(scale) + pad * 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (status != null) status,
                if (pending.isNotEmpty) ...[
                  Row(
                    children: [
                      Expanded(child: AppGroupCaption(scale: scale, text: 'Завантажується · ${pending.length}', inset: pad, top: 14)),
                      Padding(
                        padding: EdgeInsets.only(top: 10 * scale, right: pad - 10 * scale),
                        child: QuietAction(
                          scale: scale,
                          label: anyActive ? 'Призупинити все' : 'Продовжити все',
                          onTap: anyActive ? _m.pauseAll : _m.resumeAll,
                        ),
                      ),
                    ],
                  ),
                  for (final i in pending) _queueRow(i, inset),
                ],
                if (shelves.isNotEmpty) ...[
                  AppGroupCaption(scale: scale, text: 'На пристрої', inset: pad, top: pending.isEmpty ? 14 : 24),
                  for (final s in shelves) _shelfRow(s, inset),
                ],
                if (pending.isEmpty && shelves.isEmpty) _empty(pad),
                if (_m.items.isNotEmpty || AppPlatform.isMobile) ...[
                  AppGroupCaption(scale: scale, text: 'Місце', inset: pad, top: 26),
                  _storage(),
                ],
                ..._settings(pad),
                if (_m.items.isNotEmpty)
                  AppLineRow(
                    scale: scale,
                    inset: pad,
                    icon: LineIcon.trash,
                    danger: true,
                    title: 'Видалити всі завантаження',
                    onTap: _removeAll,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A small "▶ Продовжити · серія 3" plate under a title: plays from the device at once
class _ContinueChip extends StatelessWidget {
  final double scale;
  final String label;
  final VoidCallback onTap;

  const _ContinueChip({required this.scale, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final accent = uiTheme.accentColor;
    final shape = RoundedRectangleBorder(borderRadius: uiTheme.borderRadius(18 * scale));
    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        color: AppTones.accentWash,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          onTap: onTap,
          splashColor: Colors.transparent,
          highlightColor: uiTheme.touchHighlight,
          hoverColor: uiTheme.hoverOverlay,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: AppPlatform.isMobile ? 36 : 32 * scale),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 6 * scale),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LineIconView(LineIcon.play, size: 13 * scale, color: accent),
                  SizedBox(width: 7 * scale),
                  Text(label, style: hikkaStyle(13 * scale, color: accent, weight: FontWeight.w700)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One title's downloads in one dub: "Продовжити" and "Ще серії" up top, then its episodes — play, pause, delete
class DownloadShelfPage extends StatefulWidget {
  final HikkaRoute route;
  final double scale;
  final double bottomInset;
  final DownloadManager? manager;

  const DownloadShelfPage({super.key, required this.route, required this.scale, this.bottomInset = 0, this.manager});

  @override
  State<DownloadShelfPage> createState() => _DownloadShelfPageState();
}

class _DownloadShelfPageState extends State<DownloadShelfPage> {
  final ScrollController _scroll = AppSmoothScrollController();
  final WatchStore _store = WatchService.instance.store;

  DownloadManager get _m => widget.manager ?? DownloadManager.instance;
  double get _scale => widget.scale;

  @override
  void initState() {
    super.initState();
    unawaited(_m.init());
    _m.addListener(_changed);
    _store.addListener(_changed);
  }

  @override
  void dispose() {
    _m.removeListener(_changed);
    _store.removeListener(_changed);
    _scroll.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _more(DownloadGroup g) async {
    final keys = g.keys;
    final store = _store;
    final watched = store.watched(g.animeKey);
    final p = continuePoint(keys, watched, store.last(g.animeKey)?.epKey);
    await DownloadPicker.show(
      context,
      scale: _scale,
      animeKey: g.animeKey,
      animeTitle: g.animeTitle,
      poster: g.poster,
      group: g.watchGroup,
      hikka: g.hikka,
      watched: watched,
      from: p.allWatched ? 0 : p.index,
      manager: _m,
    );
  }

  Future<void> _delete(DownloadItem i) async {
    final ok = await showAppConfirm(
      context,
      scale: _scale,
      title: 'Видалити ${i.title.toLowerCase()}?',
      message: '${formatBytes(i.bytes)} звільниться. Позначка «переглянуто» й місце перегляду залишаться.',
      action: 'Видалити',
      destructive: true,
    );
    if (ok) await _m.remove(i.id);
  }

  Future<void> _deleteAll(DownloadGroup g, List<DownloadItem> items) async {
    final ok = await showAppConfirm(
      context,
      scale: _scale,
      title: 'Видалити всі серії «${g.animeTitle}»?',
      message: '${DownloadText.episodes(items.length)} (${formatBytes(items.fold(0, (a, i) => a + i.bytes))}) зникнуть із пристрою.',
      action: 'Видалити',
      destructive: true,
    );
    if (!ok) return;
    await _m.removeGroup(g.animeKey, g.id);
    if (mounted) HikkaNav.instance.back();
  }

  /// The episode's number on a plate like in "Перегляд": dim with a check when watched
  Widget _plate(String label, bool watched) {
    final scale = _scale;
    return Container(
      width: 46 * scale,
      height: 40 * scale,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: watched ? AppTones.menu : AppTones.plate, borderRadius: uiTheme.borderRadius(10 * scale)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (watched) ...[LineIconView(LineIcon.check, size: 12 * scale, color: uiTheme.textDarkMuted), SizedBox(width: 2 * scale)],
          Flexible(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                style: hikkaStyle(14 * scale, color: watched ? uiTheme.textDarkMuted : uiTheme.textPrimary, weight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _episodeRow(DownloadGroup g, DownloadItem i, double inset, Set<String> watched) {
    final scale = _scale;
    final seen = watched.contains(i.epKey);
    final index = i.order.clamp(0, g.episodes.isEmpty ? 0 : g.episodes.length - 1);
    final label = g.episodes.isEmpty ? i.epKey : episodeLabel(g.episodes[index], index);
    final f = i.fraction;
    final showBar = !i.isDone && (i.state == DownloadState.running || i.state == DownloadState.paused) && f != null && f > 0;
    final status = DownloadText.status(i, _m);
    return Builder(
      builder: (rowContext) => AppMediaRow(
        key: ValueKey('dl-ep-${i.id}'),
        scale: scale,
        inset: inset,
        leading: _plate(label, seen),
        title: i.title,
        subtitle: i.isDone && seen ? '$status · переглянуто' : status,
        gap: 12,
        below: showBar
            ? Padding(
                padding: EdgeInsets.only(top: 7 * scale, right: 4 * scale),
                child: ClipRRect(borderRadius: BorderRadius.circular(2 * scale), child: HikkaProgressBar(value: f, height: 3 * scale)),
              )
            : null,
        trailing: i.isDone
            ? HikkaLineButton(scale: scale, icon: LineIcon.trash, tooltip: 'Видалити', iconSize: 20, onTap: () => _delete(i))
            : DownloadRing(item: i, scale: scale, onTap: () => i.isActive ? _m.pause(i.id) : _m.resume(i.id)),
        onTap: i.isDone ? () => playDownloaded(_m, g, i.epKey) : null,
        onLongPress: () => _delete(i),
        onSecondaryTap: (_) => _delete(i),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scale = _scale;
    final pad = HikkaLayout.sidePad(context, scale);
    final inset = pad - 6 * scale;
    final (animeKey, groupId) = HikkaNav.shelfOf(widget.route);
    final g = _m.group(animeKey, groupId);
    final items = [for (final i in _m.items) if (i.animeKey == animeKey && i.groupId == groupId) i]..sort((a, b) => a.order.compareTo(b.order));
    if (g == null || items.isEmpty) {
      return HikkaPageFrame(
        scale: scale,
        controller: _scroll,
        bottomInset: widget.bottomInset,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(pad, 30 * scale, pad, 0),
            child: Text(_m.ready ? 'Цих серій на пристрої вже немає.' : 'Завантажуємо…', style: hikkaStyle(14 * scale, color: uiTheme.textMuted)),
          ),
        ],
      );
    }
    final watched = _store.watched(animeKey);
    final done = [for (final i in items) if (i.isDone) i];
    final start = downloadsStart(_m, g, store: _store);
    final slug = items.first.slug;
    return HikkaPageFrame(
      scale: scale,
      controller: _scroll,
      bottomInset: widget.bottomInset,
      children: [
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: hikkaReadableWidth(scale) + pad * 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(pad, 6 * scale, pad, 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 84 * scale, child: HikkaPoster(url: g.poster, scale: scale, radius: 10)),
                      SizedBox(width: 16 * scale),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(g.animeTitle, maxLines: 3, overflow: TextOverflow.ellipsis, style: hikkaStyle(19 * scale, color: uiTheme.textPrimary, weight: FontWeight.w700, height: 1.2)),
                            SizedBox(height: 6 * scale),
                            Text('${g.isSub ? 'Субтитри' : 'Озвучення'} ${g.watchGroup.teamLabel}', style: hikkaStyle(13.5 * scale, color: uiTheme.textSecondary)),
                            SizedBox(height: 3 * scale),
                            Text(
                              'На пристрої ${done.length} з ${g.episodes.length} · ${formatBytes(done.fold(0, (a, i) => a + i.bytes))}',
                              style: hikkaStyle(13 * scale, color: uiTheme.textMuted),
                            ),
                            if (slug != null)
                              Transform.translate(
                                offset: Offset(-10 * scale, 2 * scale),
                                child: QuietAction(scale: scale, label: 'Сторінка тайтлу', onTap: () => HikkaNav.instance.openAnime(slug)),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (start != null)
                  Padding(
                    padding: EdgeInsets.fromLTRB(pad, 16 * scale, pad, 2 * scale),
                    child: AppAccentButton(
                      scale: scale,
                      solid: true,
                      compact: true,
                      expand: true,
                      icon: Symbols.play_arrow_rounded,
                      label: '${start.$3 ? 'Продовжити' : 'Дивитись'} · серія ${episodeLabel(g.episodes[start.$2], start.$2)}',
                      onTap: () => playDownloaded(_m, g, start.$1),
                    ),
                  ),
                SizedBox(height: 6 * scale),
                AppLineRow(
                  scale: scale,
                  inset: pad,
                  icon: LineIcon.download,
                  title: 'Завантажити ще серії',
                  subtitle: '${g.episodes.length - items.length} з ${g.episodes.length} ще не на пристрої',
                  chevron: true,
                  onTap: () => _more(g),
                ),
                AppGroupCaption(scale: scale, text: 'Серії', inset: pad, top: 14),
                for (final i in items) _episodeRow(g, i, inset, watched),
                SizedBox(height: 8 * scale),
                AppLineRow(
                  scale: scale,
                  inset: pad,
                  icon: LineIcon.trash,
                  danger: true,
                  title: 'Видалити всі серії',
                  onTap: () => _deleteAll(g, items),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// "Завантажене" on "Головна": the titles on the device, each one continues at a tap — without internet too. Hidden
/// while nothing is downloaded. Offline it stands first and says so
class DownloadsHomeShelf extends StatelessWidget {
  final double scale;
  final double pad;

  const DownloadsHomeShelf({super.key, required this.scale, required this.pad});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([DownloadManager.instance, WatchService.instance.store, NetworkStatus.instance]),
      builder: (context, _) {
        final m = DownloadManager.instance;
        final shelves = [for (final s in m.shelves) if (s.done.isNotEmpty) s];
        if (shelves.isEmpty) return const SizedBox.shrink();
        return HikkaShelf(
          key: const ValueKey('home-downloads'),
          scale: scale,
          pad: pad,
          title: 'Завантажене',
          subtitle: NetworkStatus.instance.online ? null : 'Немає інтернету — це можна дивитися',
          count: shelves.length,
          cardWidth: HikkaContinueCard.width(scale),
          cardHeight: HikkaContinueCard.height(scale),
          itemBuilder: (context, i) => DownloadContinueCard(shelf: shelves[i], scale: scale),
          onMore: HikkaNav.instance.openDownloads,
        );
      },
    );
  }
}

/// A downloaded title in the look of "Продовжити перегляд": the poster, which episode is next and in which dub, how
/// many are on the device; a tap plays from the device, holding it opens the title's downloads
class DownloadContinueCard extends StatelessWidget {
  final DownloadShelf shelf;
  final double scale;

  const DownloadContinueCard({super.key, required this.shelf, required this.scale});

  @override
  Widget build(BuildContext context) {
    final m = DownloadManager.instance;
    final s = shelf;
    final g = m.group(s.animeKey, s.groupId);
    final start = g == null ? null : downloadsStart(m, g);
    final episode = g == null || start == null ? null : 'Серія ${episodeLabel(g.episodes[start.$2], start.$2)}';
    final team = s.groupLabel.replaceAll(RegExp(r'\s*\(суб\.\)\s*$'), '');
    final sub = [if (episode != null) episode, if (team.isNotEmpty) team].join(' · ');
    final r = uiTheme.borderRadius(14 * scale);
    void open() => HikkaNav.instance.openDownloadShelf(s.animeKey, s.groupId);
    return Semantics(
      button: true,
      label: '${start?.$3 == true ? 'Продовжити' : 'Дивитись'}: ${s.animeTitle}. $sub',
      excludeSemantics: true,
      child: Material(
        color: uiTheme.bgSurface,
        shape: RoundedRectangleBorder(borderRadius: r, side: BorderSide(color: uiTheme.borderSubtle)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: g == null || start == null ? open : () => playDownloaded(m, g, start.$1),
          onLongPress: open,
          onSecondaryTap: open,
          splashColor: Colors.transparent,
          highlightColor: uiTheme.touchHighlight,
          hoverColor: uiTheme.hoverOverlay,
          child: Padding(
            padding: EdgeInsets.all(8 * scale),
            child: Row(
              children: [
                SizedBox(
                  width: 56 * scale,
                  height: 80 * scale,
                  child: HikkaPoster(url: s.poster, scale: scale, radius: 9, aspect: 56 / 80, icon: Symbols.movie_rounded, border: false),
                ),
                SizedBox(width: 12 * scale),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(s.animeTitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: hikkaStyle(14 * scale, weight: FontWeight.bold, height: 1.25)),
                      if (sub.isNotEmpty) ...[
                        SizedBox(height: 4 * scale),
                        Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: hikkaStyle(12 * scale, color: uiTheme.textMuted)),
                      ],
                      SizedBox(height: 3 * scale),
                      Row(
                        children: [
                          LineIconView(LineIcon.download, size: 12 * scale, color: uiTheme.accentColor, stroke: 2),
                          SizedBox(width: 4 * scale),
                          Flexible(
                            child: Text('${DownloadText.episodes(s.done.length)} на пристрої',
                                maxLines: 1, overflow: TextOverflow.ellipsis, style: hikkaStyle(11.5 * scale, weight: FontWeight.w600, color: uiTheme.accentColor)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 8 * scale),
                Container(
                  width: 36 * scale,
                  height: 36 * scale,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: AppTones.playCircle),
                  alignment: Alignment.center,
                  child: LineIconView(LineIcon.play, size: 14 * scale, color: uiTheme.isLight ? uiTheme.textPrimary : const Color(0xFFEEEEEE)),
                ),
                SizedBox(width: 4 * scale),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A strip over the bottom navigation while there is no internet, like other apps have: what happened and the way to
/// what still works — the downloads. Slides away when the internet returns
class OfflineStrip extends StatelessWidget {
  final double scale;

  const OfflineStrip({super.key, required this.scale});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([NetworkStatus.instance, DownloadManager.instance, HikkaNav.instance]),
      builder: (context, _) {
        final offline = !NetworkStatus.instance.online;
        final m = DownloadManager.instance;
        final onDownloads = HikkaNav.instance.top?.kind == HikkaRouteKind.downloads;
        final canGo = m.done.isNotEmpty && !onDownloads;
        return AppVerticalCollapse(
          isExpanded: offline,
          child: Container(
            key: const ValueKey('offline-strip'),
            decoration: BoxDecoration(
              color: AppTones.plate,
              border: Border(top: BorderSide(color: uiTheme.borderSubtle)),
            ),
            padding: EdgeInsets.symmetric(horizontal: 16 * scale),
            constraints: BoxConstraints(minHeight: AppPlatform.isMobile ? 44 : 38 * scale),
            child: Row(
              children: [
                LineIconView(LineIcon.wifiOff, size: 18 * scale, color: uiTheme.textSecondary),
                SizedBox(width: 10 * scale),
                Expanded(
                  child: Text(
                    canGo || m.done.isEmpty ? 'Немає інтернету' : 'Немає інтернету · завантажене можна дивитися',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: hikkaStyle(13 * scale, color: uiTheme.textSecondary),
                  ),
                ),
                if (canGo)
                  TextButton(
                    onPressed: HikkaNav.instance.openDownloads,
                    style: TextButton.styleFrom(
                      foregroundColor: uiTheme.accentColor,
                      padding: EdgeInsets.symmetric(horizontal: 10 * scale),
                      minimumSize: Size(0, AppPlatform.isMobile ? 40 : 30 * scale),
                    ),
                    child: Text('Завантажене', style: hikkaStyle(13 * scale, color: uiTheme.accentColor, weight: FontWeight.w700)),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
