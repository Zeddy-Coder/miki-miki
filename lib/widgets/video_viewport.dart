import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'app_animation_kit.dart';
import 'app_ui_kit.dart';

class VideoViewport extends StatefulWidget {
  final double scale;
  final VideoController controller;
  final bool isSpeeding;
  final VoidCallback onSpeedStart;
  final VoidCallback onSpeedEnd;
  final VoidCallback onTap;
  /// Подвійний дотик: true = правий бік (вперед), false = лівий (назад); null = вимкнено
  final ValueChanged<bool>? onDoubleTapSide;
  final String doubleTapLabel;
  final List<Widget> overlays;

  const VideoViewport({
    super.key,
    required this.scale,
    required this.controller,
    required this.isSpeeding,
    required this.onSpeedStart,
    required this.onSpeedEnd,
    required this.onTap,
    this.onDoubleTapSide,
    this.doubleTapLabel = '',
    required this.overlays,
  });

  @override
  State<VideoViewport> createState() => _VideoViewportState();
}

class _VideoViewportState extends State<VideoViewport> {
  Offset _tapPos = Offset.zero;
  bool? _flashForward;
  int _flashId = 0;

  void _doubleTap(double width) {
    final forward = _tapPos.dx > width / 2;
    widget.onDoubleTapSide?.call(forward);
    final id = ++_flashId;
    setState(() => _flashForward = forward);
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted && id == _flashId) setState(() => _flashForward = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.scale;
    final controller = widget.controller;
    final isSpeeding = widget.isSpeeding;
    return LayoutBuilder(builder: (context, cons) {
    final width = cons.maxWidth;
    return Stack(
      children: [
        // 1. ВІДЕОПОТІК ТА ЖЕСТИ КЛІКУ (ПРИВ'ЯЗАНІ ТІЛЬКИ ДО ВІДЕОШАРУ)
        Positioned.fill(
          child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onLongPressStart: (_) => widget.onSpeedStart(),
              onLongPressEnd: (_) => widget.onSpeedEnd(),
              onTap: widget.onTap,
              onDoubleTapDown: widget.onDoubleTapSide == null ? null : (d) => _tapPos = d.localPosition,
              onDoubleTap: widget.onDoubleTapSide == null ? null : () => _doubleTap(width),
              child: RepaintBoundary(
                  child: Center(
                    child: Video(
                      controller: controller,
                      controls: NoVideoControls,
                      fit: BoxFit.contain,
                      subtitleViewConfiguration: const SubtitleViewConfiguration(visible: false),
                    ),
                  ),
                ),
          ),
        ),

        // 2. 2.0x ПЛАШКА
        Positioned(
          top: 45 * scale,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: AppPresence(
              visible: isSpeeding,
              child: AppOverlayButton(
                scale: scale,
                width: 104 * scale,
                height: 32 * scale,
                borderRadius: 16 * scale,
                opacity: 0.85,
                child: Text(
                  '▶▶  2.0x',
                  style: TextStyle(
                    fontFamily: 'Arial',
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                    fontSize: 13 * scale,
                  ),
                ),
              ),
            ),
          ),
        ),

        // Індикатор перемотки подвійним дотиком
        Positioned(
          top: 0,
          bottom: 0,
          left: 0,
          right: width / 2,
          child: IgnorePointer(
            child: Center(child: AppPresence(visible: _flashForward == false, slide: Offset.zero, child: _seekChip(scale, false))),
          ),
        ),
        Positioned(
          top: 0,
          bottom: 0,
          left: width / 2,
          right: 0,
          child: IgnorePointer(
            child: Center(child: AppPresence(visible: _flashForward == true, slide: Offset.zero, child: _seekChip(scale, true))),
          ),
        ),

        // 3. НАКЛАДАНІ ВІДЖЕТИ, ШУХЛЯДИ ТА ОВЕРЛЕЇ (ПОВНІСТЮ ІЗОЛЬОВАНІ)
        ...widget.overlays,
      ],
    );
    });
  }

  Widget _seekChip(double scale, bool forward) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16 * scale, vertical: 10 * scale),
      decoration: BoxDecoration(
        color: const Color(0xFF16161A).withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(22 * scale),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(forward ? Icons.fast_forward_rounded : Icons.fast_rewind_rounded, color: Colors.white, size: 22 * scale),
          SizedBox(width: 6 * scale),
          Text(widget.doubleTapLabel, style: TextStyle(fontFamily: 'Arial', color: Colors.white, fontSize: 14 * scale, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}