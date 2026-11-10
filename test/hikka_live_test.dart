// «Живий» тест: усі запити каталогу проти справжнього api.hikka.io. Не входить у звичайний набір:
// запускати вручну — `flutter test test/hikka_live_test.dart` (потрібен інтернет).
@Timeout(Duration(minutes: 6))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:miki_miki/models/hikka_models.dart';
import 'package:miki_miki/services/hikka_api.dart';
import 'package:miki_miki/services/hikka_franchise.dart';

void main() {
  final api = HikkaApi();
  const frieren = 'sousou-no-frieren-ad4e3e';

  test('жанри', () async {
    final g = await api.genres();
    expect(g.length, greaterThan(40));
    expect(g.any((e) => e.slug == 'fantasy'), isTrue);
  });

  test('каталог: типове сортування, пошук, фільтри; 18+ не потрапляє', () async {
    final top = await api.searchAnime(HikkaSearchFilters(), size: 8);
    expect(top.items.length, 8);
    expect(top.total, greaterThan(1000));
    expect(top.items.every((a) => !a.isAdult), isTrue);
    expect(top.items.first.hasScore, isTrue);

    final found = await api.searchAnime(HikkaSearchFilters(query: 'Фрірен'), size: 6);
    expect(found.items.any((a) => a.slug == frieren), isTrue, reason: 'пошук українською');
    final found2 = await api.searchAnime(HikkaSearchFilters(query: 'Frieren'), size: 6);
    expect(found2.items.any((a) => a.slug == frieren), isTrue, reason: 'пошук англійською');

    final ongoing = await api.searchAnime(HikkaSearchFilters(statuses: {'ongoing'}, genres: {'fantasy'}), size: 6);
    expect(ongoing.items, isNotEmpty);
    expect(ongoing.items.every((a) => a.isOngoing), isTrue);

    final second = await api.searchAnime(HikkaSearchFilters(), size: 8, page: 2);
    expect(second.page, 2);
    expect(second.items.first.slug, isNot(top.items.first.slug));
  });

  test('сторінка аніме: повні дані', () async {
    final a = await api.anime(frieren);
    expect(a.title(HikkaTitleLang.ua), isNotEmpty);
    expect(a.synopsisUa ?? a.synopsisEn, isNotNull);
    expect(a.genres, isNotEmpty);
    expect(a.studios, isNotEmpty);
    expect(a.external, isNotEmpty);
    expect(a.hasFranchise, isTrue);
    expect(a.isAdult, isFalse);
  });

  test('персонажі, автори, рекомендації', () async {
    final chars = await api.animeCharacters(frieren, size: 10);
    expect(chars.items, isNotEmpty);
    expect(chars.items.any((r) => r.main), isTrue);
    final staff = await api.animeStaff(frieren, size: 10);
    expect(staff.items, isNotEmpty);
    expect(staff.items.first.person.name, isNotEmpty);
    final recs = await api.recommendations(frieren, size: 6);
    expect(recs.items, isNotEmpty);
    expect(recs.items.every((a) => !a.isAdult), isTrue);
  });

  test('франшиза: лише аніме, поточний у моделі', () async {
    final data = await api.franchise(frieren);
    expect(data.anime.length, greaterThan(1));
    final model = FranchiseModel.build(data, frieren);
    expect(model, isNotNull);
    expect(model!.nodes.length, data.anime.length);
    expect(model.chain, isNotEmpty);
  });

  test('календар', () async {
    final s = await api.schedule(size: 8);
    expect(s.items, isNotEmpty);
    expect(s.items.every((e) => !e.anime.isAdult), isTrue);
    expect(s.items.first.episode, greaterThan(0));
  });

  test('персонажі: популярні, пошук, сторінка, аніме й озвучення', () async {
    final popular = await api.searchCharacters('', size: 8);
    expect(popular.items, isNotEmpty);
    final found = await api.searchCharacters('Фрірен', size: 6);
    expect(found.items, isNotEmpty);
    final slug = found.items.first.slug;
    final c = await api.character(slug);
    expect(c.name, isNotEmpty);
    final anime = await api.characterAnime(slug, size: 6);
    expect(anime.items, isNotEmpty);
    final voices = await api.characterVoices(slug, size: 30);
    expect(voices.items, isNotEmpty);
    final groups = HikkaCharacterVoice.groupByLanguage(voices.items);
    // Усі мови мають людські назви: жодної «сирої» двобуквеної (en / ja) у підписах
    for (final g in groups) {
      expect(g.$1.length, greaterThan(2), reason: 'код мови без перекладу: ${g.$1}');
    }
    print('мови озвучення: ${groups.map((g) => g.$1).toList()}');
  });

  test('неіснуючий slug — зрозуміла помилка «не знайдено»', () async {
    await expectLater(
      api.anime('there-is-no-such-anime-zzzz'),
      throwsA(isA<HikkaException>().having((e) => e.kind, 'kind', HikkaErrorKind.notFound)),
    );
  });
}
