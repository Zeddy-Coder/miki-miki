/// Моделі «Дивитись»: що знайдено для аніме (озвучки/субтитри з серіями) і черга серій для плеєра.
/// Чиста Dart-логіка без Flutter.
library;

import '../models/source_models.dart';
import 'sources/anime_source.dart';
import 'sources/ua/mikai_source.dart';

/// Ключ серії для прогресу: «3», «3.5», «s2e5»; без номера — порядковий («i7»).
String episodeKey(SEpisode e, int index) {
  final n = e.number;
  final num = n == null ? 'i${index + 1}' : (n == n.roundToDouble() ? '${n.toInt()}' : '$n');
  final s = e.season;
  return s == null ? num : 's${s}e$num';
}

/// Номер серії для кнопок і списків: «3», «3.5»; без номера — порядковий
String episodeLabel(SEpisode e, int index) {
  final n = e.number;
  if (n == null) return '${index + 1}';
  return n == n.roundToDouble() ? '${n.toInt()}' : '$n';
}

/// Один варіант перегляду: озвучка чи субтитри конкретної команди (або озвучка з іншого сайту)
class WatchGroup {
  /// Стабільний ідентифікатор: `джерело|аніме|реліз`
  final String id;
  final String sourceId;
  final String label;
  final bool isSub;

  /// Команди (лише Mikai): аватарки й сторінки з описом та посиланнями
  final List<MikaiTeam> teams;

  /// Серії в порядку перегляду
  final List<SEpisode> episodes;

  /// Коли варіант востаннє оновлювали (є не в кожного джерела; Mikai його віддає)
  final DateTime? updatedAt;

  const WatchGroup({
    required this.id,
    required this.sourceId,
    required this.label,
    required this.episodes,
    this.isSub = false,
    this.teams = const [],
    this.updatedAt,
  });

  /// Назва команди без позначки «(суб.)» — вид показують іконкою
  String get teamLabel => isSub ? label.replaceAll(RegExp(r'\s*\(суб\.\)\s*$'), '') : label;

  String get kindLabel => isSub ? 'Субтитри' : 'Озвучення';

  /// Підпис із видом: «Озвучення: Inari» / «Субтитри: Inari». «(суб.)» з назви прибирається, бо вид уже названо
  String get fullLabel => '$kindLabel: ${isSub ? label.replaceAll(RegExp(r'\s*\(суб\.\)\s*$'), '') : label}';

  /// Номер останньої серії, якщо відомий
  double? get lastNumber {
    double? best;
    for (final e in episodes) {
      final n = e.number;
      if (n != null && (best == null || n > best)) best = n;
    }
    return best;
  }
}

/// Стійка ознака варіанта поза межами тайтлу: «озвучка / субтитри» + команда. За нею запамʼятовується
/// свідомий вибір людини (`WatchStore.favoriteChoice`), щоб у наступних тайтлах відкривати знайому озвучку.
String choiceKeyOf(WatchGroup g) {
  final who = g.teams.isNotEmpty
      ? ([for (final t in g.teams) t.id > 0 ? '${t.id}' : t.slug]..sort()).join('+')
      : '${g.sourceId}:${g.label.toLowerCase()}';
  return '${g.isSub ? 's' : 'v'}:$who';
}

/// Який варіант відкрити за кнопкою «Дивитись», коли людина не обирала його на сторінці:
///  1. той, що вона обрала (або дивилась) для цього тайтлу — [preferredId];
///  2. той, що вона свідомо обирала в інших тайтлах, — [favorites] (за [choiceKeyOf], найновіші першими), якщо він [safe];
///  3. перший [safe] варіант (озвучення йдуть перед субтитрами, де серій більше — вище);
///  4. інакше перший. [safe] — «нумерація збігається з Hikka» (не `mismatch`).
WatchGroup pickGroup(
  List<WatchGroup> groups, {
  String? preferredId,
  List<String> favorites = const [],
  bool Function(WatchGroup g)? safe,
}) {
  assert(groups.isNotEmpty);
  bool ok(WatchGroup g) => safe == null || safe(g);
  if (preferredId != null) {
    for (final g in groups) {
      if (g.id == preferredId) return g;
    }
  }
  for (final fav in favorites) {
    for (final g in groups) {
      if (choiceKeyOf(g) == fav && ok(g)) return g;
    }
  }
  for (final g in groups) {
    if (ok(g)) return g;
  }
  return groups.first;
}

/// Що знайшло одне джерело для аніме
class WatchOffer {
  final AnimeSource source;
  final SAnime anime;
  final List<WatchGroup> groups;

  const WatchOffer({required this.source, required this.anime, required this.groups});

  String get webUrl => source.animeWebUrl(anime);
}

/// Підсумок для сторінки аніме: пропозиції джерел + ліцензійний стан
class WatchTitle {
  /// Ключ для прогресу: `hikka:<slug>` або `<джерело>:<адреса>`
  final String animeKey;
  final List<WatchOffer> offers;

