import 'package:media_kit/media_kit.dart';

class VideoChapter {
  final String title;
  final Duration startTime;
  final Duration? endTime;

  /// "Автоматичний пропуск" may skip it: its times are exact (not moved over from another version with a margin)
  final bool autoSkip;

  const VideoChapter({
    required this.title,
    required this.startTime,
    this.endTime,
    this.autoSkip = true,
  });
}

/// Volume for the slider: value (0..100) + "muted". Has equality, so identical
/// values do not cause rebuilds.
class VolumeState {
  final double volume;
  final bool muted;

  const VolumeState(this.volume, this.muted);

  @override
  bool operator ==(Object other) => other is VolumeState && other.volume == volume && other.muted == muted;

  @override
  int get hashCode => Object.hash(volume, muted);
}

class CachedSubtitleTrack {
  final SubtitleTrack track;
  final String formattedTitle;

  const CachedSubtitleTrack({
    required this.track,
    required this.formattedTitle,
  });
}

class CachedAudioTrack {
  final AudioTrack track;
  final String formattedTitle;

  const CachedAudioTrack({
    required this.track,
    required this.formattedTitle,
  });
}

class PlaybackStats {
  final int totalDroppedFrames;
  final int voDroppedFrames;
  final int decoderDroppedFrames;
  final double currentFps;
  final double containerFps;
  final double expectedFps;
  final String hwdecActive;
  final double avSyncDiff;
  final String videoCodec;
  final String audioCodec;

  /// What goes to the speakers: channels (and what they came from), rate, the output (`MpvConfig.describeAudioOutput`)
  final String audioOutput;

  const PlaybackStats({
    this.totalDroppedFrames = 0,
    this.voDroppedFrames = 0,
    this.decoderDroppedFrames = 0,
    this.currentFps = 0.0,
    this.containerFps = 23.976,
    this.expectedFps = 23.976,
    this.hwdecActive = "nvdec-copy",
    this.avSyncDiff = 0.0,
    this.videoCodec = "HEVC",
    this.audioCodec = "AAC",
    this.audioOutput = '—',
  });
}