import '../constants/app_constants.dart';

/// Matching a track's language (subtitles or audio) against the language code from settings. Pure logic: no player or widgets.
///
/// The language is taken from the track label (`ukr`, `uk`, `pt-BR`), and when there is no label or it is "und", from the title
/// ("Українські", "Ukrainian [FanVox]", "UA").
class LangMatch {
  const LangMatch._();

  /// All spellings of one language: `uk` → {uk, ukr}; an unknown code → {code}
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

  /// 3-letter codes that are not in `AppConstants.langMap`
  static const Map<String, List<String>> _tagAliases = {
    'ru': ['rus'],
  };

  /// Language markers in track names: word fragments (lowercase) and separate words
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

  /// Track language from the container label: "UKR" → `ukr`, "pt-BR" → `pt`; empty if the language is not set (`und` etc.)
  static String normalizeTag(String? lang) {
    var t = (lang ?? '').trim().toLowerCase();
    if (t.isEmpty) return '';
    t = t.split(RegExp(r'[-_]')).first;
    return const {'und', 'unk', 'zxx', 'mul', 'mis'}.contains(t) ? '' : t;
  }

  static List<String> _stems(String code) {
    final known = _titleStems[code];
    if (known != null) return known;
    // Other languages: the root of the Ukrainian name ("Турецька" → "турецьк")
    final name = AppConstants.langMap[code]?.toLowerCase();
    if (name == null || name.length < 5) return const [];
    return [name.endsWith('а') || name.endsWith('я') ? name.substring(0, name.length - 1) : name];
  }

  /// Whether a track with label [language] and title [title] is in language [code] (`uk`, `en`, `ja` …)
  static bool matches(String code, {String? language, String? title}) {
    final want = aliases(code);
    if (want.isEmpty) return false;
    final tag = normalizeTag(language);
    // If there is a language label, trust it: "eng" does not become Ukrainian because of a word in the title
    if (tag.isNotEmpty) return want.contains(tag);

    final t = (title ?? '').toLowerCase();
    if (t.isEmpty) return false;
    final words = t.split(RegExp(r'[^a-zа-яіїєґ0-9]+')).where((w) => w.isNotEmpty).toSet();
    if (words.any(want.contains)) return true;
    final c = code.trim().toLowerCase();
    if ((_titleWords[c] ?? const <String>[]).any(words.contains)) return true;
    return _stems(c).any(t.contains);
  }

  /// Index of the track with labels [labels] (language names of external tracks: "Українська", "English", "ukr") by the priority of
  /// languages [priorities]; 0 if none matched (a track still has to be chosen, there is just nothing to choose it by)
  static int pickByLabel(List<String> labels, List<String> priorities) {
    for (final code in priorities) {
      for (int i = 0; i < labels.length; i++) {
        final label = labels[i].trim();
        // A short label is a language tag ("ukr"), a long one is a name ("Українська")
        if (matches(code, language: label.length <= 3 ? label : null, title: label)) return i;
      }
    }
    return 0;
  }
}
