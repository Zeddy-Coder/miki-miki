import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../models/hikka_models.dart';
import '../../services/hikka_images.dart';
import '../../services/hikka_nav.dart';
import '../../services/ui_theme_service.dart';
import '../app_animation_kit.dart';
import '../app_ui_kit.dart';
import 'hikka_markdown_view.dart' show HikkaSpoilerBox;

/// Текст статті Hikka (документ редактора Slate): абзаци, заголовки, списки, цитати, спойлери, картинки,
/// групи картинок, відео та посилання (на аніме, персонажів, колекції й статті — усередині застосунку).
class HikkaSlateView extends StatefulWidget {
  final List<SlateNode> nodes;
  final double scale;
  final double fontSize;

  /// Куди вести посилання; за замовчуванням — навігація застосунку
  final void Function(String url)? onLink;

  const HikkaSlateView({super.key, required this.nodes, required this.scale, this.fontSize = 14.5, this.onLink});

  @override
  State<HikkaSlateView> createState() => _HikkaSlateViewState();
}

class _HikkaSlateViewState extends State<HikkaSlateView> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    _disposeAll(_recognizers);
    _recognizers.clear();
    super.dispose();
  }

  static void _disposeAll(List<TapGestureRecognizer> list) {
    for (final r in list) {
      r.dispose();
    }
  }

  double get _scale => widget.scale;

  void _open(String url) {
    final handler = widget.onLink;
    if (handler != null) {
      handler(url);
    } else {
      HikkaNav.instance.openLink(url);
    }
  }

  TextStyle get _base => TextStyle(
        fontFamily: 'Arial',
        color: uiTheme.textPrimary.withValues(alpha: 0.92),
        fontSize: widget.fontSize * _scale,
        height: 1.55,
      );

  static bool _isInline(SlateNode n) => n.isText || n.type == 'a';

  // ── Рядки ──────────────────────────────────────────────────────────────────

  List<InlineSpan> _inline(List<SlateNode> kids, {String? link}) {
    final out = <InlineSpan>[];
    for (final n in kids) {
      if (n.isText) {
        if (n.text.isEmpty) continue;
        out.add(_leaf(n, link: link));
      } else if (n.type == 'a' && n.url != null) {
        // Розпізнавач натискання діє лише на власний текст проміжку, тож його дістає кожен листок усередині посилання
        out.addAll(_inline(n.children, link: n.url));
      } else {
        out.addAll(_inline(n.children, link: link));
      }
    }
    return out;
  }

  TextSpan _leaf(SlateNode n, {String? link}) {
    final decorations = <TextDecoration>[
      if (n.underline) TextDecoration.underline,
      if (n.strike) TextDecoration.lineThrough,
      if (link != null) TextDecoration.underline,
    ];
    TapGestureRecognizer? recognizer;
    if (link != null) {
      recognizer = TapGestureRecognizer()..onTap = () => _open(link);
      _recognizers.add(recognizer);
    }
    return TextSpan(
      text: n.text,
      recognizer: recognizer,
      mouseCursor: link != null ? SystemMouseCursors.click : null,
      semanticsLabel: link != null ? n.text : null,
      style: TextStyle(
        fontWeight: n.bold ? FontWeight.bold : null,
        fontStyle: n.italic ? FontStyle.italic : null,
        decoration: decorations.isEmpty ? null : TextDecoration.combine(decorations),
        decorationColor: link != null ? uiTheme.accentColor.withValues(alpha: 0.45) : null,
        color: link != null ? uiTheme.accentColor : null,
        fontFamily: n.code ? 'monospace' : null,
        backgroundColor: n.code ? uiTheme.bgElevated : null,
      ),
    );
  }

  Widget _text(List<SlateNode> inline, {TextStyle? style}) {
    final spans = _inline(inline);
    if (spans.isEmpty) return const SizedBox.shrink();
    return Text.rich(TextSpan(style: style, children: spans));
  }

  // ── Блоки ──────────────────────────────────────────────────────────────────

  /// Діти вузла: підряд інлайнові листки йдуть одним абзацом, блоки — кожен сам
  List<Widget> _children(List<SlateNode> kids, {int depth = 0}) {
    final out = <Widget>[];
    var run = <SlateNode>[];
    void flush() {
      if (run.isEmpty) return;
      final w = _text(run);
      if (w is! SizedBox) out.add(Padding(padding: EdgeInsets.only(bottom: 10 * _scale), child: w));
      run = <SlateNode>[];
    }

    for (final k in kids) {
      if (_isInline(k)) {
        run.add(k);
      } else {
        flush();
        out.add(_block(k, depth: depth));
      }
    }
    flush();
    return out;
  }

  static double _headingFactor(String type) => switch (type) {
        'h1' => 1.5,
        'h2' => 1.35,
        'h3' => 1.22,
        'h4' => 1.12,
        _ => 1.04,
      };

  Widget _block(SlateNode n, {int depth = 0}) {
    final scale = _scale;
    switch (n.type) {
      case 'p':
        final inline = n.children.where(_isInline).toList();
        final hasBlocks = inline.length != n.children.length;
        if (hasBlocks) {
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: _children(n.children, depth: depth));
        }
        final w = _text(inline);
        // Порожній абзац — відступ між блоками, як у редакторі
        return Padding(padding: EdgeInsets.only(bottom: 10 * scale), child: w is SizedBox ? SizedBox(height: 6 * scale) : w);
      case 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
        final w = _text(
          n.children,
          style: TextStyle(fontWeight: FontWeight.bold, color: uiTheme.textPrimary, fontSize: _base.fontSize! * _headingFactor(n.type), height: 1.3),
        );
        if (w is SizedBox) return const SizedBox.shrink();
        return Padding(padding: EdgeInsets.only(top: 8 * scale, bottom: 8 * scale), child: w);
      case 'ul' || 'ol':
        return Padding(
          padding: EdgeInsets.only(bottom: 8 * scale),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (int i = 0; i < n.children.length; i++) _listItem(n.children[i], n.type == 'ol' ? '${i + 1}.' : (depth.isEven ? '•' : '–'), depth),
            ],
          ),
        );
      case 'li':
        return _listItem(n, '•', depth);
      case 'blockquote':
        return Padding(
          padding: EdgeInsets.only(bottom: 10 * scale),
          child: Container(
            padding: EdgeInsets.only(left: 12 * scale),
            decoration: BoxDecoration(border: Border(left: BorderSide(color: uiTheme.accentBorder, width: 3))),
            child: DefaultTextStyle.merge(
              style: TextStyle(fontStyle: FontStyle.italic, color: uiTheme.textMuted),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: _children(n.children, depth: depth)),
            ),
          ),
        );
      case 'spoiler':
        return Padding(
          padding: EdgeInsets.only(bottom: 10 * scale),
          child: HikkaSpoilerBox(
            scale: scale,
            title: null,
            childBuilder: () => Column(crossAxisAlignment: CrossAxisAlignment.start, children: _children(n.children, depth: depth)),
          ),
        );
      case 'image':
        final url = n.url;
        if (url == null) return const SizedBox.shrink();
        return Padding(padding: EdgeInsets.only(bottom: 12 * scale), child: HikkaSlateImage(url: url, scale: scale));
      case 'image_group':
        return Padding(padding: EdgeInsets.only(bottom: 12 * scale), child: _imageGroup(n));
      case 'video':
        final url = n.url;
        if (url == null) return const SizedBox.shrink();
        return Padding(padding: EdgeInsets.only(bottom: 12 * scale), child: _videoLink(url));
      default:
        // Невідомий блок: показуємо його вміст, а не губимо текст
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: _children(n.children, depth: depth));
    }
  }

  Widget _listItem(SlateNode li, String marker, int depth) {
    final scale = _scale;
    // Вміст пункту: `lic` (текст) і вкладені списки
    final content = li.type == 'li' ? li.children : [li];
    return Padding(
      padding: EdgeInsets.only(left: (4 + depth * 14) * scale, bottom: 5 * scale),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 22 * scale, child: Text(marker, style: _base.copyWith(color: uiTheme.textMuted))),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final c in content)
                  if (c.type == 'lic')
                    _text(c.children) is SizedBox ? const SizedBox.shrink() : _text(c.children)
                  else if (c.type == 'ul' || c.type == 'ol')
                    _block(c, depth: depth + 1)
                  else if (_isInline(c))
                    _text([c])
                  else
                    _block(c, depth: depth + 1),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _imageGroup(SlateNode group) {
    final scale = _scale;
    final images = [for (final c in group.children) if (c.type == 'image' && c.url != null) c.url!];
    if (images.isEmpty) return const SizedBox.shrink();
    if (images.length == 1) return HikkaSlateImage(url: images.first, scale: scale);
    final gap = 6 * scale;
    return LayoutBuilder(
      builder: (context, c) {
        final columns = images.length == 2 || images.length == 4 ? 2 : (c.maxWidth < 420 ? 2 : 3);
        final width = (c.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final url in images) SizedBox(width: width, child: HikkaSlateImage(url: url, scale: scale, aspect: 4 / 3, gallery: images)),
          ],
        );
      },
    );
  }

  Widget _videoLink(String url) {
    final scale = _scale;
    final host = Uri.tryParse(url)?.host.replaceFirst('www.', '') ?? '';
    return AppCard(
      scale: scale,
      radius: 12,
      onTap: () => _open(url),
      padding: EdgeInsets.symmetric(horizontal: 14 * scale, vertical: 12 * scale),
      child: Row(
        children: [
          Icon(Symbols.play_circle_rounded, color: uiTheme.accentColor, size: 28 * scale, fill: 1),
          SizedBox(width: 12 * scale),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Відео', style: TextStyle(fontFamily: 'Arial', color: uiTheme.textPrimary, fontSize: 13.5 * scale, fontWeight: FontWeight.w600)),
                if (host.isNotEmpty)
                  Text(host, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: 'Arial', color: uiTheme.textMuted, fontSize: 11.5 * scale)),
              ],
            ),
          ),
          Icon(Symbols.open_in_new_rounded, color: uiTheme.textDarkMuted, size: 18 * scale),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Розпізнавачі попереднього кадру знищуємо після побудови нового
    final old = List<TapGestureRecognizer>.of(_recognizers);
    _recognizers.clear();
    if (old.isNotEmpty) {
      SchedulerBinding.instance.addPostFrameCallback((_) => _disposeAll(old));
    }
    final children = _children(widget.nodes);
    if (children.isEmpty) return const SizedBox.shrink();
    return DefaultTextStyle(
      style: _base,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

/// Картинка зі статті: плавно проявляється, під час завантаження — заглушка; натискання відкриває перегляд
/// з масштабуванням. [aspect] — фіксоване співвідношення сторін (плитки груп), інакше висота за картинкою.
class HikkaSlateImage extends StatelessWidget {
  final String url;
  final double scale;
  final double? aspect;

  /// Усі картинки групи: у перегляді їх можна гортати
  final List<String>? gallery;

  const HikkaSlateImage({super.key, required this.url, required this.scale, this.aspect, this.gallery});

  @override
  Widget build(BuildContext context) {
    final r = uiTheme.borderRadius(10 * scale);
    final placeholder = ColoredBox(
      color: uiTheme.bgElevated,
      child: Center(child: Icon(Symbols.image_rounded, color: uiTheme.textDarkMuted.withValues(alpha: 0.6), size: 28 * scale, weight: 300)),
    );
    return Semantics(
      button: true,
      label: 'Картинка зі статті. Відкрити',
      child: InkWell(
        borderRadius: r,
        splashColor: Colors.transparent,
        highlightColor: uiTheme.touchHighlight,
        hoverColor: uiTheme.hoverOverlay,
        onTap: () => HikkaImageViewer.show(context, gallery ?? [url], initial: gallery == null ? 0 : gallery!.indexOf(url)),
        child: ClipRRect(
          borderRadius: r,
          child: LayoutBuilder(
            builder: (context, c) {
              final w = c.maxWidth.isFinite ? c.maxWidth : 480.0;
              final px = HikkaImages.bucket(w, MediaQuery.devicePixelRatioOf(context));
              final resized = HikkaImages.resized(url, width: px);
              final provider = ResizeImage.resizeIfNeeded(px, null, HikkaImage(resized, fallback: resized == url ? null : url));
              final image = Image(
                image: provider,
                width: double.infinity,
                height: aspect == null ? null : w / aspect!,
                fit: aspect == null ? BoxFit.fitWidth : BoxFit.cover,
                filterQuality: FilterQuality.medium,
                gaplessPlayback: true,
                frameBuilder: (context, child, frame, sync) => sync || frame != null ? child : SizedBox(height: aspect == null ? 180 * scale : w / aspect!, child: placeholder),
                errorBuilder: (context, error, stack) => SizedBox(
                  height: aspect == null ? 120 * scale : w / aspect!,
                  child: ColoredBox(
                    color: uiTheme.bgElevated,
                    child: Center(child: Icon(Symbols.broken_image_rounded, color: uiTheme.textDarkMuted, size: 28 * scale, weight: 300)),
                  ),
                ),
              );
              return AppAnimatedSize(alignment: Alignment.topCenter, child: image);
            },
          ),
        ),
      ),
    );
  }
}

/// Перегляд картинок на весь екран: масштабування щипком чи колесом, гортання між картинками групи
class HikkaImageViewer extends StatefulWidget {
  final List<String> urls;
  final int initial;

  const HikkaImageViewer({super.key, required this.urls, this.initial = 0});

  static Future<void> show(BuildContext context, List<String> urls, {int initial = 0}) {
    if (urls.isEmpty) return Future.value();
    return AppDialogs.show<void>(
      context,
      barrierColor: Colors.black.withValues(alpha: 0.92),
      builder: (_) => HikkaImageViewer(urls: urls, initial: initial.clamp(0, urls.length - 1)),
    );
  }

  @override
  State<HikkaImageViewer> createState() => _HikkaImageViewerState();
}

class _HikkaImageViewerState extends State<HikkaImageViewer> {
  late final PageController _pages = PageController(initialPage: widget.initial);
  late int _index = widget.initial;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final many = widget.urls.length > 1;
    return Material(
      color: Colors.transparent,
      child: Stack(
        fit: StackFit.expand,
        children: [
          PageView.builder(
            controller: _pages,
            itemCount: widget.urls.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, i) {
              final url = widget.urls[i];
              final px = HikkaImages.bucket(MediaQuery.sizeOf(context).width, MediaQuery.devicePixelRatioOf(context)).clamp(480, 1600);
              final resized = HikkaImages.resized(url, width: px);
              return InteractiveViewer(
                minScale: 1,
                maxScale: 5,
                child: Center(
                  child: Image(
                    image: HikkaImage(resized, fallback: resized == url ? null : url),
                    fit: BoxFit.contain,
                    errorBuilder: (context, e, s) => Icon(Symbols.broken_image_rounded, color: Colors.white54, size: 48),
                    loadingBuilder: (context, child, progress) => child,
                    frameBuilder: (context, child, frame, sync) => frame == null && !sync
                        ? const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white70))
                        : child,
                  ),
                ),
              );
            },
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (many)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Text('${_index + 1} / ${widget.urls.length}', style: const TextStyle(fontFamily: 'Arial', color: Colors.white70, fontSize: 13)),
                      ),
                    Semantics(
                      button: true,
                      label: 'Закрити',
                      child: IconButton(
                        tooltip: 'Закрити',
                        iconSize: 26,
                        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                        color: Colors.white,
                        icon: const Icon(Symbols.close_rounded, weight: 300),
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
