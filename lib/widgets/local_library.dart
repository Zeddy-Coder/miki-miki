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

/// Локальна медіатека: відкрити файл чи посилання, історія файлів, остання черга й плейлисти. Раніше була
/// головним екраном; тепер Miki Miki працює від каталогу Hikka, тож медіатека прихована й вмикається в
/// «Налаштування → Розробник» (відкривається з «Профілю»).
class LocalLibrary extends StatefulWidget {
  final double scale;
  final ValueChanged<String> onOpenFile;
  final ValueChanged<List<String>> onOpenMultipleFiles;
  final void Function(List<Map<String, String>> items, int startIndex) onOpenQueue;

  /// Додатковий відступ знизу у списках (телефон: щоб згорнутий плеєр не закривав кінець списку)
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
  int _tab = 0; // 0 — огляд, 1 — історія, 2 — плейлисти
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

  /// Вузький екран телефона (портрет)
  bool get _compact => AppPlatform.isMobile && AppLayout(MediaQuery.sizeOf(context)).isCompactWidth;

  /// Бічний відступ вмісту: на вузькому екрані менший
  double _sidePad(double scale) => _compact ? 16.0 : 24 * scale;

  @override
  Widget build(BuildContext context) {
    final scale = widget.scale;
    final recentFiles = StorageService.getRecentFiles();
    final playlists = StorageService.getPlaylists().length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Розділи медіатеки (раніше — пункти нижньої навігації й бічного меню)
        Padding(
          padding: EdgeInsets.fromLTRB(_sidePad(scale), 4 * scale, _sidePad(scale), 2 * scale),
          child: AppSegmentedBar<int>(
            scale: scale * (_compact ? 0.95 : 1),
            selectedValue: _tab,
            options: [
              const AppSegmentOption(value: 0, label: 'Огляд'),
              AppSegmentOption(value: 1, label: recentFiles.isEmpty ? 'Історія' : 'Історія · ${recentFiles.length}'),
              AppSegmentOption(value: 2, label: playlists == 0 ? 'Плейлисти' : 'Плейлисти · $playlists'),
            ],
            onSelected: (v) => setState(() {
              _tab = v;
              if (v == 2) _openPlaylistId = null;
            }),
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

  // ── Шапка розділу ──────────────────────────────────────────────────────────

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

    return AppPaneHeader(
      scale: scale,
      title: 'Локальні файли',
      subtitle: 'Продовжуйте перегляд або відкрийте нове відео',
      actions: [
        AppSecondaryButton(
          scale: scale,
          expand: false,
          icon: Symbols.link_rounded,
          label: 'URL / Потік',
          onTap: _showUrlDialog,
        ),
        AppAccentButton(
          scale: scale,
          icon: Symbols.file_open_rounded,
          label: 'Відкрити файл',
          onTap: _pickFile,
        ),
      ],
    );
  }

  // ── Вкладка «Головна» ──────────────────────────────────────────────────────

  Widget _buildOverviewTab(double scale, List<String> recentFiles) {
    final String? lastFile = recentFiles.isNotEmpty ? recentFiles.first : null;
    final int lastPosMs = lastFile != null ? StorageService.getPlaybackPosition(lastFile) : 0;
    final bool canResume = lastFile != null && lastPosMs > 5000;
    final preview = recentFiles.take(4).toList();

    return AppScrollbar(
      scale: scale,
      controller: _overviewScroll,
      child: SingleChildScrollView(
        controller: _overviewScroll,
        padding: EdgeInsets.fromLTRB(_sidePad(scale), 4 * scale, _sidePad(scale), 24 * scale + _belowContent()),
        child: Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 920 * scale),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (canResume) ...[
                  AppSectionHeader(scale: scale, title: 'Продовжити перегляд', subtitle: 'Останній файл, який ви не додивились'),
                  SizedBox(height: 10 * scale),
                  _buildResumeCard(scale, lastFile, lastPosMs),
                  SizedBox(height: 26 * scale),
                ],
                ..._buildLastQueueSection(scale),
                AppSectionHeader(scale: scale, title: 'Швидкі дії', subtitle: 'Відкрийте файл, папку або мережевий потік'),
                SizedBox(height: 10 * scale),
                _buildActionCards(scale),
                if (preview.isNotEmpty) ...[
                  SizedBox(height: 26 * scale),
                  AppSectionHeader(
                    scale: scale,
                    title: 'Нещодавні',
                    subtitle: 'Останні відкриті файли',
                    trailing: recentFiles.length > preview.length
                        ? _buildLinkButton(scale, 'Усі (${recentFiles.length})', () => setState(() => _tab = 1))
                        : null,
                  ),
                  SizedBox(height: 10 * scale),
                  for (int i = 0; i < preview.length; i++) _buildRecentRow(scale, i, preview[i]),
                ],
                // Гарячі клавіші потрібні лише з клавіатурою — на телефоні розділ не показуємо
                if (!AppPlatform.isMobile) ...[
                  SizedBox(height: 22 * scale),
                  AppSectionHeader(scale: scale, title: 'Гарячі клавіші', subtitle: 'Працюють під час відтворення'),
                  SizedBox(height: 10 * scale),
                  AppCard(
                    scale: scale,
                    padding: EdgeInsets.symmetric(horizontal: 16 * scale, vertical: 14 * scale),
                    child: SizedBox(
                      width: double.infinity,
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
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Додатковий відступ знизу, щоб згорнутий плеєр (плаваюча картка) не закривав кінець списку
  double _belowContent() => widget.reserveBottom;

  /// Три швидкі дії: у рядок на широкому екрані, у стовпчик на вузькому
  Widget _buildActionCards(double scale) {
    final cards = <Widget>[
      _buildActionCard(
        scale,
        icon: Symbols.file_open_rounded,
        title: 'Відкрити файл',
        subtitle: 'MKV, MP4, 4K HDR',
        onTap: _pickFile,
      ),
      _buildActionCard(
        scale,
        icon: Symbols.folder_open_rounded,
        title: 'Відкрити папку',
        subtitle: 'Серіал або сезон',
        onTap: _pickFolder,
      ),
      _buildActionCard(
        scale,
        icon: Symbols.link_rounded,
        title: 'Мережевий потік',
        subtitle: 'URL / HLS / M3U8',
        onTap: _showUrlDialog,
      ),
    ];
    if (_compact) {
      return Column(
        children: [
          for (int i = 0; i < cards.length; i++) ...[
            if (i > 0) SizedBox(height: 8 * scale),
            SizedBox(width: double.infinity, child: cards[i]),
          ],
        ],
      );
    }
    return Row(
      children: [
        for (int i = 0; i < cards.length; i++) ...[
          if (i > 0) SizedBox(width: 12 * scale),
          Expanded(child: cards[i]),
        ],
      ],
    );
  }

  Widget _buildResumeCard(double scale, String path, int posMs) {
    final bool compact = _compact;
    final thumb = AppMediaThumbnail(
      uri: path,
      scale: scale,
      width: (compact ? 104 : 112) * scale,
      height: (compact ? 58.5 : 63) * scale,
      radius: 8,
      borderColor: uiTheme.accentBorder,
      overlay: Center(
        child: Container(
          width: 28 * scale,
          height: 28 * scale,
          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), shape: BoxShape.circle),
          child: Icon(Symbols.play_arrow_rounded, color: Colors.white, size: 18 * scale, fill: 1),
        ),
      ),
    );
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppFormatters.cleanMediaTitle(path),
          maxLines: compact ? 2 : 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: 'Arial',
            color: uiTheme.textPrimary,
            fontSize: 14 * scale,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: 4 * scale),
        Text(
          'Зупинено на ${AppFormatters.formatTime(Duration(milliseconds: posMs))}',
          style: TextStyle(fontFamily: 'Arial', color: uiTheme.textMuted, fontSize: 11.5 * scale),
        ),
      ],
    );
    final resume = AppAccentButton(
      scale: scale,
      expand: compact,
      icon: Symbols.play_arrow_rounded,
      label: 'Продовжити',
      onTap: () => widget.onOpenFile(path),
    );

    return AppCard(
      scale: scale,
      radius: 14,
      isHighlighted: true,
      padding: EdgeInsets.all(16 * scale),
      child: compact
          ? Column(
              children: [
                Row(
                  children: [
                    thumb,
                    SizedBox(width: 14 * scale),
                    Expanded(child: info),
                  ],
                ),
                SizedBox(height: 14 * scale),
                SizedBox(width: double.infinity, child: resume),
              ],
            )
          : Row(
              children: [
                thumb,
                SizedBox(width: 16 * scale),
                Expanded(child: info),
                SizedBox(width: 12 * scale),
                resume,
              ],
            ),
    );
  }

  Widget _buildActionCard(
    double scale, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final iconBox = Container(
      width: 40 * scale,
      height: 40 * scale,
      decoration: BoxDecoration(
        color: uiTheme.accentWash,
        borderRadius: uiTheme.borderRadius(10 * scale),
      ),
      child: Icon(icon, color: uiTheme.accentColor, size: 22 * scale, weight: 300, opticalSize: 24),
    );
    final texts = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: 'Arial',
            color: uiTheme.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 13 * scale,
          ),
        ),
        SizedBox(height: 3 * scale),
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontFamily: 'Arial', color: uiTheme.textMuted, fontSize: 11 * scale),
        ),
      ],
    );
    // Телефон в альбомній: три картки в рядок завузькі для «значок + текст» поруч — значок ставимо зверху
    final bool stacked = AppPlatform.isMobile && !_compact;
    return AppCard(
      scale: scale,
      onTap: onTap,
      padding: EdgeInsets.all(16 * scale),
      child: stacked
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [iconBox, SizedBox(height: 12 * scale), texts],
            )
          : Row(
              children: [
                iconBox,
                SizedBox(width: 12 * scale),
                Expanded(child: texts),
              ],
            ),
    );
  }

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
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Arial',
                color: uiTheme.accentColor,
                fontSize: 12 * scale,
                fontWeight: FontWeight.w600,
              ),
            ),
            Icon(Symbols.chevron_right_rounded, color: uiTheme.accentColor, size: 16 * scale),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentRow(double scale, int idx, String path) {
    final title = AppFormatters.cleanMediaTitle(path);
    final posMs = StorageService.getPlaybackPosition(path);

    return Padding(
      padding: EdgeInsets.only(bottom: 8 * scale),
      child: AppCard(
        scale: scale,
        radius: 10,
        onTap: () => widget.onOpenFile(path),
        padding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 9 * scale),
        child: Row(
          children: [
            AppMediaThumbnail(
              uri: path,
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
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.72),
                        borderRadius: uiTheme.borderRadius(4 * scale),
                      ),
                      child: Text(
                        '#${idx + 1}',
                        style: TextStyle(
                          fontFamily: 'Arial',
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 9.5 * scale,
                        ),
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
                    style: TextStyle(
                      fontFamily: 'Arial',
                      color: uiTheme.textPrimary,
                      fontWeight: FontWeight.w500,
                      fontSize: 13 * scale,
                    ),
                  ),
                  SizedBox(height: 2 * scale),
                  Text(
                    posMs > 0 ? 'Зупинено на ${AppFormatters.formatTime(Duration(milliseconds: posMs))}' : 'З початку',
                    style: TextStyle(fontFamily: 'Arial', color: uiTheme.textMuted, fontSize: 11 * scale),
                  ),
                ],
              ),
            ),
            Icon(Symbols.play_arrow_rounded, color: uiTheme.accentColor, size: 20 * scale, weight: 300, opticalSize: 24),
          ],
        ),
      ),
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


  // ── Остання черга ──────────────────────────────────────────────────────────

  List<Widget> _buildLastQueueSection(double scale) {
    final q = StorageService.getLastQueue();
    if (q == null) return const [];
    final items = q['items'] as List<Map<String, String>>;
    final idx = q['index'] as int;
    if (items.length < 2) return const [];
    final cur = items[idx];
    final curTitle = (cur['title'] ?? '').isNotEmpty ? cur['title']! : AppFormatters.cleanMediaTitle(cur['uri']!);

    return [
      AppSectionHeader(scale: scale, title: 'Остання черга', subtitle: 'Відновіть чергу відтворення з того місця, де зупинились'),
      SizedBox(height: 10 * scale),
      _buildLastQueueCard(scale, items, idx, curTitle, cur['uri']!),
      SizedBox(height: 26 * scale),
    ];
  }

  Widget _buildLastQueueCard(double scale, List<Map<String, String>> items, int idx, String curTitle, String uri) {
    final bool compact = _compact;
    final thumb = _queueThumb(scale, uri, items.length, compact ? 104 : 112, compact ? 58.5 : 63);
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          curTitle,
          maxLines: compact ? 2 : 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontFamily: 'Arial', color: uiTheme.textPrimary, fontSize: 14 * scale, fontWeight: FontWeight.w600),
        ),
        SizedBox(height: 4 * scale),
        Text(
          'Серія ${idx + 1} з ${items.length}',
          style: TextStyle(fontFamily: 'Arial', color: uiTheme.textMuted, fontSize: 11.5 * scale),
        ),
      ],
    );
    final save = AppSecondaryButton(
      scale: scale,
      expand: compact,
      icon: Symbols.playlist_add_rounded,
      label: 'Зберегти',
      onTap: () => _saveQueueAsPlaylist(items),
    );
    final restore = AppAccentButton(
      scale: scale,
      expand: compact,
      icon: Symbols.play_arrow_rounded,
      label: 'Відновити',
      onTap: () => widget.onOpenQueue(items, idx),
    );

    return AppCard(
      scale: scale,
      radius: 14,
      padding: EdgeInsets.all(16 * scale),
      child: compact
          ? Column(
              children: [
                Row(
                  children: [
                    thumb,
                    SizedBox(width: 14 * scale),
                    Expanded(child: info),
                  ],
                ),
                SizedBox(height: 14 * scale),
                Row(
                  children: [
                    Expanded(child: save),
                    SizedBox(width: 10 * scale),
                    Expanded(child: restore),
                  ],
                ),
              ],
            )
          : Row(
              children: [
                thumb,
                SizedBox(width: 16 * scale),
                Expanded(child: info),
                SizedBox(width: 12 * scale),
                save,
                SizedBox(width: 8 * scale),
                restore,
              ],
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

  // ── Плейлисти ──────────────────────────────────────────────────────────────

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

  // ── Вкладка «Історія» ──────────────────────────────────────────────────────

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
