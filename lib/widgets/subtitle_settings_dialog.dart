import '../services/system_fonts.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:file_picker/file_picker.dart';
import 'package:media_kit/media_kit.dart';
import '../services/storage_service.dart';
import '../services/ui_theme_service.dart';
import '../services/mpv_config.dart';
import 'app_animation_kit.dart';
import 'app_ui_kit.dart';

class SubtitleSettingsDialog extends StatefulWidget {
  final double scale;
  final Player player;

  const SubtitleSettingsDialog({
    super.key,
    required this.scale,
    required this.player,
  });

  static void show(BuildContext context, double scale, Player player) {
    AppDialogs.show(
      context,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (ctx) => SubtitleSettingsDialog(scale: scale, player: player),
    );
  }

  @override
  State<SubtitleSettingsDialog> createState() => _SubtitleSettingsDialogState();
}

class _SubtitleSettingsDialogState extends State<SubtitleSettingsDialog> {
  late String _font;
  late double _fontSize;
  late String _textColor;
  late double _borderSize;
  late String _borderColor;
  late double _shadowOffset;
  late double _marginY;
  late double _bgOpacity;
  late String _assMode;
  List<String> _customFonts = [];

  final List<String> _builtInFonts = SystemFonts.available;

  final Map<String, (String, Color)> _palette = {
    '#FFFFFF': ('Білий', Colors.white),
    '#FFE600': ('Жовтий', const Color(0xFFFFE600)),
    '#00E5FF': ('Блакитний', const Color(0xFF00E5FF)),
    '#00FF66': ('Салатовий', const Color(0xFF00FF66)),
    '#E46767': ('Кораловий', const Color(0xFFE46767)),
    '#FFAA00': ('Помаранчевий', const Color(0xFFFFAA00)),
    '#D8B4FE': ('Бузковий', const Color(0xFFD8B4FE)),
  };

  @override
  void initState() {
    super.initState();
    _font = StorageService.getSubFont();
    _fontSize = StorageService.getSubFontSize();
    _textColor = StorageService.getSubTextColor();
    _borderSize = StorageService.getSubBorderSize();
    _borderColor = StorageService.getSubBorderColor();
    _shadowOffset = StorageService.getSubShadowOffset();
    _marginY = StorageService.getSubMarginY();
    _bgOpacity = StorageService.getSubBgOpacity();
    _assMode = StorageService.getSubAssMode();
    _customFonts = StorageService.getCustomFonts();
  }

  Color _parseHex(String hex) {
    try {
      final clean = hex.replaceAll('#', '').trim();
      return Color(int.parse('FF$clean', radix: 16));
    } catch (_) {
      return Colors.white;
    }
  }

  Future<void> _applyLive() async {
    StorageService.saveSubFont(_font);
    StorageService.saveSubFontSize(_fontSize);
    StorageService.saveSubTextColor(_textColor);
    StorageService.saveSubBorderSize(_borderSize);
    StorageService.saveSubBorderColor(_borderColor);
    StorageService.saveSubShadowOffset(_shadowOffset);
    StorageService.saveSubMarginY(_marginY);
    StorageService.saveSubBgOpacity(_bgOpacity);
    StorageService.saveSubAssMode(_assMode);

    await MpvConfig.applySubtitleStyles(widget.player);
    setState(() {});
  }

  Future<void> _resetDefaults() async {
    _font = SystemFonts.defaultFont;
    _fontSize = 48.0;
    _textColor = '#FFFFFF';
    _borderSize = 5.0;
    _borderColor = '#000000';
    _shadowOffset = 2.0;
    _marginY = 36.0;
    _bgOpacity = 0.0;
    _assMode = 'yes';
    await _applyLive();
  }

