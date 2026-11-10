import '../constants/app_constants.dart';

/// Збіг мови доріжки (субтитрів чи звуку) з кодом мови з налаштувань. Чиста логіка: без плеєра й віджетів.
///
/// Мову беремо з мітки доріжки (`ukr`, `uk`, `pt-BR`), а коли мітки нема чи вона «und» — із назви
/// («Українські», «Ukrainian [FanVox]», «UA»).
class LangMatch {
  const LangMatch._();

  /// Усі записи однієї мови: `uk` → {uk, ukr}; невідомий код → {код}
  static Set<String> aliases(String code) {
    final c = code.trim().toLowerCase();
    if (c.isEmpty) return const {};
    final out = <String>{c};
    final name = AppConstants.langMap[c];
    if (name != null) {
      AppConstants.langMap.forEach((k, v) {
        if (v == name) out.add(k);
      });
    }
    out.addAll(_tagAliases[c] ?? const []);
    return out;
  }

  /// 3-літерні коди, яких нема в `AppConstants.langMap`
  static const Map<String, List<String>> _tagAliases = {
    'ru': ['rus'],
  };

  /// Позначки мови в назвах доріжок: фрагменти слів (малими літерами) і окремі слова
  static const Map<String, List<String>> _titleStems = {
    'uk': ['ukrain', 'україн', 'укр'],
    'en': ['english', 'англ'],
    'ja': ['japan', 'япон'],
    'ru': ['russian', 'росій', 'русск', 'русск'],
    'pl': ['polish', 'польськ'],
    'de': ['german', 'німецьк'],
    'fr': ['french', 'французьк'],
    'es': ['spanish', 'іспанськ'],
    'it': ['italian', 'італійськ'],
    'pt': ['portug', 'португальськ'],
    'zh': ['chinese', 'китайськ'],
    'ko': ['korean', 'корейськ'],
  };

  static const Map<String, List<String>> _titleWords = {
    'uk': ['ua'],
    'ja': ['jp', 'jap'],
  };

  /// Мова доріжки з мітки контейнера: «UKR» → `ukr`, «pt-BR» → `pt`; порожньо, якщо мови не задано (`und` тощо)
  static String normalizeTag(String? lang) {
    var t = (lang ?? '').trim().toLowerCase();
    if (t.isEmpty) return '';
    t = t.split(RegExp(r'[-_]')).first;
    return const {'und', 'unk', 'zxx', 'mul', 'mis'}.contains(t) ? '' : t;
  }

  static List<String> _stems(String code) {
    final known = _titleStems[code];
    if (known != null) return known;
    // Решта мов: корінь української назви («Турецька» → «турецьк»)
    final name = AppConstants.langMap[code]?.toLowerCase();
    if (name == null || name.length < 5) return const [];
    return [name.endsWith('а') || name.endsWith('я') ? name.substring(0, name.length - 1) : name];
  }

  /// Чи доріжка з міткою [language] і назвою [title] — мовою [code] (`uk`, `en`, `ja` …)
  static bool matches(String code, {String? language, String? title}) {
    final want = aliases(code);
    if (want.isEmpty) return false;
    final tag = normalizeTag(language);
    // Є мітка мови — їй і вірити: «eng» не стає українською через слово в назві
    if (tag.isNotEmpty) return want.contains(tag);

    final t = (title ?? '').toLowerCase();
    if (t.isEmpty) return false;
    final words = t.split(RegExp(r'[^a-zа-яіїєґ0-9]+')).where((w) => w.isNotEmpty).toSet();
    if (words.any(want.contains)) return true;
    final c = code.trim().toLowerCase();
    if ((_titleWords[c] ?? const <String>[]).any(words.contains)) return true;
    return _stems(c).any(t.contains);
  }

  /// Індекс доріжки з підписами [labels] (назви мов зовнішніх доріжок: «Українська», «English», «ukr») за пріоритетом
  /// мов [priorities]; 0, якщо жодна не збіглась (доріжку все одно треба обрати, її просто немає за що вибирати)
  static int pickByLabel(List<String> labels, List<String> priorities) {
    for (final code in priorities) {
      for (int i = 0; i < labels.length; i++) {
        final label = labels[i].trim();
        // Короткий підпис — це мітка мови («ukr»), довгий — назва («Українська»)
        if (matches(code, language: label.length <= 3 ? label : null, title: label)) return i;
      }
    }
    return 0;
  }
}
