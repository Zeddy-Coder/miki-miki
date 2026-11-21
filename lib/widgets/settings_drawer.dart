import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import '../constants/app_constants.dart';
import '../models/media_models.dart';
import '../models/source_models.dart';
import '../services/anime4k_controller.dart';
import '../services/anime4k_service.dart';
import '../services/remote_driver.dart';
import '../services/app_log.dart';
import '../services/hikka_nav.dart';
import '../services/playback_clock.dart';
import '../services/skips/skip_align.dart';
import '../services/songs/song_service.dart';
import '../services/songs/theme_songs.dart';
import '../services/storage_service.dart';
import '../services/ui_theme_service.dart';
import '../utils/formatters.dart';
import '../utils/platform_info.dart';
import 'app_animation_kit.dart';
import 'app_tones.dart';
import 'app_ui_kit.dart';
import 'design_kit.dart';
import 'line_icons.dart';
import 'player_kit.dart';
import 'song_card.dart';

class SettingsDrawer extends StatelessWidget {
  final double scale;
  final double screenWidth;
  final double drawerAnchorPixelX;
  final bool drawerIsTop;

  /// Phone: only the header and the list, without a surface of their own or a button anchor:
  /// the background, position and scrim come from [MobileSheetFrame]
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

  /// "Додати файл субтитрів…" in the subtitle menu (without it there is no item)
  final VoidCallback? onAddSubtitleFile;
  final ValueChanged<AudioTrack> onAudioSelected;
  final ValueChanged<String> onHwdecSelected;
  final VoidCallback onOpenChaptersSidePanel;
  final VoidCallback onOpenStats;
  final Anime4kController anime4k;

  /// Work key for saving the audio delay (empty means do not save)
  final String audioDelayKey;

  /// Site episodes: with several quality variants the menu starts with "Якість" (switched from the same place)
  final RemoteDriver? remote;

