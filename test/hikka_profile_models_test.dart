import 'package:flutter_test/flutter_test.dart';
import 'package:miki_miki/models/hikka_profile_models.dart';
import 'package:miki_miki/models/hikka_models.dart';
import 'package:miki_miki/models/hikka_user_models.dart';

import 'package:miki_miki/services/hikka_markdown.dart';

/// api.hikka.io responses for the ZEDDY profile (shortened)
const _anime = {'data_type': 'anime', 'slug': 'masamune-kun-no-revenge-r', 'title_ua': 'Помста Масамуне - 2 сезон', 'episodes_total': 12};

Map<String, dynamic> _h(String type, Map<String, dynamic> before, Map<String, dynamic> after, {bool? isNew, Map<String, dynamic>? content = _anime}) => {
      'reference': 'r-$type',
      'created': 1794429892,
      'updated': 1794429900,
      'history_type': type,
      'content': content,
      'data': {'before': before, 'after': after, if (isNew != null) 'new_watch': isNew},
    };

String _describe(String type, Map<String, dynamic> before, Map<String, dynamic> after, {bool? isNew}) =>
    HikkaHistoryEntry.fromJson(_h(type, before, after, isNew: isNew)).describe();

void main() {
  test('користувач: роль, посилання, обкладинка', () {
    final u = HikkaUser.fromJson({
      'reference': '94e6',
      'username': 'ZEDDY',
      'description': 'Повелитель туалетних мух',
      'links': [
        {'url': 'https://t.me/oZEDDYo', 'text': 'Telegram', 'icon': 'telegram'},
        {'url': 'https://www.example.com/x', 'text': '', 'icon': ''},
        {'url': '', 'text': 'порожнє'},
      ],
      'cover': 'https://cdn.hikka.io/uploads/ZEDDY/cover/1.jpg',
      'avatar': 'https://cdn.hikka.io/uploads/ZEDDY/avatar/1.jpg',
      'role': 'moderator',
      'created': 1705190224,
    });
    expect(u.username, 'ZEDDY');
    expect(u.roleLabel, 'Модератор');
    expect(u.links.map((l) => l.label), ['Telegram', 'example.com'], reason: 'порожнє посилання відкинуто, без тексту — домен');
    expect(u.cover, isNotNull);
    expect(const HikkaUser(username: 'x', role: 'user').roleLabel, isNull);
  });

  test('лічильники: улюблене, коментарі, правки, підписки, час перегляду', () {
    final s = HikkaUserStats.fromJson({
      'favourites_count': {'collection': 0, 'character': 10, 'anime': 9, 'manga': 2},
      'comments_count': 741,
      'reviews_count': 2,
      'edits_count': 5552,
    });
    expect([s.favouriteAnime, s.favouriteCharacters, s.comments, s.reviews, s.edits], [9, 10, 741, 2, 5552]);
    final f = HikkaFollowStats.fromJson({'followers': 42, 'following': 60});
    expect([f.followers, f.following], [42, 60]);
    final w = HikkaWatchStats.fromJson({'duration': 215108, 'completed': 488, 'watching': 21, 'planned': 69, 'dropped': 77, 'on_hold': 18});
    expect(w.total, 673);
    expect(HikkaProfileText.watchTime(w.duration), '4 місяці 29 днів', reason: 'як на hikka.io/u/ZEDDY');
    expect(HikkaProfileText.watchTime(0), '0 хвилин');
    expect(HikkaProfileText.watchTime(45), '45 хвилин');
    expect(HikkaProfileText.watchTime(24 * 60 * 3 + 5 * 60 + 7), '3 дні 5 годин');
  });

  test('активність: дні за порядком, від\'ємне відкидається', () {
    final days = HikkaActivityDay.parseList([
      {'timestamp': 1763251200, 'actions': 0},
      {'timestamp': 1763164800, 'actions': 31},
      {'timestamp': 'x', 'actions': 1},
      {'timestamp': 1763337600, 'actions': -3},
    ]);
    expect(days.map((d) => d.actions), [31, 0, 0]);
    expect(days.first.day, DateTime.utc(2025, 11, 15));
    expect(days.first.day.isUtc, isTrue);
  });

  group('історія', () {
    test('серії: одна, кілька, без загальної кількості', () {
      expect(_describe('watch', {'episodes': 11}, {'episodes': 12}), 'Переглянуто епізод 12 з 12');
      expect(_describe('watch', {'episodes': 6}, {'episodes': 9}), 'Переглянуто епізоди 7–9 з 12');
      expect(_describe('watch', {'episodes': 9}, {'episodes': 7}), 'Епізодів переглянуто: 7 з 12');
    });

    test('статус: «Завершено» без зайвих серій, новий запис, «Запис оновлено»', () {
      expect(
        _describe('watch', {'status': 'watching', 'episodes': 9, 'start_date': 1790553600}, {'status': 'completed', 'episodes': 12, 'start_date': null}),
        'Завершено',
      );
      expect(_describe('watch', {'status': 'planned', 'episodes': 0}, {'status': 'planned', 'episodes': 0}), 'Запис оновлено');
      expect(_describe('watch', {'status': 'watching'}, {'status': 'on_hold'}), 'Статус «Відкладено»');
      // A new entry: Hikka sends nulls in "before" and score: 0, which is not "score removed"
      expect(
        _describe('watch', {'score': null, 'status': null, 'episodes': null}, {'score': 0, 'status': 'planned', 'episodes': 0}),
        'Додано до списку «${HikkaWatchStatus.planned.label}»',
      );
      expect(
        _describe('watch', {'score': null, 'status': null, 'episodes': null}, {'score': 0, 'status': 'watching', 'episodes': 2}),
        'Додано до списку «Дивлюсь», переглянуто епізод 2 з 12',
      );
      expect(_describe('watch', {}, {'status': 'watching', 'episodes': 0}, isNew: true), 'Додано до списку «Дивлюсь»');
    });

    test('оцінка, видалення, улюблене, імпорт', () {
      expect(_describe('watch', {'score': 7}, {'score': 9}), 'Оцінка 9');
      expect(_describe('watch', {'score': 7}, {'score': 0}), 'Оцінку прибрано');
      expect(_describe('watch_delete', {}, {}), 'Видалено зі списку');
      expect(_describe('favourite_anime_add', {}, {}), 'Додано до улюблених');
      expect(_describe('favourite_anime_remove', {}, {}), 'Видалено з улюблених');
      expect(_describe('watch_import', {}, {}), 'Список імпортовано');
    });

    test('манґа й ранобе — не про аніме', () {
      final manga = HikkaHistoryEntry.fromJson(_h('read_manga', {'chapters': 1}, {'chapters': 2}, content: {'data_type': 'manga', 'slug': 'm'}));
      expect(manga.isAnime, isFalse);
      expect(manga.anime, isNull);
      final e = HikkaHistoryEntry.fromJson(_h('watch', {}, {}));
      expect(e.isAnime, isTrue);
      expect(e.anime?.slug, 'masamune-kun-no-revenge-r');
      expect(e.time, 1794429900, reason: 'час — останнє оновлення запису');
    });

    test('заголовок дня: «Сьогодні», «Вчора», дата з днем тижня', () {
      final now = DateTime(2026, 11, 14, 4, 30);
      expect(HikkaProfileText.historyDay(DateTime(2026, 11, 14, 1), now), 'Сьогодні');
      expect(HikkaProfileText.historyDay(DateTime(2026, 11, 13, 23), now), 'Вчора');
      expect(HikkaProfileText.historyDay(DateTime(2026, 11, 11, 22, 44), now), '11 листопада, середа');
      expect(HikkaProfileText.historyDay(DateTime(2025, 11, 11, 10), now), '11 листопада 2025, вівторок');
    });
  });

  test('посилання на профіль hikka.io/u/<імʼя> відкривається в застосунку', () {
    final t = HikkaLinkTarget.classify('https://hikka.io/u/ZEDDY');
    expect(t.kind, HikkaLinkKind.user);
    expect(t.slug, 'ZEDDY');
    expect(HikkaLinkTarget.classify('/u/other').kind, HikkaLinkKind.user);
  });

  test('людина: імена без повторів, лічильники, роботи й озвучення', () {
    final p = HikkaPerson.fromJson({
      'slug': 'k-1',
      'name_native': '山田 鐘人',
      'name_ua': 'Ямада Канехіто',
      'name_en': 'Kanehito Yamada',
      'description_ua': 'Мангака.',
      'synonyms': ['Yamada', ''],
      'anime_count': 4,
      'characters_count': 0,
    });
    expect(p.name, 'Ямада Канехіто');
    expect(p.otherNames, ['Kanehito Yamada', '山田 鐘人']);
    expect(p.synonyms, ['Yamada']);
    expect([p.animeCount, p.charactersCount], [4, 0]);
    final w = HikkaPersonAnime.fromJson({
      'anime': {'slug': 'a', 'title_ua': 'Фрірен'},
      'roles': [
        {'name_ua': 'Режисер'},
        {'name_en': 'Composer'},
      ],
    });
    expect(w.rolesLabel, 'Режисер, Composer');
  });

  test('фільтр за студією йде в запит і рахується активним', () {
    const f = HikkaSearchFilters(studios: {'madhouse-b52579'}, studioNames: {'madhouse-b52579': 'Madhouse'});
    expect(f.toBody(allowAdult: false)['studios'], ['madhouse-b52579']);
    expect(f.activeCount, 1);
    expect(f.copyWith(query: 'x').studioNames['madhouse-b52579'], 'Madhouse', reason: 'підпис зберігається при зміні інших умов');
    expect(f.copyWith(studios: <String>{}).toBody(allowAdult: false).containsKey('studios'), isFalse);
  });
}
