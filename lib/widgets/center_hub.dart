import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:media_kit/media_kit.dart';
import 'app_ui_kit.dart';

class CenterHub extends StatelessWidget {
  final double scale;
  final Player player;

  const CenterHub({
    super.key,
    required this.scale,
    required this.player,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(Symbols.skip_previous_rounded, color: Colors.white70, size: 26 * scale, weight: 300, opticalSize: 24),
            onPressed: () => player.previous(),
          ),
          SizedBox(width: 32 * scale),
          AppOverlayButton(
            scale: scale,
            width: 48 * scale,
            height: 48 * scale,
            borderRadius: 24 * scale,
            opacity: 0.60,
            onTap: () => player.seek(player.state.position - const Duration(seconds: 10)),
            child: Icon(Symbols.replay_10_rounded, color: Colors.white, size: 24 * scale, weight: 300, opticalSize: 24),
          ),
          SizedBox(width: 28 * scale),
          AppOverlayButton(
            scale: scale,
            width: 64 * scale,
            height: 64 * scale,
            borderRadius: 32 * scale,
            opacity: 0.72,
            onTap: () => player.playOrPause(),
            child: StreamBuilder<bool>(
              stream: player.stream.playing,
              initialData: player.state.playing, // Фікс: точний поточний стан без затримки
              builder: (context, snapshot) {
                final playing = snapshot.data ?? player.state.playing;
                return Icon(
                  playing ? Symbols.pause_rounded : Symbols.play_arrow_rounded,
                  color: Colors.white,
                  size: 36 * scale,
                  weight: 300,
                  opticalSize: 24,
                );
              },
            ),
          ),
          SizedBox(width: 28 * scale),
          AppOverlayButton(
            scale: scale,
            width: 48 * scale,
            height: 48 * scale,
            borderRadius: 24 * scale,
            opacity: 0.60,
            onTap: () => player.seek(player.state.position + const Duration(seconds: 10)),
            child: Icon(Symbols.forward_10_rounded, color: Colors.white, size: 24 * scale, weight: 300, opticalSize: 24),
          ),
          SizedBox(width: 32 * scale),
          IconButton(
            icon: Icon(Symbols.skip_next_rounded, color: Colors.white70, size: 26 * scale, weight: 300, opticalSize: 24),
            onPressed: () => player.next(),
          ),
        ],
      ),
    );
  }
}