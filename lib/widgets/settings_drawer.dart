import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:media_kit/media_kit.dart';
import '../constants/app_constants.dart';
import '../models/media_models.dart';
import '../services/anime4k_controller.dart';
import '../services/anime4k_service.dart';
import '../services/storage_service.dart';
import '../services/ui_theme_service.dart';
import '../utils/formatters.dart';
import '../utils/platform_info.dart';
import 'app_animation_kit.dart';
import 'app_ui_kit.dart';

class SettingsDrawer extends StatelessWidget {
  final double scale;
  final double screenWidth;
  final double drawerAnchorPixelX;
  final bool drawerIsTop;

  /// Телефон: лише шапка й список без власної поверхні та прив'язки до кнопки —
  /// фон, положення й затемнення дає [MobileSheetFrame]
  final bool sheet;
  final String activeDrawer;
  final String? activeDrawerPrev;
  final Player player;
  final double currentSpeed;
  final String currentHwdec;
  final List<CachedSubtitleTrack> subtitleTracks;
  final List<CachedAudioTrack> audioTracks;
  final List<VideoChapter> chapters;
  final ScrollController scrollController;
  final VoidCallback onClose;
  final VoidCallback onBack;
  final ValueChanged<String> onOpenSubDrawer;
  final ValueChanged<double> onSpeedSelected;
  final ValueChanged<SubtitleTrack> onSubtitleSelected;

  /// «Додати файл субтитрів…» у меню субтитрів (без нього пункту нема)
  final VoidCallback? onAddSubtitleFile;
  final ValueChanged<AudioTrack> onAudioSelected;
  final ValueChanged<String> onHwdecSelected;
  final VoidCallback onOpenChaptersSidePanel;
  final VoidCallback onOpenStats;
  final Anime4kController anime4k;

  /// Ключ твору для збереження затримки звуку (порожній — не зберігати)
  final String audioDelayKey;

  const SettingsDrawer({
    super.key,
    required this.scale,
    this.screenWidth = 0,
    this.drawerAnchorPixelX = 0,
    this.drawerIsTop = false,
    this.sheet = false,
    required this.activeDrawer,
    required this.activeDrawerPrev,
    required this.player,
    required this.currentSpeed,
    required this.currentHwdec,
    required this.subtitleTracks,
    required this.audioTracks,
    required this.chapters,
    required this.scrollController,
    required this.onClose,
    required this.onBack,
    required this.onOpenSubDrawer,
    required this.onSpeedSelected,
    required this.onSubtitleSelected,
    this.onAddSubtitleFile,
    required this.onAudioSelected,
    required this.onHwdecSelected,
    required this.onOpenChaptersSidePanel,
    required this.onOpenStats,
    required this.anime4k,
    this.audioDelayKey = '',
  });

  String _getCurrentChapterLabel() {
    if (chapters.isEmpty) return "Немає";
    final pos = player.state.position;
    for (int i = chapters.length - 1; i >= 0; i--) {
      if (pos >= chapters[i].startTime) return AppFormatters.translateChapterTitle(chapters[i].title);
    }
    return AppFormatters.translateChapterTitle(chapters.first.title);
  }

  String _getCurrentAudioLabel() {
    if (audioTracks.isEmpty) return "Немає";
    final curAud = player.state.track.audio;
    for (var a in audioTracks) {
      if (a.track.id == curAud.id) return a.formattedTitle;
    }
    return audioTracks.first.formattedTitle;
  }

  String _getCurrentSubtitleLabel() {
    final curSub = player.state.track.subtitle;
    if (curSub.id == 'no' || (curSub.id.isEmpty && curSub.id != 'auto')) return "Вимкнено";
    if (subtitleTracks.isEmpty) return "Вимкнено";

    for (var s in subtitleTracks) {
      if (s.track.id == curSub.id) return s.formattedTitle;
    }

    if (curSub.id == 'auto' || curSub.id.isNotEmpty) {
      if (curSub.language != null && curSub.language!.isNotEmpty) {
        return AppFormatters.formatTrackTitle(curSub.language, curSub.title);
      }
      if (subtitleTracks.isNotEmpty) return subtitleTracks.first.formattedTitle;
    }

    return "Вимкнено";
  }

