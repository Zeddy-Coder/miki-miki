/// Мінімальний розбір Markdown для описів Hikka: абзаци, посилання, жирний і курсив, цитати,
/// списки, заголовки та блоки-спойлери (`:::spoiler … :::`). Без залежностей і без Flutter —
/// покрито тестами. Усе, що розбір не розпізнав, лишається звичайним текстом.
library;

// ── Модель ───────────────────────────────────────────────────────────────────

/// Фрагмент рядка з однаковим оформленням. Розрив рядка — окремий фрагмент `\n`.
class MdSpan {
  final String text;
  final bool bold;
  final bool italic;

  /// Адреса посилання (null — звичайний текст)
  final String? url;
  final String? title;

  const MdSpan(this.text, {this.bold = false, this.italic = false, this.url, this.title});

  bool get isBreak => text == '\n';
  bool get isLink => url != null;

  bool _sameStyle(MdSpan o) => bold == o.bold && italic == o.italic && url == o.url && title == o.title;

  @override
  bool operator ==(Object other) => other is MdSpan && other.text == text && _sameStyle(other);

  @override
  int get hashCode => Object.hash(text, bold, italic, url, title);

  @override
  String toString() => 'MdSpan(${text.replaceAll('\n', '\\n')}${bold ? ', bold' : ''}${italic ? ', italic' : ''}${url != null ? ', $url' : ''})';
}

sealed class MdBlock {
  const MdBlock();
}

/// Абзац; [heading] 1…6 — заголовок, 0 — звичайний текст
class MdParagraph extends MdBlock {
  final List<MdSpan> spans;
  final int heading;

  const MdParagraph(this.spans, {this.heading = 0});
}

/// Пункт списку: [marker] — «•» або «1.»
class MdListItem extends MdBlock {
  final String marker;
  final List<MdSpan> spans;

  const MdListItem(this.marker, this.spans);
}

class MdQuote extends MdBlock {
  final List<MdBlock> blocks;

  const MdQuote(this.blocks);
}

/// Прихований за натисканням блок (`:::spoiler`)
class MdSpoiler extends MdBlock {
  final String? title;
  final List<MdBlock> blocks;

  const MdSpoiler(this.blocks, {this.title});
}

// ── Посилання ────────────────────────────────────────────────────────────────

enum HikkaLinkKind { anime, character, collection, article, external }

/// Куди веде посилання з опису: на сторінку каталогу всередині застосунку чи назовні
class HikkaLinkTarget {
  final HikkaLinkKind kind;
  final String slug;
  final String url;

  const HikkaLinkTarget(this.kind, this.slug, this.url);

  bool get isInternal => kind != HikkaLinkKind.external;

  /// `hikka.io/anime/<slug>`, `hikka.io/characters/<slug>`, `hikka.io/collections/<id>`, `hikka.io/articles/<slug>`
  /// (і відносні `/anime/<slug>`) відкриваються в застосунку; усе інше — зовнішнє
  static HikkaLinkTarget classify(String url) {
    final clean = url.trim();
    final uri = Uri.tryParse(clean);
    if (uri == null) return HikkaLinkTarget(HikkaLinkKind.external, '', clean);
    final host = uri.host.toLowerCase();
    final isHikka = host == 'hikka.io' || host == 'www.hikka.io' || (host.isEmpty && !uri.hasScheme && clean.startsWith('/'));
    if (isHikka) {
      final seg = [for (final s in uri.pathSegments) if (s.isNotEmpty) s];
      if (seg.length >= 2) {
        if (seg[0] == 'anime') return HikkaLinkTarget(HikkaLinkKind.anime, seg[1], clean);
        if (seg[0] == 'characters') return HikkaLinkTarget(HikkaLinkKind.character, seg[1], clean);
        if (seg[0] == 'collections') return HikkaLinkTarget(HikkaLinkKind.collection, seg[1], clean);
        if (seg[0] == 'articles') return HikkaLinkTarget(HikkaLinkKind.article, seg[1], clean);
      }
    }
    return HikkaLinkTarget(HikkaLinkKind.external, '', clean);
  }
}

// ── Розбір ───────────────────────────────────────────────────────────────────

class HikkaMarkdown {
  const HikkaMarkdown._();

