import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'app_animation_kit.dart';
import 'line_icons.dart';
import 'player_kit.dart';

/// A short large pause/play icon in the middle of the video (instead of permanent central buttons): the same
/// translucent circle as the transport's pause button
class CenterFlash extends StatefulWidget {
  final double scale;
  final Player player;

  const CenterFlash({super.key, required this.scale, required this.player});

  @override
  State<CenterFlash> createState() => _CenterFlashState();
}

class _CenterFlashState extends State<CenterFlash> {
  StreamSubscription<bool>? _sub;
  Timer? _timer;
  bool _show = false;
  late bool _playing;

  @override
  void initState() {
    super.initState();
    _playing = widget.player.state.playing;
    _sub = widget.player.stream.playing.listen((p) {
      if (p == _playing || !mounted) return;
      _timer?.cancel();
      setState(() {
        _playing = p;
        _show = true;
      });
      _timer = Timer(const Duration(milliseconds: 650), () {
        if (mounted) setState(() => _show = false);
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.scale;
    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: AppPresence(
            visible: _show,
            slide: Offset.zero,
            duration: AppAnim.medium,
            child: Container(
              key: const ValueKey('center-flash'),
              width: 72 * scale,
              height: 72 * scale,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: PlayerTones.circleBig, shape: BoxShape.circle),
              child: LineIconView(_playing ? LineIcon.play : LineIcon.pause, size: 32 * scale, color: PlayerTones.fg, stroke: 1.2),
            ),
          ),
        ),
      ),
    );
  }
}
