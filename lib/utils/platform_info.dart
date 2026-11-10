import 'dart:io' show Platform;
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart' show visibleForTesting;

/// Де працює застосунок. Віконні можливості (міні-плеєр, «поверх усіх вікон», перетягування
/// вікна) є лише на десктопі; на телефоні їх немає.
class AppPlatform {
  const AppPlatform._();

  /// Лише для тестів: true — поводитись як телефон, false — як десктоп, null — за справжньою платформою
  @visibleForTesting
  static bool? debugMobile;

  static final bool _realDesktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  static final bool _realMobile = Platform.isAndroid || Platform.isIOS;

  static bool get isDesktop => debugMobile != null ? !debugMobile! : _realDesktop;
  static bool get isMobile => debugMobile ?? _realMobile;
  static final bool isAndroid = Platform.isAndroid;

  /// Апаратне декодування за замовчуванням: Direct3D 11 на Windows, MediaCodec на Android
  static final String defaultHwdec = Platform.isAndroid ? 'mediacodec-copy' : 'd3d11va-copy';

  /// Масштаб старих («десктопних») віджетів на телефоні: вони розраховані на мишу й великий
  /// екран, тож на дотиковому екрані збільшуються. Нові мобільні віджети задають розміри в dp самі.
  static const double mobileScale = 1.15;

  /// Мінімальний розмір цілі дотику (рекомендація Material: 48 dp)
  static const double touchTarget = 48;
}

/// Розкладка під поточний розмір екрана (портрет / альбомна, вузький / широкий).
class AppLayout {
  final Size size;
  const AppLayout(this.size);

  bool get isLandscape => size.width > size.height;
  bool get isPortrait => !isLandscape;

  /// Вузький екран (телефон у портреті): бічна навігація замінюється нижньою
  bool get isCompactWidth => size.width < 640;

  /// Низький екран (телефон в альбомній): вертикального місця мало
  bool get isShortHeight => size.height < 520;
}
