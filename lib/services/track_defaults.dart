import 'package:media_kit/media_kit.dart';

import 'lang_match.dart';

/// What exactly the player should enable for a freshly opened file
class TrackPlan {
  /// `null`: change nothing (the mpv choice stays); [SubtitleTrack.no] turns subtitles off
  final SubtitleTrack? subtitle;
  final AudioTrack? audio;

  const TrackPlan({this.subtitle, this.audio});

  bool get isEmpty => subtitle == null && audio == null;
}

/// Auto-selecting subtitle and audio tracks by the language priority from settings ("Пріоритет мов субтитрів / аудіодоріжок").
///
/// mpv itself does not know the language from settings: by default it turns on only a track marked "default", so
/// in a file without such a mark no subtitles are visible, whatever the settings say. Here the player picks the track:
/// the first language from the list that has a track. The language is taken from the track label (`ukr`, `uk`, `pt-BR`), and when there is no label
/// or it is "und", from the title ("Українські", "Ukrainian [FanVox]", "UA").
class TrackDefaults {
  const TrackDefaults._();

  /// Not full subtitles: only signs, songs, "forced". We take them when there are no full ones in this language
  static final RegExp _partialSubs = RegExp(r'\b(signs?|songs?|forced|karaoke)\b|надпис|написи|пісн|караоке', caseSensitive: false);

  /// Not the main audio: director's commentary, audio description
  static final RegExp _extraAudio = RegExp(r'\b(commentary|descriptive|description)\b|коментар|тифлокоментар', caseSensitive: false);

  static _Cand<T>? _pick<T>(List<_Cand<T>> cands, List<String> priorities, bool Function(String title) lesser) {
    for (final code in priorities) {
      final fit = cands.where((c) => LangMatch.matches(code, language: c.language, title: c.title)).toList();
      if (fit.isEmpty) continue;
      // A full track before a partial one, text before image, "default" before the rest, then as in the file
      int rank(_Cand<T> c) => (lesser(c.title ?? '') ? 4 : 0) + (c.image ? 2 : 0) + (c.isDefault ? 0 : 1);
      fit.sort((a, b) {
        final r = rank(a).compareTo(rank(b));
        return r != 0 ? r : a.index.compareTo(b.index);
      });
      return fit.first;
    }
    return null;
  }

  /// Which subtitle track to turn on: the first language from the list that has one. `null`: there is none
  static SubtitleTrack? pickSubtitle(List<SubtitleTrack> tracks, List<String> priorities) {
    final cands = <_Cand<SubtitleTrack>>[
      for (int i = 0; i < tracks.length; i++)
        if (tracks[i].id != 'auto' && tracks[i].id != 'no')
          _Cand(tracks[i], tracks[i].language, tracks[i].title, tracks[i].isDefault ?? false, tracks[i].image ?? false, i),
    ];
    return _pick(cands, priorities, _partialSubs.hasMatch)?.track;
  }

  /// Which audio track to turn on: the first language from the list that has one. `null`: there is none
  static AudioTrack? pickAudio(List<AudioTrack> tracks, List<String> priorities) {
    final cands = <_Cand<AudioTrack>>[
      for (int i = 0; i < tracks.length; i++)
        if (tracks[i].id != 'auto' && tracks[i].id != 'no')
          _Cand(tracks[i], tracks[i].language, tracks[i].title, tracks[i].isDefault ?? false, false, i),
    ];
    return _pick(cands, priorities, _extraAudio.hasMatch)?.track;
  }

  /// Choice for a file with the given [tracks]. Subtitles are off in settings ([subtitlesEnabled] = false): `no`,
  /// but only when the file has at least one track (otherwise there is nothing to turn off).
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
