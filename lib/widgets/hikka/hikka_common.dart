import '../../services/anilist_posters.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SliverConstraints, SliverGridLayout, SliverGridRegularTileLayout;
import 'package:material_symbols_icons/symbols.dart';

import '../../services/hikka_api.dart';
import '../../services/hikka_images.dart';
import '../../services/hikka_pager.dart';
import '../../services/ui_theme_service.dart';
import '../../utils/platform_info.dart';
import '../app_animation_kit.dart';
import '../app_ui_kit.dart';

/// Спільні розміри сторінок каталогу
class HikkaLayout {
  const HikkaLayout._();

  /// Вузький екран телефона (портрет)
  static bool compact(BuildContext context) =>
      AppPlatform.isMobile && AppLayout(MediaQuery.sizeOf(context)).isCompactWidth;

  /// Бічний відступ вмісту
  static double sidePad(BuildContext context, double scale) => compact(context) ? 16.0 : 24 * scale;

  /// Найбільша ширина вмісту (на надшироких вікнах решта лишається порожньою)
  static const double maxContentWidth = 1240;

  /// Висота рядка заголовка сторінки
  static double barHeight(double scale) => AppPlatform.isMobile ? 56.0 : 52 * scale;
}

/// Стиль тексту сторінок каталогу (Arial, кольори теми). Розмір уже помножений на масштаб.
TextStyle hikkaStyle(
  double size, {
  Color? color,
  FontWeight weight = FontWeight.normal,
  double? height,
}) =>
    TextStyle(fontFamily: 'Arial', color: color ?? uiTheme.textPrimary, fontSize: size, fontWeight: weight, height: height);

// ── Зображення ───────────────────────────────────────────────────────────────

/// Постер / портрет з диска чи мережі: знизу заглушка, зображення плавно проявляється,
/// запит іде на зменшену копію під ширину елемента.
class HikkaPoster extends StatelessWidget {
  final String? url;
  final double scale;

  /// Ширина / висота
  final double aspect;
  final double radius;
  final IconData icon;
  final Widget? overlay;
  final BoxFit fit;
  final Alignment alignment;
  final bool border;

  /// MAL-id тайтлу: якщо задано, постер береться з AniList (якісніший, без тексту), а Hikka лишається запасним
  final int malId;

  const HikkaPoster({
    super.key,
    required this.url,
    this.malId = 0,
    required this.scale,
    this.aspect = 0.7,
    this.radius = 10,
    this.icon = Symbols.image_rounded,
    this.overlay,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.topCenter,
    this.border = true,
  });

  @override
  Widget build(BuildContext context) {
    if (malId <= 0) return _build(context, url);
    return ListenableBuilder(
      listenable: AniListPosters.instance,
      builder: (context, _) {
        final found = AniListPosters.instance.lookup(malId);
        // Поки AniList відповідає — заглушка, щоб не вантажити малий постер Hikka даремно
        if (found == null) return _build(context, null);
        return _build(context, found.isEmpty ? url : found);
      },
    );
  }

  Widget _build(BuildContext context, String? src) {
    final r = uiTheme.borderRadius(radius * scale);
    final placeholder = ColoredBox(
      color: uiTheme.bgElevated,
      child: Center(child: Icon(icon, size: 26 * scale, color: uiTheme.textDarkMuted.withValues(alpha: 0.6), weight: 300)),
    );
    final Widget picture = src == null
        ? placeholder
        : LayoutBuilder(
            builder: (context, c) {
              final w = c.maxWidth.isFinite ? c.maxWidth : 160.0;
              final px = HikkaImages.bucket(w, MediaQuery.devicePixelRatioOf(context));
              final resized = HikkaImages.resized(src, width: px);
              final provider = ResizeImage.resizeIfNeeded(px, null, HikkaImage(resized, fallback: resized == src ? null : src));
              return Stack(
                fit: StackFit.expand,
                children: [
                  placeholder,
                  Image(
                    image: provider,
                    fit: fit,
                    alignment: alignment,
                    gaplessPlayback: true,
                    filterQuality: FilterQuality.medium,
                    frameBuilder: (context, child, frame, sync) =>
                        sync ? child : AppFade(opacity: frame == null ? 0 : 1, child: child),
                    errorBuilder: (context, error, stack) => const SizedBox.shrink(),
                  ),
                ],
              );
            },
          );

    return AspectRatio(
      aspectRatio: aspect,
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: r,
          border: border ? Border.all(color: uiTheme.borderSubtle) : null,
        ),
        child: ClipRRect(
          borderRadius: r,
          child: Stack(fit: StackFit.expand, children: [picture, if (overlay != null) overlay!]),
        ),
      ),
    );
  }
}