  /// "Усі налаштування" under "Більше": the app settings over the player (null: no row)
  final VoidCallback? onOpenAppSettings;

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
    this.remote,
    this.onOpenAppSettings,
  });

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

  /// The quality variants of the current site episode ("Авто", "1080p" …); empty for files
  List<Video> get _qualities => remote != null && remote!.active ? (remote!.stream?.qualities ?? const <Video>[]) : const <Video>[];

  static String qualityLabel(Video v) => v.title.isNotEmpty ? v.title : (v.resolution != null ? '${v.resolution}p' : 'Авто');

  String get _currentQuality {
    final url = remote?.video?.url;
    for (final v in _qualities) {
      if (v.url == url) return qualityLabel(v);
    }
    return remote?.video == null ? '' : qualityLabel(remote!.video!);
  }

  @override
  Widget build(BuildContext context) {
    final currentSub = player.state.track.subtitle;
    final bool isSubDisabled = currentSub.id == 'no' ||
        (currentSub.id.isEmpty && currentSub.id != 'auto') ||
        subtitleTracks.isEmpty;
    final currentAud = player.state.track.audio;

    if (sheet) return _buildSheet(context, isSubDisabled, currentSub, currentAud);

    // A PC: one dark tile like the app's drop-down menus, under (or over) its button
    final double drawerWidth = 390.0 * scale;
    final double calculatedLeft = (drawerAnchorPixelX - (drawerWidth / 2))
        .clamp(35.0 * scale, screenWidth - drawerWidth - 35.0 * scale);
    final radius = uiTheme.borderRadius(14 * scale);

    return Stack(children: [Positioned(
      bottom: drawerIsTop ? null : 95.0 * scale,
      top: drawerIsTop ? 65.0 * scale : null,
      left: calculatedLeft,
      child: DecoratedBox(
        key: const ValueKey('player-menu'),
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: uiTheme.isLight ? 0.16 : 0.42), blurRadius: 36 * scale, offset: Offset(0, 10 * scale))],
        ),
        child: Material(
          color: AppTones.menu,
          shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: AppTones.menuLine)),
          clipBehavior: Clip.antiAlias,
          child: Container(
            width: drawerWidth,
            constraints: BoxConstraints(maxHeight: 440 * scale),
            child: AppAnimatedSize(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(height: 6 * scale),
                  _menuCaption(),
                  Flexible(
                    child: ScrollConfiguration(
                      behavior: const AppScrollBehavior().copyWith(scrollbars: false),
                      child: SingleChildScrollView(
                        controller: scrollController,
                        padding: EdgeInsets.only(bottom: 6 * scale),
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
                ],
              ),
            ),
          ),
        ),
      ),
    )]);
  }

  /// The grey caption of the tile: what the menu is about; on an inner page it leads back ("‹ Швидкість відтворення")
  Widget _menuCaption() {
    final s = scale;
    final text = Text(_getDrawerTitle(), maxLines: 1, overflow: TextOverflow.ellipsis, style: playerText(12 * s, color: AppTones.caption, weight: FontWeight.w700));
    if (activeDrawerPrev == null) {
      return Padding(padding: EdgeInsets.fromLTRB(16 * s, 8 * s, 16 * s, 4 * s), child: text);
    }
    return Semantics(
      button: true,
      label: 'Назад',
      child: InkWell(
        key: const ValueKey('menu-back'),
        onTap: onBack,
        splashColor: Colors.transparent,
        highlightColor: uiTheme.touchHighlight,
        hoverColor: uiTheme.hoverOverlay,
        child: Padding(
          padding: EdgeInsets.fromLTRB(12 * s, 6 * s, 16 * s, 4 * s),
          child: Row(
            children: [
              LineIconView(LineIcon.back, size: 16 * s, color: AppTones.caption, stroke: 1.8),
              SizedBox(width: 8 * s),
              Flexible(child: text),
            ],
          ),
        ),
      ),
    );
  }

  /// Phone: a header (back / title / close, buttons ≥ 48 dp) and a list scrolled by finger
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
                Padding(padding: const EdgeInsets.only(left: 6), child: _sheetButton(LineIcon.back, onBack, 'Назад'))
              else
                const SizedBox(width: 20),
              Expanded(
                child: Text(
                  _getDrawerTitle(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: playerText(18, weight: FontWeight.w700),
                ),
              ),
              _sheetButton(LineIcon.close, onClose, 'Закрити'),
              const SizedBox(width: 6),
            ],
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            controller: scrollController,
            padding: EdgeInsets.only(bottom: 10 * scale),
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

  /// A round 48×48 dp button with a visible touch reaction
  Widget _sheetButton(LineIcon icon, VoidCallback onTap, String label) {
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
            child: Center(child: LineIconView(icon, size: icon == LineIcon.close ? 21 : 23, color: uiTheme.textSecondary)),
          ),
        ),
      ),
    );
  }

  String _getDrawerTitle() {
    switch (activeDrawer) {
      case 'speed': return 'Швидкість відтворення';
      case 'quality': return 'Якість';
      case 'advanced': return 'Більше';
      case 'hwdec': return 'Апаратний декодер';
      case 'chapters': return 'Розділи';
      case 'anime4k': return 'Anime4K';
      case 'subs': return 'Субтитри';
      case 'audio': return 'Звук';
      case 'song-op': case 'song-ed': return 'Пісня';
      default: return 'Налаштування';
    }
  }

  // ── Rows ───────────────────────────────────────────────────────────────────

  /// A row of the menu: a line icon, the title (on a phone a long value goes under it in grey), the value, a chevron
  Widget _row({
    required String id,
    required LineIcon icon,
    required String title,
    String? value,
    bool long = false,
    bool chevron = true,
    bool active = false,
    VoidCallback? onTap,
  }) =>
      PlayerMenuRow(
        key: ValueKey('menu-$id'),
        scale: scale,
        sheet: sheet,
        icon: icon,
        title: title,
        sub: long && sheet ? value : null,
        value: long && sheet ? null : value,
        chevron: chevron,
        active: active,
        onTap: onTap,
      );

  /// A choice inside a page: the label, maybe a grey line, the accent check mark on the chosen one
  Widget _choice({
    required String id,
    required String label,
    String? subtitle,
    required bool selected,
    required VoidCallback onTap,
    Widget? trailing,
    Widget? leading,
  }) =>
      AppCheckRow(
        key: ValueKey('choice-$id'),
        scale: scale,
        label: label,
        subtitle: subtitle,
        selected: selected,
        onTap: onTap,
        trailing: trailing,
        leading: leading,
        padH: sheet ? 20 : 16,
        minHeight: sheet ? 52 : 42,
      );

  Widget _divider() => Container(height: 1, margin: EdgeInsets.symmetric(vertical: 6 * scale), color: AppTones.menuLine);

  /// A grey note under a list (Anime4K skipped, an error, what the audio delay does)
  Widget _note(String text, {bool isError = false}) {
    return Padding(
      padding: EdgeInsets.fromLTRB((sheet ? 20 : 16) * scale, 6 * scale, (sheet ? 20 : 16) * scale, 4 * scale),
      child: Text(
        text,
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
        style: playerText(12 * scale, color: isError ? const Color(0xFFE5484D) : AppTones.rowSub, height: 1.35),
      ),
    );
  }

  List<Widget> _buildContent(
    BuildContext context,
    double scale,
    bool isSubDisabled,
    SubtitleTrack currentSub,
    AudioTrack currentAud,
  ) {
    if (activeDrawer == 'song-op' || activeDrawer == 'song-ed') return _songPage(activeDrawer == 'song-ed' ? SongKind.ed : SongKind.op);

    if (activeDrawer == 'speed') {
      return [
        for (final s in AppConstants.speeds)
          _choice(
            id: 'speed-$s',
            label: s == 1.0 ? '1× · звичайна' : AppFormatters.formatSpeed(s),
            selected: (currentSpeed - s).abs() < 0.05,
            onTap: () => onSpeedSelected(s),
          ),
      ];
    }

    if (activeDrawer == 'quality') {
      final url = remote?.video?.url;
      return [
        for (final v in _qualities)
          _choice(
            id: 'quality-${qualityLabel(v)}',
            label: qualityLabel(v),
            selected: v.url == url,
            onTap: () {
              remote?.switchQuality(v);
              onClose();
            },
          ),
      ];
    }

    if (activeDrawer == 'advanced') {
      return [
        _row(
          id: 'hwdec',
          icon: LineIcon.chip,
          title: 'Апаратний декодер',
          value: AppConstants.hwdecShortNames[currentHwdec] ?? 'NVDEC',
          onTap: () => onOpenSubDrawer('hwdec'),
        ),
        _row(id: 'stats', icon: LineIcon.chart, title: 'Статистика відтворення', chevron: false, onTap: onOpenStats),
        if (onOpenAppSettings != null) _row(id: 'app-settings', icon: LineIcon.gear, title: 'Усі налаштування', onTap: onOpenAppSettings),
      ];
    }

    if (activeDrawer == 'hwdec') {
      return [
        for (final entry in AppConstants.hwdecOptions.entries)
          _choice(id: 'hwdec-${entry.key}', label: entry.value, selected: currentHwdec == entry.key, onTap: () => onHwdecSelected(entry.key)),
      ];
    }

    if (activeDrawer == 'anime4k') return _buildAnime4kPage(scale);

    if (activeDrawer == 'chapters') {
      final curPos = player.state.position;
      final songs = remote?.songs?.current.value;
      return [
        for (final (idx, ch) in chapters.indexed)
          () {
            final current = curPos >= ch.startTime && curPos < ((idx + 1 < chapters.length) ? chapters[idx + 1].startTime : player.state.duration);
            final kind = ChapterMath.songKindOf(ch);
            final song = kind == null ? null : songs?.of(kind);
            final time = Text(
              AppFormatters.formatTime(ch.startTime),
              style: playerText(13 * scale, color: AppTones.rowSub, features: const [FontFeature.tabularFigures()]),
            );
            return _choice(
              id: 'chapter-$idx',
              label: AppFormatters.translateChapterTitle(ch.title),
              subtitle: song == null ? null : [song.title, if (song.artists.isNotEmpty) song.artist].join(' · '),
              selected: current,
              // The song's cover in front: the rows of songs stand out, the times stay in one column
              leading: song == null
                  ? null
                  : Semantics(
                      button: true,
                      label: 'Пісня: ${song.title}',
                      child: GestureDetector(
                        key: ValueKey('chapter-song-${kind!.name}'),
                        onTap: () => onOpenSubDrawer('song-${kind.name}'),
                        child: SongCover(
                          url: songs!.art[kind]?.cover,
                          size: (sheet ? 44 : 36) * scale,
                          equalizer: current,
                          playing: PlaybackClock.of(player).playing,
                        ),
                      ),
                    ),
              trailing: time,
              onTap: () {
                player.seek(ch.startTime);
                onClose();
              },
            );
          }(),
        ..._skipControls(),
      ];
    }

    if (activeDrawer == 'subs') {
      return [
        _choice(id: 'subs-off', label: 'Вимкнено', selected: isSubDisabled, onTap: () => onSubtitleSelected(SubtitleTrack.no())),
        for (final cached in subtitleTracks)
          _choice(
            id: 'subs-${cached.track.id}',
            label: cached.formattedTitle,
            subtitle: cached.formattedTitle.toLowerCase().contains('sdh') || (cached.track.title?.toLowerCase().contains('sdh') ?? false)
                ? 'Для людей з порушеннями слуху'
                : null,
            selected: !isSubDisabled &&
                (currentSub.id == cached.track.id ||
                    (currentSub.id == 'auto' && subtitleTracks.first.track.id == cached.track.id) ||
                    (currentSub.id.isEmpty && subtitleTracks.first.track.id == cached.track.id)),
            onTap: () => onSubtitleSelected(cached.track),
          ),
        if (onAddSubtitleFile != null) ...[
          _divider(),
          _row(id: 'subs-file', icon: LineIcon.plus, title: 'Додати файл субтитрів…', chevron: false, onTap: onAddSubtitleFile),
        ],
      ];
    }

    if (activeDrawer == 'audio') {
      return [
        for (final cached in audioTracks)
          _choice(
            id: 'audio-${cached.track.id}',
            label: cached.formattedTitle,
            selected: (currentAud.id == cached.track.id) ||
                (currentAud.id == 'auto' && audioTracks.first.track.id == cached.track.id) ||
                (currentAud.id.isEmpty && audioTracks.first.track.id == cached.track.id) ||
                (audioTracks.length == 1),
            onTap: () => onAudioSelected(cached.track),
          ),
        if (audioTracks.isEmpty) _note('Аудіодоріжок немає'),
        _divider(),
        _AudioDelayRow(scale: scale, sheet: sheet, player: player, storeKey: audioDelayKey),
        _note('Зсуває звук відносно картинки: мінус — раніше, плюс — пізніше. Зберігається для цього твору.'),
      ];
    }

    // The main page: what is switched most often, then the rest under "Більше"
    final qualities = _qualities;
    final delay = audioDelayKey.isEmpty ? 0 : StorageService.getAudioDelay(audioDelayKey);
    return [
      if (qualities.length > 1)
        _row(id: 'quality', icon: LineIcon.hd, title: 'Якість', value: _currentQuality, onTap: () => onOpenSubDrawer('quality')),
      _row(id: 'speed', icon: LineIcon.speed, title: 'Швидкість', value: AppFormatters.formatSpeed(currentSpeed), onTap: () => onOpenSubDrawer('speed')),
      _row(id: 'subs', icon: LineIcon.subtitles, title: 'Субтитри', value: _getCurrentSubtitleLabel(), long: true, onTap: () => onOpenSubDrawer('subs')),
      _row(
        id: 'audio',
        icon: LineIcon.musicNote,
        title: 'Звук',
        value: [_getCurrentAudioLabel(), if (delay != 0) 'затримка ${_AudioDelayRowState.format(delay)}'].join(' · '),
        long: true,
        onTap: () => onOpenSubDrawer('audio'),
      ),
      _row(
        id: 'chapters',
        icon: LineIcon.chapters,
        title: 'Розділи',
        value: chapters.isEmpty ? 'Немає' : '${chapters.length}',
        chevron: chapters.isNotEmpty,
        onTap: chapters.isEmpty ? null : () => onOpenSubDrawer('chapters'),
      ),
      _row(id: 'anime4k', icon: LineIcon.sparkle, title: 'Anime4K', value: anime4k.summary, active: anime4k.active, onTap: () => onOpenSubDrawer('anime4k')),
      _divider(),
      _row(id: 'more', icon: LineIcon.sliders, title: 'Більше', onTap: () => onOpenSubDrawer('advanced')),
    ];
  }

  /// «Пісня»: the cover, which opening / ending it is, the title and the artist, and where to listen to it
  List<Widget> _songPage(SongKind kind) {
    final songs = remote?.songs?.current.value;
    final song = songs?.of(kind);
    if (song == null) return [_note('Пісню цієї серії не знайдено')];
    final art = songs!.art[kind];
    final pad = (sheet ? 20 : 16) * scale;
    return [
      Padding(
        padding: EdgeInsets.fromLTRB(pad, 4 * scale, pad, 12 * scale),
        child: Row(
          children: [
            SongCover(url: art?.cover, size: (sheet ? 96 : 72) * scale),
            SizedBox(width: 16 * scale),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(song.label, style: playerText((sheet ? 12.5 : 12) * scale, color: AppTones.caption, weight: FontWeight.w700)),
                  SizedBox(height: 4 * scale),
                  Text(song.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: playerText((sheet ? 20 : 18) * scale, weight: FontWeight.w700)),
                  if (song.native != null && song.native != song.title) ...[
                    SizedBox(height: 2 * scale),
                    Text(song.native!, maxLines: 1, overflow: TextOverflow.ellipsis, style: playerText((sheet ? 14 : 13) * scale, color: AppTones.rowSub)),
                  ],
                  if (song.artists.isNotEmpty) ...[
                    SizedBox(height: 2 * scale),
                    Text(song.artist, maxLines: 2, overflow: TextOverflow.ellipsis, style: playerText((sheet ? 15 : 14) * scale, color: uiTheme.textSecondary)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      _divider(),
      for (final l in SongService.linksFor(song, art: art))
        PlayerMenuRow(
          key: ValueKey('menu-song-${l.app.name}'),
          scale: scale,
          sheet: sheet,
          icon: LineIcon.musicNote,
          leading: MusicAppBadge(app: l.app, size: (sheet ? 32 : 28) * scale),
          title: musicAppName(l.app),
          value: !l.direct ? 'пошук' : (l.app == MusicApp.youtube ? 'кліп' : 'пісня'),
          chevron: false,
          onTap: () {
            AppLog.i('дія', 'пісня: ${musicAppName(l.app)} (${l.direct ? 'посилання' : 'пошук'})');
            unawaited(HikkaNav.instance.urlOpener(l.url));
          },
        ),
    ];
  }

  /// Under the chapters, when their times came from AniSkip: the shift for this dub, "the opening started here" and
  /// where the times come from
  List<Widget> _skipControls() {
    final r = remote;
    final plan = r?.skipPlan;
    if (r == null || plan == null || plan.source == 'сайт') return const [];
    final note = skipNote(plan);
    return [
      _divider(),
      if (plan.adjustable) _SkipShiftRow(scale: scale, sheet: sheet, remote: r, plan: plan),
      if (plan.adjustable && plan.opBase != null)
        _row(
          id: 'skip-here',
          icon: LineIcon.pin,
          title: 'Опенінґ почався тут',
          value: AppFormatters.formatTime(player.state.position),
          chevron: false,
          onTap: () => r.skipOpeningAt(player.state.position),
        ),
      if (note.isNotEmpty) _note(note),
    ];
  }

  /// Where the skip times come from and how sure they are, for people
  static String skipNote(SkipPlan p) {
    final s = p.shift;
    if (s == null) return p.source == 'аналіз звуку' ? 'Опенінґ знайдено за звуком: він однаковий у сусідніх серіях цього озвучення.' : '';
    if (s.source == 'user') return 'Зсув задано вручну — він діє на всі серії цього озвучення.';
    if (s.exact) return 'Таймкоди з ${p.source}, підігнані під це озвучення. Якщо пропуск не влучає — підправте зсув: він діє на всі серії озвучення.';
    final extra = (p.extra ?? 0).abs().round();
    final longer = (p.extra ?? 0) >= 0 ? 'довше' : 'коротше';
    return 'Приблизно: відео на $extra\u00A0с $longer, ніж версія, розмічена в ${p.source}, тож кнопка є лише там, де опенінґ іде напевно. Позначте його початок — і таймкоди стануть точними.';
  }

  /// The Anime4K page: quality, off, and six modes with key hints.
  /// The menu does not close after a choice: modes are convenient to compare "live".
  List<Widget> _buildAnime4kPage(double scale) {
    final a = anime4k;
    final keys = !AppPlatform.isMobile;
    final pad = (sheet ? 20 : 16) * scale;
    return [
      Padding(
        padding: EdgeInsets.fromLTRB(pad, 4 * scale, pad, 6 * scale),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                for (final q in Anime4kQuality.values) ...[
                  AppPlate(
                    key: ValueKey('anime4k-quality-${q.name}'),
                    scale: scale,
                    label: q.label,
                    height: 34,
                    radius: 10,
                    selected: a.quality == q,
                    onTap: () => a.setQuality(q),
                  ),
                  SizedBox(width: 8 * scale),
                ],
                const Spacer(),
                // Key hints (Ctrl + digit) make sense only with a keyboard
                if (keys) AppKeyCombo(scale: scale, keys: const ['Ctrl', '9']),
              ],
            ),
            SizedBox(height: 8 * scale),
            Text(
              AppPlatform.isMobile ? a.quality.deviceHint : a.quality.gpuHint,
              style: playerText(12 * scale, color: AppTones.rowSub, height: 1.35),
            ),
          ],
        ),
      ),
      _choice(
        id: 'anime4k-off',
        label: 'Вимкнено',
        subtitle: 'Без обробки шейдерами',
        selected: !a.enabled,
        trailing: keys ? AppKeyCombo(scale: scale, keys: const ['Ctrl', '0']) : null,
        onTap: a.disable,
      ),
      for (final m in Anime4kMode.values)
        _choice(
          id: 'anime4k-${m.name}',
          label: m.title,
          subtitle: m.tagline,
          selected: a.enabled && a.mode == m,
          trailing: keys ? AppKeyCombo(scale: scale, keys: ['Ctrl', '${m.digit}']) : null,
          onTap: () => a.setMode(m),
        ),
      if (a.enabled && a.skipped) _note('Пропущено: відео ${a.videoHeight}p не менше за поріг ${a.skipHeight}p (змінюється в налаштуваннях)'),
      if (a.error != null) _note(a.error!, isError: true),
    ];
  }
}

