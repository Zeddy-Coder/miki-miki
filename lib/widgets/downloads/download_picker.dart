/// «Завантажити серії»: which episodes of the dub to keep on the device. The usual choices are one tap away — the next
/// few, every unwatched one, all of them — and any set can be picked on the same plates as in the "Перегляд" panel.
/// Below: the quality, roughly how much room it takes and how much there is, and when it starts (Wi-Fi, no internet).
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../services/downloads/download_manager.dart';
import '../../services/downloads/download_models.dart';
import '../../services/episode_check.dart' show HikkaEpisodeInfo;
import '../../services/network_status.dart';
import '../../services/source_prefs.dart';
import '../../services/ui_theme_service.dart';
import '../../services/watch_models.dart';
import '../../utils/platform_info.dart';
import '../app_animation_kit.dart';
import '../app_tones.dart';
import '../app_ui_kit.dart';
import '../design_kit.dart';
import '../hikka/hikka_common.dart';
import '../hikka/hikka_watch_dialogs.dart' show QuietAction, WatchDialogFrame;
import '../line_icons.dart';
import '../settings_kit.dart';
import 'download_kit.dart';

enum _Pick { next, unwatched, all, manual }

class DownloadPicker {
  DownloadPicker._();

  /// How many episodes "the next few" are
  static const int nextCount = 3;

  /// Opens the picker for dub [group] of [animeKey]. [from] is the continue point (the "next" ones start there),
  /// [watched] the episode keys already watched. Returns how many episodes were queued (0: none, or closed)
  static Future<int> show(
    BuildContext context, {
    required double scale,
    required String animeKey,
    required String animeTitle,
    String? poster,
    required WatchGroup group,
    HikkaEpisodeInfo? hikka,
    required Set<String> watched,
    required int from,
    DownloadManager? manager,
  }) async {
    final m = manager ?? DownloadManager.instance;
    await m.init();
    if (!context.mounted) return 0;
    Widget body(BuildContext ctx) => _PickerBody(
          scale: scale,
          manager: m,
          animeKey: animeKey,
          group: group,
          watched: watched,
          from: from,
          onDone: (indexes) async {
            final n = await m.enqueue(animeKey: animeKey, animeTitle: animeTitle, poster: poster, group: group, indexes: indexes, hikka: hikka);
            if (ctx.mounted) Navigator.of(ctx).pop(n);
          },
        );
    final int? n;
    if (AppPlatform.isMobile) {
      n = await showAppSheet<int>(context, scale: scale, title: 'Завантажити серії', builder: body);
    } else {
      n = await AppDialogs.show<int>(
        context,
        builder: (ctx) => WatchDialogFrame(scale: scale, title: 'Завантажити серії', icon: Symbols.download_rounded, body: SettingsFont(child: body(ctx))),
      );
    }
    return n ?? 0;
  }

  /// "5–7", "1–3, 5, 8–9": episode labels of [indexes] (sorted) with runs joined
  static String ranges(WatchGroup g, List<int> indexes) {
    if (indexes.isEmpty) return '';
    final out = <String>[];
    var start = indexes.first;
    var prev = start;
    void flush() {
      final a = episodeLabel(g.episodes[start], start);
      out.add(start == prev ? a : '$a–${episodeLabel(g.episodes[prev], prev)}');
    }
    for (final i in indexes.skip(1)) {
      if (i == prev + 1) {
        prev = i;
        continue;
      }
      flush();
      start = prev = i;
    }
    flush();
    final text = out.join(', ');
    return out.length > 4 ? '${out.take(4).join(', ')}…' : text;
  }

  /// A rough size of one episode: the average of what this dub (or anything at this height) already took, otherwise
  /// a typical 24-minute episode of that height
  static int estimate(DownloadManager m, String animeKey, String groupId, int height) {
    final mine = [for (final i in m.done) if (i.animeKey == animeKey && i.groupId == groupId && i.bytes > 0) i.bytes];
    final same = [for (final i in m.done) if (i.height == height && i.bytes > 0) i.bytes];
    final pool = mine.isNotEmpty ? mine : same;
    if (pool.isNotEmpty) return pool.reduce((a, b) => a + b) ~/ pool.length;
    const mb = 1024 * 1024;
    return switch (height) {
      > 0 && <= 480 => 150 * mb,
      > 480 && <= 720 => 280 * mb,
      _ => 480 * mb,
    };
  }
}

