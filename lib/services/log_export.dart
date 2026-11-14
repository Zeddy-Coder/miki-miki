/// Saving the log to a separate file (not to the clipboard).
///
/// Builds the full report ([AppLog.buildReport]) and hands it to the system "Save as" window: on a phone this is a folder
/// picker (e.g. "Downloads"), on Windows the standard dialog. The file can then be sent as is.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import 'app_log.dart';
import '../constants/app_identity.dart';

/// Save result
class LogExportResult {
  /// The file was written
  final bool saved;

  /// The user closed the window without choosing anything
  final bool cancelled;

  /// The path (or link) the system returned
  final String? path;

  /// The file name offered for saving
  final String fileName;

  final String? error;

  const LogExportResult({required this.saved, required this.fileName, this.cancelled = false, this.path, this.error});
}

/// Shows the system save window: returns a path or `null` if cancelled (replaced in tests)
typedef LogSaver = Future<String?> Function(String fileName, Uint8List bytes);

class LogExport {
  const LogExport._();

  /// File name: `miki_miki_log_20261103_143012.txt`
  static String fileName([DateTime? now]) {
    final t = now ?? DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${AppIdentity.packageName}_log_${t.year}${two(t.month)}${two(t.day)}_${two(t.hour)}${two(t.minute)}${two(t.second)}.txt';
  }

  static Future<String?> _pickerSaver(String fileName, Uint8List bytes) {
    return FilePicker.saveFile(
      dialogTitle: 'Зберегти журнал',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: const ['txt', 'log'],
      bytes: bytes,
    );
  }

  /// Builds the report and offers to save the file. `extra` holds extra sections (live metrics, libmpv logs…).
  static Future<LogExportResult> save({
    List<(String, String)> extra = const [],
    AppLog? log,
    LogSaver? saver,
    DateTime? now,
  }) async {
    final name = fileName(now);
    final journal = log ?? AppLog.instance;
    try {
      final text = await journal.buildReport(extra: extra);
      final bytes = Uint8List.fromList(utf8.encode(text));
      final path = await (saver ?? _pickerSaver)(name, bytes);
      if (path == null) {
        AppLog.i('журнал', 'збереження у файл скасовано');
        return LogExportResult(saved: false, cancelled: true, fileName: name);
      }
      AppLog.i('журнал', 'журнал збережено у файл ($name, ${AppLog.bytesLabel(bytes.length)})');
      return LogExportResult(saved: true, path: path, fileName: name);
    } catch (e) {
      AppLog.e('журнал', 'не вдалося зберегти файл', e);
      return LogExportResult(saved: false, fileName: name, error: '$e');
    }
  }
}
