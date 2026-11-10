import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:miki_miki/models/hikka_models.dart';
import 'package:miki_miki/services/hikka_api.dart';

import 'support/hikka_fakes.dart';

void main() {
  group('Колекції: моделі', () {
    test('список: назва, автор, лічильники й кілька записів для мозаїки', () {
      final list = HikkaPage.parse(sample('collections_list.json'), HikkaCollection.fromJson);
      expect(list.items, isNotEmpty);
      final c = list.items.first;
      expect(c.reference, isNotEmpty);
      expect(c.title, isNotEmpty);
      expect(c.author.username, isNotEmpty);
      expect(c.entries, greaterThan(0));
      expect(c.items.length, lessThanOrEqualTo(c.entries));
      expect(c.items.first.anime.slug, isNotEmpty);
      expect(c.items.first.anime.image, isNotNull);
      expect(c.contentType, 'anime');
    });

    test('сторінка колекції: усі записи за порядком автора', () {
      final c = HikkaCollection.fromJson(sampleMap('collection_detail.json'));
      expect(c.items.length, 12);
      final orders = [for (final e in c.items) e.order];
      expect([...orders]..sort(), orders);
      expect(c.createdAt.year, greaterThanOrEqualTo(2024));
      expect(c.description, isNotNull);
    });

    test('розділи автора: порядок як у labels_order, записи без мітки — першими', () {
      final src = sampleMap('collection_detail.json');
      final raw = (src['collection'] as List).cast<Map<String, dynamic>>();
      final json = {
        ...src,
        'labels_order': ['Друга група', 'Перша група'],
        'collection': [
          for (var i = 0; i < raw.length; i++) {...raw[i], 'label': i < 3 ? 'Перша група' : (i < 6 ? 'Друга група' : null)},
        ],
      };
      final c = HikkaCollection.fromJson(json);
      final g = c.grouped(allowAdult: true);
      expect(g.map((e) => e.$1), [null, 'Друга група', 'Перша група']);
      expect(g[0].$2.length, 6);
      expect(g[1].$2.length, 3);
      expect(g[2].$2.length, 3);
    });

    test('без міток усе в одній групі', () {
      final c = HikkaCollection.fromJson(sampleMap('collection_detail.json'));
      final g = c.grouped(allowAdult: true);
      expect(g.length, 1);
      expect(g.single.$1, isNull);
      expect(g.single.$2.length, 12);
    });

    test('записи 18+ ховаються, поки показ не дозволено', () {
      final src = sampleMap('collection_detail.json');
      final raw = (src['collection'] as List).cast<Map<String, dynamic>>();
      final json = {
        ...src,
        'collection': [
          for (var i = 0; i < raw.length; i++)
            if (i == 1) {...raw[i], 'content': {...(raw[i]['content'] as Map<String, dynamic>), 'rating': 'rx'}} else raw[i],
        ],
      };
      final c = HikkaCollection.fromJson(json);
      expect(c.visibleItems(allowAdult: true).length, 12);
      expect(c.visibleItems(allowAdult: false).length, 11);
    });

    test('колекції не про аніме не дають записів-аніме', () {
      final json = {...sampleMap('collection_detail.json'), 'content_type': 'character'};
      expect(HikkaCollection.fromJson(json).items, isEmpty);
    });

    test('порожня чи зіпсована відповідь не падає', () {
      final c = HikkaCollection.fromJson(const {});
      expect(c.reference, '');
      expect(c.title, 'Без назви');
      expect(c.items, isEmpty);
      expect(c.author.username, '');
    });
  });

  group('Статті: моделі', () {
    test('список: категорія, автор, лічильники, короткий опис', () {
      final list = HikkaPage.parse(sample('articles_list.json'), HikkaArticle.fromJson);
      expect(list.items, isNotEmpty);
      final a = list.items.first;
      expect(a.slug, isNotEmpty);
      expect(a.title, isNotEmpty);
      expect(a.categoryLabel, 'Новини');
      expect(a.author.username, isNotEmpty);
      expect(a.snippet(), isNotEmpty);
      expect(a.snippet(maxChars: 40).length, lessThanOrEqualTo(41));
    });

    test('стаття: блоки документа з розміткою й посиланнями', () {
      final a = HikkaArticle.fromJson(sampleMap('article_detail.json'));
      final types = <String>{};
      void walk(List<SlateNode> nodes) {
        for (final n in nodes) {
          if (!n.isText) types.add(n.type);
          walk(n.children);
        }
      }

      walk(a.document);
      expect(types, containsAll(['p', 'h3', 'ul', 'li', 'lic', 'blockquote', 'spoiler', 'image']));
      expect(a.document.first.plainText, isNotEmpty);
    });

    test('Slate: жирний, курсив, закреслений, код, посилання, картинка', () {
      final nodes = SlateNode.parseList(jsonDecode('''[
        {"type":"p","children":[
          {"text":"звичайний "},
          {"text":"жирний","bold":true},
          {"text":"курсив","italic":true},
          {"text":"закреслений","strikethrough":true},
          {"text":"код","code":true},
          {"type":"a","url":"https://hikka.io/anime/x","target":"_blank","children":[{"text":"посилання"}]}
        ]},
        {"type":"image","url":"https://cdn.hikka.io/a.jpg","children":[{"text":""}]}
      ]'''));
      final p = nodes[0];
      expect(p.plainText, 'звичайний жирнийкурсивзакресленийкодпосилання');
      expect(p.children[1].bold, isTrue);
      expect(p.children[2].italic, isTrue);
      expect(p.children[3].strike, isTrue);
      expect(p.children[4].code, isTrue);
      expect(p.children[5].url, 'https://hikka.io/anime/x');
      expect(nodes[1].firstImage, 'https://cdn.hikka.io/a.jpg');
      expect(p.firstImage, isNull);
    });

    test('обкладинка статті — перша картинка, а абзаци без картинок її не дають', () {
      final withImg = HikkaArticle.fromJson({
        'slug': 's',
        'title': 'T',
        'preview': [
          {'type': 'p', 'children': [{'text': 'текст'}]},
          {'type': 'image_group', 'children': [{'type': 'image', 'url': 'https://cdn.hikka.io/i.jpg', 'children': [{'text': ''}]}]},
        ],
      });
      expect(withImg.coverImage, 'https://cdn.hikka.io/i.jpg');
      expect(withImg.snippet(), 'текст');
      final none = HikkaArticle.fromJson({'slug': 's', 'title': 'T'});
      expect(none.coverImage, isNull);
      expect(none.snippet(), '');
    });
  });

  group('HikkaApi: колекції та статті', () {
    late FakeHikka server;
    late HikkaApi api;

    setUp(() {
      server = FakeHikka();
      api = HikkaApi(sender: server.call, retryDelay: Duration.zero);
    });

    test('колекції: запит, розбір, кеш', () async {
      final p = await api.collections();
      expect(p.items, isNotEmpty);
      final req = server.log.single;
      expect(req.method, 'POST');
      expect(req.url.path, '/collections');
      expect(jsonDecode(req.body!)['content_type'], 'anime');
      expect(req.url.queryParameters['size'], '20');
      await api.collections();
      expect(api.networkCalls, 1);
    });

    test('колекції «Нові» просять сортування за датою', () async {
      await api.collections(sort: 'new');
      expect(jsonDecode(server.log.single.body!)['sort'], ['created:desc']);
    });

    test('колекції 18+ приховані, доки показ не ввімкнено', () async {
      final nsfwApi = HikkaApi(
        retryDelay: Duration.zero,
        sender: (r) async {
          final list = (sampleMap('collections_list.json')['list'] as List).cast<Map<String, dynamic>>();
          final body = {
            'pagination': {'total': 2, 'pages': 1, 'page': 1},
            'list': [
              list[0],
              {...list[1], 'nsfw': true},
            ],
          };
          return HikkaResponse(200, jsonEncode(body));
        },
      );
      expect((await nsfwApi.collections()).items.length, 1);
      nsfwApi.clearCache();
      expect((await nsfwApi.collections(allowAdult: true)).items.length, 2);
    });

    test('колекція за посиланням: усі записи', () async {
      final ref = (sampleMap('collection_detail.json'))['reference'] as String;
      final c = await api.collection(ref);
      expect(c.items.length, 12);
      expect(server.log.single.url.path, '/collections/$ref');
    });

    test('колекції немає — «не знайдено»', () async {
      await expectLater(
        api.collection('нема-такої'),
        throwsA(isA<HikkaException>().having((e) => e.kind, 'kind', HikkaErrorKind.notFound)),
      );
    });

    test('статті: категорія й сортування потрапляють у тіло запиту', () async {
      final p = await api.articles(category: 'news', sort: 'top');
      expect(p.items, isNotEmpty);
      final body = jsonDecode(server.log.single.body!) as Map<String, dynamic>;
      expect(body['categories'], ['news']);
      expect(body['sort'], ['vote_score:desc']);
      await api.articles(category: 'news', sort: 'top');
      expect(api.networkCalls, 1, reason: 'повторний запит бере кеш');
    });

    test('статті без категорії: за замовчуванням найновіші', () async {
      await api.articles();
      final body = jsonDecode(server.log.single.body!) as Map<String, dynamic>;
      expect(body.containsKey('categories'), isFalse);
      expect(body['sort'], ['created:desc']);
    });

    test('повний текст статті', () async {
      final slug = (sampleMap('article_detail.json'))['slug'] as String;
      final a = await api.article(slug);
      expect(a.document, isNotEmpty);
      expect(a.title, isNotEmpty);
    });

    test('коротка мережева помилка не ламає колекції — повтор', () async {
      server.failNext = 1;
      final p = await api.collections();
      expect(p.items, isNotEmpty);
      expect(server.log.length, 2);
    });
  });
}
