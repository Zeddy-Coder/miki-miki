import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../services/source_prefs.dart';
import '../../services/source_registry.dart';
import '../../services/sources/anime_source.dart';
import '../../services/ui_theme_service.dart';
import '../app_animation_kit.dart';
import '../app_ui_kit.dart';
import 'hikka_common.dart';
import 'hikka_watch_dialogs.dart';

/// «Джерела перегляду»: які сайти шукають озвучки й субтитри, найбільша якість, плеєр за замовчуванням,
/// необов'язковий ключ Mikai. Зміни застосовуються одразу; ключ зберігається з невеликою затримкою після набору.
class SourcesDialog extends StatefulWidget {
  final double scale;
  final SourceRegistry registry;

  const SourcesDialog({super.key, required this.scale, required this.registry});

  static Future<void> show(BuildContext context, {required double scale, required SourceRegistry registry}) {
    return AppDialogs.show<void>(context, builder: (ctx) => SourcesDialog(scale: scale, registry: registry));
  }

  /// Відбиток налаштувань, від яких залежить результат пошуку (які сайти й який ключ): змінився — пошук варто повторити
  static String searchSignature(SourceRegistry registry) =>
      '${[for (final s in registry.enabled) s.id].join(',')}|${registry.prefs.mikaiKey}';

  /// Плеєри, які можна вибрати за замовчуванням (порожній — «Авто»: за порядком джерела)
  static const List<String> hosters = ['', 'Moon'];

  @override
  State<SourcesDialog> createState() => _SourcesDialogState();
}

class _SourcesDialogState extends State<SourcesDialog> {
  late final TextEditingController _key = TextEditingController(text: _prefs.mikaiKey);
  late final TextEditingController _moonKey = TextEditingController(text: _prefs.moonKey);
  Timer? _keyTimer;

  double get _scale => widget.scale;
  SourcePrefs get _prefs => widget.registry.prefs;

  @override
  void dispose() {
    _keyTimer?.cancel();
    _commitKey();
    _moonKey.dispose();
    _key.dispose();
    super.dispose();
  }

  void _keyChanged(String _) {
    _keyTimer?.cancel();
    _keyTimer = Timer(const Duration(milliseconds: 600), _commitKey);
  }

  void _commitKey() {
    final v = _key.text.trim();
    if (v != _prefs.mikaiKey) _prefs.mikaiKey = v;
    final m = _moonKey.text.trim();
    if (m != _prefs.moonKey) _prefs.moonKey = m;
  }

  /// Підказка до сайту: порада й опис із самого джерела
  String _hint(AnimeSource s) {
    final lead = switch (s.id) {
      'mikai' => 'Основне джерело: знає команди озвучення й серії. ',
      'uakino' => 'Сайт за Cloudflare, тож із деяких мереж може не відкриватися. ',
      _ => '',
    };
    return '$lead${s.about}'.trim();
  }

  Widget _title(String text, {String? hint}) {
    final scale = _scale;
    return Padding(
      padding: EdgeInsets.only(bottom: 10 * scale),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, style: hikkaStyle(13.5 * scale, weight: FontWeight.bold)),
          if (hint != null)
            Padding(
              padding: EdgeInsets.only(top: 2 * scale),
              child: Text(hint, style: hikkaStyle(11.5 * scale, color: uiTheme.textDarkMuted, height: 1.35)),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scale = _scale;
    return WatchDialogFrame(
      scale: scale,
      title: 'Джерела перегляду',
      icon: Symbols.tune_rounded,
      body: ListenableBuilder(
        listenable: _prefs,
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _title('Сайти', hint: 'Де шукати українські озвучки й субтитри. Вимкнені сайти не опитуються.'),
            for (final s in widget.registry.all) ...[
              HikkaToggleRow(
                scale: scale,
                title: s.name,
                subtitle: _hint(s),
                value: _prefs.isEnabled(s.id),
                onChanged: (v) => _prefs.setEnabled(s.id, v),
              ),
              SizedBox(height: 14 * scale),
            ],
            SizedBox(height: 8 * scale),
            _title('Якість відео', hint: 'Автоматично вибирається не вище за цю. Змінити можна й під час перегляду.'),
            AppSegmentedBar<int>(
              scale: scale,
              selectedValue: _prefs.maxHeight,
              options: [for (final h in SourcePrefs.heights) AppSegmentOption(value: h, label: SourcePrefs.heightLabel(h))],
              onSelected: (v) => _prefs.maxHeight = v,
            ),
            SizedBox(height: 22 * scale),
            _title('Плеєр за замовчуванням', hint: 'Де в серії є Moon, інші плеєри (Ashdi) не пропонуються. Якщо Moon немає, береться наявний.'),
            AppSegmentedBar<String>(
              scale: scale,
              selectedValue: SourcesDialog.hosters.contains(_prefs.hoster) ? _prefs.hoster : '',
              options: [for (final h in SourcesDialog.hosters) AppSegmentOption(value: h, label: h.isEmpty ? 'Авто' : h)],
              onSelected: (v) => _prefs.hoster = v,
            ),
            SizedBox(height: 22 * scale),
            _title('Ключ Mikai API', hint: 'Необов’язково. З ключем — 300 запитів на хвилину замість 60; без нього все працює.'),
            AppSearchField(
              scale: scale,
              controller: _key,
              icon: Symbols.key_rounded,
              hint: 'Вставте ключ, якщо він є',
              onChanged: _keyChanged,
            ),
            SizedBox(height: 22 * scale),
            _title('Свій ключ Moon API', hint: 'Необов’язково: за замовчуванням відео Moon беруться з офіційного API безкоштовним ключем зі служби застосунку. Свій ключ (наприклад, Premium) діятиме замість нього; при збої API — розбір сторінки плеєра.'),
            AppSearchField(
              scale: scale,
              controller: _moonKey,
              icon: Symbols.key_rounded,
              hint: 'Premium-ключ MoonAnime (за потреби)',
              onChanged: _keyChanged,
            ),
            SizedBox(height: 4 * scale),
          ],
        ),
      ),
    );
  }
}
