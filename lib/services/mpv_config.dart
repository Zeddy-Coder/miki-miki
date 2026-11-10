import 'dart:convert';
import 'dart:io';
import 'package:media_kit/media_kit.dart';
import '../constants/app_identity.dart';
import '../models/media_models.dart';
import '../utils/formatters.dart';
import 'storage_service.dart';

class MpvConfig {
  /// Шрифт субтитрів для libass на Android (Liberation Sans, SIL OFL 1.1; є кирилиця, зокрема і ї є ґ).
  /// У libmpv для Android немає системних шрифтів: без цього шрифту libass не малює жодного рядка.
  static const String androidSubtitleFontAsset = 'assets/fonts/subtitle.ttf';
  static const String androidSubtitleFontName = 'Liberation Sans';

  static Future<void> configureEngine(Player player, String hwdec) async {
    try {
      final dynamic platform = player.platform;
      if (platform != null) {
        await platform.setProperty('demuxer-max-bytes', '67108864');
        await platform.setProperty('demuxer-max-back-bytes', '16777216');
        await platform.setProperty('demuxer-readahead-secs', '20');
        await platform.setProperty('demuxer-mkv-subtitle-preroll', 'no');
        await platform.setProperty('osc', 'no');
        await platform.setProperty('hwdec', hwdec);
        await platform.setProperty('video-sync', 'audio');
        await platform.setProperty('framedrop', 'vo');
        await platform.setProperty('vd-lavc-fast', 'yes');
        await platform.setProperty('audio-pitch-correction', 'yes');
        await platform.setProperty('hr-seek-framedrop', 'yes');
        await platform.setProperty('sub-ass', 'yes');
        await platform.setProperty('embeddedfonts', 'yes');
        await platform.setProperty('sub-font-provider', 'auto');
        await platform.setProperty('sub-ass-force-margins', 'no');
        await platform.setProperty('sub-ass-vsfilter-blur-compat', 'yes');
        await platform.setProperty('blend-subtitles', 'yes');
        await platform.setProperty('sub-fix-timing', 'yes');
        await platform.setProperty('gapless-audio', 'yes');

        // 1. Застосування стилів субтитрів
        await applySubtitleStyles(player);

        // 2. Зчитування та застосування кастомного mpv.conf якщо він існує
        await loadCustomMpvConf(player);
      }
    } catch (_) {}
  }

  // ЗЧИТУВАННЯ ТА ПАРСИНГ КАСТОМНОГО MPV.CONF
  static Future<void> loadCustomMpvConf(Player player) async {
    try {
      final dynamic platform = player.platform;
      if (platform == null) return;

      String basePath = '';
      if (Platform.isWindows) {
        final appData = Platform.environment['APPDATA'] ?? Platform.environment['USERPROFILE'] ?? '.';
        basePath = '$appData/${AppIdentity.dataDirName}';
      } else {
        basePath = '${Directory.systemTemp.path}/${AppIdentity.dataDirName}';
      }

      final confFile = File('$basePath/mpv.conf');
      if (await confFile.exists()) {
        final lines = await confFile.readAsLines();
        for (var line in lines) {
          line = line.trim();
          if (line.isEmpty || line.startsWith('#')) continue;

          if (line == 'no-sub-ass') {
            await platform.setProperty('sub-ass', 'no');
            continue;
          }

          if (line.contains('=')) {
            final parts = line.split('=');
            final key = parts.first.trim();
            final value = parts.sublist(1).join('=').trim().replaceAll("'", "").replaceAll('"', "");
            await platform.setProperty(key, value);
          } else {
            final parts = line.split(RegExp(r'\s+'));
            if (parts.length == 2) {
              await platform.setProperty(parts[0].trim(), parts[1].trim());
            }
          }
        }
      }
    } catch (_) {}
  }

