import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:media_kit/media_kit.dart';
import '../models/media_models.dart';
import '../services/ui_theme_service.dart';
import '../services/remote_driver.dart';
import '../services/seek_preview_service.dart';
import '../services/thumbnail_service.dart';
import '../utils/formatters.dart';
import 'app_animation_kit.dart';
import 'app_media_thumbnail.dart';
import 'remote_panel.dart';
import 'app_ui_kit.dart';

enum SidePanelType { chapters, episodes, info }

class SidePanel extends StatefulWidget {
  final double scale;
  final SidePanelType type;
  final Player player;
  final List<Media> playlistItems;
  final int currentPlaylistIndex;
  final List<VideoChapter> chapters;
  final VoidCallback onClose;
  final VoidCallback onAddMedia;
  final ValueChanged<int> onEpisodeSelected;
  final ValueChanged<Duration> onChapterSelected;
  final void Function(int from, int to) onQueueReorder;
  final ValueChanged<int> onQueueRemove;
  final VoidCallback onQueueClear;

  /// Серії із сайту: замість черги файлів показуються серії, озвучки й плеєри
  final RemoteDriver? remote;

  /// Телефон: без власної поверхні й ширини — поверхню та положення дає [MobileSheetFrame],
  /// кнопки збільшені під дотик, черга міняється порядок лише перетягуванням
  final bool sheet;

  const SidePanel({
    super.key,
    this.sheet = false,
    required this.scale,
    required this.type,
    required this.player,
    required this.playlistItems,
    required this.currentPlaylistIndex,
    required this.chapters,
    required this.onClose,
    required this.onAddMedia,
    required this.onEpisodeSelected,
    required this.onChapterSelected,
    required this.onQueueReorder,
    required this.onQueueRemove,
    required this.onQueueClear,
    this.remote,
  });

  @override
  State<SidePanel> createState() => _SidePanelState();
}

class _SidePanelState extends State<SidePanel> {
  final ScrollController _scrollController = AppSmoothScrollController();
  int _loopChapter = -1;
  int _lastScrolledTo = -2;
  final GlobalKey _currentRowKey = GlobalKey();

  Future<void> _setProp(String k, String v) async {
    try {
      final dynamic plat = widget.player.platform;
      await plat?.setProperty(k, v);
    } catch (_) {}
  }

  void _toggleLoop(int index) {
    if (_loopChapter == index) {
      setState(() => _loopChapter = -1);
      _setProp('ab-loop-a', 'no');
      _setProp('ab-loop-b', 'no');
      return;
    }
    final ch = widget.chapters[index];
    final end = (index + 1 < widget.chapters.length) ? widget.chapters[index + 1].startTime : widget.player.state.duration;
    setState(() => _loopChapter = index);
    _setProp('ab-loop-a', (ch.startTime.inMilliseconds / 1000).toStringAsFixed(3));
    _setProp('ab-loop-b', (end.inMilliseconds / 1000).toStringAsFixed(3));
  }

