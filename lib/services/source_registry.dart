/// Watch-source registry: which exist, which are enabled. All sources go to the network through the shared `SourceHttp`
/// (shared cookies: once the Cloudflare check is passed it applies to all requests to the site).
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

  /// Standard set: Mikai (UFDub and UAKino removed: they do not work)
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

  /// The only source (currently Mikai) cannot be disabled: there is then no site switcher
  bool isEnabled(AnimeSource s) => all.length <= 1 || prefs.isEnabled(s.id);

  List<AnimeSource> get enabled => [for (final s in all) if (isEnabled(s)) s];
}
