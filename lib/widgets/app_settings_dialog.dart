import 'dart:io';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:file_picker/file_picker.dart';

import '../constants/app_constants.dart';
import '../constants/app_identity.dart';
import '../services/app_diagnostics.dart';
import '../services/app_updater.dart';
import '../services/system_controls.dart';
import '../services/anime4k_service.dart';
import '../services/app_log.dart';
import '../services/log_export.dart';
import '../services/orientation_policy.dart';
import '../services/storage_service.dart';
import '../services/ui_theme_service.dart';
import '../services/mpv_config.dart';
import '../services/player_state_controller.dart';
import '../services/shortcut_catalog.dart';
import 'app_ui_kit.dart';
import 'app_animation_kit.dart';
import 'shortcuts_view.dart';
import '../utils/platform_info.dart';

class AppSettingsDialog extends StatefulWidget {
  final double scale;
  final PlayerStateController controller;

  /// Вкладка, з якої відкривається вікно (див. [tabDeveloper], [tabAbout])
  final int initialTab;

  /// Вкладка навігації замість вікна: заповнює відведене місце, без «Закрити» і «Готово»
  final bool embedded;

  /// Індекси вкладок, до яких можна перейти з інших екранів
  static const int tabDeveloper = 5;
  static const int tabAbout = 6;

  const AppSettingsDialog({
    super.key,
    required this.scale,
    required this.controller,
    this.initialTab = 0,
    this.embedded = false,
  });

  static void show(BuildContext context, double scale, PlayerStateController controller, {int initialTab = 0}) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Settings',
      barrierColor: Colors.black.withValues(alpha: 0.75),
      transitionDuration: AppAnim.medium,
      pageBuilder: (ctx, anim1, anim2) => AppSettingsDialog(scale: scale, controller: controller, initialTab: initialTab),
      transitionBuilder: AppDialogTransition.build,
    );
  }

  @override
  State<AppSettingsDialog> createState() => _AppSettingsDialogState();
}

class _AppSettingsDialogState extends State<AppSettingsDialog> {
  late int _activeTab = widget.initialTab;
  final TextEditingController _tmdbKey = TextEditingController(text: StorageService.getTmdbKey());
  bool _isResetting = false;

  // Вигляд
  late String _themeMode;
  late String _initialThemeMode;

  // Субтитри
  late String _font;
  late double _fontSize;
  late String _textColor;
  late double _borderSize;
  late double _shadowOffset;
  late double _marginY;
  late double _bgOpacity;
  late String _assMode;
  late String _defaultSubLang;
  late bool _subtitlesEnabled;
  late List<String> _subLangPriorities;

  // Відтворення
  late bool _autoplayNext;
  late double _defaultSpeed;
  late int _seekStep;
  late bool _holdToSpeed;
  late bool _seekButtons;
  late bool _mobileSeekButtons;
  late bool _doubleTapSeek;
  late double _holdRate;
  late bool _autoSkip;
  late PlayerOrientation _playerOrientation;

  // Звук
  late bool _pitchCorrection;
  late String _defaultAudioLang;
  late List<String> _audioLangPriorities;

  // Anime4K
  late bool _a4kEnabled;
  late Anime4kMode _a4kMode;
  late Anime4kQuality _a4kQuality;
  late int _a4kSkipHeight;

  // Гарячі клавіші
  late KeyScheme _keyScheme;
  final TextEditingController _hotkeysSearch = TextEditingController();
  String _hotkeysQuery = '';

  // Початкові знімки для відстеження змін
  late String _initialFont;
  late double _initialFontSize;
  late String _initialTextColor;
  late double _initialBorderSize;
  late double _initialShadowOffset;
  late double _initialMarginY;
  late double _initialBgOpacity;
  late String _initialAssMode;
  late String _initialDefaultSubLang;
  late bool _initialSubtitlesEnabled;
  late List<String> _initialSubLangPriorities;

  late bool _initialAutoplayNext;
  late double _initialDefaultSpeed;
  late int _initialSeekStep;
  late bool _initialHoldToSpeed;
  late bool _initialSeekButtons;
  late bool _initialMobileSeekButtons;
  late bool _initialDoubleTapSeek;
  late double _initialHoldRate;
  late bool _initialAutoSkip;
  late PlayerOrientation _initialPlayerOrientation;

  late bool _initialPitchCorrection;
  late String _initialDefaultAudioLang;
  late List<String> _initialAudioLangPriorities;

  late bool _initialA4kEnabled;
  late Anime4kMode _initialA4kMode;
  late Anime4kQuality _initialA4kQuality;
  late int _initialA4kSkipHeight;
  late KeyScheme _initialKeyScheme;

  final List<String> _builtInFonts = ['Trebuchet MS', 'Arial', 'Roboto', 'Segoe UI', 'Tahoma', 'Consolas'];

  @override
  void initState() {
    super.initState();
    _loadFromStorage();
    _saveInitialSnapshot();
  }

  @override
  void dispose() {
    _hotkeysSearch.dispose();
    _tmdbKey.dispose();
    super.dispose();
  }

  void _loadFromStorage() {
    _themeMode = StorageService.getThemeMode(fallback: 'dark');

    _font = StorageService.getSubFont();
    _fontSize = StorageService.getSubFontSize();
    _textColor = StorageService.getSubTextColor();
    _borderSize = StorageService.getSubBorderSize();
    _shadowOffset = StorageService.getSubShadowOffset();
    _marginY = StorageService.getSubMarginY();
    _bgOpacity = StorageService.getSubBgOpacity();
    _assMode = StorageService.getSubAssMode();
    _defaultSubLang = StorageService.getDefaultSubLang();
    _subtitlesEnabled = _defaultSubLang != 'no';
    _subLangPriorities = StorageService.getSubLangPriorities();

    _autoplayNext = StorageService.getAutoplayNext();
    _defaultSpeed = StorageService.getDefaultPlaybackSpeed();
    _seekStep = StorageService.getSeekStep();
    _holdToSpeed = StorageService.getHoldToSpeedEnabled();
    _seekButtons = StorageService.getSeekButtons();
    _mobileSeekButtons = StorageService.getMobileSeekButtons();
    _doubleTapSeek = StorageService.getDoubleTapSeek();
    _holdRate = StorageService.getHoldToSpeedRate();
    _autoSkip = StorageService.getAutoSkipChapters();
    _playerOrientation = PlayerOrientation.parse(StorageService.getPlayerOrientation());

    _pitchCorrection = StorageService.getPitchCorrection();
    _defaultAudioLang = StorageService.getDefaultAudioLang();
    _audioLangPriorities = StorageService.getAudioLangPriorities();

    // Anime4K і схема клавіш можуть змінюватися поза діалогом (меню, Ctrl+1…6) — беремо живий стан
    final a4k = widget.controller.anime4k;
    _a4kEnabled = a4k.enabled;
    _a4kMode = a4k.mode;
    _a4kQuality = a4k.quality;
    _a4kSkipHeight = a4k.skipHeight;
    _keyScheme = widget.controller.keyScheme;
  }

  void _saveInitialSnapshot() {
    _initialThemeMode = _themeMode;

    _initialFont = _font;
    _initialFontSize = _fontSize;
    _initialTextColor = _textColor;
    _initialBorderSize = _borderSize;
    _initialShadowOffset = _shadowOffset;
    _initialMarginY = _marginY;
    _initialBgOpacity = _bgOpacity;
    _initialAssMode = _assMode;
    _initialDefaultSubLang = _defaultSubLang;
    _initialSubtitlesEnabled = _subtitlesEnabled;
    _initialSubLangPriorities = List<String>.from(_subLangPriorities);

    _initialAutoplayNext = _autoplayNext;
    _initialDefaultSpeed = _defaultSpeed;
    _initialSeekStep = _seekStep;
    _initialHoldToSpeed = _holdToSpeed;
    _initialSeekButtons = _seekButtons;
    _initialMobileSeekButtons = _mobileSeekButtons;
    _initialDoubleTapSeek = _doubleTapSeek;
    _initialHoldRate = _holdRate;
    _initialAutoSkip = _autoSkip;
    _initialPlayerOrientation = _playerOrientation;

    _initialPitchCorrection = _pitchCorrection;
    _initialDefaultAudioLang = _defaultAudioLang;
    _initialAudioLangPriorities = List<String>.from(_audioLangPriorities);

    _initialA4kEnabled = _a4kEnabled;
    _initialA4kMode = _a4kMode;
    _initialA4kQuality = _a4kQuality;
    _initialA4kSkipHeight = _a4kSkipHeight;
    _initialKeyScheme = _keyScheme;
  }

  bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  bool get _hasChanges {
    return _themeMode != _initialThemeMode ||
        _font != _initialFont ||
        _fontSize != _initialFontSize ||
        _textColor != _initialTextColor ||
        _borderSize != _initialBorderSize ||
        _shadowOffset != _initialShadowOffset ||
        _marginY != _initialMarginY ||
        _bgOpacity != _initialBgOpacity ||
        _assMode != _initialAssMode ||
        _subtitlesEnabled != _initialSubtitlesEnabled ||
        !_listEquals(_subLangPriorities, _initialSubLangPriorities) ||
        _autoplayNext != _initialAutoplayNext ||
        _defaultSpeed != _initialDefaultSpeed ||
        _seekStep != _initialSeekStep ||
        _holdToSpeed != _initialHoldToSpeed ||
        _seekButtons != _initialSeekButtons ||
        _mobileSeekButtons != _initialMobileSeekButtons ||
        _doubleTapSeek != _initialDoubleTapSeek ||
        _holdRate != _initialHoldRate ||
        _autoSkip != _initialAutoSkip ||
        _playerOrientation != _initialPlayerOrientation ||
        _pitchCorrection != _initialPitchCorrection ||
        !_listEquals(_audioLangPriorities, _initialAudioLangPriorities) ||
        _a4kEnabled != _initialA4kEnabled ||
        _a4kMode != _initialA4kMode ||
        _a4kQuality != _initialA4kQuality ||
        _a4kSkipHeight != _initialA4kSkipHeight ||
        _keyScheme != _initialKeyScheme;
  }

