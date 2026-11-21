import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../services/video_zoom.dart';
import 'app_animation_kit.dart';
import 'line_icons.dart';
import 'player_kit.dart';

class VideoViewport extends StatefulWidget {
  final double scale;
  final VideoController controller;
  final bool isSpeeding;
  final VoidCallback onSpeedStart;
  final VoidCallback onSpeedEnd;
  final VoidCallback onTap;
  /// Double tap: true = right side (forward), false = left (back); null = off
  final ValueChanged<bool>? onDoubleTapSide;
  final String doubleTapLabel;

  /// The rate while the video is held ("2×"), shown at the top while [isSpeeding]
  final String speedLabel;
  final List<Widget> overlays;

  /// Pinch zoom (phone); null means no zoom
  final VideoZoomController? zoom;

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
    this.speedLabel = '2×',
    required this.overlays,
    this.zoom,
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
        // 1. VIDEO STREAM AND CLICK GESTURES (BOUND ONLY TO THE VIDEO LAYER)
        Positioned.fill(
          child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onLongPressStart: (_) => widget.onSpeedStart(),
              onLongPressEnd: (_) => widget.onSpeedEnd(),
              onTap: widget.onTap,
              onDoubleTapDown: widget.onDoubleTapSide == null ? null : (d) => _tapPos = d.localPosition,
              onDoubleTap: widget.onDoubleTapSide == null ? null : () => _doubleTap(width),
              child: RepaintBoundary(
                  child: ClipRect(
                    child: VideoZoomTransform(
                      zoom: widget.zoom,
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
          ),
        ),

        // 2. 2× BADGE (hold on the video)
        Positioned(
          top: 45 * scale,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: AppPresence(
              visible: isSpeeding,
              child: Center(child: _chip(scale, LineIcon.speed, widget.speedLabel, key: const ValueKey('speed-hold'))),
            ),
          ),
        ),

        // Double-tap seek indicator
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

        // 3. OVERLAY WIDGETS, DRAWERS AND OVERLAYS (FULLY ISOLATED)
        ...widget.overlays,
      ],
    );
    });
  }

  Widget _seekChip(double scale, bool forward) =>
      _chip(scale, forward ? LineIcon.forward : LineIcon.replay, widget.doubleTapLabel, key: ValueKey(forward ? 'double-tap-forward' : 'double-tap-back'));

  /// A dark plate over the video with a line icon and a short bold value (double-tap seek, hold for 2×)
  Widget _chip(double scale, LineIcon icon, String text, {Key? key}) {
    return Container(
      key: key,
      height: 40 * scale,
      padding: EdgeInsets.symmetric(horizontal: 14 * scale),
      decoration: BoxDecoration(
        color: const Color(0xDB18181C),
        borderRadius: BorderRadius.circular(20 * scale),
        border: Border.all(color: PlayerTones.pillLine),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          LineIconView(icon, size: 21 * scale, color: PlayerTones.fg),
          SizedBox(width: 8 * scale),
          Text(text, style: TextStyle(fontFamily: 'Arial', fontFamilyFallback: const ['MikiSans'], color: PlayerTones.fg, fontSize: 14 * scale, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