class _PickerBody extends StatefulWidget {
  final double scale;
  final DownloadManager manager;
  final String animeKey;
  final WatchGroup group;
  final Set<String> watched;
  final int from;
  final Future<void> Function(List<int> indexes) onDone;

  const _PickerBody({
    required this.scale,
    required this.manager,
    required this.animeKey,
    required this.group,
    required this.watched,
    required this.from,
    required this.onDone,
  });

  @override
  State<_PickerBody> createState() => _PickerBodyState();
}

class _PickerBodyState extends State<_PickerBody> {
  late final List<String> _keys = episodeKeysOf(widget.group);
  _Pick? _pick;
  final Set<int> _manual = {};
  bool _busy = false;

  /// A long series shows one range of [_range] plates at a time (as the "Перегляд" panel does)
  static const int _rangeSize = 100;
  int? _range;
  Future<(int, int)?>? _space;

  double get _scale => widget.scale;
  DownloadManager get _m => widget.manager;

  @override
  void initState() {
    super.initState();
    _space = _m.storageInfo();
    _m.addListener(_changed);
    NetworkStatus.instance.addListener(_changed);
  }

  @override
  void dispose() {
    _m.removeListener(_changed);
    NetworkStatus.instance.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Map<String, DownloadItem> get _have => _m.byEpKey(widget.animeKey, widget.group.id);

  /// Episodes not on the device (and not queued)
  List<int> get _free {
    final have = _have;
    return [for (var i = 0; i < _keys.length; i++) if (!have.containsKey(_keys[i])) i];
  }

  List<int> _of(_Pick p) {
    final free = _free;
    switch (p) {
      case _Pick.next:
        final start = widget.from.clamp(0, math.max(0, _keys.length - 1));
        return [for (final i in free) if (i >= start) i].take(DownloadPicker.nextCount).toList();
      case _Pick.unwatched:
        return [for (final i in free) if (!widget.watched.contains(_keys[i])) i];
      case _Pick.all:
        return free;
      case _Pick.manual:
        return [for (final i in free) if (_manual.contains(i)) i];
    }
  }

  /// The choice offered first: the next few when there are any, else whatever is left
  _Pick get _current {
    final p = _pick;
    if (p != null) return p;
    if (_of(_Pick.next).isNotEmpty) return _Pick.next;
    final unwatched = _of(_Pick.unwatched);
    final all = _of(_Pick.all);
    // "All unwatched" is hidden when it is the same as "all"
    if (unwatched.isNotEmpty && unwatched.length != all.length) return _Pick.unwatched;
    return all.isNotEmpty ? _Pick.all : _Pick.manual;
  }

  int get _height {
    final h = _m.prefs.height;
    return h > 0 ? h : SourcePrefs.instance.maxHeight;
  }

  Future<void> _go() async {
    final list = _of(_current);
    if (list.isEmpty || _busy) return;
    setState(() => _busy = true);
    await widget.onDone(list);
    if (mounted) setState(() => _busy = false);
  }

  Widget _radio(_Pick p, String title, List<int> list, {String? empty}) {
    final g = widget.group;
    final n = list.length;
    final subtitle = n == 0
        ? (empty ?? 'Усе вже завантажено')
        : '${DownloadText.episodes(n)}: ${DownloadPicker.ranges(g, list)}';
    return SettingsRadioRow(
      scale: _scale,
      title: title,
      subtitle: subtitle,
      selected: _current == p,
      onTap: () => setState(() => _pick = p),
    );
  }

  /// The plates to pick by hand: the same look as in "Перегляд"; those on the device are marked and cannot be picked
  Widget _grid() {
    final scale = _scale;
    final g = widget.group;
    final have = _have;
    const cols = 6;
    final gap = 8 * scale;
    final light = uiTheme.isLight;
    final Color plain = light ? const Color(0xFFE6E6EE) : const Color(0xFF232328);
    final Color dim = light ? const Color(0xFFEFEFF4) : const Color(0xFF1A1A1D);
    final total = _keys.length;
    final ranges = (total + _rangeSize - 1) ~/ _rangeSize;
    final int current = (_range ?? (widget.from ~/ _rangeSize)).clamp(0, math.max(0, ranges - 1)).toInt();
    final from = ranges > 1 ? current * _rangeSize : 0;
    final to = ranges > 1 ? math.min(total, from + _rangeSize) : total;
    String label(int i) => episodeLabel(g.episodes[i], i);
    return Padding(
      padding: EdgeInsets.fromLTRB(settingsTextInset * scale, 2 * scale, 12 * scale, 8 * scale),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (ranges > 1)
            Padding(
              padding: EdgeInsets.only(bottom: 10 * scale),
              child: AppRangeStrip(
                scale: scale,
                labels: [for (int r = 0; r < ranges; r++) '${label(r * _rangeSize)}–${label(math.min(total, (r + 1) * _rangeSize) - 1)}'],
                selected: current,
                onSelect: (r) => setState(() => _range = r),
              ),
            ),
          LayoutBuilder(
            builder: (context, c) {
              final w = ((c.maxWidth - gap * (cols - 1)) / cols).floorToDouble();
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (var i = from; i < to; i++)
                    SizedBox(
                      width: w,
                      child: _plate(i, g, have[_keys[i]], plain: plain, dim: dim),
                    ),
                ],
              );
            },
          ),
          SizedBox(height: 8 * scale),
          Row(
            children: [
              QuietAction(
                scale: scale,
                label: ranges > 1 ? 'Вибрати всі ${label(from)}–${label(to - 1)}' : 'Вибрати всі',
                onTap: () => setState(() => _manual.addAll([for (final i in _free) if (i >= from && i < to) i])),
              ),
              QuietAction(scale: scale, label: 'Зняти вибір', onTap: () => setState(_manual.clear)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _plate(int i, WatchGroup g, DownloadItem? item, {required Color plain, required Color dim}) {
    final scale = _scale;
    final on = _manual.contains(i);
    final watched = widget.watched.contains(_keys[i]);
    final accent = uiTheme.accentColor;
    final label = episodeLabel(g.episodes[i], i);
    final radius = 10 * scale;
    final shape = RoundedRectangleBorder(
      borderRadius: uiTheme.borderRadius(radius),
      side: on ? BorderSide(color: accent, width: 1.6) : BorderSide.none,
    );
    final fg = item != null ? uiTheme.textDarkMuted : (on ? uiTheme.textPrimary : (watched ? uiTheme.textDarkMuted : uiTheme.textMuted));
    return Semantics(
      button: item == null,
      selected: on,
      label: 'Серія $label${item != null ? ', уже завантажено' : ''}',
      child: Stack(
        children: [
          Material(
            color: on ? AppTones.accentWash : (item != null || watched ? dim : plain),
            shape: shape,
            child: InkWell(
              customBorder: shape,
              splashColor: Colors.transparent,
              highlightColor: uiTheme.touchHighlight,
              hoverColor: uiTheme.hoverOverlay,
              onTap: item != null
                  ? null
                  : () => setState(() {
                        _pick = _Pick.manual;
                        if (!_manual.remove(i)) _manual.add(i);
                      }),
              child: SizedBox(
                height: math.max(38 * scale, AppPlatform.isMobile ? 40.0 : 0),
                child: Center(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                      style: hikkaStyle(14 * scale, color: fg, weight: on ? FontWeight.bold : FontWeight.normal)),
                ),
              ),
            ),
          ),
          if (item != null) DownloadPlateMark(item: item, scale: scale, radius: radius),
        ],
      ),
    );
  }

  /// "Орієнтовно 1,4 ГБ · вільно 21 ГБ" and when it starts
  Widget _footnote(int count) {
    final scale = _scale;
    final net = NetworkStatus.instance;
    final per = DownloadPicker.estimate(_m, widget.animeKey, widget.group.id, _height);
    final when = !net.online
        ? 'Немає інтернету: завантаження почнеться, щойно він зʼявиться.'
        : (_m.prefs.wifiOnly && net.metered ? 'Зараз мобільний інтернет: завантаження почнеться через Wi-Fi (це можна змінити в налаштуваннях завантажень).' : null);
    return FutureBuilder<(int, int)?>(
      future: _space,
      builder: (context, snap) {
        final free = snap.data?.$1;
        final need = per * count;
        final tight = free != null && count > 0 && need > free;
        final line = [
          if (count > 0) 'Орієнтовно ${formatBytes(need)}',
          if (free != null) 'вільно ${formatBytes(free)}',
        ].join(' · ');
        return Padding(
          padding: EdgeInsets.fromLTRB(12 * scale, 6 * scale, 12 * scale, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (line.isNotEmpty)
                Text(line, style: hikkaStyle(12.5 * scale, color: tight ? AppTones.danger : uiTheme.textMuted)),
              if (tight)
                Padding(
                  padding: EdgeInsets.only(top: 4 * scale),
                  child: Text('Схоже, місця не вистачить на всі серії.', style: hikkaStyle(12.5 * scale, color: AppTones.danger)),
                ),
              if (when != null)
                Padding(
                  padding: EdgeInsets.only(top: 4 * scale),
                  child: Text(when, style: hikkaStyle(12.5 * scale, color: uiTheme.textMuted)),
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final scale = _scale;
    final g = widget.group;
    final next = _of(_Pick.next);
    final unwatched = _of(_Pick.unwatched);
    final all = _of(_Pick.all);
    final chosen = _of(_current);
    final count = chosen.length;
    final watchH = SourcePrefs.instance.maxHeight;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 6 * scale),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(12 * scale, 0, 12 * scale, 6 * scale),
            child: Text(
              '${g.isSub ? 'Субтитри' : 'Озвучення'} ${g.teamLabel} · на пристрої ${_m.byEpKey(widget.animeKey, g.id).values.where((i) => i.isDone).length} з ${_keys.length}',
              style: hikkaStyle(13 * scale, color: uiTheme.textMuted),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          _radio(_Pick.next, next.length == 1 ? 'Наступна серія' : 'Наступні ${next.isEmpty ? DownloadPicker.nextCount : next.length} серії', next, empty: 'Наступні серії вже завантажено'),
          // Nothing watched yet (or the watched ones are on the device): "all unwatched" would repeat "all"
          if (unwatched.length != all.length) _radio(_Pick.unwatched, 'Усі непереглянуті', unwatched, empty: 'Непереглянуті вже завантажено'),
          _radio(_Pick.all, 'Усі серії', all),
          SettingsRadioRow(
            scale: scale,
            title: 'Вибрати вручну',
            subtitle: _current == _Pick.manual
                ? (chosen.isEmpty ? 'Позначте серії нижче' : '${DownloadText.episodes(chosen.length)}: ${DownloadPicker.ranges(g, chosen)}')
                : 'Будь-які серії на ваш вибір',
            selected: _current == _Pick.manual,
            onTap: () => setState(() => _pick = _Pick.manual),
          ),
          AppVerticalCollapse(isExpanded: _current == _Pick.manual, child: _grid()),
          SettingsChoiceRow<int>(
            scale: scale,
            leading: LineIconView(LineIcon.hd, size: 22 * scale, color: uiTheme.textSecondary),
            title: 'Якість',
            subtitle: 'Найбільша висота; якщо такої немає, найближча нижча',
            options: [
              (0, 'Як для перегляду (${SourcePrefs.heightLabel(watchH)})'),
              for (final h in SourcePrefs.heights.where((h) => h > 0)) (h, '${h}p'),
            ],
            value: SourcePrefs.heights.contains(_m.prefs.height) ? _m.prefs.height : 0,
            onChanged: (v) => _m.prefs = _m.prefs.copyWith(height: v),
          ),
          _footnote(count),
          Padding(
            padding: EdgeInsets.fromLTRB(12 * scale, 14 * scale, 12 * scale, 8 * scale),
            child: Opacity(
              opacity: count == 0 || _busy ? 0.45 : 1,
              child: AppAccentButton(
                scale: scale,
                solid: true,
                expand: true,
                icon: Symbols.download_rounded,
                label: count == 0 ? 'Нічого не вибрано' : 'Завантажити ${DownloadText.episodes(count)}',
                onTap: _go,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
