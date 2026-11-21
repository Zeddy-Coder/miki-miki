/// Small pieces of the downloads' look, shared by the downloads pages, the "Перегляд" panel and the player's list:
/// the status in words, the mark on an episode plate, the round progress with pause.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/hikka_models.dart';
import '../../services/downloads/download_manager.dart';
import '../../services/downloads/download_models.dart';
import '../../services/ui_theme_service.dart';
import '../app_tones.dart';
import '../line_icons.dart';

class DownloadText {
  DownloadText._();

  static String episodes(int n) => '$n ${HikkaText.plural(n, 'серія', 'серії', 'серій')}';

  /// "120 з 300 МБ", "2,1 з 4,0 ГБ"
  static String amount(int got, int total) {
    if (total <= 0) return formatBytes(got);
    final a = formatBytes(got);
    final b = formatBytes(total);
    final unit = b.split(' ').last;
    return a.endsWith(' $unit') ? '${a.substring(0, a.length - unit.length - 1)} з $b' : '$a з $b';
  }

  /// One line about where the download is: "45 % · 120 з 300 МБ · 2,1 МБ/с", "У черзі", "На паузі" …
  static String status(DownloadItem i, DownloadManager m) {
    switch (i.state) {
      case DownloadState.done:
        return [if (i.quality.isNotEmpty) i.quality, formatBytes(i.bytes)].join(' · ');
      case DownloadState.paused:
        return [
          'На паузі',
          if (i.fraction != null && i.fraction! > 0) '${(i.fraction! * 100).floor()} %',
        ].join(' · ');
      case DownloadState.failed:
        return i.error == null ? 'Не вдалося' : 'Не вдалося: ${i.error}';
      case DownloadState.queued:
        final why = m.waitReason;
        if (why != null) return why;
        if (i.error != null) return i.error!;
        return 'У черзі';
      case DownloadState.running:
        final f = i.fraction;
        if (f == null || i.bytes == 0) return 'Готуємо посилання…';
        final speed = m.speed;
        return [
          '${(f * 100).floor()} %',
          amount(i.bytes, i.totalBytes),
          if (speed > 0) '${formatBytes(speed.round())}/с',
        ].join(' · ');
    }
  }
}

/// One line about all downloads (the "Завантаження" row in "Профіль"): what goes, why it waits, what is on the device
String downloadsSummary(DownloadManager m) {
  final pending = m.pending;
  final active = pending.where((i) => i.isActive).length;
  if (active > 0) {
    final cur = m.current;
    final f = cur?.fraction;
    final why = m.waitReason;
    return [
      'Завантажується $active',
      if (cur != null && f != null) '${(f * 100).floor()} %' else if (why != null) why.split(' — ').first.split(':').first,
    ].join(' · ');
  }
  final done = m.done;
  if (done.isEmpty && pending.isEmpty) return 'Серії для перегляду без інтернету';
  final paused = pending.where((i) => i.state == DownloadState.paused).length;
  final failed = pending.where((i) => i.state == DownloadState.failed).length;
  return [
    if (done.isNotEmpty) '${DownloadText.episodes(done.length)} · ${formatBytes(m.usedBytes)}',
    if (paused > 0) 'на паузі $paused',
    if (failed > 0) 'не вдалося $failed',
  ].join(' · ');
}

/// The mark on an episode plate (the "Перегляд" panel, the download picker): downloaded — a small arrow in the
/// corner in the accent, waiting — the same arrow dim, downloading — a thin bar along the bottom, failed — a yellow dot.
/// Lies over the plate and lets taps through
class DownloadPlateMark extends StatelessWidget {
  final DownloadItem item;
  final double scale;
  final double radius;

  const DownloadPlateMark({super.key, required this.item, required this.scale, required this.radius});

  @override
  Widget build(BuildContext context) {
    final accent = uiTheme.accentColor;
    final corner = Positioned(
      top: 3 * scale,
      right: 3 * scale,
      child: switch (item.state) {
        DownloadState.done => LineIconView(LineIcon.download, size: 11 * scale, color: accent, stroke: 2),
        DownloadState.failed => Container(
            width: 6 * scale,
            height: 6 * scale,
            margin: EdgeInsets.all(2 * scale),
            decoration: const BoxDecoration(color: Color(0xFFE0B341), shape: BoxShape.circle),
          ),
        _ => LineIconView(LineIcon.download, size: 11 * scale, color: AppTones.rowSub, stroke: 2),
      },
    );
    final f = item.fraction;
    return Positioned.fill(
      child: IgnorePointer(
        child: ClipRRect(
          borderRadius: uiTheme.borderRadius(radius),
          child: Stack(
            children: [
              corner,
              if (item.state == DownloadState.running || (item.state == DownloadState.paused && (f ?? 0) > 0))
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 2.5 * scale,
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: (f ?? 0.03).clamp(0.03, 1.0),
                    child: ColoredBox(color: item.state == DownloadState.running ? accent : AppTones.rowSub),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A round button with the download's progress around it: pause while it goes, an arrow to go on when it is paused
/// or failed. 40 dp to touch (48 on a phone through the row's own padding)
class DownloadRing extends StatelessWidget {
  final DownloadItem item;
  final double scale;
  final VoidCallback onTap;

  const DownloadRing({super.key, required this.item, required this.scale, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final size = 40 * scale;
    final active = item.isActive;
    final accent = uiTheme.accentColor;
    final f = item.fraction;
    return Semantics(
      button: true,
      label: active ? 'Призупинити' : 'Продовжити завантаження',
      child: Tooltip(
        message: active ? 'Призупинити' : (item.state == DownloadState.failed ? 'Спробувати ще' : 'Продовжити'),
        child: InkResponse(
          onTap: onTap,
          radius: size * 0.6,
          child: SizedBox.square(
            dimension: size,
            child: CustomPaint(
              painter: _RingPainter(
                value: item.state == DownloadState.queued ? null : f,
                color: active ? accent : AppTones.rowSub,
                track: AppTones.track,
                stroke: 2.4 * scale,
              ),
              child: Center(
                child: active
                    ? LineIconView(LineIcon.pause, size: 15 * scale, color: uiTheme.textPrimary)
                    : item.state == DownloadState.failed
                        ? LineIconView(LineIcon.refresh, size: 17 * scale, color: uiTheme.textPrimary)
                        : LineIconView(LineIcon.download, size: 17 * scale, color: uiTheme.textPrimary),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  /// null: a dashed full circle (waiting)
  final double? value;
  final Color color;
  final Color track;
  final double stroke;

  _RingPainter({required this.value, required this.color, required this.track, required this.stroke});

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromCircle(center: size.center(Offset.zero), radius: size.shortestSide / 2 - stroke);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = track;
    canvas.drawArc(r, 0, math.pi * 2, false, base);
    final v = value;
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;
    if (v == null) {
      // Waiting: short dashes all around
      const n = 12;
      for (var i = 0; i < n; i++) {
        canvas.drawArc(r, -math.pi / 2 + i * math.pi * 2 / n, math.pi / n * 0.6, false, p);
      }
      return;
    }
    if (v <= 0) return;
    canvas.drawArc(r, -math.pi / 2, math.pi * 2 * v.clamp(0.0, 1.0), false, p);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.value != value || old.color != color || old.track != track || old.stroke != stroke;
}
