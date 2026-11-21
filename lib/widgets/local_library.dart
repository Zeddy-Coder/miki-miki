import 'dart:io';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:file_picker/file_picker.dart';
import '../services/playlist_service.dart';
import '../services/storage_service.dart';
import '../services/ui_theme_service.dart';
import '../utils/formatters.dart';
import '../utils/platform_info.dart';
import 'app_animation_kit.dart';
import 'app_media_thumbnail.dart';
import 'app_ui_kit.dart';
import 'design_kit.dart' show AppGroupCaption, AppLineRow, AppMediaRow, AppPillTab;
import 'line_icons.dart';

/// Local media library: open a file or link, file history, the last queue and playlists. It used to be
/// the main screen; now Miki Miki works from the Hikka catalog, so the library is hidden and enabled in
/// "Налаштування → Розробник" (opens from "Профіль").
class LocalLibrary extends StatefulWidget {
  final double scale;
  final ValueChanged<String> onOpenFile;
  final ValueChanged<List<String>> onOpenMultipleFiles;
  final void Function(List<Map<String, String>> items, int startIndex) onOpenQueue;

  /// Extra bottom padding in lists (phone: so the collapsed player does not cover the end of the list)
  final double reserveBottom;

  const LocalLibrary({
    super.key,
    required this.scale,
    required this.onOpenFile,
    required this.onOpenMultipleFiles,
    required this.onOpenQueue,
    this.reserveBottom = 0,
  });

  @override
  State<LocalLibrary> createState() => _LocalLibraryState();
}

class _LocalLibraryState extends State<LocalLibrary> {
  final TextEditingController _urlController = TextEditingController();
  final ScrollController _overviewScroll = AppSmoothScrollController();
  final ScrollController _historyScroll = AppSmoothScrollController();
  final ScrollController _playlistsScroll = AppSmoothScrollController();
  final ScrollController _playlistDetailScroll = AppSmoothScrollController();
  int _tab = 0; // 0 is overview, 1 is history, 2 is playlists
  String? _openPlaylistId;

  @override
  void dispose() {
    _urlController.dispose();
    _overviewScroll.dispose();
    _historyScroll.dispose();
    _playlistsScroll.dispose();
    _playlistDetailScroll.dispose();
    super.dispose();
  }