  @override
  Widget build(BuildContext context) {
    final currentSub = player.state.track.subtitle;
    final bool isSubDisabled = currentSub.id == 'no' ||
        (currentSub.id.isEmpty && currentSub.id != 'auto') ||
        subtitleTracks.isEmpty;
    final currentAud = player.state.track.audio;

    if (sheet) return _buildSheet(context, isSubDisabled, currentSub, currentAud);

    final double drawerWidth = 390.0 * scale;
    final double calculatedLeft = (drawerAnchorPixelX - (drawerWidth / 2))
        .clamp(35.0 * scale, screenWidth - drawerWidth - 35.0 * scale);

    return Stack(children: [Positioned(
      bottom: drawerIsTop ? null : 95.0 * scale,
      top: drawerIsTop ? 65.0 * scale : null,
      left: calculatedLeft,
      child: Container(
        width: drawerWidth,
        decoration: BoxDecoration(
          color: uiTheme.colors.drawerBg,
          borderRadius: uiTheme.borderRadius(14 * scale),
          border: Border.all(color: uiTheme.colors.drawerBorder, width: 1.0),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: uiTheme.isLight ? 0.12 : 0.50),
              blurRadius: 16 * scale,
              offset: Offset(0, 4 * scale),
            ),
          ],
        ),
        child: Container(
          constraints: BoxConstraints(maxHeight: 420 * scale),
          child: AppAnimatedSize(
            child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 48 * scale,
                padding: EdgeInsets.symmetric(horizontal: 18 * scale),
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (activeDrawerPrev != null)
                      InkWell(
                        onTap: onBack,
                        borderRadius: uiTheme.borderRadius(6 * scale),
                        splashColor: Colors.transparent,
                        highlightColor: uiTheme.touchHighlight,
                        hoverColor: uiTheme.isLight
                            ? Colors.black.withValues(alpha: 0.04)
                            : Colors.white.withValues(alpha: 0.05),
                        child: Row(
                          children: [
                            Icon(Symbols.chevron_left_rounded, color: uiTheme.colors.textMuted, size: 20 * scale),
                            SizedBox(width: 4 * scale),
                            Text(
                              'Назад',
                              style: TextStyle(
                                fontFamily: 'Arial',
                                color: uiTheme.colors.textMuted,
                                fontSize: 13.5 * scale,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Text(
                        _getDrawerTitle(),
                        style: TextStyle(
                          fontFamily: 'Arial',
                          color: uiTheme.colors.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 14.5 * scale,
                        ),
                      ),
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: Icon(
                        Symbols.close_rounded,
                        color: uiTheme.colors.textDarkMuted,
                        size: 19 * scale,
                        weight: 300,
                        opticalSize: 24,
                      ),
                      onPressed: onClose,
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ScrollConfiguration(
                  behavior: const AppScrollBehavior().copyWith(scrollbars: false),
                  child: KeyedSubtree(
                    child: SingleChildScrollView(
                      controller: scrollController,
                      padding: EdgeInsets.only(left: 8 * scale, right: 8 * scale, bottom: 8 * scale),
                      child: AppFadeSwitcher(
                        duration: AppAnim.fast,
                        child: Column(
                          key: ValueKey(activeDrawer),
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: _buildContent(context, scale, isSubDisabled, currentSub, currentAud),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          ),
        ),
      ),
    )]);
  }

  /// Телефон: шапка (назад / назва / закрити, кнопки ≥ 48 dp) і список, що прокручується пальцем
  Widget _buildSheet(BuildContext context, bool isSubDisabled, SubtitleTrack currentSub, AudioTrack currentAud) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 56,
          child: Row(
            children: [
              if (activeDrawerPrev != null)
                _sheetButton(Symbols.arrow_back_rounded, onBack, 'Назад')
              else
                const SizedBox(width: 20),
              Expanded(
                child: Text(
                  _getDrawerTitle(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: 'Arial', color: uiTheme.colors.textPrimary, fontWeight: FontWeight.w600, fontSize: 17),
                ),
              ),
              _sheetButton(Symbols.close_rounded, onClose, 'Закрити'),
              const SizedBox(width: 6),
            ],
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            controller: scrollController,
            padding: EdgeInsets.fromLTRB(10, 0, 10, 14 * scale),
            child: AppFadeSwitcher(
              duration: AppAnim.fast,
              child: Column(
                key: ValueKey(activeDrawer),
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _buildContent(context, scale, isSubDisabled, currentSub, currentAud),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Кругла кнопка 48×48 dp з видимою реакцією на дотик
  Widget _sheetButton(IconData icon, VoidCallback onTap, String label) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        type: MaterialType.transparency,
        child: InkResponse(
          onTap: onTap,
          radius: 26,
          highlightColor: uiTheme.hoverOverlay,
          splashColor: uiTheme.hoverOverlay,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Icon(icon, color: uiTheme.colors.textMuted, size: 24, weight: 300, opticalSize: 24),
          ),
        ),
      ),
    );
  }

  String _getDrawerTitle() {
    switch (activeDrawer) {
      case 'speed': return 'Швидкість відтворення';
      case 'advanced': return 'Більше';
      case 'hwdec': return 'Апаратний декодер';
      case 'chapters': return 'Розділи та глави';
      case 'anime4k': return 'Anime4K';
      case 'subs': return 'Субтитри (${subtitleTracks.length})';
      case 'audio': return 'Аудіодоріжка (${audioTracks.length})';
      default: return 'Налаштування';
    }
  }

  List<Widget> _buildContent(
    BuildContext context,
    double scale,
    bool isSubDisabled,
    SubtitleTrack currentSub,
    AudioTrack currentAud,
  ) {
    if (activeDrawer == 'speed') {
      return AppConstants.speeds.map((s) {
        final isCur = (currentSpeed - s).abs() < 0.05;
        return AppSelectableTile(
          scale: scale,
          title: '${s}x${s == 1.0 ? ' (Звичайна)' : ''}',
          icon: AppFormatters.getSpeedIcon(s),
          isSelected: isCur,
          onTap: () => onSpeedSelected(s),
        );
      }).toList();
    }

    if (activeDrawer == 'advanced') {
      return [
        _buildItem(
          scale: scale,
          icon: Symbols.developer_board_rounded,
          title: 'Апаратний декодер (GPU)',
          value: '${AppConstants.hwdecShortNames[currentHwdec] ?? "NVDEC"}  ›',
          onTap: () => onOpenSubDrawer('hwdec'),
        ),
        _buildItem(
          scale: scale,
          icon: Symbols.query_stats_rounded,
          title: 'Статистика відтворення (Stats)',
          onTap: onOpenStats,
        ),
      ];
    }

    if (activeDrawer == 'hwdec') {
      return AppConstants.hwdecOptions.entries.map((entry) {
        final isCur = currentHwdec == entry.key;
        return AppSelectableTile(
          scale: scale,
          title: entry.value,
          icon: Symbols.developer_board_rounded,
          isSelected: isCur,
          onTap: () => onHwdecSelected(entry.key),
        );
      }).toList();
    }

    if (activeDrawer == 'anime4k') return _buildAnime4kPage(scale);

    if (activeDrawer == 'chapters') {
      final curPos = player.state.position;
      return chapters.asMap().entries.map((entry) {
        final idx = entry.key;
        final ch = entry.value;
        final nextStart = (idx + 1 < chapters.length) ? chapters[idx + 1].startTime : player.state.duration;
        final isCur = curPos >= ch.startTime && curPos < nextStart;

        return AppSelectableTile(
          scale: scale,
          title: '${AppFormatters.translateChapterTitle(ch.title)} (${AppFormatters.formatTime(ch.startTime)})',
          icon: Symbols.bookmark_rounded,
          isSelected: isCur,
          onTap: () {
            player.seek(ch.startTime);
            onClose();
          },
        );
      }).toList();
    }

    if (activeDrawer == 'subs') {
      return [
        AppSelectableTile(
          scale: scale,
          title: 'Вимкнути субтитри',
          icon: Symbols.close_rounded,
          isSelected: isSubDisabled,
          onTap: () => onSubtitleSelected(SubtitleTrack.no()),
        ),
        ...subtitleTracks.map((cached) {
          final bool isSelected = !isSubDisabled &&
              (currentSub.id == cached.track.id ||
                  (currentSub.id == 'auto' && subtitleTracks.first.track.id == cached.track.id) ||
                  (currentSub.id.isEmpty && subtitleTracks.first.track.id == cached.track.id));

          final bool isSdh = cached.formattedTitle.toLowerCase().contains("sdh") ||
              (cached.track.title?.toLowerCase().contains("sdh") ?? false);

          return AppSelectableTile(
            scale: scale,
            title: cached.formattedTitle,
            icon: isSdh ? Symbols.hearing_rounded : Symbols.subtitles_rounded,
            isSelected: isSelected,
            onTap: () => onSubtitleSelected(cached.track),
          );
        }),
        if (onAddSubtitleFile != null)
          AppSelectableTile(
            scale: scale,
            title: 'Додати файл субтитрів…',
            icon: Symbols.upload_file_rounded,
            isSelected: false,
            onTap: onAddSubtitleFile!,
          ),
      ];
    }

    if (activeDrawer == 'audio') {
      final tiles = audioTracks.map((cached) {
        final bool isSelected = (currentAud.id == cached.track.id) ||
            (currentAud.id == 'auto' && audioTracks.first.track.id == cached.track.id) ||
            (currentAud.id.isEmpty && audioTracks.first.track.id == cached.track.id) ||
            (audioTracks.length == 1);

        return AppSelectableTile(
          scale: scale,
          title: cached.formattedTitle,
          icon: Symbols.music_note_rounded,
          isSelected: isSelected,
          onTap: () => onAudioSelected(cached.track),
        );
      }).toList();
      return [_AudioPane(scale: scale, player: player, storeKey: audioDelayKey, tracks: tiles)];
    }

    return [
      _buildItem(
        scale: scale,
        icon: Symbols.speed_rounded,
        title: 'Швидкість відтворення',
        value: '${AppFormatters.formatSpeed(currentSpeed)}  ›',
        onTap: () => onOpenSubDrawer('speed'),
      ),
      _buildItem(
        scale: scale,
        icon: Symbols.subtitles_rounded,
        title: 'Субтитри',
        value: '${_getCurrentSubtitleLabel()}  ›',
        onTap: () => onOpenSubDrawer('subs'),
      ),
      _buildItem(
        scale: scale,
        icon: Symbols.music_note_rounded,
        title: 'Аудіодоріжка',
        isFilledIcon: true,
        value: '${_getCurrentAudioLabel()}  ›',
        onTap: () => onOpenSubDrawer('audio'),
      ),
      _buildItem(
        scale: scale,
        icon: Symbols.auto_stories_rounded,
        title: 'Розділи / Глави',
        value: chapters.isNotEmpty ? '${_getCurrentChapterLabel()}  ›' : 'Немає',
        onTap: chapters.isNotEmpty ? () => onOpenSubDrawer('chapters') : () {},
      ),
      _buildItem(
        scale: scale,
        icon: Symbols.auto_awesome_rounded,
        title: 'Anime4K',
        isActive: anime4k.active,
        value: '${anime4k.summary}  ›',
        onTap: () => onOpenSubDrawer('anime4k'),
      ),
      _buildItem(
        scale: scale,
        icon: Symbols.settings_rounded,
        title: 'Більше',
        value: '›',
        onTap: () => onOpenSubDrawer('advanced'),
      ),
    ];
  }

  /// Сторінка Anime4K: якість, вимкнення та шість режимів із підказками клавіш.
  /// Меню не закривається після вибору — режими зручно порівнювати «наживо».
  List<Widget> _buildAnime4kPage(double scale) {
    final a = anime4k;
    return [
      Padding(
        padding: EdgeInsets.fromLTRB(2 * scale, 2 * scale, 2 * scale, 8 * scale),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: AppSegmentedBar<Anime4kQuality>(
                    scale: scale,
                    options: [
                      for (final q in Anime4kQuality.values) AppSegmentOption(value: q, label: q.label),
                    ],
                    selectedValue: a.quality,
                    onSelected: a.setQuality,
                  ),
                ),
                // Підказки клавіш (Ctrl + цифра) мають сенс лише з клавіатурою
                if (!AppPlatform.isMobile) ...[
                  SizedBox(width: 10 * scale),
                  AppKeyCombo(scale: scale, keys: const ['Ctrl', '9']),
                ],
              ],
            ),
            SizedBox(height: 6 * scale),
            Text(
              AppPlatform.isMobile ? a.quality.deviceHint : a.quality.gpuHint,
              style: TextStyle(fontFamily: 'Arial', color: uiTheme.colors.textDarkMuted, fontSize: 11.5 * scale),
            ),
          ],
        ),
      ),
      AppSelectableTile(
        scale: scale,
        title: 'Вимкнено',
        subtitle: 'Без обробки шейдерами',
        icon: Symbols.close_rounded,
        isSelected: !a.enabled,
        trailing: AppPlatform.isMobile ? null : AppKeyCombo(scale: scale, keys: const ['Ctrl', '0']),
        onTap: a.disable,
      ),
      for (final m in Anime4kMode.values)
        AppSelectableTile(
          scale: scale,
          title: m.title,
          subtitle: m.tagline,
          icon: Symbols.auto_awesome_rounded,
          isSelected: a.enabled && a.mode == m,
          trailing: AppPlatform.isMobile ? null : AppKeyCombo(scale: scale, keys: ['Ctrl', '${m.digit}']),
          onTap: () => a.setMode(m),
        ),
      if (a.enabled && a.skipped)
        _buildAnime4kNote(scale, 'Пропущено: відео ${a.videoHeight}p не менше за поріг ${a.skipHeight}p (змінюється в налаштуваннях)'),
      if (a.error != null) _buildAnime4kNote(scale, a.error!, isError: true),
    ];
  }

  Widget _buildAnime4kNote(double scale, String text, {bool isError = false}) {
    return Padding(
      padding: EdgeInsets.fromLTRB(4 * scale, 6 * scale, 4 * scale, 2 * scale),
      child: Text(
        text,
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontFamily: 'Arial',
          color: isError ? const Color(0xFFE5484D) : uiTheme.colors.textDarkMuted,
          fontSize: 11.5 * scale,
          height: 1.35,
        ),
      ),
    );
  }

