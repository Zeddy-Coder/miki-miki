import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'player_state_controller.dart';
import 'shortcut_catalog.dart';

/// Обробка гарячих клавіш за каталогом [ShortcutCatalog].
/// Використовує фізичні клавіші, тому комбінації працюють в будь-якій розкладці.
class KeyboardShortcuts {
  KeyboardShortcuts._();

  /// Коли відео ще не відкрито, діють лише ці дії
  static const Set<String> _allowedWithoutMedia = {'open_file', 'help', 'fullscreen', 'escape', 'ontop'};

  /// Фокус у текстовому полі — клавіші плеєра не перехоплюємо
  static bool _isTyping() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return false;
    return ctx.widget is EditableText || ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  static KeyEventResult handle(KeyEvent event, PlayerStateController c) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    if (_isTyping()) return KeyEventResult.ignored;

    final keyboard = HardwareKeyboard.instance;
    // Win+клавіша — системні комбінації
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

    // Утримання клавіші повторює лише «безперервні» дії (перемотка, гучність…)
    if (event is KeyRepeatEvent && !def.repeat) return KeyEventResult.handled;

    c.handleInteraction();
    if (def.id == 'escape') {
      return c.actions.escape() ? KeyEventResult.handled : KeyEventResult.ignored;
    }
    c.actions.run(def.id);
    return KeyEventResult.handled;
  }
}