  void _showUrlDialog() {
    final scale = widget.scale;
    _urlController.clear();

    AppDialogs.show(
      context,
      builder: (ctx) => AlertDialog(
        backgroundColor: uiTheme.colors.bgSurface,
        shape: RoundedRectangleBorder(
          borderRadius: uiTheme.borderRadius(16 * scale),
          side: BorderSide(color: uiTheme.colors.borderSubtle),
        ),
        title: Row(
          children: [
            Icon(Symbols.link_rounded, color: uiTheme.accentColor, size: 24 * scale),
            SizedBox(width: 10 * scale),
            Text(
              'Відкрити потік / URL',
              style: TextStyle(
                fontFamily: 'Arial',
                color: uiTheme.colors.textPrimary,
                fontSize: 16 * scale,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 440 * scale,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Вставте посилання на відео або M3U8 потік:',
                style: TextStyle(
                  fontFamily: 'Arial',
                  color: uiTheme.colors.textMuted,
                  fontSize: 12.5 * scale,
                ),
              ),
              SizedBox(height: 12 * scale),
              TextField(
                controller: _urlController,
                autofocus: true,
                style: TextStyle(
                  fontFamily: 'Arial',
                  color: uiTheme.colors.textPrimary,
                  fontSize: 13 * scale,
                ),
                decoration: InputDecoration(
                  hintText: 'https://example.com/stream.m3u8',
                  hintStyle: TextStyle(color: uiTheme.colors.textDarkMuted, fontSize: 12.5 * scale),
                  filled: true,
                  fillColor: uiTheme.colors.bgElevated,
                  contentPadding: EdgeInsets.symmetric(horizontal: 14 * scale, vertical: 12 * scale),
                  border: OutlineInputBorder(
                    borderRadius: uiTheme.borderRadius(8 * scale),
                    borderSide: BorderSide(color: uiTheme.colors.borderSubtle),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: uiTheme.borderRadius(8 * scale),
                    borderSide: BorderSide(color: uiTheme.accentColor, width: 1.5),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Скасувати',
              style: TextStyle(
                fontFamily: 'Arial',
                color: uiTheme.colors.textMuted,
                fontSize: 13 * scale,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: uiTheme.accentColor,
              shape: RoundedRectangleBorder(borderRadius: uiTheme.borderRadius(8 * scale)),
              padding: EdgeInsets.symmetric(horizontal: 16 * scale, vertical: 10 * scale),
            ),
            onPressed: () {
              final url = _urlController.text.trim();
              if (url.isNotEmpty) {
                Navigator.of(ctx).pop();
                widget.onOpenFile(url);
              }
            },
            child: Text(
              'Відтворити',
              style: TextStyle(
                fontFamily: 'Arial',
                color: uiTheme.onAccent,
                fontWeight: FontWeight.bold,
                fontSize: 13 * scale,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickFolder() async {
    try {
      final dirPath = await FilePicker.getDirectoryPath();
      if (dirPath != null && dirPath.isNotEmpty) {
        final dir = Directory(dirPath);
        final videoExts = ['mp4', 'mkv', 'avi', 'mov', 'webm', 'flv', 'ts', 'm4v', 'm3u', 'm3u8'];
        final List<String> paths = [];
        await for (final entity in dir.list(recursive: false)) {
          if (entity is File) {
            final ext = entity.path.split('.').last.toLowerCase();
            if (videoExts.contains(ext)) paths.add(entity.path);
          }
        }
        paths.sort();
        if (paths.isNotEmpty) widget.onOpenMultipleFiles(paths);
      }
    } catch (_) {}
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowMultiple: true,
        allowedExtensions: ['mp4', 'mkv', 'avi', 'mov', 'webm', 'flv', 'ts', 'm4v', 'm3u', 'm3u8', 'pls'],
      );
      if (result != null && result.files.isNotEmpty) {
        final paths = result.files.where((f) => f.path != null).map((f) => f.path!).toList();
        if (paths.length == 1) {
          widget.onOpenFile(paths.first);
        } else if (paths.length > 1) {
          widget.onOpenMultipleFiles(paths);
        }
      }
    } catch (_) {}
  }

  /// Narrow phone screen (portrait)
  bool get _compact => AppPlatform.isMobile && AppLayout(MediaQuery.sizeOf(context)).isCompactWidth;

  /// Side padding of the content: smaller on a narrow screen
  double _sidePad(double scale) => _compact ? 16.0 : 24 * scale;

  @override
  Widget build(BuildContext context) {
    final scale = widget.scale;
    final recentFiles = StorageService.getRecentFiles();
    final playlists = StorageService.getPlaylists().length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Library sections as pill tabs (as in "Списки"): an icon, a name and a grey counter
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.fromLTRB(_sidePad(scale), 4 * scale, _sidePad(scale), 6 * scale),
          child: Row(
            children: [
              for (final (i, label, icon, count) in [
                (0, 'Огляд', LineIcon.grid, 0),
                (1, 'Історія', LineIcon.history, recentFiles.length),
                (2, 'Плейлисти', LineIcon.playlist, playlists),
              ]) ...[
                if (i > 0) SizedBox(width: 8 * scale),
                AppPillTab(
                  key: ValueKey('library-tab-$i'),
                  scale: scale,
                  label: label,
                  count: count > 0 ? '$count' : null,
                  selected: _tab == i,
                  icon: (c) => LineIconView(icon, size: 16 * scale, color: c),
                  onTap: () => setState(() {
                    _tab = i;
                    if (i == 2) _openPlaylistId = null;
                  }),
                ),
              ],
            ],
          ),
        ),
        AppFadeSwitcher(
          child: KeyedSubtree(
            key: ValueKey('hdr-$_tab-$_openPlaylistId'),
            child: _buildHeader(scale, recentFiles.length),
          ),
        ),
        Expanded(
          child: AppFadeSwitcher(
            expand: true,
            duration: AppAnim.normal,
            child: KeyedSubtree(
              key: ValueKey('body-$_tab-$_openPlaylistId'),
              child: _tab == 0
                  ? _buildOverviewTab(scale, recentFiles)
                  : _tab == 1
                      ? _buildHistoryTab(scale, recentFiles)
                      : _buildPlaylistsTab(scale),
            ),
          ),
        ),
      ],
    );
  }

  // ── Section header ──────────────────────────────────────────────────────────

  Widget _buildHeader(double scale, int recentCount) {
    if (_tab == 2) return _buildPlaylistsHeader(scale);
    if (_tab == 1) {
      return AppPaneHeader(
        scale: scale,
        title: 'Історія відтворення',
        subtitle: recentCount == 0 ? 'Поки що порожньо' : 'Файлів у списку: $recentCount',
        actions: [
          if (recentCount > 0)
            AppSecondaryButton(
              scale: scale,
              expand: false,
              icon: Symbols.delete_outline_rounded,
              label: 'Очистити',
              onTap: () {
                StorageService.clearRecentFiles();
                setState(() {});
              },
            ),
        ],
      );
    }

    return const SizedBox.shrink();
  }

  // ── The "Головна" tab ──────────────────────────────────────────────────────

  /// "Відкрити" (a file, a folder, a network stream) as rows with line icons, the last queue as a tile, recent files
  /// with a frame; hotkeys only with a keyboard
  Widget _buildOverviewTab(double scale, List<String> recentFiles) {
    final pad = _sidePad(scale);
    final preview = recentFiles.take(4).toList();
    final queue = _buildLastQueueSection(scale);
    return AppScrollbar(
      scale: scale,
      controller: _overviewScroll,
      child: SingleChildScrollView(
        controller: _overviewScroll,
        padding: EdgeInsets.only(bottom: 24 * scale + _belowContent()),
        child: Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 920 * scale),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppGroupCaption(scale: scale, text: 'Відкрити', inset: pad, top: 10),
                AppLineRow(scale: scale, inset: pad, icon: LineIcon.doc, title: 'Файл', subtitle: 'MKV, MP4, 4K HDR', chevron: true, onTap: _pickFile),
                AppLineRow(scale: scale, inset: pad, icon: LineIcon.folder, title: 'Папку', subtitle: 'Серіал або сезон — усі серії чергою', chevron: true, onTap: _pickFolder),
                AppLineRow(scale: scale, inset: pad, icon: LineIcon.link, title: 'Мережевий потік', subtitle: 'URL, HLS, M3U8', chevron: true, onTap: _showUrlDialog),
                ...queue,
                if (preview.isNotEmpty) ...[
                  Padding(
                    padding: EdgeInsets.only(right: pad - 8 * scale),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(child: AppGroupCaption(scale: scale, text: 'Нещодавно', inset: pad)),
                        if (recentFiles.length > preview.length) _buildLinkButton(scale, 'Усі ${recentFiles.length}', () => setState(() => _tab = 1)),
                      ],
                    ),
                  ),
                  for (int i = 0; i < preview.length; i++) _buildRecentRow(scale, i, preview[i]),
                ],
                // Hotkeys are needed only with a keyboard: we do not show the section on a phone
                if (!AppPlatform.isMobile) ...[
                  AppGroupCaption(scale: scale, text: 'Гарячі клавіші', inset: pad, top: 22),
                  Padding(
                    padding: EdgeInsets.fromLTRB(pad, 6 * scale, pad, 0),
                    child: Wrap(
                      spacing: 30 * scale,
                      runSpacing: 12 * scale,
                      children: [
                        _buildKeyHint(scale, 'Space', 'Пауза / Пуск'),
                        _buildKeyHint(scale, 'F', 'Повний екран'),
                        _buildKeyHint(scale, 'J / L', '±10 секунд'),
                        _buildKeyHint(scale, '↑ / ↓', 'Гучність'),
                        _buildKeyHint(scale, 'C', 'Субтитри'),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Extra bottom padding so the collapsed player (a floating card) does not cover the end of the list
  double _belowContent() => widget.reserveBottom;

  Widget _buildLinkButton(double scale, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: uiTheme.borderRadius(6 * scale),
      splashColor: Colors.transparent,
      highlightColor: uiTheme.touchHighlight,
      hoverColor: uiTheme.hoverOverlay,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 8 * scale, vertical: 4 * scale),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: TextStyle(fontFamily: 'Arial', fontFamilyFallback: const ['MikiSans'], color: uiTheme.textMuted, fontSize: 12.5 * scale)),
            LineIconView(LineIcon.chevronRight, size: 14 * scale, color: uiTheme.textMuted),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentRow(double scale, int idx, String path) {
    final title = AppFormatters.cleanMediaTitle(path);
    final posMs = StorageService.getPlaybackPosition(path);
    return AppMediaRow(
      key: ValueKey('recent-$idx'),
      scale: scale,
      inset: _sidePad(scale),
      gap: 12,
      leading: AppMediaThumbnail(uri: path, scale: scale, width: 96 * scale, height: 54 * scale, radius: 8),
      title: title,
      titleLines: 1,
      subtitle: posMs > 0 ? 'Зупинено на ${AppFormatters.formatTime(Duration(milliseconds: posMs))}' : 'З початку',
      onTap: () => widget.onOpenFile(path),
    );
  }

  Widget _buildKeyHint(double scale, String keyText, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppKeyCap(scale: scale, text: keyText),
        SizedBox(width: 8 * scale),
        Text(
          label,
          style: TextStyle(fontFamily: 'Arial', color: uiTheme.textMuted, fontSize: 11.5 * scale),
        ),
      ],
    );
  }


  // ── Last queue ──────────────────────────────────────────────────────────

  List<Widget> _buildLastQueueSection(double scale) {
    final q = StorageService.getLastQueue();
    if (q == null) return const [];
    final items = q['items'] as List<Map<String, String>>;
    final idx = q['index'] as int;
    if (items.length < 2) return const [];
    final cur = items[idx];
    final curTitle = (cur['title'] ?? '').isNotEmpty ? cur['title']! : AppFormatters.cleanMediaTitle(cur['uri']!);

    return [
      AppGroupCaption(scale: scale, text: 'Остання черга', inset: _sidePad(scale)),
      Padding(
        padding: EdgeInsets.fromLTRB(_sidePad(scale), 6 * scale, _sidePad(scale), 4 * scale),
        child: _buildLastQueueCard(scale, items, idx, curTitle, cur['uri']!),
      ),
    ];
  }

  /// The queue as a tile: a frame, the current title and "Серія 6 з 12"; "Зберегти" keeps it as a playlist, the round
  /// play button (or a tap on the tile) brings it back
  Widget _buildLastQueueCard(double scale, List<Map<String, String>> items, int idx, String curTitle, String uri) {
    final shape = RoundedRectangleBorder(borderRadius: uiTheme.borderRadius(14 * scale), side: BorderSide(color: uiTheme.borderSubtle));
    return Material(
      color: uiTheme.bgSurface,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const ValueKey('library-queue'),
        onTap: () => widget.onOpenQueue(items, idx),
        splashColor: Colors.transparent,
        highlightColor: uiTheme.touchHighlight,
        hoverColor: uiTheme.hoverOverlay,
        child: Stack(
          children: [
            Padding(
              padding: EdgeInsets.all(10 * scale),
              child: Row(
                children: [
                  _queueThumb(scale, uri, items.length, 88, 49.5),
                  SizedBox(width: 12 * scale),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(curTitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: 'Arial', fontFamilyFallback: const ['MikiSans'], color: uiTheme.textPrimary, fontSize: 14 * scale, fontWeight: FontWeight.bold, height: 1.25)),
                        SizedBox(height: 3 * scale),
                        Text('Серія ${idx + 1} з ${items.length}', style: TextStyle(fontFamily: 'Arial', fontFamilyFallback: const ['MikiSans'], color: uiTheme.textMuted, fontSize: 12 * scale)),
                      ],
                    ),
                  ),
                  Tooltip(
                    message: 'Зберегти як плейлист',
                    child: InkResponse(
                      onTap: () => _saveQueueAsPlaylist(items),
                      radius: 20 * scale,
                      child: SizedBox.square(
                        dimension: AppPlatform.isMobile ? 44.0 : 36 * scale,
                        child: Center(child: LineIconView(LineIcon.playlist, size: 20 * scale, color: uiTheme.textMuted)),
                      ),
                    ),
                  ),
                  SizedBox(width: 4 * scale),
                  Semantics(
                    button: true,
                    label: 'Відновити чергу',
                    child: Container(
                      width: 36 * scale,
                      height: 36 * scale,
                      decoration: const BoxDecoration(color: Color(0xFF2A2A30), shape: BoxShape.circle),
                      child: Center(child: LineIconView(LineIcon.play, size: 14 * scale, color: const Color(0xFFEEEEEE))),
                    ),
                  ),
                ],
              ),
            ),
            // How far into the queue: a thin accent line along the bottom edge
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SizedBox(
                height: 3 * scale,
                child: ColoredBox(
                  color: const Color(0xFF26262B),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: ((idx + 1) / items.length).clamp(0.0, 1.0),
                    child: ColoredBox(color: uiTheme.accentColor),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _queueThumb(double scale, String uri, int count, double w, double h) {
    return AppMediaThumbnail(
      uri: uri,
      scale: scale,
      width: w * scale,
      height: h * scale,
      radius: 8,
      overlay: Stack(
        children: [
          Positioned(
            right: 4 * scale,
            bottom: 4 * scale,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 5 * scale, vertical: 1.5 * scale),
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.72), borderRadius: uiTheme.borderRadius(4 * scale)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Symbols.queue_music_rounded, color: Colors.white, size: 11 * scale),
                  SizedBox(width: 3 * scale),
                  Text('$count', style: TextStyle(fontFamily: 'Arial', color: Colors.white, fontWeight: FontWeight.bold, fontSize: 9.5 * scale)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Playlists ──────────────────────────────────────────────────────────────

  List<Map<String, String>> _toItems(List<String> paths) =>
      paths.map((p) => {'uri': p, 'title': AppFormatters.cleanMediaTitle(p)}).toList();

  Future<String?> _askName({required String title, required String action, String initial = ''}) {
    final scale = widget.scale;
    final controller = TextEditingController(text: initial);
    controller.selection = TextSelection(baseOffset: 0, extentOffset: initial.length);

    return AppDialogs.show<String>(
      context,
      builder: (ctx) => AlertDialog(
        backgroundColor: uiTheme.colors.bgSurface,
        shape: RoundedRectangleBorder(
          borderRadius: uiTheme.borderRadius(16 * scale),
          side: BorderSide(color: uiTheme.colors.borderSubtle),
        ),
        title: Row(
          children: [
            Icon(Symbols.queue_music_rounded, color: uiTheme.accentColor, size: 24 * scale),
            SizedBox(width: 10 * scale),
            Text(
              title,
              style: TextStyle(fontFamily: 'Arial', color: uiTheme.colors.textPrimary, fontSize: 16 * scale, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: SizedBox(
          width: 380 * scale,
          child: TextField(
            controller: controller,
            autofocus: true,
            onSubmitted: (v) {
              if (v.trim().isNotEmpty) Navigator.of(ctx).pop(v.trim());
            },
            style: TextStyle(fontFamily: 'Arial', color: uiTheme.colors.textPrimary, fontSize: 13 * scale),
            decoration: InputDecoration(
              hintText: 'Назва плейлиста',
              hintStyle: TextStyle(color: uiTheme.colors.textDarkMuted, fontSize: 12.5 * scale),
              filled: true,
              fillColor: uiTheme.colors.bgElevated,
              contentPadding: EdgeInsets.symmetric(horizontal: 14 * scale, vertical: 12 * scale),
              border: OutlineInputBorder(
                borderRadius: uiTheme.borderRadius(8 * scale),
                borderSide: BorderSide(color: uiTheme.colors.borderSubtle),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: uiTheme.borderRadius(8 * scale),
                borderSide: BorderSide(color: uiTheme.accentColor, width: 1.5),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Скасувати', style: TextStyle(fontFamily: 'Arial', color: uiTheme.colors.textMuted, fontSize: 13 * scale)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: uiTheme.accentColor,
              shape: RoundedRectangleBorder(borderRadius: uiTheme.borderRadius(8 * scale)),
              padding: EdgeInsets.symmetric(horizontal: 16 * scale, vertical: 10 * scale),
            ),
            onPressed: () {
              final v = controller.text.trim();
              if (v.isNotEmpty) Navigator.of(ctx).pop(v);
            },
            child: Text(
              action,
              style: TextStyle(fontFamily: 'Arial', color: uiTheme.onAccent, fontWeight: FontWeight.bold, fontSize: 13 * scale),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _createPlaylist() async {
    final paths = await PlaylistService.pickVideoPaths();
    if (paths.isEmpty || !mounted) return;
    final name = await _askName(
      title: 'Новий плейлист',
      action: 'Створити',
      initial: 'Плейлист ${StorageService.getPlaylists().length + 1}',
    );
    if (name == null || !mounted) return;
    final id = StorageService.createPlaylist(name, _toItems(paths));
    setState(() {
      _tab = 2;
      _openPlaylistId = id;
    });
  }

  Future<void> _saveQueueAsPlaylist(List<Map<String, String>> items) async {
    final now = DateTime.now();
    final name = await _askName(
      title: 'Зберегти чергу як плейлист',
      action: 'Зберегти',
      initial: 'Черга ${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}',
    );
    if (name == null || !mounted) return;
    final id = StorageService.createPlaylist(name, items);
    setState(() {
      _tab = 2;
      _openPlaylistId = id;
    });
  }

  Future<void> _renamePlaylist(Map<String, dynamic> pl) async {
    final name = await _askName(title: 'Перейменувати', action: 'Зберегти', initial: pl['name'] as String);
    if (name == null || !mounted) return;
    StorageService.updatePlaylist(pl['id'] as String, name: name);
    setState(() {});
  }

  void _deletePlaylist(Map<String, dynamic> pl) {
    StorageService.deletePlaylist(pl['id'] as String);
    setState(() => _openPlaylistId = null);
  }

  Future<void> _addToPlaylist(Map<String, dynamic> pl) async {
    final paths = await PlaylistService.pickVideoPaths();
    if (paths.isEmpty || !mounted) return;
    final items = List<Map<String, String>>.from(pl['items'] as List);
    final existing = items.map((e) => e['uri']).toSet();
    items.addAll(_toItems(paths.where((p) => !existing.contains(p)).toList()));
    StorageService.updatePlaylist(pl['id'] as String, items: items);
    setState(() {});
  }

  Map<String, dynamic>? _currentPlaylist() {
    if (_openPlaylistId == null) return null;
    for (final pl in StorageService.getPlaylists()) {
      if (pl['id'] == _openPlaylistId) return pl;
    }
    return null;
  }

  Widget _buildPlaylistsHeader(double scale) {
    final pl = _currentPlaylist();
    if (pl == null) {
      final count = StorageService.getPlaylists().length;
      return AppPaneHeader(
        scale: scale,
        title: 'Плейлисти',
        subtitle: count == 0 ? 'Збережені підбірки відео' : 'Збережено плейлистів: $count',
        actions: [
          AppAccentButton(scale: scale, icon: Symbols.add_rounded, label: 'Новий плейлист', onTap: _createPlaylist),
        ],
      );
    }
    final items = pl['items'] as List<Map<String, String>>;
    return AppPaneHeader(
      scale: scale,
      title: pl['name'] as String,
      subtitle: 'Відео: ${items.length}',
      actions: [
        AppSecondaryButton(
          scale: scale,
          expand: false,
          icon: Symbols.arrow_back_rounded,
          label: 'Назад',
          onTap: () => setState(() => _openPlaylistId = null),
        ),
        if (items.isNotEmpty)
          AppAccentButton(
            scale: scale,
            icon: Symbols.play_arrow_rounded,
            label: 'Відтворити',
            onTap: () => widget.onOpenQueue(items, 0),
          ),
      ],
    );
  }

  Widget _buildPlaylistsTab(double scale) {
    final pl = _currentPlaylist();
    if (pl != null) return _buildPlaylistDetail(scale, pl);

    final playlists = StorageService.getPlaylists();
    if (playlists.isEmpty) {
      return AppEmptyState(
        scale: scale,
        icon: Symbols.queue_music_rounded,
        text: 'Плейлистів ще немає. Створіть новий або збережіть поточну чергу з головної',
      );
    }

    return AppScrollbar(
      scale: scale,
      controller: _playlistsScroll,
      child: ListView.builder(
        controller: _playlistsScroll,
        padding: EdgeInsets.fromLTRB(_sidePad(scale), 4 * scale, _sidePad(scale), 24 * scale + _belowContent()),
        itemCount: playlists.length,
        itemBuilder: (context, i) => Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 920 * scale),
            child: _buildPlaylistRow(scale, playlists[i]),
          ),
        ),
      ),
    );
  }

  Widget _buildPlaylistRow(double scale, Map<String, dynamic> pl) {
    final items = pl['items'] as List<Map<String, String>>;
    return Padding(
      padding: EdgeInsets.only(bottom: 8 * scale),
      child: AppCard(
        scale: scale,
        radius: 10,
        onTap: () => setState(() => _openPlaylistId = pl['id'] as String),
        padding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 9 * scale),
        child: Row(
          children: [
            items.isEmpty
                ? Container(
                    width: 80 * scale,
                    height: 45 * scale,
                    decoration: BoxDecoration(
                      color: uiTheme.bgElevated,
                      borderRadius: uiTheme.borderRadius(6 * scale),
                      border: Border.all(color: uiTheme.colors.borderSubtle),
                    ),
                    child: Icon(Symbols.queue_music_rounded, color: uiTheme.textDarkMuted, size: 20 * scale),
                  )
                : _queueThumb(scale, items.first['uri']!, items.length, 80, 45),
            SizedBox(width: 14 * scale),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pl['name'] as String,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontFamily: 'Arial', color: uiTheme.textPrimary, fontWeight: FontWeight.w500, fontSize: 13 * scale),
                  ),
                  SizedBox(height: 2 * scale),
                  Text(
                    'Відео: ${items.length}',
                    style: TextStyle(fontFamily: 'Arial', color: uiTheme.textMuted, fontSize: 11 * scale),
                  ),
                ],
              ),
            ),
            if (items.isNotEmpty)
              InkWell(
                onTap: () => widget.onOpenQueue(items, 0),
                borderRadius: uiTheme.borderRadius(8 * scale),
                hoverColor: uiTheme.hoverOverlay,
                child: Padding(
                  padding: EdgeInsets.all(6 * scale),
                  child: Icon(Symbols.play_arrow_rounded, color: uiTheme.accentColor, size: 22 * scale, weight: 300, opticalSize: 24),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaylistDetail(double scale, Map<String, dynamic> pl) {
    final items = pl['items'] as List<Map<String, String>>;

    return AppScrollbar(
      scale: scale,
      controller: _playlistDetailScroll,
      child: ListView.builder(
        controller: _playlistDetailScroll,
        padding: EdgeInsets.fromLTRB(_sidePad(scale), 4 * scale, _sidePad(scale), 24 * scale + _belowContent()),
        itemCount: items.length + 1,
        itemBuilder: (context, i) {
          return Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 920 * scale),
              child: i == 0
                  ? Padding(
                      padding: EdgeInsets.only(bottom: 14 * scale),
                      child: Wrap(
                        spacing: 8 * scale,
                        runSpacing: 8 * scale,
                        children: [
                          AppSecondaryButton(
                            scale: scale,
                            expand: false,
                            icon: Symbols.add_rounded,
                            label: 'Додати файли',
                            onTap: () => _addToPlaylist(pl),
                          ),
                          AppSecondaryButton(
                            scale: scale,
                            expand: false,
                            icon: Symbols.edit_rounded,
                            label: 'Перейменувати',
                            onTap: () => _renamePlaylist(pl),
                          ),
                          AppSecondaryButton(
                            scale: scale,
                            expand: false,
                            icon: Symbols.delete_outline_rounded,
                            label: 'Видалити плейлист',
                            onTap: () => _deletePlaylist(pl),
                          ),
                        ],
                      ),
                    )
                  : _buildPlaylistItemRow(scale, pl, items, i - 1),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPlaylistItemRow(double scale, Map<String, dynamic> pl, List<Map<String, String>> items, int idx) {
    final it = items[idx];
    final uri = it['uri']!;
    final title = (it['title'] ?? '').isNotEmpty ? it['title']! : AppFormatters.cleanMediaTitle(uri);
    final posMs = StorageService.getPlaybackPosition(uri);

    return Padding(
      padding: EdgeInsets.only(bottom: 8 * scale),
      child: AppCard(
        scale: scale,
        radius: 10,
        onTap: () => widget.onOpenQueue(items, idx),
        padding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 9 * scale),
        child: Row(
          children: [
            AppMediaThumbnail(
              uri: uri,
              scale: scale,
              width: 80 * scale,
              height: 45 * scale,
              radius: 6,
              overlay: Stack(
                children: [
                  Positioned(
                    top: 3 * scale,
                    left: 3 * scale,
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 4 * scale, vertical: 1 * scale),
                      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.72), borderRadius: uiTheme.borderRadius(4 * scale)),
                      child: Text(
                        '#${idx + 1}',
                        style: TextStyle(fontFamily: 'Arial', color: Colors.white, fontWeight: FontWeight.bold, fontSize: 9.5 * scale),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: 14 * scale),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontFamily: 'Arial', color: uiTheme.textPrimary, fontWeight: FontWeight.w500, fontSize: 13 * scale),
                  ),
                  SizedBox(height: 2 * scale),
                  Text(
                    posMs > 0 ? 'Зупинено на ${AppFormatters.formatTime(Duration(milliseconds: posMs))}' : 'З початку',
                    style: TextStyle(fontFamily: 'Arial', color: uiTheme.textMuted, fontSize: 11 * scale),
                  ),
                ],
              ),
            ),
            InkWell(
              onTap: () {
                final next = List<Map<String, String>>.from(items)..removeAt(idx);
                StorageService.updatePlaylist(pl['id'] as String, items: next);
                setState(() {});
              },
              borderRadius: uiTheme.borderRadius(8 * scale),
              hoverColor: uiTheme.hoverOverlay,
              child: Padding(
                padding: EdgeInsets.all(6 * scale),
                child: Icon(Symbols.close_rounded, color: uiTheme.textMuted, size: 18 * scale, weight: 300, opticalSize: 24),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── The "Історія" tab ──────────────────────────────────────────────────────

  Widget _buildHistoryTab(double scale, List<String> recentFiles) {
    if (recentFiles.isEmpty) {
      return AppEmptyState(
        scale: scale,
        icon: Symbols.history_rounded,
        text: 'Історія порожня. Відкрийте файл, і він з\'явиться тут',
      );
    }

    return AppScrollbar(
      scale: scale,
      controller: _historyScroll,
      child: ListView.builder(
        controller: _historyScroll,
        padding: EdgeInsets.fromLTRB(_sidePad(scale), 4 * scale, _sidePad(scale), 24 * scale + _belowContent()),
        itemCount: recentFiles.length,
        itemBuilder: (context, idx) => Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 920 * scale),
            child: _buildRecentRow(scale, idx, recentFiles[idx]),
          ),
        ),
      ),
    );
  }
}
