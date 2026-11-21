/// Reconciliation of dub/player episodes with what Hikka states. Needed for an honest disclaimer and for the future
/// "watched" sync with Hikka: marks can be sent only when the episode number in the source
/// guaranteed to mean the same episode on Hikka.
///
/// Typical pitfalls caught here:
///  • several parts of a season merged into one pile: "24 of 12" on the first part and "0 of 12" on the second;
///  • continuous numbering (13–24) on the second part's page;
///  • numbering restarts (1–12, 1–12), which gives duplicates;
///  • an OVA / special added as the last episode (13 of 12) or inserted mid-season;
///  • gaps in numbering, several seasons in one variant, missing numbers.
library;

import '../models/source_models.dart';
import 'watch_models.dart';

enum EpisodeCheckLevel {
  /// Count and numbering match Hikka
  match,

  /// Nothing to compare on Hikka (the count is unknown)
  unknown,

  /// The title is still airing: fewer are dubbed than aired, which is normal but worth mentioning
  lag,

  /// The title has finished but not all episodes are here
  incomplete,

  /// The title is airing and the source already has more episodes than Hikka knows have aired
  lead,

  /// The main episodes match, but there are extras at the end (OVA / special) that Hikka does not have
  extra,

  /// Numbering does not match Hikka (shift, gaps, repeats, several seasons, no numbers, more than "total")
  mismatch,
}

/// What Hikka says about the episode count
class HikkaEpisodeInfo {
  final int? released;
  final int? total;
  final bool finished;

  const HikkaEpisodeInfo({this.released, this.total, this.finished = false});

  bool get known => (released ?? 0) > 0 || (total ?? 0) > 0;

  /// How many episodes we expect to see in a full dub
  int? get expected => finished ? (total ?? released) : (released ?? total);
}

class EpisodeCheck {
  final EpisodeCheckLevel level;

  /// How many main episodes (integer numbers, without extra OVAs at the end) the variant has
  final int count;
  final int? expected;

  /// Short form: "5 з 12"
  final String summary;

  /// Explanation for the disclaimer: only where the numbers do not name Hikka's episodes (merged parts, repeats,
  /// several seasons, an OVA among the main ones…) or an OVA at the end will not be synced. Fewer or more episodes than
  /// on Hikka say nothing: the marks follow the episode's number, the count shows in the dub's row
  final String note;

  /// If set, only episodes up to this number inclusive can be synced with Hikka (extras at the end are ignored)
  final int? syncLimit;

  /// Each number still names Hikka's (MyAnimeList's) episode of that number — what AniSkip and the songs go by. A gap
  /// moves nothing (the first two often aired as one: Gintama's dubs go 1, 3, 4…), nor does a 0 before 1; repeats,
  /// several seasons, an extra among the main episodes, a start past 1 or numbers past Hikka's total do
  final bool numbersHold;

  const EpisodeCheck(this.level, this.count, this.expected, this.summary, this.note, {this.syncLimit, bool? numbersHold})
      : numbersHold = numbersHold ?? level != EpisodeCheckLevel.mismatch;

  /// Show the disclaimer
  bool get hasNote => note.isNotEmpty;

  /// A serious numbering mismatch (red flag)
  bool get isWarning => level == EpisodeCheckLevel.mismatch;

  /// Whether this variant's "watched" can be synced with Hikka without risk of confusion
  bool get syncSafe => level != EpisodeCheckLevel.mismatch;
}

String _list(List<int> v, {int max = 6}) {
  final shown = v.take(max).join(', ');
  return v.length > max ? '$shown …' : shown;
}

const String _extraWords =
    r'ova|ona|oad|special|specials|movie|film|спешл|спеціальн\p{L}*|спецвипуск\p{L}*|ова|оад|фільм|позасюжетн\p{L}*';

/// "OVA 1", "[OVA] …", "Спешл", "Спеціальний випуск": a marker at the start of the title
final RegExp _extraLead = RegExp(
  r'''^[\s\[\(«"'\-–—:]*(?:''' + _extraWords + r')(?![\p{L}\p{N}])',
  caseSensitive: false,
  unicode: true,
);

/// "Серія 13 (OVA)", "13 [Special]": a marker in brackets
final RegExp _extraBracket = RegExp(
  r'[\[\(][^\]\)]*?(?<![\p{L}\p{N}])(?:' + _extraWords + r')(?![\p{L}\p{N}])[^\]\)]*[\]\)]',
  caseSensitive: false,
  unicode: true,
);

/// The title looks like an OVA / special / movie (not like a regular episode). A word in the middle of an arbitrary episode
/// title ("Серія 5. Special Training") does not count, so a regular episode is not mistaken for an extra.
bool looksLikeExtra(String name) {
  for (final part in name.split('·')) {
    if (_extraLead.hasMatch(part)) return true;
  }
  return _extraBracket.hasMatch(name);
}