/// Audio delay (`audio-delay` in mpv): a 50 ms step, from −10 to +10 s; the reset button returns zero.
/// It is stored for a work (see `audioDelayKey`) and applied to its next episodes.
class _AudioDelayRow extends StatefulWidget {
  final double scale;
  final bool sheet;
  final Player player;
  final String storeKey;
  const _AudioDelayRow({required this.scale, required this.sheet, required this.player, required this.storeKey});

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

  /// "+150 мс", "−50 мс", "0 мс"
  static String format(int ms) => ms > 0 ? '+$ms мс' : (ms < 0 ? '−${-ms} мс' : '0 мс');

  @override
  Widget build(BuildContext context) => _StepperRow(
        scale: widget.scale,
        sheet: widget.sheet,
        id: 'delay',
        icon: LineIcon.sync,
        title: 'Затримка звуку',
        value: format(_ms),
        strong: _ms != 0,
        minus: ('Раніше на $_stepMs мс', () => _set(_ms - _stepMs)),
        plus: ('Пізніше на $_stepMs мс', () => _set(_ms + _stepMs)),
        reset: ('Скинути затримку', _ms == 0 ? null : () => _set(0)),
      );
}

/// A row with a stepper: the icon, the name and the value, − / + / reset plates (at least 40 dp on a phone). On a
/// phone sheet the value goes under the name: the narrow sheet has no room for both in one line
class _StepperRow extends StatelessWidget {
  final double scale;
  final bool sheet;

