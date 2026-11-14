import 'package:flutter/widgets.dart';

/// An on-screen notification over the video (like mpv's OSD): an icon, a title, a value,
/// an optional progress bar and a hotkey hint.
class OsdMessage {
  const OsdMessage({
    required this.icon,
    required this.title,
    this.detail,
    this.keys = const [],
    this.progress,
    this.isError = false,
  });

  final IconData icon;
  final String title;

  /// Value: "1.25x", "Режим A (Fast)", "12:34 / 24:00" …
  final String? detail;

  /// Keyboard key labels: ['Ctrl', '1']
  final List<String> keys;

  /// 0..1: a bar under the text (volume, position in the video)
  final double? progress;
  final bool isError;
}

/// Notification receiver (the player controller shows them via [OsdToast]).
typedef OsdSink = void Function(OsdMessage message, {Duration? duration});