/// Reconciles the [episodes] with Hikka's [info].
/// [othersFrom] — the lowest episode number among the site's other dubs of the title: 1 there, and a dub that starts
/// later (Re:Zero 4 by «Далі Буде»: 10–19 of 19) joined mid-season, its numbers are the season's own
/// ([EpisodeCheck.numbersHold]); the level and the note stay as they are
EpisodeCheck checkEpisodes(List<SEpisode> episodes, HikkaEpisodeInfo info, {int? othersFrom}) {
  final expected = info.expected;
  if (episodes.isEmpty) {
    // "0 з 12": the page was found but has no episodes (often they were added to another part's page)
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
      // fractional numbers (5.5) are off-plot releases and are not counted in the main total
      if (!seen.add(n.toInt())) dups.add(n.toInt());
    }
  }

  EpisodeCheck mismatch(int count, String note) => EpisodeCheck(
        EpisodeCheckLevel.mismatch,
        count,
        expected,
        expected == null ? '$count' : '$count з $expected',
        note,
        numbersHold: false,
      );

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

  // Extra OVAs / specials: if they are all at the end, drop them from the count; if among the main ones, it is a numbering shift
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

  // Whether the numbers still name Hikka's episodes where the list is not 1, 2, 3…: 1, 3, 4… or 0, 1, 2… do (then it is
  // no mismatch, only fewer episodes); counting from zero (0…N−1 for N episodes) or past the total does not
  bool holds() {
    final positive = [for (final n in main) if (n > 0) n];
    if (positive.isEmpty) return false;
    // A later start is the season's own numbers only beside a dub of the site that starts at 1 — else it is likely
    // counted on from a previous season (13–24 for a part of 12)
    final late = positive.first > 1;
    if (late && othersFrom != 1) return false;
    if (main.first == 0 && expected != null && main.length == expected && main.last == expected - 1) return false;
    // Within Hikka's count: its total, else what aired (a day or two of Hikka's lag allowed); a late start needs one
    final total = (info.total ?? 0) > 0 ? info.total : null;
    final aired = (info.released ?? 0) > 0 ? info.released! + (info.finished ? 0 : 2) : null;
    final bound = total ?? (info.finished || late ? aired : null);
    if (bound == null) return !late;
    return positive.last <= bound;
  }

  final numbersHold = holds();
  if (main.first != 1 && !numbersHold) {
    final span = main.last - main.first + 1;
    final hint = (expected != null && span == expected)
        ? ' Схоже на наскрізну нумерацію: серії ${main.first}–${main.last} відповідають 1–$span на Hikka.'
        : '';
    return mismatch(count, 'Нумерація починається з ${main.first}, а на Hikka — з 1.$hint');
  }
  final gaps = [for (int i = 1; i <= main.last; i++) if (!main.contains(i)) i];
  if (gaps.isNotEmpty && !numbersHold) {
    return mismatch(count, 'У нумерації є пропуски (немає серій: ${_list(gaps)}).');
  }
  final total = info.total;
  if (total != null && total > 0 && main.last > total) {
    final parts = (count % total == 0) ? count ~/ total : 0;
    final hint = parts >= 2 ? ' Схоже, тут об’єднано $parts частини підряд — тоді на сторінці наступної частини серій не буде.' : '';
    return mismatch(count, 'Тут $count серій, а на Hikka їх лише $total.$hint');
  }
  if (!info.known) return EpisodeCheck(EpisodeCheckLevel.unknown, count, null, '$count з ?', '');

  final want = expected;
  if (want != null && count > want) {
    if (info.finished) {
      // A 0 before 1 (a prologue) is one more, the others are Hikka's
      if (numbersHold && main.last <= want) return EpisodeCheck(EpisodeCheckLevel.match, count, want, head, '');
      final parts = (count % want == 0) ? count ~/ want : 0;
      final hint = parts >= 2 ? ' Схоже, тут об’єднано $parts частини підряд — тоді на сторінці наступної частини серій не буде.' : '';
      return mismatch(count, 'Тут $count серій, а на Hikka їх $want.$hint');
    }
    // More aired than Hikka knows yet: the marks of the new ones reach Hikka by their numbers when it catches up
    return EpisodeCheck(EpisodeCheckLevel.lead, count, want, head, '');
  }

  String? extraNote() => tailExtras == 0
      ? null
      : 'Останні $tailExtras ${tailExtras == 1 ? 'серія схожа' : 'серії схожі'} на OVA або спецвипуск (${extras.map((e) => e.name).take(2).join(', ')}) — на Hikka ${tailExtras == 1 ? 'її' : 'їх'} немає, у синхронізації ${tailExtras == 1 ? 'вона' : 'вони'} враховуватись не будуть.';
  final limit = tailExtras > 0 ? main.last : null;

  if (want == null || count == want) {
    final n = extraNote();
    return n == null ? EpisodeCheck(EpisodeCheckLevel.match, count, want, head, '') : EpisodeCheck(EpisodeCheckLevel.extra, count, want, head, n, syncLimit: limit);
  }
  // count < want: fewer episodes (a dub still behind, or one that started mid-season) — the row shows «10 з 19», no note
  return EpisodeCheck(info.finished ? EpisodeCheckLevel.incomplete : EpisodeCheckLevel.lag, count, want, head, extraNote() ?? '', syncLimit: limit);
}

/// The same for a group; [all] — the title's dubs (for one that started mid-season: `othersFrom`)
EpisodeCheck checkGroup(WatchGroup group, HikkaEpisodeInfo info, {Iterable<WatchGroup> all = const []}) =>
    checkEpisodes(group.episodes, info, othersFrom: othersFromOf(group, all));

/// The lowest whole episode number among [all]'s dubs of [g]'s site other than [g] (see `othersFrom`)
int? othersFromOf(WatchGroup g, Iterable<WatchGroup> all) {
  int? low;
  for (final o in all) {
    if (o.id == g.id || o.sourceId != g.sourceId) continue;
    for (final e in o.episodes) {
      final n = e.number;
      if (n != null && n >= 1 && n == n.roundToDouble() && (low == null || n < low)) low = n.toInt();
    }
  }
  return low;
}
