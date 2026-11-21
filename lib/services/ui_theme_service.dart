import 'package:flutter/material.dart';
import '../utils/platform_info.dart';
import 'storage_service.dart';

/// Theme design tokens (light and dark palettes)
class AppThemePalette {
  final Color bgPrimary;
  final Color bgSurface;
  final Color bgElevated;
  final Color bgSidebar;
  final Color borderSubtle;
  final Color borderMedium;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color textDarkMuted;
  final Color drawerBg;
  final Color drawerBorder;
  final Color tileBg;
  final Color tileBorder;
  final Color overlayShadow;

  const AppThemePalette({
    required this.bgPrimary,
    required this.bgSurface,
    required this.bgElevated,
    required this.bgSidebar,
    required this.borderSubtle,
    required this.borderMedium,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.textDarkMuted,
    required this.drawerBg,
    required this.drawerBorder,
    required this.tileBg,
    required this.tileBorder,
    required this.overlayShadow,
  });

  static const dark = AppThemePalette(
    bgPrimary: Color(0xFF0C0C0C),
    bgSurface: Color(0xFF141416),
    bgElevated: Color(0xFF1E1E22),
    bgSidebar: Color(0xFF111114),
    borderSubtle: Color(0xFF222226),
    borderMedium: Color(0xFF2C2C34),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xFFCCCCCC),
    textMuted: Color(0xFFAAAAAA),
    textDarkMuted: Color(0xFF888888),
    drawerBg: Color(0xFF18181C),
    drawerBorder: Color(0xFF282830),
    tileBg: Color(0xFF18181C),
    tileBorder: Color(0xFF282830),
    overlayShadow: Color(0xFF0C0C0C),
  );

  static const light = AppThemePalette(
    bgPrimary: Color(0xFFF6F6F9),
    bgSurface: Color(0xFFFFFFFF),
    bgElevated: Color(0xFFEBEBF2),
    bgSidebar: Color(0xFFEFEFF5),
    borderSubtle: Color(0xFFE0E0E8),
    borderMedium: Color(0xFFD0D0DC),
    textPrimary: Color(0xFF111114),
    textSecondary: Color(0xFF454552),
    textMuted: Color(0xFF6E6E7C),
    textDarkMuted: Color(0xFF90909E),
    drawerBg: Color(0xFFFFFFFF),
    drawerBorder: Color(0xFFE0E0E8),
    tileBg: Color(0xFFFFFFFF),
    tileBorder: Color(0xFFE0E0E8),
    overlayShadow: Color(0xFFF6F6F9),
  );
}

class UiThemeService extends ChangeNotifier {
  static final UiThemeService instance = UiThemeService._();
  // The default (yellow) accent right away, before init() reads the saved one
  UiThemeService._() {
    _rebuildAccents();
  }

  static const Map<String, (String, Color)> presets = {
    '#E46767': ('Кораловий', Color(0xFFE46767)),
    '#A667E4': ('Фіолетовий', Color(0xFFA667E4)),
    '#00E5FF': ('Блакитний', Color(0xFF00E5FF)),
    '#00FF66': ('Смарагдовий', Color(0xFF00FF66)),
    '#FFAA00': ('Жовтий', Color(0xFFFFAA00)),
    '#FF3366': ('Рожевий', Color(0xFFFF3366)),
    '#FF0000': ('Класичний червоний', Color(0xFFFF0000)),
  };

  /// Defaults: a yellow accent and the system theme
  static const String defaultAccentHex = '#FFAA00';
  static const String defaultThemeMode = 'system';

  static const Map<String, double> radiusMultipliers = {
    'Без': 0.0,
    'XS': 0.5,
    'SM': 0.75,
    'MD': 1.0,
    'LG': 1.4,
    'XL': 1.8,
  };

  String _accentHex = defaultAccentHex;
  String _radiusKey = 'MD';
  String _themeMode = defaultThemeMode; // 'system', 'dark', 'light'

  // Accents adjusted for the light / dark theme (computed once when the color changes)
  Color _accentForLight = const Color(0xFFCF2525);
  Color _accentForDark = const Color(0xFFE46767);

  void init() {
    _accentHex = StorageService.getAccentColorHex(fallback: defaultAccentHex);
    _radiusKey = StorageService.getUiRadius(fallback: 'MD');
    _themeMode = StorageService.getThemeMode(fallback: defaultThemeMode);
    _rebuildAccents();
    notifyListeners();
  }

  String get accentHex => _accentHex;
  String get radiusKey => _radiusKey;
  String get themeMode => _themeMode;

  ThemeMode get flutterThemeMode {
    if (_themeMode == 'light') return ThemeMode.light;
    if (_themeMode == 'system') return ThemeMode.system;
    return ThemeMode.dark;
  }

  bool get isLight {
    if (_themeMode == 'light') return true;
    if (_themeMode == 'system') {
      return WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.light;
    }
    return false;
  }

  /// The active palette (automatically Light or Dark)
  AppThemePalette get colors => isLight ? AppThemePalette.light : AppThemePalette.dark;

  // Direct shortcuts to the most used tokens
  Color get bgPrimary => colors.bgPrimary;
  Color get bgSurface => colors.bgSurface;
  Color get bgElevated => colors.bgElevated;
  Color get bgSidebar => colors.bgSidebar;
  Color get borderSubtle => colors.borderSubtle;
  Color get borderMedium => colors.borderMedium;
  Color get textPrimary => colors.textPrimary;
  Color get textSecondary => colors.textSecondary;
  Color get textMuted => colors.textMuted;
  Color get textDarkMuted => colors.textDarkMuted;

