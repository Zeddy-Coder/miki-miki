import 'package:flutter/material.dart';

/// Line icons of the new design, drawn from the same SVG paths as the concepts (a 24 grid, a 1.6 line, round ends),
/// where the icon font draws them differently: the title page, the main tabs, sheets and menus
enum LineIcon {
  mic(['M12 3a3 3 0 0 1 3 3v5a3 3 0 0 1-6 0V6a3 3 0 0 1 3-3z', 'M5 11a7 7 0 0 0 14 0M12 18v3']),
  subtitles(['M5 5h14a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2z', 'M7 15h4M14 15h3M7 11h2M12 11h5']),
  warning(['M12 4l9 16H3z', 'M12 10v4M12 17h.01']),
  list(['M8 6h12M8 12h12M8 18h12M4 6h.01M4 12h.01M4 18h.01']),
  hd(['M5 6h14a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2z', 'M7 10v4M7 12h3M10 10v4M14 10v4h1.5a2 2 0 0 0 0-4z']),
  monitor(['M5 4h14a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2z', 'M8 21h8']),
  sliders(['M4 7h10M18 7h2M4 17h2M10 17h10', 'M16 5a2 2 0 1 0 0 4a2 2 0 1 0 0-4z', 'M8 15a2 2 0 1 0 0 4a2 2 0 1 0 0-4z']),
  groups(['M9 5a3 3 0 1 0 0 6a3 3 0 1 0 0-6z', 'M3 20a6 6 0 0 1 12 0', 'M16 6a2.5 2.5 0 1 1 0 5', 'M17.5 14.3a5 5 0 0 1 3.5 4.7']),
  openOut(['M14 4h6v6M20 4l-9 9', 'M18 14v4a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h4']),
  refresh(['M20 12a8 8 0 1 1-2.34-5.66', 'M20 4v5h-5']),
  clock(['M12 3a9 9 0 1 0 0 18a9 9 0 1 0 0-18z', 'M12 7v5l3 2']),
  chevronRight(['M9 6l6 6-6 6']),
  close(['M6 6l12 12M18 6L6 18']),
  back(['M19 12H5M11 6l-6 6 6 6']),
  check(['M5 12.5l4.5 4.5L19 7.5']),
  home(['M4 11l8-7 8 7v9h-5v-6H9v6H4z']),
  search(['M11 4a7 7 0 1 0 0 14a7 7 0 1 0 0-14z', 'M20 20l-4-4']),
  bookmark(['M6 4h12v17l-6-4-6 4z']),
  person(['M12 4a4 4 0 1 0 0 8a4 4 0 1 0 0-8z', 'M4 21a8 8 0 0 1 16 0']),
  play(['M7 5l12 7-12 7z'], filled: true),
  bell(['M6 16v-5a6 6 0 0 1 12 0v5l1.5 2h-15z', 'M10 20.5a2 2 0 0 0 4 0']),
  chevronDown(['M6 9l6 6 6-6']),
  chevronUp(['M6 15l6-6 6 6']),
  grid([
    'M5 4h5a1 1 0 0 1 1 1v5a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V5a1 1 0 0 1 1-1z',
    'M14 4h5a1 1 0 0 1 1 1v5a1 1 0 0 1-1 1h-5a1 1 0 0 1-1-1V5a1 1 0 0 1 1-1z',
    'M5 13h5a1 1 0 0 1 1 1v5a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1v-5a1 1 0 0 1 1-1z',
    'M14 13h5a1 1 0 0 1 1 1v5a1 1 0 0 1-1 1h-5a1 1 0 0 1-1-1v-5a1 1 0 0 1 1-1z',
  ]),
  rows(['M4 6h16M4 12h16M4 18h16']),
  calendar(['M6 5h12a2 2 0 0 1 2 2v11a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2z', 'M4 10h16M9 3v4M15 3v4']),
  stack(['M8 4h10a1 1 0 0 1 1 1v12a1 1 0 0 1-1 1H8a1 1 0 0 1-1-1V5a1 1 0 0 1 1-1z', 'M4 8v11a1 1 0 0 0 1 1h10']),
  doc(['M7 3h7l4 4v13a1 1 0 0 1-1 1H7a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1z', 'M14 3v4h4', 'M9 12h6M9 16h5']),
  face(['M12 3a9 9 0 1 0 0 18a9 9 0 1 0 0-18z', 'M9 10h.01M15 10h.01', 'M8.5 14.5a4.5 4.5 0 0 0 7 0']),
  gear([
    'M12 9a3 3 0 1 0 0 6a3 3 0 1 0 0-6z',
    'M12 2.8v2.4M12 18.8v2.4M2.8 12h2.4M18.8 12h2.4M5.5 5.5l1.7 1.7M16.8 16.8l1.7 1.7M5.5 18.5l1.7-1.7M16.8 7.2l1.7-1.7',
  ]),
  folder(['M4 7a1 1 0 0 1 1-1h5l2 2h7a1 1 0 0 1 1 1v9a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1z']),
  arrowUp(['M12 19V6M6 11l6-6 6 6']),
  comment(['M5 5h14a1 1 0 0 1 1 1v9a1 1 0 0 1-1 1H10l-5 4V6a1 1 0 0 1 1-1z']),
  heart(['M12 20s-7.5-4.6-7.5-10.2A4.2 4.2 0 0 1 12 7.3a4.2 4.2 0 0 1 7.5 2.5C19.5 15.4 12 20 12 20z']),
  trash(['M5 7h14M10 7V5h4v2M7 7l1 13h8l1-13']),
  star(['M12 4l2.4 4.9 5.4.8-3.9 3.8.9 5.4L12 16.4l-4.8 2.5.9-5.4-3.9-3.8 5.4-.8z']),
  minus(['M6 12h12']),
  plus(['M12 6v12M6 12h12']),
  logout(['M10 5H6a1 1 0 0 0-1 1v12a1 1 0 0 0 1 1h4', 'M14 8l4 4-4 4M18 12H9']),
  sync(['M20 11a8 8 0 0 0-14.3-4.9M4 5v4h4', 'M4 13a8 8 0 0 0 14.3 4.9M20 19v-4h-4']),
  info(['M12 3a9 9 0 1 0 0 18a9 9 0 1 0 0-18z', 'M12 11v5M12 8h.01']),
  // The admin panel: a shield with a check
  shield(['M12 3L19 6V11.5C19 15.9 16 19.4 12 21C8 19.4 5 15.9 5 11.5V6Z', 'M9 12L11.2 14.2L15.2 10']),
  link(['M10 14a4 4 0 0 0 5.66 0l3-3a4 4 0 0 0-5.66-5.66l-1 1', 'M14 10a4 4 0 0 0-5.66 0l-3 3a4 4 0 0 0 5.66 5.66l1-1']),
  send(['M21 4L3 11l7 2.5L12.5 21z', 'M10 13.5L21 4']),
  login(['M14 5h4a1 1 0 0 1 1 1v12a1 1 0 0 1-1 1h-4', 'M10 8l4 4-4 4M14 12H5']),
  eye(['M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12z', 'M12 9a3 3 0 1 0 0 6a3 3 0 1 0 0-6z']),
  pin(['M9.5 4h5l-.6 5 3.1 3.2V14H7v-1.8L10.1 9z', 'M12 14v6']),
  megaphone(['M4 10v4a1 1 0 0 0 1 1h2l7 4V5L7 9H5a1 1 0 0 0-1 1z', 'M17.5 9.5a3.5 3.5 0 0 1 0 5']),
  download(['M12 4v11M7.5 10.5L12 15l4.5-4.5', 'M5 19h14']),
  // Downloads: a downloaded episode (an arrow in a circle), no internet (Wi-Fi crossed out)
  downloaded(['M12 3a9 9 0 1 0 0 18a9 9 0 1 0 0-18z', 'M12 7.5v8M8.5 12.2L12 15.7l3.5-3.5']),
  wifi(['M2.5 8.8a14.5 14.5 0 0 1 19 0', 'M5.5 12.2a10 10 0 0 1 13 0', 'M8.7 15.5a5.4 5.4 0 0 1 6.6 0', 'M12 19.2h.01']),
  wifiOff(['M2.5 8.8a14.5 14.5 0 0 1 19 0', 'M5.5 12.2a10 10 0 0 1 13 0', 'M8.7 15.5a5.4 5.4 0 0 1 6.6 0', 'M12 19.2h.01', 'M4 4l16 16']),
  checks(['M3.5 12.5l4 4L15 9', 'M12.5 15.5l1 1L21 9']),
  history(['M4 12a8 8 0 1 0 2.4-5.7', 'M4 5v4h4', 'M12 8v4l3 2']),
  playlist(['M4 6h12M4 12h12M4 18h8', 'M17 15.5v5l4-2.5z']),
  // The player
  pause(['M7 5h3.2v14H7zM13.8 5H17v14h-3.2z'], filled: true),
  pictureInPicture(['M4 5h16a1 1 0 0 1 1 1v12a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V6a1 1 0 0 1 1-1z', 'M12.5 12h5.5v4.5h-5.5z']),
  rotate(['M9 4h6a1 1 0 0 1 1 1v14a1 1 0 0 1-1 1H9a1 1 0 0 1-1-1V5a1 1 0 0 1 1-1z', 'M3.5 9a8.5 8.5 0 0 1 2.8-4.6', 'M20.5 15a8.5 8.5 0 0 1-2.8 4.6']),
  skipPrevious(['M6.5 5.5v13', 'M18 5.5L9.5 12l8.5 6.5z']),
  skipNext(['M17.5 5.5v13', 'M6 5.5l8.5 6.5L6 18.5z']),
  replay(['M4.5 12a7.5 7.5 0 1 0 2.2-5.3', 'M4.3 4.2v4h4']),
  forward(['M19.5 12a7.5 7.5 0 1 1-2.2-5.3', 'M19.7 4.2v4h-4']),
  sparkle(['M11 4l1.7 4.6L17 10.3l-4.3 1.7L11 16.5l-1.7-4.5L5 10.3l4.3-1.7z', 'M18 14.5l.8 2 2 .8-2 .8-.8 2-.8-2-2-.8 2-.8z']),
  musicNote(['M9 17.5V6.5l10-2.3v11', 'M9 17.5a2.5 2.5 0 1 1-5 0a2.5 2.5 0 1 1 5 0z', 'M19 15.2a2.5 2.5 0 1 1-5 0a2.5 2.5 0 1 1 5 0z']),
  volume(['M4 9.5h3.2L12 5.5v13l-4.8-4H4z', 'M15.5 9.2a4 4 0 0 1 0 5.6', 'M18.3 6.5a8 8 0 0 1 0 11']),
  volumeLow(['M4 9.5h3.2L12 5.5v13l-4.8-4H4z', 'M15.5 9.2a4 4 0 0 1 0 5.6']),
  volumeOff(['M4 9.5h3.2L12 5.5v13l-4.8-4H4z', 'M16 9.5l5 5M21 9.5l-5 5']),
  fullscreen(['M4 9V5h4M20 9V5h-4M4 15v4h4M20 15v4h-4']),
  fullscreenExit(['M8 4v4H4M16 4v4h4M8 20v-4H4M16 20v-4h4']),
  speed(['M4.5 17.5a8.5 8.5 0 1 1 15 0', 'M12 13l3.6-4.2']),
  chapters(['M3.5 12h4.5M10 12h5M17 12h3.5', 'M8 8.5v7M15 8.5v7']),
  skipForward(['M5 6l8 6-8 6z', 'M18 6v12']),
  chip(['M8 6h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2z', 'M10 10h4v4h-4z', 'M10 3v3M14 3v3M10 18v3M14 18v3M3 10h3M3 14h3M18 10h3M18 14h3']),
  chart(['M5 20V11M12 20V5M19 20v-6', 'M3.5 20h17']),
  repeat(['M17 3l3 3-3 3', 'M4 11V9a3 3 0 0 1 3-3h13', 'M7 21l-3-3 3-3', 'M20 13v2a3 3 0 0 1-3 3H4']),
  grip(['M9 6h.01M15 6h.01M9 12h.01M15 12h.01M9 18h.01M15 18h.01']);

