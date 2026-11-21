import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader, ByteData;
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
import '../services/hikka_auth.dart';
import '../services/hikka_nav.dart';
import '../services/storage_service.dart';
import '../services/watch_service.dart';
import '../services/system_fonts.dart';
import '../services/ui_theme_service.dart';
import '../services/mpv_config.dart';
import '../services/player_state_controller.dart';
import '../services/shortcut_catalog.dart';
import 'app_tones.dart';
import 'app_ui_kit.dart';
import 'settings_kit.dart';
import 'settings_search.dart';
import 'hikka/hikka_cards.dart' show HikkaProgressBar;
import 'hikka/hikka_page_kit.dart';
import 'hikka/hikka_settings_dialog.dart';
import 'app_animation_kit.dart';
import 'shortcuts_view.dart';
import 'update_prompt.dart';
import '../utils/platform_info.dart';

class AppSettingsDialog extends StatefulWidget {
  final double scale;
  final PlayerStateController controller;

  /// The tab the window opens on (see [tabDeveloper], [tabAbout])
  final int? initialTab;

  /// A navigation tab instead of a window: fills the given space, without "Закрити" and "Готово"
  final bool embedded;

  /// Tab indices reachable from other screens
  static const int tabPlayback = 2;
  static const int tabDeveloper = 5;
  static const int tabAbout = 6;
  static const int tabCatalog = 9;

  const AppSettingsDialog({
    super.key,
    required this.scale,
    required this.controller,
    this.initialTab,
    this.embedded = false,
  });

