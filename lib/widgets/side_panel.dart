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
import 'app_tones.dart';
import 'design_kit.dart';
import 'line_icons.dart';
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

  /// Site episodes: instead of a file queue, episodes, dubs and players are shown
  final RemoteDriver? remote;

  /// Phone: without a surface or width of its own: the surface and position come from [MobileSheetFrame],
  /// the buttons are enlarged for touch, the queue is reordered only by dragging
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
    // We do not start background players (previews) while the panel slides out, otherwise it hurts smoothness
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
      width: 88 * scale,
      height: 50 * scale,
      decoration: BoxDecoration(
        color: AppTones.plate,
        borderRadius: uiTheme.borderRadius(8 * scale),
        border: isCurrent ? Border.all(color: uiTheme.accentColor, width: 1.5) : null,
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
                    : Center(key: ValueKey('p$index'), child: LineIconView(LineIcon.chapters, size: 20 * scale, color: AppTones.chevron)),
              );
            },
          ),
          Positioned(top: 4 * scale, left: 4 * scale, child: _badge(scale, '${index + 1}')),
        ],
      ),
    );
  }

  /// A small dark number on a picture ("3", "#2")
  Widget _badge(double scale, String text) => Container(
        padding: EdgeInsets.symmetric(horizontal: 5 * scale, vertical: 1.5 * scale),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.72), borderRadius: uiTheme.borderRadius(5 * scale)),
        child: Text(text, style: _text(10 * scale, color: Colors.white, weight: FontWeight.w700)),
      );

  static TextStyle _text(double size, {Color? color, FontWeight weight = FontWeight.normal, double? height, List<FontFeature>? features}) => TextStyle(
        fontFamily: 'Arial',
        fontFamilyFallback: const ['MikiSans'],
        color: color ?? uiTheme.textPrimary,
        fontSize: size,
        fontWeight: weight,
        height: height,
        fontFeatures: features,
      );

  /// A flat list row in the style of the app's menus: a soft highlight under the finger or cursor, nothing else
  Widget _flatRow(double scale, {required Widget child, VoidCallback? onTap, Key? key}) => Material(
        key: key,
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          splashColor: Colors.transparent,
          highlightColor: uiTheme.touchHighlight,
          hoverColor: uiTheme.hoverOverlay,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: (widget.sheet ? 14 : 10) * scale, vertical: 7 * scale),
            child: child,
          ),
        ),
      );

  /// A small line-icon button in a row (loop a chapter, move or remove a file); [active] — in the accent
  Widget _rowButton(double scale, LineIcon icon, String label, VoidCallback? onTap, {bool active = false, Key? key}) {
    final double size = widget.sheet ? 44 : 30 * scale;
    final enabled = onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      selected: active,
      label: label,
      child: Tooltip(
        message: label,
        child: InkResponse(
          key: key,
          onTap: onTap,
          radius: size * 0.55,
          highlightColor: uiTheme.hoverOverlay,
          splashColor: uiTheme.hoverOverlay,
          child: SizedBox.square(
            dimension: size,
            child: Center(
              child: LineIconView(icon, size: (widget.sheet ? 20 : 17) * scale, color: active ? uiTheme.accentColor : (enabled ? AppTones.rowIcon : AppTones.chevron)),
            ),
          ),
        ),
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
    final rd = widget.remote;
    // Site episodes: the "Перегляд" panel draws its own header (its pages have their own titles)
    final Widget body = widget.type == SidePanelType.episodes && rd != null && rd.active
        ? RemotePanelBody(scale: scale, driver: rd, sheet: widget.sheet, onEpisodeSelected: widget.onEpisodeSelected, onClose: widget.onClose)
        : Column(
            children: [
              AppPanelHeader(scale: scale, title: _getTitle(), onClose: widget.onClose),
              Expanded(child: _buildContent(scale)),
            ],
          );

    if (widget.sheet) return body;

    return AppPanelSurface(
      scale: scale,
      width: 380 * scale,
      radius: 16,
      shadowOffset: const Offset(-4, 0),
      margin: EdgeInsets.only(top: 8 * scale, bottom: 8 * scale, right: 8 * scale),
      child: body,
    );
  }

  String _getTitle() {
    switch (widget.type) {
      case SidePanelType.chapters: return widget.chapters.isEmpty ? 'Розділи' : 'Розділи · ${widget.chapters.length}';
      case SidePanelType.episodes: return widget.playlistItems.isEmpty ? 'Черга' : 'Черга · ${widget.playlistItems.length}';
      case SidePanelType.info: return 'Про відео';
    }
  }

  Widget _buildContent(double scale) {
    switch (widget.type) {
      case SidePanelType.chapters: return _buildChaptersList(scale);
      case SidePanelType.episodes:
        return _buildEpisodesList(scale);
      case SidePanelType.info: return _buildInfoTab(scale);
    }
  }

  /// A thin scrollbar in the style of the settings menu
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

    // The video position updates dozens of times per second, so we listen not to it but only to
    // the current chapter index (distinct): the list rebuilds only when the chapter changes.
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
            padding: EdgeInsets.only(bottom: 8 * scale),
            itemCount: widget.chapters.length,
            itemBuilder: (context, index) {
              final ch = widget.chapters[index];
              final bool isCurrent = index == currentIndex;

              final Duration chEnd = (index + 1 < widget.chapters.length) ? widget.chapters[index + 1].startTime : widget.player.state.duration;
              final Duration len = chEnd - ch.startTime;
              final bool looping = _loopChapter == index;
              return KeyedSubtree(
                key: isCurrent ? _currentRowKey : ValueKey('ch$index'),
                child: _flatRow(
                  scale,
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
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: _text((widget.sheet ? 15 : 14) * scale, weight: isCurrent ? FontWeight.w700 : FontWeight.normal, height: 1.25),
                            ),
                            SizedBox(height: 2 * scale),
                            Text(
                              isCurrent ? 'Зараз · ${AppFormatters.formatTime(ch.startTime)}' : (len > Duration.zero ? '${AppFormatters.formatTime(ch.startTime)} · ${AppFormatters.formatTime(len)}' : AppFormatters.formatTime(ch.startTime)),
                              style: _text(12.5 * scale, color: isCurrent ? uiTheme.accentColor : AppTones.rowSub, features: const [FontFeature.tabularFigures()]),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(width: 4 * scale),
                      _rowButton(
                        scale,
                        LineIcon.repeat,
                        looping ? 'Вимкнути повтор розділу' : 'Повторювати розділ',
                        () => _toggleLoop(index),
                        active: looping,
                        key: ValueKey('chapter-loop-$index'),
                      ),
                    ],
                  ),
                ),
              );
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

  String _modeTip(PlaylistMode m) {
    switch (m) {
      case PlaylistMode.single: return 'Повтор відео';
      case PlaylistMode.loop: return 'Повтор черги';
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
    final many = widget.playlistItems.length > 1;
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB((widget.sheet ? 20 : 16) * scale, 2 * scale, (widget.sheet ? 20 : 16) * scale, 8 * scale),
          child: Row(
            children: [
              AppPlate(
                key: const ValueKey('queue-add'),
                scale: scale,
                label: 'Додати',
                height: widget.sheet ? 40 : 34,
                radius: 10,
                leading: (c) => LineIconView(LineIcon.plus, size: 17 * scale, color: c),
                onTap: widget.onAddMedia,
              ),
              SizedBox(width: 8 * scale),
              Flexible(
                child: StreamBuilder<PlaylistMode>(
                  stream: widget.player.stream.playlistMode,
                  initialData: widget.player.state.playlistMode,
                  builder: (context, snap) {
                    final m = snap.data ?? PlaylistMode.none;
                    return AppPlate(
                      key: const ValueKey('queue-repeat'),
                      scale: scale,
                      label: _modeTip(m),
                      height: widget.sheet ? 40 : 34,
                      radius: 10,
                      selected: m != PlaylistMode.none,
                      leading: (c) => LineIconView(LineIcon.repeat, size: 17 * scale, color: m != PlaylistMode.none ? uiTheme.accentColor : c),
                      onTap: _cycleMode,
                    );
                  },
                ),
              ),
              const Spacer(),
              _rowButton(scale, LineIcon.trash, 'Очистити чергу (крім поточного)', many ? widget.onQueueClear : null, key: const ValueKey('queue-clear')),
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
                    padding: EdgeInsets.only(bottom: 8 * scale),
                    itemCount: widget.playlistItems.length,
                    proxyDecorator: (child, i, anim) => Material(color: uiTheme.bgSurface, elevation: 6, child: child),
                    onReorderItem: widget.onQueueReorder,
                    itemBuilder: (context, index) {
                      final item = widget.playlistItems[index];
                      final bool isCurrent = index == widget.currentPlaylistIndex;
                      final title = item.extras?['title'] ?? AppFormatters.cleanMediaTitle(item.uri);
                      final bool isFirst = index == 0;
                      final bool isLast = index == widget.playlistItems.length - 1;

                      return KeyedSubtree(
                        key: ObjectKey(item),
                        child: _flatRow(
                          scale,
                          key: ValueKey('queue-$index'),
                          onTap: () => widget.onEpisodeSelected(index),
                          child: Row(
                            children: [
                              ReorderableDragStartListener(
                                index: index,
                                child: MouseRegion(
                                  cursor: SystemMouseCursors.grab,
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(horizontal: (widget.sheet ? 6 : 2) * scale, vertical: 12 * scale),
                                    child: LineIconView(LineIcon.grip, size: 18 * scale, color: AppTones.chevron, stroke: 2.6),
                                  ),
                                ),
                              ),
                              SizedBox(width: 4 * scale),
                              _buildThumb(scale, index, isCurrent, item.uri),
                              SizedBox(width: 12 * scale),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: _text((widget.sheet ? 15 : 14) * scale, weight: isCurrent ? FontWeight.w700 : FontWeight.normal, height: 1.25),
                                    ),
                                    if (isCurrent) ...[
                                      SizedBox(height: 2 * scale),
                                      Text('Зараз відтворюється', style: _text(12.5 * scale, color: uiTheme.accentColor)),
                                    ],
                                  ],
                                ),
                              ),
                              if (many && !widget.sheet) ...[
                                SizedBox(width: 4 * scale),
                                Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _rowButton(scale, LineIcon.chevronUp, 'Вище', isFirst ? null : () => widget.onQueueReorder(index, index - 1)),
                                    _rowButton(scale, LineIcon.chevronDown, 'Нижче', isLast ? null : () => widget.onQueueReorder(index, index + 1)),
                                  ],
                                ),
                              ],
                              if (!isCurrent && many)
                                _rowButton(scale, LineIcon.close, 'Прибрати з черги', () => widget.onQueueRemove(index), key: ValueKey('queue-remove-$index'))
                              else
                                SizedBox(width: widget.sheet ? 44 : 30 * scale),
                            ],
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
      width: 88 * scale,
      height: 50 * scale,
      radius: 8,
      borderColor: isCurrent ? uiTheme.accentColor : Colors.transparent,
      fallback: Center(child: LineIconView(LineIcon.play, size: 18 * scale, color: isCurrent ? uiTheme.accentColor : AppTones.chevron)),
      overlay: Stack(
        children: [
          Positioned(top: 4 * scale, left: 4 * scale, child: _badge(scale, '${index + 1}')),
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
                  return _badge(scale, AppFormatters.formatTime(dur));
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
        padding: EdgeInsets.only(bottom: 8 * scale),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
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

  /// Lines about the video source: the file path or episode / dub / player (we do not show the direct stream link)
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppGroupCaption(scale: scale, text: title, inset: (widget.sheet ? 20 : 16) * scale, top: 10),
        ...items,
        SizedBox(height: 4 * scale),
      ],
    );
  }

  Widget _buildInfoRow(double scale, String label, String value) {
    final pad = (widget.sheet ? 20 : 16) * scale;
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 5 * scale, pad, 5 * scale),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 92 * scale, child: Text(label, style: _text(13 * scale, color: AppTones.rowSub, height: 1.35))),
          Expanded(
            child: Text(value, maxLines: 3, overflow: TextOverflow.ellipsis, style: _text(13.5 * scale, height: 1.35)),
          ),
        ],
      ),
    );
  }
}
