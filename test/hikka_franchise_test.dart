import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:miki_miki/models/hikka_models.dart';
import 'package:miki_miki/services/hikka_franchise.dart';

int ts(int year, [int month = 1]) => DateTime.utc(year, month, 1).millisecondsSinceEpoch ~/ 1000;

HikkaAnime anime(String slug, {int? start, int? year}) => HikkaAnime(slug: slug, titleUa: slug.toUpperCase(), startDate: start, year: year);

HikkaRelation rel(String slug, String related, String type, {String from = 'anime', String to = 'anime'}) =>
    HikkaRelation(slug: slug, relatedSlug: related, contentType: from, relatedContentType: to, type: type);

/// Фікстура з тестів фронтенду hikka.io: a1 → a2 → a3 (сиквели), s1 — побічна історія a1,
/// s2 — сиквел s1, r1 — рекап a2
HikkaFranchiseData fixture() => HikkaFranchiseData(
      anime: [
        anime('a2', start: ts(2012)),
        anime('a1', start: ts(2010)),
        anime('r1', start: ts(2012, 6)),
        anime('s2', start: ts(2013)),
        anime('a3', start: ts(2014)),
        anime('s1', start: ts(2011)),
      ],
      relations: [
        rel('a1', 'a2', 'sequel'),
        rel('a2', 'a3', 'sequel'),
        rel('a1', 's1', 'side_story'),
        rel('s1', 's2', 'sequel'),
        rel('a2', 'r1', 'summary'),
      ],
    );

List<String> ids(Iterable<FranchiseNode> nodes) => [for (final n in nodes) n.id];

