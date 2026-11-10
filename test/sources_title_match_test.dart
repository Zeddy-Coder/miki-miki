import 'package:flutter_test/flutter_test.dart';
import 'package:miki_miki/models/source_models.dart';
import 'package:miki_miki/services/sources/title_match.dart';

void main() {
  group('нормалізація', () {
    test('сезон із різних записів, у т. ч. латинська «c» замість «с»', () {
      expect(seasonOfTitle('Хвіст Феї (1 cезон)'), 1);
      expect(seasonOfTitle('Монолог травниці - 3 сезон'), 3);
      expect(seasonOfTitle('The Apothecary Diaries Season 2'), 2);
      expect(seasonOfTitle('Kusuriya no Hitorigoto 3rd Season'), 3);
      expect(seasonOfTitle('Fairy Tail (TV-2)'), 2);
      expect(seasonOfTitle('Re:Zero II'), 2);
      expect(seasonOfTitle('Монолог травниці 2'), 2);
      expect(seasonOfTitle('Монолог травниці'), isNull);
    });

    test('текст без дужок, сезону й типу', () {
      expect(normalizeTitle('Хвіст Феї (1 cезон)'), 'хвіст феї');
      expect(normalizeTitle('Fairy Tail (TV-1)'), 'fairy tail');
      expect(normalizeTitle('Fairy Tail: OVA'), 'fairy tail');
      expect(normalizeTitle('Frieren: Beyond Journey’s End'), 'frieren beyond journeys end');
    });
  });

  group('схожість', () {
    test('той самий тайтл з різним оформленням', () {
      expect(titleSimilarity('Хвіст Феї (1 cезон)', 'Хвіст Феї'), greaterThan(0.95));
      expect(titleSimilarity('Fairy Tail (TV-1)', 'Fairy Tail'), greaterThan(0.95));
      expect(titleSimilarity('Kusuriya no Hitorigoto 3rd Season', 'Kusuriya no Hitorigoto Season 3'), greaterThan(0.95));
    });

    test('інший сезон — низька оцінка', () {
      expect(titleSimilarity('Монолог травниці - 3 сезон', 'Монолог травниці'), lessThan(0.5));
      expect(titleSimilarity('Монолог травниці 2', 'Монолог травниці - 3 сезон'), lessThan(0.5));
    });

    test('OVA / фільм — не той самий, що серіал', () {
      expect(titleSimilarity('Fairy Tail OVA', 'Fairy Tail'), lessThan(0.7));
      expect(titleSimilarity('Хвіст Феї ОВА', 'Хвіст Феї'), lessThan(0.7));
    });

    test('різні тайтли', () {
      expect(titleSimilarity('Хвіст Феї', 'Вона змушує моє серце битися'), lessThan(0.3));
    });
  });

  group('вибір найкращого', () {
    const wanted = ['Монолог травниці', 'The Apothecary Diaries', 'Kusuriya no Hitorigoto'];

    test('береться серіал, а не OVA чи інший сезон', () {
      final c = [
        const SAnime(url: '/a', title: 'Монолог травниці ОВА', originalTitle: 'Kusuriya no Hitorigoto OVA'),
        const SAnime(url: '/b', title: 'Монолог травниці - 2 сезон', originalTitle: 'Kusuriya no Hitorigoto 2nd Season'),
        const SAnime(url: '/c', title: 'Монолог травниці', originalTitle: 'Kusuriya no Hitorigoto'),
      ];
      expect(bestAnimeMatch(wanted, c)!.anime.url, '/c');
    });

    test('за оригінальною назвою, коли українська відрізняється', () {
      final c = [const SAnime(url: '/x', title: 'Записки аптекарки', originalTitle: 'The Apothecary Diaries')];
      expect(bestAnimeMatch(wanted, c)?.anime.url, '/x');
    });

    test('нічого схожого → null', () {
      final c = [const SAnime(url: '/z', title: 'Бути героєм Х'), const SAnime(url: '/y', title: 'Вона Змушує Моє Серце Битися')];
      expect(bestAnimeMatch(wanted, c), isNull);
    });

    test('рік допомагає відсікти перезапуск', () {
      final c = [
        const SAnime(url: '/old', title: 'Хвіст Феї', year: 2009),
        const SAnime(url: '/new', title: 'Хвіст Феї', year: 2018),
      ];
      expect(bestAnimeMatch(['Хвіст Феї'], c, year: 2018)!.anime.url, '/new');
    });
  });
}
