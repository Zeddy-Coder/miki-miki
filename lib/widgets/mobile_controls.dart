import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../models/media_models.dart';
import '../services/playback_clock.dart';
import '../utils/formatters.dart';
import '../utils/platform_info.dart';
import 'app_animation_kit.dart';
import 'app_dock_widgets.dart';
import 'line_icons.dart';
import 'player_kit.dart';

/// Playback controls for a phone (portrait and landscape).
///
/// A layout familiar from mobile players:
/// - at the top: "Back", the title, PiP, screen rotation, settings;
/// - in the center: previous / −N s / pause / +N s / next;
/// - at the bottom: a slider with the time, and under it speed, Anime4K, subtitles, sound, episodes.
/// All touch targets are at least 48 dp. Sizes are in dp (independent of `scale`).
class MobileControls extends StatelessWidget {
  /// The panels are shown (otherwise they are transparent and catch no touches)
  final bool visible;
  final Player player;
  final String title;
  final String subtitle;
  final List<VideoChapter> chapters;
  final double currentSpeed;
  final bool anime4kActive;
  final bool subtitlesOn;
  final bool hasQueue;
  final bool pipSupported;
  final bool rotationLocked;
  final String? drawerOwner;
  final bool isEpisodesOpen;

  /// Seek step, seconds (the "Крок перемотки" setting)
  final int seekStep;

  /// The ±step buttons next to pause (the "Кнопки перемотки на екрані" setting)
  final bool seekButtons;

  final VoidCallback onBack;
  final VoidCallback onInfo;
  final VoidCallback onPip;
  final VoidCallback onRotate;
  final VoidCallback onRotateAuto;
  final VoidCallback onSettings;
  final VoidCallback onSpeed;
  final VoidCallback onAnime4k;
  final VoidCallback onAnime4kToggle;
  final VoidCallback onSubs;
  final VoidCallback onAudio;
  final VoidCallback onEpisodes;

  /// A finger grabbed / released the progress slider
  final ValueChanged<bool>? onSeekDrag;

  /// "Previous / next": by default queue files; for site episodes the controller sets it
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  /// false: seek and pause are hidden (the episode has not started yet, a state screen replaces them)
  final bool showTransport;

  const MobileControls({
    super.key,
    required this.visible,
    required this.player,
    required this.title,
    required this.subtitle,
    required this.chapters,
    required this.currentSpeed,
    required this.anime4kActive,
    required this.subtitlesOn,
    required this.hasQueue,
    required this.pipSupported,
    required this.rotationLocked,
    required this.drawerOwner,
    required this.isEpisodesOpen,
    required this.seekStep,
    this.seekButtons = true,
    required this.onBack,
    required this.onInfo,
    required this.onPip,
    required this.onRotate,
    required this.onRotateAuto,
    required this.onSettings,
    required this.onSpeed,
    required this.onAnime4k,
    required this.onAnime4kToggle,
    required this.onSubs,
    required this.onAudio,
    required this.onEpisodes,
    this.onSeekDrag,
    this.onPrevious,
    this.onNext,
    this.showTransport = true,
  });

  static const double _button = AppPlatform.touchTarget;
  static const double _centerSmall = 56;
  static const double _centerBig = 72;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final pad = mq.padding;
    final double left = (pad.left > 12 ? pad.left : 12) + 4;
    final double right = (pad.right > 12 ? pad.right : 12) + 4;

