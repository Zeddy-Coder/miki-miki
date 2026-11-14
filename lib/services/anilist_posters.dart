/// Posters from AniList. Hikka serves posters from MAL, often small and with chunks of text, while AniList has large covers
/// (`coverImage.extraLarge`). The address is looked up by MAL id in one request for several titles; the result (and "none there")
/// is cached on disk, so repeated launches ask nothing.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'app_log.dart';
import 'banner_art.dart' show JsonFetcher, ioJsonFetch;
import 'storage_service.dart';

class AniListPosters extends ChangeNotifier {
  static AniListPosters instance = AniListPosters();

  static final Uri endpoint = Uri.parse('https://graphql.anilist.co');
  static const int maxPerRequest = 50;
  static const String _section = 'anilist_posters';
  static const String query = r'query($ids:[Int]){Page(perPage:50){media(idMal_in:$ids,type:ANIME){idMal coverImage{extraLarge large}}}}';

  final JsonFetcher _fetch;
  final bool enabled;

  AniListPosters({JsonFetcher? fetch, bool? enabled})
      : _fetch = fetch ?? ioJsonFetch,
        enabled = enabled ?? !Platform.environment.containsKey('FLUTTER_TEST');

  /// MAL id → address ('' means AniList has no poster or the request failed)
  final Map<int, String> _mem = {};
  final Set<int> _queued = {};
  final Set<int> _inFlight = {};
  bool _loaded = false;
  bool _scheduled = false;

  void _loadDisk() {
    if (_loaded) return;
    _loaded = true;
    StorageService.getSection(_section).forEach((k, v) {
      final id = int.tryParse(k);
      if (id != null && v is String) _mem[id] = v;
    });
  }

  /// Poster address: a string (empty means none, the Hikka poster stays) or `null` while still being looked up
  String? lookup(int malId) {
    if (!enabled || malId <= 0) return '';
    _loadDisk();
    final known = _mem[malId];
    if (known != null) return known;
    if (!_inFlight.contains(malId) && _queued.add(malId) && !_scheduled) {
      _scheduled = true;
      // All posters of one frame are gathered into one request
      scheduleMicrotask(_flush);
    }
    return null;
  }

  Future<void> _flush() async {
    _scheduled = false;
    final ids = _queued.toList();
    _queued.clear();
    _inFlight.addAll(ids);
    for (var i = 0; i < ids.length; i += maxPerRequest) {
      final chunk = ids.sublist(i, i + maxPerRequest > ids.length ? ids.length : i + maxPerRequest);
      Map<int, String>? found;
      try {
        final json = await _fetch('POST', endpoint, body: {'query': query, 'variables': {'ids': chunk}}, headers: const {'Accept': 'application/json'});
        found = parse(json);
      } catch (e) {
        AppLog.w('постери', 'AniList не відповів: $e');
      }
      for (final id in chunk) {
        _inFlight.remove(id);
        if (found == null) {
          // The request failed: this run keeps the Hikka poster and nothing is written to disk so we can try again later
          _mem[id] = '';
        } else {
          _mem[id] = found[id] ?? '';
        }
      }
      if (found != null) _persist(chunk);
      notifyListeners();
    }
  }

  void _persist(List<int> ids) {
    final section = Map<String, dynamic>.from(StorageService.getSection(_section));
    for (final id in ids) {
      section['$id'] = _mem[id] ?? '';
    }
    StorageService.saveSection(_section, section);
  }

  static Map<int, String> parse(Object? json) {
    final out = <int, String>{};
    if (json is! Map) return out;
    final data = json['data'];
    final page = data is Map ? data['Page'] : null;
    final media = page is Map ? page['media'] : null;
    if (media is! List) return out;
    for (final m in media) {
      if (m is! Map) continue;
      final id = m['idMal'];
      final cover = m['coverImage'];
      if (id is! num || cover is! Map) continue;
      final url = cover['extraLarge'] ?? cover['large'];
      if (url is String && url.startsWith('http')) out[id.toInt()] = url;
    }
    return out;
  }
}
