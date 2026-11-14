/// Watch-source log for diagnostics: requests, extractor steps, errors.
/// Visible in "Статистика → Джерела" and goes into "Копіювати звіт". In memory only, no personal data:
/// the values of `token`, `key`, `apikey` are hidden in addresses.
library;

import 'package:flutter/foundation.dart';

import '../app_log.dart';

class SourceLog extends ChangeNotifier {
  SourceLog._();

  static final SourceLog instance = SourceLog._();
  static const int maxLines = 400;

  final List<String> lines = [];
  final Stopwatch _clock = Stopwatch()..start();

  static final RegExp _secret = RegExp(r'((?:token|key|apikey|api_key|auth)=)[^&\s]+', caseSensitive: false);

  static String clean(String s) => s.replaceAllMapped(_secret, (m) => '${m.group(1)}***');

  /// A timestamped entry (mm:ss.ms since the app launch)
  static void add(String text) {
    final i = instance;
    final t = i._clock.elapsed;
    final stamp = '${t.inMinutes.toString().padLeft(2, '0')}:${(t.inSeconds % 60).toString().padLeft(2, '0')}.${(t.inMilliseconds % 1000).toString().padLeft(3, '0')}';
    final cleaned = clean(text);
    if (i.lines.length >= maxLines) i.lines.removeAt(0);
    i.lines.add('$stamp $cleaned');
    i.notifyListeners();
    // The same goes into the single log (file)
    final bad = cleaned.startsWith('✗') || cleaned.startsWith('Збій') || cleaned.contains('ПОМИЛКА');
    if (bad) {
      AppLog.w('джерела', cleaned);
    } else {
      AppLog.i('джерела', cleaned);
    }
  }

  static void clear() {
    instance.lines.clear();
    instance.notifyListeners();
  }
}
