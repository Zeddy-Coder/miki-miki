import 'dart:io';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../services/thumbnail_service.dart';
import '../services/ui_theme_service.dart';
import 'app_animation_kit.dart';

/// Прев'юшка відео. Бере картинку з кешу; якщо її немає, ставить файл у чергу на
/// генерацію й показує заглушку, поки кадр не буде готовий.
class AppMediaThumbnail extends StatefulWidget {
  final String uri;
  final double scale;
  final double width;
  final double height;
  final double radius;
  final Color? borderColor;

  /// Заглушка, поки прев'юшки немає (за замовчуванням іконка фільму)
  final Widget? fallback;

  /// Накладка поверх картинки (бейджі, кнопка відтворення тощо)
  final Widget? overlay;

  const AppMediaThumbnail({
    super.key,
    required this.uri,
    required this.scale,
    required this.width,
    required this.height,
    this.radius = 6,
    this.borderColor,
    this.fallback,
    this.overlay,
  });

  @override
  State<AppMediaThumbnail> createState() => _AppMediaThumbnailState();
}

class _AppMediaThumbnailState extends State<AppMediaThumbnail> {
  late ValueNotifier<String?> _notifier;

  @override
  void initState() {
    super.initState();
    _notifier = ThumbnailService.watch(widget.uri);
  }

  @override
  void didUpdateWidget(AppMediaThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uri != widget.uri) {
      ThumbnailService.unwatch(oldWidget.uri);
      _notifier = ThumbnailService.watch(widget.uri);
    }
  }

  @override
  void dispose() {
    ThumbnailService.unwatch(widget.uri);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.scale;
    final radius = uiTheme.borderRadius(widget.radius * scale);
    final dpr = MediaQuery.devicePixelRatioOf(context);

    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: uiTheme.bgElevated,
        borderRadius: radius,
        border: Border.all(color: widget.borderColor ?? uiTheme.colors.borderSubtle, width: 1.0),
      ),
      child: ClipRRect(
        borderRadius: uiTheme.borderRadius((widget.radius - 1).clamp(0.0, 100.0) * scale),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: widget.fallback ??
                  Icon(Symbols.movie_rounded, color: uiTheme.textDarkMuted, size: 20 * scale, weight: 300, opticalSize: 24),
            ),
            ValueListenableBuilder<String?>(
              valueListenable: _notifier,
              builder: (context, path, _) {
                if (path == null) return const SizedBox.shrink();
                return Image.file(
                  File(path),
                  fit: BoxFit.cover,
                  cacheWidth: (widget.width * dpr).ceil(),
                  filterQuality: FilterQuality.medium,
                  gaplessPlayback: true,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                    if (wasSynchronouslyLoaded) return child;
                    return AppFade(
                      opacity: frame == null ? 0 : 1,
                      duration: AppAnim.normal,
                      curve: AppAnim.easeOut,
                      child: child,
                    );
                  },
                );
              },
            ),
            if (widget.overlay != null) widget.overlay!,
          ],
        ),
      ),
    );
  }
}
