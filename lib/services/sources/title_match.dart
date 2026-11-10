/// Зіставлення назв аніме з різних сайтів: «Хвіст Феї (1 cезон)» ↔ «Fairy Tail», «Монолог травниці - 3 сезон» ↔ «Kusuriya no Hitorigoto 3rd Season».
/// Чиста Dart-логіка. Назви нормалізуються (регістр, дужки, розділові знаки, номер сезону, тип OVA / фільм),
/// порівнюються за біграмами, а розбіжність сезону чи типу сильно знижує оцінку.
library;

import '../../models/source_models.dart';

final RegExp _brackets = RegExp(r'[\(\[\{][^\)\]\}]*[\)\]\}]');
final RegExp _punct = RegExp(r'[^\p{L}\p{N}\s]+', unicode: true);
final RegExp _spaces = RegExp(r'\s+');

// У сайтів трапляється латинська «c» замість кириличної «с» («cезон»), тож у шаблонах обидві.
final List<RegExp> _seasonPatterns = [
  RegExp(r'(\d+)\s*[-–]?\s*(?:й|ий|ій|го)?\s*[cс]езон', unicode: true),
  RegExp(r'[cс]езон\s*[:№#-]?\s*(\d+)', unicode: true),
  RegExp(r'season\s*(\d+)'),
  RegExp(r'(\d+)\s*(?:st|nd|rd|th)\s+season'),
  RegExp(r'\btv\s*-?\s*(\d+)\b'),
  RegExp(r'\bs(\d{1,2})\b'),
];
final RegExp _romanTail = RegExp(r'\s(ii|iii|iv|v|vi)$');
final RegExp _digitTail = RegExp(r'\s([2-9])$');

const Map<String, int> _roman = {'ii': 2, 'iii': 3, 'iv': 4, 'v': 5, 'vi': 6};

const Set<String> _typeWords = {'ova', 'ona', 'oad', 'special', 'specials', 'movie', 'film', 'фільм', 'ова', 'спешл', 'спецвипуск'};

/// Приводить рядок до порівнянного вигляду без номера сезону й дужок.
String normalizeTitle(String s) => _base(s).text;

/// Номер сезону, якщо назва його містить (`null` — не вказано, тобто перший)
int? seasonOfTitle(String s) => _base(s).season;

class _Norm {
  final String text;
  final int? season;
  final Set<String> types;
  const _Norm(this.text, this.season, this.types);
}

_Norm _base(String raw) {
  var s = raw.toLowerCase().replaceAll(RegExp("[’'ʼ`]"), '').replaceAll('ё', 'е');
  int? season;
  // сезон шукаємо до видалення дужок: «Хвіст Феї (1 cезон)»
  for (final p in _seasonPatterns) {
    final m = p.firstMatch(s);
    if (m != null) {
      season = int.tryParse(m.group(1)!);
      s = s.replaceFirst(m.group(0)!, ' ');
      break;
    }
  }
  s = s.replaceAll(_brackets, ' ').replaceAll(_punct, ' ').replaceAll(_spaces, ' ').trim();
  if (season == null) {
    final r = _romanTail.firstMatch(s);
    if (r != null && s.split(' ').length > 1) {
      season = _roman[r.group(1)!];
      s = s.substring(0, r.start).trim();
    } else {
      final d = _digitTail.firstMatch(s);
      if (d != null && s.split(' ').length > 1) {
        season = int.tryParse(d.group(1)!);
        s = s.substring(0, d.start).trim();
      }
    }
  }
  final words = s.split(' ').where((w) => w.isNotEmpty).toList();
  final types = words.where(_typeWords.contains).toSet();
  final kept = words.where((w) => !_typeWords.contains(w)).join(' ');
  return _Norm(kept, season, types);
}

Set<String> _bigrams(String s) {
  final t = ' $s ';
  return {for (int i = 0; i + 1 < t.length; i++) t.substring(i, i + 2)};
}

double _dice(String a, String b) {
  if (a == b) return 1;
  final x = _bigrams(a), y = _bigrams(b);
  if (x.isEmpty || y.isEmpty) return 0;
  final common = x.intersection(y).length;
  return 2 * common / (x.length + y.length);
}

/// Схожість двох назв, 0..1. Різні сезони чи типи (OVA ↔ серіал) дають значно меншу оцінку.
double titleSimilarity(String a, String b) {
  final x = _base(a), y = _base(b);
  if (x.text.isEmpty || y.text.isEmpty) return 0;
  var score = _dice(x.text, y.text);
  final sx = x.season ?? 1, sy = y.season ?? 1;
  if (sx != sy) score *= 0.35;
  final tx = x.types, ty = y.types;
  if (tx.length != ty.length || !tx.containsAll(ty)) score *= 0.6;
  return score;
}

class TitleMatch {
  final SAnime anime;
  final double score;
  const TitleMatch(this.anime, this.score);
}

/// Найкращий збіг серед кандидатів: порівнюються всі назви Hikka з усіма назвами кандидата (укр. + оригінальна).
/// Нижче порогу — `null`. Якщо є рік і в кандидата він відомий та різниться більш ніж на рік — оцінка знижується.
TitleMatch? bestAnimeMatch(List<String> wanted, List<SAnime> candidates, {int? year, double threshold = 0.74}) {
  final titles = wanted.where((t) => t.trim().isNotEmpty).toList();
  if (titles.isEmpty) return null;
  TitleMatch? best;
  for (final c in candidates) {
    var score = 0.0;
    for (final w in titles) {
      for (final t in c.allTitles) {
        final v = titleSimilarity(w, t);
        if (v > score) score = v;
      }
    }
    final cy = c.year;
    if (year != null && cy != null && (cy - year).abs() > 1) score *= 0.7;
    if (best == null || score > best.score) best = TitleMatch(c, score);
  }
  return best != null && best.score >= threshold ? best : null;
}
