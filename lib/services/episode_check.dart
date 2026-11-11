/// Звірка серій озвучки/плеєра з тим, що вказано на Hikka. Потрібна для чесного дисклеймера й для майбутньої
/// синхронізації «переглянуто» з Hikka: відмітки можна передавати лише тоді, коли номер серії в джерелі
/// гарантовано означає ту саму серію на Hikka.
///
/// Типові халепи, які тут ловляться:
///  • кілька частин сезону злито в одну купу: «24 з 12» на першій частині й «0 з 12» на другій;
///  • наскрізна нумерація (13–24) на сторінці другої частини;
///  • номери починаються знову (1–12, 1–12) — повтори;
///  • OVA / спецвипуск додано останньою серією (13 при 12) або вставлено посеред сезону;
///  • пропуски в нумерації, кілька сезонів у одному варіанті, відсутні номери.
library;

import '../models/source_models.dart';
import 'watch_models.dart';

enum EpisodeCheckLevel {
  /// Кількість і нумерація збігаються з Hikka
  match,

  /// На Hikka нічого порівняти (кількість невідома)
  unknown,

  /// Тайтл ще виходить: озвучено менше, ніж вийшло, — це нормально, але варто сказати
  lag,

  /// Тайтл завершено, а тут не всі серії
  incomplete,

  /// Тайтл виходить, у джерелі вже більше серій, ніж Hikka знає про вихід
  lead,

  /// Основні серії збігаються, але в кінці є зайві (OVA / спецвипуск), яких на Hikka нема
  extra,

  /// Нумерація не збігається з Hikka (зсув, пропуски, повтори, кілька сезонів, немає номерів, більше за «всього»)
  mismatch,
}

/// Що Hikka каже про кількість серій
class HikkaEpisodeInfo {
  final int? released;
  final int? total;
  final bool finished;

  const HikkaEpisodeInfo({this.released, this.total, this.finished = false});

  bool get known => (released ?? 0) > 0 || (total ?? 0) > 0;

  /// Скільки серій очікуємо побачити в повній озвучці
  int? get expected => finished ? (total ?? released) : (released ?? total);
}

class EpisodeCheck {
  final EpisodeCheckLevel level;

  /// Скільки основних серій (з цілими номерами, без зайвих OVA в кінці) у варіанті
  final int count;
  final int? expected;

  /// Коротко: «5 з 12»
  final String summary;

  /// Пояснення для дисклеймера (порожнє, коли все гаразд)
  final String note;

  /// Якщо задано — з Hikka можна синхронізувати лише серії до цього номера включно (зайві в кінці ігноруються)
  final int? syncLimit;

  const EpisodeCheck(this.level, this.count, this.expected, this.summary, this.note, {this.syncLimit});

  /// Показувати дисклеймер
  bool get hasNote => note.isNotEmpty;

  /// Серйозна розбіжність нумерації (червоний прапорець)
  bool get isWarning => level == EpisodeCheckLevel.mismatch;

  /// Чи можна синхронізувати «переглянуто» цього варіанта з Hikka без ризику плутанини
  bool get syncSafe => level != EpisodeCheckLevel.mismatch;
}

String _list(List<int> v, {int max = 6}) {
  final shown = v.take(max).join(', ');
  return v.length > max ? '$shown …' : shown;
}

const String _extraWords =
    r'ova|ona|oad|special|specials|movie|film|спешл|спеціальн\p{L}*|спецвипуск\p{L}*|ова|оад|фільм|позасюжетн\p{L}*';

/// «OVA 1», «[OVA] …», «Спешл», «Спеціальний випуск» — позначка на початку назви
final RegExp _extraLead = RegExp(
  r'''^[\s\[\(«"'\-–—:]*(?:''' + _extraWords + r')(?![\p{L}\p{N}])',
  caseSensitive: false,
  unicode: true,
);