void main() {
  group('Франшиза: головна лінія', () {
    test('ланцюг сиквелів і підпис «N з M»', () {
      final m = FranchiseModel.build(fixture(), 'a2')!;
      expect(ids(m.chain), ['a1', 'a2', 'a3']);
      expect(m.current.chainIndex, 1);
      expect(m.relationText(m.current), 'Основна історія, 2 з 3');
      expect(m.relationText(m.byId['a1']!), 'Основна історія, 1 з 3');
      expect(m.relationText(m.byId['a3']!), 'Основна історія, 3 з 3');
    });

    test('хронологія за датою виходу', () {
      final m = FranchiseModel.build(fixture(), 'a2')!;
      expect(ids(m.nodes), ['a1', 's1', 'a2', 'r1', 's2', 'a3']);
      expect(m.groupByYear().map((g) => g.$1), ['2010', '2011', '2012', '2013', '2014']);
      expect(ids(m.groupByYear()[2].$2), ['a2', 'r1']);
    });

    test('прямі зв’язки: приквел, сиквел, рекап — у порядку сайту', () {
      final m = FranchiseModel.build(fixture(), 'a2')!;
      expect([for (final d in m.direct) '${d.label}:${d.node.id}'], ['Приквел:a1', 'Сиквел:a3', 'Рекап:r1']);
    });

    test('побічна історія та її сиквел лишаються в групі побічних', () {
      final m = FranchiseModel.build(fixture(), 'a2')!;
      final s1 = m.byId['s1']!;
      final s2 = m.byId['s2']!;
      expect((s1.group, s1.relation?.label, s1.relation?.targetId), (FranchiseGroup.side, 'Побічна історія', 'a1'));
      expect((s2.group, s2.relation?.label, s2.relation?.targetId), (FranchiseGroup.side, 'Сиквел', 's1'));
      expect(m.relationText(s2), 'Сиквел');
      expect(s1.chainIndex, isNull);
      expect(s1.onMainLine, isFalse);
    });

    test('рекап: група, підпис і зворотний зв’язок', () {
      final m = FranchiseModel.build(fixture(), 'a2')!;
      final r1 = m.byId['r1']!;
      expect((r1.group, r1.relation?.label, r1.relation?.targetId), (FranchiseGroup.summary, 'Рекап', 'a2'));
      // зв'язки самого рекапу: що він є для a2 — «Повна історія» (a2) стосовно r1
      expect([for (final d in m.relations['r1']!) '${d.label}:${d.node.id}'], ['Повна історія:a2']);
    });

    test('поточний — рекап поза головною лінією: хребет береться з найдовшого ланцюга', () {
      final m = FranchiseModel.build(fixture(), 'r1')!;
      expect(ids(m.chain), ['a1', 'a2', 'a3']);
      expect(m.current.chainIndex, isNull);
      expect(m.current.relation?.label, 'Рекап');
      expect(m.relationText(m.current), 'Рекап');
      expect([for (final d in m.direct) d.label], ['Повна історія']);
    });

    test('поточний — сиквел побічної історії: основна лінія — його власний ланцюг', () {
      final m = FranchiseModel.build(fixture(), 's2')!;
      // власний ланцюг s1–s2 коротший за a1–a3, але s2 має сиквел-зв'язок, тож основна лінія — її власна
      expect(ids(m.chain), ['s1', 's2']);
      expect(m.current.chainIndex, 1);
      expect(m.relationText(m.current), 'Основна історія, 2 з 2');
    });

    test('унікальний тайтл без зв’язків', () {
      final m = FranchiseModel.build(HikkaFranchiseData(anime: [anime('solo', start: ts(2020))], relations: const []), 'solo')!;
      expect(ids(m.chain), ['solo']);
      expect(m.direct, isEmpty);
      expect(m.relationText(m.current), 'Основна історія');
    });

    test('невідомий slug і порожня відповідь', () {
      expect(FranchiseModel.build(fixture(), 'nope'), isNull);
      expect(FranchiseModel.build(const HikkaFranchiseData(anime: [], relations: []), 'a1'), isNull);
    });
  });

  group('Франшиза: крайні випадки', () {
    test('манґа та ранобе у відповіді ігноруються', () {
      final data = HikkaFranchiseData(
        anime: [anime('a1', start: ts(2010)), anime('a2', start: ts(2012))],
        relations: [
          rel('a1', 'a2', 'sequel'),
          rel('a1', 'manga-1', 'adaptation', to: 'manga'),
          rel('novel-1', 'a2', 'adaptation', from: 'novel'),
          rel('a2', 'ghost', 'sequel'), // тайтл, якого немає у відповіді
        ],
      );
      final m = FranchiseModel.build(data, 'a1')!;
      expect(ids(m.chain), ['a1', 'a2']);
      expect(m.edges, hasLength(1));
      expect([for (final d in m.direct) d.node.id], ['a2']);
    });

    test('альтернативний сетинг зводиться до альтернативної версії', () {
      final data = HikkaFranchiseData(
        anime: [anime('a1', start: ts(2010)), anime('x1', start: ts(2011))],
        relations: [rel('a1', 'x1', 'alternative_setting')],
      );
      final m = FranchiseModel.build(data, 'a1')!;
      expect(m.edges.single.type, 'alternative_version');
      final x1 = m.byId['x1']!;
      expect((x1.group, x1.relation?.label), (FranchiseGroup.alternative, 'Альтернативний сетинг'));
    });

    test('спіноф і оригінал', () {
      final data = HikkaFranchiseData(
        anime: [anime('a1', start: ts(2010)), anime('sp', start: ts(2012))],
        relations: [rel('a1', 'sp', 'spin_off')],
      );
      final m = FranchiseModel.build(data, 'a1')!;
      expect((m.byId['sp']!.group, m.byId['sp']!.relation?.label), (FranchiseGroup.spinOff, 'Спіноф'));
      expect([for (final d in m.direct) d.label], ['Спіноф']);
      expect([for (final d in FranchiseModel.build(data, 'sp')!.direct) d.label], ['Оригінал']);
    });

    test('тайтли без дати йдуть наприкінці, порядок вхідних даних зберігається', () {
      final data = HikkaFranchiseData(
        anime: [anime('u3'), anime('a1', start: ts(2010)), anime('u1'), anime('u2'), anime('a2', year: 2015)],
        relations: [rel('a1', 'a2', 'sequel')],
      );
      final m = FranchiseModel.build(data, 'a1')!;
      expect(ids(m.nodes), ['a1', 'a2', 'u3', 'u1', 'u2']); // стабільне сортування
      expect(m.groupByYear().last.$1, 'Дата невідома');
      expect(m.groupByYear().map((g) => g.$1).toList().sublist(0, 2), ['2010', '2015']);
    });

    test('цикл у зв’язках не підвішує побудову', () {
      final data = HikkaFranchiseData(
        anime: [anime('a', start: ts(2010)), anime('b', start: ts(2011)), anime('c', start: ts(2012))],
        relations: [rel('a', 'b', 'sequel'), rel('b', 'c', 'sequel'), rel('c', 'a', 'sequel')],
      );
      final m = FranchiseModel.build(data, 'b')!;
      expect(m.chain.length, 3);
      expect(ids(m.chain).toSet(), {'a', 'b', 'c'});
    });

    test('дублікати зв’язків не повторюються в прямих', () {
      final data = HikkaFranchiseData(
        anime: [anime('a1', start: ts(2010)), anime('a2', start: ts(2012))],
        relations: [rel('a1', 'a2', 'sequel'), rel('a1', 'a2', 'sequel')],
      );
      final m = FranchiseModel.build(data, 'a1')!;
      expect(m.direct, hasLength(1));
    });

    test('злиття двох гілок: обидва приквели ведуть до спільного сиквела', () {
      final data = HikkaFranchiseData(
        anime: [anime('p1', start: ts(2010)), anime('p2', start: ts(2011)), anime('end', start: ts(2013))],
        relations: [rel('p1', 'end', 'sequel'), rel('p2', 'end', 'sequel')],
      );
      final m = FranchiseModel.build(data, 'end')!;
      expect(ids(m.chain), ['p1', 'p2', 'end']);
    });
  });

  test('справжня франшиза «Фрірен»: 4 аніме, манґа відкинута', () {
    final json = jsonDecode(File('test/data/hikka_related_franchise.json').readAsStringSync());
    final data = HikkaFranchiseData.fromJson(json);
    expect(data.anime.length, greaterThanOrEqualTo(3));
    for (final a in data.anime) {
      final m = FranchiseModel.build(data, a.slug)!;
      expect(m.nodes.length, data.anime.length);
      expect(m.chain, isNotEmpty);
      expect(m.edges.every((e) => m.byId.containsKey(e.a) && m.byId.containsKey(e.b)), isTrue);
      expect(m.relationText(m.current), isNotEmpty);
    }
  });
}
