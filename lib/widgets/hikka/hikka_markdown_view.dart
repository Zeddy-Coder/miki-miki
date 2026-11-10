import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../services/hikka_markdown.dart';
import '../../services/hikka_nav.dart';
import '../../services/ui_theme_service.dart';
import '../app_animation_kit.dart';

/// Опис у Markdown: абзаци, посилання (на аніме й персонажів — усередині застосунку, решта — у браузері),
/// жирний і курсив, цитати та приховані спойлери.
class HikkaMarkdownView extends StatefulWidget {
  final String? source;
  final double scale;
  final double fontSize;
  final Color? color;

  /// Куди вести посилання; за замовчуванням — навігація каталогу
  final void Function(String url)? onLink;

  const HikkaMarkdownView({
    super.key,
    required this.source,
    required this.scale,
    this.fontSize = 13.5,
    this.color,
    this.onLink,
  });

  @override
  State<HikkaMarkdownView> createState() => _HikkaMarkdownViewState();
}

class _HikkaMarkdownViewState extends State<HikkaMarkdownView> {
  late List<MdBlock> _blocks;
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void initState() {
    super.initState();
    _blocks = HikkaMarkdown.parse(widget.source);
  }

  @override
  void didUpdateWidget(HikkaMarkdownView old) {
    super.didUpdateWidget(old);
    if (old.source != widget.source) _blocks = HikkaMarkdown.parse(widget.source);
  }

  @override
  void dispose() {
    _disposeRecognizers(_recognizers);
    _recognizers.clear();
    super.dispose();
  }

