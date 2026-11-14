import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../services/episode_check.dart';
import '../services/remote_driver.dart';
import '../services/ui_theme_service.dart';
import '../services/watch_models.dart';
import 'app_animation_kit.dart';
import 'app_ui_kit.dart';
import 'watch_callout.dart';

enum _RemoteTab { episodes, voices, player }

/// Вміст бічної панелі / шторки для серій із сайтів: список серій із позначками «переглянуто»,
/// вибір озвучки чи субтитрів, плеєра (Moon, Ashdi …) і якості. Усе перемикається на льоту, з того ж місця.
/// Черга файлів тут не редагується (це не файли), тому кнопок «додати / видалити / впорядкувати» немає.
class RemotePanelBody extends StatefulWidget {
  final double scale;
  final RemoteDriver driver;

  /// Телефон: вищі рядки під дотик
  final bool sheet;
  final ValueChanged<int> onEpisodeSelected;

  const RemotePanelBody({
    super.key,
    required this.scale,
    required this.driver,
    required this.onEpisodeSelected,
    this.sheet = false,
  });

  @override
  State<RemotePanelBody> createState() => _RemotePanelBodyState();
}

class _RemotePanelBodyState extends State<RemotePanelBody> {
  final ScrollController _scroll = AppSmoothScrollController();
  _RemoteTab _tab = _RemoteTab.episodes;
  int _shownIndex = -1;

  double get _rowH => (widget.sheet ? 56 : 52) * widget.scale;
  double get _extent => _rowH + 4 * widget.scale;

  @override
  void initState() {
    super.initState();
    _scrollToCurrent();
  }

