/// Episode / season number from human-readable site titles: "Серія 12 - …", "12 серія", "Сезон 2", "Episode 5".
library;

final RegExp _epWord = RegExp(r'(?:серія|серiя|епізод|ep\.?|episode|#)\s*(\d+(?:[.,]\d+)?)', caseSensitive: false);
final RegExp _epAfter = RegExp(r'(\d+(?:[.,]\d+)?)\s*(?:серія|серiя|епізод|ep\b|episode)', caseSensitive: false);
final RegExp _seasonWord = RegExp(r'(?:сезон|season|s)\s*(\d+)', caseSensitive: false);
final RegExp _seasonAfter = RegExp(r'(\d+)\s*(?:сезон|season)', caseSensitive: false);
final RegExp _leadingNumber = RegExp(r'^\s*(\d+(?:[.,]\d+)?)\b');

/// `null`: there is no number in the title (a movie, a special)
double? parseEpisodeNumber(String name) {
  final m = _epWord.firstMatch(name) ?? _epAfter.firstMatch(name) ?? _leadingNumber.firstMatch(name);
  if (m == null) return null;
  return double.tryParse(m.group(1)!.replaceAll(',', '.'));
}

int? parseSeasonNumber(String name) {
  final m = _seasonWord.firstMatch(name) ?? _seasonAfter.firstMatch(name);
  if (m == null) return null;
  return int.tryParse(m.group(1)!);
}

/// Whether the episode is "main" (numbered), not a movie / OVA / special
bool looksLikeNumbered(String name) => parseEpisodeNumber(name) != null;

final RegExp _titleAfterWord = RegExp(
  r'^\s*(?:(?:сезон|season)\s*\d+\s*[·.,:–—-]?\s*)?(?:серія|серiя|епізод|episode)\s*\d+(?:[.,]\d+)?\s*[.:–—-]\s*(.+)$',
  caseSensitive: false,
);
final RegExp _titleAfterNumber = RegExp(r'^\s*\d+(?:[.,]\d+)?\s*(?:серія|серiя|епізод)\s*[.:–—-]\s*(.+)$', caseSensitive: false);
// (`\b` knows only Latin letters: the Cyrillic marks go without it)
final RegExp _extraMark = RegExp(r'^[\(\[]?\s*((ova|ona|special|movie)\b|спешл|спецвипуск|спеціальний|фільм)', caseSensitive: false);
final RegExp _cyrillicLetters = RegExp(r'[А-Яа-яІіЇїЄєҐґ]{2}');

/// The episode's own Ukrainian title in a site's name, after its number: «Серія 13 - Нацу проти Юкі» → «Нацу проти Юкі»
/// (null: just a number, «Сезон 1 · Серія 1», an OVA mark, a title not in Cyrillic)
String? siteEpisodeTitle(String name) {
  final m = _titleAfterWord.firstMatch(name) ?? _titleAfterNumber.firstMatch(name);
  final t = m?.group(1)?.trim() ?? '';
  if (t.length < 3 || !_cyrillicLetters.hasMatch(t) || _extraMark.hasMatch(t)) return null;
  return t;
}