  Color get _accentColor => uiTheme.accentColor;

  Color _parseHex(String hex) {
    try {
      final clean = hex.replaceAll('#', '').trim();
      return Color(int.parse('FF$clean', radix: 16));
    } catch (_) {
      return Colors.white;
    }
  }

  Future<void> _applySubtitles() async {
    StorageService.saveSubFont(_font);
    StorageService.saveSubFontSize(_fontSize);
    StorageService.saveSubTextColor(_textColor);
    StorageService.saveSubBorderSize(_borderSize);
    StorageService.saveSubShadowOffset(_shadowOffset);
    StorageService.saveSubMarginY(_marginY);
    StorageService.saveSubBgOpacity(_bgOpacity);
    StorageService.saveSubAssMode(_assMode);

    await MpvConfig.applySubtitleStyles(widget.controller.player);
    setState(() {});
  }

  void _resetCurrentTab() {
    setState(() {
      _isResetting = true;
      if (_activeTab == 0) {
        uiTheme.reset();
        _themeMode = 'dark';
      } else if (_activeTab == 1) {
        _font = 'Trebuchet MS';
        _fontSize = 48.0;
        _textColor = '#FFFFFF';
        _borderSize = 5.0;
        _shadowOffset = 2.0;
        _marginY = 36.0;
        _bgOpacity = 0.0;
        _assMode = 'yes';
        _subtitlesEnabled = true;
        _defaultSubLang = 'uk';
        _subLangPriorities = ['uk', 'ja', 'en'];
      } else if (_activeTab == 2) {
        _autoplayNext = true;
        _defaultSpeed = 1.0;
        _seekStep = 10;
        _holdToSpeed = true;
        _seekButtons = false;
        _mobileSeekButtons = true;
        _doubleTapSeek = true;
        _holdRate = 2.0;
        _autoSkip = true;
        _playerOrientation = PlayerOrientation.system;
      } else if (_activeTab == 3) {
        widget.controller.changeHwdec(AppPlatform.defaultHwdec);
      } else if (_activeTab == 4) {
        _pitchCorrection = true;
        _defaultAudioLang = 'auto';
        _audioLangPriorities = ['ja', 'uk', 'en'];
      } else if (_activeTab == 7) {
        _a4kEnabled = false;
        _a4kMode = Anime4kMode.a;
        _a4kQuality = Anime4kQuality.fast;
        _a4kSkipHeight = 0;
      } else if (_activeTab == 8) {
        _keyScheme = KeyScheme.standard;
      }
    });

    _applySubtitles();

    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted) setState(() => _isResetting = false);
    });
  }

  void _cancelChanges() {
    setState(() {
      _themeMode = _initialThemeMode;
      uiTheme.setThemeMode(_initialThemeMode);

      _font = _initialFont;
      _fontSize = _initialFontSize;
      _textColor = _initialTextColor;
      _borderSize = _initialBorderSize;
      _shadowOffset = _initialShadowOffset;
      _marginY = _initialMarginY;
      _bgOpacity = _initialBgOpacity;
      _assMode = _initialAssMode;
      _defaultSubLang = _initialDefaultSubLang;
      _subtitlesEnabled = _initialSubtitlesEnabled;
      _subLangPriorities = List<String>.from(_initialSubLangPriorities);

      _autoplayNext = _initialAutoplayNext;
      _defaultSpeed = _initialDefaultSpeed;
      _seekStep = _initialSeekStep;
      _holdToSpeed = _initialHoldToSpeed;
      _seekButtons = _initialSeekButtons;
      _mobileSeekButtons = _initialMobileSeekButtons;
      _doubleTapSeek = _initialDoubleTapSeek;
      _holdRate = _initialHoldRate;
      _autoSkip = _initialAutoSkip;
      _playerOrientation = _initialPlayerOrientation;

      _pitchCorrection = _initialPitchCorrection;
      _defaultAudioLang = _initialDefaultAudioLang;
      _audioLangPriorities = List<String>.from(_initialAudioLangPriorities);

      _a4kEnabled = _initialA4kEnabled;
      _a4kMode = _initialA4kMode;
      _a4kQuality = _initialA4kQuality;
      _a4kSkipHeight = _initialA4kSkipHeight;
      _keyScheme = _initialKeyScheme;
    });
    _applySubtitles();
  }

  Future<void> _applyAllChanges() async {
    StorageService.saveThemeMode(_themeMode);
    uiTheme.setThemeMode(_themeMode);

    StorageService.saveSubFont(_font);
    StorageService.saveSubFontSize(_fontSize);
    StorageService.saveSubTextColor(_textColor);
    StorageService.saveSubBorderSize(_borderSize);
    StorageService.saveSubShadowOffset(_shadowOffset);
    StorageService.saveSubMarginY(_marginY);
    StorageService.saveSubBgOpacity(_bgOpacity);
    StorageService.saveSubAssMode(_assMode);
    StorageService.saveDefaultSubLang(_defaultSubLang);
    StorageService.saveSubLangPriorities(_subLangPriorities);

    StorageService.saveAutoplayNext(_autoplayNext);
    StorageService.saveDefaultPlaybackSpeed(_defaultSpeed);
    StorageService.saveSeekStep(_seekStep);
    StorageService.saveHoldToSpeedEnabled(_holdToSpeed);
    StorageService.saveSeekButtons(_seekButtons);
    StorageService.saveMobileSeekButtons(_mobileSeekButtons);
    StorageService.saveDoubleTapSeek(_doubleTapSeek);
    StorageService.saveHoldToSpeedRate(_holdRate);
    StorageService.saveAutoSkipChapters(_autoSkip);
    StorageService.savePlayerOrientation(_playerOrientation.id);

    StorageService.savePitchCorrection(_pitchCorrection);
    StorageService.saveDefaultAudioLang(_defaultAudioLang);
    StorageService.saveAudioLangPriorities(_audioLangPriorities);

    await MpvConfig.applySubtitleStyles(widget.controller.player);
    final dynamic platform = widget.controller.player.platform;
    if (platform != null) {
      await platform.setProperty('audio-pitch-correction', _pitchCorrection ? 'yes' : 'no');
    }

    widget.controller.setKeyScheme(_keyScheme);
    await widget.controller.anime4k.configure(
      enabled: _a4kEnabled,
      mode: _a4kMode,
      quality: _a4kQuality,
      skipHeight: _a4kSkipHeight,
    );

    await StorageService.flush();
    AppLog.i('налаштування', 'застосовано: орієнтація плеєра ${_playerOrientation.id}, швидкість $_defaultSpeed, крок перемотки $_seekStep, автопродовження $_autoplayNext, '
        'Anime4K ${_a4kEnabled ? '${_a4kMode.name}/${_a4kQuality.name}' : 'вимк.'}, pitch-корекція $_pitchCorrection, тема $_themeMode');
    widget.controller.refreshOrientationPreference();
    widget.controller.refreshSettings();

    setState(() {
      _saveInitialSnapshot();
    });
  }

  /// Вкладки для вузького екрана телефона: (індекс вкладки, значок, підпис). «Гарячі клавіші» без клавіатури зайві.
  static const List<(int, IconData, String)> _phoneTabs = [
    (0, Symbols.palette_rounded, 'Вигляд'),
    (1, Symbols.subtitles_rounded, 'Субтитри'),
    (2, Symbols.play_circle_rounded, 'Відтворення'),
    (3, Symbols.developer_board_rounded, 'Відео & GPU'),
    (7, Symbols.auto_awesome_rounded, 'Anime4K'),
    (4, Symbols.volume_up_rounded, 'Звук'),
    (5, Symbols.terminal_rounded, 'Розробник'),
    (6, Symbols.info_rounded, 'Про програму'),
  ];

  /// Рядок вкладок під шапкою (вузький екран): прокручується вбік, кожна вкладка ≥ 48 dp заввишки
  Widget _buildPhoneTabStrip(double scale) {
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: 18 * scale),
        children: [
          for (final (index, icon, label) in _phoneTabs)
            Padding(
              padding: const EdgeInsets.only(right: 8, top: 2, bottom: 2),
              child: Material(
                color: _activeTab == index ? uiTheme.accentWash : uiTheme.bgElevated,
                shape: StadiumBorder(
                  side: BorderSide(color: _activeTab == index ? uiTheme.accentBorder : uiTheme.borderSubtle),
                ),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  splashColor: Colors.transparent,
                  highlightColor: uiTheme.touchHighlight,
                  onTap: () => setState(() => _activeTab = index),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, size: 20, color: _activeTab == index ? uiTheme.accentColor : uiTheme.textMuted, weight: 300, opticalSize: 24),
                        const SizedBox(width: 8),
                        Text(
                          label,
                          style: TextStyle(
                            fontFamily: 'Arial',
                            color: _activeTab == index ? uiTheme.textPrimary : uiTheme.textMuted,
                            fontSize: 14,
                            fontWeight: _activeTab == index ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.scale;
    final mq = MediaQuery.of(context);
    // Телефон: налаштування на весь екран (портрет — вкладки рядком, альбомна — бічне меню)
    final bool phone = AppPlatform.isMobile;
    final bool compact = phone && AppLayout(mq.size).isCompactWidth;
    final EdgeInsets safe = phone ? mq.padding : EdgeInsets.zero;
    final double outerR = phone ? 0 : 22 * scale;

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: widget.embedded ? double.infinity : (phone ? mq.size.width : 860 * scale),
          height: widget.embedded ? double.infinity : (phone ? mq.size.height : 620 * scale),
          padding: phone && !widget.embedded ? safe : EdgeInsets.zero,
          decoration: BoxDecoration(
            color: uiTheme.bgPrimary,
            borderRadius: uiTheme.borderRadius(outerR),
            border: phone ? null : Border.all(color: uiTheme.borderSubtle, width: 1.0),
            boxShadow: phone
                ? null
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: uiTheme.isLight ? 0.12 : 0.80),
                      blurRadius: 40 * scale,
                      offset: Offset(0, 12 * scale),
                    ),
                  ],
          ),
          child: Row(
            children: [
              if (!compact)
                Container(
                  width: (phone ? 200 : 220) * scale,
                  padding: EdgeInsets.symmetric(horizontal: 14 * scale, vertical: 20 * scale),
                  decoration: BoxDecoration(
                    color: uiTheme.bgSidebar,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(uiTheme.radius(outerR)),
                      bottomLeft: Radius.circular(uiTheme.radius(outerR)),
                    ),
                    border: Border(right: BorderSide(color: uiTheme.borderSubtle, width: 1.0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: EdgeInsets.only(left: 10 * scale, bottom: 16 * scale),
                        child: Text(
                          'Налаштування',
                          style: TextStyle(
                            fontFamily: 'Arial',
                            color: uiTheme.textPrimary,
                            fontSize: 16 * scale,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Expanded(
                        child: ListView(
                          children: [
                            _buildNavGroupLabel(scale, 'ОФОРМЛЕННЯ'),
                            _buildNavItem(scale, index: 0, icon: Symbols.palette_rounded, label: 'Вигляд'),
                            _buildNavItem(scale, index: 1, icon: Symbols.subtitles_rounded, label: 'Субтитри'),
                            SizedBox(height: 12 * scale),
                            _buildNavGroupLabel(scale, 'ПЛЕЄР'),
                            _buildNavItem(scale, index: 2, icon: Symbols.play_circle_rounded, label: 'Відтворення'),
                            _buildNavItem(scale, index: 3, icon: Symbols.developer_board_rounded, label: 'Відео & GPU'),
                            _buildNavItem(scale, index: 7, icon: Symbols.auto_awesome_rounded, label: 'Anime4K'),
                            _buildNavItem(scale, index: 4, icon: Symbols.volume_up_rounded, label: 'Звук'),
                            if (!phone) _buildNavItem(scale, index: 8, icon: Symbols.keyboard_rounded, label: 'Гарячі клавіші'),
                            SizedBox(height: 12 * scale),
                            _buildNavGroupLabel(scale, 'СИСТЕМА'),
                            _buildNavItem(scale, index: 5, icon: Symbols.terminal_rounded, label: 'Розробник'),
                            _buildNavItem(scale, index: 6, icon: Symbols.info_rounded, label: 'Про програму'),
                          ],
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.only(left: 8 * scale),
                        child: Text(
                          '${AppIdentity.name} · ${AppIdentity.version}',
                          style: TextStyle(
                            fontFamily: 'Arial',
                            color: uiTheme.textDarkMuted,
                            fontSize: 11 * scale,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: EdgeInsets.only(
                        left: (compact ? 18 : 24) * scale,
                        right: (compact ? 6 : 20) * scale,
                        top: (compact ? 8 : 18) * scale,
                        bottom: (compact ? 6 : 12) * scale,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 44 * scale,
                              child: AppFadeSwitcher(
                                duration: AppAnim.fast,
                                child: Column(
                                  key: ValueKey<int>(_activeTab),
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      _getTitle(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontFamily: 'Arial',
                                        color: uiTheme.textPrimary,
                                        fontSize: 17 * scale,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    SizedBox(height: 2 * scale),
                                    Text(
                                      _getSubtitle(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontFamily: 'Arial',
                                        color: uiTheme.textDarkMuted,
                                        fontSize: 12 * scale,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          if (_activeTab != 6) ...[
                            InkWell(
                              onTap: _resetCurrentTab,
                              borderRadius: BorderRadius.circular(8 * scale),
                              splashColor: Colors.transparent,
                              highlightColor: uiTheme.touchHighlight,
                              hoverColor: uiTheme.isLight ? Colors.black.withValues(alpha: 0.04) : Colors.white.withValues(alpha: 0.05),
                              child: AppAnimatedContainer(
                                duration: AppAnim.medium,
                                curve: AppAnim.easeOut,
                                constraints: BoxConstraints(minHeight: phone ? AppPlatform.touchTarget : 0),
                                alignment: Alignment.center,
                                padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 5 * scale),
                                decoration: BoxDecoration(
                                  color: _isResetting
                                      ? const Color(0xFF00FF66).withValues(alpha: 0.12)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8 * scale),
                                  border: Border.all(
                                    color: _isResetting
                                        ? const Color(0xFF00FF66).withValues(alpha: 0.40)
                                        : Colors.transparent,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    AppRotate(
                                      turns: _isResetting ? 1.0 : 0.0,
                                      duration: AppAnim.long,
                                      curve: AppAnim.easeOut,
                                      child: Icon(
                                        _isResetting ? Symbols.check_rounded : Symbols.restart_alt_rounded,
                                        color: _isResetting ? const Color(0xFF00FF66) : uiTheme.textMuted,
                                        size: 16 * scale,
                                      ),
                                    ),
                                    SizedBox(width: 5 * scale),
                                    Text(
                                      _isResetting ? 'Скинуто до початкових' : 'Скинути',
                                      style: TextStyle(
                                        fontFamily: 'Arial',
                                        color: _isResetting ? const Color(0xFF00FF66) : uiTheme.textMuted,
                                        fontSize: 12 * scale,
                                        fontWeight: _isResetting ? FontWeight.bold : FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            SizedBox(width: 8 * scale),
                          ],
                          if (!widget.embedded)
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: phone ? const BoxConstraints.tightFor(width: 48, height: 48) : const BoxConstraints(),
                            icon: Icon(Symbols.close_rounded, color: uiTheme.textDarkMuted, size: phone ? 24 : 20 * scale),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                    ),
                    if (compact) _buildPhoneTabStrip(scale),
                    Expanded(
                      child: AppFadeSlideSwitcher(
                        duration: AppAnim.normal,
                        child: KeyedSubtree(
                          key: ValueKey<int>(_activeTab),
                          child: _activeTab == 1
                              ? _buildSubtitlesTabWithStickyPreview(scale)
                              : _buildScrollableTabWithShadows(scale, _buildTabBody(scale)),
                        ),
                      ),
                    ),
                    if (!widget.embedded || _hasChanges)
                    Padding(
                      padding: EdgeInsets.only(
                        left: (compact ? 16 : 24) * scale,
                        right: (compact ? 16 : 24) * scale,
                        bottom: (compact ? 12 : 16) * scale,
                        top: 8 * scale,
                      ),
                      // Вузький екран: три кнопки не вміщаються в рядок — рядок трохи стискається
                      child: _footerFit(
                        compact,
                        Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (_hasChanges) ...[
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: uiTheme.bgElevated,
                                foregroundColor: uiTheme.textPrimary,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: uiTheme.borderRadius(12 * scale),
                                  side: BorderSide(color: uiTheme.borderSubtle),
                                ),
                                padding: EdgeInsets.symmetric(horizontal: 18 * scale, vertical: 12 * scale),
                                minimumSize: phone ? const Size(0, AppPlatform.touchTarget) : null,
                              ),
                              onPressed: _cancelChanges,
                              child: Text(
                                'Скасувати',
                                style: TextStyle(
                                  fontFamily: 'Arial',
                                  color: uiTheme.textPrimary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13 * scale,
                                ),
                              ),
                            ),
                            SizedBox(width: 10 * scale),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _accentColor.withValues(alpha: uiTheme.isLight ? 0.16 : 0.22),
                                foregroundColor: uiTheme.isLight ? _accentColor : Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: uiTheme.borderRadius(12 * scale),
                                  side: BorderSide(color: _accentColor.withValues(alpha: 0.75)),
                                ),
                                padding: EdgeInsets.symmetric(horizontal: 20 * scale, vertical: 12 * scale),
                                minimumSize: phone ? const Size(0, AppPlatform.touchTarget) : null,
                              ),
                              onPressed: _applyAllChanges,
                              child: Text(
                                'Застосувати',
                                style: TextStyle(
                                  fontFamily: 'Arial',
                                  color: uiTheme.isLight ? _accentColor : Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13 * scale,
                                ),
                              ),
                            ),
                            SizedBox(width: 10 * scale),
                          ],
                          if (!widget.embedded)
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _accentColor.withValues(alpha: uiTheme.isLight ? 0.15 : 0.18),
                              foregroundColor: uiTheme.isLight ? _accentColor : Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: uiTheme.borderRadius(12 * scale),
                                side: BorderSide(color: _accentColor.withValues(alpha: 0.65)),
                              ),
                              padding: EdgeInsets.symmetric(horizontal: 24 * scale, vertical: 12 * scale),
                              minimumSize: phone ? const Size(0, AppPlatform.touchTarget) : null,
                            ),
                            onPressed: () => Navigator.of(context).pop(),
                            child: Text(
                              'Готово',
                              style: TextStyle(
                                fontFamily: 'Arial',
                                color: uiTheme.isLight ? _accentColor : Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13 * scale,
                              ),
                            ),
                          ),
                        ],
                      )),
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

  Widget _footerFit(bool compact, Widget row) => compact
      ? SizedBox(width: double.infinity, child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight, child: row))
      : row;

  /// Універсальна обгортка для вкладок зі скролом із м'якими тінями зверху та знизу
  Widget _buildScrollableTabWithShadows(double scale, Widget content) {
    return Stack(
      children: [
        Positioned.fill(
          child: AppSmoothScrollView(
            padding: EdgeInsets.only(
              left: 24 * scale,
              right: 24 * scale,
              top: 18 * scale,
              bottom: 36 * scale,
            ),
            child: Align(
              alignment: Alignment.topLeft,
              child: content,
            ),
          ),
        ),
        // Верхнє затінення (розчинення контенту під шапку)
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 14 * scale,
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    uiTheme.bgPrimary.withValues(alpha: 0.95),
                    uiTheme.bgPrimary.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
        ),
        // Нижнє затінення (розчинення контенту над кнопками)
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          height: 16 * scale,
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    uiTheme.bgPrimary.withValues(alpha: 0.95),
                    uiTheme.bgPrimary.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSubtitlesTabWithStickyPreview(double scale) {
    final fontOptions = [
      ..._builtInFonts,
      ...StorageService.getCustomFonts().map((p) => p.split(RegExp(r'[/\\]')).last.split('.').first),
    ].map((f) => AppDropdownOption(value: f, label: f)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 24 * scale),
          child: _buildSubtitlePreview(scale),
        ),
        SizedBox(height: 6 * scale),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: AppSmoothScrollView(
                  padding: EdgeInsets.only(
                    left: 24 * scale,
                    right: 24 * scale,
                    top: 18 * scale,
                    bottom: 36 * scale,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildToggleRow(
                        scale,
                        title: 'Автоматично завантажувати субтитри',
                        subtitle: 'Вмикати бажану доріжку при відкритті нового відео',
                        value: _subtitlesEnabled,
                        onChanged: (enabled) {
                          setState(() {
                            _subtitlesEnabled = enabled;
                            _defaultSubLang = enabled
                                ? (_subLangPriorities.isNotEmpty ? _subLangPriorities.first : 'uk')
                                : 'no';
                          });
                        },
                      ),
                      AppSlideDownCollapse(
                        isExpanded: _subtitlesEnabled,
                        duration: AppAnim.medium,
                        child: Padding(
                          padding: EdgeInsets.only(top: 14 * scale),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildSectionHeader(
                                scale,
                                'Пріоритет мов субтитрів',
                                'Перетягуйте для зміни пріоритету; плеєр обере першу знайдену мову',
                              ),
                              SizedBox(height: 8 * scale),
                              AppLanguagePriorityList(
                                scale: scale,
                                languages: _subLangPriorities,
                                onChanged: (newList) {
                                  setState(() => _subLangPriorities = newList);
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                      Divider(color: uiTheme.borderSubtle, height: 24 * scale),
                      _buildSectionHeader(scale, 'Режим заміни ASS / SSA', 'Рівень сумісності з аніме-субтитрами'),
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
                          setState(() => _assMode = val);
                          _applySubtitles();
                        },
                      ),
                      SizedBox(height: 18 * scale),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(child: _buildSectionHeader(scale, 'Гарнітура шрифту', 'Оберіть системний або власний шрифт')),
                          SizedBox(width: 10 * scale),
                          _buildActionPill(
                            scale,
                            icon: Symbols.add_rounded,
                            label: 'Свій шрифт',
                            onTap: () async {
                              final res = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['ttf', 'otf']);
                              if (res != null && res.files.first.path != null) {
                                StorageService.addCustomFont(res.files.first.path!);
                                setState(() {
                                  _font = res.files.first.name.split('.').first;
                                });
                                _applySubtitles();
                              }
                            },
                          ),
                        ],
                      ),
                      SizedBox(height: 8 * scale),
                      AppDropdown<String>(
                        scale: scale,
                        value: _font,
                        options: fontOptions,
                        onChanged: (newFont) {
                          setState(() => _font = newFont);
                          _applySubtitles();
                        },
                      ),
                      SizedBox(height: 16 * scale),
                      _buildAlignedSlider(scale, label: 'Розмір шрифту', valueText: '${_fontSize.toInt()} px', value: _fontSize, min: 24.0, max: 80.0, onChanged: (v) { setState(() => _fontSize = v.roundToDouble()); _applySubtitles(); }),
                      _buildAlignedSlider(scale, label: 'Товщина обводки', valueText: '${_borderSize.toStringAsFixed(1)} px', value: _borderSize, min: 0.0, max: 8.0, onChanged: (v) { setState(() => _borderSize = (v * 10).round() / 10); _applySubtitles(); }),
                      _buildAlignedSlider(scale, label: 'Зсув твердої тіні', valueText: '${_shadowOffset.toStringAsFixed(1)} px', value: _shadowOffset, min: 0.0, max: 6.0, onChanged: (v) { setState(() => _shadowOffset = (v * 10).round() / 10); _applySubtitles(); }),
                      _buildAlignedSlider(scale, label: 'Відступ знизу (Margin Y)', valueText: '${_marginY.toInt()} px', value: _marginY, min: 10.0, max: 80.0, onChanged: (v) { setState(() => _marginY = v.roundToDouble()); _applySubtitles(); }),
                      SizedBox(height: 16 * scale),
                    ],
                  ),
                ),
              ),
              // Тінь зверху під прев'ю
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 14 * scale,
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          uiTheme.bgPrimary.withValues(alpha: 0.95),
                          uiTheme.bgPrimary.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // Тінь знизу над панеллю кнопок
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                height: 16 * scale,
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          uiTheme.bgPrimary.withValues(alpha: 0.95),
                          uiTheme.bgPrimary.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTabBody(double scale) {
    switch (_activeTab) {
      case 0: // ВИГЛЯД
        final swatchRadius = uiTheme.borderRadius(8 * scale);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildSectionHeader(scale, 'Тема оформлення', 'Оберіть колірну гаму інтерфейсу плеєра'),
            SizedBox(height: 10 * scale),
            AppSegmentedBar<String>(
              scale: scale,
              options: const [
                AppSegmentOption(value: 'system', label: 'Авто (Система)'),
                AppSegmentOption(value: 'dark', label: 'Темна'),
                AppSegmentOption(value: 'light', label: 'Світла'),
              ],
              selectedValue: _themeMode,
              onSelected: (val) {
                setState(() => _themeMode = val);
                uiTheme.setThemeMode(val);
              },
            ),
            SizedBox(height: 24 * scale),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: _buildSectionHeader(scale, 'Основний колір', 'Оберіть акцентний колір інтерфейсу плеєра')),
                SizedBox(width: 10 * scale),
                Text('Як акцент  ${uiTheme.accentHex}', style: TextStyle(fontFamily: 'Arial', color: uiTheme.textDarkMuted, fontSize: 12 * scale)),
              ],
            ),
            SizedBox(height: 12 * scale),
            // Wrap: на вузькому екрані телефона кольори переходять на другий рядок
            Wrap(
              runSpacing: 4 * scale,
              children: UiThemeService.presets.entries.map((e) {
                final hex = e.key;
                final col = e.value.$2;
                final isCur = uiTheme.accentHex.toUpperCase() == hex.toUpperCase();

                return GestureDetector(
                  onTap: () {
                    uiTheme.setAccentHex(hex);
                    setState(() {});
                  },
                  child: Container(
                    width: 34 * scale,
                    height: 34 * scale,
                    margin: EdgeInsets.only(right: 10 * scale),
                    alignment: Alignment.center,
                    child: AppAnimatedContainer(
                      duration: AppAnim.fast,
                      curve: AppAnim.easeOut,
                      width: 30 * scale,
                      height: 30 * scale,
                      decoration: BoxDecoration(
                        color: col,
                        borderRadius: swatchRadius,
                        border: Border.all(
                          color: isCur ? (uiTheme.isLight ? Colors.black : Colors.white) : uiTheme.borderSubtle,
                          width: isCur ? 2.5 : 1.0,
                        ),
                        boxShadow: isCur
                            ? [
                                BoxShadow(
                                  color: col.withValues(alpha: 0.5),
                                  blurRadius: 8 * scale,
                                  spreadRadius: 1 * scale,
                                ),
                              ]
                            : null,
                      ),
                      child: isCur ? Icon(Symbols.check_rounded, color: Colors.black, size: 17 * scale) : null,
                    ),
                  ),
                );
              }).toList(),
            ),
            SizedBox(height: 24 * scale),
            _buildSectionHeader(scale, 'Радіус заокруглення', 'Заокруглення кутів кнопок, карток та елементів UI'),
            SizedBox(height: 10 * scale),
            Wrap(
              runSpacing: 8 * scale,
              children: ['Без', 'XS', 'SM', 'MD', 'LG', 'XL'].map((r) {
                final isCur = uiTheme.radiusKey == r;
                return Padding(
                  padding: EdgeInsets.only(right: 8 * scale),
                  child: GestureDetector(
                    onTap: () {
                      uiTheme.setRadiusKey(r);
                      setState(() {});
                    },
                    child: AppAnimatedContainer(
                      duration: AppAnim.fast,
                      curve: AppAnim.easeOut,
                      width: 44 * scale,
                      height: 32 * scale,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isCur ? uiTheme.accentWash : uiTheme.bgSurface,
                        borderRadius: uiTheme.borderRadius(14 * scale),
                        border: Border.all(
                          color: isCur ? uiTheme.accentBorder : uiTheme.borderSubtle,
                          width: 1.0,
                        ),
                      ),
                      child: Text(
                        r,
                        style: TextStyle(
                          fontFamily: 'Arial',
                          color: isCur ? uiTheme.accentColor : uiTheme.textMuted,
                          fontSize: 12.5 * scale,
                          fontWeight: isCur ? FontWeight.bold : FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        );

      case 2: // ВІДТВОРЕННЯ
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildToggleRow(
              scale,
              title: 'Автовідтворення наступного епізоду',
              subtitle: 'Автоматично вмикати наступне відео в черзі після завершення поточного',
              value: _autoplayNext,
              onChanged: (v) {
                setState(() => _autoplayNext = v);
              },
            ),
            Divider(color: uiTheme.borderSubtle, height: 24 * scale),
            _buildSectionHeader(scale, 'Стандартна швидкість відтворення', 'Швидкість, яка застосовується до нових відео за замовчуванням'),
            SizedBox(height: 10 * scale),
            AppSegmentedBar<double>(
              scale: scale,
              options: const [
                AppSegmentOption(value: 0.75, label: '0.75x'),
                AppSegmentOption(value: 1.0, label: '1.0x (Норма)'),
                AppSegmentOption(value: 1.25, label: '1.25x'),
                AppSegmentOption(value: 1.5, label: '1.5x'),
                AppSegmentOption(value: 2.0, label: '2.0x'),
              ],
              selectedValue: _defaultSpeed,
              onSelected: (v) {
                setState(() => _defaultSpeed = v);
              },
            ),
            if (AppPlatform.isMobile) ...[
              Divider(color: uiTheme.borderSubtle, height: 24 * scale),
              _buildSectionHeader(
                scale,
                'Орієнтація плеєра',
                'У якій орієнтації відкривається відео. Коли вийдете з плеєра або згорнете його в міні-плеєр, повернеться попередня',
              ),
              SizedBox(height: 10 * scale),
              AppSegmentedBar<PlayerOrientation>(
                scale: scale,
                options: [for (final o in PlayerOrientation.values) AppSegmentOption(value: o, label: o.label)],
                selectedValue: _playerOrientation,
                onSelected: (v) => setState(() => _playerOrientation = v),
              ),
            ],
            Divider(color: uiTheme.borderSubtle, height: 24 * scale),
            _buildSectionHeader(
              scale,
              'Крок перемотування',
              'Для подвійного дотику, кнопок ±крок та клавіш J / L (у стандартній схемі)',
            ),
            SizedBox(height: 10 * scale),
            AppSegmentedBar<int>(
              scale: scale,
              options: const [
                AppSegmentOption(value: 5, label: '±5 сек'),
                AppSegmentOption(value: 10, label: '±10 сек'),
                AppSegmentOption(value: 15, label: '±15 сек'),
                AppSegmentOption(value: 30, label: '±30 сек'),
              ],
              selectedValue: _seekStep,
              onSelected: (v) {
                setState(() => _seekStep = v);
              },
            ),
            Divider(color: uiTheme.borderSubtle, height: 24 * scale),
            _buildToggleRow(
              scale,
              title: 'Перемотка подвійним дотиком',
              subtitle: 'Подвійний клік по лівому чи правому боці відео перемотує назад / вперед на крок',
              value: _doubleTapSeek,
              onChanged: (v) => setState(() => _doubleTapSeek = v),
            ),
            Divider(color: uiTheme.borderSubtle, height: 24 * scale),
            if (AppPlatform.isMobile)
              _buildToggleRow(
                scale,
                title: 'Кнопки перемотки на екрані',
                subtitle: 'Показувати кнопки ±крок поруч із паузою; перемотку лишають подвійний дотик і повзунок',
                value: _mobileSeekButtons,
                onChanged: (v) => setState(() => _mobileSeekButtons = v),
              )
            else
              _buildToggleRow(
                scale,
                title: 'Кнопки перемотки на панелі',
                subtitle: 'Показувати кнопки ±крок поруч із кнопкою паузи',
                value: _seekButtons,
                onChanged: (v) => setState(() => _seekButtons = v),
              ),
            Divider(color: uiTheme.borderSubtle, height: 24 * scale),
            _buildToggleRow(
              scale,
              title: 'Прискорення утримуванням на екрані',
              subtitle: 'Тимчасове прискорення відео при затисканні клавіші миші чи тачпаду',
              value: _holdToSpeed,
              onChanged: (v) {
                setState(() => _holdToSpeed = v);
              },
            ),
            AppSlideDownCollapse(
              isExpanded: _holdToSpeed,
              duration: AppAnim.medium,
              child: Padding(
                padding: EdgeInsets.only(top: 12 * scale),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionHeader(scale, 'Швидкість при утримуванні', 'Темп відтворення під час затискання екрана'),
                    SizedBox(height: 8 * scale),
                    AppSegmentedBar<double>(
                      scale: scale,
                      options: const [
                        AppSegmentOption(value: 1.5, label: '1.5x'),
                        AppSegmentOption(value: 2.0, label: '2.0x (2x)'),
                        AppSegmentOption(value: 2.5, label: '2.5x'),
                        AppSegmentOption(value: 3.0, label: '3.0x'),
                      ],
                      selectedValue: _holdRate,
                      onSelected: (v) {
                        setState(() => _holdRate = v);
                      },
                    ),
                  ],
                ),
              ),
            ),
            Divider(color: uiTheme.borderSubtle, height: 24 * scale),
            _buildToggleRow(
              scale,
              title: 'Автопропуск опенінгів та ендінгів',
              subtitle: 'Автоматично виводити або пропускати вступні та титрові частини',
              value: _autoSkip,
              onChanged: (v) {
                setState(() => _autoSkip = v);
              },
            ),
          ],
        );

      case 3: // ВІДЕО & GPU
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            AppDropdown<String>(
              scale: scale,
              label: 'Апаратний декодер (GPU)',
              subtitle: 'Оберіть бекенд для апаратного декодування відео 120 FPS',
              value: widget.controller.currentHwdec,
              options: AppConstants.hwdecOptions.entries
                  .map((e) => AppDropdownOption(value: e.key, label: e.value))
                  .toList(),
              onChanged: (newHwdec) async {
                await widget.controller.changeHwdec(newHwdec);
                setState(() {});
              },
            ),
          ],
        );

      case 4: // ЗВУК
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildToggleRow(
              scale,
              title: 'Корекція висоти тону (Pitch Correction)',
              subtitle: 'Зберігає природне звучання голосу при прискоренні відтворення 1.25x–2.0x',
              value: _pitchCorrection,
              onChanged: (v) async {
                setState(() => _pitchCorrection = v);
              },
            ),
            Divider(color: uiTheme.borderSubtle, height: 24 * scale),
            _buildSectionHeader(
              scale,
              'Пріоритет мов аудіодоріжок',
              'Плеєр автоматично вибере аудіо за найвищим доступним пріоритетом',
            ),
            SizedBox(height: 10 * scale),
            AppLanguagePriorityList(
              scale: scale,
              languages: _audioLangPriorities,
              onChanged: (newList) {
                setState(() => _audioLangPriorities = newList);
              },
            ),
          ],
        );

      case 7: // ANIME4K
        return _buildAnime4kTab(scale);

      case 8: // ГАРЯЧІ КЛАВІШІ
        return _buildHotkeysTab(scale);

      case 5: // РОЗРОБНИК
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildSectionHeader(scale, 'Приховані можливості', 'Те, що поки не входить до основного інтерфейсу'),
            SizedBox(height: 10 * scale),
            _buildToggleRow(
              scale,
              title: 'Локальна медіатека',
              subtitle: 'Відкрити файл чи посилання, історія файлів і плейлисти. Розділ з’являється у «Профілі»',
              value: StorageService.getLocalLibrary(),
              onChanged: (v) => setState(() => StorageService.saveLocalLibrary(v)),
            ),
            SizedBox(height: 14 * scale),
            _buildSectionHeader(scale, 'Банери на головній', 'Широкі зображення беруться з AniList; запасний варіант — TheMovieDB'),
            SizedBox(height: 10 * scale),
            AppSearchField(
              scale: scale,
              controller: _tmdbKey,
              icon: Symbols.key_rounded,
              hint: 'Ключ TheMovieDB (необов’язково)',
              onChanged: StorageService.saveTmdbKey,
            ),
            Divider(color: uiTheme.borderSubtle, height: 24 * scale),
            _buildSectionHeader(scale, 'Журнал і діагностика', 'Запис майже всіх дій застосунку, щоб знаходити помилки'),
            SizedBox(height: 10 * scale),
            _buildToggleRow(
              scale,
              title: 'Детальний журнал',
              subtitle: 'Дії, мережа, події плеєра, синхронізація звуку й відео — в окремий файл. Докладність libmpv змінюється після перезапуску',
              value: AppLog.instance.detailed,
              onChanged: _setDetailedLog,
            ),
            SizedBox(height: 10 * scale),
            Wrap(
              spacing: 10 * scale,
              runSpacing: 10 * scale,
              children: [
                _buildActionPill(
                  scale,
                  icon: Symbols.download_rounded,
                  label: 'Зберегти журнал у файл',
                  onTap: _saveLogToFile,
                ),
                _buildActionPill(
                  scale,
                  icon: Symbols.delete_outline_rounded,
                  label: 'Очистити журнали',
                  onTap: _clearLogs,
                ),
              ],
            ),
            if (Platform.isWindows) ...[
              SizedBox(height: 10 * scale),
              _buildActionPill(
                scale,
                icon: Symbols.folder_open_rounded,
                label: 'Відкрити папку журналів',
                onTap: () async {
                  final dir = AppLog.instance.directory;
                  if (dir == null) return;
                  await dir.create(recursive: true);
                  Process.run('explorer.exe', [dir.path]);
                },
              ),
            ],
            SizedBox(height: 8 * scale),
            _buildLogStatusLine(scale),
            Divider(color: uiTheme.borderSubtle, height: 24 * scale),
            _buildSectionHeader(scale, 'Конфігурація та Кеш', 'Прямий доступ до файлів конфігурації libmpv'),
            SizedBox(height: 12 * scale),
            Row(
              children: [
                // Провідник є лише на Windows; на телефоні кнопки немає
                if (Platform.isWindows) ...[
                  Expanded(
                    child: _buildActionPill(
                      scale,
                      icon: Symbols.folder_open_rounded,
                      label: 'Відкрити папку конфігів',
                      onTap: () => Process.run('explorer.exe', [StorageService.appBasePath]),
                    ),
                  ),
                  SizedBox(width: 10 * scale),
                ],
                Expanded(
                  child: _buildActionPill(
                    scale,
                    icon: Symbols.delete_outline_rounded,
                    label: 'Очистити історію перегляду',
                    onTap: () {
                      StorageService.clearRecentFiles();
                      setState(() {});
                    },
                  ),
                ),
              ],
            ),
            SizedBox(height: 18 * scale),
            _buildSectionHeader(scale, 'Живий буфер логів libmpv', 'Останні записи внутрішнього C-рушія'),
            SizedBox(height: 8 * scale),
            Container(
              height: 180 * scale,
              padding: EdgeInsets.all(10 * scale),
              decoration: BoxDecoration(
                color: uiTheme.isLight ? const Color(0xFFF0F0F4) : const Color(0xFF070707),
                borderRadius: uiTheme.borderRadius(10 * scale),
                border: Border.all(color: uiTheme.borderSubtle),
              ),
              child: ListView.builder(
                itemCount: widget.controller.mpvLogs.length,
                itemBuilder: (ctx, i) {
                  final log = widget.controller.mpvLogs[i];
                  return Text(
                    log,
                    style: TextStyle(
                      fontFamily: 'Consolas',
                      fontSize: 10.5 * scale,
                      color: log.contains('error')
                          ? Colors.redAccent
                          : (uiTheme.isLight ? const Color(0xFF222226) : Colors.white70),
                    ),
                  );
                },
              ),
            ),
          ],
        );

      case 6: // ПРО ПРОГРАМУ
        return Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64 * scale,
                  height: 64 * scale,
                  decoration: BoxDecoration(
                    color: uiTheme.accentColor,
                    borderRadius: uiTheme.borderRadius(18 * scale),
                  ),
                  child: Icon(Symbols.smart_display_rounded, color: Colors.white, size: 38 * scale),
                ),
                SizedBox(height: 14 * scale),
                Text(
                  AppIdentity.name,
                  style: TextStyle(
                    fontFamily: 'Arial',
                    color: uiTheme.textPrimary,
                    fontSize: 18 * scale,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 4 * scale),
                Text(
                  'Версія ${AppIdentity.version} · збірка ${AppDiagnostics.build}',
                  style: TextStyle(
                    fontFamily: 'Arial',
                    color: uiTheme.textMuted,
                    fontSize: 12.5 * scale,
                  ),
                ),
                SizedBox(height: 16 * scale),
                Container(
                  padding: EdgeInsets.all(14 * scale),
                  decoration: BoxDecoration(
                    color: uiTheme.bgSurface,
                    borderRadius: uiTheme.borderRadius(12 * scale),
                    border: Border.all(color: uiTheme.borderSubtle),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '• ${AppIdentity.tagline}\n• Дані каталогу — hikka.io\n• Банери: AniList; запасні — TheMovieDB (використовує TMDB API, але не схвалений і не сертифікований TMDB)\n• Відео — libmpv: D3D11 і NVDEC на ПК, MediaCodec на телефоні\n• Субтитри SSA/ASS, шейдери Anime4K\n• Шрифти: Arial / Liberation Sans',
                        style: TextStyle(
                          fontFamily: 'Arial',
                          color: uiTheme.textSecondary,
                          fontSize: 12 * scale,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 14 * scale),
                _buildUpdateBlock(scale),
              ],
            ),
          ),
        );

      default:
        return const SizedBox.shrink();
    }
  }

  // ───────── Оновлення ─────────

  Widget _buildUpdateBlock(double scale) {
    return ValueListenableBuilder<UpdateState>(
      valueListenable: AppUpdater.instance.state,
      builder: (context, st, _) {
        final checking = st is UpdateChecking;
        final String title;
        final String? sub;
        switch (st) {
          case UpdateAvailable(:final info):
            title = 'Доступна версія ${info.version}';
            final size = info.size > 0 ? ' · ${(info.size / 1048576).toStringAsFixed(1)} МБ' : '';
            sub = info.notes.isEmpty ? 'Файл: ${info.assetName.isEmpty ? 'сторінка релізу' : info.assetName}$size' : info.notes;
          case UpdateUpToDate():
            title = 'У вас остання версія';
            sub = null;
          case UpdateChecking():
            title = 'Перевіряю…';
            sub = null;
          case UpdateFailed(:final message):
            title = message;
            sub = null;
          case UpdateIdle():
            title = 'Оновлення';
            sub = 'Нові версії беруться з GitHub (${AppUpdater.repo})';
        }
        return Container(
          width: double.infinity,
          padding: EdgeInsets.all(14 * scale),
          decoration: BoxDecoration(
            color: uiTheme.bgSurface,
            borderRadius: uiTheme.borderRadius(12 * scale),
            border: Border.all(color: uiTheme.borderSubtle),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(fontFamily: 'Arial', color: uiTheme.textPrimary, fontSize: 13.5 * scale, fontWeight: FontWeight.bold),
              ),
              if (sub != null) ...[
                SizedBox(height: 4 * scale),
                Text(
                  sub,
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: 'Arial', color: uiTheme.textMuted, fontSize: 12 * scale, height: 1.4),
                ),
              ],
              SizedBox(height: 12 * scale),
              Wrap(
                spacing: 10 * scale,
                runSpacing: 10 * scale,
                children: [
                  if (st is UpdateAvailable)
                    AppAccentButton(
                      scale: scale,
                      label: 'Завантажити',
                      icon: Symbols.download_rounded,
                      onTap: () => SystemControls.openUrl(st.info.target),
                    ),
                  AppSecondaryButton(
                    scale: scale,
                    label: checking ? 'Перевіряю…' : 'Перевірити оновлення',
                    icon: Symbols.refresh_rounded,
                    expand: false,
                    onTap: () {
                      if (!checking) AppUpdater.instance.check();
                    },
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // ───────── Anime4K ─────────

  static const List<(int, String)> _skipHeights = [
    (0, 'Не пропускати'),
    (1080, 'від 1080p'),
    (1440, 'від 1440p'),
    (2160, 'від 4K'),
  ];

  Widget _buildAnime4kTab(double scale) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildToggleRow(
          scale,
          title: 'Увімкнути Anime4K',
          subtitle: 'Відновлює лінії та збільшує роздільність відео в реальному часі шейдерами відеокарти',
          value: _a4kEnabled,
          onChanged: (v) => setState(() => _a4kEnabled = v),
        ),
        AppSlideDownCollapse(
          isExpanded: _a4kEnabled,
          duration: AppAnim.medium,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Divider(color: uiTheme.borderSubtle, height: 24 * scale),
              _buildSectionHeader(
                scale,
                'Режим',
                'Оберіть той, що на вашому відео виглядає найкраще. Перемикати можна й під час перегляду',
              ),
              SizedBox(height: 10 * scale),
              for (final mode in Anime4kMode.values) _buildAnime4kModeCard(scale, mode),
              Divider(color: uiTheme.borderSubtle, height: 24 * scale),
              Row(
                children: [
                  Expanded(
                    child: _buildSectionHeader(scale, 'Якість', 'Fast легший для відеокарти, HQ дає чіткіший результат'),
                  ),
                  SizedBox(width: 12 * scale),
                  AppKeyCombo(scale: scale, keys: const ['Ctrl', '9']),
                ],
              ),
              SizedBox(height: 10 * scale),
              AppSegmentedBar<Anime4kQuality>(
                scale: scale,
                options: [
                  for (final q in Anime4kQuality.values) AppSegmentOption(value: q, label: '${q.label} · ${q.title}'),
                ],
                selectedValue: _a4kQuality,
                onSelected: (q) => setState(() => _a4kQuality = q),
              ),
              SizedBox(height: 8 * scale),
              Text(
                _a4kQuality.gpuHint,
                style: TextStyle(fontFamily: 'Arial', color: uiTheme.textMuted, fontSize: 11.5 * scale),
              ),
              Divider(color: uiTheme.borderSubtle, height: 24 * scale),
              _buildSectionHeader(
                scale,
                'Пропускати відео з високою роздільністю',
                'Не вмикати шейдери, коли апскейл уже не потрібен — це економить відеокарту',
              ),
              SizedBox(height: 10 * scale),
              AppSegmentedBar<int>(
                scale: scale,
                options: [for (final (value, label) in _skipHeights) AppSegmentOption(value: value, label: label)],
                selectedValue: _skipHeights.any((o) => o.$1 == _a4kSkipHeight) ? _a4kSkipHeight : 0,
                onSelected: (v) => setState(() => _a4kSkipHeight = v),
              ),
            ],
          ),
        ),
        Divider(color: uiTheme.borderSubtle, height: 24 * scale),
        _buildAnime4kStatus(scale),
        SizedBox(height: 12 * scale),
        // Комбінації клавіш Ctrl + цифра — лише для клавіатури; на телефоні їх не показуємо
        if (!AppPlatform.isMobile) ...[
          _buildAnime4kKeys(scale),
          SizedBox(height: 14 * scale),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(top: 1 * scale),
              child: Icon(Symbols.info_rounded, color: uiTheme.textDarkMuted, size: 15 * scale),
            ),
            SizedBox(width: 8 * scale),
            Expanded(
              child: Text(
                'Шейдери bloc97/Anime4K v4.0.1 (ліцензія MIT) вбудовані в застосунок. Поки Anime4K увімкнений, '
                'він замінює список glsl-shaders із вашого mpv.conf. Режими A+A, B+B і C+A мають сенс лише тоді, '
                'коли картинку збільшують удвічі й більше.',
                style: TextStyle(
                  fontFamily: 'Arial',
                  color: uiTheme.textDarkMuted,
                  fontSize: 11.5 * scale,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAnime4kModeCard(double scale, Anime4kMode mode) {
    final selected = _a4kMode == mode;
    return Padding(
      padding: EdgeInsets.only(bottom: 8 * scale),
      child: AppCard(
        scale: scale,
        isHighlighted: selected,
        padding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 10 * scale),
        onTap: () => setState(() {
          _a4kMode = mode;
          _a4kEnabled = true;
        }),
        child: Row(
          children: [
            Container(
              width: 42 * scale,
              height: 42 * scale,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? uiTheme.accentWash : uiTheme.bgElevated,
                borderRadius: uiTheme.borderRadius(11 * scale),
                border: Border.all(color: selected ? uiTheme.accentBorder : uiTheme.borderSubtle),
              ),
              child: Text(
                mode.label,
                style: TextStyle(
                  fontFamily: 'Arial',
                  color: selected ? uiTheme.accentColor : uiTheme.textPrimary,
                  fontSize: (mode.label.length > 1 ? 12.5 : 15) * scale,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            SizedBox(width: 12 * scale),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${mode.title}  ·  ${mode.tagline}',
                    style: TextStyle(
                      fontFamily: 'Arial',
                      color: uiTheme.textPrimary,
                      fontSize: 13 * scale,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 2 * scale),
                  Text(
                    mode.bestFor,
                    style: TextStyle(fontFamily: 'Arial', color: uiTheme.textMuted, fontSize: 11.5 * scale),
                  ),
                  AppSlideDownCollapse(
                    isExpanded: selected,
                    duration: AppAnim.normal,
                    child: Padding(
                      padding: EdgeInsets.only(top: 5 * scale),
                      child: Text(
                        mode.note,
                        style: TextStyle(fontFamily: 'Arial', color: uiTheme.textDarkMuted, fontSize: 11.5 * scale),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: 12 * scale),
            AppKeyCombo(scale: scale, keys: ['Ctrl', '${mode.digit}'], accent: selected),
          ],
        ),
      ),
    );
  }

  Widget _buildAnime4kStatus(double scale) {
    final a4k = widget.controller.anime4k;
    final error = a4k.error;
    final hasError = error != null && error.isNotEmpty;
    final height = a4k.videoHeight;
    return AppStatTile(
      scale: scale,
      icon: hasError ? Symbols.error_rounded : Symbols.auto_awesome_rounded,
      label: 'Зараз у плеєрі',
      value: hasError ? error : (height > 0 ? '${a4k.summary} · відео ${height}p' : a4k.summary),
      isWarning: hasError,
    );
  }

  Widget _buildAnime4kKeys(double scale) {
    Widget row(String label, List<String> caps) => Padding(
          padding: EdgeInsets.symmetric(vertical: 6 * scale),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(fontFamily: 'Arial', color: uiTheme.textPrimary, fontSize: 12.5 * scale),
                ),
              ),
              SizedBox(width: 12 * scale),
              AppKeyCombo(scale: scale, keys: caps),
            ],
          ),
        );

    final extra = [
      for (final id in const ['a4k_off', 'a4k_toggle', 'a4k_quality'])
        if (ShortcutCatalog.byId[id] case final def?) row(def.label, def.chords.first.caps),
    ];

    return AppCard(
      scale: scale,
      padding: EdgeInsets.symmetric(horizontal: 14 * scale, vertical: 6 * scale),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          row('Обрати режим A, B, C, A+A, B+B, C+A', const ['Ctrl', '1 … 6']),
          ...extra,
        ],
      ),
    );
  }

  // ───────── Гарячі клавіші ─────────

  Widget _buildHotkeysTab(double scale) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildSectionHeader(
          scale,
          'Схема клавіш',
          'Клавіші ↑ ↓ J L O у стандартній схемі та в схемі mpv виконують різні дії',
        ),
        SizedBox(height: 10 * scale),
        AppSegmentedBar<KeyScheme>(
          scale: scale,
          options: [for (final s in KeyScheme.values) AppSegmentOption(value: s, label: s.title)],
          selectedValue: _keyScheme,
          onSelected: (s) => setState(() => _keyScheme = s),
        ),
        SizedBox(height: 8 * scale),
        Row(
          children: [
            Expanded(
              child: Text(
                _keyScheme.summary,
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
        ),
        Divider(color: uiTheme.borderSubtle, height: 24 * scale),
        _buildSectionHeader(
          scale,
          'Усі комбінації',
          'Працюють в будь-якій розкладці. Довідка поверх відео — клавіші ? або F1',
        ),
        SizedBox(height: 10 * scale),
        AppSearchField(
          scale: scale,
          controller: _hotkeysSearch,
          hint: 'Пошук за дією або клавішею',
          onChanged: (v) => setState(() => _hotkeysQuery = v),
        ),
        SizedBox(height: 14 * scale),
        ShortcutsView(scale: scale, scheme: _keyScheme, query: _hotkeysQuery),
      ],
    );
  }

  Widget _buildSubtitlePreview(double scale) {
    final txtColor = _parseHex(_textColor);
    final brdColor = _parseHex(_borderSize > 0 ? '#000000' : '#FFFFFF');

    return Container(
      width: double.infinity,
      height: 90 * scale,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: uiTheme.borderRadius(12 * scale),
        border: Border.all(color: uiTheme.borderSubtle),
        gradient: const LinearGradient(
          colors: [Color(0xFF1E3C72), Color(0xFF2A5298), Color(0xFFE65C00), Color(0xFFF9D423)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(color: Colors.black.withValues(alpha: 0.35)),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.only(bottom: 8 * scale),
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
                          fontSize: (_fontSize * 0.36) * scale,
                          fontWeight: FontWeight.w600,
                          foreground: Paint()
                            ..style = PaintingStyle.stroke
                            ..strokeWidth = (_borderSize * 1.5) * scale
                            ..color = Colors.black,
                        ),
                      ),
                    ),
                  if (_borderSize > 0)
                    Text(
                      'Зразок тексту субтитрів / Sample Text',
                      style: TextStyle(
                        fontFamily: _font,
                        fontSize: (_fontSize * 0.36) * scale,
                        fontWeight: FontWeight.w600,
                        foreground: Paint()
                          ..style = PaintingStyle.stroke
                          ..strokeWidth = (_borderSize * 1.5) * scale
                          ..color = brdColor,
                      ),
                    ),
                  Text(
                    'Зразок тексту субтитрів / Sample Text',
                    style: TextStyle(fontFamily: _font, fontSize: (_fontSize * 0.36) * scale, fontWeight: FontWeight.w600, color: txtColor),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(double scale, {required int index, required IconData icon, required String label}) {
    final isSelected = _activeTab == index;
    return Padding(
      padding: EdgeInsets.only(bottom: 4 * scale),
      child: Material(
        color: Colors.transparent,
        borderRadius: uiTheme.borderRadius(10 * scale),
        child: InkWell(
          borderRadius: uiTheme.borderRadius(10 * scale),
          splashColor: Colors.transparent,
          highlightColor: uiTheme.touchHighlight,
          hoverColor: uiTheme.isLight ? Colors.black.withValues(alpha: 0.04) : Colors.white.withValues(alpha: 0.05),
          onTap: () => setState(() => _activeTab = index),
          child: AppAnimatedContainer(
            duration: AppAnim.fast,
            curve: AppAnim.easeOut,
            height: 42 * scale,
            padding: EdgeInsets.symmetric(horizontal: 10 * scale),
            decoration: BoxDecoration(
              color: isSelected ? uiTheme.bgElevated : Colors.transparent,
              borderRadius: uiTheme.borderRadius(10 * scale),
              border: Border.all(
                color: isSelected ? uiTheme.borderSubtle : Colors.transparent,
                width: 1.0,
              ),
            ),
            child: Row(
              children: [
                AppActivePillIndicator(
                  isSelected: isSelected,
                  scale: scale,
                  color: _accentColor,
                ),
                SizedBox(width: 8 * scale),
                Icon(
                  icon,
                  color: isSelected ? _accentColor : uiTheme.textMuted,
                  size: 17 * scale,
                ),
                SizedBox(width: 10 * scale),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontFamily: 'Arial',
                      color: isSelected ? uiTheme.textPrimary : uiTheme.textMuted,
                      fontSize: 12.5 * scale,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavGroupLabel(double scale, String text) {
    return Padding(
      padding: EdgeInsets.only(left: 10 * scale, bottom: 6 * scale, top: 4 * scale),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'Arial',
          color: uiTheme.textDarkMuted,
          fontSize: 10 * scale,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildAlignedSlider(
    double scale, {
    required String label,
    required String valueText,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 7 * scale),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Arial',
                  color: uiTheme.textPrimary,
                  fontSize: 13 * scale,
                  fontWeight: FontWeight.w400,
                ),
              ),
              Text(
                valueText,
                style: TextStyle(
                  fontFamily: 'Arial',
                  color: uiTheme.textMuted,
                  fontSize: 12.5 * scale,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          SizedBox(height: 4 * scale),
          SliderTheme(
            data: SliderThemeData(
              trackShape: EdgeToEdgeSliderTrackShape(),
              trackHeight: 3.0 * scale,
              activeTrackColor: _accentColor,
              inactiveTrackColor: uiTheme.isLight ? const Color(0xFFE2E2E8) : const Color(0xFF202024),
              thumbColor: _accentColor,
              thumbShape: DotSliderThumbShape(enabledThumbRadius: 6.5 * scale, innerDotRadius: 2.8 * scale),
              overlayShape: RoundSliderOverlayShape(overlayRadius: 8.0 * scale),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  // ── Журнал ────────────────────────────────────────────────────────────────

  String? _logStatus;
  bool _logStatusError = false;

  Future<void> _setDetailedLog(bool value) async {
    StorageService.saveDetailedLog(value);
    await StorageService.flush();
    await AppLog.instance.setDetailed(value);
    if (!mounted) return;
    setState(() {
      _logStatus = value ? 'Детальний журнал увімкнено' : 'Детальний журнал вимкнено';
      _logStatusError = false;
    });
  }

  Future<void> _saveLogToFile() async {
    final c = widget.controller;
    final result = await LogExport.save(extra: [
      ('ПОТОЧНЕ ВІДЕО', 'Файл: ${c.currentFilePath.isEmpty ? '—' : c.currentFilePath}\nНазва: ${c.currentTitle}\nДекодер: ${c.currentHwdec}; швидкість ×${c.currentSpeed}'),
      ('ЖИВІ ЛОГИ LIBMPV (${c.mpvLogs.length} записів)', c.mpvLogs.join('\n')),
    ]);
    if (!mounted || result.cancelled) return;
    setState(() {
      _logStatus = result.saved ? 'Журнал збережено: ${result.fileName}' : 'Не вдалося зберегти журнал: ${result.error ?? 'невідома помилка'}';
      _logStatusError = !result.saved;
    });
  }

  Future<void> _clearLogs() async {
    await AppLog.instance.clear();
    if (!mounted) return;
    setState(() {
      _logStatus = 'Журнали очищено';
      _logStatusError = false;
    });
  }

  Widget _buildLogStatusLine(double scale) {
    return FutureBuilder<int>(
      future: AppLog.instance.totalBytes(),
      builder: (context, snap) {
        final size = snap.data == null ? '' : 'Файли журналу: ${AppLog.bytesLabel(snap.data!)}. ';
        final dir = AppLog.instance.directory;
        final where = Platform.isWindows && dir != null ? 'Тека: ${dir.path}. ' : '';
        final status = _logStatus;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$size$where',
              style: TextStyle(fontFamily: 'Arial', color: uiTheme.textDarkMuted, fontSize: 11.5 * scale),
            ),
            if (status != null) ...[
              SizedBox(height: 4 * scale),
              Text(
                status,
                style: TextStyle(
                  fontFamily: 'Arial',
                  color: _logStatusError ? const Color(0xFFE46767) : _accentColor,
                  fontSize: 12 * scale,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildToggleRow(
    double scale, {
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final bool phone = AppPlatform.isMobile;
    final row = Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontFamily: 'Arial',
                  color: uiTheme.textPrimary,
                  fontSize: 13.5 * scale,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 2 * scale),
              Text(
                subtitle,
                style: TextStyle(
                  fontFamily: 'Arial',
                  color: uiTheme.textDarkMuted,
                  fontSize: 11.5 * scale,
                ),
              ),
            ],
          ),
        ),
        SizedBox(width: 16 * scale),
        GestureDetector(
          onTap: () => onChanged(!value),
          behavior: HitTestBehavior.opaque,
          child: AppAnimatedContainer(
            duration: AppAnim.fast,
            curve: AppAnim.easeOut,
            width: 44 * scale,
            height: 24 * scale,
            padding: EdgeInsets.all(2.5 * scale),
            decoration: BoxDecoration(
              color: value
                  ? _accentColor
                  : (uiTheme.isLight ? const Color(0xFFD4D4DE) : const Color(0xFF28282C)),
              borderRadius: BorderRadius.circular(12 * scale),
              border: Border.all(
                color: value
                    ? _accentColor
                    : (uiTheme.isLight ? const Color(0xFFC0C0CC) : const Color(0xFF38383E)),
                width: 1.0,
              ),
            ),
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 17 * scale,
              height: 17 * scale,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ],
    );
    // Телефон: перемикач завеликий для пальця лише візуально — тапом по всьому рядку (≥ 48 dp) він перемикається
    if (!phone) return row;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!value),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppPlatform.touchTarget),
        child: Align(alignment: Alignment.center, child: row),
      ),
    );
  }

  Widget _buildSectionHeader(double scale, String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontFamily: 'Arial',
            color: uiTheme.textPrimary,
            fontSize: 13.5 * scale,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: 2 * scale),
        Text(
          subtitle,
          style: TextStyle(
            fontFamily: 'Arial',
            color: uiTheme.textDarkMuted,
            fontSize: 11.5 * scale,
          ),
        ),
      ],
    );
  }

  Widget _buildActionPill(
    double scale, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final radiusObj = uiTheme.borderRadius(10 * scale);
    return Material(
      color: uiTheme.bgSurface,
      borderRadius: radiusObj,
      child: InkWell(
        borderRadius: radiusObj,
        onTap: onTap,
        splashColor: Colors.transparent,
        highlightColor: uiTheme.touchHighlight,
        hoverColor: uiTheme.isLight ? Colors.black.withValues(alpha: 0.04) : Colors.white.withValues(alpha: 0.08),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 14 * scale, vertical: 8 * scale),
          decoration: BoxDecoration(
            borderRadius: radiusObj,
            border: Border.all(color: uiTheme.borderSubtle),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: _accentColor, size: 17 * scale),
              SizedBox(width: 8 * scale),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Arial',
                    color: uiTheme.textPrimary,
                    fontSize: 12 * scale,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getTitle() {
    switch (_activeTab) {
      case 0:
        return 'Оформлення та вигляд';
      case 1:
        return 'Стилізація субтитрів';
      case 2:
        return 'Параметри відтворення';
      case 3:
        return 'Відео та апаратне прискорення';
      case 4:
        return 'Аудіодоріжки та звук';
      case 5:
        return 'Інструменти розробника';
      case 6:
        return 'Про програму';
      case 7:
        return 'Апскейл Anime4K';
      case 8:
        return 'Гарячі клавіші';
      default:
        return 'Налаштування';
    }
  }

  String _getSubtitle() {
    switch (_activeTab) {
      case 0:
        return 'Кольори теми, заокруглення інтерфейсу';
      case 1:
        return 'Шрифти, колір, тіні та сумісність з ASS';
      case 2:
        return 'Автопропуск, швидкість і перемотка';
      case 3:
        return 'Декодери NVDEC, D3D11 та оптимізація 120 FPS';
      case 4:
        return 'Корекція тону та пріоритет мов аудіо';
      case 5:
        return 'Конфігураційні файли, логи рушія mpv';
      case 6:
        return 'Інформація про збірку та версію';
      case 7:
        return 'Шейдери для аніме: режими, якість і комбінації клавіш';
      case 8:
        return 'Схема клавіш і повний список комбінацій';
      default:
        return '';
    }
  }
}