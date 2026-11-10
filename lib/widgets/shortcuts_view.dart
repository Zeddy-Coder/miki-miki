import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../services/player_state_controller.dart';
import '../services/shortcut_catalog.dart';
import '../services/ui_theme_service.dart';
import 'app_animation_kit.dart';
import 'app_ui_kit.dart';

/// Група довідки: назва групи й дії, що мають видимі комбінації у вибраній схемі.
class ShortcutSection {
  const ShortcutSection(this.group, this.items);

  final ShortcutGroup group;
  final List<ShortcutDef> items;

  /// Приблизна висота картки в «рядках» (заголовок рахується як два)
  int get weight => items.length + 2;
}

IconData _groupIcon(ShortcutGroup group) {
  switch (group) {
    case ShortcutGroup.playback:
      return Symbols.play_circle_rounded;
    case ShortcutGroup.seek:
      return Symbols.fast_forward_rounded;
    case ShortcutGroup.speed:
      return Symbols.speed_rounded;
    case ShortcutGroup.audio:
      return Symbols.volume_up_rounded;
    case ShortcutGroup.subtitles:
      return Symbols.subtitles_rounded;
    case ShortcutGroup.picture:
      return Symbols.tune_rounded;
    case ShortcutGroup.anime4k:
      return Symbols.auto_awesome_rounded;
    case ShortcutGroup.window:
      return Symbols.desktop_windows_rounded;
  }
}

/// «1 дія», «2 дії», «5 дій»
String _actionsCount(int n) {
  final mod10 = n % 10;
  final mod100 = n % 100;
  if (mod10 == 1 && mod100 != 11) return '$n дія';
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return '$n дії';
  return '$n дій';
}

/// Довідка з гарячих клавіш: картки за групами, у кожній — назва дії й кнопки клавіатури.
/// Не прокручується сама, тому підходить і для окремого вікна, і для вкладки налаштувань.
/// Дані беруться з [ShortcutCatalog] — того самого списку, за яким працює обробник клавіш.
class ShortcutsView extends StatelessWidget {
  const ShortcutsView({super.key, required this.scale, required this.scheme, this.query = ''});

  final double scale;
  final KeyScheme scheme;

  /// Пошук за назвою дії, групою або клавішею («ctrl 1», «пауза», «seek»)
  final String query;

  /// Від якої ширини картки стають у дві колонки
  static const double twoColumnsFrom = 640;

  /// Групи довідки для схеми [scheme], відфільтровані за [query]
  static List<ShortcutSection> sections(KeyScheme scheme, String query) {
    final grouped = ShortcutCatalog.grouped(scheme);
    final out = <ShortcutSection>[];
    for (final group in ShortcutGroup.values) {
      final items = (grouped[group] ?? const <ShortcutDef>[]).where((d) => matches(d, scheme, query)).toList();
      if (items.isNotEmpty) out.add(ShortcutSection(group, items));
    }
    return out;
  }

  /// Інші назви клавіш, які можна вписати в пошук (ключ — підпис клавіші малими літерами)
  static const Map<String, List<String>> _keyAliases = {
    'space': ['пробіл'],
    'enter': ['ентер'],
    'backspace': ['бекспейс'],
    '←': ['left', 'вліво', 'ліворуч'],
    '→': ['right', 'вправо', 'праворуч'],
    '↑': ['up', 'вгору'],
    '↓': ['down', 'вниз'],
    'pgup': ['pageup', 'page'],
    'pgdn': ['pagedown', 'page'],
  };

  /// Слова запиту. Клавіші розділяють пробіл і «+»: «ctrl 1», «ctrl+1» і «ctrl + 1» — те саме.
  /// «+» наприкінці («ctrl++», «ctrl +») — це клавіша «+», а «ctrl+» — ще не дописана комбінація.
  /// Мінус Unicode («−») зводиться до звичайного.
  static List<String> queryWords(String query) {
    final parts = query.trim().toLowerCase().replaceAll('−', '-').split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    final out = <String>[];
    for (var i = 0; i < parts.length; i++) {
      final part = parts[i];
      out.addAll(part.split('+').where((w) => w.isNotEmpty));
      final last = i == parts.length - 1;
      if (last && (part == '+' || part.endsWith('++'))) out.add('+');
    }
    return out;
  }

