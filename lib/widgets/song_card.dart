/// The opening's / ending's song over the video: in the top left corner on a soft shade, the track's cover with a "now
/// playing" equalizer (as YouTube Music has it), which song it is, the title and the artist. Shown in the song's first
/// seconds and whenever the controls are (under the top bar then); a tap opens where to listen to it («Пісня»).
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../models/media_models.dart';
import '../services/hikka_images.dart';
import '../services/playback_clock.dart';
import '../services/songs/song_service.dart';
import '../services/songs/theme_songs.dart';
import '../services/storage_service.dart';
import 'app_animation_kit.dart';
import 'app_dock_widgets.dart';
import 'app_tones.dart';
import 'line_icons.dart';
import 'player_kit.dart';

/// Three bars rising and falling, each on its own beat; still while paused
class EqualizerPainter extends CustomPainter {
  final Animation<double> clock;
  EqualizerPainter(this.clock) : super(repaint: clock);

  static const List<double> _phase = [0.0, 1.7, 0.8];
  static const List<double> _speed = [6.1, 7.9, 5.3];

  /// The height of bar [i] (0…1) at [t] seconds
  static double level(int i, double t) => 0.32 + 0.68 * (0.5 + 0.5 * math.sin(t * _speed[i] + _phase[i]));

  @override
  void paint(Canvas canvas, Size size) {
    final t = clock.value * 4.0; // the controller runs 0…1 over 4 s
    final w = size.width * 0.16;
    final gap = size.width * 0.12;
    final total = 3 * w + 2 * gap;
    final paint = Paint()..color = Colors.white;
    for (var i = 0; i < 3; i++) {
      final h = size.height * level(i, t);
      final x = (size.width - total) / 2 + i * (w + gap);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, size.height - h, w, h), Radius.circular(w / 2)), paint);
    }
  }

  @override
  bool shouldRepaint(EqualizerPainter old) => old.clock != clock;
}

/// A song's cover, rounded; [equalizer] — the bars over a shade, moving while [playing]. Without a cover: a quiet plate
/// with a note
class SongCover extends StatefulWidget {
  final String? url;
  final double size;
  final bool equalizer;
  final ValueListenable<bool>? playing;

  const SongCover({super.key, required this.url, required this.size, this.equalizer = false, this.playing});

  @override
  State<SongCover> createState() => _SongCoverState();
}

class _SongCoverState extends State<SongCover> with SingleTickerProviderStateMixin {
  late final AnimationController _beat = AnimationController(vsync: this, duration: const Duration(seconds: 4));

  @override
  void initState() {
    super.initState();
    widget.playing?.addListener(_sync);
    _sync();
  }

  @override
  void didUpdateWidget(SongCover old) {
    super.didUpdateWidget(old);
    if (old.playing != widget.playing) {
      old.playing?.removeListener(_sync);
      widget.playing?.addListener(_sync);
    }
    _sync();
  }

  void _sync() {
    final run = widget.equalizer && (widget.playing?.value ?? false);
    if (run && !_beat.isAnimating) {
      _beat.repeat();
    } else if (!run && _beat.isAnimating) {
      _beat.stop();
    }
  }

  @override
  void dispose() {
    widget.playing?.removeListener(_sync);
    _beat.dispose();
    super.dispose();
  }

