/// Watch-source settings: which are enabled, the Mikai key, preferred quality and player.
library;

import 'package:flutter/foundation.dart';

import 'backend_client.dart';
import 'storage_service.dart';

class SourcePrefs extends ChangeNotifier {
  static const String section = 'source_prefs';

  /// Qualities we offer to choose (frame height; 0 is the highest available)
  static const List<int> heights = [0, 1080, 720, 480];

  final SectionLoader _load;
  final SectionSaver _save;
  late Map<String, dynamic> _data = Map<String, dynamic>.of(_load());

  SourcePrefs({SectionLoader? load, SectionSaver? save})
      : _load = load ?? (() => StorageService.getSection(section)),
        _save = save ?? ((d) => StorageService.saveSection(section, d));

  static SourcePrefs instance = SourcePrefs();

  /// For tests and after a store change: reread the data
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

  // ── Enabled sources ────────────────────────────────────────────────────────
  Set<String> get _disabled => {for (final x in (_data['disabled'] as List? ?? const [])) '$x'};

  bool isEnabled(String sourceId) => !_disabled.contains(sourceId);

  void setEnabled(String sourceId, bool on) {
    final d = _disabled;
    on ? d.remove(sourceId) : d.add(sourceId);
    _put('disabled', d.toList()..sort());
  }

  // ── Mikai ────────────────────────────────────────────────────────────────────
  /// Optional Mikai API key (300 requests/min instead of 60)
  String get mikaiKey => (_data['mikai_key'] as String?) ?? '';

  set mikaiKey(String v) => _put('mikai_key', v.trim().isEmpty ? null : v.trim());

  // ── Moon ─────────────────────────────────────────────────────────────────────
  /// Own MoonAnime API key (optional: without it the free key from the backend applies)
  String get moonKey => (_data['moon_key'] as String?) ?? '';

  set moonKey(String v) => _put('moon_key', v.trim().isEmpty ? null : v.trim());

  /// The key Moon uses: the own one from settings, and when there is none, the free one from the backend (the app has no keys)
  String get effectiveMoonKey => moonKey.isNotEmpty ? moonKey : BackendClient.instance.cachedMoonKey;

  // ── Video ────────────────────────────────────────────────────────────────────
  /// The largest frame height we pick automatically (0 is the highest)
  int get maxHeight => (_data['max_height'] as num?)?.toInt() ?? 0;

  set maxHeight(int v) => _put('max_height', v);

  /// Preferred player ("Moon", "Ashdi"); empty means by the source's order
  String get hoster => (_data['hoster'] as String?) ?? '';

  set hoster(String v) => _put('hoster', v.isEmpty ? null : v);

  static String heightLabel(int h) => h == 0 ? 'Найвища' : '${h}p';
}
