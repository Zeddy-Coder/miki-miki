import 'package:flutter/foundation.dart';

import '../models/hikka_models.dart';
import 'storage_service.dart';

/// Hikka catalog settings: title language and showing 18+ content (off by default).
/// Stored in `app_state.json` together with the rest of the settings.
class HikkaPrefs extends ChangeNotifier {
  /// Shared instance (replaced in tests)
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

  /// Re-reads everything from the store (after settings arrive from another device)
  void reload() {
    _titleLang = HikkaTitleLang.fromName(StorageService.getHikkaTitleLang());
    _allowAdult = StorageService.getHikkaAllowAdult();
    _showSecondary = StorageService.getHikkaShowSecondary();
    _secondaryLang = HikkaTitleLang.fromName(StorageService.getHikkaSecondaryLang());
    notifyListeners();
  }

  HikkaTitleLang get titleLang => _titleLang;
  bool get allowAdult => _allowAdult;

  /// Secondary title on the title page: whether to show it and in which language
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