  Widget _blank() => DecoratedBox(
        decoration: BoxDecoration(color: AppTones.plate),
        child: Center(child: LineIconView(LineIcon.musicNote, size: widget.size * 0.42, color: AppTones.plateText)),
      );

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final url = widget.url;
    return ClipRRect(
      borderRadius: BorderRadius.circular(s * 0.16),
      child: SizedBox.square(
        dimension: s,
        child: Stack(fit: StackFit.expand, children: [
          if (url == null)
            _blank()
          else
            Image(image: HikkaImage(url), fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (_, _, _) => _blank()),
          if (widget.equalizer) ...[
            const ColoredBox(color: Color(0x61000000)),
            Center(
              child: SizedBox.square(
                dimension: s * 0.46,
                child: RepaintBoundary(child: CustomPaint(painter: EqualizerPainter(_beat))),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

/// The card while an opening or an ending with a known song plays
class SongCard extends StatefulWidget {
  final double scale;

  /// A phone: its safe insets, its top bar
  final bool touch;
  final bool showControls;

  /// A menu or a panel is open: the card steps aside
  final bool hidden;
  final Player player;
  final List<VideoChapter> chapters;
  final ValueListenable<EpisodeSongs?> songs;
  final void Function(SongKind kind, GlobalKey key) onOpen;

  /// How long the card stays at the start of the song without the controls
  static const Duration early = Duration(seconds: 8);

  const SongCard({
    super.key,
    required this.scale,
    this.touch = false,
    required this.showControls,
    this.hidden = false,
    required this.player,
    required this.chapters,
    required this.songs,
    required this.onOpen,
  });

  @override
  State<SongCard> createState() => _SongCardState();
}

class _SongCardState extends State<SongCard> {
  final GlobalKey _key = GlobalKey();
  late ClockValue<int> _state;
  late List<VideoChapter> _chapters;

  @override
  void initState() {
    super.initState();
    _chapters = widget.chapters;
    _state = _derive();
  }

  ClockValue<int> _derive() => PlaybackClock.of(widget.player).derive((pos, dur) => ChapterMath.songStateAt(_chapters, pos, dur, early: SongCard.early));

  @override
  void didUpdateWidget(SongCard old) {
    super.didUpdateWidget(old);
    if (!identical(old.chapters, widget.chapters)) _chapters = widget.chapters;
    if (old.player != widget.player) {
      _state.dispose();
      _state = _derive();
    } else {
      _state.refresh();
    }
  }

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<EpisodeSongs?>(
      valueListenable: widget.songs,
      builder: (context, songs, _) => AppClockBuilder<int>(
        listenable: _state,
        builder: (context, state) {
          final kind = state < 0 ? null : ChapterMath.songKindOf(_chapters[state ~/ 2]);
          final song = kind == null ? null : songs?.of(kind);
          final early = state >= 0 && state.isOdd;
          final show = song != null && !widget.hidden && (early || widget.showControls) && StorageService.getShowThemeSongs();
          return _layout(context, show ? (song, songs!.art[kind!]?.cover, kind) : null);
        },
      ),
    );
  }

  /// The corner: a soft shade from the top left (it lets touches through to the video) and the song on it — under
  /// the top bar while the controls are shown
  Widget _layout(BuildContext context, (ThemeSong, String?, SongKind)? now) {
    final touch = widget.touch;
    final s = touch ? 1.0 : widget.scale;
    final EdgeInsets safe = touch ? MediaQuery.paddingOf(context) : EdgeInsets.zero;
    final double top = touch ? (widget.showControls ? 60.0 : 14.0) + safe.top : (widget.showControls ? 64.0 : 22.0) * s;
    final double left = touch ? 18.0 + safe.left : 26.0 * s;
    final double shadeW = (touch ? 470.0 : 640.0 * s) + safe.left;
    final double shadeH = (touch ? 210.0 : 260.0 * s) + safe.top;
    return Positioned.fill(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: 0,
            left: 0,
            child: IgnorePointer(
              child: AppFade(
                opacity: now == null ? 0.0 : 1.0,
                duration: AppAnim.medium,
                child: SizedBox(
                  width: shadeW,
                  height: shadeH,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment.topLeft,
                        radius: 2.0,
                        colors: [Color(0xA6000000), Color(0x66000000), Color(0x00000000)],
                        stops: [0.0, 0.45, 1.0],
                        transform: _CornerEllipse(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          AppAnimatedPositioned(
            duration: AppAnim.medium,
            curve: AppAnim.easeOut,
            top: top,
            left: left,
            child: now == null
                ? const AppPresence(visible: false, child: SizedBox.shrink())
                : AppPresence(visible: true, slide: const Offset(-0.06, 0), child: _card(now.$1, now.$2, now.$3)),
          ),
        ],
      ),
    );
  }

  Widget _card(ThemeSong song, String? cover, SongKind kind) {
    final touch = widget.touch;
    final s = touch ? 1.0 : widget.scale;
    // A PC's screen is far bigger than a phone's: the song is larger there too
    final double side = touch ? 56.0 : 64 * s;
    const shadow = [Shadow(color: Color(0x73000000), blurRadius: 8)];
    return RepaintBoundary(
      child: Material(
        color: Colors.transparent,
        child: Semantics(
          button: true,
          label: '${song.label}: ${song.title}${song.artists.isEmpty ? '' : ', ${song.artist}'}. Де послухати',
          child: InkWell(
            key: _key,
            onTap: () => widget.onOpen(kind, _key),
            borderRadius: BorderRadius.circular(12 * s),
            splashColor: Colors.transparent,
            highlightColor: Colors.white.withValues(alpha: 0.10),
            hoverColor: Colors.white.withValues(alpha: 0.08),
            child: Padding(
              padding: EdgeInsets.fromLTRB(4 * s, 4 * s, 12 * s, 4 * s),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SongCover(url: cover, size: side, equalizer: true, playing: PlaybackClock.of(widget.player).playing),
                  SizedBox(width: 14 * s),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: touch ? 260.0 : 380 * s),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          song.label.toUpperCase(),
                          maxLines: 1,
                          style: playerText(touch ? 11.0 : 12 * s, color: const Color(0xB3FFFFFF), weight: FontWeight.w700).copyWith(letterSpacing: 1.1, shadows: shadow),
                        ),
                        SizedBox(height: 3 * s),
                        Text(
                          song.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: playerText(touch ? 17.0 : 20 * s, color: PlayerTones.fg, weight: FontWeight.bold).copyWith(shadows: shadow),
                        ),
                        if (song.artists.isNotEmpty) ...[
                          SizedBox(height: 2 * s),
                          Text(
                            song.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: playerText(touch ? 14.0 : 15.5 * s, color: const Color(0xD9FFFFFF)).copyWith(shadows: shadow),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The corner shade spreads twice as wide as it is tall
class _CornerEllipse extends GradientTransform {
  const _CornerEllipse();

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) => Matrix4.identity()
    ..translateByDouble(bounds.left, bounds.top, 0, 1)
    ..scaleByDouble(1.0, 0.5, 1.0, 1)
    ..translateByDouble(-bounds.left, -bounds.top, 0, 1);
}

/// A streaming app's emblem: the icon the app's own site gives (loaded like a browser shows a site's icon, kept on
/// disk), and its initial on a quiet plate until then or without the network
class MusicAppBadge extends StatelessWidget {
  final MusicApp app;
  final double size;
  const MusicAppBadge({super.key, required this.app, required this.size});

  static String _domain(MusicApp app) => switch (app) {
        MusicApp.spotify => 'open.spotify.com',
        MusicApp.youtubeMusic => 'music.youtube.com',
        MusicApp.appleMusic => 'music.apple.com',
        MusicApp.youtube => 'www.youtube.com',
      };

  /// Where its icon comes from
  static String iconUrl(MusicApp app) => 'https://www.google.com/s2/favicons?domain=${_domain(app)}&sz=64';

  @override
  Widget build(BuildContext context) {
    final initial = Center(
      child: Text(musicAppName(app).substring(0, 1), style: playerText(size * 0.5, color: AppTones.plateText, weight: FontWeight.w700)),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.24),
      child: SizedBox.square(
        dimension: size,
        child: DecoratedBox(
          decoration: BoxDecoration(color: AppTones.plate),
          child: Image(
            image: HikkaImage(iconUrl(app)),
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
            frameBuilder: (context, child, frame, sync) => frame == null ? initial : child,
            errorBuilder: (_, _, _) => initial,
          ),
        ),
      ),
    );
  }
}
