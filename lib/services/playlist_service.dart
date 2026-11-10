import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:media_kit/media_kit.dart';
import '../utils/formatters.dart';

class PlaylistService {
  static Future<List<Media>> parsePath(String path) async {
    final ext = path.split('.').last.toLowerCase();

    if (ext == 'm3u' || ext == 'm3u8' || ext == 'pls') {
      try {
        final file = File(path);
        if (await file.exists()) {
          final lines = await file.readAsLines();
          List<Media> medias = [];
          String currentMediaTitle = '';

          for (var line in lines) {
            line = line.trim();
            if (line.isEmpty) continue;
            if (line.startsWith('#EXTINF:')) {
              final parts = line.split(',');
              if (parts.length > 1) currentMediaTitle = parts.sublist(1).join(',').trim();
            } else if (!line.startsWith('#')) {
              String mediaPath = line;
              if (!line.startsWith('http://') && !line.startsWith('https://') && !line.startsWith('file://')) {
                if (!File(line).isAbsolute) mediaPath = '${file.parent.path}/$line';
              }
              final title = currentMediaTitle.isNotEmpty ? currentMediaTitle : AppFormatters.cleanMediaTitle(mediaPath);
              medias.add(Media(mediaPath, extras: {'title': title}));
              currentMediaTitle = '';
            }
          }
          if (medias.isNotEmpty) return medias;
        }
      } catch (_) {}
    }

    final fileName = AppFormatters.cleanMediaTitle(path);
    return [Media(path, extras: {'title': fileName})];
  }

  static Future<List<String>> pickVideoPaths() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowMultiple: true,
        allowedExtensions: ['mp4', 'mkv', 'avi', 'mov', 'webm', 'flv', 'ts', 'm4v', 'm3u', 'm3u8', 'pls'],
      );
      if (result != null && result.files.isNotEmpty) {
        return result.files.where((f) => f.path != null).map((f) => f.path!).toList();
      }
    } catch (_) {}
    return [];
  }
}