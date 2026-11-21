import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/hikka_models.dart';
import '../../models/hikka_user_models.dart';
import '../../services/hikka_api.dart';
import '../../services/hikka_auth.dart';
import '../../services/hikka_lists.dart';
import '../../services/ui_theme_service.dart';
import '../app_tones.dart';
import '../design_kit.dart';
import '../line_icons.dart';
import '../settings_kit.dart' show SettingsSwitch;
import 'hikka_account_ui.dart';
import 'hikka_common.dart';
import 'hikka_my_list_bar.dart' show HikkaListMark;

/// "Мій список" as a sheet (on a PC, a window in the middle): the status as plates with the bookmark glyphs, the watched
/// episodes with ± steps, the score as plates 1–10, "В улюблене" as a switch and "Видалити зі списку" in red.
/// Every change is saved at once; there is no "Зберегти". A guest is sent to sign in.
Future<void> showHikkaListSheet(BuildContext context, {required HikkaAnime anime, required double scale}) async {
  if (!HikkaAuth.instance.signedIn) {
    await HikkaLoginDialog.show(context, scale: scale);
    return;
  }
  await showAppSheet<void>(context, scale: scale, title: 'Мій список', builder: (ctx) => HikkaListSheetBody(anime: anime, scale: scale));
}

/// The content of the "Мій список" sheet
class HikkaListSheetBody extends StatefulWidget {
  final HikkaAnime anime;
  final double scale;

  const HikkaListSheetBody({super.key, required this.anime, required this.scale});

  @override
  State<HikkaListSheetBody> createState() => _HikkaListSheetBodyState();
}

class _HikkaListSheetBodyState extends State<HikkaListSheetBody> {
  bool _busy = false;
  String? _error;

  /// The counter shown while the ± steps are not saved yet (they are saved together a moment after the last tap)
  int? _episodes;
  Timer? _save;

  HikkaMyList get _list => HikkaMyList.instance;
  String get _slug => widget.anime.slug;
  int? get _total => (widget.anime.episodesTotal ?? 0) > 0 ? widget.anime.episodesTotal : null;

  @override
  void initState() {
    super.initState();
    _list.addListener(_changed);
    unawaited(_load());
  }

