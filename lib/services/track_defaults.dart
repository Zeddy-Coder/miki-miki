import 'package:media_kit/media_kit.dart';

import 'lang_match.dart';

/// Що саме плеєр має увімкнути для щойно відкритого файлу
class TrackPlan {
  /// `null` — нічого не міняти (лишається вибір mpv); [SubtitleTrack.no] — вимкнути субтитри
  final SubtitleTrack? subtitle;
  final AudioTrack? audio;

  const TrackPlan({this.subtitle, this.audio});

  bool get isEmpty => subtitle == null && audio == null;
}

/// Автовибір доріжок субтитрів і звуку за пріоритетом мов із налаштувань («Пріоритет мов субтитрів / аудіодоріжок»).
///
/// Сам mpv мову з налаштувань не знає: за замовчуванням він вмикає лише доріжку з позначкою «за замовчуванням», тож
/// у файлі, де такої позначки нема, субтитрів не видно, хоч би що було в налаштуваннях. Тут доріжку обирає плеєр:
/// перша мова зі списку, для якої є доріжка. Мову беремо з мітки доріжки (`ukr`, `uk`, `pt-BR`), а коли мітки нема
/// чи вона «und» — із назви («Українські», «Ukrainian [FanVox]», «UA»).
class TrackDefaults {
  const TrackDefaults._();

  /// Не повні субтитри: лише написи, пісні, «примусові». Їх беремо, коли повних цією мовою нема
  static final RegExp _partialSubs = RegExp(r'\b(signs?|songs?|forced|karaoke)\b|надпис|написи|пісн|караоке', caseSensitive: false);

  /// Не основне аудіо: коментарі режисера, тифлокоментар
  static final RegExp _extraAudio = RegExp(r'\b(commentary|descriptive|description)\b|коментар|тифлокоментар', caseSensitive: false);

  static _Cand<T>? _pick<T>(List<_Cand<T>> cands, List<String> priorities, bool Function(String title) lesser) {
    for (final code in priorities) {
      final fit = cands.where((c) => LangMatch.matches(code, language: c.language, title: c.title)).toList();
      if (fit.isEmpty) continue;
      // Повна доріжка перед неповною, текстова перед зображенням, «за замовчуванням» перед рештою, далі — як у файлі
      int rank(_Cand<T> c) => (lesser(c.title ?? '') ? 4 : 0) + (c.image ? 2 : 0) + (c.isDefault ? 0 : 1);
      fit.sort((a, b) {
        final r = rank(a).compareTo(rank(b));
        return r != 0 ? r : a.index.compareTo(b.index);
      });
      return fit.first;
    }
    return null;
  }

  /// Яку доріжку субтитрів увімкнути: перша мова зі списку, для якої вона є. `null` — жодної такої нема
  static SubtitleTrack? pickSubtitle(List<SubtitleTrack> tracks, List<String> priorities) {
    final cands = <_Cand<SubtitleTrack>>[
      for (int i = 0; i < tracks.length; i++)
        if (tracks[i].id != 'auto' && tracks[i].id != 'no')
          _Cand(tracks[i], tracks[i].language, tracks[i].title, tracks[i].isDefault ?? false, tracks[i].image ?? false, i),
    ];
    return _pick(cands, priorities, _partialSubs.hasMatch)?.track;
  }

  /// Яку аудіодоріжку увімкнути: перша мова зі списку, для якої вона є. `null` — жодної такої нема
  static AudioTrack? pickAudio(List<AudioTrack> tracks, List<String> priorities) {
    final cands = <_Cand<AudioTrack>>[
      for (int i = 0; i < tracks.length; i++)
        if (tracks[i].id != 'auto' && tracks[i].id != 'no')
          _Cand(tracks[i], tracks[i].language, tracks[i].title, tracks[i].isDefault ?? false, false, i),
    ];
    return _pick(cands, priorities, _extraAudio.hasMatch)?.track;
  }

  /// Вибір для файлу з наявними [tracks]. Субтитри вимкнено в налаштуваннях ([subtitlesEnabled] = false) — `no`,
  /// але лише коли в файлі є бодай одна доріжка (інакше нічого й вимикати).
  static TrackPlan plan(Tracks tracks, {required bool subtitlesEnabled, required List<String> subPriorities, required List<String> audioPriorities}) {
    final hasSubs = tracks.subtitle.any((t) => t.id != 'auto' && t.id != 'no');
    SubtitleTrack? sub;
    if (!subtitlesEnabled) {
      if (hasSubs) sub = SubtitleTrack.no();
    } else {
      sub = pickSubtitle(tracks.subtitle, subPriorities);
    }
    return TrackPlan(subtitle: sub, audio: pickAudio(tracks.audio, audioPriorities));
  }
}

class _Cand<T> {
  final T track;
  final String? language;
  final String? title;
  final bool isDefault;
  final bool image;
  final int index;

  const _Cand(this.track, this.language, this.title, this.isDefault, this.image, this.index);
}
