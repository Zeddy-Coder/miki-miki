import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../services/hikka_markdown.dart';
import '../../services/hikka_nav.dart';
import '../../services/ui_theme_service.dart';
import '../app_animation_kit.dart';
import '../app_tones.dart';
import '../line_icons.dart';

/// A Markdown description: paragraphs, links (to anime and characters inside the app, the rest in a browser),
/// bold and italic, quotes and hidden spoilers.
class HikkaMarkdownView extends StatefulWidget {
  final String? source;
  final double scale;
  final double fontSize;
  final Color? color;

  /// Link color; by default the accent
  final Color? linkColor;

  /// Collapsed view: the text of paragraphs and list items run together and cut to so many lines with "…"
  /// (quotes and spoilers are left for the full view)
  final int? maxLines;

  /// Where to send a link; by default the catalog navigation
  final void Function(String url)? onLink;

  /// Opacity of the link underline; by default 0.45 for accent links and 0.25 for a given [linkColor]
  final double? linkUnderline;

  const HikkaMarkdownView({
    super.key,
    required this.source,
    required this.scale,
    this.fontSize = 13.5,
    this.color,
    this.linkColor,
    this.maxLines,
    this.onLink,
    this.linkUnderline,
  });

  /// The text face of descriptions. The full view replaces the inherited text style, so the fallback is given here:
  /// otherwise a phone without Arial draws the opened text in a narrower font and it jumps
  static TextStyle baseStyle({required double fontSize, required double scale, Color? color}) => TextStyle(
        fontFamily: 'Arial',
        fontFamilyFallback: const ['MikiSans'],
        color: color ?? uiTheme.textPrimary.withValues(alpha: 0.92),
        fontSize: fontSize * scale,
        height: 1.5,
      );

  /// The collapsed text: paragraphs and list items run together into one span; links read as plain text and do
  /// nothing (a tap on a collapsed text opens it); quotes and spoilers are left for the full view
  static TextSpan collapsedSpan(List<MdBlock> blocks, TextStyle base) {
    final spans = <InlineSpan>[];
    for (final b in blocks) {
      final List<MdSpan>? run = switch (b) {
        MdParagraph() => b.spans,
        MdListItem() => b.spans,
        _ => null,
      };
      if (run == null || run.isEmpty) continue;
      if (spans.isNotEmpty) spans.add(const TextSpan(text: ' '));
      for (final s in run) {
        spans.add(TextSpan(
          text: s.isBreak ? ' ' : s.text,
          style: s.bold || s.italic ? TextStyle(fontWeight: s.bold ? FontWeight.bold : null, fontStyle: s.italic ? FontStyle.italic : null) : null,
        ));
      }
    }
    return TextSpan(style: base, children: spans);
  }

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

  /// The same face in both views
  TextStyle get _base => HikkaMarkdownView.baseStyle(fontSize: widget.fontSize, scale: widget.scale, color: widget.color);