  static void _disposeRecognizers(List<TapGestureRecognizer> list) {
    for (final r in list) {
      r.dispose();
    }
  }

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
        color: widget.color ?? uiTheme.textPrimary.withValues(alpha: 0.92),
        fontSize: widget.fontSize * widget.scale,
        height: 1.5,
      );

  /// Фрагменти рядка → `TextSpan` (посилання отримують розпізнавач натискання)
  List<InlineSpan> _spans(List<MdSpan> spans, List<TapGestureRecognizer> sink) {
    return [
      for (final s in spans)
        if (s.isBreak)
          const TextSpan(text: '\n')
        else if (s.isLink)
          () {
            final recognizer = TapGestureRecognizer()..onTap = () => _open(s.url!);
            sink.add(recognizer);
            return TextSpan(
              text: s.text,
              recognizer: recognizer,
              mouseCursor: SystemMouseCursors.click,
              semanticsLabel: s.text,
              style: TextStyle(
                color: uiTheme.accentColor,
                fontWeight: s.bold ? FontWeight.bold : null,
                fontStyle: s.italic ? FontStyle.italic : null,
                decoration: TextDecoration.underline,
                decorationColor: uiTheme.accentColor.withValues(alpha: 0.45),
              ),
            );
          }()
        else
          TextSpan(
            text: s.text,
            style: TextStyle(
              fontWeight: s.bold ? FontWeight.bold : null,
              fontStyle: s.italic ? FontStyle.italic : null,
            ),
          ),
    ];
  }

  Widget _block(MdBlock b, List<TapGestureRecognizer> sink) {
    final scale = widget.scale;
    switch (b) {
      case MdParagraph():
        final size = switch (b.heading) {
          0 => 1.0,
          1 || 2 => 1.25,
          _ => 1.1,
        };
        return Padding(
          padding: EdgeInsets.only(bottom: 10 * scale),
          child: Text.rich(
            TextSpan(
              style: b.heading > 0 ? _base.copyWith(fontSize: _base.fontSize! * size, fontWeight: FontWeight.bold, color: uiTheme.textPrimary) : null,
              children: _spans(b.spans, sink),
            ),
          ),
        );
      case MdListItem():
        return Padding(
          padding: EdgeInsets.only(bottom: 6 * scale, left: 4 * scale),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 22 * scale, child: Text(b.marker, style: _base.copyWith(color: uiTheme.textMuted))),
              Expanded(child: Text.rich(TextSpan(children: _spans(b.spans, sink)))),
            ],
          ),
        );
      case MdQuote():
        return Padding(
          padding: EdgeInsets.only(bottom: 10 * scale),
          child: Container(
            padding: EdgeInsets.only(left: 12 * scale),
            decoration: BoxDecoration(border: Border(left: BorderSide(color: uiTheme.accentBorder, width: 3))),
            child: DefaultTextStyle.merge(
              style: TextStyle(fontStyle: FontStyle.italic, color: uiTheme.textMuted),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [for (final c in b.blocks) _block(c, sink)]),
            ),
          ),
        );
      case MdSpoiler():
        return Padding(
          padding: EdgeInsets.only(bottom: 10 * scale),
          child: HikkaSpoilerBox(
            scale: scale,
            title: b.title,
            // Внутрішні розпізнавачі живуть стільки ж, скільки решта: вони потрапляють у той самий список
            childBuilder: () => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [for (final c in b.blocks) _block(c, sink)]),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_blocks.isEmpty) return const SizedBox.shrink();
    // Розпізнавачі попереднього кадру знищуємо після побудови нового
    final old = List<TapGestureRecognizer>.of(_recognizers);
    _recognizers.clear();
    if (old.isNotEmpty) {
      SchedulerBinding.instance.addPostFrameCallback((_) => _disposeRecognizers(old));
    }
    final children = [for (final b in _blocks) _block(b, _recognizers)];
    return DefaultTextStyle(
      style: _base,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

/// Прихований блок: рядок «Спойлер» розкривається натисканням (в описах і в статтях)
class HikkaSpoilerBox extends StatefulWidget {
  final double scale;
  final String? title;
  final Widget Function() childBuilder;

  const HikkaSpoilerBox({super.key, required this.scale, required this.title, required this.childBuilder});

  @override
  State<HikkaSpoilerBox> createState() => _HikkaSpoilerBoxState();
}

class _HikkaSpoilerBoxState extends State<HikkaSpoilerBox> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final scale = widget.scale;
    final r = uiTheme.borderRadius(10 * scale);
    final label = widget.title ?? 'Спойлер';
    return Material(
      color: uiTheme.bgElevated,
      shape: RoundedRectangleBorder(borderRadius: r, side: BorderSide(color: uiTheme.borderSubtle)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: _open,
            label: _open ? 'Сховати: $label' : 'Показати: $label',
            child: InkWell(
              borderRadius: r,
              splashColor: Colors.transparent,
              highlightColor: uiTheme.touchHighlight,
              hoverColor: uiTheme.hoverOverlay,
              onTap: () => setState(() => _open = !_open),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 8 * scale),
                  child: Row(
                    children: [
                      Icon(_open ? Symbols.visibility_off_rounded : Symbols.visibility_rounded, color: uiTheme.accentColor, size: 18 * scale, weight: 300),
                      SizedBox(width: 8 * scale),
                      Expanded(
                        child: Text(
                          _open ? '$label · сховати' : '$label · натисніть, щоб показати',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontFamily: 'Arial', color: uiTheme.textMuted, fontSize: 12.5 * scale, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          AppAnimatedSize(
            child: _open
                ? Padding(
                    padding: EdgeInsets.fromLTRB(12 * scale, 2 * scale, 12 * scale, 4 * scale),
                    child: widget.childBuilder(),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

/// Згортає довгий вміст до [collapsedHeight] з плавним затемненням і кнопкою «Показати більше»
class HikkaCollapsible extends StatefulWidget {
  final Widget child;
  final double collapsedHeight;
  final double scale;

  /// Колір фону під вмістом (для затемнення краю)
  final Color? fadeColor;

  const HikkaCollapsible({
    super.key,
    required this.child,
    required this.collapsedHeight,
    required this.scale,
    this.fadeColor,
  });

  @override
  State<HikkaCollapsible> createState() => _HikkaCollapsibleState();
}

class _HikkaCollapsibleState extends State<HikkaCollapsible> {
  bool _expanded = false;
  double _fullHeight = 0;

  bool get _needsToggle => _fullHeight > widget.collapsedHeight + 24 * widget.scale;

  @override
  Widget build(BuildContext context) {
    final scale = widget.scale;
    final fade = widget.fadeColor ?? uiTheme.bgPrimary;
    final measured = _SizeReporter(
      onSize: (s) {
        if (!mounted || (s.height - _fullHeight).abs() < 1) return;
        setState(() => _fullHeight = s.height);
      },
      child: widget.child,
    );
    final collapsed = _needsToggle && !_expanded;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppAnimatedSize(
          alignment: Alignment.topCenter,
          child: collapsed
              ? SizedBox(
                  height: widget.collapsedHeight,
                  width: double.infinity,
                  child: ClipRect(
                    child: Stack(
                      children: [
                        OverflowBox(alignment: Alignment.topLeft, minHeight: 0, maxHeight: double.infinity, child: measured),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          height: 48 * scale,
                          child: IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [fade.withValues(alpha: 0), fade],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : measured,
        ),
        if (_needsToggle)
          Semantics(
            button: true,
            label: _expanded ? 'Згорнути' : 'Показати більше',
            child: InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              borderRadius: uiTheme.borderRadius(6 * scale),
              splashColor: Colors.transparent,
              highlightColor: uiTheme.touchHighlight,
              hoverColor: uiTheme.hoverOverlay,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8 * scale, vertical: 6 * scale),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _expanded ? 'Згорнути' : 'Показати більше',
                        style: TextStyle(fontFamily: 'Arial', color: uiTheme.accentColor, fontSize: 12.5 * scale, fontWeight: FontWeight.w600),
                      ),
                      AppRotate(
                        turns: _expanded ? 0.5 : 0,
                        child: Icon(Symbols.expand_more_rounded, color: uiTheme.accentColor, size: 18 * scale),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Повідомляє про розмір дочірнього віджета після розкладки
class _SizeReporter extends SingleChildRenderObjectWidget {
  final ValueChanged<Size> onSize;

  const _SizeReporter({required this.onSize, required Widget super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderSizeReporter(onSize);

  @override
  void updateRenderObject(BuildContext context, _RenderSizeReporter renderObject) => renderObject.onSize = onSize;
}

class _RenderSizeReporter extends RenderProxyBox {
  ValueChanged<Size> onSize;
  Size? _last;

  _RenderSizeReporter(this.onSize);

  @override
  void performLayout() {
    super.performLayout();
    if (size != _last) {
      _last = size;
      final s = size;
      SchedulerBinding.instance.addPostFrameCallback((_) => onSize(s));
    }
  }
}