/// «Серія 13 (OVA)», «13 [Special]» — позначка в дужках
final RegExp _extraBracket = RegExp(
  r'[\[\(][^\]\)]*?(?<![\p{L}\p{N}])(?:' + _extraWords + r')(?![\p{L}\p{N}])[^\]\)]*[\]\)]',
  caseSensitive: false,
  unicode: true,
);

/// Назва схожа на OVA / спецвипуск / фільм (а не на звичайну серію). Слово в середині довільної назви
/// серії («Серія 5. Special Training») не рахується — щоб не прийняти звичайну серію за зайву.
bool looksLikeExtra(String name) {
  for (final part in name.split('·')) {
    if (_extraLead.hasMatch(part)) return true;
  }
  return _extraBracket.hasMatch(name);
}

const String _syncOff = 'Тому відмітки «переглянуто» для цього варіанта не синхронізуватимуться з Hikka автоматично.';

/// Звіряє серії [episodes] із даними Hikka [info].
EpisodeCheck checkEpisodes(List<SEpisode> episodes, HikkaEpisodeInfo info) {
  final expected = info.expected;
  if (episodes.isEmpty) {
    // «0 з 12»: сторінку знайдено, а серій на ній немає (часто їх додано на сторінку іншої частини сезону)
    if (expected == null || expected <= 0) return const EpisodeCheck(EpisodeCheckLevel.unknown, 0, null, '0 з ?', '');
    return EpisodeCheck(
      info.finished ? EpisodeCheckLevel.incomplete : EpisodeCheckLevel.lag,
      0,
      expected,
      '0 з $expected',
      info.finished
          ? 'Тут немає жодної серії (на Hikka їх $expected). Можливо, їх додано на сторінку іншої частини сезону.'
          : 'Тут поки немає жодної серії (на Hikka вийшло $expected).',
    );
  }

  final seasons = <int>{for (final e in episodes) if (e.season != null) e.season!};
  var unnumbered = 0;
  final seen = <int>{};
  final dups = <int>{};
  for (final e in episodes) {
    final n = e.number;
    if (n == null) {
      unnumbered++;
    } else if (n == n.roundToDouble()) {
      // дробові номери (5.5) — позасюжетні випуски, до основного рахунку не входять
      if (!seen.add(n.toInt())) dups.add(n.toInt());
    }
  }

  EpisodeCheck mismatch(int count, String note) =>
      EpisodeCheck(EpisodeCheckLevel.mismatch, count, expected, expected == null ? '$count' : '$count з $expected', '$note $_syncOff');

  if (seasons.length > 1) {
    return mismatch(seen.length, 'У цьому варіанті зібрано кілька сезонів (${seasons.length}), а Hikka рахує серії одного сезону окремо.');
  }
  if (unnumbered > 0 || seen.isEmpty) {
    return mismatch(seen.length, 'Не вдалося визначити номери серій, тож порівняти їх із Hikka неможливо.');
  }
  if (dups.isNotEmpty) {
    final d = dups.toList()..sort();
    return mismatch(seen.length, 'Номери серій повторюються (${_list(d)}): схоже, тут зібрано кілька частин підряд.');
  }

  // Зайві OVA / спецвипуски: якщо вони всі в кінці — відкидаємо їх із рахунку, а якщо серед основних — зсув нумерації
  final numbered = [for (final e in episodes) if (e.number != null && e.number == e.number!.roundToDouble()) e]
    ..sort((a, b) => a.number!.compareTo(b.number!));
  final extras = [for (final e in numbered) if (looksLikeExtra(e.name)) e];
  var main = [for (final e in numbered) if (!looksLikeExtra(e.name)) e.number!.toInt()];
  var tailExtras = 0;
  if (extras.isNotEmpty) {
    final lastMain = main.isEmpty ? 0 : main.last;
    final inTail = extras.every((e) => e.number!.toInt() > lastMain);
    if (!inTail) {
      final first = extras.firstWhere((e) => e.number!.toInt() < lastMain);
      return mismatch(seen.length, 'Серед основних серій є схожа на OVA або спецвипуск («${first.name}»), через що нумерація зсувається відносно Hikka.');
    }
    tailExtras = extras.length;
  }
  if (main.isEmpty) main = seen.toList()..sort();
  final count = main.length;
  final head = expected == null ? '$count з ?' : '$count з $expected';

  if (main.first != 1) {
    final span = main.last - main.first + 1;
    final hint = (expected != null && span == expected)
        ? ' Схоже на наскрізну нумерацію: серії ${main.first}–${main.last} відповідають 1–$span на Hikka.'
        : '';
    return mismatch(count, 'Нумерація починається з ${main.first}, а на Hikka — з 1.$hint');
  }
  final gaps = [for (int i = 1; i <= main.last; i++) if (!main.contains(i)) i];
  if (gaps.isNotEmpty) {
    return mismatch(count, 'У нумерації є пропуски (немає серій: ${_list(gaps)}).');
  }
  final total = info.total;
  if (total != null && total > 0 && main.last > total) {
    final parts = (count % total == 0) ? count ~/ total : 0;
    final hint = parts >= 2 ? ' Схоже, тут об’єднано $parts частини підряд — тоді на сторінці наступної частини серій не буде.' : '';
    return mismatch(count, 'Тут $count серій, а на Hikka їх лише $total.$hint');
  }
  if (!info.known) return EpisodeCheck(EpisodeCheckLevel.unknown, count, null, '$count з ?', '');

  final released = info.released ?? 0;
  final want = expected;
  if (want != null && count > want) {
    if (info.finished) {
      final parts = (count % want == 0) ? count ~/ want : 0;
      final hint = parts >= 2 ? ' Схоже, тут об’єднано $parts частини підряд — тоді на сторінці наступної частини серій не буде.' : '';
      return mismatch(count, 'Тут $count серій, а на Hikka їх $want.$hint');
    }
    return EpisodeCheck(
      EpisodeCheckLevel.lead,
      count,
      want,
      head,
      'Кількість епізодів не збігається з Hikka: $count з ${released > 0 ? released : want}. Відмітки «переглянуто» зʼявляться на Hikka, коли він оновить дані.',
    );
  }

  String? extraNote() => tailExtras == 0
      ? null
      : 'Останні $tailExtras ${tailExtras == 1 ? 'серія схожа' : 'серії схожі'} на OVA або спецвипуск (${extras.map((e) => e.name).take(2).join(', ')}) — на Hikka ${tailExtras == 1 ? 'її' : 'їх'} немає, у синхронізації ${tailExtras == 1 ? 'вона' : 'вони'} враховуватись не будуть.';
  final limit = tailExtras > 0 ? main.last : null;

  if (want == null || count == want) {
    final n = extraNote();
    return n == null ? EpisodeCheck(EpisodeCheckLevel.match, count, want, head, '') : EpisodeCheck(EpisodeCheckLevel.extra, count, want, head, n, syncLimit: limit);
  }
  // count < want
  final prefix = extraNote();
  if (info.finished) {
    return EpisodeCheck(
      EpisodeCheckLevel.incomplete,
      count,
      want,
      head,
      'У цього озвучення є відсутні серії: $count/$want.${prefix == null ? '' : ' $prefix'}',
      syncLimit: limit,
    );
  }
  return EpisodeCheck(
    EpisodeCheckLevel.lag,
    count,
    want,
    head,
    'Озвучено $count з $want серій, що вже вийшли; решта зʼявиться пізніше.${prefix == null ? '' : ' $prefix'}',
    syncLimit: limit,
  );
}

/// Те саме для групи
EpisodeCheck checkGroup(WatchGroup group, HikkaEpisodeInfo info) => checkEpisodes(group.episodes, info);
