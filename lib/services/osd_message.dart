import 'package:flutter/widgets.dart';

/// Екранне сповіщення поверх відео (аналог OSD в mpv): іконка, заголовок, значення,
/// необов'язкова смужка прогресу й підказка гарячої клавіші.
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

  /// Значення: «1.25x», «Режим A (Fast)», «12:34 / 24:00» …
  final String? detail;

  /// Підписи кнопок клавіатури: ['Ctrl', '1']
  final List<String> keys;

  /// 0..1 — смужка під текстом (гучність, позиція у відео)
  final double? progress;
  final bool isError;
}

/// Приймач сповіщень (контролер плеєра показує їх через [OsdToast]).
typedef OsdSink = void Function(OsdMessage message, {Duration? duration});