    return Positioned.fill(
      child: RepaintBoundary(
        child: AppFade(
          opacity: visible ? 1.0 : 0.0,
          duration: AppAnim.normal,
          child: IgnorePointer(
            ignoring: !visible,
            child: Stack(
              children: [
                // The darkening under the panels is decoration only, it passes touches to the video
                Positioned(top: 0, left: 0, right: 0, child: IgnorePointer(child: _shade(pad.top + 110, true))),
                Positioned(bottom: 0, left: 0, right: 0, child: IgnorePointer(child: _shade(pad.bottom + 170, false))),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(left - 6, pad.top + 4, right - 6, 0),
                    child: _topBar(),
                  ),
                ),
                Positioned.fill(
                  child: Center(
                    child: AppFade(
                      opacity: showTransport ? 1.0 : 0.0,
                      duration: AppAnim.normal,
                      child: IgnorePointer(ignoring: !showTransport, child: _transport(mq.size.width)),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(left, 0, right, (pad.bottom > 6 ? pad.bottom : 6) + 4),
                    child: _bottomBar(mq.size.width),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _shade(double height, bool top) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: top ? Alignment.topCenter : Alignment.bottomCenter,
          end: top ? Alignment.bottomCenter : Alignment.topCenter,
          colors: [Colors.black.withValues(alpha: 0.78), Colors.transparent],
        ),
      ),
    );
  }

  // ── Top bar ──────────────────────────────────────────────────────────

  /// "Back", the title with the grey "серія · озвучка" line (a tap opens the information), PiP, rotation, settings:
  /// line icons straight on the video
  Widget _topBar() {
    return Row(
      children: [
        PlayerIconButton(icon: LineIcon.back, onTap: onBack, label: 'Назад', size: _button, iconSize: 24),
        const SizedBox(width: 4),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onInfo,
            child: Container(
              height: _button,
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: 'Arial', fontFamilyFallback: ['MikiSans'], color: PlayerTones.fg, fontWeight: FontWeight.bold, fontSize: 16, height: 1.2),
                  ),
                  if (subtitle.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontFamily: 'Arial', fontFamilyFallback: ['MikiSans'], color: PlayerTones.sub, fontSize: 12.5, height: 1.2),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        if (pipSupported) PlayerIconButton(icon: LineIcon.pictureInPicture, onTap: onPip, label: 'Картинка в картинці', size: _button, iconSize: 23),
        PlayerIconButton(
          icon: LineIcon.rotate,
          onTap: onRotate,
          onLongPress: onRotateAuto,
          active: rotationLocked,
          label: rotationLocked ? 'Поворот заблоковано' : 'Повернути екран',
          size: _button,
          iconSize: 23,
        ),
        PlayerIconButton(icon: LineIcon.gear, onTap: onSettings, active: drawerOwner == 'settings', label: 'Налаштування', size: _button, iconSize: 23),
      ],
    );
  }

  // ── Center: seek and pause ───────────────────────────────────────────────

  /// Previous · −N s · pause · +N s · next in translucent circles
  Widget _transport(double width) {
    // Narrow screen (≈360 dp): the buttons are a bit smaller so the row does not touch the edges; landscape: the
    // circles stand wider apart, as in the concept
    final bool narrow = width < 400;
    final bool wide = width >= 600;
    final double small = narrow ? 50 : _centerSmall;
    final double big = narrow ? 68 : (wide ? 76 : _centerBig);
    final double gap = narrow ? 10 : (wide ? 30 : 18);
    final prev = hasQueue ? (onPrevious ?? () => player.previous()) : null;
    final next = hasQueue ? (onNext ?? () => player.next()) : null;
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PlayerCircleButton(
            size: small,
            onTap: prev,
            label: 'Попередній',
            child: LineIconView(LineIcon.skipPrevious, size: 25, color: PlayerTones.fg),
          ),
          SizedBox(width: gap),
          if (seekButtons) ...[_seekButton(false, small), SizedBox(width: gap)],
          _playPause(big),
          if (seekButtons) ...[SizedBox(width: gap), _seekButton(true, small)],
          SizedBox(width: gap),
          PlayerCircleButton(
            size: small,
            onTap: next,
            label: 'Наступний',
            child: LineIconView(LineIcon.skipNext, size: 25, color: PlayerTones.fg),
          ),
        ],
      ),
    );
  }

  Widget _playPause(double size) {
    return StreamBuilder<bool>(
      stream: player.stream.playing,
      initialData: player.state.playing,
      builder: (context, snapshot) {
        final playing = snapshot.data ?? player.state.playing;
        return PlayerCircleButton(
          size: size,
          big: true,
          onTap: () => player.playOrPause(),
          label: playing ? 'Пауза' : 'Відтворити',
          child: AppFadeSwitcher(
            alignment: Alignment.center,
            child: LineIconView(playing ? LineIcon.pause : LineIcon.play, key: ValueKey(playing), size: size * 0.44, color: PlayerTones.fg, stroke: 1.2),
          ),
        );
      },
    );
  }

  /// A step-seek button: a round arrow with the step in the middle
  Widget _seekButton(bool forward, double size) {
    final step = seekStep;
    final Duration d = Duration(seconds: step);
    void seek() {
      final pos = player.state.position;
      final total = player.state.duration;
      var target = forward ? pos + d : pos - d;
      if (target < Duration.zero) target = Duration.zero;
      if (total > Duration.zero && target > total) target = total;
      player.seek(target);
    }

    return PlayerCircleButton(
      key: ValueKey(forward ? 'seek-forward' : 'seek-back'),
      size: size,
      onTap: seek,
      label: forward ? 'Вперед на $step с' : 'Назад на $step с',
      child: PlayerSeekGlyph(forward: forward, seconds: step, size: 28),
    );
  }

  // ── Bottom bar: slider and quick buttons ─────────────────────────────────

  /// The time and the slider; under them "1×", Anime4K, subtitles, sound and, on the right, "Серії"
  Widget _bottomBar(double width) {
    final clock = PlaybackClock.of(player);
    final String durText = AppFormatters.formatTime(player.state.duration);
    final double timeW = durText.length * 8.2 + 6;
    // A narrow portrait screen: "Серії" is only an icon
    final bool wide = width >= 520;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            AppClockBuilder<int>(
              listenable: clock.seconds,
              live: visible,
              builder: (context, sec) => _time(AppFormatters.formatTime(Duration(seconds: sec)), timeW, TextAlign.left),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: AppSeekBar(
                scale: 1.45,
                hitHeight: _button,
                bubbleScale: 1.0,
                player: player,
                chapters: chapters,
                live: visible,
                onDragChanged: onSeekDrag,
              ),
            ),
            const SizedBox(width: 6),
            AppClockBuilder<Duration>(
              listenable: clock.duration,
              live: visible,
              builder: (context, dur) => _time(AppFormatters.formatTime(dur), timeW, TextAlign.right),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            _speedChip(),
            const SizedBox(width: 4),
            PlayerIconButton(
              icon: LineIcon.sparkle,
              onTap: onAnime4k,
              onLongPress: onAnime4kToggle,
              active: drawerOwner == 'anime4k',
              badge: anime4kActive,
              label: 'Anime4K',
              size: _button,
              iconSize: 23,
            ),
            PlayerIconButton(
              icon: LineIcon.subtitles,
              onTap: onSubs,
              active: drawerOwner == 'subs',
              badge: subtitlesOn,
              label: 'Субтитри',
              size: _button,
              iconSize: 23,
            ),
            PlayerIconButton(icon: LineIcon.musicNote, onTap: onAudio, active: drawerOwner == 'audio', label: 'Аудіодоріжка', size: _button, iconSize: 23),
            const Spacer(),
            PlayerPill(
              key: const ValueKey('player-episodes'),
              icon: LineIcon.list,
              text: wide ? 'Серії' : null,
              label: 'Серії',
              active: isEpisodesOpen,
              onTap: onEpisodes,
              hitHeight: _button,
            ),
          ],
        ),
      ],
    );
  }

  Widget _time(String text, double width, TextAlign align) {
    return SizedBox(
      width: width,
      child: Text(
        text,
        textAlign: align,
        maxLines: 1,
        style: const TextStyle(
          fontFamily: 'Arial',
          color: PlayerTones.fg,
          fontSize: 13.5,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    );
  }

  /// "1×": a pill; accent while its menu is open or the speed is not normal
  Widget _speedChip() {
    final bool open = drawerOwner == 'speed';
    final bool custom = (currentSpeed - 1.0).abs() > 0.01;
    return PlayerPill(
      key: const ValueKey('player-speed'),
      text: AppFormatters.formatSpeed(currentSpeed),
      label: 'Швидкість відтворення',
      active: open || custom,
      onTap: onSpeed,
      hitHeight: _button,
    );
  }
}