  /// Блоки документа. Порожній або `null` текст дає порожній список.
  static List<MdBlock> parse(String? source) {
    if (source == null) return const [];
    final text = source.replaceAll('\r\n', '\n').replaceAll('\r', '\n').replaceAll('​', '').replaceAll('﻿', '');
    if (text.trim().isEmpty) return const [];
    return _blocks(text.split('\n'));
  }

  /// Звичайний текст без розмітки (спойлери пропускаються): для коротких витягів
  static String plain(String? source, {String separator = '\n', bool includeSpoilers = false}) {
    final out = <String>[];
    void walk(List<MdBlock> blocks) {
      for (final b in blocks) {
        switch (b) {
          case MdParagraph():
            out.add(_plainSpans(b.spans));
          case MdListItem():
            out.add('${b.marker} ${_plainSpans(b.spans)}');
          case MdQuote():
            walk(b.blocks);
          case MdSpoiler():
            if (includeSpoilers) walk(b.blocks);
        }
      }
    }

    walk(parse(source));
    return out.where((s) => s.isNotEmpty).join(separator);
  }

  static String _plainSpans(List<MdSpan> spans) => spans.map((s) => s.text).join();

  // ── Блоки ──

  static final RegExp _heading = RegExp(r'^(#{1,6})\s+(.*?)\s*#*\s*$');
  static final RegExp _listItem = RegExp(r'^\s{0,3}([-*+]|\d{1,3}[.)])\s+(.*)$');

  static bool _startsBlock(String line) {
    final t = line.trimLeft();
    return t.startsWith(':::') || t.startsWith('>') || _heading.hasMatch(t) || _listItem.hasMatch(line);
  }

  static List<MdBlock> _blocks(List<String> lines) {
    final out = <MdBlock>[];
    var i = 0;
    while (i < lines.length) {
      final line = lines[i];
      final t = line.trim();
      if (t.isEmpty) {
        i++;
        continue;
      }

      // Контейнер ":::spoiler [заголовок]" … ":::"
      if (t.startsWith(':::')) {
        final head = t.substring(3).trim();
        if (head.isEmpty) {
          i++; // зайве закриття
          continue;
        }
        var depth = 1;
        var j = i + 1;
        final inner = <String>[];
        while (j < lines.length) {
          final tj = lines[j].trim();
          if (tj == ':::') {
            depth--;
            if (depth == 0) break;
          } else if (tj.startsWith(':::')) {
            depth++;
          }
          inner.add(lines[j]);
          j++;
        }
        final children = _blocks(inner);
        final isSpoiler = head == 'spoiler' || head.startsWith('spoiler ');
        if (isSpoiler) {
          final title = head.length > 7 ? head.substring(7).trim() : '';
          if (children.isNotEmpty) out.add(MdSpoiler(children, title: title.isEmpty ? null : title));
        } else {
          out.addAll(children); // невідомий контейнер показуємо як є
        }
        i = j + 1;
        continue;
      }

      // Цитата
      if (t.startsWith('>')) {
        final inner = <String>[];
        while (i < lines.length && lines[i].trimLeft().startsWith('>')) {
          var s = lines[i].trimLeft().substring(1);
          if (s.startsWith(' ')) s = s.substring(1);
          inner.add(s);
          i++;
        }
        final children = _blocks(inner);
        if (children.isNotEmpty) out.add(MdQuote(children));
        continue;
      }

      // Заголовок
      final h = _heading.firstMatch(t);
      if (h != null) {
        final spans = _tidy(parseInline(h.group(2)!));
        if (spans.isNotEmpty) out.add(MdParagraph(spans, heading: h.group(1)!.length));
        i++;
        continue;
      }

      // Пункт списку
      final li = _listItem.firstMatch(line);
      if (li != null) {
        final marker = li.group(1)!;
        final spans = _tidy(parseInline(li.group(2)!));
        if (spans.isNotEmpty) out.add(MdListItem(RegExp(r'\d').hasMatch(marker) ? marker : '•', spans));
        i++;
        continue;
      }

      // Абзац: рядки до порожнього або до початку іншого блоку
      final para = <String>[];
      while (i < lines.length && lines[i].trim().isNotEmpty && (para.isEmpty || !_startsBlock(lines[i]))) {
        para.add(lines[i].trim());
        i++;
      }
      final spans = _tidy(parseInline(para.join('\n')));
      if (spans.isNotEmpty) out.add(MdParagraph(spans));
    }
    return out;
  }

