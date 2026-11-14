import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../models/hikka_models.dart';
import '../../services/hikka_images.dart';
import '../../services/hikka_prefs.dart';
import '../../services/ui_theme_service.dart';
import '../../services/watch_service.dart';
import '../app_ui_kit.dart';
import '../../services/hikka_nav.dart';
import 'hikka_common.dart';
import 'sources_dialog.dart';

/// Вміст вкладки «Каталог» основних налаштувань: мова назв, друга назва, 18+, джерела перегляду, свій клієнт Hikka,
/// оновлення даних і кеш зображень. Зміни застосовуються одразу.
class HikkaCatalogSettings extends StatefulWidget {
  final double scale;

  const HikkaCatalogSettings({super.key, required this.scale});

  /// «12,4 МБ» / «830 КБ» / «0 Б»
  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes Б';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} КБ';
    final mb = bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(mb < 10 ? 1 : 0).replaceAll('.', ',')} МБ';
  }

  @override
  State<HikkaCatalogSettings> createState() => _HikkaCatalogSettingsState();
}

class _HikkaCatalogSettingsState extends State<HikkaCatalogSettings> {
  int? _cacheBytes;
  bool _cleared = false;

  double get _scale => widget.scale;
  HikkaPrefs get _prefs => HikkaPrefs.instance;

  @override
  void initState() {
    super.initState();
    _measure();
  }


  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _measure() async {
    final size = await HikkaImageStore.instance.diskSize();
    if (mounted) setState(() => _cacheBytes = size);
  }

  Future<void> _clearImages() async {
    await HikkaImageStore.instance.clear();
    // Уже декодовані картинки теж скидаємо, щоб нове завантаження справді пішло з мережі
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    if (!mounted) return;
    setState(() {
      _cacheBytes = 0;
      _cleared = true;
    });
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
    return ListenableBuilder(
      listenable: _prefs,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title('Мова назв', hint: 'Якщо потрібної назви немає, показується наступна доступна'),
          AppSegmentedBar<HikkaTitleLang>(
            scale: scale,
            selectedValue: _prefs.titleLang,
            options: const [
              AppSegmentOption(value: HikkaTitleLang.ua, label: 'Українська'),
              AppSegmentOption(value: HikkaTitleLang.en, label: 'English'),
              AppSegmentOption(value: HikkaTitleLang.ja, label: 'Ромаджі'),
            ],
            onSelected: (v) => _prefs.titleLang = v,
          ),
          SizedBox(height: 22 * scale),
          HikkaToggleRow(
            scale: scale,
            title: 'Друга назва',
            subtitle: 'Додаткова назва під заголовком тайтла',
            value: _prefs.showSecondary,
            onChanged: (v) => _prefs.showSecondary = v,
          ),
          if (_prefs.showSecondary) ...[
            SizedBox(height: 12 * scale),
            AppSegmentedBar<HikkaTitleLang>(
              scale: scale,
              selectedValue: _prefs.secondaryLang,
              options: const [
                AppSegmentOption(value: HikkaTitleLang.ua, label: 'Українська'),
                AppSegmentOption(value: HikkaTitleLang.en, label: 'English'),
                AppSegmentOption(value: HikkaTitleLang.ja, label: 'Ромаджі'),
              ],
              onSelected: (v) => _prefs.secondaryLang = v,
            ),
          ],
          SizedBox(height: 22 * scale),
          HikkaToggleRow(
            scale: scale,
            title: 'Контент 18+',
            subtitle: 'Показувати у списках, пошуку й календарі. Лише для повнолітніх',
            value: _prefs.allowAdult,
            onChanged: (v) => _prefs.allowAdult = v,
          ),
          SizedBox(height: 22 * scale),
          SourcesSettings(scale: scale, registry: WatchService.instance.registry, heading: false),
          SizedBox(height: 22 * scale),
          _title('Дані', hint: 'Оновлення даних каталогу та очищення кешу зображень'),
          Wrap(
            spacing: 10 * scale,
            runSpacing: 10 * scale,
            children: [
              AppSecondaryButton(
                scale: scale,
                expand: false,
                icon: Symbols.refresh_rounded,
                label: 'Оновити дані',
                onTap: () => HikkaNav.instance.refreshAll?.call(),
              ),
              AppSecondaryButton(
                scale: scale,
                expand: false,
                icon: Symbols.delete_outline_rounded,
                label: _cleared
                    ? 'Кеш очищено'
                    : _cacheBytes == null
                        ? 'Очистити кеш зображень'
                        : 'Очистити кеш зображень · ${HikkaCatalogSettings.formatBytes(_cacheBytes!)}',
                onTap: _clearImages,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
