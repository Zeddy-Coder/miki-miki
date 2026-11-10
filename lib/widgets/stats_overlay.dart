import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:media_kit/media_kit.dart';
import '../models/media_models.dart';
import '../services/log_export.dart';
import '../services/sources/source_log.dart';
import '../services/ui_theme_service.dart';
import '../utils/formatters.dart';
import 'app_animation_kit.dart';
import 'app_ui_kit.dart';

class StatsOverlay extends StatefulWidget {
  final double scale;
  final Player player;
  final double currentSpeed;
  final double currentVolume;
  final PlaybackStats stats;
  final List<String> mpvLogs;
  final ScrollController logScrollController;
  final VoidCallback onClose;
  final VoidCallback onClearLogs;

  const StatsOverlay({
    super.key,
    required this.scale,
    required this.player,
    required this.currentSpeed,
    required this.currentVolume,
    required this.stats,
    required this.mpvLogs,
    required this.logScrollController,
    required this.onClose,
    required this.onClearLogs,
  });

  @override
  State<StatsOverlay> createState() => _StatsOverlayState();
}

class _StatsOverlayState extends State<StatsOverlay> {
  bool _copied = false;
  bool _saved = false;
  bool _saveFailed = false;
  int _tab = 0; // 0 — огляд, 1 — логи libmpv, 2 — журнал джерел перегляду
  final ScrollController _overviewScroll = AppSmoothScrollController();