  /// Keys: `<id>-minus`, `<id>-value`, `<id>-plus`, `<id>-reset`
  final String id;
  final LineIcon icon;
  final String title;
  final String value;

  /// The value is set (not zero, exact): bright, not muted
  final bool strong;

  /// (what it does for screen readers, the action; null: disabled)
  final (String, VoidCallback?) minus;
  final (String, VoidCallback?) plus;
  final (String, VoidCallback?) reset;

  const _StepperRow({
    required this.scale,
    required this.sheet,
    required this.id,
    required this.icon,
    required this.title,
    required this.value,
    required this.strong,
    required this.minus,
    required this.plus,
    required this.reset,
  });

  Widget _plate(String part, LineIcon icon, (String, VoidCallback?) a) {
    final double size = sheet ? 40 : 32 * scale;
    final enabled = a.$2 != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: a.$1,
      child: Material(
        color: AppTones.plate,
        shape: RoundedRectangleBorder(borderRadius: uiTheme.borderRadius(10 * scale)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('$id-$part'),
          onTap: a.$2,
          splashColor: Colors.transparent,
          highlightColor: uiTheme.touchHighlight,
          hoverColor: uiTheme.hoverOverlay,
          child: SizedBox.square(
            dimension: size,
            child: Center(child: LineIconView(icon, size: size * 0.5, color: enabled ? AppTones.plateText : AppTones.chevron)),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double sc = scale;
    final valueText = Text(
      value,
      key: ValueKey('$id-value'),
      maxLines: 1,
      textAlign: sheet ? TextAlign.start : TextAlign.center,
      style: playerText((sheet ? 13 : 13.5) * sc, weight: FontWeight.w700, color: strong ? uiTheme.textPrimary : uiTheme.textMuted),
    );
    // On a phone a long name gets a little smaller rather than cut off
    final name = sheet
        ? FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(title, maxLines: 1, style: playerText(15 * sc)))
        : Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: playerText(14 * sc));
    return Padding(
      padding: EdgeInsets.fromLTRB((sheet ? 20 : 16) * sc, 6 * sc, (sheet ? 14 : 12) * sc, 2 * sc),
      child: Row(
        children: [
          SizedBox(width: 24 * sc, child: Center(child: LineIconView(icon, size: (sheet ? 22 : 20) * sc, color: AppTones.rowIcon))),
          SizedBox(width: (sheet ? 16 : 14) * sc),
          if (sheet) ...[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [name, SizedBox(height: 2 * sc), valueText],
              ),
            ),
            SizedBox(width: 8 * sc),
            _plate('minus', LineIcon.minus, minus),
            SizedBox(width: 6 * sc),
            _plate('plus', LineIcon.plus, plus),
          ] else ...[
            Expanded(child: name),
            _plate('minus', LineIcon.minus, minus),
            SizedBox(width: 72 * sc, child: valueText),
            _plate('plus', LineIcon.plus, plus),
          ],
          SizedBox(width: 6 * sc),
          _plate('reset', LineIcon.refresh, reset),
        ],
      ),
    );
  }
}