  /// Зливає сусідні фрагменти з однаковим оформленням, обрізає краї абзацу
  static List<MdSpan> _tidy(List<MdSpan> spans) {
    final merged = <MdSpan>[];
    for (final s in spans) {
      if (s.text.isEmpty) continue;
      if (merged.isNotEmpty && !s.isBreak && !merged.last.isBreak && merged.last._sameStyle(s)) {
        final prev = merged.removeLast();
        merged.add(MdSpan('${prev.text}${s.text}', bold: s.bold, italic: s.italic, url: s.url, title: s.title));
      } else {
        merged.add(s);
      }
    }
    // Початок і кінець: прибираємо пропуски й розриви
    while (merged.isNotEmpty) {
      final first = merged.first;
      if (first.isBreak || first.text.trim().isEmpty) {
        merged.removeAt(0);
      } else {
        final trimmed = first.text.trimLeft();
        if (trimmed != first.text) merged[0] = MdSpan(trimmed, bold: first.bold, italic: first.italic, url: first.url, title: first.title);
        break;
      }
    }
    while (merged.isNotEmpty) {
      final last = merged.last;
      if (last.isBreak || last.text.trim().isEmpty) {
        merged.removeLast();
      } else {
        final trimmed = last.text.trimRight();
        if (trimmed != last.text) merged[merged.length - 1] = MdSpan(trimmed, bold: last.bold, italic: last.italic, url: last.url, title: last.title);
        break;
      }
    }
    // Пропуски навколо розривів рядка
    for (int i = 0; i < merged.length; i++) {
      final s = merged[i];
      if (s.isBreak) continue;
      var text = s.text;
      if (i + 1 < merged.length && merged[i + 1].isBreak) text = text.trimRight();
      if (i > 0 && merged[i - 1].isBreak) text = text.trimLeft();
      if (text != s.text) merged[i] = MdSpan(text, bold: s.bold, italic: s.italic, url: s.url, title: s.title);
    }
    merged.removeWhere((s) => s.text.isEmpty);
    return merged;
  }

  // ── Рядкова розмітка ──

  /// Розбір одного абзацу (рядки розділені `\n`)
  static List<MdSpan> parseInline(String s) {
    final out = <MdSpan>[];
    _inline(s, 0, s.length, false, false, null, null, out);
    return out;
  }

  static bool _isAsciiPunct(int c) => (c >= 0x21 && c <= 0x2f) || (c >= 0x3a && c <= 0x40) || (c >= 0x5b && c <= 0x60) || (c >= 0x7b && c <= 0x7e);

  static final RegExp _wordChar = RegExp(r'[\p{L}\p{N}]', unicode: true);

  static bool _isWord(String s, int i) => i >= 0 && i < s.length && _wordChar.hasMatch(String.fromCharCode(s.codeUnitAt(i)));

  static bool _isSpace(String s, int i) {
    if (i < 0 || i >= s.length) return true;
    final c = s.codeUnitAt(i);
    return c == 0x20 || c == 0x09 || c == 0x0a || c == 0xa0;
  }

  static final RegExp _entity = RegExp(r'&(#[xX][0-9a-fA-F]{1,6}|#[0-9]{1,7}|[a-zA-Z]{2,8});');
  static const Map<String, String> _namedEntities = {
    'amp': '&',
    'lt': '<',
    'gt': '>',
    'quot': '"',
    'apos': "'",
    'nbsp': ' ',
    'laquo': '«',
    'raquo': '»',
    'hellip': '…',
    'mdash': '—',
    'ndash': '–',
  };

  /// Розпізнана HTML-сутність у позиції [i]: (символ, позиція після неї)
  static (String, int)? _entityAt(String s, int i, int end) {
    final m = _entity.matchAsPrefix(s, i);
    if (m == null || m.end > end) return null;
    final body = m.group(1)!;
    String? ch;
    if (body.startsWith('#')) {
      final hex = body.length > 1 && (body[1] == 'x' || body[1] == 'X');
      final code = int.tryParse(hex ? body.substring(2) : body.substring(1), radix: hex ? 16 : 10);
      if (code != null && code > 0 && code <= 0x10ffff && !(code >= 0xd800 && code <= 0xdfff)) ch = String.fromCharCode(code);
    } else {
      ch = _namedEntities[body];
    }
    return ch == null ? null : (ch, m.end);
  }

