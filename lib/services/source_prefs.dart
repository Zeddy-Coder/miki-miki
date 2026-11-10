/// Налаштування джерел перегляду: які ввімкнені, ключ Mikai, бажана якість і плеєр.
library;

import 'package:flutter/foundation.dart';

import 'backend_client.dart';
import 'storage_service.dart';

class SourcePrefs extends ChangeNotifier {
  static const String section = 'source_prefs';

  /// Якості, які пропонуємо вибрати (висота кадру; 0 — найвища доступна)
  static const List<int> heights = [0, 1080, 720, 480];

  final SectionLoader _load;
  final SectionSaver _save;
  late Map<String, dynamic> _data = Map<String, dynamic>.of(_load());

  SourcePrefs({SectionLoader? load, SectionSaver? save})
      : _load = load ?? (() => StorageService.getSection(section)),
        _save = save ?? ((d) => StorageService.saveSection(section, d));

  static SourcePrefs instance = SourcePrefs();

  /// Для тестів і після зміни сховища: перечитати дані
  void reload() {
    _data = Map<String, dynamic>.of(_load());
    notifyListeners();
  }

  void _put(String key, Object? value) {
    if (value == null) {
      _data.remove(key);
    } else {
      _data[key] = value;
    }
    _save(_data);
    notifyListeners();
  }

  // ── Ввімкнені джерела ────────────────────────────────────────────────────────
  Set<String> get _disabled => {for (final x in (_data['disabled'] as List? ?? const [])) '$x'};

  bool isEnabled(String sourceId) => !_disabled.contains(sourceId);

  void setEnabled(String sourceId, bool on) {
    final d = _disabled;
    on ? d.remove(sourceId) : d.add(sourceId);
    _put('disabled', d.toList()..sort());
  }

  // ── Mikai ────────────────────────────────────────────────────────────────────
  /// Необовʼязковий ключ API Mikai (300 запитів/хв замість 60)
  String get mikaiKey => (_data['mikai_key'] as String?) ?? '';

  set mikaiKey(String v) => _put('mikai_key', v.trim().isEmpty ? null : v.trim());

  // ── Moon ─────────────────────────────────────────────────────────────────────
  /// Власний ключ MoonAnime API (необов'язковий: без нього діє безкоштовний ключ із бекенду)
  String get moonKey => (_data['moon_key'] as String?) ?? '';

  set moonKey(String v) => _put('moon_key', v.trim().isEmpty ? null : v.trim());

  /// Ключ, яким користується Moon: власний із налаштувань, а коли його нема — безкоштовний із бекенду (у застосунку ключів немає)
  String get effectiveMoonKey => moonKey.isNotEmpty ? moonKey : BackendClient.instance.cachedMoonKey;

  // ── Відео ────────────────────────────────────────────────────────────────────
  /// Найбільша висота кадру, яку вибираємо автоматично (0 — найвища)
  int get maxHeight => (_data['max_height'] as num?)?.toInt() ?? 0;

  set maxHeight(int v) => _put('max_height', v);

  /// Бажаний плеєр («Moon», «Ashdi»); порожньо — за порядком джерела
  String get hoster => (_data['hoster'] as String?) ?? '';

  set hoster(String v) => _put('hoster', v.isEmpty ? null : v);

  static String heightLabel(int h) => h == 0 ? 'Найвища' : '${h}p';
}