  /// Тайтл ліцензований в Україні (за даними Mikai)
  final bool licensed;
  final MikaiLicense? license;

  /// Помилки джерел: id джерела → повідомлення для користувача
  final Map<String, String> errors;

  const WatchTitle({
    required this.animeKey,
    required this.offers,
    this.licensed = false,
    this.license,
    this.errors = const {},
  });

  List<WatchGroup> get groups => [for (final o in offers) ...o.groups];

  bool get isEmpty => groups.isEmpty;

  WatchOffer? offerOf(String sourceId) {
    for (final o in offers) {
      if (o.source.id == sourceId) return o;
    }
    return null;
  }

  WatchGroup? groupById(String id) {
    for (final g in groups) {
      if (g.id == id) return g;
    }
    return null;
  }

  WatchOffer? offerOfGroup(WatchGroup g) => offerOf(g.sourceId);
}

/// Серія в черзі плеєра
class RemoteEntry {
  /// Ключ позиції та «переглянуто»: один на серію, незалежно від озвучки
  final String key;
  final String epKey;
  final String title;
  final String sourceId;
  final SEpisode episode;
  final String groupId;

  const RemoteEntry({
    required this.key,
    required this.epKey,
    required this.title,
    required this.sourceId,
    required this.episode,
    required this.groupId,
  });
}

/// Ключі серій варіанта. Однакові номери (злиті частини) не повинні ділити позначки й позицію,
/// тому повтор отримує суфікс «~2», «~3» …
List<String> episodeKeysOf(WatchGroup group) {
  final out = <String>[];
  final used = <String>{};
  for (int i = 0; i < group.episodes.length; i++) {
    var k = episodeKey(group.episodes[i], i);
    if (!used.add(k)) {
      var n = 2;
      while (!used.add('$k~$n')) {
        n++;
      }
      k = '$k~$n';
    }
    out.add(k);
  }
  return out;
}

/// Звідки продовжити перегляд варіанта
class ContinuePoint {
  /// Номер у списку серій варіанта
  final int index;
  final String epKey;

  /// Є історія (відкривали чи дивились раніше): підпис «Продовжити», а не «Дивитись»
  final bool started;

  /// Усе переглянуто: підпис «Дивитись знову»
  final bool allWatched;

  const ContinuePoint(this.index, this.epKey, {this.started = false, this.allWatched = false});
}

/// Яку серію запропонувати: останню відкриту (якщо вона вже переглянута — наступну), інакше першу непереглянуту.
/// [keys] — ключі серій варіанта ([episodeKeysOf]).
ContinuePoint continuePoint(List<String> keys, Set<String> watched, String? lastKey) {
  if (keys.isEmpty) return const ContinuePoint(0, '');
  final li = lastKey == null ? -1 : keys.indexOf(lastKey);
  if (li >= 0) {
    if (watched.contains(keys[li]) && li + 1 < keys.length) return ContinuePoint(li + 1, keys[li + 1], started: true);
    return ContinuePoint(li, keys[li], started: true);
  }
  final fi = keys.indexWhere((k) => !watched.contains(k));
  if (fi >= 0) return ContinuePoint(fi, keys[fi], started: watched.any(keys.contains));
  return ContinuePoint(0, keys.first, started: true, allWatched: true);
}

/// Черга серій одного аніме в одній озвучці
class RemoteSession {
  final String animeKey;
  final String animeTitle;
  final String? poster;
  final String groupLabel;
  final List<RemoteEntry> entries;

  const RemoteSession({
    required this.animeKey,
    required this.animeTitle,
    required this.entries,
    this.poster,
    this.groupLabel = '',
  });

  /// Черга з озвучки: усі її серії, заголовки «Назва — Серія N»
  factory RemoteSession.fromGroup({
    required String animeKey,
    required String animeTitle,
    required WatchGroup group,
    String? poster,
  }) {
    final entries = <RemoteEntry>[];
    final keys = episodeKeysOf(group);
    for (int i = 0; i < group.episodes.length; i++) {
      final e = group.episodes[i];
      final k = keys[i];
      entries.add(RemoteEntry(
        key: '$animeKey#$k',
        epKey: k,
        title: e.name.isEmpty ? 'Серія ${i + 1}' : e.name,
        sourceId: group.sourceId,
        episode: e,
        groupId: group.id,
      ));
    }
    return RemoteSession(animeKey: animeKey, animeTitle: animeTitle, entries: entries, poster: poster, groupLabel: group.label);
  }

  int indexOfKey(String epKey) => entries.indexWhere((e) => e.epKey == epKey);

  /// Назва для екрана плеєра: «Назва · Серія 3»
  String displayTitle(int index) {
    final t = entries[index].title;
    return animeTitle.isEmpty ? t : '$animeTitle · $t';
  }
}