// ── Завантаження даних ───────────────────────────────────────────────────────

/// Показує заглушку, поки вантажаться дані, потім вміст; при збої — повідомлення з кнопкою «Повторити».
/// [initial] — уже відомі дані (сторінка вже відкривалась): показуються одразу, без запиту.
class HikkaAsync<T> extends StatefulWidget {
  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data) builder;
  final WidgetBuilder? loading;
  final T? initial;
  final ValueChanged<T>? onLoaded;

  /// Інше значення — завантажити заново
  final Object? reloadKey;
  final double scale;

  /// Стислий вигляд помилки (полиці, малі блоки)
  final bool compactError;

  /// Рамка навколо заглушки завантаження та помилки (наприклад, заголовок секції)
  final Widget Function(BuildContext context, Widget child)? stateFrame;

  const HikkaAsync({
    super.key,
    required this.load,
    required this.builder,
    required this.scale,
    this.loading,
    this.initial,
    this.onLoaded,
    this.reloadKey,
    this.compactError = false,
    this.stateFrame,
  });

  @override
  State<HikkaAsync<T>> createState() => _HikkaAsyncState<T>();
}

class _HikkaAsyncState<T> extends State<HikkaAsync<T>> {
  T? _data;
  Object? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _data = widget.initial;
    if (_data == null) _start();
  }

  @override
  void didUpdateWidget(HikkaAsync<T> old) {
    super.didUpdateWidget(old);
    if (old.reloadKey != widget.reloadKey) {
      _data = widget.initial;
      _error = null;
      if (_data == null) _start();
    }
  }

  void _start() {
    final gen = ++_generation;
    if (_error != null) setState(() => _error = null); // «Повторити»: назад до індикатора
    widget.load().then<void>((value) {
      if (!mounted || gen != _generation) return;
      widget.onLoaded?.call(value);
      setState(() => _data = value);
    }, onError: (Object e) {
      if (!mounted || gen != _generation) return;
      setState(() => _error = e);
    });
  }

  @override
  Widget build(BuildContext context) {
    final Widget child;
    if (_data != null) {
      child = KeyedSubtree(key: const ValueKey('data'), child: widget.builder(context, _data as T));
    } else if (_error != null) {
      final view = HikkaErrorView(scale: widget.scale, error: _error!, onRetry: _start, compact: widget.compactError);
      child = KeyedSubtree(key: const ValueKey('error'), child: widget.stateFrame?.call(context, view) ?? view);
    } else {
      final view = widget.loading?.call(context) ?? HikkaLoading(scale: widget.scale);
      child = KeyedSubtree(key: const ValueKey('loading'), child: widget.stateFrame?.call(context, view) ?? view);
    }
    return AppFadeSwitcher(duration: AppAnim.normal, child: child);
  }
}

/// Індикатор завантаження за замовчуванням
class HikkaLoading extends StatelessWidget {
  final double scale;
  final double height;

  const HikkaLoading({super.key, required this.scale, this.height = 160});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: Center(
        child: SizedBox(
          width: 26 * scale,
          height: 26 * scale,
          child: CircularProgressIndicator(strokeWidth: 2.4, color: uiTheme.accentColor),
        ),
      ),
    );
  }
}

