import 'dart:async';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:media_kit/media_kit.dart';
import 'app_animation_kit.dart';

/// Коротка велика іконка пауза/пуск посередині відео (замість постійних центральних кнопок)
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
              width: 76 * scale,
              height: 76 * scale,
              decoration: BoxDecoration(
                color: const Color(0xFF16161A).withValues(alpha: 0.72),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.16), width: 1.0),
              ),
              child: Icon(
                _playing ? Symbols.play_arrow_rounded : Symbols.pause_rounded,
                color: Colors.white,
                size: 42 * scale,
                fill: 1,
                weight: 300,
                opticalSize: 24,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
