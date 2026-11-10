/// Міст між [RemoteDriver] і media_kit: відкриває пряме відео із заголовками й місцем початку, додає зовнішні доріжки.
library;

import 'package:media_kit/media_kit.dart' show Media, Player;

import '../models/source_models.dart';
import 'remote_driver.dart';

class MpvRemoteEngine implements RemoteEngine {
  MpvRemoteEngine({required this.player, required this.command});

  final Player player;

  /// Виконує команду mpv (`PlayerStateController.mpv`); помилки не кидає
  final Future<void> Function(List<String> args) command;

  /// Заголовки (Referer, User-Agent …) media_kit передає mpv перед завантаженням, місце початку — опцією `start`
  /// (тому відео одразу відкривається з потрібної секунди, без «стрибка» після старту).
  /// Додаткові опції mpv із [Video.mpvOptions] поки не застосовуються: жодне джерело їх не задає.
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

  /// mpv: `<назва> <мова>`; мова — лише коротким кодом (`uk`, `eng`), довільний підпис іде в назву
  static List<String> _labels(Track t) {
    final lang = t.lang.trim();
    if (lang.isEmpty) return const [];
    final code = RegExp(r'^[A-Za-z]{2,3}(-[A-Za-z]{2,4})?$').hasMatch(lang) ? lang.toLowerCase() : '';
    return code.isEmpty ? [lang] : [lang, code];
  }
}
