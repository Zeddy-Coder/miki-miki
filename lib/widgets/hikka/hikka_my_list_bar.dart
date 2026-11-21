import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/hikka_models.dart';
import '../../models/hikka_user_models.dart';
import '../../services/hikka_api.dart';
import '../../services/hikka_auth.dart';
import '../../services/hikka_lists.dart';
import '../../services/ui_theme_service.dart';
import '../app_ui_kit.dart';
import 'hikka_account_ui.dart';
import 'hikka_common.dart';
import 'hikka_list_sheet.dart';

const Color _errorColor = Color(0xFFE57373);

/// Status color (the profile's list bar): watching is blue, planned is purple, completed is green, on hold is yellow,
/// dropped is red; muted, as in the concepts
Color hikkaStatusColor(HikkaWatchStatus s) => switch (s) {
  HikkaWatchStatus.watching => const Color(0xFF4A7BD0),
  HikkaWatchStatus.planned => const Color(0xFF8A6BD0),
  HikkaWatchStatus.completed => const Color(0xFF3FAE6A),
  HikkaWatchStatus.onHold => const Color(0xFFD0A040),
  HikkaWatchStatus.dropped => const Color(0xFFC9604A),
};

/// The "Мій список" button on the anime page banner: a round bookmark whose look shows the status (tap → the
/// "Мій список" sheet: statuses, episodes, score, favorites, removal), or an invitation to sign in for a guest.
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

  /// The "Мій список" sheet: statuses, episodes, score, favorites, removal; every change is saved at once
  Future<void> _open() => showHikkaListSheet(context, anime: widget.anime, scale: _scale);

  /// The round bookmark button on the banner: a gray outline when the title is not in a list, accent-colored with a
  /// glyph of the status inside when it is (play, check, pause, cross); for "Дивлюсь" a small "episodes/total" badge
  @override
  Widget build(BuildContext context) {
    final scale = _scale;
    return ListenableBuilder(
      listenable: Listenable.merge([_auth, _list]),
      builder: (context, _) {
        final signedIn = _auth.signedIn;
        final entry = signedIn ? _list.cached(_slug) : null;
        final total = widget.anime.episodesTotal ?? 0;
        final badge = entry != null && entry.status == HikkaWatchStatus.watching && entry.episodes > 0
            ? (total > 0 ? '${entry.episodes}/$total' : '${entry.episodes}')
            : null;
        final tooltip = entry == null ? 'Додати в список' : 'У списку: ${entry.status.label}';
        // Same circle and touch area as the floating "Назад" on the other side of the banner
        final size = floatingButtonSize(scale);
        final hit = floatingButtonHit(scale);
        final accent = uiTheme.accentColor;
        void open() => unawaited(!signedIn ? _login() : (_loading ? Future<void>.value() : _open()));
        final shape = RoundedRectangleBorder(borderRadius: uiTheme.borderRadius(size / 2));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              button: true,
              label: tooltip,
              child: Tooltip(
                message: tooltip,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: open,
                  child: SizedBox(
                    width: hit,
                    height: hit,
                    child: Center(
                      child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Material(
                              color: Colors.black.withValues(alpha: .55),
                              shape: shape,
                              child: InkWell(
                                customBorder: shape,
                                splashColor: Colors.transparent,
                                highlightColor: uiTheme.touchHighlight,
                                hoverColor: uiTheme.hoverOverlay,
                                onTap: open,
                                child: SizedBox(
                                  width: size,
                                  height: size,
                                  child: Center(
                                    child: Opacity(
                                      opacity: _loading ? 0.5 : 1,
                                      child: HikkaListMark(
                                        status: entry?.status,
                                        size: 22 * scale,
                                        color: entry == null ? const Color(0xFFDDDDDD) : accent,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            if (badge != null)
                              Positioned(
                                right: -2 * scale,
                                bottom: -2 * scale,
                                child: IgnorePointer(
                                  child: Container(
                                    padding: EdgeInsets.symmetric(horizontal: 5 * scale, vertical: 1 * scale),
                                    decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(8 * scale)),
                                    child: Text(badge, style: hikkaStyle(9.5 * scale, weight: FontWeight.bold, color: onAccent(accent))),
                                  ),
                                ),
                              ),
                          ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (_error != null)
              Container(
                margin: EdgeInsets.only(top: 6 * scale),
                constraints: BoxConstraints(maxWidth: 220 * scale),
                padding: EdgeInsets.symmetric(horizontal: 8 * scale, vertical: 4 * scale),
                decoration: BoxDecoration(color: const Color(0xCC000000), borderRadius: BorderRadius.circular(8 * scale)),
                child: Text(_error!, style: hikkaStyle(11.5 * scale, color: _errorColor)),
              ),
          ],
        );
      },
    );
  }
}

/// The bookmark outline from the bottom navigation with a status glyph inside (none for "not in a list" and "planned"
/// shows a plus and nothing). Drawn by hand so that the line weight matches the other icons.
class HikkaListMark extends StatelessWidget {
  final HikkaWatchStatus? status;
  final double size;
  final Color color;

  const HikkaListMark({super.key, required this.status, required this.size, required this.color});

  @override
  Widget build(BuildContext context) => CustomPaint(size: Size.square(size), painter: _ListMarkPainter(status, color));
}

class _ListMarkPainter extends CustomPainter {
  final HikkaWatchStatus? status;
  final Color color;

  _ListMarkPainter(this.status, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 24;
    Offset o(double x, double y) => Offset(x * k, y * k);
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6 * k
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final body = Path()
      ..moveTo(6 * k, 4 * k)
      ..lineTo(18 * k, 4 * k)
      ..lineTo(18 * k, 21 * k)
      ..lineTo(12 * k, 17 * k)
      ..lineTo(6 * k, 21 * k)
      ..close();
    canvas.drawPath(body, line);
    switch (status) {
      case null:
        canvas.drawLine(o(12, 7.5), o(12, 12.5), line);
        canvas.drawLine(o(9.5, 10), o(14.5, 10), line);
      case HikkaWatchStatus.watching:
        final tri = Path()
          ..moveTo(10.5 * k, 7.6 * k)
          ..lineTo(14.1 * k, 10 * k)
          ..lineTo(10.5 * k, 12.4 * k)
          ..close();
        canvas.drawPath(tri, Paint()..color = color);
        canvas.drawPath(tri, line..strokeWidth = 1 * k);
      case HikkaWatchStatus.planned:
        break;
      case HikkaWatchStatus.completed:
        canvas.drawPath(Path()..moveTo(9.2 * k, 10 * k)..lineTo(11.2 * k, 12 * k)..lineTo(14.8 * k, 8.2 * k), line);
      case HikkaWatchStatus.onHold:
        canvas.drawLine(o(10.4, 8), o(10.4, 12), line);
        canvas.drawLine(o(13.6, 8), o(13.6, 12), line);
      case HikkaWatchStatus.dropped:
        canvas.drawLine(o(9.8, 8.2), o(14.2, 12.6), line);
        canvas.drawLine(o(14.2, 8.2), o(9.8, 12.6), line);
    }
  }

  @override
  bool shouldRepaint(_ListMarkPainter old) => old.status != status || old.color != color;
}
