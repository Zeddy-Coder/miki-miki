import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../models/hikka_models.dart';
import '../../models/hikka_user_models.dart';
import '../../services/hikka_api.dart';
import '../../services/hikka_auth.dart';
import '../../services/hikka_lists.dart';
import '../../services/ui_theme_service.dart';
import '../../utils/platform_info.dart';
import '../app_animation_kit.dart';
import '../app_ui_kit.dart';
import 'hikka_account_ui.dart';
import 'hikka_common.dart';
import 'hikka_watch_dialogs.dart';

const Color _errorColor = Color(0xFFE57373);

/// Значок статусу у списках (спільний для сторінки аніме й вкладки «Списки»)
IconData hikkaStatusIcon(HikkaWatchStatus s) => switch (s) {
      HikkaWatchStatus.watching => Symbols.play_circle_rounded,
      HikkaWatchStatus.planned => Symbols.bookmark_rounded,
      HikkaWatchStatus.completed => Symbols.check_circle_rounded,
      HikkaWatchStatus.onHold => Symbols.pause_circle_rounded,
      HikkaWatchStatus.dropped => Symbols.cancel_rounded,
    };

/// Колір статусу: дивлюсь — блакитний, у планах — фіолетовий, переглянуто — зелений, відкладено — жовтий, кинуто — червоний
Color hikkaStatusColor(HikkaWatchStatus s) => switch (s) {
      HikkaWatchStatus.watching => const Color(0xFF4FA8F5),
      HikkaWatchStatus.planned => const Color(0xFFA98BF0),
      HikkaWatchStatus.completed => const Color(0xFF5CC27A),
      HikkaWatchStatus.onHold => const Color(0xFFF2C94C),
      HikkaWatchStatus.dropped => const Color(0xFFE5645F),
    };

/// Колір вкладки «Улюблене»
const Color hikkaFavouriteColor = Color(0xFFF06292);

/// Блок «Мій список» на сторінці аніме: поточний статус із прогресом і оцінкою (натиснути — змінити), або
/// «Додати в список», або запрошення увійти. Збоку — кнопка «в улюблене».
class HikkaMyListBar extends StatefulWidget {
  final HikkaAnime anime;
  final double scale;

  const HikkaMyListBar({super.key, required this.anime, required this.scale});

  @override
  State<HikkaMyListBar> createState() => _HikkaMyListBarState();
}

class _HikkaMyListBarState extends State<HikkaMyListBar> {
  bool _loading = false;
  String? _error;
  bool _wasSignedIn = false;

  double get _scale => widget.scale;
  HikkaAuth get _auth => HikkaAuth.instance;
  HikkaMyList get _list => HikkaMyList.instance;
  String get _slug => widget.anime.slug;

  @override
  void initState() {
    super.initState();
    _wasSignedIn = _auth.signedIn;
    _auth.addListener(_onAuth);
    unawaited(_load());
  }