/// Помилка завантаження: текст зрозумілою мовою й кнопка повтору
class HikkaErrorView extends StatelessWidget {
  final double scale;
  final Object error;
  final VoidCallback onRetry;
  final bool compact;

  const HikkaErrorView({super.key, required this.scale, required this.error, required this.onRetry, this.compact = false});

  static String messageOf(Object error) =>
      error is HikkaException ? error.message : 'Не вдалося завантажити. Спробуйте ще раз.';

  @override
  Widget build(BuildContext context) {
    final e = error;
    final offline = e is HikkaException && (e.kind == HikkaErrorKind.network || e.kind == HikkaErrorKind.timeout);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: (compact ? 14 : 36) * scale),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              offline ? Symbols.cloud_off_rounded : Symbols.error_rounded,
              color: uiTheme.textDarkMuted,
              size: (compact ? 24 : 32) * scale,
              weight: 300,
            ),
            SizedBox(height: 8 * scale),
            Text(
              messageOf(error),
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Arial', color: uiTheme.textMuted, fontSize: 13 * scale, height: 1.35),
            ),
            SizedBox(height: 12 * scale),
            AppSecondaryButton(scale: scale, expand: false, icon: Symbols.refresh_rounded, label: 'Повторити', onTap: onRetry),
          ],
        ),
      ),
    );
  }
}

// ── Дрібні елементи ──────────────────────────────────────────────────────────

/// Мітка: жанр, тип, статус; натискна — фільтр
class HikkaChip extends StatelessWidget {
  final String label;
  final double scale;
  final IconData? icon;
  final bool selected;
  final VoidCallback? onTap;

  /// Акцентне оформлення без вибору (статус «виходить»)
  final bool highlight;

  /// Свій колір замість акценту (статуси списків): значок завжди кольоровий, вибраний чип підсвічується ним
  final Color? color;

  const HikkaChip({
    super.key,
    required this.label,
    required this.scale,
    this.icon,
    this.selected = false,
    this.onTap,
    this.highlight = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final bool accent = selected || highlight;
    final base = color ?? uiTheme.accentColor;
    final fg = accent ? base : uiTheme.textMuted;
    final iconColor = color != null ? base : fg;
    final r = uiTheme.borderRadius(16 * scale);
    final double minH = onTap == null ? 26 * scale : (AppPlatform.isMobile ? 40.0 : 30 * scale);
    final content = ConstrainedBox(
      constraints: BoxConstraints(minHeight: minH),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 4 * scale),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, color: iconColor, size: 15 * scale, weight: 300),
              SizedBox(width: 5 * scale),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Arial',
                  color: fg,
                  fontSize: 12 * scale,
                  fontWeight: accent ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return Material(
      color: accent ? (color != null ? base.withValues(alpha: 0.16) : uiTheme.accentWash) : uiTheme.bgElevated,
      shape: RoundedRectangleBorder(
        borderRadius: r,
        side: BorderSide(color: accent ? (color != null ? base.withValues(alpha: 0.6) : uiTheme.accentBorder) : uiTheme.borderSubtle),
      ),
      child: onTap == null
          ? content
          : Semantics(
              button: true,
              selected: selected,
              label: label,
              child: InkWell(
                borderRadius: r,
                splashColor: Colors.transparent,
                highlightColor: uiTheme.touchHighlight,
                hoverColor: uiTheme.hoverOverlay,
                onTap: onTap,
                child: content,
              ),
            ),
    );
  }
}

/// Оцінка в зірочці (плашка поверх постера або в рядку)
class HikkaScoreBadge extends StatelessWidget {
  final double score;
  final double scale;