  // ЗАСТОСУВАННЯ СТИЛІВ CRUNCHYROLL ТА РЕЖИМІВ SSA OVERRIDE
  static Future<void> applySubtitleStyles(Player player) async {
    try {
      final dynamic platform = player.platform;
      if (platform != null) {
        final font = StorageService.getSubFont();
        final fontSize = StorageService.getSubFontSize();
        final color = StorageService.getSubTextColor();
        final border = StorageService.getSubBorderSize();
        final shadow = StorageService.getSubShadowOffset();
        final marginY = StorageService.getSubMarginY();
        final bgOpacity = StorageService.getSubBgOpacity();
        final assMode = StorageService.getSubAssMode(); // 'no' | 'yes' | 'force'

        // Android: єдиний доступний libass шрифт — вбудований (його каталог і назву вже задав media_kit); власні
        // шрифти й назву з налаштувань для Windows сюди не переносимо, бо вони замінили б його й субтитри зникли б
        final bool android = Platform.isAndroid;
        final customFonts = android ? const <String>[] : StorageService.getCustomFonts();
        if (customFonts.isNotEmpty) {
          final customDirs = customFonts.map((p) => File(p).parent.path).toSet().join(';');
          await platform.setProperty('sub-fonts-dir', customDirs);
        }

        // Режими переписування ASS
        if (assMode == 'force') {
          await platform.setProperty('sub-ass-override', 'force');
        } else if (assMode == 'yes') {
          // Переписує тільки звичайний текст діалогів (зберігає написи та пісні)
          await platform.setProperty('sub-ass-override', 'yes');
        } else {
          await platform.setProperty('sub-ass-override', 'no');
        }

        if (!android) await platform.setProperty('sub-font', font);
        await platform.setProperty('sub-font-size', fontSize.toInt().toString());
        await platform.setProperty('sub-color', color);
        await platform.setProperty('sub-border-size', border.toString());
        await platform.setProperty('sub-border-color', '#000000');
        await platform.setProperty('sub-shadow-offset', shadow.toString());
        await platform.setProperty('sub-shadow-color', '#000000');
        await platform.setProperty('sub-margin-y', marginY.toInt().toString());

        if (bgOpacity > 0) {
          final alphaHex = ((bgOpacity * 255).toInt()).toRadixString(16).padLeft(2, '0');
          await platform.setProperty('sub-back-color', '#${alphaHex}000000');
        } else {
          await platform.setProperty('sub-back-color', '#00000000');
        }
      }
    } catch (_) {}
  }

  static Future<PlaybackStats> fetchLiveStats({
    required Player player,
    required double currentSpeed,
    required String currentHwdec,
  }) async {
    try {
      final dynamic platform = player.platform;
      if (platform != null) {
        Future<String?> getProp(String name) async {
          try {
            final res = await platform.getProperty(name);
            return res?.toString();
          } catch (_) {
            return null;
          }
        }

        final results = await Future.wait([
          getProp('frame-drop-count'),
          getProp('vo-drop-frame-count'),
          getProp('decoder-frame-drop-count'),
          getProp('container-fps'),
          getProp('hwdec-current'),
          getProp('avsync'),
        ]);

        final totalDrops = int.tryParse(results[0] ?? '') ?? 0;
        final voDrops = int.tryParse(results[1] ?? '') ?? 0;
        final decDrops = int.tryParse(results[2] ?? '') ?? 0;
        double conFps = double.tryParse(results[3] ?? '') ?? 0.0;
        if (conFps <= 0.0) conFps = player.state.tracks.video.firstOrNull?.fps ?? 23.976;

        final hwdec = (results[4] != null && results[4]!.isNotEmpty) ? results[4]! : currentHwdec;
        final avSync = double.tryParse(results[5] ?? '') ?? 0.0;
        final vTrack = player.state.tracks.video.firstOrNull;
        final aTrack = player.state.track.audio;

        return PlaybackStats(
          totalDroppedFrames: totalDrops,
          voDroppedFrames: voDrops,
          decoderDroppedFrames: decDrops,
          currentFps: conFps * currentSpeed,
          containerFps: conFps,
          expectedFps: conFps * currentSpeed,
          hwdecActive: hwdec,
          avSyncDiff: avSync,
          videoCodec: vTrack?.codec ?? "HEVC",
          audioCodec: aTrack.title ?? aTrack.language ?? "Аудіо",
        );
      }
    } catch (_) {}

    return const PlaybackStats();
  }

  static Future<List<VideoChapter>> extractChapters(Player player) async {
    try {
      final dynamic platform = player.platform;
      if (platform != null) {
        final raw = await platform.getProperty('chapter-list');
        if (raw != null && raw.toString().isNotEmpty) {
          dynamic data = raw is String ? jsonDecode(raw) : raw;
          if (data is List && data.isNotEmpty) {
            final List<VideoChapter> parsed = [];
            for (var item in data) {
              if (item is Map) {
                final title = (item['title']?.toString() ?? '').trim();
                final double timeSec = (item['time'] is num) ? (item['time'] as num).toDouble() : (double.tryParse(item['time']?.toString() ?? '0') ?? 0.0);
                parsed.add(VideoChapter(
                  title: title.isNotEmpty ? title : 'Розділ ${parsed.length + 1}',
                  startTime: Duration(milliseconds: (timeSec * 1000).round()),
                ));
              }
            }
            return parsed;
          }
        }
      }
    } catch (_) {}
    return [];
  }

  static List<CachedSubtitleTrack> extractSubtitleTracks(Tracks tracks) {
    return tracks.subtitle
        .where((t) => t.id != 'no' && t.id != 'auto')
        .map((t) => CachedSubtitleTrack(track: t, formattedTitle: AppFormatters.formatTrackTitle(t.language, t.title)))
        .toList();
  }

  static List<CachedAudioTrack> extractAudioTracks(Tracks tracks) {
    return tracks.audio
        .where((t) => t.id != 'no' && t.id != 'auto')
        .map((t) => CachedAudioTrack(track: t, formattedTitle: AppFormatters.formatTrackTitle(t.language, t.title, channels: t.channels?.toString())))
        .toList();
  }
}