  @override
  void didUpdateWidget(HikkaMyListBar old) {
    super.didUpdateWidget(old);
    if (old.anime.slug != widget.anime.slug) unawaited(_load());
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuth);
    super.dispose();
  }

  void _onAuth() {
    final now = _auth.signedIn;
    if (now == _wasSignedIn) return;
    _wasSignedIn = now;
    if (now) unawaited(_load());
  }

  Future<void> _load() async {
    if (!_auth.signedIn) return;
    setState(() {
      _loading = !_list.knows(_slug);
      _error = null;
    });
    try {
      await _list.entry(_slug);
      await _list.isFavourite(_slug);
    } on HikkaException catch (e) {
      _error = e.message;
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _login() async {
    final ok = await HikkaLoginDialog.show(context, scale: _scale);
    if (ok && mounted) unawaited(_load());
  }

  Future<void> _edit() async {
    await AppDialogs.show<void>(
      context,
      builder: (_) => HikkaListEditDialog(anime: widget.anime, scale: _scale, entry: _list.cached(_slug)),
    );
  }

  final GlobalKey _anchor = GlobalKey();

  /// Випадне меню під кнопкою: статуси, «Серії та оцінка…», «Видалити зі списку»
  Future<void> _menu() async {
    final scale = _scale;
    final box = _anchor.currentContext?.findRenderObject();
    final overlay = Overlay.of(context).context.findRenderObject();
    if (box is! RenderBox || overlay is! RenderBox) return;
    final origin = box.localToGlobal(Offset(0, box.size.height + 4 * scale), ancestor: overlay);
    final entry = _list.cached(_slug);
    const edit = 'edit';
    const remove = 'remove';
    // Як кнопки у «Списках»: контурний значок кольору статусу, назва нейтральна; вибраний — виділена назва й пташка
    PopupMenuItem<Object> row(Object v, IconData icon, String text, {Color? iconColor, Color? color, bool checked = false}) => PopupMenuItem<Object>(
          value: v,
          height: 44 * scale,
          child: Row(
            children: [
              Icon(icon, size: 20 * scale, color: iconColor ?? color ?? uiTheme.colors.textMuted, weight: 300, fill: 0),
              SizedBox(width: 12 * scale),
              Expanded(
                child: Text(
                  text,
                  style: hikkaStyle(13.5 * scale, color: color ?? uiTheme.colors.textPrimary, weight: checked ? FontWeight.bold : FontWeight.normal),
                ),
              ),
              if (checked) Icon(Symbols.check_rounded, size: 18 * scale, color: uiTheme.colors.textMuted),
            ],
          ),
        );
    final picked = await showMenu<Object>(
      context: context,
      color: uiTheme.colors.drawerBg,
      constraints: BoxConstraints(minWidth: box.size.width, maxWidth: math.max(box.size.width, 260 * scale)),
      shape: RoundedRectangleBorder(
        borderRadius: uiTheme.borderRadius(12 * scale),
        side: BorderSide(color: uiTheme.colors.drawerBorder),
      ),
      position: RelativeRect.fromLTRB(origin.dx, origin.dy, overlay.size.width - origin.dx - box.size.width, 0),
      items: [
        for (final st in HikkaWatchStatus.values) row(st, hikkaStatusIcon(st), st.label, iconColor: hikkaStatusColor(st), checked: entry?.status == st),
        const PopupMenuDivider(),
        row(edit, Symbols.tune_rounded, 'Серії та оцінка…'),
        if (entry != null) row(remove, Symbols.delete_rounded, 'Видалити зі списку', iconColor: _errorColor),
      ],
    );
    if (!mounted || picked == null) return;
    if (picked == edit) return _edit();
    try {
      if (picked == remove) {
        await _list.remove(_slug);
      } else if (picked is HikkaWatchStatus) {
        final total = (widget.anime.episodesTotal ?? 0) > 0 ? widget.anime.episodesTotal : null;
        await _list.save(_slug, status: picked, total: total, anime: widget.anime);
      }
    } on HikkaException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _toggleFavourite() async {
    final now = _list.favouriteCached(_slug) ?? false;
    try {
      await _list.setFavourite(_slug, !now);
    } on HikkaException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  /// Коротка кнопка статусу: лише значок, назва й стрілка випадного меню (без кількості серій); оцінка окремою плашкою поруч
  Widget _entryTile(HikkaWatchEntry e) {
    final scale = _scale;
    final color = hikkaStatusColor(e.status);
    Widget tappable({required Widget child, required Color fill, required Color line}) => InkWell(
          onTap: () => unawaited(_menu()),
          borderRadius: uiTheme.borderRadius(12 * scale),
          splashColor: Colors.transparent,
          highlightColor: uiTheme.touchHighlight,
          hoverColor: uiTheme.hoverOverlay,
          child: Container(
            constraints: BoxConstraints(minHeight: AppPlatform.isMobile ? AppPlatform.touchTarget : 44 * scale),
            padding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 8 * scale),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: uiTheme.borderRadius(12 * scale),
              border: Border.all(color: line),
            ),
            child: child,
          ),
        );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: tappable(
            fill: color.withValues(alpha: 0.14),
            line: color.withValues(alpha: 0.55),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(hikkaStatusIcon(e.status), color: color, size: 20 * scale, weight: 300, fill: 1),
                SizedBox(width: 8 * scale),
                Flexible(
                  child: Text(e.status.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: hikkaStyle(13.5 * scale, weight: FontWeight.bold)),
                ),
                SizedBox(width: 10 * scale),
                Icon(Symbols.expand_more_rounded, color: uiTheme.textDarkMuted, size: 20 * scale, weight: 300),
              ],
            ),
          ),
        ),
        if (e.score > 0) ...[
          SizedBox(width: 8 * scale),
          tappable(
            fill: const Color(0xFFFFC23D).withValues(alpha: 0.12),
            line: const Color(0xFFFFC23D).withValues(alpha: 0.5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Symbols.star_rounded, color: const Color(0xFFFFC23D), size: 18 * scale, fill: 1),
                SizedBox(width: 4 * scale),
                Text('${e.score}', style: hikkaStyle(13.5 * scale, weight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final scale = _scale;
    return ListenableBuilder(
      listenable: Listenable.merge([_auth, _list]),
      builder: (context, _) {
        final signedIn = _auth.signedIn;
        final entry = signedIn ? _list.cached(_slug) : null;
        final fav = _list.favouriteCached(_slug) ?? false;

        final Widget main;
        if (!signedIn) {
          main = AppSecondaryButton(scale: scale, expand: false, icon: Symbols.bookmark_add_rounded, label: 'Додати в список', onTap: () => unawaited(_login()));
        } else if (_loading) {
          main = Opacity(
            opacity: 0.6,
            child: IgnorePointer(child: AppSecondaryButton(scale: scale, expand: false, icon: Symbols.bookmark_rounded, label: 'Завантажую список…', onTap: () {})),
          );
        } else if (entry == null) {
          main = AppSecondaryButton(scale: scale, expand: false, icon: Symbols.bookmark_add_rounded, label: 'Додати в список', onTap: () => unawaited(_menu()));
        } else {
          main = _entryTile(entry);
        }

        return Padding(
          padding: EdgeInsets.only(bottom: 12 * scale),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(child: KeyedSubtree(key: _anchor, child: main)),
                  if (signedIn && !_loading) ...[
                    SizedBox(width: 6 * scale),
                    HikkaIconButton(
                      icon: Symbols.favorite_rounded,
                      tooltip: fav ? 'Прибрати з улюбленого' : 'В улюблене',
                      scale: scale,
                      active: fav,
                      onTap: () => unawaited(_toggleFavourite()),
                    ),
                  ],
                ],
              ),
              if (_error != null)
                Padding(
                  padding: EdgeInsets.only(top: 6 * scale),
                  child: Text(_error!, style: hikkaStyle(11.5 * scale, color: _errorColor)),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Вікно зміни запису: статус, кількість серій, оцінка; видалення зі списків
class HikkaListEditDialog extends StatefulWidget {
  final HikkaAnime anime;
  final double scale;
  final HikkaWatchEntry? entry;

  const HikkaListEditDialog({super.key, required this.anime, required this.scale, this.entry});

  @override
  State<HikkaListEditDialog> createState() => _HikkaListEditDialogState();
}

class _HikkaListEditDialogState extends State<HikkaListEditDialog> {
  late HikkaWatchStatus _status = widget.entry?.status ?? HikkaWatchStatus.planned;
  late int _episodes = widget.entry?.episodes ?? 0;
  late int _score = widget.entry?.score ?? 0;
  bool _saving = false;
  String? _error;

  double get _scale => widget.scale;
  int? get _total => (widget.anime.episodesTotal ?? 0) > 0 ? widget.anime.episodesTotal : null;

  void _pickStatus(HikkaWatchStatus s) {
    setState(() {
      _status = s;
      // Як на сайті: «Переглянуто» означає, що пройдено всі серії
      final t = _total;
      if (s == HikkaWatchStatus.completed && t != null) _episodes = t;
    });
  }

  void _step(int d) {
    final max = _total ?? 9999;
    setState(() => _episodes = (_episodes + d).clamp(0, max));
  }

  Future<void> _run(Future<void> Function() job) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await job();
      if (mounted) Navigator.of(context).pop();
    } on HikkaException catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.message;
        });
      }
    }
  }

  Future<void> _save() => _run(() => HikkaMyList.instance.save(
        widget.anime.slug,
        status: _status,
        episodes: _episodes,
        score: _score,
        total: _total,
        anime: widget.anime,
      ));

  Future<void> _remove() => _run(() => HikkaMyList.instance.remove(widget.anime.slug));

  Widget _label(String text) => Padding(
        padding: EdgeInsets.only(bottom: 8 * _scale),
        child: Text(text, style: hikkaStyle(12.5 * _scale, weight: FontWeight.bold, color: uiTheme.textMuted)),
      );

  @override
  Widget build(BuildContext context) {
    final scale = _scale;
    final total = _total;
    return WatchDialogFrame(
      scale: scale,
      title: widget.entry == null ? 'Додати в список' : 'Мій список',
      icon: Symbols.bookmarks_rounded,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label('Статус'),
          Wrap(
            spacing: 8 * scale,
            runSpacing: 8 * scale,
            children: [
              for (final s in HikkaWatchStatus.values)
                HikkaChip(label: s.label, scale: scale, icon: hikkaStatusIcon(s), color: hikkaStatusColor(s), selected: _status == s, onTap: () => _pickStatus(s)),
            ],
          ),
          SizedBox(height: 18 * scale),
          _label('Переглянуто серій'),
          Row(
            children: [
              AppRowIconButton(scale: scale, icon: Symbols.remove_rounded, size: 22, onTap: _episodes > 0 ? () => _step(-1) : null),
              SizedBox(
                width: 84 * scale,
                child: Text(
                  total == null ? '$_episodes' : '$_episodes / $total',
                  textAlign: TextAlign.center,
                  style: hikkaStyle(16 * scale, weight: FontWeight.bold),
                ),
              ),
              AppRowIconButton(scale: scale, icon: Symbols.add_rounded, size: 22, onTap: (total == null || _episodes < total) ? () => _step(1) : null),
            ],
          ),
          SizedBox(height: 18 * scale),
          _label(_score == 0 ? 'Оцінка' : 'Оцінка: $_score з 10'),
          Wrap(
            spacing: 6 * scale,
            runSpacing: 6 * scale,
            children: [
              for (int n = 1; n <= 10; n++)
                HikkaChip(label: '$n', scale: scale, selected: _score == n, onTap: () => setState(() => _score = _score == n ? 0 : n)),
            ],
          ),
          if (_error != null) ...[
            SizedBox(height: 14 * scale),
            Text(_error!, style: hikkaStyle(12 * scale, color: _errorColor, height: 1.4)),
          ],
        ],
      ),
      actions: [
        if (widget.entry != null) QuietAction(label: 'Видалити зі списку', scale: scale, onTap: _saving ? () {} : () => unawaited(_remove())),
        AppAccentButton(scale: scale, solid: true, icon: Symbols.check_rounded, label: _saving ? 'Зберігаю…' : 'Зберегти', onTap: _saving ? () {} : () => unawaited(_save())),
      ],
    );
  }
}
