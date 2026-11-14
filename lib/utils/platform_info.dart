import 'dart:io' show Platform;
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart' show visibleForTesting;

/// Where the app runs. Window features (mini player, "always on top", window
/// dragging) exist only on desktop; a phone has none.
class AppPlatform {
  const AppPlatform._();

  /// Tests only: true behaves as a phone, false as desktop, null follows the real platform
  @visibleForTesting
  static bool? debugMobile;

  static final bool _realDesktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  static final bool _realMobile = Platform.isAndroid || Platform.isIOS;

  static bool get isDesktop => debugMobile != null ? !debugMobile! : _realDesktop;
  static bool get isMobile => debugMobile ?? _realMobile;
  static final bool isAndroid = Platform.isAndroid;

  /// Hardware decoding by default: Direct3D 11 on Windows, MediaCodec on Android
  static final String defaultHwdec = Platform.isAndroid ? 'mediacodec-copy' : 'd3d11va-copy';

  /// Scale of the old ("desktop") widgets on a phone: they were designed for a mouse and a big
  /// screen, so they are enlarged on a touch screen. New mobile widgets set sizes in dp themselves.
  static const double mobileScale = 1.15;

  /// Minimum touch target size (Material recommendation: 48 dp)
  static const double touchTarget = 48;
}

/// Layout for the current screen size (portrait / landscape, narrow / wide).
class AppLayout {
  final Size size;
  const AppLayout(this.size);

  bool get isLandscape => size.width > size.height;
  bool get isPortrait => !isLandscape;

  /// Narrow screen (phone in portrait): the side navigation is replaced by a bottom one
  bool get isCompactWidth => size.width < 640;

  /// Short screen (phone in landscape): there is little vertical room
  bool get isShortHeight => size.height < 520;
}