  static void _inline(String s, int start, int end, bool bold, bool italic, String? url, String? title, List<MdSpan> out) {
    final buf = StringBuffer();
    void flush() {
      if (buf.isEmpty) return;
      out.add(MdSpan(buf.toString(), bold: bold, italic: italic, url: url, title: title));
      buf.clear();
    }

    var i = start;
    while (i < end) {
      final c = s.codeUnitAt(i);

      // Екранування: \* \_ \[ …
      if (c == 0x5c /* \ */ && i + 1 < end) {
        final n = s.codeUnitAt(i + 1);
        if (_isAsciiPunct(n)) {
          buf.writeCharCode(n);
          i += 2;
          continue;
        }
        if (n == 0x0a) {
          flush();
          out.add(MdSpan('\n', bold: bold, italic: italic, url: url, title: title));
          i += 2;
          continue;
        }
      }

      // Розрив рядка
      if (c == 0x0a) {
        flush();
        out.add(MdSpan('\n', bold: bold, italic: italic, url: url, title: title));
        i++;
        continue;
      }

      // HTML-сутності: &#x20; &amp; …
      if (c == 0x26 /* & */) {
        final e = _entityAt(s, i, end);
        if (e != null) {
          buf.write(e.$1);
          i = e.$2;
          continue;
        }
      }

      // [текст](адреса "підказка")
      if (c == 0x5b /* [ */ && url == null) {
        final link = _parseLink(s, i, end);
        if (link != null) {
          flush();
          final inner = <MdSpan>[];
          _inline(s, link.textStart, link.textEnd, bold, italic, link.url, link.title, inner);
          if (inner.isEmpty) inner.add(MdSpan(link.url, bold: bold, italic: italic, url: link.url, title: link.title));
          out.addAll(inner);
          i = link.next;
          continue;
        }
      }

      // <https://…>
      if (c == 0x3c /* < */ && url == null) {
        final close = s.indexOf('>', i + 1);
        if (close > 0 && close < end) {
          final inner = s.substring(i + 1, close);
          if (RegExp(r'^https?://\S+$').hasMatch(inner)) {
            flush();
            out.add(MdSpan(inner, bold: bold, italic: italic, url: inner));
            i = close + 1;
            continue;
          }
        }
      }

      // Голе посилання https://…
      if ((c == 0x68 /* h */) && url == null && !_isWord(s, i - 1) && (s.startsWith('http://', i) || s.startsWith('https://', i))) {
        var j = i;
        while (j < end && !_isSpace(s, j) && s[j] != '<' && s[j] != '>' && s[j] != '"') {
          j++;
        }
        while (j > i && '.,;:!?'.contains(s[j - 1])) {
          j--;
        }
        // закриваюча дужка без відкриваючої належить тексту навколо
        while (j > i && (s[j - 1] == ')' || s[j - 1] == ']') && !_balanced(s.substring(i, j))) {
          j--;
        }
        if (j - i > 8) {
          flush();
          final target = s.substring(i, j);
          out.add(MdSpan(target, bold: bold, italic: italic, url: target));
          i = j;
          continue;
        }
      }

      // Виділення: * _ ** __ *** ___
      if (c == 0x2a /* * */ || c == 0x5f /* _ */) {
        final emphasis = _parseEmphasis(s, i, end, c);
        if (emphasis != null) {
          flush();
          _inline(s, i + emphasis.count, emphasis.closeAt, bold || emphasis.count >= 2, italic || emphasis.count == 1 || emphasis.count == 3, url, title, out);
          i = emphasis.closeAt + emphasis.count;
          continue;
        }
        // не відкриває виділення — лишається текстом (разом з усім рядом однакових символів)
        var j = i;
        while (j < end && s.codeUnitAt(j) == c) {
          buf.writeCharCode(c);
          j++;
        }
        i = j;
        continue;
      }

      buf.writeCharCode(c);
      i++;
    }
    flush();
  }

  static bool _balanced(String s) {
    var round = 0, square = 0;
    for (int i = 0; i < s.length; i++) {
      switch (s[i]) {
        case '(':
          round++;
        case ')':
          round--;
        case '[':
          square++;
        case ']':
          square--;
      }
    }
    return round >= 0 && square >= 0;
  }