  const HikkaScoreBadge({super.key, required this.score, required this.scale});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 6 * scale, vertical: 2.5 * scale),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.65), borderRadius: uiTheme.borderRadius(6 * scale)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Symbols.star_rounded, color: const Color(0xFFFFC23D), size: 13 * scale, fill: 1),
          SizedBox(width: 3 * scale),
          Text(
            score.toStringAsFixed(2),
            style: TextStyle(fontFamily: 'Arial', color: Colors.white, fontSize: 11 * scale, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

/// Маленька плашка поверх постера (тип, 18+, номер серії)
class HikkaPill extends StatelessWidget {
  final String text;
  final double scale;
  final Color? background;
  final Color? foreground;
  final FontWeight weight;
  final double size;

  const HikkaPill({super.key, required this.text, required this.scale, this.background, this.foreground, this.weight = FontWeight.bold, this.size = 10.5});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 6 * scale, vertical: 2.5 * scale),
      decoration: BoxDecoration(
        color: background ?? Colors.black.withValues(alpha: 0.65),
        borderRadius: uiTheme.borderRadius(6 * scale),
      ),
      child: Text(
        text,
        maxLines: 1,
        style: TextStyle(fontFamily: 'Arial', color: foreground ?? Colors.white, fontSize: size * scale, fontWeight: weight),
      ),
    );
  }
}

/// Посилання-кнопка «Усі →» біля заголовка секції
class HikkaLinkButton extends StatelessWidget {
  final String label;
  final double scale;
  final VoidCallback onTap;

  /// Значок перед підписом: тоді це «тиха» дія (як «Скинути» в налаштуваннях), без стрілки й акценту
  final IconData? icon;

  const HikkaLinkButton({super.key, required this.label, required this.scale, required this.onTap, this.icon});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: uiTheme.borderRadius(6 * scale),
        splashColor: Colors.transparent,
        highlightColor: uiTheme.touchHighlight,
        hoverColor: uiTheme.hoverOverlay,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: AppPlatform.isMobile ? AppPlatform.touchTarget : 0),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 8 * scale, vertical: 4 * scale),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, color: uiTheme.textMuted, size: 16 * scale),
                  SizedBox(width: 5 * scale),
                ],
                Text(
                  label,
                  style: TextStyle(fontFamily: 'Arial', color: icon != null ? uiTheme.textMuted : uiTheme.accentColor, fontSize: 12 * scale, fontWeight: icon != null ? FontWeight.w500 : FontWeight.w600),
                ),
                if (icon == null) Icon(Symbols.chevron_right_rounded, color: uiTheme.accentColor, size: 16 * scale),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Кругла кнопка-іконка (назад, налаштування) з зоною дотику не менше 48 dp на телефоні
class HikkaIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final double scale;
  final VoidCallback onTap;
  final bool active;

  const HikkaIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.scale,
    required this.onTap,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final double size = AppPlatform.isMobile ? AppPlatform.touchTarget : 38 * scale;
    return Semantics(
      button: true,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: SizedBox(
          width: size,
          height: size,
          child: Material(
            color: active ? uiTheme.accentWash : Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: uiTheme.borderRadius(size / 2)),
            child: InkWell(
              customBorder: RoundedRectangleBorder(borderRadius: uiTheme.borderRadius(size / 2)),
              splashColor: Colors.transparent,
              highlightColor: uiTheme.touchHighlight,
              hoverColor: uiTheme.hoverOverlay,
              onTap: onTap,
              child: Icon(icon, color: active ? uiTheme.accentColor : uiTheme.textPrimary, size: 22 * scale, weight: 300, opticalSize: 24),
            ),
          ),
        ),
      ),
    );
  }
}

/// Рядок заголовка відкритої сторінки: «Назад», назва, дії праворуч
class HikkaBackBar extends StatelessWidget {
  final double scale;
  final String title;
  final String? subtitle;
  final VoidCallback onBack;
  final List<Widget> actions;

