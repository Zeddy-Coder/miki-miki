import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'player_state_controller.dart';
import 'shortcut_catalog.dart';

/// Handles hotkeys by the [ShortcutCatalog].
/// Uses physical keys, so combinations work in any keyboard layout.
class KeyboardShortcuts {
  KeyboardShortcuts._();

  /// Until a video is opened, only these actions apply
  static const Set<String> _allowedWithoutMedia = {'open_file', 'help', 'fullscreen', 'escape', 'ontop'};

  /// Focus in a text field: we do not intercept player keys
  static bool _isTyping() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return false;
    return ctx.widget is EditableText || ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  static KeyEventResult handle(KeyEvent event, PlayerStateController c) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    if (_isTyping()) return KeyEventResult.ignored;

    final keyboard = HardwareKeyboard.instance;
    // Win+key: system combinations
    if (keyboard.isMetaPressed) return KeyEventResult.ignored;

    final def = ShortcutCatalog.find(
      c.keyScheme,
      event.physicalKey,
      ctrl: keyboard.isControlPressed,
      shift: keyboard.isShiftPressed,
      alt: keyboard.isAltPressed,
    );
    if (def == null) return KeyEventResult.ignored;
    if (c.isHome && !_allowedWithoutMedia.contains(def.id)) return KeyEventResult.ignored;

    // Holding a key repeats only "continuous" actions (seek, volume…)
    if (event is KeyRepeatEvent && !def.repeat) return KeyEventResult.handled;

    c.handleInteraction();
    if (def.id == 'escape') {
      return c.actions.escape() ? KeyEventResult.handled : KeyEventResult.ignored;
    }
    c.actions.run(def.id);
    return KeyEventResult.handled;
  }
}
