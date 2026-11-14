// Яку озвучку відкриває «Дивитись» без вибору на сторінці: вибір для тайтлу → улюблена команда з інших тайтлів →
// перший варіант, де нумерація збігається з Hikka. Чиста логіка, без UI й мережі.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:miki_miki/models/source_models.dart';
import 'package:miki_miki/services/episode_check.dart';
import 'package:miki_miki/services/sources/ua/mikai_source.dart';
import 'package:miki_miki/services/watch_models.dart';
import 'package:miki_miki/services/watch_store.dart';

SEpisode ep(int n) => SEpisode(url: 'u$n', name: 'Серія $n', number: n.toDouble());
List<SEpisode> eps(int count) => [for (int i = 1; i <= count; i++) ep(i)];

WatchGroup vg(
  String id,
  String label, {
  int count = 12,
  bool sub = false,
  String source = 'mikai',
  List<MikaiTeam> teams = const [],
}) => WatchGroup(id: id, sourceId: source, label: label, episodes: eps(count), isSub: sub, teams: teams);

WatchStore memoryStore() {
  var data = <String, dynamic>{};
  return WatchStore(load: () => data, save: (d) => data = jsonDecode(jsonEncode(d)) as Map<String, dynamic>);
}

const MikaiTeam inari = MikaiTeam(121, 'inari', 'Inari');
const MikaiTeam fanvox = MikaiTeam(2, 'fanvoxua', 'FanVoxUA');
const MikaiTeam glass = MikaiTeam(3, 'glass-moon', 'Glass Moon');