  const HikkaBackBar({
    super.key,
    required this.scale,
    required this.title,
    required this.onBack,
    this.subtitle,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final pad = HikkaLayout.sidePad(context, scale);
    return Container(
      height: HikkaLayout.barHeight(scale),
      padding: EdgeInsets.only(left: math.max(pad - 8, 4), right: math.max(pad - 8, 4)),
      child: Row(
        children: [
          HikkaIconButton(icon: Symbols.arrow_back_rounded, tooltip: 'Назад', scale: scale, onTap: onBack),
          SizedBox(width: 6 * scale),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: 'Arial', color: uiTheme.textPrimary, fontSize: 15 * scale, fontWeight: FontWeight.bold),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontFamily: 'Arial', color: uiTheme.textDarkMuted, fontSize: 11.5 * scale),
                  ),
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

// ── Сітка ────────────────────────────────────────────────────────────────────

/// Сітка карток: кількість стовпців підбирається під ширину, висота картки = постер + текст
class HikkaGridDelegate extends SliverGridDelegate {
  final double maxTileWidth;
  final double spacing;

  /// Ширина / висота постера
  final double posterAspect;

  /// Висота текстового блока під постером
  final double textHeight;

  const HikkaGridDelegate({
    required this.maxTileWidth,
    required this.spacing,
    required this.textHeight,
    this.posterAspect = 0.7,
  });

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) {
    final width = constraints.crossAxisExtent;
    final columns = math.max(2, ((width + spacing) / (maxTileWidth + spacing)).ceil());
    final tileWidth = (width - spacing * (columns - 1)) / columns;
    final tileHeight = tileWidth / posterAspect + textHeight;
    return SliverGridRegularTileLayout(
      crossAxisCount: columns,
      mainAxisStride: tileHeight + spacing,
      crossAxisStride: tileWidth + spacing,
      childMainAxisExtent: tileHeight,
      childCrossAxisExtent: tileWidth,
      reverseCrossAxis: false,
    );
  }

  @override
  bool shouldRelayout(HikkaGridDelegate old) =>
      old.maxTileWidth != maxTileWidth ||
      old.spacing != spacing ||
      old.posterAspect != posterAspect ||
      old.textHeight != textHeight;
}

/// Висота двох рядків назви й рядка підпису під постером з урахуванням системного масштабу шрифту
double hikkaCardTextHeight(BuildContext context, double scale, {int titleLines = 2, bool subtitle = true}) {
  final ts = MediaQuery.textScalerOf(context);
  final title = ts.scale(12.5 * scale) * 1.25 * titleLines;
  final sub = subtitle ? ts.scale(11 * scale) * 1.25 + 3 * scale : 0.0;
  return 7 * scale + title + sub + 4 * scale;
}

/// Картка-заглушка в сітці, поки дані вантажаться: постер і рядки тексту під ним
class HikkaCardSkeleton extends StatelessWidget {
  final double scale;
  final int titleLines;

  const HikkaCardSkeleton({super.key, required this.scale, this.titleLines = 2});

  @override
  Widget build(BuildContext context) {
    Widget bar(double factor, double height) => FractionallySizedBox(
          widthFactor: factor,
          child: Container(height: height, decoration: BoxDecoration(color: uiTheme.bgElevated, borderRadius: uiTheme.borderRadius(4))),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(color: uiTheme.bgElevated, borderRadius: uiTheme.borderRadius(10 * scale)),
            child: const SizedBox.expand(),
          ),
        ),
        SizedBox(height: 9 * scale),
        bar(0.85, 9 * scale),
        if (titleLines > 1) ...[SizedBox(height: 6 * scale), bar(0.55, 9 * scale)],
        SizedBox(height: 6 * scale),
        bar(0.4, 8 * scale),
      ],
    );
  }
}

/// Смужка-заглушка (рядок тексту)
Widget hikkaSkeletonBar(double? width, double height, {double? factor}) {
  final box = Container(height: height, width: width, decoration: BoxDecoration(color: uiTheme.bgElevated, borderRadius: uiTheme.borderRadius(4)));
  return factor == null ? box : FractionallySizedBox(widthFactor: factor, alignment: Alignment.centerLeft, child: box);
}

