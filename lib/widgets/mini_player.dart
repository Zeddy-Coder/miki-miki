import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';
import '../services/ui_theme_service.dart';
import 'app_animation_kit.dart';
import 'app_dock_widgets.dart';
import 'app_ui_kit.dart';

/// Міні-плеєр: відео в маленькому вікні поверх усіх. Керування з'являється при наведенні.
class MiniPlayer extends StatefulWidget {
  final Player player;
  final VideoController controller;
  final String title;
  final VoidCallback onExpand;
  final VoidCallback onClose;

  const MiniPlayer({
    super.key,
    required this.player,
    required this.controller,
    required this.title,
    required this.onExpand,
    required this.onClose,
  });

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = (constraints.maxWidth / 480.0).clamp(0.6, 1.4);

        return MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: Container(
            color: Colors.black,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Відео: клік — пауза/пуск, перетягування — переміщення вікна
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.player.playOrPause,
                  onPanStart: (_) => windowManager.startDragging(),
                  child: Video(
                    controller: widget.controller,
                    controls: NoVideoControls,
                    fit: BoxFit.contain,
                    subtitleViewConfiguration: const SubtitleViewConfiguration(visible: false),
                  ),
                ),
                Positioned.fill(
                  child: AppPresence(
                    expand: true,
                    visible: _hover,
                    slide: Offset.zero,
                    child: _buildOverlay(scale),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildOverlay(double scale) {
    return Stack(
      children: [
        // Верх: назва + розгорнути / закрити
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanStart: (_) => windowManager.startDragging(),
            child: Container(
              padding: EdgeInsets.fromLTRB(12 * scale, 8 * scale, 8 * scale, 14 * scale),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.black.withValues(alpha: 0.85), Colors.transparent],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Arial',
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                        fontSize: 12.5 * scale,
                      ),
                    ),
                  ),
                  SizedBox(width: 8 * scale),
                  AppOverlayButton(
                    scale: scale,
                    width: 30 * scale,
                    height: 28 * scale,
                    borderRadius: 7 * scale,
                    onTap: widget.onExpand,
                    child: Icon(Symbols.open_in_full_rounded, color: Colors.white, size: 16 * scale, weight: 300, opticalSize: 24),
                  ),
                  SizedBox(width: 6 * scale),
                  AppOverlayButton(
                    scale: scale,
                    width: 30 * scale,
                    height: 28 * scale,
                    borderRadius: 7 * scale,
                    onTap: widget.onClose,
                    child: Icon(Symbols.close_rounded, color: Colors.white, size: 17 * scale, weight: 300, opticalSize: 24),
                  ),
                ],
              ),
            ),
          ),
        ),

        // Центр: пауза / пуск
        Center(
          child: StreamBuilder<bool>(
            stream: widget.player.stream.playing,
            initialData: widget.player.state.playing,
            builder: (context, snap) {
              final playing = snap.data ?? false;
              return AppOverlayButton(
                scale: scale,
                width: 46 * scale,
                height: 46 * scale,
                borderRadius: 23 * scale,
                onTap: widget.player.playOrPause,
                child: AppFadeSwitcher(
                  alignment: Alignment.center,
                  child: Icon(
                    playing ? Symbols.pause_rounded : Symbols.play_arrow_rounded,
                    key: ValueKey(playing),
                    color: Colors.white,
                    size: 28 * scale,
                    fill: 1,
                  ),
                ),
              );
            },
          ),
        ),

        // Низ: прогрес
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _buildProgress(scale),
        ),
      ],
    );
  }

  Widget _buildProgress(double scale) {
    return LayoutBuilder(
      builder: (context, c) {
        void seekTo(double dx) {
          final total = widget.player.state.duration.inMilliseconds;
          if (total <= 0) return;
          final f = (dx / c.maxWidth).clamp(0.0, 1.0);
          widget.player.seek(Duration(milliseconds: (total * f).round()));
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => seekTo(d.localPosition.dx),
          onHorizontalDragUpdate: (d) => seekTo(d.localPosition.dx),
          child: Container(
            height: 18 * scale,
            alignment: Alignment.bottomLeft,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.transparent, Colors.black.withValues(alpha: 0.7)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            // Смужка оновлюється в проміле — не на кожну подію позиції
            child: AppProgressLine(
              player: widget.player,
              height: 3 * scale,
              trackColor: Colors.white.withValues(alpha: 0.25),
              fillColor: uiTheme.accentOnDark,
            ),
          ),
        );
      },
    );
  }
}
