import 'package:flutter/foundation.dart';

import '../models/hikka_models.dart';
import 'hikka_api.dart';

/// Постраничне завантаження списку (каталог, персонажі, календар): накопичує елементи, підвантажує
/// наступну сторінку на вимогу й відкидає відповіді, що спізнилися після зміни умов пошуку.
class HikkaPager<T> extends ChangeNotifier {
  final Future<HikkaPage<T>> Function(int page) _fetch;

  /// Не вважати елементи однаковими, якщо в різних сторінках трапився один і той самий (зсув при вставці
  /// нових записів на сервері): ключ елемента
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

  /// Помилка останнього завантаження (null — усе гаразд)
  Object? get error => _error;
  int get total => _total;

  /// Сторінок ще не завантажували
  bool get isFresh => _page == 0 && !_loading && _error == null;

  /// Перше завантаження ще триває й нічого не показано
  bool get isInitialLoading => _loading && _items.isEmpty;

  /// Завантаження закінчилось, але нічого немає
  bool get isEmpty => !_loading && _error == null && _items.isEmpty && _page > 0;

  /// Скидає список і вантажить першу сторінку
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

  /// Підвантажує наступну сторінку; нічого не робить, якщо вона вже вантажиться або сторінки скінчились
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

  /// Повторити після помилки
  Future<void> retry() {
    _error = null;
    return loadMore();
  }

  /// Текст помилки для користувача
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
