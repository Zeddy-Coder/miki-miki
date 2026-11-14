/// Моделі «Дивитись»: що знайдено для аніме (озвучки/субтитри з серіями) і черга серій для плеєра.
/// Чиста Dart-логіка без Flutter.
library;

import '../models/source_models.dart';
import 'sources/anime_source.dart';
import 'episode_check.dart' show looksLikeExtra;
import 'storage_service.dart';
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

  /// Чи є у варіанті серія з цілим номером [n] (без номерів — за порядком). Важливо саме за номером: в озвучці
  /// «10 з 19» можуть бути, наприклад, серії 3–12, і тоді 12-ту в ній дивитись можна
  bool hasEpisode(int n) {
    for (var i = 0; i < episodes.length; i++) {
      final v = episodes[i].number;
      if (v == null ? i + 1 == n : v == n.toDouble()) return true;
    }
    return false;
  }

  /// Чи є у варіанті серія з номером більшим за [n]
  bool hasEpisodeAfter(int n) {
    for (var i = 0; i < episodes.length; i++) {
      final v = episodes[i].number;
      if (v == null ? i + 1 > n : v > n) return true;
    }
    return false;
  }

  /// Діапазони цілих номерів серій, що є у варіанті: [(1,5),(7,19)]. Без номерів — за порядком 1…N
  /// Зайві серії (OVA / спецвипуск за назвою) і номери більші за [limit] (кількість серій на Hikka) не рахуються
  List<(int, int)> ranges({int? limit}) {
    final nums = <int>{};
    for (var i = 0; i < episodes.length; i++) {
      if (looksLikeExtra(episodes[i].name)) continue;
      final v = episodes[i].number;
      if (v == null) {
        nums.add(i + 1);
      } else if (v == v.roundToDouble() && v >= 0) {
        nums.add(v.toInt());
      }
    }
    final sorted = [for (final n in nums) if (limit == null || limit <= 0 || n <= limit) n]..sort();
    final out = <(int, int)>[];
    for (final n in sorted) {
      if (out.isNotEmpty && out.last.$2 == n - 1) {
        out[out.length - 1] = (out.last.$1, n);
      } else {
        out.add((n, n));
      }
    }
    return out;
  }

  /// Які серії охоплює варіант: «1–10», «10–19», «1–5, 7–19»
  String get coverage {
    final r = ranges();
    if (r.isEmpty) return '0';
    return r.map((x) => x.$1 == x.$2 ? '${x.$1}' : '${x.$1}–${x.$2}').join(', ');
  }

  /// Варіант не з першої серії або з пропусками — у порядку й виборі стоїть нижче за повні
  bool get isPartial {
    final r = ranges();
    return r.isEmpty || r.length > 1 || r.first.$1 > 1;
  }

  /// Неповний варіант відносно [maxLast] — найбільшого номера серії серед усіх варіантів: не з 1-ї серії,
  /// з пропусками або без останніх серій, які є в інших
  bool isIncomplete(int maxLast) {
    final r = ranges(limit: maxLast);
    return r.length != 1 || r.first.$1 > 1 || r.first.$2 < maxLast;
  }

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
///  1а. команда з її списку пріоритетів [priority] (назви, найпотрібніша першою) — навіть якщо нумерація не збігається
///      з Hikka (позначка ⚠): людина свідомо поставила її вище, а синхронізація з Hikka для такого варіанта лише вимкнена;
///  2. той, що вона свідомо обирала в інших тайтлах, — [favorites] (за [choiceKeyOf], найновіші першими), якщо він [safe];
///  3. перший [safe] варіант (озвучення йдуть перед субтитрами, де серій більше — вище);
///  4. інакше перший. [safe] — «нумерація збігається з Hikka» (не `mismatch`).
WatchGroup pickGroup(
  List<WatchGroup> groups, {
  String? preferredId,
  List<String> favorites = const [],
  List<String> priority = const [],
  bool Function(WatchGroup g)? safe,
}) {
  assert(groups.isNotEmpty);
  bool ok(WatchGroup g) => safe == null || safe(g);
  if (preferredId != null) {
    for (final g in groups) {
      if (g.id == preferredId) return g;
    }
  }
  for (final name in priority) {
    final n = name.trim().toLowerCase();
    if (n.isEmpty) continue;
    for (final g in groups) {
      if (teamMatches(g, n)) return g;
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

/// Чи належить варіант команді з назвою [lowerName] (у нижньому регістрі): збіг за назвою варіанта чи його команд
bool teamMatches(WatchGroup g, String lowerName) {
  if (g.teamLabel.toLowerCase().contains(lowerName)) return true;
  return g.teams.any((t) => t.name.toLowerCase().contains(lowerName));
}

/// Найбільший цілий номер серії серед варіантів
///
/// Зайві серії не враховуються (OVA за назвою, а також номери більші за [limit] — кількість серій на Hikka):
/// озвучка з додатковою серією не робить решту «неповними»
int maxEpisodeOf(Iterable<WatchGroup> groups, {int? limit}) {
  var m = 0;
  for (final g in groups) {
    final r = g.ranges(limit: limit);
    if (r.isNotEmpty && r.last.$2 > m) m = r.last.$2;
  }
  return m;
}

/// Порядок варіантів у списках: спершу команди з вашого пріоритету (за порядком у ньому), далі озвучення перед
/// субтитрами, де більше серій — вище, а за рівної кількості — за алфавітом
/// [fullFirst] — повні варіанти (див. [WatchGroup.isIncomplete]) завжди вище за неповні, хоч би де ті були в пріоритеті.
List<WatchGroup> sortGroups(List<WatchGroup> groups, {List<String> priority = const [], bool fullFirst = false, int? limit}) {
  final maxLast = maxEpisodeOf(groups, limit: limit);
  final names = [for (final n in priority) n.trim().toLowerCase()];
  int rank(WatchGroup g) {
    for (var i = 0; i < names.length; i++) {
      if (names[i].isNotEmpty && teamMatches(g, names[i])) return i;
    }
    return names.length;
  }

  final indexed = groups.asMap().entries.toList();
  indexed.sort((x, y) {
    final a = x.value, b = y.value;
    if (fullFirst) {
      final pa = (a.isIncomplete(maxLast) ? 1 : 0).compareTo(b.isIncomplete(maxLast) ? 1 : 0);
      if (pa != 0) return pa;
    }
    final r = rank(a).compareTo(rank(b));
    if (r != 0) return r;
    final k = (a.isSub ? 1 : 0).compareTo(b.isSub ? 1 : 0);
    if (k != 0) return k;
    final c = b.episodes.length.compareTo(a.episodes.length);
    if (c != 0) return c;
    final l = a.label.toLowerCase().compareTo(b.label.toLowerCase());
    return l != 0 ? l : x.key.compareTo(y.key);
  });
  return [for (final e in indexed) e.value];
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

  /// Кількість серій тайтлу на Hikka (якщо відома): що більше — зайве й не впливає на «повноту» озвучок
  final int? episodeLimit;

  const WatchTitle({
    required this.animeKey,
    required this.offers,
    this.licensed = false,
    this.license,
    this.errors = const {},
    this.episodeLimit,
  });

  /// Усі варіанти в порядку показу: див. [sortGroups]
  List<WatchGroup> get groups => sortGroups([for (final o in offers) ...o.groups], priority: StorageService.getWatchTeamPriority(), fullFirst: StorageService.getPreferFullDub(), limit: episodeLimit);

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
/// [keys] — ключі серій варіанта ([episodeKeysOf]). [hikkaEpisodes] — скільки серій відмічено переглянутими на Hikka:
/// вони вважаються переглянутими, навіть якщо в застосунку історії немає (дивились на сайті чи іншому пристрої).
ContinuePoint continuePoint(List<String> keys, Set<String> watched, String? lastKey, {int hikkaEpisodes = 0}) {
  if (keys.isEmpty) return const ContinuePoint(0, '');
  final upTo = hikkaEpisodes.clamp(0, keys.length);
  final plain = RegExp(r'^(\d+)(?:~\d+)?$');
  // Серії з простими номерами вважаємо переглянутими за номером (в озвучці можуть бути не всі серії підряд), решту
  // (сезонні, дробові, без номера) — за порядком
  bool seen(int i) {
    if (watched.contains(keys[i])) return true;
    final m = plain.firstMatch(keys[i]);
    if (m != null) return int.parse(m.group(1)!) <= hikkaEpisodes;
    return i < upTo;
  }
  final li = lastKey == null ? -1 : keys.indexOf(lastKey);
  if (li >= 0) {
    if (seen(li)) {
      for (var j = li + 1; j < keys.length; j++) {
        if (!seen(j)) return ContinuePoint(j, keys[j], started: true);
      }
    }
    return ContinuePoint(li, keys[li], started: true);
  }
  for (var i = 0; i < keys.length; i++) {
    if (!seen(i)) return ContinuePoint(i, keys[i], started: upTo > 0 || watched.any(keys.contains));
  }
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