  final ScrollController _sourceScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    SourceLog.instance.addListener(_onSourceLog);
  }

  void _onSourceLog() {
    if (!mounted) return;
    setState(() {});
    if (_tab == 2 && _sourceScroll.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _sourceScroll.hasClients) _sourceScroll.jumpTo(_sourceScroll.position.maxScrollExtent);
      });
    }
  }

  @override
  void dispose() {
    SourceLog.instance.removeListener(_onSourceLog);
    _sourceScroll.dispose();
    _overviewScroll.dispose();
    super.dispose();
  }

  /// Блок про відео, швидкість і синхронізацію (спільний для файлу й буфера обміну)
  String _videoBlock() {
    final vTrack = widget.player.state.tracks.video.firstOrNull;
    final aTrack = widget.player.state.track.audio;
    return '''
Файл: ${widget.player.state.playlist.medias.firstOrNull?.uri ?? "Невідомо"}

--- [ ВІДЕОПОТІК ТА РЕАЛЬНИЙ FPS ] ---
Відеокодек: ${vTrack?.codec ?? "HEVC / H.265 (10-bit)"}
Роздільна здатність: ${vTrack?.w ?? 3840}x${vTrack?.h ?? 1606}
Частота контейнера: ${widget.stats.containerFps.toStringAsFixed(3)} FPS
Очікуваний FPS: ${widget.stats.expectedFps.toStringAsFixed(2)} FPS
Фактичний рендер FPS: ${widget.stats.currentFps.toStringAsFixed(2)} FPS
Апаратний декодер: ${widget.stats.hwdecActive}
Швидкість: ${AppFormatters.formatSpeed(widget.currentSpeed)}
Гучність: ${widget.currentVolume.toInt()}%

--- [ ВТРАТИ КАДРІВ ТА СИНХРОНІЗАЦІЯ ] ---
Всього пропущено кадрів: ${widget.stats.totalDroppedFrames}
Пропущено відеовиходом (VO Drops): ${widget.stats.voDroppedFrames}
Пропущено декодером (Decoder Drops): ${widget.stats.decoderDroppedFrames}
Зсув A/V синхронізації: ${(widget.stats.avSyncDiff * 1000).toStringAsFixed(2)} ms
Аудіодоріжка: ${aTrack.title ?? aTrack.language ?? "Stereo/5.1"}
''';
  }

  void _copyDiagnosticsToClipboard() {
    final report = '''
======================================================
         YOUTUBE MOBILE FORK - ДІАГНОСТИЧНИЙ ЗВІТ
======================================================
Час звіту: ${DateTime.now().toIso8601String()}
${_videoBlock()}
--- [ ЖУРНАЛ ДЖЕРЕЛ ПЕРЕГЛЯДУ (${SourceLog.instance.lines.length} записів) ] ---
${SourceLog.instance.lines.join('\n')}

--- [ ЖИВІ ЛОГИ LIBMPV (${widget.mpvLogs.length} записів) ] ---
${widget.mpvLogs.join('\n')}
======================================================
''';

    Clipboard.setData(ClipboardData(text: report));
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  /// Зберігає повний звіт (журнал сесії + показники плеєра + логи libmpv) в окремий файл
  Future<void> _saveReportToFile() async {
    final result = await LogExport.save(extra: [
      ('ПОТОЧНИЙ СТАН ВІДТВОРЕННЯ', _videoBlock()),
      ('ЖИВІ ЛОГИ LIBMPV (${widget.mpvLogs.length} записів)', widget.mpvLogs.join('\n')),
    ]);
    if (!mounted || result.cancelled) return;
    setState(() {
      _saved = result.saved;
      _saveFailed = !result.saved;
    });
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _saved = false;
          _saveFailed = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.scale;

    return SizedBox.expand(
      child: GestureDetector(
        onTap: widget.onClose,
        child: Container(
          color: Colors.black.withValues(alpha: 0.75),
          alignment: Alignment.center,
          padding: EdgeInsets.all(24 * scale),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = math.min(860 * scale, constraints.maxWidth);
              final height = math.min(620 * scale, constraints.maxHeight);
              return GestureDetector(
                onTap: () {},
                child: AppModalShell(
                  scale: scale,
                  width: width,
                  height: height,
                  child: Row(
                    children: [
                      _buildSidebar(scale),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildHeader(scale),
                            Expanded(
                              child: AppFadeSwitcher(
                                expand: true,
                                child: KeyedSubtree(
                                  key: ValueKey('stats-tab-$_tab'),
                                  child: _tab == 0 ? _buildOverviewTab(scale) : (_tab == 1 ? _buildLogsTab(scale) : _buildSourcesTab(scale)),
                                ),
                              ),
                            ),
                            Padding(
                              padding: EdgeInsets.only(left: 24 * scale, right: 24 * scale, bottom: 16 * scale, top: 8 * scale),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  AppAccentButton(scale: scale, label: 'Закрити', onTap: widget.onClose),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildSidebar(double scale) {
    return AppSidebar(
      scale: scale,
      header: Row(
        children: [
          Icon(Symbols.query_stats_rounded, color: uiTheme.accentColor, size: 20 * scale),
          SizedBox(width: 8 * scale),
          Text(
            'Статистика',
            style: TextStyle(
              fontFamily: 'Arial',
              color: uiTheme.textPrimary,
              fontSize: 16 * scale,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
      children: [
        AppNavGroupLabel(scale: scale, text: 'ДІАГНОСТИКА'),
        AppNavItem(
          scale: scale,
          icon: Symbols.query_stats_rounded,
          label: 'Огляд',
          isSelected: _tab == 0,
          onTap: () => setState(() => _tab = 0),
        ),
        AppNavItem(
          scale: scale,
          icon: Symbols.terminal_rounded,
          label: 'Логи libmpv',
          isSelected: _tab == 1,
          trailing: widget.mpvLogs.isEmpty ? null : '${widget.mpvLogs.length}',
          onTap: () => setState(() => _tab = 1),
        ),
        AppNavItem(
          scale: scale,
          icon: Symbols.travel_explore_rounded,
          label: 'Джерела',
          isSelected: _tab == 2,
          trailing: SourceLog.instance.lines.isEmpty ? null : '${SourceLog.instance.lines.length}',
          onTap: () => setState(() => _tab = 2),
        ),
      ],
      footer: Padding(
        padding: EdgeInsets.only(left: 8 * scale),
        child: Text(
          'Stats for Nerds',
          style: TextStyle(fontFamily: 'Arial', color: uiTheme.textDarkMuted, fontSize: 11 * scale),
        ),
      ),
    );
  }

  Widget _buildHeader(double scale) {
    return AppPaneHeader(
      scale: scale,
      title: _tab == 0 ? 'Огляд відтворення' : (_tab == 1 ? 'Логи libmpv' : 'Журнал джерел'),
      subtitle: _tab == 0
          ? 'Кодек, FPS, пропущені кадри та синхронізація'
          : (_tab == 1 ? 'Записів: ${widget.mpvLogs.length}' : 'Запити, плеєри Moon/Ashdi, помилки · записів: ${SourceLog.instance.lines.length}'),
      actions: [
        AppSecondaryButton(
          scale: scale,
          expand: false,
          isSuccess: _saved,
          icon: _saved ? Symbols.check_rounded : Symbols.download_rounded,
          label: _saved ? 'Збережено!' : (_saveFailed ? 'Помилка збереження' : 'Зберегти у файл'),
          onTap: _saveReportToFile,
        ),
        IconButton(
          tooltip: _copied ? 'Скопійовано!' : 'Копіювати звіт у буфер',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          icon: Icon(_copied ? Symbols.check_rounded : Symbols.content_copy_rounded, color: uiTheme.textMuted, size: 20 * scale),
          onPressed: _copyDiagnosticsToClipboard,
        ),
        if (_tab >= 1)
          IconButton(
            tooltip: 'Очистити логи',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: Icon(Symbols.delete_outline_rounded, color: uiTheme.textMuted, size: 20 * scale),
            onPressed: _tab == 1 ? widget.onClearLogs : SourceLog.clear,
          ),
        IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          icon: Icon(Symbols.close_rounded, color: uiTheme.textDarkMuted, size: 20 * scale),
          onPressed: widget.onClose,
        ),
      ],
    );
  }

  // ── Вкладка «Огляд» ────────────────────────────────────────────────────────

  Widget _buildOverviewTab(double scale) {
    final stats = widget.stats;
    final vTrack = widget.player.state.tracks.video.firstOrNull;
    final aTrack = widget.player.state.track.audio;
    final bool hasDrops = stats.totalDroppedFrames > 0;

    final resolution = (vTrack?.w != null && vTrack?.h != null) ? '${vTrack!.w}×${vTrack.h}' : '—';

    return AppScrollbar(
      scale: scale,
      controller: _overviewScroll,
      child: SingleChildScrollView(
        controller: _overviewScroll,
        padding: EdgeInsets.fromLTRB(24 * scale, 4 * scale, 24 * scale, 12 * scale),
        child: LayoutBuilder(
          builder: (context, c) {
            final gap = 10 * scale;
            final tileWidth = (c.maxWidth - gap) / 2;

            Widget section(String title, String subtitle, List<Widget> tiles, {bool last = false}) {
              return Padding(
                padding: EdgeInsets.only(bottom: last ? 0 : 22 * scale),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppSectionHeader(scale: scale, title: title, subtitle: subtitle),
                    SizedBox(height: 10 * scale),
                    Wrap(
                      spacing: gap,
                      runSpacing: gap,
                      children: [for (final t in tiles) SizedBox(width: tileWidth, child: t)],
                    ),
                  ],
                ),
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                section('Відеопотік', 'Що закодовано у файлі', [
                  AppStatTile(scale: scale, icon: Symbols.movie_rounded, label: 'Кодек', value: vTrack?.codec ?? '—'),
                  AppStatTile(scale: scale, icon: Symbols.aspect_ratio_rounded, label: 'Роздільна здатність', value: resolution),
                  AppStatTile(scale: scale, icon: Symbols.slow_motion_video_rounded, label: 'Частота контейнера', value: '${stats.containerFps.toStringAsFixed(3)} FPS'),
                  AppStatTile(scale: scale, icon: Symbols.target_rounded, label: 'Очікуваний FPS', value: '${stats.expectedFps.toStringAsFixed(2)} FPS'),
                ]),
                section('Відтворення', 'Поточний стан плеєра', [
                  AppStatTile(scale: scale, icon: Symbols.speed_rounded, label: 'Фактичний FPS', value: '${stats.currentFps.toStringAsFixed(1)} FPS'),
                  AppStatTile(scale: scale, icon: Symbols.fast_forward_rounded, label: 'Швидкість', value: AppFormatters.formatSpeed(widget.currentSpeed)),
                  AppStatTile(scale: scale, icon: Symbols.volume_up_rounded, label: 'Гучність', value: '${widget.currentVolume.toInt()}%'),
                  AppStatTile(scale: scale, icon: Symbols.music_note_rounded, label: 'Аудіодоріжка', value: aTrack.title ?? aTrack.language ?? '—'),
                ]),
                section('Кадри та синхронізація', 'Втрати кадрів і розсинхрон аудіо/відео', [
                  AppStatTile(scale: scale, icon: Symbols.running_with_errors_rounded, label: 'Пропущено всього', value: '${stats.totalDroppedFrames}', isWarning: hasDrops),
                  AppStatTile(scale: scale, icon: Symbols.developer_board_rounded, label: 'Декодер', value: '${stats.hwdecActive}'),
                  AppStatTile(scale: scale, icon: Symbols.monitor_rounded, label: 'Пропущено відеовиходом (VO)', value: '${stats.voDroppedFrames}', isWarning: stats.voDroppedFrames > 0),
                  AppStatTile(scale: scale, icon: Symbols.memory_rounded, label: 'Пропущено декодером', value: '${stats.decoderDroppedFrames}', isWarning: stats.decoderDroppedFrames > 0),
                  AppStatTile(scale: scale, icon: Symbols.sync_rounded, label: 'Зсув A/V', value: '${(stats.avSyncDiff * 1000).toStringAsFixed(1)} ms'),
                ], last: true),
              ],
            );
          },
        ),
      ),
    );
  }

  // ── Вкладки «Логи» (libmpv) і «Джерела» ────────────────────────────────────

  Widget _buildSourcesTab(double scale) => _buildLogsTab(scale, lines: SourceLog.instance.lines, controller: _sourceScroll, empty: 'Журнал порожній — відкрийте серію з «Дивитись»');

  Widget _buildLogsTab(double scale, {List<String>? lines, ScrollController? controller, String empty = 'Логи порожні...'}) {
    final logs = lines ?? widget.mpvLogs;
    final ctrl = controller ?? widget.logScrollController;
    return Padding(
      padding: EdgeInsets.fromLTRB(24 * scale, 4 * scale, 24 * scale, 12 * scale),
      child: Container(
        decoration: BoxDecoration(
          // Термінал лишається темним в обох темах: кольори логів підібрані під темний фон
          color: const Color(0xFF0D0D0D),
          borderRadius: uiTheme.borderRadius(10 * scale),
          border: Border.all(color: uiTheme.colors.borderSubtle),
        ),
        child: logs.isEmpty
            ? Center(
                child: Text(
                  empty,
                  style: TextStyle(fontFamily: 'Consolas', color: const Color(0xFF888888), fontSize: 11.5 * scale),
                ),
              )
            : AppScrollbar(
                scale: scale,
                controller: ctrl,
                child: ListView.builder(
                  controller: ctrl,
                  physics: const ClampingScrollPhysics(),
                  padding: EdgeInsets.all(10 * scale),
                  itemCount: logs.length,
                  itemBuilder: (context, index) {
                    final logLine = logs[index];
                    Color logColor = const Color(0xFF00FF66);
                    if (logLine.contains('error') || logLine.contains('Failed') || logLine.contains('✗') || logLine.contains('ПОМИЛКА') || logLine.contains('Збій') || logLine.contains('збій') || logLine.contains('помилка')) {
                      logColor = const Color(0xFFFF4D4D);
                    } else if (logLine.contains('warn')) {
                      logColor = const Color(0xFFFFCC00);
                    }
                    return Padding(
                      padding: EdgeInsets.symmetric(vertical: 1.5 * scale),
                      child: Text(
                        logLine,
                        style: TextStyle(fontFamily: 'Consolas', color: logColor, fontSize: 11 * scale),
                      ),
                    );
                  },
                ),
              ),
      ),
    );
  }
}