  /// Слово запиту, що збігається з підписом клавіші: повністю, початком («ctr» → Ctrl) або псевдонімом
  static bool _hitsCap(String word, String cap) {
    bool same(String name) => name == word || (word.length > 1 && name.startsWith(word));
    return same(cap) || (_keyAliases[cap]?.any(same) ?? false);
  }

  /// Слова запиту шукаються в назві дії, групі та англійському ідентифікаторі (підрядок), а ті,
  /// яких там немає, — серед клавіш, причому всі в межах однієї комбінації: «ctrl 1» знаходить
  /// лише Ctrl+1, а не «Звук раніше на 0,1 с». Односимвольні слова («1», «a») шукаються лише
  /// серед клавіш. Приховані комбінації не враховуються.
  static bool matches(ShortcutDef def, KeyScheme scheme, String query) {
    final words = queryWords(query);
    if (words.isEmpty) return true;
    final text = [def.label, def.group.title, def.id.replaceAll('_', ' ')].join(' ').toLowerCase().replaceAll('−', '-');
    final keyWords = [
      for (final w in words)
        if (w.length < 2 || !text.contains(w)) w,
    ];
    if (keyWords.isEmpty) return true;
    for (final chord in def.chordsFor(scheme)) {
      if (chord.hidden) continue;
      final caps = chord.caps.map((c) => c.toLowerCase().replaceAll('−', '-')).toList();
      if (keyWords.every((w) => caps.any((cap) => _hitsCap(w, cap)))) return true;
    }
    return false;
  }

  /// Скільки перших груп іде в ліву колонку, щоб колонки вийшли приблизно однакової висоти
  static int splitIndex(List<ShortcutSection> sections) {
    if (sections.length < 2) return sections.length;
    final total = sections.fold<int>(0, (sum, s) => sum + s.weight);
    var left = 0;
    var best = 1;
    var bestDiff = 1 << 30;
    for (var i = 0; i < sections.length - 1; i++) {
      left += sections[i].weight;
      final diff = (total - 2 * left).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        best = i + 1;
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final list = sections(scheme, query);
    if (list.isEmpty) {
      return SizedBox(
        height: 180 * scale,
        child: AppEmptyState(
          scale: scale,
          icon: Symbols.search_off_rounded,
          text: 'Нічого не знайдено за запитом «${query.trim()}»',
        ),
      );
    }

    Widget column(Iterable<ShortcutSection> items) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final s in items) ...[
              _GroupCard(key: ValueKey(s.group), scale: scale, scheme: scheme, section: s),
              SizedBox(height: 12 * scale),
            ],
          ],
        );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < twoColumnsFrom * scale || list.length < 2) {
          return column(list);
        }
        final split = splitIndex(list);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: column(list.take(split))),
            SizedBox(width: 14 * scale),
            Expanded(child: column(list.skip(split))),
          ],
        );
      },
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({super.key, required this.scale, required this.scheme, required this.section});

  final double scale;
  final KeyScheme scheme;
  final ShortcutSection section;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      scale: scale,
      padding: EdgeInsets.fromLTRB(14 * scale, 12 * scale, 14 * scale, 4 * scale),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 28 * scale,
                height: 28 * scale,
                decoration: BoxDecoration(
                  color: uiTheme.accentWash,
                  borderRadius: uiTheme.borderRadius(8 * scale),
                ),
                child: Icon(
                  _groupIcon(section.group),
                  color: uiTheme.accentColor,
                  size: 16 * scale,
                  weight: 300,
                  opticalSize: 24,
                ),
              ),
              SizedBox(width: 10 * scale),
              Expanded(
                child: Text(
                  section.group.title,
                  style: TextStyle(
                    fontFamily: 'Arial',
                    color: uiTheme.textPrimary,
                    fontSize: 13.5 * scale,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Text(
                '${section.items.length}',
                style: TextStyle(fontFamily: 'Arial', color: uiTheme.textDarkMuted, fontSize: 11 * scale),
              ),
            ],
          ),
          SizedBox(height: 6 * scale),
          for (int i = 0; i < section.items.length; i++) ...[
            if (i > 0) Container(height: 1, color: uiTheme.borderSubtle.withValues(alpha: 0.6)),
            _ShortcutRow(scale: scale, scheme: scheme, def: section.items[i]),
          ],
        ],
      ),
    );
  }
}

