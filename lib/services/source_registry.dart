/// Реєстр джерел перегляду: які є, які ввімкнені. Усі джерела ходять в мережу через спільний `SourceHttp`
/// (спільні куки — після проходження перевірки Cloudflare вона діє для всіх запитів до сайту).
library;

import 'package:flutter/foundation.dart';

import 'source_prefs.dart';
import 'sources/anime_source.dart';
import 'sources/source_http.dart';
import 'sources/ua/mikai_source.dart';

class SourceRegistry extends ChangeNotifier {
  final SourcePrefs prefs;
  final SourceHttp http;
  final List<AnimeSource> all;

  SourceRegistry({List<AnimeSource>? sources, SourcePrefs? prefs, SourceHttp? http})
      : prefs = prefs ?? SourcePrefs.instance,
        http = http ?? SourceHttp(),
        all = List.unmodifiable(sources ?? const []) {
    this.prefs.addListener(_onPrefs);
  }

  /// Стандартний набір: Mikai (UFDub і UAKino прибрано: не працюють)
  factory SourceRegistry.standard({SourcePrefs? prefs, SourceHttp? http}) {
    final p = prefs ?? SourcePrefs.instance;
    final h = http ?? SourceHttp();
    final key = p.mikaiKey;
    return SourceRegistry(
      prefs: p,
      http: h,
      sources: [
        MikaiSource(http: h, apiKey: key.isEmpty ? null : key),
      ],
    );
  }

  static SourceRegistry instance = SourceRegistry.standard();

  void _onPrefs() {
    final m = mikai;
    if (m != null) {
      final key = prefs.mikaiKey;
      m.apiKey = key.isEmpty ? null : key;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    prefs.removeListener(_onPrefs);
    super.dispose();
  }

  AnimeSource? byId(String id) {
    for (final s in all) {
      if (s.id == id) return s;
    }
    return null;
  }

  MikaiSource? get mikai => byId('mikai') is MikaiSource ? byId('mikai') as MikaiSource : null;

  bool isEnabled(AnimeSource s) => prefs.isEnabled(s.id);

  List<AnimeSource> get enabled => [for (final s in all) if (prefs.isEnabled(s.id)) s];
}