  @override
  void didUpdateWidget(RemotePanelBody old) {
    super.didUpdateWidget(old);
    if (_tab == _RemoteTab.episodes && widget.driver.index != _shownIndex) _scrollToCurrent(animate: true);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Поточна серія — на 30% висоти списку, як у черзі файлів
  void _scrollToCurrent({bool animate = false}) {
    _shownIndex = widget.driver.index;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients || _tab != _RemoteTab.episodes) return;
      final pos = _scroll.position;
      final target = (_shownIndex * _extent - pos.viewportDimension * 0.3).clamp(0.0, pos.maxScrollExtent);
      if (animate) {
        _scroll.animateTo(target, duration: AppAnim.medium, curve: AppAnim.easeOut);
      } else {
        _scroll.jumpTo(target);
      }
    });
  }

  void _selectTab(_RemoteTab t) {
    if (t == _tab) return;
    setState(() => _tab = t);
    if (t == _RemoteTab.episodes) _scrollToCurrent();
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.scale;
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(8 * scale, 0, 8 * scale, 6 * scale),
          child: AppSegmentedBar<_RemoteTab>(
            scale: scale,
            selectedValue: _tab,
            onSelected: _selectTab,
            options: const [
              AppSegmentOption(value: _RemoteTab.episodes, label: 'Серії'),
              AppSegmentOption(value: _RemoteTab.voices, label: 'Озвучка'),
              AppSegmentOption(value: _RemoteTab.player, label: 'Плеєр'),
            ],
          ),
        ),
        _caption(scale),
        Expanded(child: KeyedSubtree(key: ValueKey(_tab), child: _content(scale))),
      ],
    );
  }

  /// Що зараз грає: «Озвучення: Amanogawa · Moon · 1080p»
  Widget _caption(double scale) {
    final d = widget.driver;
    final g = d.group;
    final parts = <String>[
      if (g != null) g.fullLabel,
      if (d.hoster.isNotEmpty) d.hoster,
      if ((d.video?.title ?? '').isNotEmpty) d.video!.title,
    ];
    if (parts.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.fromLTRB(14 * scale, 0, 14 * scale, 6 * scale),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          parts.join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontFamily: 'Arial', color: uiTheme.textDarkMuted, fontSize: 11.5 * scale),
        ),
      ),
    );
  }

  Widget _content(double scale) {
    switch (_tab) {
      case _RemoteTab.episodes:
        return _episodes(scale);
      case _RemoteTab.voices:
        return _voices(scale);
      case _RemoteTab.player:
        return _player(scale);
    }
  }

  /// Тонкий скролбар у стилі решти панелей
  Widget _scrollArea(double scale, Widget child) {
    return ScrollConfiguration(
      behavior: const AppScrollBehavior().copyWith(scrollbars: false),
      child: KeyedSubtree(
        child: child,
      ),
    );
  }

  // ── Серії ───────────────────────────────────────────────────────────────────

  static String _num(RemoteEntry e, int i) => episodeLabel(e.episode, i);

  Widget _episodes(double scale) {
    final d = widget.driver;
    final s = d.session;
    if (s == null || s.entries.isEmpty) {
      return AppEmptyState(scale: scale, icon: Symbols.video_library_rounded, text: 'Серій немає');
    }
    final seen = d.store.watched(s.animeKey);
    final cur = d.index;
    return _scrollArea(
      scale,
      ListView.builder(
        controller: _scroll,
        itemExtent: _extent,
        padding: EdgeInsets.only(left: 8 * scale, right: 8 * scale, bottom: 8 * scale),
        itemCount: s.entries.length,
        itemBuilder: (context, i) {
          final e = s.entries[i];
          final bool isCur = i == cur;
          final bool watched = seen.contains(e.epKey);
          final Color titleColor = isCur ? uiTheme.accentColor : (watched ? uiTheme.textMuted : uiTheme.textPrimary);
          return AppSelectableSurface(
            scale: scale,
            isSelected: isCur,
            height: _rowH,
            padding: EdgeInsets.symmetric(horizontal: 10 * scale),
            onTap: () => widget.onEpisodeSelected(i),
            onLongPress: () => widget.driver.toggleWatched(i),
            child: Row(
              children: [
                Container(
                  width: 38 * scale,
                  height: 28 * scale,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isCur ? uiTheme.accentColor : uiTheme.bgElevated,
                    borderRadius: uiTheme.borderRadius(6 * scale),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      _num(e, i),
                      maxLines: 1,
                      style: TextStyle(
                        fontFamily: 'Arial',
                        color: isCur ? uiTheme.onAccent : uiTheme.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 12 * scale,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 10 * scale),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        e.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Arial',
                          color: titleColor,
                          fontWeight: isCur ? FontWeight.w600 : FontWeight.w500,
                          fontSize: 13 * scale,
                        ),
                      ),
                      if (isCur || watched) ...[
                        SizedBox(height: 2 * scale),
                        Text(
                          isCur ? _currentLabel(d) : 'Переглянуто',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Arial',
                            color: isCur ? uiTheme.accentColor.withValues(alpha: 0.85) : uiTheme.textDarkMuted,
                            fontSize: 11 * scale,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                SizedBox(width: 6 * scale),
                if (isCur)
                  Icon(Symbols.equalizer_rounded, color: uiTheme.accentColor, size: 20 * scale, weight: 300, opticalSize: 24)
                else if (watched)
                  Icon(Symbols.check_circle_rounded, color: uiTheme.textDarkMuted, size: 19 * scale, fill: 1, weight: 300, opticalSize: 24),
              ],
            ),
          );
        },
      ),
    );
  }

  static String _currentLabel(RemoteDriver d) {
    switch (d.phase) {
      case RemotePhase.resolving:
        return 'Шукаю відео…';
      case RemotePhase.opening:
        return 'Запускаю…';
      case RemotePhase.failed:
        return 'Не вдалося запустити';
      case RemotePhase.playing:
      case RemotePhase.idle:
        return 'Зараз відтворюється';
    }
  }

  // ── Озвучки й субтитри ──────────────────────────────────────────────────────

  Widget _voices(double scale) {
    final d = widget.driver;
    final groups = d.title?.groups ?? const <WatchGroup>[];
    if (groups.isEmpty) {
      return AppEmptyState(scale: scale, icon: Symbols.record_voice_over_rounded, text: 'Інших озвучок для цього аніме немає');
    }
    // Поточний варіант з розбіжністю серій відносно Hikka: пояснення над списком (відмітки з ним не синхронізуватимуться)
    EpisodeCheck? currentCheck;
    for (final g in groups) {
      if (g.id == d.groupId) currentCheck = d.checkOf(g);
    }
    final note = currentCheck != null && currentCheck.hasNote ? currentCheck : null;
    final lead = note == null ? 1 : 2; // заголовок, за ним (за потреби) пояснення
    return _scrollArea(
      scale,
      ListView.builder(
        controller: _scroll,
        padding: EdgeInsets.only(left: 8 * scale, right: 8 * scale, bottom: 8 * scale),
        itemCount: groups.length + lead,
        itemBuilder: (context, i) {
          if (i == 0) {
            return Padding(
              padding: EdgeInsets.fromLTRB(6 * scale, 4 * scale, 6 * scale, 8 * scale),
              child: AppSectionHeader(scale: scale, title: 'Озвучка', subtitle: 'Перемикається з того ж місця. Вибір запамʼятовується'),
            );
          }
          if (note != null && i == 1) {
            return Padding(
              padding: EdgeInsets.fromLTRB(2 * scale, 0, 2 * scale, 10 * scale),
              child: EpisodeNote(scale: scale, check: note, compact: true),
            );
          }
          final g = groups[i - lead];
          final source = d.registry.byId(g.sourceId)?.name ?? g.sourceId;
          final check = d.checkOf(g);
          return AppSelectableTile(
            scale: scale,
            title: g.label,
            subtitle: '${g.kindLabel} · ${g.coverage} сер. · $source',
            icon: g.isSub ? Symbols.subtitles_rounded : Symbols.record_voice_over_rounded,
            isSelected: g.id == d.groupId,
            trailing: episodeCheckWarns(check) ? Icon(Symbols.warning_rounded, color: watchWarnColor(), size: 18 * scale, fill: 1, weight: 400) : null,
            onTap: () => d.switchGroup(g),
          );
        },
      ),
    );
  }

  // ── Плеєр і якість ──────────────────────────────────────────────────────────

  Widget _player(double scale) {
    final d = widget.driver;
    final res = d.stream;
    if (res == null) {
      return AppEmptyState(
        scale: scale,
        icon: Symbols.hourglass_top_rounded,
        text: d.phase == RemotePhase.failed ? 'Плеєри не знайдено. Спробуйте іншу озвучку.' : 'Список зʼявиться, коли серія завантажиться',
      );
    }
    final cur = d.video?.url;
    return _scrollArea(
      scale,
      ListView(
        controller: _scroll,
        padding: EdgeInsets.only(left: 8 * scale, right: 8 * scale, bottom: 8 * scale),
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(6 * scale, 4 * scale, 6 * scale, 8 * scale),
            child: AppSectionHeader(scale: scale, title: 'Плеєр', subtitle: 'Якщо один не працює, спробуйте інший'),
          ),
          for (final h in res.hosters)
            AppSelectableTile(
              scale: scale,
              title: h,
              icon: Symbols.smart_display_rounded,
              isSelected: h.toLowerCase() == res.hoster.toLowerCase(),
              onTap: () => d.switchHoster(h),
            ),
          if (res.qualities.length > 1) ...[
            Padding(
              padding: EdgeInsets.fromLTRB(6 * scale, 14 * scale, 6 * scale, 8 * scale),
              child: AppSectionHeader(scale: scale, title: 'Якість'),
            ),
            for (final v in res.qualities)
              AppSelectableTile(
                scale: scale,
                title: v.title.isNotEmpty ? v.title : (v.resolution != null ? '${v.resolution}p' : 'Авто'),
                icon: Symbols.high_quality_rounded,
                isSelected: v.url == cur,
                onTap: () => d.switchQuality(v),
              ),
          ],
        ],
      ),
    );
  }
}