/// The shift of AniSkip's times for this dub (a half-second step): one for all its episodes, kept until reset.
/// "≈" while the lengths alone place them (the middle of what they allow)
class _SkipShiftRow extends StatelessWidget {
  final double scale;
  final bool sheet;
  final RemoteDriver remote;
  final SkipPlan plan;
  const _SkipShiftRow({required this.scale, required this.sheet, required this.remote, required this.plan});

  static const double step = 0.5;

  /// "+12,5 с", "−3 с", "0 с"
  static String format(double seconds) {
    final v = (seconds * 2).round() / 2;
    final a = v.abs();
    final t = a == a.roundToDouble() ? '${a.toInt()}' : a.toStringAsFixed(1).replaceAll('.', ',');
    return v > 0 ? '+$t с' : (v < 0 ? '−$t с' : '0 с');
  }

  @override
  Widget build(BuildContext context) {
    final shift = plan.shift!;
    return _StepperRow(
      scale: scale,
      sheet: sheet,
      id: 'skipshift',
      icon: LineIcon.clock,
      title: 'Зсув таймкодів',
      value: shift.exact ? format(shift.mid) : '≈${format(shift.mid)}',
      strong: shift.exact,
      minus: ('Раніше на пів секунди', () => remote.shiftSkips(-step)),
      plus: ('Пізніше на пів секунди', () => remote.shiftSkips(step)),
      reset: ('Скинути зсув', shift.source == 'user' ? () => remote.resetSkipShift() : null),
    );
  }
}
