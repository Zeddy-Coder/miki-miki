/// A bridge between [RemoteDriver] and media_kit: opens a direct video with headers and a start position, adds external tracks.
library;

import 'package:media_kit/media_kit.dart' show Media, Player;

import '../models/source_models.dart';
import 'remote_driver.dart';

class MpvRemoteEngine implements RemoteEngine {
  MpvRemoteEngine({required this.player, required this.command});

  final Player player;

  /// Runs an mpv command (`PlayerStateController.mpv`); does not throw errors
  final Future<void> Function(List<String> args) command;

  /// media_kit passes headers (Referer, User-Agent …) to mpv before loading, and the start position as the `start` option
  /// (so the video opens at the right second at once, without a "jump" after the start).
  /// Extra mpv options from [Video.mpvOptions] are not applied yet: no source sets them.
  @override
  Future<void> openVideo(Video video, {Duration? start}) {
    final media = Media(
      video.url,
      httpHeaders: video.headers.isEmpty ? null : video.headers,
      start: (start == null || start <= Duration.zero) ? null : start,
    );
    return player.open(media, play: true);
  }

  @override
  Duration get position => player.state.position;

  @override
  Duration get duration => player.state.duration;

  @override
  bool get playing => player.state.playing;

  @override
  Future<void> addSubtitle(Track track, {required bool select}) =>
      command(['sub-add', track.url, select ? 'select' : 'auto', ..._labels(track)]);

  @override
  Future<void> addAudio(Track track, {required bool select}) =>
      command(['audio-add', track.url, select ? 'select' : 'auto', ..._labels(track)]);

  /// mpv: `<title> <language>`; the language only as a short code (`uk`, `eng`), an arbitrary label goes into the title
  static List<String> _labels(Track t) {
    final lang = t.lang.trim();
    if (lang.isEmpty) return const [];
    final code = RegExp(r'^[A-Za-z]{2,3}(-[A-Za-z]{2,4})?$').hasMatch(lang) ? lang.toLowerCase() : '';
    return code.isEmpty ? [lang] : [lang, code];
  }
}
