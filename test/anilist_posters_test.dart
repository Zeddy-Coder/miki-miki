import 'package:flutter_test/flutter_test.dart';
import 'package:miki_miki/services/anilist_posters.dart';

void main() {
  test('розбір відповіді AniList: MAL-id → extraLarge', () {
    final out = AniListPosters.parse({
      'data': {
        'Page': {
          'media': [
            {'idMal': 5, 'coverImage': {'extraLarge': 'https://s4.anilist.co/a.jpg', 'large': 'https://s4.anilist.co/b.jpg'}},
            {'idMal': 6, 'coverImage': {'large': 'https://s4.anilist.co/c.jpg'}},
            {'idMal': 7, 'coverImage': {}},
          ],
        },
      },
    });
    expect(out, {5: 'https://s4.anilist.co/a.jpg', 6: 'https://s4.anilist.co/c.jpg'});
  });

  test('lookup: збирає запит, повертає адресу, "немає" — порожній рядок', () async {
    final calls = <Object?>[];
    final svc = AniListPosters(
      enabled: true,
      fetch: (m, u, {body, headers}) async {
        calls.add(body);
        return {
          'data': {
            'Page': {
              'media': [
                {'idMal': 1, 'coverImage': {'extraLarge': 'https://s4.anilist.co/x.jpg'}},
              ],
            },
          },
        };
      },
    );
    expect(svc.lookup(1), isNull);
    expect(svc.lookup(2), isNull);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(calls.length, 1, reason: 'обидва id в одному запиті');
    expect(svc.lookup(1), 'https://s4.anilist.co/x.jpg');
    expect(svc.lookup(2), '');
  });
}
