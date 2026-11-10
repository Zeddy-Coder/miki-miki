import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../services/playback_clock.dart';
import '../services/ui_theme_service.dart';
import '../utils/formatters.dart';
import '../utils/platform_info.dart';
import 'app_animation_kit.dart';
import 'app_dock_widgets.dart';

/// Згорнутий плеєр: компактна картка в куті головної сторінки.
/// Відтворення триває, по кліку плеєр розгортається назад.
class CollapsedPlayer extends StatelessWidget {
  final double scale;
  final Player player;
  final VideoController controller;
  final String title;
  final VoidCallback onExpand;
  final VoidCallback onClose;

  /// Ширина картки (null — стандартна 380 × масштаб). Телефон у портреті: на всю ширину екрана
  final double? width;

  const CollapsedPlayer({
    super.key,
    required this.scale,
    required this.player,
    required this.controller,
    required this.title,
    required this.onExpand,
    required this.onClose,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    final clock = PlaybackClock.of(player);
    final r = uiTheme.borderRadius(14 * scale);
    final w = width ?? 380.0 * scale;
    final videoW = 120.0 * scale;
    final videoH = videoW * 9 / 16;

    return Material(
      color: Colors.transparent,
      child: Container(
        width: w,
        decoration: BoxDecoration(
          color: uiTheme.bgSurface,
          borderRadius: r,
          border: Border.all(color: uiTheme.borderSubtle, width: 1.0),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: uiTheme.isLight ? 0.14 : 0.55),
              blurRadius: 24 * scale,
              offset: Offset(0, 8 * scale),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: r,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: onExpand,
                splashColor: Colors.transparent,
                highlightColor: uiTheme.touchHighlight,
                hoverColor: uiTheme.hoverOverlay,
                child: Padding(
                  padding: EdgeInsets.all(8 * scale),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: uiTheme.borderRadius(8 * scale),
                        child: Container(
                          width: videoW,
                          height: videoH,
                          color: Colors.black,
                          child: IgnorePointer(
                            child: Video(
                              controller: controller,
                              controls: NoVideoControls,
                              fit: BoxFit.cover,
                              subtitleViewConfiguration: const SubtitleViewConfiguration(visible: false),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: 12 * scale),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: 'Arial',
                                color: uiTheme.textPrimary,
                                fontWeight: FontWeight.w600,
                                fontSize: 12.5 * scale,
                              ),
                            ),
                            SizedBox(height: 4 * scale),
                            // Підпис оновлюється раз на секунду (а не на кожну подію позиції)
                            ListenableBuilder(
                              listenable: Listenable.merge([clock.seconds, clock.duration]),
                              builder: (context, _) => Text(
                                '${AppFormatters.formatTime(Duration(seconds: clock.seconds.value))} / ${AppFormatters.formatTime(clock.duration.value)}',
                                style: TextStyle(fontFamily: 'Arial', color: uiTheme.textMuted, fontSize: 11 * scale),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(width: 8 * scale),
                      _iconButton(
                        scale,
                        StreamBuilder<bool>(
                          stream: player.stream.playing,
                          initialData: player.state.playing,
                          builder: (context, snap) {
                            final playing = snap.data ?? false;
                            return AppFadeSwitcher(
                              alignment: Alignment.center,
                              child: Icon(
                                playing ? Symbols.pause_rounded : Symbols.play_arrow_rounded,
                                key: ValueKey(playing),
                                color: uiTheme.accentColor,
                                size: 22 * scale,
                                fill: 1,
                              ),
                            );
                          },
                        ),
                        player.playOrPause,
                      ),
                      SizedBox(width: 4 * scale),
                      _iconButton(
                        scale,
                        Icon(Symbols.close_rounded, color: uiTheme.textMuted, size: 19 * scale, weight: 300, opticalSize: 24),
                        onClose,
                      ),
                    ],
                  ),
                ),
              ),
              // Прогрес (у проміле: ~1 оновлення на секунду, а не 24–60)
              AppProgressLine(
                player: player,
                height: 3 * scale,
                trackColor: uiTheme.borderSubtle,
                fillColor: uiTheme.accentColor,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _iconButton(double scale, Widget icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: uiTheme.borderRadius(8 * scale),
      splashColor: Colors.transparent,
      highlightColor: uiTheme.touchHighlight,
      hoverColor: uiTheme.hoverOverlay,
      // Кнопки не менші за 48 dp на телефоні
      child: SizedBox(
        width: AppPlatform.isMobile ? AppPlatform.touchTarget : 34 * scale,
        height: AppPlatform.isMobile ? AppPlatform.touchTarget : 34 * scale,
        child: Center(child: icon),
      ),
    );
  }
}