  /// Line fragments → `TextSpan` (links get a tap recognizer)
  List<InlineSpan> _spans(List<MdSpan> spans, List<TapGestureRecognizer> sink) {
    return [
      for (final s in spans)
        if (s.isBreak)
          const TextSpan(text: '\n')
        else if (s.isLink)
          () {
            final recognizer = TapGestureRecognizer()..onTap = () => _open(s.url!);
            sink.add(recognizer);
            final link = widget.linkColor ?? uiTheme.accentColor;
            return TextSpan(
              text: s.text,
              recognizer: recognizer,
              mouseCursor: SystemMouseCursors.click,
              semanticsLabel: s.text,
              style: TextStyle(
                color: link,
                fontWeight: s.bold ? FontWeight.bold : null,
                fontStyle: s.italic ? FontStyle.italic : null,
                decoration: TextDecoration.underline,
                decorationColor: link.withValues(alpha: widget.linkUnderline ?? (widget.linkColor == null ? 0.45 : 0.25)),
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
            // Internal recognizers live as long as the rest: they go into the same list
            childBuilder: () => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [for (final c in b.blocks) _block(c, sink)]),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_blocks.isEmpty) return const SizedBox.shrink();
    // Recognizers of the previous frame are destroyed after the new one is built
    final old = List<TapGestureRecognizer>.of(_recognizers);
    _recognizers.clear();
    if (old.isNotEmpty) {
      SchedulerBinding.instance.addPostFrameCallback((_) => _disposeRecognizers(old));
    }
    final lines = widget.maxLines;
    if (lines != null) {
      return Text.rich(HikkaMarkdownView.collapsedSpan(_blocks, _base), maxLines: lines, overflow: TextOverflow.ellipsis);
    }
    final children = [for (final b in _blocks) _block(b, _recognizers)];
    return DefaultTextStyle(
      style: _base,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

/// A description that opens in place: [lines] lines whose last one fades into the page, then a light "Читати далі ⌄";
/// a tap anywhere on the text opens it. Opened, it shows the whole text with working links (light, thinly underlined)
/// and a grey "Згорнути ⌃". While the text is closed its links do nothing, so a tap never lands on one by accident.
/// Both views use one face and the height changes smoothly, so the lines stay where they were. A text that fits into
/// [lines] is shown whole at once, without the toggle.
class HikkaSynopsis extends StatefulWidget {
  final String source;
  final double scale;
  final double fontSize;
  final int lines;

  /// Text color; by default the muted one
  final Color? color;

  /// Opened at the start (a page keeps it in its route memo to come back to the same view)
  final bool open;
  final ValueChanged<bool>? onOpen;
  final void Function(String url)? onLink;

  const HikkaSynopsis({
    super.key,
    required this.source,
    required this.scale,
    this.fontSize = 13,
    this.lines = 4,
    this.color,
    this.open = false,
    this.onOpen,
    this.onLink,
  });

  @override
  State<HikkaSynopsis> createState() => _HikkaSynopsisState();
}

class _HikkaSynopsisState extends State<HikkaSynopsis> {
  late bool _open = widget.open;
  late List<MdBlock> _blocks = HikkaMarkdown.parse(widget.source);

  @override
  void didUpdateWidget(HikkaSynopsis old) {
    super.didUpdateWidget(old);
    if (old.source != widget.source) _blocks = HikkaMarkdown.parse(widget.source);
    if (old.open != widget.open) _open = widget.open;
  }

  void _set(bool open) {
    setState(() => _open = open);
    widget.onOpen?.call(open);
  }

  Widget _toggle(String label, LineIcon icon, Color color, {bool bold = false}) {
    final scale = widget.scale;
    return SizedBox(
      height: 34 * scale,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(fontFamily: 'Arial', fontFamilyFallback: const ['MikiSans'], color: color, fontSize: 13 * scale, fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
          SizedBox(width: 4 * scale),
          LineIconView(icon, size: 15 * scale, color: color, stroke: 1.8),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.scale;
    final color = widget.color ?? uiTheme.textMuted;
    final full = HikkaMarkdownView(
      source: widget.source,
      scale: scale,
      fontSize: widget.fontSize,
      color: color,
      linkColor: uiTheme.textPrimary.withValues(alpha: 0.9),
      linkUnderline: 0.45,
      onLink: widget.onLink,
    );
    return LayoutBuilder(
      builder: (context, c) {
        final span = HikkaMarkdownView.collapsedSpan(_blocks, HikkaMarkdownView.baseStyle(fontSize: widget.fontSize, scale: scale, color: color));
        final painter = TextPainter(
          text: span,
          maxLines: widget.lines,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: c.maxWidth);
        final long = painter.didExceedMaxLines;
        painter.dispose();
        if (!long) return full;
        final Widget body;
        if (_open) {
          body = Column(
            key: const ValueKey('synopsis-open'),
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // The full view ends its last paragraph with a gap of its own
              full,
              Semantics(
                button: true,
                excludeSemantics: true,
                label: 'Згорнути опис',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _set(false),
                  child: _toggle('Згорнути', LineIcon.chevronUp, AppTones.caption),
                ),
              ),
            ],
          );
        } else {
          body = Semantics(
            key: const ValueKey('synopsis-closed'),
            button: true,
            label: 'Показати опис повністю',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _set(true),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  ShaderMask(
                    blendMode: BlendMode.dstIn,
                    shaderCallback: (r) => const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.white, Colors.white, Color(0x14FFFFFF)],
                      stops: [0, 0.55, 1],
                    ).createShader(r),
                    child: Text.rich(span, maxLines: widget.lines, overflow: TextOverflow.ellipsis),
                  ),
                  SizedBox(height: 2 * scale),
                  ExcludeSemantics(child: _toggle('Читати далі', LineIcon.chevronDown, uiTheme.textPrimary.withValues(alpha: 0.86), bold: true)),
                ],
              ),
            ),
          );
        }
        return AppAnimatedSize(alignment: Alignment.topCenter, child: body);
      },
    );
  }
}

/// A hidden block: the "Спойлер" line expands on tap (in descriptions and articles)
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
