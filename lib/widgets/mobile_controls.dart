import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:media_kit/media_kit.dart';

import '../models/media_models.dart';
import '../services/playback_clock.dart';
import '../utils/formatters.dart';
import '../utils/platform_info.dart';
import 'app_animation_kit.dart';
import 'app_dock_widgets.dart';
import 'app_ui_kit.dart';

/// Елементи керування відтворенням для телефона (портрет і альбомна).
///
/// Розкладка, звична для мобільних плеєрів:
/// - угорі: «Назад», назва, PiP, поворот екрана, налаштування;
/// - по центру: попередній / −N с / пауза / +N с / наступний;
/// - унизу: повзунок із часом, а під ним швидкість, Anime4K, субтитри, звук, епізоди.
/// Усі цілі дотику не менші за 48 dp. Розміри задано в dp (не залежать від `scale`).
class MobileControls extends StatelessWidget {
  /// Панелі показано (інакше вони прозорі й не ловлять дотики)
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

  /// Крок перемотки, секунди (налаштування «Крок перемотки»)
  final int seekStep;

  /// Кнопки ±крок поруч із паузою (налаштування «Кнопки перемотки на екрані»)
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

  /// Палець узяв/відпустив повзунок прогресу
  final ValueChanged<bool>? onSeekDrag;

  /// «Попередній / наступний»: типово — файли черги; для серій із сайту задає контролер
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  /// false — перемотка й пауза ховаються (серія ще не запустилась, замість них екран стану)
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
  static const double _icon = 26;

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
                // Затемнення під панелями — лише оздоблення, дотики пропускає до відео
                Positioned(top: 0, left: 0, right: 0, child: IgnorePointer(child: _shade(pad.top + 110, true))),
                Positioned(bottom: 0, left: 0, right: 0, child: IgnorePointer(child: _shade(pad.bottom + 170, false))),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(left, pad.top + 6, right, 0),
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
                    padding: EdgeInsets.fromLTRB(left, 0, right, (pad.bottom > 6 ? pad.bottom : 6) + 6),
                    child: _bottomBar(),
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

  // ── Верхня панель ──────────────────────────────────────────────────────────

