import 'package:flutter/material.dart';

import '../services/ui_theme_service.dart';

/// Colors of the new design that the theme has no token for: soft plates (chips, steppers, quiet buttons),
/// menu tiles, the grey of captions, row icons and chevrons, the red of destructive actions.
/// Dark values come from the approved concepts; light ones are their counterparts on a light background.
class AppTones {
  const AppTones._();

  static bool get _light => uiTheme.isLight;

  /// A plate: a chip, a stepper button, a quiet button
  static Color get plate => _light ? const Color(0xFFE6E6EE) : const Color(0xFF232328);

  /// A chosen plate: lighter, with an outline [plateOutline]
  static Color get plateOn => _light ? Colors.white : const Color(0xFF34343B);
  static Color get plateOutline => _light ? const Color(0xFF7A7A88) : const Color(0xFF6A6A76);

  /// Text on a plate
  static Color get plateText => _light ? const Color(0xFF3A3A44) : const Color(0xFFCFCFD4);

  /// A menu tile (drop-down lists, the long-press menu) and its outline
  static Color get menu => _light ? Colors.white : const Color(0xFF1A1A1D);
  static Color get menuLine => _light ? const Color(0xFFE0E0E8) : const Color(0xFF2A2A2E);

  /// An icon in a menu row
  static Color get menuIcon => _light ? const Color(0xFF6E6E7C) : const Color(0xFFB8B8C0);

  /// Group captions ("Список", "Застосунок") and the caption in a menu
  static Color get caption => _light ? const Color(0xFF6E6E7C) : const Color(0xFF8E8E96);

  /// The grey line under a row title
  static Color get rowSub => _light ? const Color(0xFF7A7A88) : const Color(0xFF83838B);

  /// A row's line icon
  static Color get rowIcon => _light ? const Color(0xFF4A4A56) : const Color(0xFFC9C9CF);

  /// A row's chevron and the quietest marks ("без оцінки")
  static Color get chevron => _light ? const Color(0xFFB0B0BC) : const Color(0xFF55555C);

  /// Destructive text ("Видалити зі списку") and the plate of a destructive button with its text
  static Color get danger => _light ? const Color(0xFFC0392B) : const Color(0xFFE07A72);
  static Color get dangerPlate => _light ? const Color(0xFFFBE3E1) : const Color(0xFF3A2020);
  static Color get dangerText => _light ? const Color(0xFFB0281C) : const Color(0xFFFF9A90);

  /// The track under a progress bar (on a poster, on a "Продовжити" card)
  static Color get track => _light ? const Color(0xFFDDDDE6) : const Color(0xFF26262B);

  /// An inactive carousel dot, the sheet handle
  static Color get dot => _light ? const Color(0xFFC8C8D2) : const Color(0xFF3A3A40);

  /// The round "play" button on a "Продовжити" card
  static Color get playCircle => _light ? const Color(0xFFE6E6EE) : const Color(0xFF2A2A30);

  /// The accent wash of a chosen pill tab
  static Color get accentWash => uiTheme.accentColor.withValues(alpha: _light ? 0.12 : 0.13);
}
