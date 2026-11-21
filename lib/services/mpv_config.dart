import 'dart:convert';
import 'dart:io';
import 'package:media_kit/media_kit.dart';
import '../constants/app_identity.dart';
import '../models/media_models.dart';
import '../utils/formatters.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'storage_service.dart';
import 'system_fonts.dart';

class MpvConfig {
  /// Subtitle font for libass on Android (Liberation Sans, SIL OFL 1.1; has Cyrillic, including ї and ґ).
  /// libmpv for Android has no system fonts: without this font libass draws no line at all.
  static const String androidSubtitleFontAsset = 'assets/fonts/subtitle.ttf';
  static const String androidSubtitleFontName = 'Liberation Sans';

  /// Lays out the bundled fonts (and the fallback Liberation Sans) in the app folder: libass reads fonts only from files
  static Future<String?> ensureEmbeddedFontsDir() async {
    try {
      final dir = Directory('${StorageService.appBasePath}/fonts');
      if (!await dir.exists()) await dir.create(recursive: true);
      final assets = {...SystemFonts.embedded.values, androidSubtitleFontAsset};
      for (final a in assets) {
        final f = File('${dir.path}/${a.split('/').last}');
        final data = await rootBundle.load(a);
        if (!await f.exists() || await f.length() != data.lengthInBytes) {
          await f.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
        }
      }
      return dir.path;
    } catch (_) {
      return null;
    }
  }

  /// The audio output options (see `tools/audio_bench.py` for the checks with real mpv).
  ///
  /// `gapless-audio=weak` (mpv's default): the output follows the format of each file. With `yes` it kept the first
  /// file's format for the whole session — after a mono episode the next stereo ones played in mono — and it never
  /// reopened, so a latency measured at start stayed until a restart.
  ///
  /// Android: `audiotrack` (as in mpv-android) creates a media AudioTrack and reads what is actually playing from its
  /// timestamps, so the sync follows Bluetooth and other route changes; OpenSL ES, which media_kit sets, measured the
  /// device latency once when the output opened and always played two channels. OpenSL ES stays as the fallback.
  static Map<String, String> audioOptions({required bool android}) => {
        'gapless-audio': 'weak',
        if (android) 'ao': 'audiotrack,opensles',
      };

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
        for (final e in audioOptions(android: Platform.isAndroid).entries) {
          await platform.setProperty(e.key, e.value);
        }

        // 1. Applying subtitle styles
        await applySubtitleStyles(player);

        // 2. Reading and applying a custom mpv.conf if it exists
        await loadCustomMpvConf(player);
      }
    } catch (_) {}
  }

  // READING AND PARSING THE CUSTOM MPV.CONF
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

  // APPLYING CRUNCHYROLL STYLES AND SSA OVERRIDE MODES
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

        // Android: the only available libass font is the bundled one (media_kit already set its directory and name); custom
        // fonts and the name from the Windows settings are not carried over here, since they would replace it and subtitles would vanish
        final bool android = Platform.isAndroid;
        final customFonts = android ? const <String>[] : StorageService.getCustomFonts();
        final embedded = SystemFonts.embedded.containsKey(font);
        final dirs = <String>{...customFonts.map((p) => File(p).parent.path)};
        if (!android || embedded) {
          final own = await ensureEmbeddedFontsDir();
          if (own != null) dirs.add(own);
        }
        if (dirs.isNotEmpty) await platform.setProperty('sub-fonts-dir', dirs.join(Platform.isWindows ? ';' : ':'));

        // ASS rewrite modes
        if (assMode == 'force') {
          await platform.setProperty('sub-ass-override', 'force');
        } else if (assMode == 'yes') {
          // Rewrites only the plain dialogue text (keeps signs and songs)
          await platform.setProperty('sub-ass-override', 'yes');
        } else {
          await platform.setProperty('sub-ass-override', 'no');
        }

        if (!android || embedded) await platform.setProperty('sub-font', font);
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
          getProp('current-ao'),
          getProp('audio-params/hr-channels'),
          getProp('audio-out-params/hr-channels'),
          getProp('audio-out-params/samplerate'),
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
          audioOutput: describeAudioOutput(ao: results[6], source: results[7], output: results[8], rate: results[9]),
        );
      }
    } catch (_) {}

    return const PlaybackStats();
  }

  /// What goes to the speakers, for the stats: `5.1 → стерео · 48 кГц · audiotrack` (mono shows as «моно»)
  static String describeAudioOutput({String? ao, String? source, String? output, String? rate}) {
    String name(String? layout) => switch (layout) {
          null || '' => '',
          'mono' => 'моно',
          'stereo' => 'стерео',
          final l => l,
        };
    final out = name(output);
    if (out.isEmpty) return '—';
    final src = name(source);
    final hz = int.tryParse(rate ?? '') ?? 0;
    return [
      src.isNotEmpty && src != out ? '$src → $out' : out,
      if (hz > 0) '${hz % 1000 == 0 ? hz ~/ 1000 : (hz / 1000).toStringAsFixed(1)} кГц',
      if (ao != null && ao.isNotEmpty) ao,
    ].join(' · ');
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