/// Заглушка списку карток-блоків (колекції, статті): стільки стовпців, скільки й у справжньому списку
class HikkaListSkeleton extends StatelessWidget {
  final double scale;
  final double maxCardWidth;
  final double cardHeight;
  final int rows;

  const HikkaListSkeleton({super.key, required this.scale, this.maxCardWidth = 520, this.cardHeight = 200, this.rows = 4});

  @override
  Widget build(BuildContext context) {
    final pad = HikkaLayout.sidePad(context, scale);
    final gap = HikkaLayout.compact(context) ? 12.0 : 14 * scale;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - pad * 2).clamp(0.0, HikkaLayout.maxContentWidth);
        final maxW = maxCardWidth * (AppPlatform.isMobile ? 1.0 : scale);
        final columns = ((width + gap) / (maxW + gap)).floor().clamp(1, 3);
        final side = ((constraints.maxWidth - width) / 2).clamp(pad, double.infinity);
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: side),
          child: Column(
            children: [
              for (int r = 0; r < rows; r++)
                Padding(
                  padding: EdgeInsets.only(bottom: gap),
                  child: Row(
                    children: [
                      for (int c = 0; c < columns; c++) ...[
                        if (c > 0) SizedBox(width: gap),
                        Expanded(
                          child: Container(
                            height: cardHeight * scale,
                            padding: EdgeInsets.all(10 * scale),
                            decoration: BoxDecoration(
                              color: uiTheme.bgElevated.withValues(alpha: 0.5),
                              borderRadius: uiTheme.borderRadius(14 * scale),
                              border: Border.all(color: uiTheme.borderSubtle),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(color: uiTheme.bgElevated, borderRadius: uiTheme.borderRadius(8 * scale)),
                                    child: const SizedBox.expand(),
                                  ),
                                ),
                                SizedBox(height: 10 * scale),
                                hikkaSkeletonBar(null, 11 * scale, factor: 0.8),
                                SizedBox(height: 6 * scale),
                                hikkaSkeletonBar(null, 9 * scale, factor: 0.45),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Прокручувана сітка з підвантаженням: слухає [pager], докантажує сторінки при наближенні до кінця
class HikkaPagedGrid<T> extends StatefulWidget {
  final HikkaPager<T> pager;
  final double scale;
  final Widget Function(BuildContext context, T item) itemBuilder;
  final String emptyText;
  final IconData emptyIcon;
  final ScrollController? controller;

  /// Додатковий відступ знизу (згорнутий плеєр)
  final double bottomInset;
  final double maxTileWidth;
  final double posterAspect;
  final int titleLines;

  /// Блок над сіткою, що прокручується разом з нею
  final Widget? header;

  const HikkaPagedGrid({
    super.key,
    required this.pager,
    required this.scale,
    required this.itemBuilder,
    required this.emptyText,
    this.emptyIcon = Symbols.search_off_rounded,
    this.controller,
    this.bottomInset = 0,
    this.maxTileWidth = 170,
    this.posterAspect = 0.7,
    this.titleLines = 2,
    this.header,
  });

  @override
  State<HikkaPagedGrid<T>> createState() => _HikkaPagedGridState<T>();
}

class _HikkaPagedGridState<T> extends State<HikkaPagedGrid<T>> {
  ScrollController? _own;
  ScrollController get _controller => widget.controller ?? (_own ??= AppSmoothScrollController());

  @override
  void initState() {
    super.initState();
    widget.pager.addListener(_onPager);
    _controller.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(HikkaPagedGrid<T> old) {
    super.didUpdateWidget(old);
    if (old.pager != widget.pager) {
      old.pager.removeListener(_onPager);
      widget.pager.addListener(_onPager);
    }
    if (old.controller != widget.controller) {
      (old.controller ?? _own)?.removeListener(_onScroll);
      _controller.addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    widget.pager.removeListener(_onPager);
    _controller.removeListener(_onScroll);
    _own?.dispose();
    super.dispose();
  }

  void _onPager() {
    if (!mounted) return;
    setState(() {});
    // Список не заповнив екран — докантажуємо ще сторінку
    WidgetsBinding.instance.addPostFrameCallback((_) => _fillViewport());
  }

  void _onScroll() {
    final c = _controller;
    if (c.hasClients && c.position.extentAfter < 900) widget.pager.loadMore();
  }

  void _fillViewport() {
    if (!mounted) return;
    final c = _controller;
    if (c.hasClients && c.position.maxScrollExtent <= 0 && widget.pager.hasMore && !widget.pager.loading && widget.pager.error == null) {
      widget.pager.loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.scale;
    final pager = widget.pager;
    final pad = HikkaLayout.sidePad(context, scale);
    final spacing = (HikkaLayout.compact(context) ? 12.0 : 14 * scale);
    final textHeight = hikkaCardTextHeight(context, scale, titleLines: widget.titleLines);

    final Widget footer;
    if (pager.error != null && pager.items.isNotEmpty) {
      footer = HikkaErrorView(scale: scale, error: pager.error!, onRetry: pager.retry, compact: true);
    } else if (pager.loading && pager.items.isNotEmpty) {
      footer = HikkaLoading(scale: scale, height: 72);
    } else {
      footer = const SizedBox(height: 8);
    }

    // Поки перша сторінка вантажиться, замість кола показуємо сітку-заглушку: вкладка одразу виглядає «як сторінка»
    final skeleton = pager.items.isEmpty && pager.error == null && (pager.isInitialLoading || pager.isFresh);
    Widget body;
    if (pager.error != null && pager.items.isEmpty) {
      body = HikkaErrorView(scale: scale, error: pager.error!, onRetry: pager.retry);
    } else if (skeleton) {
      body = const SizedBox.shrink();
    } else if (pager.isEmpty) {
      body = SizedBox(height: 260, child: AppEmptyState(scale: scale, icon: widget.emptyIcon, text: widget.emptyText));
    } else {
      body = const SizedBox.shrink();
    }

    return AppScrollbar(
      scale: scale,
      controller: _controller,
      child: CustomScrollView(
        controller: _controller,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: SizedBox(height: AppHeaderInset.of(context))), // місце під шапкою-накладкою
          if (widget.header != null) SliverToBoxAdapter(child: widget.header),
          if (skeleton)
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: pad),
              sliver: SliverGrid(
                gridDelegate: HikkaGridDelegate(
                  maxTileWidth: widget.maxTileWidth * (AppPlatform.isMobile ? 1.0 : scale),
                  spacing: spacing,
                  posterAspect: widget.posterAspect,
                  textHeight: textHeight,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, i) => HikkaCardSkeleton(scale: scale, titleLines: widget.titleLines),
                  childCount: 12,
                ),
              ),
            )
          else if (pager.items.isEmpty)
            SliverToBoxAdapter(child: body)
          else
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: pad),
              sliver: SliverGrid(
                gridDelegate: HikkaGridDelegate(
                  maxTileWidth: widget.maxTileWidth * (AppPlatform.isMobile ? 1.0 : scale),
                  spacing: spacing,
                  posterAspect: widget.posterAspect,
                  textHeight: textHeight,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, i) => widget.itemBuilder(context, pager.items[i]),
                  childCount: pager.items.length,
                ),
              ),
            ),
          SliverToBoxAdapter(child: footer),
          SliverToBoxAdapter(child: SizedBox(height: 24 * scale + widget.bottomInset)),
        ],
      ),
    );
  }
}

/// Рядок налаштування з перемикачем (вигляд як у налаштуваннях застосунку)
class HikkaToggleRow extends StatelessWidget {
  final double scale;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const HikkaToggleRow({
    super.key,
    required this.scale,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final accent = uiTheme.accentColor;
    final row = Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(fontFamily: 'Arial', color: uiTheme.textPrimary, fontSize: 13.5 * scale, fontWeight: FontWeight.w600)),
              SizedBox(height: 2 * scale),
              Text(subtitle, style: TextStyle(fontFamily: 'Arial', color: uiTheme.textDarkMuted, fontSize: 11.5 * scale, height: 1.35)),
            ],
          ),
        ),
        SizedBox(width: 16 * scale),
        AppAnimatedContainer(
          duration: AppAnim.fast,
          curve: AppAnim.easeOut,
          width: 44 * scale,
          height: 24 * scale,
          padding: EdgeInsets.all(2.5 * scale),
          decoration: BoxDecoration(
            color: value ? accent : (uiTheme.isLight ? const Color(0xFFD4D4DE) : const Color(0xFF28282C)),
            borderRadius: uiTheme.borderRadius(12 * scale),
            border: Border.all(
              color: value ? accent : (uiTheme.isLight ? const Color(0xFFC0C0CC) : const Color(0xFF38383E)),
            ),
          ),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(width: 17 * scale, height: 17 * scale, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
        ),
      ],
    );
    return Semantics(
      toggled: value,
      label: title,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(!value),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: AppPlatform.isMobile ? AppPlatform.touchTarget : 0),
          child: Align(alignment: Alignment.center, child: row),
        ),
      ),
    );
  }
}