  final List<String> paths;
  final bool filled;

  const LineIcon(this.paths, {this.filled = false});
}

/// A [LineIcon] of [size] in [color]; [stroke] is the line width on the 24 grid (the menus' check mark is a little bolder)
class LineIconView extends StatelessWidget {
  final LineIcon icon;
  final double size;
  final Color color;
  final double stroke;

  const LineIconView(this.icon, {super.key, required this.size, required this.color, this.stroke = 1.6});

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _LinePainter(icon, color, stroke)),
      );
}

class _LinePainter extends CustomPainter {
  final LineIcon icon;
  final Color color;
  final double stroke;

  _LinePainter(this.icon, this.color, this.stroke);

  static final Map<LineIcon, List<Path>> _cache = {};

  @override
  void paint(Canvas canvas, Size size) {
    final paths = _cache.putIfAbsent(icon, () => [for (final d in icon.paths) parseSvgPath(d)]);
    final k = size.width / 24;
    canvas.save();
    canvas.scale(k);
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final p in paths) {
      if (icon.filled) canvas.drawPath(p, Paint()..color = color);
      canvas.drawPath(p, line);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LinePainter old) => old.icon != icon || old.color != color || old.stroke != stroke;
}

/// A small SVG path reader: M L H V A C S Z, absolute and relative (enough for the icons above)
Path parseSvgPath(String d) {
  final path = Path();
  final tokens = RegExp(r'[MmLlHhVvAaCcSsZz]|-?(?:\d+\.?\d*|\.\d+)').allMatches(d).map((m) => m.group(0)!).toList();
  var i = 0;
  var cmd = '';
  double x = 0, y = 0, sx = 0, sy = 0;
  // The second control point of the last curve (a smooth curve mirrors it)
  double? cx, cy;
  bool isCmd(String t) => RegExp(r'^[A-Za-z]$').hasMatch(t);
  double n() => double.parse(tokens[i++]);
  while (i < tokens.length) {
    if (isCmd(tokens[i])) cmd = tokens[i++];
    final rel = cmd == cmd.toLowerCase();
    switch (cmd.toUpperCase()) {
      case 'M':
        x = (rel ? x : 0) + n();
        y = (rel ? y : 0) + n();
        path.moveTo(x, y);
        sx = x;
        sy = y;
        cmd = rel ? 'l' : 'L'; // pairs after a move are lines
      case 'L':
        x = (rel ? x : 0) + n();
        y = (rel ? y : 0) + n();
        path.lineTo(x, y);
      case 'H':
        x = (rel ? x : 0) + n();
        path.lineTo(x, y);
      case 'V':
        y = (rel ? y : 0) + n();
        path.lineTo(x, y);
      case 'C':
        final x1 = (rel ? x : 0) + n(), y1 = (rel ? y : 0) + n();
        final x2 = (rel ? x : 0) + n(), y2 = (rel ? y : 0) + n();
        x = (rel ? x : 0) + n();
        y = (rel ? y : 0) + n();
        path.cubicTo(x1, y1, x2, y2, x, y);
        cx = x2;
        cy = y2;
        continue;
      case 'S':
        final x1 = cx == null ? x : 2 * x - cx;
        final y1 = cy == null ? y : 2 * y - cy;
        final x2 = (rel ? x : 0) + n(), y2 = (rel ? y : 0) + n();
        x = (rel ? x : 0) + n();
        y = (rel ? y : 0) + n();
        path.cubicTo(x1, y1, x2, y2, x, y);
        cx = x2;
        cy = y2;
        continue;
      case 'A':
        final rx = n(), ry = n(), rot = n(), large = n() != 0, sweep = n() != 0;
        x = (rel ? x : 0) + n();
        y = (rel ? y : 0) + n();
        path.arcToPoint(Offset(x, y), radius: Radius.elliptical(rx, ry), rotation: rot, largeArc: large, clockwise: sweep);
      case 'Z':
        path.close();
        x = sx;
        y = sy;
      default:
        i++;
    }
    // Only a curve right before a smooth one lends it a control point
    cx = null;
    cy = null;
  }
  return path;
}