  void _scrollToCurrent(int index, double scale) {
    if (index < 0 || index == _lastScrolledTo) return;
    _lastScrolledTo = index;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _currentRowKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx, duration: AppAnim.medium, curve: AppAnim.easeOut, alignment: 0.3);
      } else if (_scrollController.hasClients) {
        _scrollController.jumpTo((index * 78 * scale).clamp(0.0, _scrollController.position.maxScrollExtent));
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final c = _currentRowKey.currentContext;
          if (mounted && c != null) Scrollable.ensureVisible(c, alignment: 0.3);
        });
      }
    });
  }

  @override
  void initState() {
    super.initState();
    // Не запускаємо фонові плеєри (прев'ю), поки панель висувається — інакше це б'є по плавності
    ThumbnailService.holdFor(AppAnim.slow + const Duration(milliseconds: 200));
    _prepareChapterPreviews();
  }

  @override
  void didUpdateWidget(SidePanel old) {
    super.didUpdateWidget(old);
    if (old.chapters != widget.chapters || old.currentPlaylistIndex != widget.currentPlaylistIndex || old.type != widget.type) {
      _prepareChapterPreviews();
    }
  }

  void _prepareChapterPreviews() {
    if (widget.type != SidePanelType.chapters || widget.chapters.isEmpty) return;
    final items = widget.playlistItems;
    final i = widget.currentPlaylistIndex;
    final uri = (i >= 0 && i < items.length) ? items[i].uri : null;
    final dur = widget.player.state.duration;
    if (uri == null || dur <= Duration.zero) return;
    SeekPreviewService.prepare(uri, dur);
    final times = widget.chapters.map((c) => c.startTime).toList();
    Future.delayed(AppAnim.slow + const Duration(milliseconds: 200), () {
      if (mounted) SeekPreviewService.requestMany(times);
    });
  }

  Widget _chapterThumb(double scale, int index, Duration start, bool isCurrent) {
    return Container(
      width: 96 * scale,
      height: 54 * scale,
      decoration: BoxDecoration(
        color: uiTheme.bgElevated,
        borderRadius: uiTheme.borderRadius(6 * scale),
        border: Border.all(color: isCurrent ? uiTheme.accentBorder : uiTheme.colors.borderSubtle),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ValueListenableBuilder<int>(
            valueListenable: SeekPreviewService.revision,
            builder: (context, _, __) {
              final bytes = SeekPreviewService.hasExact(start) ? SeekPreviewService.frame(start) : null;
              return AppFadeSwitcher(
                expand: true,
                child: bytes != null
                    ? Image.memory(bytes, key: ValueKey('f$index'), fit: BoxFit.cover, gaplessPlayback: true)
                    : Center(
                        key: ValueKey('p$index'),
                        child: Icon(
                          isCurrent ? Symbols.equalizer_rounded : Symbols.auto_stories_rounded,
                          color: isCurrent ? uiTheme.accentColor : uiTheme.textDarkMuted,
                          size: 20 * scale,
                          weight: 300,
                          opticalSize: 24,
                        ),
                      ),
              );
            },
          ),
          Positioned(
            top: 4 * scale,
            left: 4 * scale,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 5 * scale, vertical: 1.5 * scale),
              decoration: BoxDecoration(
                color: isCurrent ? uiTheme.accentColor : Colors.black.withValues(alpha: 0.72),
                borderRadius: uiTheme.borderRadius(4 * scale),
              ),
              child: Text(
                '${index + 1}',
                style: TextStyle(
                  fontFamily: 'Arial',
                  color: isCurrent ? uiTheme.onAccent : Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 10 * scale,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    if (_loopChapter >= 0) {
      _setProp('ab-loop-a', 'no');
      _setProp('ab-loop-b', 'no');
    }
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.scale;

    if (widget.sheet) {
      return Column(
        children: [
          AppPanelHeader(scale: scale, title: _getTitle(), onClose: widget.onClose),
          Expanded(child: _buildContent(scale)),
        ],
      );
    }

    return AppPanelSurface(
      scale: scale,
      width: 380 * scale,
      radius: 14,
      shadowOffset: const Offset(-4, 0),
      margin: EdgeInsets.only(top: 8 * scale, bottom: 8 * scale, right: 8 * scale),
      child: Column(
        children: [
          AppPanelHeader(scale: scale, title: _getTitle(), onClose: widget.onClose),
          Expanded(child: _buildContent(scale)),
        ],
      ),
    );
  }

  String _getTitle() {
    switch (widget.type) {
      case SidePanelType.chapters: return 'Розділи та глави (${widget.chapters.length})';
      case SidePanelType.episodes:
        final rd = widget.remote;
        if (rd != null && rd.active) return 'Серії (${rd.session!.entries.length})';
        return 'Черга відтворення (${widget.playlistItems.length})';
      case SidePanelType.info: return 'Інформація про медіа';
    }
  }

  Widget _buildContent(double scale) {
    switch (widget.type) {
      case SidePanelType.chapters: return _buildChaptersList(scale);
      case SidePanelType.episodes:
        final rd = widget.remote;
        if (rd != null && rd.active) {
          return RemotePanelBody(scale: scale, driver: rd, sheet: widget.sheet, onEpisodeSelected: widget.onEpisodeSelected);
        }
        return _buildEpisodesList(scale);
      case SidePanelType.info: return _buildInfoTab(scale);
    }
  }

  /// Тонкий скролбар у стилі меню налаштувань
  Widget _scrollArea(double scale, Widget child) {
    return ScrollConfiguration(
      behavior: const AppScrollBehavior().copyWith(scrollbars: false),
      child: KeyedSubtree(
        child: child,
      ),
    );
  }

  Widget _buildChaptersList(double scale) {
    if (widget.chapters.isEmpty) {
      return AppEmptyState(
        scale: scale,
        icon: Symbols.auto_stories_rounded,
        text: 'У цьому відео немає розмічених розділів',
      );
    }

    // Позиція відео оновлюється десятки разів на секунду, тому слухаємо не її, а лише
    // індекс поточного розділу (distinct): список перебудовується тільки при зміні розділу.
    return StreamBuilder<int>(
      stream: widget.player.stream.position.map(_currentChapterIndex).distinct(),
      initialData: _currentChapterIndex(widget.player.state.position),
      builder: (context, snapshot) {
        final currentIndex = snapshot.data ?? -1;
        _scrollToCurrent(currentIndex, scale);
        return _scrollArea(
          scale,
          ListView.builder(
            controller: _scrollController,
            padding: EdgeInsets.only(left: 8 * scale, right: 8 * scale, bottom: 8 * scale),
            itemCount: widget.chapters.length,
            itemBuilder: (context, index) {
              final ch = widget.chapters[index];
              final bool isCurrent = index == currentIndex;

              final Duration chEnd = (index + 1 < widget.chapters.length) ? widget.chapters[index + 1].startTime : widget.player.state.duration;
              final Duration len = chEnd - ch.startTime;
              return KeyedSubtree(
                key: isCurrent ? _currentRowKey : ValueKey('ch$index'),
                child: AppSelectableSurface(
                scale: scale,
                isSelected: isCurrent,
                padding: EdgeInsets.all(8 * scale),
                onTap: () => widget.onChapterSelected(ch.startTime),
                child: Row(
                  children: [
                    _chapterThumb(scale, index, ch.startTime, isCurrent),
                    SizedBox(width: 12 * scale),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            AppFormatters.translateChapterTitle(ch.title),
                            style: TextStyle(
                              fontFamily: 'Arial',
                              color: isCurrent ? uiTheme.accentColor : uiTheme.textPrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: 13.5 * scale,
                              height: 1.25,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (len > Duration.zero) ...[
                            SizedBox(height: 4 * scale),
                            Text(
                              isCurrent ? 'Зараз відтворюється' : 'Тривалість ${AppFormatters.formatTime(len)}',
                              style: TextStyle(
                                fontFamily: 'Arial',
                                color: isCurrent ? uiTheme.accentColor.withValues(alpha: 0.85) : uiTheme.textDarkMuted,
                                fontSize: 11 * scale,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    SizedBox(width: 8 * scale),
                    _iconTile(
                      scale,
                      Symbols.repeat_one_rounded,
                      active: _loopChapter == index,
                      tooltip: _loopChapter == index ? 'Вимкнути повтор розділу' : 'Повторювати розділ',
                      onTap: () => _toggleLoop(index),
                      size: widget.sheet ? 40 : 30,
                    ),
                    SizedBox(width: 6 * scale),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 8 * scale, vertical: 4 * scale),
                      decoration: BoxDecoration(
                        color: isCurrent ? uiTheme.accentColor : uiTheme.bgElevated,
                        borderRadius: uiTheme.borderRadius(6 * scale),
                      ),
                      child: Text(
                        AppFormatters.formatTime(ch.startTime),
                        style: TextStyle(
                          fontFamily: 'Arial',
                          color: isCurrent ? uiTheme.onAccent : uiTheme.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 11.5 * scale,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ),
              ));
            },
          ),
        );
      },
    );
  }

  int _currentChapterIndex(Duration pos) {
    final chapters = widget.chapters;
    for (int i = 0; i < chapters.length; i++) {
      final nextStart = (i + 1 < chapters.length) ? chapters[i + 1].startTime : widget.player.state.duration;
      if (pos >= chapters[i].startTime && pos < nextStart) return i;
    }
    return -1;
  }

  /// Невелика квадратна кнопка-плитка для панелей
  Widget _iconTile(double scale, IconData icon, {required VoidCallback onTap, bool active = false, String? tooltip, double size = 30}) {
    final tile = Material(
      color: active ? uiTheme.accentColor.withValues(alpha: 0.18) : uiTheme.bgElevated,
      borderRadius: uiTheme.borderRadius(8 * scale),
      child: InkWell(
        borderRadius: uiTheme.borderRadius(8 * scale),
        onTap: onTap,
        child: Container(
          width: size * scale,
          height: size * scale,
          decoration: BoxDecoration(
            borderRadius: uiTheme.borderRadius(8 * scale),
            border: Border.all(color: active ? uiTheme.accentBorder : uiTheme.colors.borderSubtle),
          ),
          child: Icon(icon, size: 17 * scale, color: active ? uiTheme.accentColor : uiTheme.textDarkMuted, weight: 300, opticalSize: 24),
        ),
      ),
    );
    return tooltip == null ? tile : Tooltip(message: tooltip, child: tile);
  }

  IconData _modeIcon(PlaylistMode m) {
    switch (m) {
      case PlaylistMode.single: return Symbols.repeat_one_rounded;
      case PlaylistMode.loop: return Symbols.repeat_rounded;
      case PlaylistMode.none: return Symbols.repeat_rounded;
    }
  }

  String _modeTip(PlaylistMode m) {
    switch (m) {
      case PlaylistMode.single: return 'Повтор: поточне відео';
      case PlaylistMode.loop: return 'Повтор: уся черга';
      case PlaylistMode.none: return 'Без повтору';
    }
  }

  void _cycleMode() {
    final m = widget.player.state.playlistMode;
    widget.player.setPlaylistMode(
      m == PlaylistMode.none ? PlaylistMode.loop : (m == PlaylistMode.loop ? PlaylistMode.single : PlaylistMode.none),
    );
  }

  Widget _buildEpisodesList(double scale) {
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(8 * scale, 0, 8 * scale, 8 * scale),
          child: Row(
            children: [
              Expanded(
                child: AppSecondaryButton(
                  scale: scale,
                  label: 'Додати до черги',
                  icon: Symbols.add_circle_rounded,
                  onTap: widget.onAddMedia,
                ),
              ),
              SizedBox(width: 8 * scale),
              StreamBuilder<PlaylistMode>(
                stream: widget.player.stream.playlistMode,
                initialData: widget.player.state.playlistMode,
                builder: (context, snap) {
                  final m = snap.data ?? PlaylistMode.none;
                  return _iconTile(scale, _modeIcon(m), active: m != PlaylistMode.none, tooltip: _modeTip(m), onTap: _cycleMode, size: widget.sheet ? 42 : 36);
                },
              ),
              SizedBox(width: 6 * scale),
              _iconTile(
                scale,
                Symbols.delete_sweep_rounded,
                tooltip: 'Очистити чергу (крім поточного)',
                onTap: widget.playlistItems.length > 1 ? widget.onQueueClear : () {},
                size: widget.sheet ? 42 : 36,
              ),
            ],
          ),
        ),
        Expanded(
          child: widget.playlistItems.isEmpty
              ? AppEmptyState(scale: scale, icon: Symbols.video_library_rounded, text: 'Черга порожня')
              : _scrollArea(
                  scale,
                  ReorderableListView.builder(
                    scrollController: _scrollController,
                    buildDefaultDragHandles: false,
                    padding: EdgeInsets.only(left: 8 * scale, right: 8 * scale, bottom: 8 * scale),
                    itemCount: widget.playlistItems.length,
                    proxyDecorator: (child, i, anim) => Material(color: Colors.transparent, child: child),
                    onReorderItem: widget.onQueueReorder,
                    itemBuilder: (context, index) {
                      final item = widget.playlistItems[index];
                      final bool isCurrent = index == widget.currentPlaylistIndex;
                      final title = item.extras?['title'] ?? AppFormatters.cleanMediaTitle(item.uri);

                      final bool isFirst = index == 0;
                      final bool isLast = index == widget.playlistItems.length - 1;
                      final bool many = widget.playlistItems.length > 1;
                      final radius = uiTheme.borderRadius(10 * scale);

                      // Рядок у тому ж вигляді, що й список пріоритету мов у налаштуваннях
                      return Container(
                        key: ObjectKey(item),
                        margin: EdgeInsets.only(bottom: 6 * scale),
                        decoration: BoxDecoration(
                          color: isCurrent ? uiTheme.accentWash : uiTheme.bgSurface,
                          borderRadius: radius,
                          border: Border.all(color: isCurrent ? uiTheme.accentBorder : uiTheme.borderSubtle, width: 1.0),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          borderRadius: radius,
                          child: InkWell(
                            borderRadius: radius,
                            splashColor: Colors.transparent,
                            highlightColor: uiTheme.touchHighlight,
                            hoverColor: uiTheme.hoverOverlay,
                            onTap: () => widget.onEpisodeSelected(index),
                            child: Padding(
                              padding: EdgeInsets.symmetric(horizontal: 8 * scale, vertical: 7 * scale),
                              child: Row(
                                children: [
                                  AppDragHandle(scale: scale, index: index),
                                  SizedBox(width: 2 * scale),
                                  _buildThumb(scale, index, isCurrent, item.uri),
                                  SizedBox(width: 10 * scale),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          title,
                                          style: TextStyle(
                                            fontFamily: 'Arial',
                                            color: isCurrent ? uiTheme.accentColor : uiTheme.textPrimary,
                                            fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w500,
                                            fontSize: 13 * scale,
                                            height: 1.25,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        if (isCurrent) ...[
                                          SizedBox(height: 4 * scale),
                                          Text(
                                            'Зараз відтворюється',
                                            style: TextStyle(
                                              fontFamily: 'Arial',
                                              color: uiTheme.accentColor.withValues(alpha: 0.85),
                                              fontSize: 11 * scale,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  if (many && !widget.sheet) ...[
                                    SizedBox(width: 4 * scale),
                                    Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        AppRowIconButton(
                                          scale: scale,
                                          icon: Symbols.keyboard_arrow_up_rounded,
                                          onTap: isFirst ? null : () => widget.onQueueReorder(index, index - 1),
                                        ),
                                        SizedBox(height: 4 * scale),
                                        AppRowIconButton(
                                          scale: scale,
                                          icon: Symbols.keyboard_arrow_down_rounded,
                                          onTap: isLast ? null : () => widget.onQueueReorder(index, index + 1),
                                        ),
                                      ],
                                    ),
                                    SizedBox(width: 8 * scale),
                                  ],
                                  if (!isCurrent && many)
                                    AppRowIconButton(
                                      scale: scale,
                                      icon: Symbols.close_rounded,
                                      muted: true,
                                      size: 17,
                                      onTap: () => widget.onQueueRemove(index),
                                    )
                                  else
                                    SizedBox(width: widget.sheet ? AppRowIconButton.touchSize : 17 * scale),
                                  SizedBox(width: 2 * scale),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildThumb(double scale, int index, bool isCurrent, String uri) {
    return AppMediaThumbnail(
      uri: uri,
      scale: scale,
      width: 96 * scale,
      height: 54 * scale,
      radius: 6,
      borderColor: isCurrent ? uiTheme.accentBorder : uiTheme.colors.borderSubtle,
      fallback: Icon(
        isCurrent ? Symbols.equalizer_rounded : Symbols.movie_rounded,
        color: isCurrent ? uiTheme.accentColor : uiTheme.textDarkMuted,
        size: 22 * scale,
        weight: 300,
        opticalSize: 24,
      ),
      overlay: Stack(
        children: [
          Positioned(
            top: 4 * scale,
            left: 4 * scale,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 5 * scale, vertical: 1.5 * scale),
              decoration: BoxDecoration(
                color: isCurrent ? uiTheme.accentColor : Colors.black.withValues(alpha: 0.72),
                borderRadius: uiTheme.borderRadius(4 * scale),
              ),
              child: Text(
                '#${index + 1}',
                style: TextStyle(
                  fontFamily: 'Arial',
                  color: isCurrent ? uiTheme.onAccent : Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 10 * scale,
                ),
              ),
            ),
          ),
          if (isCurrent)
            Positioned(
              bottom: 4 * scale,
              right: 4 * scale,
              child: StreamBuilder<Duration>(
                stream: widget.player.stream.duration,
                initialData: widget.player.state.duration,
                builder: (context, snapshot) {
                  final dur = snapshot.data ?? Duration.zero;
                  if (dur == Duration.zero) return const SizedBox.shrink();
                  return Container(
                    padding: EdgeInsets.symmetric(horizontal: 4 * scale, vertical: 1 * scale),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.72),
                      borderRadius: uiTheme.borderRadius(3 * scale),
                    ),
                    child: Text(
                      AppFormatters.formatTime(dur),
                      style: TextStyle(
                        fontFamily: 'Arial',
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                        fontSize: 9.5 * scale,
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInfoTab(double scale) {
    final vTrack = widget.player.state.tracks.video.firstOrNull;
    final aTrack = widget.player.state.track.audio;
    final sTrack = widget.player.state.track.subtitle;

    return _scrollArea(
      scale,
      SingleChildScrollView(
        controller: _scrollController,
        padding: EdgeInsets.only(left: 8 * scale, right: 8 * scale, bottom: 8 * scale),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoSection(
              scale,
              title: 'Файл',
              items: [
                ..._fileRows(scale),
                _buildInfoRow(scale, 'Тривалість', AppFormatters.formatTime(widget.player.state.duration)),
              ],
            ),
            _buildInfoSection(
              scale,
              title: 'Відеопотік',
              items: [
                _buildInfoRow(scale, 'Кодек', '${vTrack?.codec ?? "HEVC"} ${vTrack?.w ?? 3840}x${vTrack?.h ?? 1606}'),
                _buildInfoRow(scale, 'Декодер', 'Direct3D 11 / NVDEC'),
              ],
            ),
            _buildInfoSection(
              scale,
              title: 'Аудіо та субтитри',
              items: [
                _buildInfoRow(scale, 'Аудіо', AppFormatters.formatTrackTitle(aTrack.language, aTrack.title, channels: aTrack.channels?.toString())),
                _buildInfoRow(scale, 'Субтитри', sTrack.id == 'no' ? 'Вимкнено' : AppFormatters.formatTrackTitle(sTrack.language, sTrack.title)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Рядки про джерело відео: шлях до файлу або серія / озвучка / плеєр (пряме посилання на потік не показуємо)
  List<Widget> _fileRows(double scale) {
    final rd = widget.remote;
    if (rd != null && rd.active) {
      return [
        _buildInfoRow(scale, 'Серія', rd.session!.displayTitle(rd.index)),
        _buildInfoRow(scale, 'Озвучка', rd.group?.label ?? '—'),
        _buildInfoRow(scale, 'Плеєр', rd.hoster.isEmpty ? '—' : rd.hoster),
      ];
    }
    return [_buildInfoRow(scale, 'Шлях', widget.player.state.playlist.medias.firstOrNull?.uri ?? 'Невідомо')];
  }

  Widget _buildInfoSection(double scale, {required String title, required List<Widget> items}) {
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: 8 * scale),
      padding: EdgeInsets.all(12 * scale),
      decoration: BoxDecoration(
        color: uiTheme.bgElevated,
        borderRadius: uiTheme.borderRadius(10 * scale),
        border: Border.all(color: uiTheme.colors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontFamily: 'Arial',
              color: uiTheme.accentColor,
              fontSize: 12 * scale,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 8 * scale),
          ...items,
        ],
      ),
    );
  }

  Widget _buildInfoRow(double scale, String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 3 * scale),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 85 * scale,
            child: Text(
              label,
              style: TextStyle(fontFamily: 'Arial', color: uiTheme.textMuted, fontSize: 11.5 * scale),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontFamily: 'Arial', color: uiTheme.textPrimary, fontSize: 12 * scale, fontWeight: FontWeight.w400),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
        ],
      ),
    );
  }
}