  Widget _topBar() {
    return Row(
      children: [
        _round(Symbols.arrow_back_rounded, onBack, label: 'Назад'),
        const SizedBox(width: 6),
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
                    style: const TextStyle(fontFamily: 'Arial', color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16, height: 1.15),
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontFamily: 'Arial', color: Colors.white70, fontSize: 12.5, height: 1.2),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        if (pipSupported) ...[
          _round(Symbols.picture_in_picture_alt_rounded, onPip, label: 'Картинка в картинці'),
          const SizedBox(width: 8),
        ],
        _round(
          rotationLocked ? Symbols.screen_lock_rotation_rounded : Symbols.screen_rotation_rounded,
          onRotate,
          onLongPress: onRotateAuto,
          active: rotationLocked,
          label: 'Повернути екран',
        ),
        const SizedBox(width: 8),
        _round(Symbols.settings_rounded, onSettings, active: drawerOwner == 'settings', label: 'Налаштування'),
      ],
    );
  }

  // ── Центр: перемотка й пауза ───────────────────────────────────────────────

  Widget _transport(double width) {
    // Вузький екран (≈360 dp): кнопки трохи менші, щоб ряд не впирався в краї
    final bool narrow = width < 400;
    final double small = narrow ? 50 : _centerSmall;
    final double big = narrow ? 68 : _centerBig;
    final double gap = narrow ? 8 : 14;
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _round(Symbols.skip_previous_rounded, hasQueue ? (onPrevious ?? () => player.previous()) : null, size: small, label: 'Попередній'),
          SizedBox(width: gap),
          if (seekButtons) ...[_seekButton(false, small), SizedBox(width: gap + 2)] else SizedBox(width: 2),
          _playPause(big),
          if (seekButtons) ...[SizedBox(width: gap + 2), _seekButton(true, small)] else SizedBox(width: 2),
          SizedBox(width: gap),
          _round(Symbols.skip_next_rounded, hasQueue ? (onNext ?? () => player.next()) : null, size: small, label: 'Наступний'),
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
        return Semantics(
          button: true,
          label: playing ? 'Пауза' : 'Відтворити',
          child: AppOverlayButton(
            scale: 1.3,
            width: size,
            height: size,
            borderRadius: size / 2,
            opacity: 0.68,
            onTap: () => player.playOrPause(),
            child: AppFadeSwitcher(
              alignment: Alignment.center,
              child: Icon(
                playing ? Symbols.pause_rounded : Symbols.play_arrow_rounded,
                key: ValueKey(playing),
                color: Colors.white,
                size: size * 0.56,
                fill: 1,
                weight: 400,
                opticalSize: 24,
              ),
            ),
          ),
        );
      },
    );
  }

  /// Кнопка перемотки на крок: для 5 / 10 / 30 с є готові значки, для інших — стрілки з числом
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

    final IconData? glyph = switch (step) {
      5 => forward ? Symbols.forward_5_rounded : Symbols.replay_5_rounded,
      10 => forward ? Symbols.forward_10_rounded : Symbols.replay_10_rounded,
      30 => forward ? Symbols.forward_30_rounded : Symbols.replay_30_rounded,
      _ => null,
    };
    return Semantics(
      button: true,
      label: forward ? 'Вперед на $step с' : 'Назад на $step с',
      child: AppOverlayButton(
        scale: 1.2,
        width: size,
        height: size,
        borderRadius: size / 2,
        opacity: 0.6,
        onTap: seek,
        child: glyph != null
            ? Icon(glyph, color: Colors.white, size: _icon + 2, weight: 300, opticalSize: 24)
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(forward ? Symbols.fast_forward_rounded : Symbols.fast_rewind_rounded, color: Colors.white, size: 22, weight: 300, opticalSize: 24),
                  Text('$step', style: const TextStyle(fontFamily: 'Arial', color: Colors.white, fontSize: 11, height: 1.0, fontWeight: FontWeight.w600)),
                ],
              ),
      ),
    );
  }

  // ── Нижня панель: повзунок і швидкі кнопки ─────────────────────────────────

  Widget _bottomBar() {
    final clock = PlaybackClock.of(player);
    final String durText = AppFormatters.formatTime(player.state.duration);
    final double timeW = durText.length * 8.4 + 6;
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
        const SizedBox(height: 6),
        Row(
          children: [
            _speedChip(),
            const SizedBox(width: 8),
            _round(
              Symbols.auto_awesome_rounded,
              onAnime4k,
              onLongPress: onAnime4kToggle,
              active: drawerOwner == 'anime4k',
              badge: anime4kActive,
              label: 'Anime4K',
            ),
            const SizedBox(width: 8),
            _round(Symbols.subtitles_rounded, onSubs, active: drawerOwner == 'subs', badge: subtitlesOn, label: 'Субтитри'),
            const SizedBox(width: 8),
            _round(Symbols.music_note_rounded, onAudio, active: drawerOwner == 'audio', fill: 1, label: 'Аудіодоріжка'),
            const Spacer(),
            _round(Symbols.video_library_rounded, onEpisodes, active: isEpisodesOpen, label: 'Епізоди'),
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
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w500,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    );
  }

  Widget _speedChip() {
    final bool open = drawerOwner == 'speed';
    final bool custom = (currentSpeed - 1.0).abs() > 0.01;
    final Color fg = open || custom ? AppOverlayButton.foreground(true) : Colors.white;
    return Semantics(
      button: true,
      label: 'Швидкість відтворення',
      child: AppOverlayButton(
        scale: 1.2,
        width: 68,
        height: _button,
        borderRadius: _button / 2,
        isActive: open,
        onTap: onSpeed,
        child: Text(
          AppFormatters.formatSpeed(currentSpeed),
          style: TextStyle(fontFamily: 'Arial', color: fg, fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
    );
  }

  /// Кругла скляна кнопка із цілью дотику ≥ 48 dp
  Widget _round(
    IconData icon,
    VoidCallback? onTap, {
    double size = _button,
    VoidCallback? onLongPress,
    bool active = false,
    bool badge = false,
    double fill = 0,
    String? label,
  }) {
    final bool enabled = onTap != null;
    final Color fg = enabled ? AppOverlayButton.foreground(active) : Colors.white38;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: AppOverlayButton(
        scale: 1.2,
        width: size,
        height: size,
        borderRadius: size / 2,
        isActive: active,
        showBadge: badge,
        opacity: enabled ? 0.55 : 0.35,
        onTap: onTap,
        onLongPress: onLongPress,
        child: Icon(icon, color: fg, size: size >= 56 ? _icon + 2 : _icon, fill: fill, weight: 300, opticalSize: 24),
      ),
    );
  }
}
