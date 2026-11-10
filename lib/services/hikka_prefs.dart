import 'package:flutter/foundation.dart';

import '../models/hikka_models.dart';
import 'storage_service.dart';

/// Налаштування каталогу Hikka: мова назв і показ контенту 18+ (за замовчуванням вимкнений).
/// Зберігаються в `app_state.json` разом з рештою налаштувань.
class HikkaPrefs extends ChangeNotifier {
  /// Спільний екземпляр (у тестах підміняється)
  static HikkaPrefs instance = HikkaPrefs();

  HikkaTitleLang _titleLang;
  bool _allowAdult;

  HikkaPrefs({HikkaTitleLang? titleLang, bool? allowAdult})
      : _titleLang = titleLang ?? HikkaTitleLang.fromName(StorageService.getHikkaTitleLang()),
        _allowAdult = allowAdult ?? StorageService.getHikkaAllowAdult();

  HikkaTitleLang get titleLang => _titleLang;
  bool get allowAdult => _allowAdult;

  set titleLang(HikkaTitleLang value) {
    if (value == _titleLang) return;
    _titleLang = value;
    StorageService.saveHikkaTitleLang(value.name);
    notifyListeners();
  }

  set allowAdult(bool value) {
    if (value == _allowAdult) return;
    _allowAdult = value;
    StorageService.saveHikkaAllowAdult(value);
    notifyListeners();
  }
}