  static void show(BuildContext context, double scale, PlayerStateController controller, {int? initialTab}) {
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
  late int _activeTab = widget.initialTab ?? 0;

  /// Phone: the start screen with the list of sections is shown until a section is opened (a PC window opens on a tab)
  late bool _menu = widget.initialTab == null && AppPlatform.isMobile;

  /// Embedded page: back (the bar's arrow or the gesture) first clears the search, then returns from a section to the list
  bool _backGuard() {
    if (_menu && _query.isNotEmpty) {
      _search.clear();
      setState(() => _query = '');
      return true;
    }
    if (_menu) return false;
    setState(() => _menu = true);
    return true;
  }
  late final TextEditingController _mikaiKey = TextEditingController(text: WatchService.instance.registry.prefs.mikaiKey);
  late final TextEditingController _moonKey = TextEditingController(text: WatchService.instance.registry.prefs.moonKey);
  late final TextEditingController _clientRef = TextEditingController(text: HikkaAuth.instance.customReference);
  late final TextEditingController _clientSecret = TextEditingController(text: HikkaAuth.instance.customSecret);
  Timer? _keyTimer;
  final TextEditingController _tmdbKey = TextEditingController(text: StorageService.getTmdbKey());
  bool _isResetting = false;

  // Appearance
  late String _themeMode;
  late String _initialThemeMode;

  // Subtitles
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

  // Playback
  late bool _autoplayNext;
  late double _defaultSpeed;
  late int _seekStep;
  late bool _holdToSpeed;
  late bool _seekButtons;
  late bool _mobileSeekButtons;
  late bool _doubleTapSeek;
  late double _holdRate;
  late bool _autoSkip;
  late bool _showSkipButton;
  late bool _listenSkips;
  late bool _themeSongs;
  late PlayerOrientation _playerOrientation;

  // Sound
  late bool _pitchCorrection;
  late String _defaultAudioLang;
  late List<String> _audioLangPriorities;

  // Anime4K
  late bool _a4kEnabled;
  late Anime4kMode _a4kMode;
  late Anime4kQuality _a4kQuality;
  late int _a4kSkipHeight;

  // Hotkeys
  late KeyScheme _keyScheme;
  final TextEditingController _hotkeysSearch = TextEditingController();
  String _hotkeysQuery = '';

  // Initial snapshots for change tracking
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
  late bool _initialShowSkipButton;
  late bool _initialListenSkips;
  late bool _initialThemeSongs;
  late PlayerOrientation _initialPlayerOrientation;

  late bool _initialPitchCorrection;
  late String _initialDefaultAudioLang;
  late List<String> _initialAudioLangPriorities;

  late bool _initialA4kEnabled;
  late Anime4kMode _initialA4kMode;
  late Anime4kQuality _initialA4kQuality;
  late int _initialA4kSkipHeight;
  late KeyScheme _initialKeyScheme;

  final List<String> _builtInFonts = SystemFonts.available;

  @override
  void initState() {
    super.initState();
    _loadFromStorage();
    _saveInitialSnapshot();
    if (widget.embedded) HikkaNav.instance.addBackGuard(_backGuard);
  }

  @override
  void dispose() {
    if (widget.embedded) HikkaNav.instance.removeBackGuard(_backGuard);
    _spotTimer?.cancel();
    _search.dispose();
    _hotkeysSearch.dispose();
    _keyTimer?.cancel();
    _commitKeys();
    _clientRef.dispose();
    _clientSecret.dispose();
    _mikaiKey.dispose();
    _moonKey.dispose();
    _tmdbKey.dispose();
    super.dispose();
  }

  final Set<String> _loadedFonts = {};

  /// Copies fonts into the app folder (the chosen files may be temporary) and adds them to the list.
  /// Returns the name of the last one added, or null.
  Future<String?> _importFonts(Iterable<String> paths) async {
    String? last;
    try {
      final dir = Directory('${StorageService.appBasePath}/fonts/custom');
      if (!await dir.exists()) await dir.create(recursive: true);
      for (final src in paths) {
        final low = src.toLowerCase();
        if (!low.endsWith('.ttf') && !low.endsWith('.otf')) continue;
        final name = src.split(RegExp(r'[/\\]')).last;
        final dst = File('${dir.path}/$name');
        await File(src).copy(dst.path);
        StorageService.addCustomFont(dst.path);
        last = name.split('.').first;
      }
    } catch (e) {
      AppLog.w('субтитри', 'шрифти не додано: $e');
    }
    return last;
  }

  /// The engine does not know custom fonts by itself: without loading, the subtitle sample stays in the system font
  Future<void> _ensureFont(String name) async {
    if (_loadedFonts.contains(name)) return;
    for (final path in StorageService.getCustomFonts()) {
      final base = path.split(RegExp(r'[/\\]')).last.split('.').first;
      if (base != name) continue;
      try {
        final bytes = await File(path).readAsBytes();
        final loader = FontLoader(name)..addFont(Future.value(ByteData.sublistView(bytes)));
        await loader.load();
        _loadedFonts.add(name);
        if (mounted) setState(() {});
      } catch (e) {
        AppLog.w('субтитри', 'шрифт «$name» не завантажено для зразка: $e');
      }
      return;
    }
  }

  void _loadFromStorage() {
    _themeMode = StorageService.getThemeMode(fallback: UiThemeService.defaultThemeMode);

    _font = StorageService.getSubFont(fallback: SystemFonts.defaultFont);
    final customNames = StorageService.getCustomFonts().map((p) => p.split(RegExp(r'[/\\]')).last.split('.').first);
    if (!_builtInFonts.contains(_font) && !customNames.contains(_font)) _font = SystemFonts.defaultFont;
    _ensureFont(_font);
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
    _showSkipButton = StorageService.getShowSkipButton();
    _listenSkips = StorageService.getListenForSkips();
    _themeSongs = StorageService.getShowThemeSongs();
    _playerOrientation = PlayerOrientation.parse(StorageService.getPlayerOrientation());

    _pitchCorrection = StorageService.getPitchCorrection();
    _defaultAudioLang = StorageService.getDefaultAudioLang();
    _audioLangPriorities = StorageService.getAudioLangPriorities();

    // Anime4K and the key scheme can change outside the dialog (menu, Ctrl+1…6), so we take the live state
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
    _initialShowSkipButton = _showSkipButton;
    _initialListenSkips = _listenSkips;
    _initialThemeSongs = _themeSongs;
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
        _showSkipButton != _initialShowSkipButton ||
        _listenSkips != _initialListenSkips ||
        _themeSongs != _initialThemeSongs ||
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
        _themeMode = UiThemeService.defaultThemeMode;
        StorageService.savePhoneUiScale(StorageService.defaultPhoneUiScale);
      } else if (_activeTab == 1) {
        _font = SystemFonts.defaultFont;
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
        _autoSkip = false;
        _showSkipButton = true;
        _listenSkips = true;
        _themeSongs = true;
        _playerOrientation = PlayerOrientation.landscape;
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
      _showSkipButton = _initialShowSkipButton;
      _listenSkips = _initialListenSkips;
      _themeSongs = _initialThemeSongs;
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
    StorageService.saveShowSkipButton(_showSkipButton);
    StorageService.saveListenForSkips(_listenSkips);
    StorageService.saveShowThemeSongs(_themeSongs);
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

  void _keysChanged(String _) {
    _keyTimer?.cancel();
    _keyTimer = Timer(const Duration(milliseconds: 600), _commitKeys);
  }

  void _commitKeys() {
    final prefs = WatchService.instance.registry.prefs;
    final mikai = _mikaiKey.text.trim();
    if (mikai != prefs.mikaiKey) prefs.mikaiKey = mikai;
    final moon = _moonKey.text.trim();
    if (moon != prefs.moonKey) prefs.moonKey = moon;
    HikkaAuth.instance.setCustomClient(_clientRef.text, _clientSecret.text);
  }

  /// Settings sections in the order of the tab strip: (tab index, icon, label). "Гарячі клавіші" is pointless without a keyboard.
  static List<(int, IconData, String)> get _tabs => [
        (0, Symbols.palette_rounded, 'Вигляд'),
        (1, Symbols.subtitles_rounded, 'Субтитри'),
        (9, Symbols.video_library_rounded, 'Каталог'),
        (2, Symbols.play_circle_rounded, 'Відтворення'),
        (3, Symbols.developer_board_rounded, 'Відео & GPU'),
        (7, Symbols.auto_awesome_rounded, 'Anime4K'),
        (4, Symbols.volume_up_rounded, 'Звук'),
        if (!AppPlatform.isMobile) (8, Symbols.keyboard_rounded, 'Гарячі клавіші'),
        (5, Symbols.terminal_rounded, 'Розробник'),
        (6, Symbols.info_rounded, 'Про програму'),
      ];

  // ───────── Search ─────────

  final TextEditingController _search = TextEditingController();
  String _query = '';

  /// The scale slider while it is being dragged
  double? _scaleDraft;

  /// What to spotlight after opening a search result (a row title or a group caption)
  String? _spot;
  int _spotSeq = 0;
  Timer? _spotTimer;

  void _setQuery(String q) => setState(() => _query = q.trim());

  void _openResult(SettingsSearchEntry e) {
    FocusManager.instance.primaryFocus?.unfocus();
    _search.clear();
    setState(() {
      _query = '';
      _activeTab = e.tab;
      _menu = false;
      _spot = e.spot ?? e.title;
      _spotSeq++;
    });
    // The row may be hidden (its switch is off): the request does not wait for it forever
    _spotTimer?.cancel();
    _spotTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _spot != null) setState(() => _spot = null);
    });
  }

  void _spotShown() {
    if (mounted && _spot != null) setState(() => _spot = null);
  }

  /// Search results: icon, title with the match, "section › group" under it
  Widget _buildSearchResults(double scale, {EdgeInsets padding = EdgeInsets.zero, bool shrinkWrap = false}) {
    final found = searchSettings(_query);
    if (found.isEmpty) {
      return Padding(
        padding: EdgeInsets.fromLTRB(12 * scale, 18 * scale, 12 * scale, 18 * scale),
        child: Text('Нічого не знайдено', style: TextStyle(fontFamily: 'Arial', color: uiTheme.textDarkMuted, fontSize: 13 * scale)),
      );
    }
    final rows = [
      Padding(
        padding: EdgeInsets.fromLTRB(12 * scale, 6 * scale, 12 * scale, 4 * scale),
        child: Text(settingsResultsLabel(found.length), style: TextStyle(fontFamily: 'Arial', color: uiTheme.textDarkMuted, fontSize: 12 * scale)),
      ),
      for (final e in found)
        SettingsRow(
          key: ValueKey('settings-result-${e.tab}-${e.title}'),
          scale: scale,
          icon: e.icon,
          title: e.title,
          highlight: _query,
          subtitle: '${_titleOf(e.tab)} › ${e.group}',
          onTap: () => _openResult(e),
        ),
    ];
    return ListView(
      key: const ValueKey('settings-search-results'),
      padding: padding,
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      children: rows,
    );
  }

  // ───────── Start screen (phone) ─────────

  /// The app logo in a circle (the same picture as the launcher icon)
  Widget _appLogo(double scale, double size) => ClipOval(
        child: Image.asset('assets/images/app_logo.png', width: size * scale, height: size * scale, filterQuality: FilterQuality.medium),
      );

  /// Phone: the start screen — who and what (app, Hikka account), search, the list of sections, version at the bottom
  Widget _buildLanding(double scale) {
    final auth = HikkaAuth.instance;
    final account = auth.signedIn && auth.username.isNotEmpty ? 'Hikka: ${auth.username}' : 'Hikka: вхід не виконано';
    Widget tile((int, IconData, String) t) => SettingsSectionTile(
          key: ValueKey('settings-menu-${t.$1}'),
          scale: scale,
          icon: t.$2,
          title: t.$3,
          subtitle: _summaryOf(t.$1),
          onTap: () => setState(() {
            _activeTab = t.$1;
            _menu = false;
          }),
        );
    // A layout builder: the header inset belongs to the context under the collapsing header
    final identity = Padding(
      padding: EdgeInsets.fromLTRB(12 * scale, 10 * scale, 12 * scale, 12 * scale),
      child: Row(
        children: [
          _appLogo(scale, 52),
          SizedBox(width: 14 * scale),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(AppIdentity.name, style: TextStyle(fontFamily: 'Arial', color: uiTheme.textPrimary, fontSize: 20 * scale, fontWeight: FontWeight.bold)),
                SizedBox(height: 3 * scale),
                Text(account, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: 'Arial', color: uiTheme.textDarkMuted, fontSize: 12.5 * scale)),
              ],
            ),
          ),
        ],
      ),
    );
    final search = Padding(
      padding: EdgeInsets.fromLTRB(4 * scale, 0, 4 * scale, 8 * scale),
      child: SettingsSearchBar(scale: scale, controller: _search, onChanged: _setQuery),
    );
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth > 640;
      return ListView(
      key: const ValueKey('settings-menu'),
      padding: EdgeInsets.fromLTRB(8 * scale, 4 + AppHeaderInset.of(context), 8 * scale, 24),
      children: [
        // Wide (landscape): who-and-what and the search share one row
        if (wide)
          Padding(
            padding: EdgeInsets.only(bottom: 6 * scale),
            child: Row(children: [Expanded(child: identity), SizedBox(width: 8 * scale), Expanded(child: search)]),
          )
        else ...[identity, search],
        if (_query.isNotEmpty)
          _buildSearchResults(scale, shrinkWrap: true)
        else ...[
          // A wide screen (landscape): sections in two columns
          if (wide)
            for (var i = 0; i < _tabs.length; i += 2)
              Row(
                children: [
                  Expanded(child: tile(_tabs[i])),
                  SizedBox(width: 8 * scale),
                  Expanded(child: i + 1 < _tabs.length ? tile(_tabs[i + 1]) : const SizedBox.shrink()),
                ],
              )
          else
            for (final t in _tabs) tile(t),
          Padding(
            padding: EdgeInsets.only(top: 18 * scale),
            child: Center(
              child: Text(
                '${AppIdentity.version}   •   ${AppDiagnostics.build}',
                style: TextStyle(fontFamily: 'Arial', color: uiTheme.textDarkMuted, fontSize: 11.5 * scale, letterSpacing: 0.3),
              ),
            ),
          ),
        ],
      ],
    );
    });
  }

  @override
  Widget build(BuildContext context) {
    // Phone: the user's scale ("Вигляд" → "Масштаб налаштувань") instead of the old fixed enlargement
    final scale = AppPlatform.isMobile ? StorageService.getPhoneUiScale() : widget.scale;
    final mq = MediaQuery.of(context);
    // Phone: a start screen with sections, then a section with the tab strip; PC window: the tab strip right away
    final bool phone = AppPlatform.isMobile;
    final bool compact = phone && AppLayout(mq.size).isCompactWidth;
    final bool menu = _menu;
    final EdgeInsets safe = phone ? mq.padding : EdgeInsets.zero;
    final double outerR = phone ? 0 : 22 * scale;
    final bool searching = !phone && _query.isNotEmpty;

    final Widget resetButton = InkWell(
      onTap: _resetCurrentTab,
      borderRadius: uiTheme.borderRadius(8 * scale),
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
          color: _isResetting ? const Color(0xFF00FF66).withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: uiTheme.borderRadius(8 * scale),
          border: Border.all(color: _isResetting ? const Color(0xFF00FF66).withValues(alpha: 0.40) : Colors.transparent),
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
                fontSize: 12.5 * scale,
                fontWeight: _isResetting ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );

    final Widget titleRow = Padding(
      padding: EdgeInsets.only(
        left: (compact ? 18 : 24) * scale,
        right: (compact ? 6 : 20) * scale,
        top: (compact ? 8 : 18) * scale,
        bottom: (compact ? 4 : 10) * scale,
      ),
      child: Row(
        children: [
          if (phone && !menu && !widget.embedded) // embedded: the page bar's arrow (and the back gesture) leads to the list, see the back guard
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: IconButton(
                key: const ValueKey('settings-back'),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(width: 44, height: 48),
                icon: Icon(Symbols.arrow_back_rounded, color: uiTheme.textPrimary, size: 24),
                onPressed: () => setState(() => _menu = true),
              ),
            ),
          Expanded(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: 48 * scale),
              child: AppFadeSwitcher(
                duration: AppAnim.fast,
                child: Column(
                  key: ValueKey<String>(menu ? 'menu' : (searching ? 'search' : '$_activeTab')),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      menu ? 'Налаштування' : (searching ? 'Пошук' : _getTitle()),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontFamily: 'Arial', color: uiTheme.textPrimary, fontSize: 20 * scale, fontWeight: FontWeight.bold),
                    ),
                    if (!menu) ...[
                      SizedBox(height: 2 * scale),
                      Text(
                        searching ? 'У всіх розділах' : _getSubtitle(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontFamily: 'Arial', color: uiTheme.textDarkMuted, fontSize: 12.5 * scale),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          if (!menu && !searching && _activeTab != 6 && _activeTab != 9) ...[resetButton, SizedBox(width: 8 * scale)],
          // PC: the search stays in one place (next to the close button) on every tab
          if (!phone) ...[
            SizedBox(width: 240 * scale, child: SettingsSearchBar(scale: scale, controller: _search, onChanged: _setQuery, compact: true)),
            SizedBox(width: 12 * scale),
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
    );

    final Widget strip = SettingsTabStrip(
      scale: scale,
      tabs: _tabs,
      active: _activeTab,
      padding: EdgeInsets.symmetric(horizontal: (compact ? 16 : 22) * scale),
      onChanged: (t) {
        if (_query.isNotEmpty) _search.clear();
        setState(() {
          _query = '';
          _activeTab = t;
        });
      },
    );

    // Phone: a sideways swipe flips sections (the order follows the tab strip)
    Widget swipeable(Widget child) {
      if (!phone) return child;
      final index = _tabs.indexWhere((t) => t.$1 == _activeTab);
      if (index < 0) return child;
      return HikkaSwipeTabs(
        index: index,
        count: _tabs.length,
        animate: false, // the transition is already animated by AppFadeSlideSwitcher
        onChanged: (i) => setState(() => _activeTab = _tabs[i].$1),
        child: child,
      );
    }

    final Widget tabSwitcher = SettingsSpotlight(
      target: _spot,
      seq: _spotSeq,
      onShown: _spotShown,
      child: AppFadeSlideSwitcher(
        duration: AppAnim.normal,
        child: KeyedSubtree(
          key: ValueKey<int>(_activeTab),
          child: _activeTab == 1 ? _buildSubtitlesTabWithStickyPreview(scale) : _buildScrollableTabWithShadows(scale, _buildTabBody(scale)),
        ),
      ),
    );

    return SettingsFont(
      child: PopScope(
      canPop: widget.embedded || _menu || !phone,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _menu = true);
      },
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: widget.embedded ? double.infinity : (phone ? mq.size.width : 900 * scale),
            height: widget.embedded ? double.infinity : (phone ? mq.size.height : 640 * scale),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (phone)
                  Expanded(
                    child: HikkaCollapsingHeader(
                      resetOn: menu ? -1 : _activeTab,
                      header: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        // The hub's page bar already says «Налаштування»: the embedded start screen has no title row
                        children: menu ? [if (!widget.embedded) titleRow] : [titleRow, strip, const SizedBox(height: 2)],
                      ),
                      body: menu ? _buildLanding(scale) : swipeable(tabSwitcher),
                    ),
                  )
                else ...[
                  titleRow,
                  strip,
                  SizedBox(height: 4 * scale),
                  Expanded(
                    child: searching
                        ? _buildSearchResults(scale, padding: EdgeInsets.fromLTRB(12 * scale, 4 * scale, 12 * scale, 24 * scale))
                        : tabSwitcher,
                  ),
                ],
                if (!widget.embedded || _hasChanges)
                  Padding(
                    padding: EdgeInsets.only(
                      left: (compact ? 16 : 24) * scale,
                      right: (compact ? 16 : 24) * scale,
                      bottom: (compact ? 12 : 16) * scale,
                      top: 8 * scale,
                    ),
                    // Narrow screen: three buttons do not fit in a row, so the row shrinks a bit
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
                                style: TextStyle(fontFamily: 'Arial', color: uiTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 13 * scale),
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
                                style: TextStyle(fontFamily: 'Arial', color: uiTheme.isLight ? _accentColor : Colors.white, fontWeight: FontWeight.bold, fontSize: 13 * scale),
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
                                style: TextStyle(fontFamily: 'Arial', color: uiTheme.isLight ? _accentColor : Colors.white, fontWeight: FontWeight.bold, fontSize: 13 * scale),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
    );
  }

  Widget _footerFit(bool compact, Widget row) => compact
      ? SizedBox(width: double.infinity, child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight, child: row))
      : row;

  /// A universal wrapper for scrollable tabs with soft shadows at the top and bottom
  /// The keyboard is up: the view's inset is set (the page may also be resized by it: depend on the size to rebuild)
  bool _keyboardUp(BuildContext context) {
    MediaQuery.sizeOf(context);
    return View.of(context).viewInsets.bottom > 0;
  }

  Widget _buildScrollableTabWithShadows(double scale, Widget content) {
    return Builder(builder: (context) => Stack(
      children: [
        Positioned.fill(
          child: AppSmoothScrollView(
            padding: EdgeInsets.only(
              left: (AppPlatform.isMobile ? 8 : 12) * scale,
              right: (AppPlatform.isMobile ? 8 : 12) * scale,
              top: 4 * scale + AppHeaderInset.of(context),
              // With the keyboard up there is slack under the content: a search list inside a block can be raised to the top
              bottom: 36 * scale + (_keyboardUp(context) ? 160 * scale : 0),
            ),
            child: Align(
              alignment: Alignment.topLeft,
              child: content,
            ),
          ),
        ),
      ],
    ));
  }

  Widget _buildSubtitlesTabWithStickyPreview(double scale) {
    final names = <String>[
      ..._builtInFonts,
      ...StorageService.getCustomFonts().map((p) => p.split(RegExp(r'[/\\]')).last.split('.').first),
    ];
    // The chosen font may be missing among the available ones (not on the device): we show it instead of crashing
    if (!names.contains(_font)) names.insert(0, _font);
    final fontOptions = names.map((f) => AppDropdownOption(value: f, label: f)).toList();

    // The sample sits over the scroll and moves with the header (an offset from its visibility), while the scroll area's size
    // does not change: otherwise collapsing the header would change the window height and the scroll would jerk
    return Builder(builder: (context) {
      final inset = AppHeaderInset.of(context);
      final shown = AppHeaderInset.maybeOf(context)?.shown;
      final previewH = 90 * scale + 10 * scale;
      Widget preview = ColoredBox(
        color: uiTheme.bgPrimary,
        child: Padding(
          padding: EdgeInsets.fromLTRB(20 * scale, 4 * scale, 20 * scale, 6 * scale),
          child: _buildSubtitlePreview(scale),
        ),
      );
      if (shown != null) {
        preview = AnimatedBuilder(
          animation: shown,
          builder: (_, child) => Transform.translate(offset: Offset(0, inset * shown.value.clamp(0.0, 1.0)), child: child),
          child: preview,
        );
      } else {
        preview = Transform.translate(offset: Offset(0, inset), child: preview);
      }
      return Stack(
        children: [
          Positioned.fill(
                child: AppSmoothScrollView(
                  padding: EdgeInsets.only(
                    left: (AppPlatform.isMobile ? 8 : 12) * scale,
                    right: (AppPlatform.isMobile ? 8 : 12) * scale,
                    top: inset + previewH + 4 * scale,
                    bottom: 36 * scale,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SettingsGroup(
                        scale: scale,
                        label: 'Субтитри',
                        rows: [
                          SettingsToggleRow(
                            scale: scale,
                            icon: Symbols.subtitles_rounded,
                            title: 'Автоматичне ввімкнення субтитрів',
                            subtitle: 'За списком мов нижче',
                            value: _subtitlesEnabled,
                            onChanged: (enabled) {
                              setState(() {
                                _subtitlesEnabled = enabled;
                                _defaultSubLang = enabled ? (_subLangPriorities.isNotEmpty ? _subLangPriorities.first : 'uk') : 'no';
                              });
                            },
                          ),
                          if (_subtitlesEnabled)
                            SettingsPad(
                              scale: scale,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: EdgeInsets.only(bottom: 8 * scale),
                                    child: Text(
                                      'Пріоритет мов: перетягуйте для зміни, плеєр обере першу знайдену мову',
                                      style: TextStyle(fontFamily: 'Arial', color: uiTheme.textDarkMuted, fontSize: 12 * scale, height: 1.3),
                                    ),
                                  ),
                                  AppLanguagePriorityList(
                                    scale: scale,
                                    languages: _subLangPriorities,
                                    onChanged: (newList) => setState(() => _subLangPriorities = newList),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      SettingsGroup(
                        scale: scale,
                        label: 'Стилі SSA / ASS',
                        rows: [
                          SettingsChoiceRow<String>(
                            scale: scale,
                            icon: Symbols.style_rounded,
                            title: 'Вигляд субтитрів SSA',
                            subtitle: 'Перезаписати стилі субтитрів SSA',
                            options: const [('no', 'Оригінал (ASS)'), ('yes', 'Лише діалоги'), ('force', 'Примусово (Force)')],
                            value: _assMode,
                            onChanged: (val) {
                              setState(() => _assMode = val);
                              _applySubtitles();
                            },
                          ),
                        ],
                      ),
                      SettingsGroup(
                        scale: scale,
                        label: 'Шрифт',
                        rows: [
                          SettingsChoiceRow<String>(
                            scale: scale,
                            icon: Symbols.font_download_rounded,
                            title: 'Шрифт субтитрів',
                            options: [for (final o in fontOptions) (o.value, o.label)],
                            value: _font,
                            onChanged: (newFont) {
                              setState(() => _font = newFont);
                              _ensureFont(newFont);
                              _applySubtitles();
                            },
                          ),
                          SettingsRow(
                            scale: scale,
                            icon: Symbols.upload_file_rounded,
                            title: 'Додати свій шрифт',
                            subtitle: 'Файл .ttf або .otf',
                            onTap: () async {
                              final res = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['ttf', 'otf']);
                              final path = res?.files.first.path;
                              if (path == null) return;
                              final name = await _importFonts([path]);
                              if (name != null && mounted) {
                                setState(() => _font = name);
                                _ensureFont(name);
                                _applySubtitles();
                              }
                            },
                          ),
                          SettingsRow(
                            scale: scale,
                            icon: Symbols.create_new_folder_rounded,
                            title: Platform.isAndroid ? 'Додати кілька шрифтів' : 'Додати теку зі шрифтами',
                            onTap: () async {
                              final paths = <String>[];
                              if (Platform.isAndroid) {
                                // Android does not let us read folders directly: we pick several files at once
                                final res = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['ttf', 'otf'], allowMultiple: true);
                                paths.addAll([for (final f in res?.files ?? const <PlatformFile>[]) if (f.path != null) f.path!]);
                              } else {
                                final dir = await FilePicker.getDirectoryPath();
                                if (dir == null) return;
                                try {
                                  for (final f in Directory(dir).listSync(recursive: true, followLinks: false)) {
                                    if (f is File) paths.add(f.path);
                                  }
                                } catch (e) {
                                  AppLog.w('субтитри', 'тека шрифтів недоступна: $e');
                                }
                              }
                              final name = await _importFonts(paths);
                              if (name != null && mounted) {
                                setState(() => _font = name);
                                _ensureFont(name);
                                _applySubtitles();
                              }
                            },
                          ),
                        ],
                      ),
                      SettingsGroup(
                        scale: scale,
                        label: 'Вигляд тексту',
                        rows: [
                          SettingsSliderRow(scale: scale, icon: Symbols.format_size_rounded, title: 'Розмір шрифту', valueLabel: '${_fontSize.toInt()} px', value: _fontSize, min: 24.0, max: 80.0, onChanged: (v) { setState(() => _fontSize = v.roundToDouble()); _applySubtitles(); }),
                          SettingsSliderRow(scale: scale, icon: Symbols.border_style_rounded, title: 'Товщина обводки', valueLabel: '${_borderSize.toStringAsFixed(1)} px', value: _borderSize, min: 0.0, max: 8.0, onChanged: (v) { setState(() => _borderSize = (v * 10).round() / 10); _applySubtitles(); }),
                          SettingsSliderRow(scale: scale, icon: Symbols.blur_on_rounded, title: 'Тінь', valueLabel: '${_shadowOffset.toStringAsFixed(1)} px', value: _shadowOffset, min: 0.0, max: 6.0, onChanged: (v) { setState(() => _shadowOffset = (v * 10).round() / 10); _applySubtitles(); }),
                          SettingsSliderRow(scale: scale, icon: Symbols.vertical_align_bottom_rounded, title: 'Відступ знизу', valueLabel: '${_marginY.toInt()} px', value: _marginY, min: 10.0, max: 80.0, onChanged: (v) { setState(() => _marginY = v.roundToDouble()); _applySubtitles(); }),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          Positioned(top: 0, left: 0, right: 0, child: preview),
        ],
      );
    });
  }

  Widget _buildTabBody(double scale) {
    switch (_activeTab) {
      case 0: // ВИГЛЯД
        final swatchRadius = uiTheme.borderRadius(8 * scale);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SettingsGroup(
              scale: scale,
              label: 'Оформлення',
              rows: [
                SettingsChoiceRow<String>(
                  scale: scale,
                  icon: Symbols.dark_mode_rounded,
                  title: 'Тема оформлення',
                  subtitle: 'Колірна схема вигляду',
                  options: const [('system', 'Авто (система)'), ('dark', 'Темна'), ('light', 'Світла')],
                  value: _themeMode,
                  onChanged: (val) {
                    setState(() => _themeMode = val);
                    uiTheme.setThemeMode(val);
                  },
                ),
                SettingsChoiceRow<String>(
                  scale: scale,
                  icon: Symbols.rounded_corner_rounded,
                  title: 'Радіус заокруглення',
                  subtitle: 'Кутів кнопок, карток та елементів',
                  options: const [('Без', 'Без'), ('XS', 'XS'), ('SM', 'SM'), ('MD', 'MD'), ('LG', 'LG'), ('XL', 'XL')],
                  value: uiTheme.radiusKey,
                  onChanged: (r) {
                    uiTheme.setRadiusKey(r);
                    setState(() {});
                  },
                ),
                // Applied when the finger is lifted: otherwise the slider would move under the finger while it is dragged
                if (AppPlatform.isMobile)
                  SettingsSliderRow(
                    scale: scale,
                    icon: Symbols.zoom_in_rounded,
                    title: 'Масштаб налаштувань',
                    subtitle: 'Розмір тексту й рядків на цьому пристрої',
                    valueLabel: '${((_scaleDraft ?? StorageService.getPhoneUiScale()) * 100).round()} %',
                    value: _scaleDraft ?? StorageService.getPhoneUiScale(),
                    min: 0.8,
                    max: 1.15,
                    divisions: 7,
                    onChanged: (v) => setState(() => _scaleDraft = v),
                    onChangeEnd: (v) => setState(() {
                      StorageService.savePhoneUiScale((v * 20).round() / 20);
                      _scaleDraft = null;
                    }),
                  ),
              ],
            ),
            SettingsGroup(
              scale: scale,
              label: 'Основний колір',
              rows: [
                SettingsRow(
                  scale: scale,
                  icon: Symbols.format_color_fill_rounded,
                  title: 'Акцентний колір',
                  subtitle: 'Інтерфейс плеєра · ${uiTheme.accentHex}',
                  // Wrap: on a narrow phone screen the colors go to a second row
                  below: Wrap(
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
                          width: 38 * scale,
                          height: 38 * scale,
                          margin: EdgeInsets.only(right: 4 * scale),
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
                            ),
                            child: isCur ? Icon(Symbols.check_rounded, color: Colors.black, size: 17 * scale) : null,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ],
        );

      case 2: // ВІДТВОРЕННЯ
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SettingsGroup(
              scale: scale,
              label: 'Відтворення',
              rows: [
                SettingsToggleRow(
                  scale: scale,
                  icon: Symbols.autoplay_rounded,
                  title: 'Автовідтворення наступного епізоду',
                  subtitle: 'Після завершення серії автоматично вмикається наступна',
                  value: _autoplayNext,
                  onChanged: (v) => setState(() => _autoplayNext = v),
                ),
                SettingsChoiceRow<double>(
                  scale: scale,
                  icon: Symbols.speed_rounded,
                  title: 'Швидкість за замовчуванням',
                  subtitle: 'Застосовується до кожного нового відео',
                  options: const [(0.75, '0.75x'), (1.0, '1.0x'), (1.25, '1.25x'), (1.5, '1.5x'), (2.0, '2.0x')],
                  value: _defaultSpeed,
                  onChanged: (v) => setState(() => _defaultSpeed = v),
                ),
                if (AppPlatform.isMobile)
                  SettingsChoiceRow<PlayerOrientation>(
                    scale: scale,
                    icon: Symbols.screen_rotation_rounded,
                    title: 'Орієнтація плеєра',
                    subtitle: 'У якій орієнтації відкривається відео',
                    options: [for (final o in PlayerOrientation.values) (o, o.label)],
                    value: _playerOrientation,
                    onChanged: (v) => setState(() => _playerOrientation = v),
                  ),
              ],
            ),
            SettingsGroup(
              scale: scale,
              label: 'Перемотування',
              rows: [
                SettingsChoiceRow<int>(
                  scale: scale,
                  icon: Symbols.fast_forward_rounded,
                  title: 'Крок перемотування',
                  subtitle: AppPlatform.isMobile ? 'Для подвійного дотику та кнопок на екрані' : 'Для клавіш J / L, стрілок чи кнопок на панелі',
                  options: const [(5, '±5 сек'), (10, '±10 сек'), (15, '±15 сек'), (30, '±30 сек')],
                  value: _seekStep,
                  onChanged: (v) => setState(() => _seekStep = v),
                ),
                SettingsToggleRow(
                  scale: scale,
                  icon: Symbols.touch_app_rounded,
                  title: 'Перемотування подвійним дотиком',
                  subtitle: 'Подвійний дотик ліворуч чи праворуч на екрані плеєра',
                  value: _doubleTapSeek,
                  onChanged: (v) => setState(() => _doubleTapSeek = v),
                ),
                if (AppPlatform.isMobile)
                  SettingsToggleRow(
                    scale: scale,
                    icon: Symbols.forward_10_rounded,
                    title: 'Кнопки перемотування на екрані',
                    subtitle: 'Кнопки «назад» і «вперед» біля кнопки паузи',
                    value: _mobileSeekButtons,
                    onChanged: (v) => setState(() => _mobileSeekButtons = v),
                  )
                else
                  SettingsToggleRow(
                    scale: scale,
                    icon: Symbols.forward_10_rounded,
                    title: 'Кнопки перемотування на панелі',
                    subtitle: 'Кнопки «назад» і «вперед» біля кнопки паузи',
                    value: _seekButtons,
                    onChanged: (v) => setState(() => _seekButtons = v),
                  ),
              ],
            ),
            SettingsGroup(
              scale: scale,
              label: 'Прискорення',
              rows: [
                SettingsToggleRow(
                  scale: scale,
                  icon: Symbols.pan_tool_rounded,
                  title: 'Прискорення утримуванням',
                  subtitle: 'Тимчасово збільшує швидкість, доки утримується екран',
                  value: _holdToSpeed,
                  onChanged: (v) => setState(() => _holdToSpeed = v),
                ),
                if (_holdToSpeed)
                  SettingsChoiceRow<double>(
                    scale: scale,
                    icon: Symbols.bolt_rounded,
                    title: 'Швидкість прискорення',
                    subtitle: 'З якою швидкістю йде відео під час утримування',
                    options: const [(1.5, '1.5x'), (2.0, '2.0x'), (2.5, '2.5x'), (3.0, '3.0x')],
                    value: _holdRate,
                    onChanged: (v) => setState(() => _holdRate = v),
                  ),
              ],
            ),
            SettingsGroup(
              scale: scale,
              label: 'Опенінґ та ендінґ',
              rows: [
                SettingsToggleRow(
                  scale: scale,
                  icon: Symbols.skip_next_rounded,
                  title: 'Кнопка пропуску опенінґу й ендінґу',
                  subtitle: 'Показується під час опенінґу чи ендінґу',
                  value: _showSkipButton,
                  onChanged: (v) => setState(() => _showSkipButton = v),
                ),
                SettingsToggleRow(
                  scale: scale,
                  icon: Symbols.keyboard_double_arrow_right_rounded,
                  title: 'Автоматичний пропуск',
                  subtitle: 'Пропуск без натискання кнопки',
                  value: _autoSkip,
                  onChanged: (v) => setState(() => _autoSkip = v),
                ),
                SettingsToggleRow(
                  scale: scale,
                  icon: Symbols.graphic_eq_rounded,
                  title: 'Шукати опенінґ за звуком',
                  subtitle: 'Коли сайт не дав таймкодів: порівнює початок двох серій (через Wi‑Fi чи із завантажених)',
                  value: _listenSkips,
                  onChanged: (v) => setState(() => _listenSkips = v),
                ),
                SettingsToggleRow(
                  scale: scale,
                  icon: Symbols.album_rounded,
                  title: 'Пісня опенінґу й ендінґу',
                  subtitle: 'Обкладинка й назва на початку пісні; дотик — послухати в Spotify, YouTube Music, Apple Music',
                  value: _themeSongs,
                  onChanged: (v) => setState(() => _themeSongs = v),
                ),
              ],
            ),
          ],
        );

      case 3: // ВІДЕО & GPU
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SettingsGroup(
              scale: scale,
              label: 'Декодування',
              hint: 'У більшості випадків достатньо автоматичного вибору',
              rows: [
                SettingsChoiceRow<String>(
                  scale: scale,
                  icon: Symbols.memory_rounded,
                  title: 'Апаратний декодер відео',
                  options: [for (final e in AppConstants.hwdecOptions.entries) (e.key, e.value)],
                  value: widget.controller.currentHwdec,
                  onChanged: (newHwdec) async {
                    await widget.controller.changeHwdec(newHwdec);
                    setState(() {});
                  },
                ),
              ],
            ),
          ],
        );

      case 4: // ЗВУК
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SettingsGroup(
              scale: scale,
              label: 'Звук',
              rows: [
                SettingsToggleRow(
                  scale: scale,
                  icon: Symbols.graphic_eq_rounded,
                  title: 'Корекція висоти тону',
                  subtitle: 'Голос звучить природно за швидкості понад 1×',
                  value: _pitchCorrection,
                  onChanged: (v) => setState(() => _pitchCorrection = v),
                ),
              ],
            ),
            SettingsGroup(
              scale: scale,
              label: 'Пріоритет мов звукових доріжок',
              hint: 'Перетягуйте для зміни пріоритету; плеєр обере першу знайдену мову',
              rows: [
                SettingsPad(
                  scale: scale,
                  child: AppLanguagePriorityList(
                    scale: scale,
                    languages: _audioLangPriorities,
                    onChanged: (newList) => setState(() => _audioLangPriorities = newList),
                  ),
                ),
              ],
            ),
          ],
        );

      case 7: // ANIME4K
        return _buildAnime4kTab(scale);

      case 8: // ГАРЯЧІ КЛАВІШІ
        return _buildHotkeysTab(scale);

      case 9: // КАТАЛОГ
        return HikkaCatalogSettings(scale: scale);

      case 5: // РОЗРОБНИК
        Widget keyRow(String title, String hint, TextEditingController c, IconData icon, String placeholder, ValueChanged<String> onChanged) => SettingsRow(
              scale: scale,
              icon: icon,
              title: title,
              subtitle: hint,
              below: AppSearchField(scale: scale, controller: c, icon: Symbols.edit_rounded, hint: placeholder, onChanged: onChanged),
            );
        Widget action(IconData icon, String label, VoidCallback onTap) => SettingsRow(scale: scale, icon: icon, title: label, onTap: onTap);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SettingsGroup(
              scale: scale,
              label: 'Експериментальні функції',
              hint: 'Функції, які ще не є частиною основного інтерфейсу',
              rows: [
                SettingsToggleRow(
                  scale: scale,
                  icon: Symbols.video_file_rounded,
                  title: 'Локальна медіатека',
                  subtitle: 'Відкриття файлів і посилань, історія та плейлисти. Розділ з’явиться у «Профілі»',
                  value: StorageService.getLocalLibrary(),
                  onChanged: (v) => setState(() => StorageService.saveLocalLibrary(v)),
                ),
              ],
            ),
            SettingsGroup(
              scale: scale,
              label: 'Ключі',
              rows: [
                keyRow('Ключ TheMovieDB', 'Необов’язково. Запасні банери на головній, українські назви й кадри серій', _tmdbKey, Symbols.key_rounded, 'Вставте ключ', StorageService.saveTmdbKey),
                keyRow('Ключ Mikai', 'Необов’язково. З ключем ліміт становить 300 запитів на хвилину замість 60', _mikaiKey, Symbols.key_rounded, 'Вставте ключ', _keysChanged),
                keyRow('Ключ Moon', 'Необов’язково. Власний ключ (наприклад, Premium) використовується замість вбудованого', _moonKey, Symbols.key_rounded, 'Вставте ключ', _keysChanged),
              ],
            ),
            SettingsGroup(
              scale: scale,
              label: 'Власний клієнт Hikka',
              hint: 'Потрібен лише тоді, коли вбудований клієнт перестав працювати. Зміни застосовуються після наступного входу',
              rows: [
                keyRow('Референс клієнта', '', _clientRef, Symbols.badge_rounded, 'Референс клієнта', _keysChanged),
                keyRow('Ключ клієнта', '', _clientSecret, Symbols.key_rounded, 'Ключ клієнта', _keysChanged),
              ],
            ),
            SettingsGroup(
              scale: scale,
              label: 'Журнал',
              hint: 'Запис дій застосунку для пошуку помилок',
              rows: [
                SettingsToggleRow(
                  scale: scale,
                  icon: Symbols.description_rounded,
                  title: 'Детальний журнал',
                  subtitle: 'Докладніший запис у файл. Повною мірою діє після перезапуску',
                  value: AppLog.instance.detailed,
                  onChanged: _setDetailedLog,
                ),
                action(Symbols.download_rounded, 'Зберегти журнал у файл', _saveLogToFile),
                action(Symbols.delete_outline_rounded, 'Очистити журнали', _clearLogs),
                if (Platform.isWindows)
                  action(Symbols.folder_open_rounded, 'Відкрити папку журналів', () async {
                    final dir = AppLog.instance.directory;
                    if (dir == null) return;
                    await dir.create(recursive: true);
                    Process.run('explorer.exe', [dir.path]);
                  }),
                SettingsPad(scale: scale, indent: true, child: _buildLogStatusLine(scale)),
              ],
            ),
            SettingsGroup(
              scale: scale,
              label: 'Конфігурація та кеш',
              hint: 'Файли налаштувань плеєра та історія перегляду',
              rows: [
                // The file explorer exists only on Windows; the phone has no such row
                if (Platform.isWindows) action(Symbols.folder_open_rounded, 'Відкрити папку конфігів', () => Process.run('explorer.exe', [StorageService.appBasePath])),
                action(Symbols.history_rounded, 'Очистити історію перегляду', () {
                  StorageService.clearRecentFiles();
                  setState(() {});
                }),
              ],
            ),
            SettingsGroup(
              scale: scale,
              label: 'Журнал плеєра',
              hint: 'Останні записи',
              rows: [
                Container(
                  height: 180 * scale,
                  margin: EdgeInsets.fromLTRB(12 * scale, 6 * scale, 12 * scale, 8 * scale),
                  padding: EdgeInsets.all(10 * scale),
                  decoration: BoxDecoration(color: uiTheme.bgSurface, borderRadius: uiTheme.borderRadius(12 * scale), border: Border.all(color: uiTheme.borderSubtle)),
                  child: ListView.builder(
                    itemCount: widget.controller.mpvLogs.length,
                    itemBuilder: (ctx, i) {
                      final log = widget.controller.mpvLogs[i];
                      return Text(
                        log,
                        style: TextStyle(
                          fontFamily: 'Consolas',
                          fontSize: 10.5 * scale,
                          color: log.contains('error') ? Colors.redAccent : (uiTheme.isLight ? const Color(0xFF222226) : Colors.white70),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        );

      case 6: // ПРО ПРОГРАМУ
        return Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // The full-body mascot
                Image.asset('assets/images/app_mascot.png', width: 120 * scale, height: 120 * scale, filterQuality: FilterQuality.medium),
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
                        '• ${AppIdentity.tagline}\n• Дані каталогу — hikka.io\n• Банери: AniList; запасні — TheMovieDB\n• Назви й кадри серій: TheMovieDB, MoonAnime, MyAnimeList (через Tenrai), Anime Skip\n• Використовує TMDB API, але не схвалений і не сертифікований TMDB\n• Відео — libmpv: D3D11 і NVDEC на ПК, MediaCodec на телефоні\n• Субтитри SSA/ASS, шейдери Anime4K\n• Шрифти: Arial / Liberation Sans',
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

  // ───────── Updates ─────────

  Widget _buildUpdateBlock(double scale) {
    final updater = AppUpdater.instance;
    final text = TextStyle(fontFamily: 'Arial', color: uiTheme.textMuted, fontSize: 12 * scale, height: 1.4);
    return ListenableBuilder(
      listenable: Listenable.merge([updater.state, updater.download]),
      builder: (context, _) {
        final st = updater.state.value;
        final d = updater.download.value;
        final checking = st is UpdateChecking;
        String title;
        String? sub;
        Color? subColor;
        Widget? progress;
        Widget? primary;
        switch (st) {
          case UpdateAvailable(:final info):
            final size = info.size > 0 ? ' · ${updateMegabytes(info.size)}' : '';
            final inApp = updater.canInstallInApp(info);
            void open() => UpdatePrompt.show(context, scale: scale, info: info, updater: updater, start: true);
            title = 'Доступна версія ${info.version}';
            sub = info.notes.isEmpty ? 'Файл: ${info.assetName.isEmpty ? 'сторінка релізу' : info.assetName}$size' : info.notes;
            if (d is DownloadRunning && d.version == info.version) {
              title = 'Завантаження версії ${info.version}';
              sub = null;
              progress = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3 * scale),
                    child: HikkaProgressBar(value: d.fraction ?? 0, height: 6 * scale),
                  ),
                  SizedBox(height: 6 * scale),
                  Text(UpdatePrompt.progressText(d), style: text),
                ],
              );
              primary = AppSecondaryButton(
                scale: scale,
                label: 'Скасувати',
                icon: Symbols.close_rounded,
                expand: false,
                onTap: updater.cancelDownload,
              );
            } else if (updater.readyFor(info.version) != null) {
              title = 'Версія ${info.version} завантажена';
              sub = updater.installRestartsApp
                  ? 'Під час встановлення Miki Miki закриється й відкриється знову.'
                  : 'Залишилось підтвердити встановлення.';
              primary = AppAccentButton(scale: scale, label: 'Встановити', icon: Symbols.system_update_rounded, onTap: open);
            } else if (d is DownloadFailed && d.version == info.version) {
              sub = d.message;
              subColor = AppTones.danger;
              primary = AppAccentButton(scale: scale, label: 'Спробувати ще', icon: Symbols.refresh_rounded, onTap: open);
            } else {
              primary = AppAccentButton(
                scale: scale,
                label: inApp ? 'Оновити' : 'Завантажити',
                icon: Symbols.download_rounded,
                onTap: inApp ? open : () => SystemControls.openUrl(info.target),
              );
            }
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
            sub = 'Нові версії беруться з GitHub (${AppUpdater.repo}) і встановлюються прямо із застосунку';
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
                  style: subColor == null ? text : text.copyWith(color: subColor),
                ),
              ],
              if (progress != null) ...[
                SizedBox(height: 10 * scale),
                progress,
              ],
              SizedBox(height: 12 * scale),
              Wrap(
                spacing: 10 * scale,
                runSpacing: 10 * scale,
                children: [
                  if (primary != null) primary,
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
        SettingsGroup(
          scale: scale,
          rows: [
            SettingsToggleRow(
              scale: scale,
              icon: Symbols.auto_awesome_rounded,
              title: 'Anime4K',
              subtitle: 'Підвищує чіткість ліній і роздільність відео в реальному часі',
              value: _a4kEnabled,
              onChanged: (v) => setState(() => _a4kEnabled = v),
            ),
          ],
        ),
        AppSlideDownCollapse(
          isExpanded: _a4kEnabled,
          duration: AppAnim.medium,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              SettingsGroup(
                scale: scale,
                label: 'Режим',
                hint: 'Можна змінювати й під час перегляду',
                rows: [for (final mode in Anime4kMode.values) _buildAnime4kModeRow(scale, mode)],
              ),
              SettingsGroup(
                scale: scale,
                label: 'Якість',
                hint: AppPlatform.isMobile ? _a4kQuality.deviceHint : _a4kQuality.gpuHint,
                rows: [
                  SettingsChoiceRow<Anime4kQuality>(
                    scale: scale,
                    icon: Symbols.high_quality_rounded,
                    title: 'Якість шейдерів',
                    subtitle: 'Fast менше навантажує пристрій, HQ дає чіткіше зображення',
                    options: [for (final q in Anime4kQuality.values) (q, '${q.label} · ${q.title}')],
                    value: _a4kQuality,
                    onChanged: (q) => setState(() => _a4kQuality = q),
                  ),
                  SettingsChoiceRow<int>(
                    scale: scale,
                    icon: Symbols.aspect_ratio_rounded,
                    title: 'Вимикати для високої роздільності',
                    subtitle: 'Шейдери не застосовуються, коли збільшення вже не потрібне',
                    options: [for (final (value, label) in _skipHeights) (value, label)],
                    value: _skipHeights.any((o) => o.$1 == _a4kSkipHeight) ? _a4kSkipHeight : 0,
                    onChanged: (v) => setState(() => _a4kSkipHeight = v),
                  ),
                ],
              ),
            ],
          ),
        ),
        SettingsGroup(scale: scale, label: 'Стан', rows: [SettingsPad(scale: scale, child: _buildAnime4kStatus(scale))]),
        // Ctrl + digit key combinations are keyboard-only; we do not show them on a phone
        if (!AppPlatform.isMobile) SettingsGroup(scale: scale, label: 'Клавіші', rows: [SettingsPad(scale: scale, child: _buildAnime4kKeys(scale))]),
        Padding(
          padding: EdgeInsets.fromLTRB(12 * scale, 8 * scale, 12 * scale, 0),
          child: Text(
            AppPlatform.isMobile
                ? 'Шейдери bloc97/Anime4K v4.0.1 (ліцензія MIT) вбудовані в застосунок. Режими A+A, B+B і C+A мають сенс лише тоді, '
                    'коли картинку збільшують удвічі й більше.'
                : 'Шейдери bloc97/Anime4K v4.0.1 (ліцензія MIT) вбудовані в застосунок. Поки Anime4K увімкнений, '
                    'він замінює список glsl-shaders із вашого mpv.conf. Режими A+A, B+B і C+A мають сенс лише тоді, '
                    'коли картинку збільшують удвічі й більше.',
            style: TextStyle(fontFamily: 'Arial', color: uiTheme.textDarkMuted, fontSize: 12 * scale, height: 1.4),
          ),
        ),
      ],
    );
  }

  /// A mode row: a radio mark, title, what it is best for; the chosen one shows a note; on a PC the Ctrl+digit keys on the right
  Widget _buildAnime4kModeRow(double scale, Anime4kMode mode) {
    final selected = _a4kMode == mode;
    return SettingsRadioRow(
      scale: scale,
      title: '${mode.title}  ·  ${mode.tagline}',
      subtitle: selected ? '${mode.bestFor}\n${mode.note}' : mode.bestFor,
      selected: selected,
      onTap: () => setState(() {
        _a4kMode = mode;
        _a4kEnabled = true;
      }),
      trailing: AppPlatform.isMobile ? null : AppKeyCombo(scale: scale, keys: ['Ctrl', '${mode.digit}'], accent: selected),
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

  // ───────── Hotkeys ─────────

  Widget _buildHotkeysTab(double scale) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SettingsRadioGroup<KeyScheme>(
          scale: scale,
          label: 'Схема клавіш',
          hint: 'Схеми по-різному використовують клавіші ↑ ↓ J L O. J діє лише в цій схемі: ${_keyScheme.summary}',
          options: [for (final s in KeyScheme.values) (s, s.title, null)],
          value: _keyScheme,
          onChanged: (s) => setState(() => _keyScheme = s),
        ),
        SettingsGroup(
          scale: scale,
          label: 'Усі комбінації',
          hint: 'Працюють у будь-якій розкладці. Довідка в плеєрі — клавіша ? або F1',
          rows: [
            SettingsPad(
              scale: scale,
              child: AppSearchField(
                scale: scale,
                controller: _hotkeysSearch,
                hint: 'Пошук за дією або клавішею',
                onChanged: (v) => setState(() => _hotkeysQuery = v),
              ),
            ),
            SettingsPad(scale: scale, child: ShortcutsView(scale: scale, scheme: _keyScheme, query: _hotkeysQuery)),
          ],
        ),
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
              padding: EdgeInsets.only(bottom: (_marginY * 0.25).clamp(2.0, 20.0) * scale),
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
                            ..strokeJoin = StrokeJoin.round
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
                          ..strokeJoin = StrokeJoin.round
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

  // ── Log ────────────────────────────────────────────────────────────────

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

  String _getTitle() => _titleOf(_activeTab);

  String _titleOf(int tab) {
    switch (tab) {
      case 0:
        return 'Вигляд';
      case 1:
        return 'Субтитри';
      case 2:
        return 'Відтворення';
      case 3:
        return 'Відео & GPU';
      case 4:
        return 'Звук';
      case 5:
        return 'Розробник';
      case 6:
        return 'Про програму';
      case 7:
        return 'Anime4K';
      case 8:
        return 'Гарячі клавіші';
      case 9:
        return 'Каталог';
      default:
        return 'Налаштування';
    }
  }

  String _getSubtitle() => _subtitleOf(_activeTab);

  /// What a section holds (the start screen)
  String _summaryOf(int tab) => _subtitleOf(tab);

  String _subtitleOf(int tab) {
    switch (tab) {
      case 0:
        return 'Тема, акцентний колір, заокруглення';
      case 1:
        return 'Мови, шрифт і вигляд тексту';
      case 2:
        return 'Швидкість, перемотування та пропуск';
      case 3:
        return 'Апаратне декодування';
      case 4:
        return 'Висота тону та мови доріжок';
      case 5:
        return 'Журнал, ключі та експериментальні функції';
      case 6:
        return 'Версія, оновлення та джерела';
      case 7:
        return 'Покращення якості зображення шейдерами';
      case 8:
        return 'Схема та перелік клавіш';
      case 9:
        return 'Назви, джерела та кеш';
      default:
        return '';
    }
  }
}