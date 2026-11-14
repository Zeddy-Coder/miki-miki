import 'package:flutter/foundation.dart';

import '../models/hikka_models.dart';
import 'hikka_api.dart';

/// Paged list loading (catalog, characters, calendar): accumulates items, loads
/// the next page on demand and discards responses that arrive late after the search conditions change.
class HikkaPager<T> extends ChangeNotifier {
  final Future<HikkaPage<T>> Function(int page) _fetch;

  /// Do not treat items as identical if the same one appeared on different pages (a shift when
  /// new records are inserted on the server): the item key
  final Object Function(T item)? keyOf;

  List<T> _items = const [];
  int _page = 0;
  bool _hasMore = true;
  bool _loading = false;
  bool _disposed = false;
  Object? _error;
  int _total = 0;
  int _generation = 0;

  HikkaPager(this._fetch, {this.keyOf});

  List<T> get items => _items;
  bool get hasMore => _hasMore;
  bool get loading => _loading;

  /// Error of the last load (null means all is well)
  Object? get error => _error;
  int get total => _total;

  /// No pages loaded yet
  bool get isFresh => _page == 0 && !_loading && _error == null;

  /// The first load is still in progress and nothing is shown
  bool get isInitialLoading => _loading && _items.isEmpty;

  /// Loading finished but there is nothing
  bool get isEmpty => !_loading && _error == null && _items.isEmpty && _page > 0;

  /// Resets the list and loads the first page
  Future<void> reload() {
    _generation++;
    _items = const [];
    _page = 0;
    _hasMore = true;
    _error = null;
    _total = 0;
    _loading = false;
    return loadMore();
  }

  /// Loads the next page; does nothing if it is already loading or the pages have ended
  Future<void> loadMore() async {
    if (_loading || !_hasMore || _disposed) return;
    final gen = _generation;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final page = await _fetch(_page + 1);
      if (gen != _generation || _disposed) return;
      final merged = List<T>.of(_items);
      if (keyOf == null) {
        merged.addAll(page.items);
      } else {
        final seen = {for (final e in merged) keyOf!(e)};
        for (final e in page.items) {
          if (seen.add(keyOf!(e))) merged.add(e);
        }
      }
      _items = merged;
      _page = page.page > _page ? page.page : _page + 1;
      _hasMore = page.hasMore && page.items.isNotEmpty;
      _total = page.total;
    } catch (e) {
      if (gen != _generation || _disposed) return;
      _error = e;
    } finally {
      if (gen == _generation && !_disposed) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  /// Retry after an error
  Future<void> retry() {
    _error = null;
    return loadMore();
  }

  /// Error text for the user
  String? get errorMessage {
    final e = _error;
    if (e == null) return null;
    return e is HikkaException ? e.message : 'Не вдалося завантажити. Спробуйте ще раз.';
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