  Widget _buildItem({
    required double scale,
    required IconData icon,
    required String title,
    String? value,
    bool isActive = false,
    bool isFilledIcon = false,
    required VoidCallback onTap,
  }) {
    final radiusObj = uiTheme.borderRadius(10 * scale);
    final bool hasChevron = value != null && value.trim().endsWith('›');
    String? shown = value?.replaceAll(RegExp(r'\s*›\s*$'), '').trim();
    if (shown != null && shown.isEmpty) shown = null;
    final Color fg = isActive ? uiTheme.accentColor : uiTheme.colors.textPrimary;

    return Container(
      height: 50 * scale,
      margin: EdgeInsets.symmetric(vertical: 2 * scale),
      child: Material(
        color: Colors.transparent,
        borderRadius: radiusObj,
        child: InkWell(
          borderRadius: radiusObj,
          splashColor: Colors.transparent,
          highlightColor: uiTheme.touchHighlight,
          hoverColor: uiTheme.hoverOverlay,
          onTap: onTap,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 9 * scale),
            decoration: BoxDecoration(
              color: isActive ? uiTheme.accentWash : Colors.transparent,
              borderRadius: radiusObj,
              border: Border.all(color: isActive ? uiTheme.accentBorder : Colors.transparent, width: 1.0),
            ),
            child: Row(
              children: [
                Container(
                  width: 32 * scale,
                  height: 32 * scale,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: uiTheme.bgElevated,
                    borderRadius: uiTheme.borderRadius(8 * scale),
                    border: Border.all(color: uiTheme.colors.borderSubtle),
                  ),
                  child: Icon(icon, color: fg, size: 18 * scale, fill: isFilledIcon ? 1 : 0, weight: 300, opticalSize: 24),
                ),
                SizedBox(width: 12 * scale),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontFamily: 'Arial',
                      color: fg,
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                      fontSize: 14.0 * scale,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (shown != null) ...[
                  SizedBox(width: 8 * scale),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: 150 * scale),
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 9 * scale, vertical: 4 * scale),
                      decoration: BoxDecoration(
                        color: uiTheme.bgElevated,
                        borderRadius: uiTheme.borderRadius(7 * scale),
                        border: Border.all(color: uiTheme.colors.borderSubtle),
                      ),
                      child: Text(
                        shown,
                        style: TextStyle(
                          fontFamily: 'Arial',
                          color: uiTheme.colors.textMuted,
                          fontSize: 12.0 * scale,
                          fontWeight: FontWeight.w400,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
                if (hasChevron) ...[
                  SizedBox(width: 4 * scale),
                  Icon(Symbols.chevron_right_rounded, color: uiTheme.colors.textDarkMuted, size: 18 * scale, weight: 300, opticalSize: 24),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}


/// Затримка звуку (`audio-delay` в mpv): крок 50 мс, від −10 до +10 с; кнопка скидання повертає нуль.
/// Зберігається для твору (див. `audioDelayKey`) і застосовується до його наступних серій.
class _AudioDelayRow extends StatefulWidget {
  final double scale;
  final Player player;
  final String storeKey;
  const _AudioDelayRow({required this.scale, required this.player, required this.storeKey});

  @override
  State<_AudioDelayRow> createState() => _AudioDelayRowState();
}

class _AudioDelayRowState extends State<_AudioDelayRow> {
  static const int _stepMs = 50;
  static const int _limitMs = 10000;
  int _ms = 0;

  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() async {
    try {
      final dynamic platform = widget.player.platform;
      final raw = await platform?.getProperty('audio-delay');
      final v = ((double.tryParse('$raw') ?? 0) * 1000).round();
      if (mounted) setState(() => _ms = v);
    } catch (_) {}
  }

  Future<void> _set(int ms) async {
    ms = ms.clamp(-_limitMs, _limitMs);
    setState(() => _ms = ms);
    try {
      final dynamic platform = widget.player.platform;
      await platform?.setProperty('audio-delay', (ms / 1000).toStringAsFixed(3));
    } catch (_) {}
    StorageService.saveAudioDelay(widget.storeKey, ms);
  }

  String get _label => _ms > 0 ? '+$_ms мс' : (_ms < 0 ? '−${-_ms} мс' : '0 мс');

  @override
  Widget build(BuildContext context) {
    final double sc = widget.scale;
    return Padding(
      padding: EdgeInsets.fromLTRB(14 * sc, 10 * sc, 8 * sc, 4 * sc),
      child: Row(
        children: [
          Icon(Symbols.sync_rounded, color: uiTheme.colors.textMuted, size: 20 * sc),
          SizedBox(width: 12 * sc),
          Expanded(
            child: Text(
              'Затримка звуку',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: 'Arial', color: uiTheme.colors.textPrimary, fontSize: 14 * sc),
            ),
          ),
          AppRowIconButton(scale: sc, icon: Symbols.remove_rounded, size: 20, onTap: () => _set(_ms - _stepMs)),
          SizedBox(
            width: 70 * sc,
            child: Text(
                _label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Arial',
                  fontSize: 13 * sc,
                  fontWeight: FontWeight.w600,
                  color: _ms == 0 ? uiTheme.colors.textMuted : uiTheme.colors.textPrimary,
                ),
              ),
          ),
          AppRowIconButton(scale: sc, icon: Symbols.add_rounded, size: 20, onTap: () => _set(_ms + _stepMs)),
          AppRowIconButton(scale: sc, icon: Symbols.restart_alt_rounded, size: 20, onTap: _ms == 0 ? null : () => _set(0)),
        ],
      ),
    );
  }
}


/// Меню «Аудіодоріжка»: вкладки «Доріжка» і «Затримка», як «Серії / Озвучка / Плеєр» у списку серій
class _AudioPane extends StatefulWidget {
  final double scale;
  final Player player;
  final String storeKey;
  final List<Widget> tracks;
  const _AudioPane({required this.scale, required this.player, required this.storeKey, required this.tracks});

  @override
  State<_AudioPane> createState() => _AudioPaneState();
}

class _AudioPaneState extends State<_AudioPane> {
  bool _delayTab = false;

  @override
  Widget build(BuildContext context) {
    final sc = widget.scale;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: 8 * sc),
          child: AppSegmentedBar<bool>(
            scale: sc,
            selectedValue: _delayTab,
            onSelected: (v) => setState(() => _delayTab = v),
            options: const [
              AppSegmentOption(value: false, label: 'Доріжка'),
              AppSegmentOption(value: true, label: 'Затримка'),
            ],
          ),
        ),
        if (!_delayTab) ...widget.tracks else ...[
          _AudioDelayRow(scale: sc, player: widget.player, storeKey: widget.storeKey),
          Padding(
            padding: EdgeInsets.fromLTRB(14 * sc, 6 * sc, 14 * sc, 4 * sc),
            child: Text(
              'Зсуває звук відносно картинки: мінус — раніше, плюс — пізніше. Зберігається для цього твору.',
              style: TextStyle(fontFamily: 'Arial', color: uiTheme.colors.textMuted, fontSize: 12 * sc, height: 1.35),
            ),
          ),
        ],
      ],
    );
  }
}