  /// Виділення, що починається в [i]: скільки символів у відкриваючому ряді й де закриваючий ряд
  static ({int count, int closeAt})? _parseEmphasis(String s, int i, int end, int mark) {
    var n = 0;
    while (i + n < end && s.codeUnitAt(i + n) == mark) {
      n++;
    }
    if (n > 3) return null;
    final after = i + n;
    if (after >= end || _isSpace(s, after)) return null;
    // `_` посеред слова (snake_case) виділенням не є
    if (mark == 0x5f && _isWord(s, i - 1)) return null;

    var j = after;
    while (j < end) {
      final c = s.codeUnitAt(j);
      if (c == 0x5c /* \ */) {
        j += 2;
        continue;
      }
      if (c == 0x5b /* [ */) {
        final link = _parseLink(s, j, end);
        if (link != null) {
          j = link.next; // адреса посилання не може закривати виділення
          continue;
        }
      }
      if (c == mark) {
        var k = j;
        while (k < end && s.codeUnitAt(k) == mark) {
          k++;
        }
        final run = k - j;
        final closes = run == n && j > after && !_isSpace(s, j - 1) && !(mark == 0x5f && _isWord(s, k));
        if (closes) return (count: n, closeAt: j);
        j = k;
        continue;
      }
      j++;
    }
    return null;
  }

  /// Посилання `[текст](адреса "підказка")`, що починається в [i]
  static ({int textStart, int textEnd, String url, String? title, int next})? _parseLink(String s, int i, int end) {
    // Закриваюча `]` з урахуванням вкладених дужок і екранування
    var depth = 0;
    var j = i;
    var close = -1;
    while (j < end) {
      final c = s.codeUnitAt(j);
      if (c == 0x5c) {
        j += 2;
        continue;
      }
      if (c == 0x5b) {
        depth++;
      } else if (c == 0x5d) {
        depth--;
        if (depth == 0) {
          close = j;
          break;
        }
      }
      j++;
    }
    if (close < 0 || close + 1 >= end || s.codeUnitAt(close + 1) != 0x28 /* ( */) return null;

    var p = close + 2;
    while (p < end && _isSpace(s, p) && s.codeUnitAt(p) != 0x0a) {
      p++;
    }
    final url = StringBuffer();
    if (p < end && s.codeUnitAt(p) == 0x3c /* < */) {
      p++;
      while (p < end && s.codeUnitAt(p) != 0x3e && s.codeUnitAt(p) != 0x0a) {
        url.writeCharCode(s.codeUnitAt(p));
        p++;
      }
      if (p >= end || s.codeUnitAt(p) != 0x3e) return null;
      p++;
    } else {
      var parens = 0;
      while (p < end) {
        final c = s.codeUnitAt(p);
        if (c == 0x5c && p + 1 < end && _isAsciiPunct(s.codeUnitAt(p + 1))) {
          url.writeCharCode(s.codeUnitAt(p + 1));
          p += 2;
          continue;
        }
        if (_isSpace(s, p)) break;
        if (c == 0x28) {
          parens++;
        } else if (c == 0x29) {
          if (parens == 0) break;
          parens--;
        }
        url.writeCharCode(c);
        p++;
      }
    }
    if (url.isEmpty) return null;

    while (p < end && _isSpace(s, p) && s.codeUnitAt(p) != 0x0a) {
      p++;
    }
    String? title;
    if (p < end && (s.codeUnitAt(p) == 0x22 || s.codeUnitAt(p) == 0x27 || s.codeUnitAt(p) == 0x28)) {
      final open = s.codeUnitAt(p);
      final closer = open == 0x28 ? 0x29 : open;
      final t = StringBuffer();
      p++;
      var closed = false;
      while (p < end) {
        final c = s.codeUnitAt(p);
        if (c == 0x5c && p + 1 < end && _isAsciiPunct(s.codeUnitAt(p + 1))) {
          t.writeCharCode(s.codeUnitAt(p + 1));
          p += 2;
          continue;
        }
        if (c == closer) {
          closed = true;
          p++;
          break;
        }
        t.writeCharCode(c);
        p++;
      }
      if (!closed) return null;
      title = t.toString();
      while (p < end && _isSpace(s, p) && s.codeUnitAt(p) != 0x0a) {
        p++;
      }
    }
    if (p >= end || s.codeUnitAt(p) != 0x29 /* ) */) return null;

    return (textStart: i + 1, textEnd: close, url: url.toString(), title: title, next: p + 1);
  }
}
