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
