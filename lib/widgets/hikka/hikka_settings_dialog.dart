import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../models/hikka_models.dart';
import '../../services/hikka_images.dart';
import '../../services/hikka_prefs.dart';
import '../../services/ui_theme_service.dart';
import '../../services/watch_service.dart';
import '../settings_kit.dart';
import '../../services/hikka_nav.dart';
import 'sources_dialog.dart';

/// Content of the main settings' "Каталог" tab: title language, second title, 18+, watch sources, own Hikka client,
/// data refresh and the image cache. Changes apply immediately.
class HikkaCatalogSettings extends StatefulWidget {
  final double scale;

  const HikkaCatalogSettings({super.key, required this.scale});

  /// "12,4 МБ" / "830 КБ" / "0 Б"
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
    // Already decoded images are reset too, so the new load really goes to the network
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    if (!mounted) return;
    setState(() {
      _cacheBytes = 0;
      _cleared = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scale = _scale;
    return ListenableBuilder(
      listenable: _prefs,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingsGroup(
            scale: scale,
            label: 'Назви',
            rows: [
              SettingsChoiceRow<HikkaTitleLang>(
                scale: scale,
                icon: Symbols.translate_rounded,
                title: 'Мова назв',
                subtitle: 'Якщо потрібної назви немає, показується наступна доступна',
                options: const [(HikkaTitleLang.ua, 'Українська'), (HikkaTitleLang.en, 'English'), (HikkaTitleLang.ja, 'Ромаджі')],
                value: _prefs.titleLang,
                onChanged: (v) => _prefs.titleLang = v,
              ),
              SettingsToggleRow(
                scale: scale,
                icon: Symbols.title_rounded,
                title: 'Друга назва',
                subtitle: 'Додаткова назва під заголовком тайтла',
                value: _prefs.showSecondary,
                onChanged: (v) => _prefs.showSecondary = v,
              ),
              if (_prefs.showSecondary)
                SettingsChoiceRow<HikkaTitleLang>(
                  scale: scale,
                  icon: Symbols.language_rounded,
                  title: 'Мова другої назви',
                  options: const [(HikkaTitleLang.ua, 'Українська'), (HikkaTitleLang.en, 'English'), (HikkaTitleLang.ja, 'Ромаджі')],
                  value: _prefs.secondaryLang,
                  onChanged: (v) => _prefs.secondaryLang = v,
                ),
            ],
          ),
          SettingsGroup(
            scale: scale,
            label: 'Вміст',
            rows: [
              SettingsToggleRow(
                scale: scale,
                icon: Symbols.explicit_rounded,
                title: 'Контент 18+',
                subtitle: 'Показувати у списках, пошуку й календарі. Лише для повнолітніх',
                value: _prefs.allowAdult,
                onChanged: (v) => _prefs.allowAdult = v,
              ),
            ],
          ),
          SourcesSettings(scale: scale, registry: WatchService.instance.registry, heading: false),
          SettingsGroup(
            scale: scale,
            label: 'Дані',
            hint: 'Оновлення даних каталогу та очищення кешу зображень',
            rows: [
              SettingsRow(
                scale: scale,
                icon: Symbols.refresh_rounded,
                title: 'Оновити дані',
                subtitle: 'Скидає кеш відповідей і перезавантажує відкриті сторінки',
                onTap: () => HikkaNav.instance.refreshAll?.call(),
              ),
              if (_cacheBytes != null)
                SettingsStorageBar(
                  scale: scale,
                  parts: [('Обкладинки', _cacheBytes!, uiTheme.isLight ? const Color(0xFF55555F) : const Color(0xFFE6E6EA))],
                  total: HikkaImageStore.instance.maxBytes,
                  format: HikkaCatalogSettings.formatBytes,
                  totalLabel: 'Ліміт ${HikkaCatalogSettings.formatBytes(HikkaImageStore.instance.maxBytes)}',
                ),
              SettingsRow(
                scale: scale,
                icon: Symbols.delete_outline_rounded,
                title: _cleared ? 'Кеш очищено' : 'Очистити кеш зображень',
                subtitle: _cacheBytes == null ? null : 'Зараз зайнято ${HikkaCatalogSettings.formatBytes(_cacheBytes!)}',
                onTap: _clearImages,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