  // ── Accent colors ───────────────────────────────────────────────────────
  //
  // The color the user picked ([baseAccent]) cannot be used "as is": a saturated
  // neon (#00FF66, #00E5FF, #FFAA00) on a light background has a contrast of 1.1–1.6:1 and
  // vanishes, and on a dark one it vibrates. So [accentColor] is the same hue
  // with the lightness adjusted to the active theme's background by WCAG contrast:
  //   • at least 4.5:1, so the accent's text and icons are readable;
  //   • at most 8:1 (light) / 10:1 (dark), so it does not turn almost black
  //     or blinding white.
  // Saturation is slightly limited so that bright colors do not "cut" the eyes.

  /// The color the user picked in settings (for swatches)
  Color get baseAccent {
    if (presets.containsKey(_accentHex)) {
      return presets[_accentHex]!.$2;
    }
    try {
      final clean = _accentHex.replaceAll('#', '').trim();
      return Color(int.parse('FF$clean', radix: 16));
    } catch (_) {
      return const Color(0xFFE46767);
    }
  }

  /// Accent for the current theme
  Color get accentColor => isLight ? _accentForLight : _accentForDark;

  /// Accent for elements over the video (the background there is always dark, regardless of theme)
  Color get accentOnDark => _accentForDark;

  /// Color of text / icons over a solid accent fill (white or almost black)
  Color get onAccent => readableOn(accentColor);

  static const Color _lightRef = Color(0xFFEBEBF2); // the darkest surface of the light theme
  static const Color _darkRef = Color(0xFF1E1E22); // the lightest surface of the dark theme

  static double contrastRatio(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final hi = la > lb ? la : lb;
    final lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  /// White or almost black, whichever contrasts more on [bg]
  static Color readableOn(Color bg) {
    const dark = Color(0xFF111114);
    return contrastRatio(Colors.white, bg) >= contrastRatio(dark, bg) ? Colors.white : dark;
  }

  /// Adjusts [base] to a light or dark background, keeping the hue.
  static Color adaptAccent(Color base, {required bool forLight}) {
    final ref = forLight ? _lightRef : _darkRef;
    // Light theme: a saturated accent must stay bright (3:1 for large elements), dark is stricter
    final minContrast = forLight ? 3.0 : 4.5;
    final maxContrast = forLight ? 8.0 : 10.0;

    final hsl = HSLColor.fromColor(base);
    final sat = hsl.saturation.clamp(0.0, forLight ? 0.95 : 0.88).toDouble();
    Color at(double l) => HSLColor.fromAHSL(1.0, hsl.hue, sat, l).toColor();

    final current = contrastRatio(at(hsl.lightness), ref);
    if (current >= minContrast && current <= maxContrast) return at(hsl.lightness);

    final bool tooLow = current < minContrast;
    final double target = tooLow ? minContrast : maxContrast;

    // Contrast is monotonic in lightness: on a light background it falls as L grows, on a dark one it rises.
    double lo = 0.0, hi = 1.0;
    for (int i = 0; i < 24; i++) {
      final mid = (lo + hi) / 2;
      final c = contrastRatio(at(mid), ref);
      final bool needLighter = forLight ? c > target : c < target;
      if (needLighter) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    // We take the side that is guaranteed to stay within [min, max]
    final double l = tooLow ? (forLight ? lo : hi) : (forLight ? hi : lo);
    return at(l);
  }

  void _rebuildAccents() {
    final base = baseAccent;
    _accentForLight = adaptAccent(base, forLight: true);
    _accentForDark = adaptAccent(base, forLight: false);
  }

  Color get accentWash => accentColor.withValues(alpha: isLight ? 0.12 : 0.16);
  Color get accentBorder => accentColor.withValues(alpha: isLight ? 0.75 : 0.65);

  /// Highlight on hover over list / menu items
  Color get hoverOverlay => isLight ? Colors.black.withValues(alpha: 0.04) : Colors.white.withValues(alpha: 0.05);
  /// Row highlight at the moment of a touch. With a mouse the row is highlighted by hover, so it is off on desktop;
  /// a phone has no hover, and without it a press would have no feedback at all.
  Color get touchHighlight => AppPlatform.isMobile ? hoverOverlay : Colors.transparent;

  /// Scrollbar thumb color in panels
  Color get scrollbarThumb => isLight ? const Color(0xFFC0C0C8) : const Color(0xFF555555);

  double get radiusMultiplier => radiusMultipliers[_radiusKey] ?? 1.0;
  double radius(double base) => base * radiusMultiplier;
  BorderRadius borderRadius(double base) => BorderRadius.circular(radius(base));

  void setAccentHex(String hex) {
    _accentHex = hex;
    StorageService.saveAccentColorHex(hex);
    _rebuildAccents();
    notifyListeners();
  }

  void setRadiusKey(String key) {
    _radiusKey = key;
    StorageService.saveUiRadius(key);
    notifyListeners();
  }

  void setThemeMode(String mode) {
    _themeMode = mode;
    StorageService.saveThemeMode(mode);
    notifyListeners();
  }

  void reset() {
    setAccentHex(defaultAccentHex);
    setRadiusKey('MD');
    setThemeMode(defaultThemeMode);
  }
}

UiThemeService get uiTheme => UiThemeService.instance;