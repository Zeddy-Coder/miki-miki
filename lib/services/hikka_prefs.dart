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
  bool _showSecondary;
  HikkaTitleLang _secondaryLang;

  HikkaPrefs({HikkaTitleLang? titleLang, bool? allowAdult, bool? showSecondary, HikkaTitleLang? secondaryLang})
      : _titleLang = titleLang ?? HikkaTitleLang.fromName(StorageService.getHikkaTitleLang()),
        _allowAdult = allowAdult ?? StorageService.getHikkaAllowAdult(),
        _showSecondary = showSecondary ?? StorageService.getHikkaShowSecondary(),
        _secondaryLang = secondaryLang ?? HikkaTitleLang.fromName(StorageService.getHikkaSecondaryLang());

  HikkaTitleLang get titleLang => _titleLang;
  bool get allowAdult => _allowAdult;

  /// Другорядна назва на сторінці тайтла: чи показувати і якою мовою
  bool get showSecondary => _showSecondary;
  HikkaTitleLang get secondaryLang => _secondaryLang;

  set showSecondary(bool value) {
    if (value == _showSecondary) return;
    _showSecondary = value;
    StorageService.saveHikkaShowSecondary(value);
    notifyListeners();
  }

  set secondaryLang(HikkaTitleLang value) {
    if (value == _secondaryLang) return;
    _secondaryLang = value;
    StorageService.saveHikkaSecondaryLang(value.name);
    notifyListeners();
  }

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