class _ShortcutRow extends StatelessWidget {
  const _ShortcutRow({required this.scale, required this.scheme, required this.def});

  final double scale;
  final KeyScheme scheme;
  final ShortcutDef def;

  @override
  Widget build(BuildContext context) {
    final chords = def.chordsFor(scheme).where((c) => !c.hidden).toList();

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 7 * scale),
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                def.label,
                style: TextStyle(fontFamily: 'Arial', color: uiTheme.textPrimary, fontSize: 12.5 * scale),
              ),
            ),
            SizedBox(width: 12 * scale),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.52),
              child: Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 5 * scale,
                runSpacing: 5 * scale,
                children: [
                  for (int i = 0; i < chords.length; i++) ...[
                    if (i > 0)
                      Text(
                        '/',
                        style: TextStyle(fontFamily: 'Arial', color: uiTheme.textDarkMuted, fontSize: 11 * scale),
                      ),
                    AppKeyCombo(scale: scale, keys: chords[i].caps, accent: chords[i].scope != KeyScope.both),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Вікно «Гарячі клавіші»: відкривається клавішею `?` або F1. Схему клавіш можна змінити тут же —
/// вона застосовується одразу.
class ShortcutsDialog extends StatefulWidget {
  const ShortcutsDialog({super.key, required this.scale, required this.controller});

  final double scale;
  final PlayerStateController controller;

  static bool _isOpen = false;

  static Future<void> show(BuildContext context, double scale, PlayerStateController controller) async {
    if (_isOpen) return;
    _isOpen = true;
    try {
      await AppDialogs.show<void>(
        context,
        barrierColor: Colors.black.withValues(alpha: 0.75),
        builder: (_) => ShortcutsDialog(scale: scale, controller: controller),
      );
    } finally {
      _isOpen = false;
    }
  }

  @override
  State<ShortcutsDialog> createState() => _ShortcutsDialogState();
}

class _ShortcutsDialogState extends State<ShortcutsDialog> {
  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  late KeyScheme _scheme = widget.controller.keyScheme;
  String _query = '';

  @override
  void dispose() {
    // Маршрут могли прибрати без завершення Future (наприклад, при закритті навігатора)
    ShortcutsDialog._isOpen = false;
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _setQuery(String value) => setState(() => _query = value);

  void _close() => Navigator.of(context).pop();

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.physicalKey;
    final keyboard = HardwareKeyboard.instance;

    if (key == PhysicalKeyboardKey.escape) {
      // Перший Esc очищає пошук, другий закриває вікно
      if (_search.text.isNotEmpty) {
        _search.clear();
        _setQuery('');
      } else {
        _close();
      }
      return KeyEventResult.handled;
    }
    if (key == PhysicalKeyboardKey.keyF && keyboard.isControlPressed) {
      _searchFocus.requestFocus();
      return KeyEventResult.handled;
    }
    // Під час введення в поле пошуку решта клавіш — звичайний текст
    if (_searchFocus.hasFocus) return KeyEventResult.ignored;
    if (key == PhysicalKeyboardKey.f1 || (key == PhysicalKeyboardKey.slash && keyboard.isShiftPressed)) {
      _close();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.scale;
    final screen = MediaQuery.sizeOf(context);
    final width = math.min(900 * scale, screen.width - 40 * scale);
    final height = math.min(680 * scale, screen.height - 40 * scale);
    final total = ShortcutCatalog.grouped(_scheme).values.fold<int>(0, (sum, list) => sum + list.length);

    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: Center(
        child: AppModalShell(
          scale: scale,
          width: width,
          height: height,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(scale, total),
              Padding(
                padding: EdgeInsets.fromLTRB(24 * scale, 0, 24 * scale, 10 * scale),
                child: _buildControls(scale),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(24 * scale, 0, 24 * scale, 12 * scale),
                child: _buildLegend(scale),
              ),
              Container(height: 1, color: uiTheme.borderSubtle),
              Expanded(
                child: AppScrollEdgeFade(
                  scale: scale,
                  child: AppSmoothScrollView(
                    padding: EdgeInsets.fromLTRB(24 * scale, 16 * scale, 24 * scale, 28 * scale),
                    child: ShortcutsView(scale: scale, scheme: _scheme, query: _query),
                  ),
                ),
              ),
              Container(height: 1, color: uiTheme.borderSubtle),
              _buildFooter(scale),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(double scale, int total) {
    return Padding(
      padding: EdgeInsets.fromLTRB(24 * scale, 20 * scale, 16 * scale, 14 * scale),
      child: Row(
        children: [
          Container(
            width: 40 * scale,
            height: 40 * scale,
            decoration: BoxDecoration(
              color: uiTheme.accentWash,
              borderRadius: uiTheme.borderRadius(12 * scale),
              border: Border.all(color: uiTheme.accentBorder.withValues(alpha: 0.5)),
            ),
            child: Icon(Symbols.keyboard_rounded, color: uiTheme.accentColor, size: 22 * scale, weight: 300, opticalSize: 24),
          ),
          SizedBox(width: 14 * scale),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Гарячі клавіші',
                  style: TextStyle(
                    fontFamily: 'Arial',
                    color: uiTheme.textPrimary,
                    fontSize: 17 * scale,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 2 * scale),
                Text(
                  '${_actionsCount(total)} · працюють в будь-якій розкладці, української чи англійської',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: 'Arial', color: uiTheme.textDarkMuted, fontSize: 12 * scale),
                ),
              ],
            ),
          ),
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            splashColor: Colors.transparent,
            highlightColor: uiTheme.touchHighlight,
            icon: Icon(Symbols.close_rounded, color: uiTheme.textDarkMuted, size: 20 * scale),
            onPressed: _close,
          ),
        ],
      ),
    );
  }

  Widget _buildControls(double scale) {
    final schemeBar = AppSegmentedBar<KeyScheme>(
      scale: scale,
      options: [for (final s in KeyScheme.values) AppSegmentOption(value: s, label: s.title)],
      selectedValue: _scheme,
      onSelected: (s) {
        widget.controller.setKeyScheme(s);
        setState(() => _scheme = s);
      },
    );
    final searchField = AppSearchField(
      scale: scale,
      controller: _search,
      focusNode: _searchFocus,
      hint: 'Пошук за дією або клавішею (Ctrl+F)',
      onChanged: _setQuery,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 560 * scale) {
          return Row(
            children: [
              SizedBox(width: 280 * scale, child: schemeBar),
              SizedBox(width: 12 * scale),
              Expanded(child: searchField),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [schemeBar, SizedBox(height: 10 * scale), searchField],
        );
      },
    );
  }

  Widget _buildLegend(double scale) {
    return Row(
      children: [
        Expanded(
          child: Text(
            _scheme.summary,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontFamily: 'Arial', color: uiTheme.textMuted, fontSize: 11.5 * scale),
          ),
        ),
        SizedBox(width: 12 * scale),
        AppKeyCap(scale: scale, text: 'J', accent: true),
        SizedBox(width: 6 * scale),
        Text(
          'діє лише в цій схемі',
          style: TextStyle(fontFamily: 'Arial', color: uiTheme.textDarkMuted, fontSize: 11.5 * scale),
        ),
      ],
    );
  }

  Widget _buildFooter(double scale) {
    return Padding(
      padding: EdgeInsets.fromLTRB(24 * scale, 12 * scale, 24 * scale, 14 * scale),
      child: Row(
        children: [
          AppKeyCombo(scale: scale, keys: const ['Esc']),
          SizedBox(width: 6 * scale),
          Text('або', style: TextStyle(fontFamily: 'Arial', color: uiTheme.textDarkMuted, fontSize: 11.5 * scale)),
          SizedBox(width: 6 * scale),
          AppKeyCombo(scale: scale, keys: const ['F1']),
          SizedBox(width: 8 * scale),
          Expanded(
            child: Text(
              'закрити довідку',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: 'Arial', color: uiTheme.textDarkMuted, fontSize: 11.5 * scale),
            ),
          ),
          AppAccentButton(scale: scale, label: 'Готово', onTap: _close),
        ],
      ),
    );
  }
}
