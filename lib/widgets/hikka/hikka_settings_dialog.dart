import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../models/hikka_models.dart';
import '../../services/hikka_auth.dart';
import '../../services/hikka_images.dart';
import '../../services/hikka_prefs.dart';
import '../../services/ui_theme_service.dart';
import '../../services/watch_service.dart';
import '../../utils/platform_info.dart';
import '../app_animation_kit.dart';
import '../app_ui_kit.dart';
import 'hikka_common.dart';
import 'sources_dialog.dart';

/// Налаштування каталогу: мова назв, показ 18+, джерела перегляду, оновлення даних та очищення кешу зображень.
class HikkaSettingsDialog extends StatefulWidget {
  final double scale;

  /// Скинути кеш відповідей API й перезавантажити відкриті сторінки
  final VoidCallback onRefresh;

  const HikkaSettingsDialog({super.key, required this.scale, required this.onRefresh});

  static Future<void> show(BuildContext context, {required double scale, required VoidCallback onRefresh}) {
    return AppDialogs.show<void>(context, builder: (ctx) => HikkaSettingsDialog(scale: scale, onRefresh: onRefresh));
  }

  /// «12,4 МБ» / «830 КБ» / «0 Б»
  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes Б';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} КБ';
    final mb = bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(mb < 10 ? 1 : 0).replaceAll('.', ',')} МБ';
  }

  @override
  State<HikkaSettingsDialog> createState() => _HikkaSettingsDialogState();
}

class _HikkaSettingsDialogState extends State<HikkaSettingsDialog> {
  final ScrollController _scroll = AppSmoothScrollController();
  int? _cacheBytes;
  bool _cleared = false;
  late final TextEditingController _clientRef = TextEditingController(text: HikkaAuth.instance.customReference);
  late final TextEditingController _clientSecret = TextEditingController(text: HikkaAuth.instance.customSecret);
  Timer? _clientTimer;

  double get _scale => widget.scale;
  HikkaPrefs get _prefs => HikkaPrefs.instance;

  @override
  void initState() {
    super.initState();
    _measure();
  }

  void _clientChanged(String _) {
    _clientTimer?.cancel();
    _clientTimer = Timer(const Duration(milliseconds: 600), _commitClient);
  }

  void _commitClient() => HikkaAuth.instance.setCustomClient(_clientRef.text, _clientSecret.text);

  @override
  void dispose() {
    _clientTimer?.cancel();
    _commitClient();
    _clientRef.dispose();
    _clientSecret.dispose();
    _scroll.dispose();
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
    final mq = MediaQuery.of(context);
    final phone = AppPlatform.isMobile;
    final width = phone ? (mq.size.width - 32).clamp(280.0, 460.0) : 460 * scale;
    final maxHeight = mq.size.height - (phone ? mq.padding.vertical + 32 : 80);
    final pad = phone ? 18.0 : 22 * scale;

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: width,
          constraints: BoxConstraints(maxHeight: maxHeight),
          decoration: BoxDecoration(
            color: uiTheme.bgPrimary,
            borderRadius: uiTheme.borderRadius(20 * scale),
            border: Border.all(color: uiTheme.borderSubtle),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: uiTheme.isLight ? 0.12 : 0.70),
                blurRadius: 36 * scale,
                offset: Offset(0, 10 * scale),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(pad, 8 * scale, pad / 2, 4 * scale),
                child: Row(
                  children: [
                    Expanded(child: Text('Налаштування каталогу', style: hikkaStyle(16 * scale, weight: FontWeight.bold))),
                    HikkaIconButton(icon: Symbols.close_rounded, tooltip: 'Закрити', scale: scale, onTap: () => Navigator.of(context).pop()),
                  ],
                ),
              ),
              Divider(height: 1, color: uiTheme.borderSubtle),
              Flexible(
                child: AppScrollbar(
                  scale: scale,
                  controller: _scroll,
                  child: SingleChildScrollView(
                    controller: _scroll,
                    padding: EdgeInsets.fromLTRB(pad, 18 * scale, pad, 16 * scale),
                    child: ListenableBuilder(
                      listenable: _prefs,
                      builder: (context, _) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _title('Мова назв', hint: 'Якщо назви потрібною мовою немає, показується наступна доступна'),
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
                            title: 'Контент 18+',
                            subtitle: 'Показувати хентай та інші матеріали для дорослих у списках, пошуку й календарі. Лише для повнолітніх.',
                            value: _prefs.allowAdult,
                            onChanged: (v) => _prefs.allowAdult = v,
                          ),
                          SizedBox(height: 22 * scale),
                          _title('Перегляд', hint: 'Де шукати українські озвучки й субтитри та яка якість відео за замовчуванням.'),
                          AppSecondaryButton(
                            scale: scale,
                            expand: false,
                            icon: Symbols.tune_rounded,
                            label: 'Джерела перегляду',
                            onTap: () => SourcesDialog.show(context, scale: scale, registry: WatchService.instance.registry),
                          ),
                          SizedBox(height: 22 * scale),
                          _title('Свій клієнт Hikka', hint: 'Необов’язково. У застосунку вже є вбудований клієнт для входу в акаунт; свій (його створюють на hikka.io, в налаштуваннях у розділі «Застосунки») знадобиться, якщо ключ вбудованого перестворили. Зміни діють при наступному вході.'),
                          AppSearchField(scale: scale, controller: _clientRef, icon: Symbols.badge_rounded, hint: 'Референс клієнта', onChanged: _clientChanged),
                          SizedBox(height: 10 * scale),
                          AppSearchField(scale: scale, controller: _clientSecret, icon: Symbols.key_rounded, hint: 'Ключ клієнта', onChanged: _clientChanged),
                          SizedBox(height: 22 * scale),
                          _title('Дані', hint: 'Каталог бере інформацію з hikka.io. Відповіді зберігаються на кілька хвилин, щоб сторінки відкривались швидко.'),
                          Wrap(
                            spacing: 10 * scale,
                            runSpacing: 10 * scale,
                            children: [
                              AppSecondaryButton(
                                scale: scale,
                                expand: false,
                                icon: Symbols.refresh_rounded,
                                label: 'Оновити дані',
                                onTap: () {
                                  widget.onRefresh();
                                  Navigator.of(context).pop();
                                },
                              ),
                              AppSecondaryButton(
                                scale: scale,
                                expand: false,
                                icon: Symbols.delete_outline_rounded,
                                label: _cleared
                                    ? 'Кеш очищено'
                                    : _cacheBytes == null
                                        ? 'Очистити кеш зображень'
                                        : 'Очистити кеш зображень · ${HikkaSettingsDialog.formatBytes(_cacheBytes!)}',
                                onTap: _clearImages,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