  Future<void> _pickCustomFontFile() async {
    try {
      final result = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['ttf', 'otf']);
      if (result != null && result.files.isNotEmpty && result.files.first.path != null) {
        final path = result.files.first.path!;
        final fileName = result.files.first.name.split('.').first;
        StorageService.addCustomFont(path);
        setState(() {
          _customFonts = StorageService.getCustomFonts();
          _font = fileName;
        });
        await _applyLive();
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.scale;
    final allFonts = [..._builtInFonts, ..._customFonts.map((p) => p.split(RegExp(r'[/\\]')).last.split('.').first)];
    final colorInfo = _palette[_textColor.toUpperCase()] ?? ('Власний', _parseHex(_textColor));

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 600 * scale,
          constraints: BoxConstraints(maxHeight: 680 * scale),
          decoration: BoxDecoration(
            color: const Color(0xFF111111),
            borderRadius: uiTheme.borderRadius(uiTheme.radius(20 * scale)),
            border: Border.all(color: const Color(0xFF222222), width: 1.0),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.70), blurRadius: 28 * scale, offset: Offset(0, 10 * scale)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: EdgeInsets.only(left: 24 * scale, right: 18 * scale, top: 18 * scale, bottom: 10 * scale),
                child: Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Вигляд субтитрів', style: TextStyle(fontFamily: 'Arial', color: Colors.white, fontSize: 17 * scale, fontWeight: FontWeight.bold)),
                        SizedBox(height: 2 * scale),
                        Text('Налаштуйте шрифт, кольори та відображення', style: TextStyle(fontFamily: 'Arial', color: uiTheme.textDarkMuted, fontSize: 12 * scale)),
                      ],
                    ),
                    const Spacer(),
                    InkWell(
                      onTap: _resetDefaults,
                      borderRadius: uiTheme.borderRadius(6 * scale),
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8 * scale, vertical: 4 * scale),
                        child: Row(
                          children: [
                            Icon(Symbols.restart_alt_rounded, color: uiTheme.textMuted, size: 16 * scale),
                            SizedBox(width: 4 * scale),
                            Text('Скинути', style: TextStyle(fontFamily: 'Arial', color: uiTheme.textMuted, fontSize: 12 * scale, fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(width: 6 * scale),
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: Icon(Symbols.close_rounded, color: uiTheme.textDarkMuted, size: 20 * scale),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              _buildSubtitlePreview(scale),
              Flexible(
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(horizontal: 24 * scale, vertical: 8 * scale),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeaderLabel(scale, 'Режим стилізації ASS / SSA'),
                      SizedBox(height: 8 * scale),
                      AppSegmentedBar<String>(
                        scale: scale,
                        options: const [
                          AppSegmentOption(value: 'no', label: 'Оригінал (ASS)'),
                          AppSegmentOption(value: 'yes', label: 'Лише діалоги'),
                          AppSegmentOption(value: 'force', label: 'Примусово (Force)'),
                        ],
                        selectedValue: _assMode,
                        onSelected: (val) {
                          _assMode = val;
                          _applyLive();
                        },
                      ),
                      SizedBox(height: 18 * scale),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildHeaderLabel(scale, 'Гарнітура шрифту'),
                          InkWell(
                            onTap: _pickCustomFontFile,
                            borderRadius: uiTheme.borderRadius(6 * scale),
                            child: Row(
                              children: [
                                Icon(Symbols.add_rounded, color: uiTheme.accentColor, size: 16 * scale),
                                SizedBox(width: 2 * scale),
                                Text('Свій шрифт', style: TextStyle(fontFamily: 'Arial', color: uiTheme.accentColor, fontSize: 11.5 * scale, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8 * scale),
                      Wrap(
                        spacing: 8 * scale,
                        runSpacing: 8 * scale,
                        children: allFonts.map((f) {
                          final isCur = _font.toLowerCase() == f.toLowerCase();
                          return GestureDetector(
                            onTap: () { _font = f; _applyLive(); },
                            child: Container(
                              padding: EdgeInsets.symmetric(horizontal: 14 * scale, vertical: 6 * scale),
                              decoration: BoxDecoration(
                                color: isCur ? uiTheme.accentWash : const Color(0xFF161616),
                                borderRadius: uiTheme.borderRadius(14 * scale),
                                border: Border.all(color: isCur ? uiTheme.accentBorder : const Color(0xFF262626)),
                              ),
                              child: Text(f, style: TextStyle(fontFamily: 'Arial', color: isCur ? Colors.white : const Color(0xFFCCCCCC), fontSize: 12 * scale, fontWeight: isCur ? FontWeight.bold : FontWeight.w500)),
                            ),
                          );
                        }).toList(),
                      ),
                      SizedBox(height: 18 * scale),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildHeaderLabel(scale, 'Основний колір'),
                          Text('${colorInfo.$1}  $_textColor', style: TextStyle(fontFamily: 'Arial', color: uiTheme.textDarkMuted, fontSize: 12 * scale)),
                        ],
                      ),
                      SizedBox(height: 10 * scale),
                      Row(
                        children: _palette.entries.map((entry) {
                          final hex = entry.key;
                          final col = entry.value.$2;
                          final isCur = _textColor.toUpperCase() == hex.toUpperCase();
                          return GestureDetector(
                            onTap: () { _textColor = hex; _applyLive(); },
                            child: Container(
                              width: 32 * scale,
                              height: 32 * scale,
                              margin: EdgeInsets.only(right: 12 * scale),
                              decoration: BoxDecoration(
                                color: col,
                                shape: BoxShape.circle,
                                border: Border.all(color: isCur ? uiTheme.accentColor : Colors.transparent, width: isCur ? 2.5 : 1.0),
                              ),
                              child: isCur ? Icon(Symbols.check_rounded, color: Colors.black, size: 18 * scale) : null,
                            ),
                          );
                        }).toList(),
                      ),
                      SizedBox(height: 18 * scale),
                      _buildCleanSlider(scale, label: 'Розмір шрифту', valueText: '${_fontSize.toInt()} px', value: _fontSize, min: 24.0, max: 80.0, onChanged: (v) { _fontSize = v.roundToDouble(); _applyLive(); }),
                      _buildCleanSlider(scale, label: 'Товщина обводки', valueText: '${_borderSize.toStringAsFixed(1)} px', value: _borderSize, min: 0.0, max: 8.0, onChanged: (v) { _borderSize = (v * 10).round() / 10; _applyLive(); }),
                      _buildCleanSlider(scale, label: 'Зсув твердої тіні', valueText: '${_shadowOffset.toStringAsFixed(1)} px', value: _shadowOffset, min: 0.0, max: 6.0, onChanged: (v) { _shadowOffset = (v * 10).round() / 10; _applyLive(); }),
                      _buildCleanSlider(scale, label: 'Відступ від краю (Margin Y)', valueText: '${_marginY.toInt()} px', value: _marginY, min: 10.0, max: 80.0, onChanged: (v) { _marginY = v.roundToDouble(); _applyLive(); }),
                      _buildCleanSlider(scale, label: 'Прозорість фонової підкладки', valueText: '${(_bgOpacity * 100).toInt()}%', value: _bgOpacity, min: 0.0, max: 1.0, onChanged: (v) { _bgOpacity = (v * 20).round() / 20; _applyLive(); }),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 24 * scale, vertical: 14 * scale),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: uiTheme.accentWash,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: uiTheme.borderRadius(uiTheme.radius(10 * scale)),
                          side: BorderSide(color: uiTheme.accentBorder),
                        ),
                        padding: EdgeInsets.symmetric(horizontal: 24 * scale, vertical: 11 * scale),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text('Готово', style: TextStyle(fontFamily: 'Arial', color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13 * scale)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSubtitlePreview(double scale) {
    final txtColor = _parseHex(_textColor);
    final brdColor = _parseHex(_borderSize > 0 ? '#000000' : '#FFFFFF');

    return Container(
      width: double.infinity,
      height: 95 * scale,
      margin: EdgeInsets.symmetric(horizontal: 24 * scale, vertical: 8 * scale),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: uiTheme.borderRadius(uiTheme.radius(14 * scale)),
        border: Border.all(color: const Color(0xFF282828)),
        gradient: const LinearGradient(
          colors: [Color(0xFF1E3C72), Color(0xFF2A5298), Color(0xFFE65C00), Color(0xFFF9D423)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(child: Container(color: Colors.black.withValues(alpha: 0.35))),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.only(bottom: 10 * scale, left: 16 * scale, right: 16 * scale),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 2 * scale),
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: _bgOpacity), borderRadius: uiTheme.borderRadius(4 * scale)),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (_shadowOffset > 0)
                      Transform.translate(
                        offset: Offset(_shadowOffset * scale, _shadowOffset * scale),
                        child: Text(
                          'Зразок тексту субтитрів / Sample Text',
                          style: TextStyle(
                            fontFamily: _font,
                            fontSize: (_fontSize * 0.38) * scale,
                            fontWeight: FontWeight.w600,
                            foreground: Paint()..style = PaintingStyle.stroke..strokeWidth = (_borderSize * 1.6) * scale..color = Colors.black,
                          ),
                        ),
                      ),
                    if (_borderSize > 0)
                      Text(
                        'Зразок тексту субтитрів / Sample Text',
                        style: TextStyle(
                          fontFamily: _font,
                          fontSize: (_fontSize * 0.38) * scale,
                          fontWeight: FontWeight.w600,
                          foreground: Paint()..style = PaintingStyle.stroke..strokeWidth = (_borderSize * 1.6) * scale..color = brdColor,
                        ),
                      ),
                    Text('Зразок тексту субтитрів / Sample Text', style: TextStyle(fontFamily: _font, fontSize: (_fontSize * 0.38) * scale, fontWeight: FontWeight.w600, color: txtColor)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderLabel(double scale, String text) {
    return Text(text, style: TextStyle(fontFamily: 'Arial', color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13 * scale));
  }

  Widget _buildCleanSlider(double scale, {required String label, required String valueText, required double value, required double min, required double max, required ValueChanged<double> onChanged}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 2 * scale),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: TextStyle(fontFamily: 'Arial', color: const Color(0xFFE0E0E0), fontSize: 12.5 * scale, fontWeight: FontWeight.w400)),
              Text(valueText, style: TextStyle(fontFamily: 'Arial', color: uiTheme.textMuted, fontSize: 12 * scale, fontWeight: FontWeight.w500)),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 2.5 * scale,
              activeTrackColor: uiTheme.accentColor,
              inactiveTrackColor: const Color(0xFF282828),
              thumbColor: uiTheme.accentColor,
              thumbShape: DotSliderThumbShape(enabledThumbRadius: 6.5 * scale, innerDotRadius: 2.8 * scale),
              overlayShape: RoundSliderOverlayShape(overlayRadius: 8.0 * scale),
            ),
            child: Slider(value: value.clamp(min, max), min: min, max: max, onChanged: onChanged),
          ),
        ],
      ),
    );
  }
}