/// Збереження журналу в окремий файл (а не в буфер обміну).
///
/// Збирає повний звіт ([AppLog.buildReport]) і віддає його системному вікну «Зберегти як»: на телефоні це вибір
/// теки (наприклад, «Завантаження»), на Windows — стандартний діалог. Файл потім можна надіслати як є.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import 'app_log.dart';
import '../constants/app_identity.dart';

/// Результат збереження
class LogExportResult {
  /// Файл записано
  final bool saved;

  /// Користувач закрив вікно, нічого не вибравши
  final bool cancelled;

  /// Шлях (або посилання), який повернула система
  final String? path;

  /// Назва файлу, під якою пропонувалось зберегти
  final String fileName;

  final String? error;

  const LogExportResult({required this.saved, required this.fileName, this.cancelled = false, this.path, this.error});
}

/// Показує системне вікно збереження: повертає шлях або `null`, якщо скасовано (у тестах підміняється)
typedef LogSaver = Future<String?> Function(String fileName, Uint8List bytes);

class LogExport {
  const LogExport._();

  /// Назва файлу: `miki_miki_log_20261103_143012.txt`
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

  /// Збирає звіт і пропонує зберегти файл. `extra` — додаткові розділи (живі показники, логи libmpv…).
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