void main() {
  const finished = HikkaEpisodeInfo(released: 12, total: 12, finished: true);
  bool safe(WatchGroup g) => checkEpisodes(g.episodes, finished).syncSafe;

  group('підпис варіанта', () {
    test('вид + назва; у субтитрів «(суб.)» не повторюється', () {
      expect(vg('a', 'Inari', teams: [inari]).fullLabel, 'Озвучення: Inari');
      expect(vg('b', 'Inari (суб.)', sub: true, teams: [inari]).fullLabel, 'Субтитри: Inari');
      expect(vg('c', 'UFDub', source: 'ufdub').fullLabel, 'Озвучення: UFDub');
      // «(суб.)» прибираємо лише наприкінці й лише в субтитрів
      expect(vg('d', 'Команда (суб.) Х', sub: true).fullLabel, 'Субтитри: Команда (суб.) Х');
      expect(vg('e', 'Озвучка (суб.)').fullLabel, 'Озвучення: Озвучка (суб.)');
    });
  });

  group('ознака команди між тайтлами', () {
    test('та сама команда → той самий ключ, хоч би які тайтл і реліз; озвучення й субтитри різні', () {
      final a = vg('mikai|1|t_121:voice', 'Inari', teams: [inari]);
      final b = vg('mikai|99|t_121:voice', 'Inari', teams: [inari], count: 24);
      final s = vg('mikai|1|t_121:sub', 'Inari (суб.)', sub: true, teams: [inari]);
      expect(choiceKeyOf(a), choiceKeyOf(b));
      expect(choiceKeyOf(a), 'v:121');
      expect(choiceKeyOf(s), 's:121');
      expect(choiceKeyOf(a), isNot(choiceKeyOf(s)));
    });

    test('співпраця команд: ключ не залежить від порядку, а склад має значення', () {
      final ab = vg('x', 'Inari & FanVoxUA', teams: [inari, fanvox]);
      final ba = vg('y', 'FanVoxUA & Inari', teams: [fanvox, inari]);
      expect(choiceKeyOf(ab), choiceKeyOf(ba));
      expect(choiceKeyOf(ab), 'v:121+2');
      expect(choiceKeyOf(ab), isNot(choiceKeyOf(vg('z', 'Inari', teams: [inari]))));
    });

    test('без команд (UFDub та ін.): джерело й назва без урахування регістру; команда без id — за slug', () {
      expect(choiceKeyOf(vg('u', 'UFDub', source: 'ufdub')), 'v:ufdub:ufdub');
      expect(choiceKeyOf(vg('u2', 'UFDub', source: 'ufdub')), choiceKeyOf(vg('u3', 'ufdub', source: 'ufdub')));
      expect(choiceKeyOf(vg('t', 'Х', teams: [const MikaiTeam(0, 'some-team', 'Х')])), 'v:some-team');
    });
  });

  group('який варіант відкрити', () {
    final inariV = vg('mikai|1|t_121:voice', 'Inari', teams: [inari]);
    final fanvoxV = vg('mikai|1|t_2:voice', 'FanVoxUA', teams: [fanvox]);
    final glassV = vg('mikai|1|t_3:voice', 'Glass Moon', teams: [glass]);
    final glassS = vg('mikai|1|t_3:sub', 'Glass Moon (суб.)', sub: true, teams: [glass]);
    final merged = vg('mikai|1|t_9:voice', 'Склеєні', count: 24, teams: [const MikaiTeam(9, 'sk', 'Склеєні')]);

    test('нічого не обирали: перший варіант (у списку озвучення йдуть першими)', () {
      expect(pickGroup([inariV, fanvoxV, glassS]).id, inariV.id);
    });

    test('вибір для цього тайтлу найсильніший, навіть якщо нумерація не збігається', () {
      final picked = pickGroup([inariV, merged], preferredId: merged.id, favorites: [choiceKeyOf(inariV)], safe: safe);
      expect(picked.id, merged.id);
    });

    test('вибір із цього тайтлу, якого вже немає в списку, ігнорується', () {
      expect(pickGroup([inariV, fanvoxV], preferredId: 'mikai|1|t_404:voice').id, inariV.id);
    });

    test('улюблена команда з інших тайтлів: найновіший вибір перший', () {
      final favs = [choiceKeyOf(glassV), choiceKeyOf(fanvoxV)]; // Glass Moon обрано пізніше
      expect(pickGroup([inariV, fanvoxV, glassV], favorites: favs, safe: safe).id, glassV.id);
      // а якщо її тут немає — наступна за давністю
      expect(pickGroup([inariV, fanvoxV], favorites: favs, safe: safe).id, fanvoxV.id);
    });

    test('улюблені озвучення й субтитри не плутаються між собою', () {
      expect(pickGroup([glassS, inariV, glassV], favorites: [choiceKeyOf(glassV)], safe: safe).id, glassV.id);
      expect(pickGroup([inariV, glassV, glassS], favorites: [choiceKeyOf(glassS)], safe: safe).id, glassS.id);
    });

    test('улюблений варіант із розбіжною нумерацією пропускається: йдемо до першого безпечного', () {
      final mergedFav = vg('mikai|1|t_121:voice', 'Inari', count: 24, teams: [inari]); // у цьому тайтлі склеєна
      expect(pickGroup([mergedFav, fanvoxV, glassV], favorites: [choiceKeyOf(mergedFav)], safe: safe).id, fanvoxV.id);
    });

    test('перший безпечний варіант випереджає склеєний навіть на першому місці', () {
      expect(pickGroup([merged, inariV, fanvoxV], safe: safe).id, inariV.id);
    });

    test('усі розбіжні: беремо перший, а застереження покаже сторінка', () {
      final other = vg('mikai|1|t_8:voice', 'Інші', count: 30);
      expect(pickGroup([merged, other], safe: safe).id, merged.id);
    });
  });

  group('улюблена команда в сховищі', () {
    test('новий вибір іде першим, повтор переміщується вгору, зберігається не більше 8', () {
      final store = memoryStore();
      expect(store.favoriteChoices, isEmpty);
      store.setFavoriteChoice('v:1');
      store.setFavoriteChoice('v:2');
      store.setFavoriteChoice('s:3');
      expect(store.favoriteChoices, ['s:3', 'v:2', 'v:1']);
      store.setFavoriteChoice('v:1');
      expect(store.favoriteChoices, ['v:1', 's:3', 'v:2']);
      for (int i = 10; i < 20; i++) {
        store.setFavoriteChoice('v:$i');
      }
      expect(store.favoriteChoices.length, 8);
      expect(store.favoriteChoices.first, 'v:19');
      expect(store.favoriteChoices, isNot(contains('v:1')));
    });

    test('переживає перезапуск і не торкається історії переглянутого', () {
      var data = <String, dynamic>{};
      WatchStore open() => WatchStore(load: () => data, save: (d) => data = jsonDecode(jsonEncode(d)) as Map<String, dynamic>);
      final first = open();
      first.setWatched('hikka:x', '1', true);
      first.setPreferredGroup('hikka:x', 'mikai|1|t_2:voice');
      first.setFavoriteChoice('v:2');

      final second = open();
      expect(second.favoriteChoices, ['v:2']);
      expect(second.preferredGroup('hikka:x'), 'mikai|1|t_2:voice');
      expect(second.watched('hikka:x'), {'1'});
    });
  });

  group('звідки продовжити з урахуванням Hikka', () {
    final keys = ['1', '2', '3', '4', '5'];

    test('історії в застосунку немає, на Hikka відмічено 3 серії — пропонується четверта', () {
      final p = continuePoint(keys, <String>{}, null, hikkaEpisodes: 3);
      expect(p.index, 3);
      expect(p.started, isTrue, reason: 'підпис «Продовжити»');
      expect(p.allWatched, isFalse);
    });

    test('без прогресу Hikka поведінка не змінилась', () {
      expect(continuePoint(keys, <String>{}, null).index, 0);
      expect(continuePoint(keys, {'1', '2'}, null).index, 2);
    });

    test('на Hikka всі серії — «Дивитись знову»', () {
      expect(continuePoint(keys, <String>{}, null, hikkaEpisodes: 5).allWatched, isTrue);
      expect(continuePoint(keys, <String>{}, null, hikkaEpisodes: 9).allWatched, isTrue);
    });

    test('Hikka попереду за локальну історію: беремо наступну після Hikka', () {
      // востаннє відкривали 2-гу й переглянули, але на Hikka вже 4
      expect(continuePoint(keys, {'1', '2'}, '2', hikkaEpisodes: 4).index, 4);
    });

    test('локальна історія попереду за Hikka: лишається локальна', () {
      expect(continuePoint(keys, {'1', '2', '3', '4'}, '4', hikkaEpisodes: 1).index, 4);
    });
  });
}
