/// Jsoup-подібні вибірки поверх `package:html`: CSS-селектори з `:contains` / `:containsOwn`,
/// непозначені значення атрибутів (`input[value*=https://x]`) і «людський» текст елемента.
/// Парсери сайтів пишуться майже один в один із Kotlin-коду розширень Aniyomi.
library;

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

Document parseHtml(String text) => html_parser.parse(text);

final RegExp _unquotedAttr = RegExp(r'''\[\s*([\w:.-]+)\s*([~|^$*!]?=)\s*([^\]"'\s][^\]]*?)\s*\]''');
final RegExp _containsTail = RegExp(r'^(.*?):(contains|containsOwn)\((.*)\)\s*$', dotAll: true);

/// Розділяє перелік через кому, не чіпаючи коми в дужках, лапках та квадратних дужках.
List<String> _splitTopLevel(String css) {
  final parts = <String>[];
  var depth = 0;
  String? quote;
  var start = 0;
  for (int i = 0; i < css.length; i++) {
    final c = css[i];
    if (quote != null) {
      if (c == quote) quote = null;
      continue;
    }
    if (c == '"' || c == "'") {
      quote = c;
    } else if (c == '(' || c == '[') {
      depth++;
    } else if (c == ')' || c == ']') {
      depth--;
    } else if (c == ',' && depth == 0) {
      parts.add(css.substring(start, i));
      start = i + 1;
    }
  }
  parts.add(css.substring(start));
  return parts.map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
}

String _quoteAttrValues(String css) =>
    css.replaceAllMapped(_unquotedAttr, (m) => '[${m[1]}${m[2]}"${m[3]!.replaceAll('"', r'\"')}"]');

bool _matchesText(Element e, String kind, String needle) {
  final hay = kind == 'containsOwn' ? ownText(e) : elementText(e);
  return hay.toLowerCase().contains(needle.toLowerCase());
}

/// `root.select(css)` як у Jsoup: усі збіги у порядку документа.
List<Element> select(Node root, String css) {
  final parts = _splitTopLevel(css);
  final found = <Element>[];
  final seen = <Element>{};
  for (final part in parts) {
    final m = _containsTail.firstMatch(part);
    var base = m == null ? part : m.group(1)!.trim();
    if (base.isEmpty) base = '*';
    final query = _quoteAttrValues(base);
    final List<Element> hits;
    if (root is Document) {
      hits = root.querySelectorAll(query);
    } else if (root is Element) {
      hits = root.querySelectorAll(query);
    } else {
      hits = const [];
    }
    for (final e in hits) {
      if (m != null) {
        var needle = m.group(3)!.trim();
        if (needle.length >= 2 && (needle.startsWith('"') && needle.endsWith('"') || needle.startsWith("'") && needle.endsWith("'"))) {
          needle = needle.substring(1, needle.length - 1);
        }
        if (!_matchesText(e, m.group(2)!, needle)) continue;
      }
      if (seen.add(e)) found.add(e);
    }
  }
  if (parts.length > 1) {
    // порядок документа: впорядкувати за позицією в дереві
    final order = <Element, int>{};
    var i = 0;
    void walk(Node n) {
      if (n is Element) order[n] = i++;
      for (final c in n.nodes) {
        walk(c);
      }
    }

    final top = root is Document ? root : _rootOf(root);
    walk(top);
    found.sort((a, b) => (order[a] ?? 0).compareTo(order[b] ?? 0));
  }
  return found;
}

Node _rootOf(Node n) {
  var cur = n;
  while (cur.parentNode != null) {
    cur = cur.parentNode!;
  }
  return cur;
}

Element? selectFirst(Node root, String css) {
  final r = select(root, css);
  return r.isEmpty ? null : r.first;
}

/// Значення атрибута першого збігу, що його має; порожній рядок, якщо нема (як `Elements.attr` у Jsoup).
String attrOf(Node root, String css, String name) {
  for (final e in select(root, css)) {
    final v = e.attributes[name];
    if (v != null && v.isNotEmpty) return v;
  }
  return '';
}

/// Зведений текст усіх збігів, розділений пропуском (як `Elements.text` у Jsoup).
String textOf(Node root, String css) => select(root, css).map(elementText).where((s) => s.isNotEmpty).join(' ');

/// Код усіх `<script>` документа, склеєний через новий рядок (як `select("script").html()`).
String scriptsOf(Node root) => select(root, 'script').map((s) => s.innerHtml).join('\n');

const Set<String> _blockTags = {
  'address', 'article', 'aside', 'blockquote', 'body', 'br', 'dd', 'div', 'dl', 'dt', 'fieldset', 'figcaption', 'figure', 'footer', //
  'form', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'header', 'hr', 'li', 'main', 'nav', 'ol', 'option', 'p', 'pre', 'section', 'table',
  'tbody', 'td', 'tfoot', 'th', 'thead', 'tr', 'ul',
};

final RegExp _ws = RegExp(r'\s+');

/// «Читабельний» текст елемента, як `Element.text()` у Jsoup: без скриптів, пробіли зведені.
String elementText(Node n) {
  final sb = StringBuffer();
  void walk(Node x) {
    if (x is Text) {
      sb.write(x.data);
    } else if (x is Element) {
      final tag = x.localName ?? '';
      if (tag == 'script' || tag == 'style') return;
      final block = _blockTags.contains(tag);
      if (block) sb.write(' ');
      for (final c in x.nodes) {
        walk(c);
      }
      if (block) sb.write(' ');
    }
  }

  walk(n);
  return sb.toString().replaceAll(_ws, ' ').trim();
}

/// Власний текст елемента без тексту вкладених тегів (`Element.ownText()`)
String ownText(Element e) {
  final sb = StringBuffer();
  for (final c in e.nodes) {
    if (c is Text) sb.write(c.data);
  }
  return sb.toString().replaceAll(_ws, ' ').trim();
}

extension JsoupElement on Element {
  String attr(String name) => attributes[name] ?? '';

  /// Читабельний текст (як `text()` у Jsoup)
  String get jsoupText => elementText(this);

  List<Element> select(String css) => _select(this, css);

  Element? selectFirst(String css) => _selectFirst(this, css);
}

List<Element> _select(Node n, String css) => select(n, css);
Element? _selectFirst(Node n, String css) => selectFirst(n, css);

extension JsoupElements on List<Element> {
  String text() => map(elementText).where((s) => s.isNotEmpty).join(' ');

  String attr(String name) {
    for (final e in this) {
      final v = e.attributes[name];
      if (v != null && v.isNotEmpty) return v;
    }
    return '';
  }
}