/// Таблиця «назва — значення» (інформація про аніме). У вузькій колонці (альбомний телефон) значення
/// не лишається в обрубку праворуч від назви, а йде під нею: слова не рвуться посеред.
class HikkaInfoTable extends StatelessWidget {
  final double scale;
  final List<(String label, String value)> rows;

  const HikkaInfoTable({super.key, required this.scale, required this.rows});

  @override
  Widget build(BuildContext context) {
    final visible = [for (final r in rows) if (r.$2.trim().isNotEmpty) r];
    if (visible.isEmpty) return const SizedBox.shrink();
    final labelStyle = TextStyle(fontFamily: 'Arial', color: uiTheme.textDarkMuted, fontSize: 12 * scale, height: 1.35);
    final valueStyle = TextStyle(fontFamily: 'Arial', color: uiTheme.textPrimary, fontSize: 12.5 * scale, height: 1.35);
    return LayoutBuilder(
      builder: (context, box) {
        final stacked = box.maxWidth < 236 * scale;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final r in visible)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 5 * scale),
                child: stacked
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(r.$1, style: labelStyle),
                          SizedBox(height: 1 * scale),
                          Text(r.$2, style: valueStyle),
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(width: 108 * scale, child: Text(r.$1, style: labelStyle)),
                          Expanded(child: Text(r.$2, style: valueStyle)),
                        ],
                      ),
              ),
          ],
        );
      },
    );
  }
}

/// Рядок пошуку з кнопкою праворуч (фільтри); на телефоні поле не нижче 48 dp
class HikkaSearchBar extends StatelessWidget {
  final double scale;
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final Widget? trailing;
  final FocusNode? focusNode;

  const HikkaSearchBar({
    super.key,
    required this.scale,
    required this.controller,
    required this.hint,
    required this.onChanged,
    this.trailing,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    final pad = HikkaLayout.sidePad(context, scale);
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 4 * scale, pad, 8 * scale),
      child: Row(
        children: [
          Expanded(
            child: AppSearchField(
              scale: AppPlatform.isMobile ? scale * 1.12 : scale,
              controller: controller,
              focusNode: focusNode,
              hint: hint,
              onChanged: onChanged,
            ),
          ),
          if (trailing != null) ...[SizedBox(width: 8 * scale), trailing!],
        ],
      ),
    );
  }
}