  @override
  void dispose() {
    _list.removeListener(_changed);
    // Steps that were not saved yet still go out
    if (_save?.isActive == true) {
      _save!.cancel();
      final n = _episodes;
      if (n != null) unawaited(_list.save(_slug, episodes: n, total: _total, anime: widget.anime).then<void>((_) {}, onError: (_) {}));
    }
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    try {
      await _list.entry(_slug);
      await _list.isFavourite(_slug);
    } on HikkaException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _run(Future<void> Function() job) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await job();
    } on HikkaException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
    if (mounted) setState(() => _busy = false);
  }

  void _status(HikkaWatchStatus s) {
    if (_list.cached(_slug)?.status == s) return;
    unawaited(_run(() async {
      await _list.save(_slug, status: s, total: _total, anime: widget.anime);
      _episodes = null;
    }));
  }

  void _step(int d) {
    final entry = _list.cached(_slug);
    if (entry == null) return;
    final max = _total ?? 99999;
    final next = ((_episodes ?? entry.episodes) + d).clamp(0, max).toInt();
    setState(() => _episodes = next);
    _save?.cancel();
    _save = Timer(const Duration(milliseconds: 600), () {
      unawaited(_run(() async {
        await _list.save(_slug, episodes: next, total: _total, anime: widget.anime);
        if (_episodes == next) _episodes = null;
      }));
    });
  }

  void _score(int n) {
    final current = _list.cached(_slug)?.score ?? 0;
    unawaited(_run(() => _list.save(_slug, score: n == current ? 0 : n, total: _total, anime: widget.anime)));
  }

  void _favourite() {
    final now = _list.favouriteCached(_slug) ?? false;
    unawaited(_run(() => _list.setFavourite(_slug, !now)));
  }

  Future<void> _remove() async {
    await _run(() => _list.remove(_slug));
    if (mounted && _list.cached(_slug) == null && _error == null) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.scale;
    final entry = _list.cached(_slug);
    final fav = _list.favouriteCached(_slug) ?? false;
    final inset = 18 * scale;
    final accent = uiTheme.accentColor;
    final episodes = _episodes ?? entry?.episodes ?? 0;
    final total = _total;
    Widget stepButton(LineIcon icon, VoidCallback? onTap, String label) => Semantics(
          button: true,
          label: label,
          excludeSemantics: true,
          child: Opacity(
            opacity: onTap == null ? 0.4 : 1,
            child: SizedBox(
              width: 38 * scale,
              child: AppPlate(scale: scale, label: '', expand: true, onTap: onTap, leading: (c) => LineIconView(icon, size: 18 * scale, color: c)),
            ),
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppGroupCaption(scale: scale, text: 'Статус', inset: inset, top: 12),
        Padding(
          padding: EdgeInsets.fromLTRB(inset, 6 * scale, inset, 0),
          child: Wrap(
            spacing: 8 * scale,
            runSpacing: 8 * scale,
            children: [
              for (final s in HikkaWatchStatus.values)
                AppPlate(
                  key: ValueKey('list-status-${s.name}'),
                  scale: scale,
                  label: s.label,
                  selected: entry?.status == s,
                  leading: (c) => HikkaListMark(status: s, size: 17 * scale, color: entry?.status == s ? accent : uiTheme.textMuted),
                  onTap: () => _status(s),
                ),
            ],
          ),
        ),
        if (_error != null)
          Padding(
            padding: EdgeInsets.fromLTRB(inset, 10 * scale, inset, 0),
            child: Text(_error!, style: hikkaStyle(12.5 * scale, color: AppTones.danger, height: 1.35)),
          ),
        if (entry != null) ...[
          AppGroupCaption(scale: scale, text: 'Перегляд', inset: inset),
          AppLineRow(
            scale: scale,
            inset: inset,
            icon: LineIcon.list,
            title: 'Серії',
            subtitle: total == null ? 'Переглянуто $episodes' : 'Переглянуто $episodes з $total',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                stepButton(LineIcon.minus, episodes > 0 ? () => _step(-1) : null, 'Менше серій'),
                SizedBox(
                  width: 44 * scale,
                  child: Text('$episodes', textAlign: TextAlign.center, style: hikkaStyle(15 * scale, weight: FontWeight.bold)),
                ),
                stepButton(LineIcon.plus, total == null || episodes < total ? () => _step(1) : null, 'Більше серій'),
              ],
            ),
          ),
          AppLineRow(
            scale: scale,
            inset: inset,
            icon: LineIcon.star,
            title: entry.score > 0 ? 'Оцінка: ${entry.score}' : 'Оцінка',
            below: LayoutBuilder(
              builder: (context, c) {
                final gap = 8 * scale;
                final w = ((c.maxWidth - gap * 4) / 5).floorToDouble();
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (int n = 1; n <= 10; n++)
                      SizedBox(
                        width: w,
                        child: AppPlate(key: ValueKey('list-score-$n'), scale: scale, label: '$n', expand: true, selected: entry.score == n, onTap: () => _score(n)),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
        Semantics(
          toggled: fav,
          child: AppLineRow(
            scale: scale,
            inset: inset,
            icon: LineIcon.heart,
            title: 'В улюблене',
            trailing: SettingsSwitch(scale: scale, value: fav),
            onTap: _favourite,
          ),
        ),
        if (entry != null)
          AppLineRow(
            scale: scale,
            inset: inset,
            icon: LineIcon.trash,
            title: 'Видалити зі списку',
            danger: true,
            onTap: () => unawaited(_remove()),
          ),
      ],
    );
  }
}
