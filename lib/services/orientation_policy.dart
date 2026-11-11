/// Орієнтація екрана телефона у плеєрі.
///
/// Налаштування «Орієнтація плеєра» задає, у якій орієнтації відкривається відео. Коли плеєр зникає з екрана
/// (вихід на головну або згортання в міні-плеєр), повертається та орієнтація, що була до його відкриття.
/// Логіка відокремлена від віджетів і `SystemChrome` (він передається ззовні), тож перевіряється тестами.
library;

import 'package:flutter/services.dart';

/// Яку орієнтацію вмикати при відкритті плеєра
enum PlayerOrientation {
  system('system', 'Як у системі'),
  landscape('landscape', 'Альбомна'),
  portrait('portrait', 'Портретна');

  final String id;
  final String label;
  const PlayerOrientation(this.id, this.label);

  static PlayerOrientation parse(String? id) =>
      PlayerOrientation.values.firstWhere((o) => o.id == id, orElse: () => PlayerOrientation.landscape);

  /// Дозволені орієнтації (`null` — нічого не змінювати)
  List<DeviceOrientation>? get orientations => switch (this) {
        PlayerOrientation.system => null,
        PlayerOrientation.landscape => const [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight],
        PlayerOrientation.portrait => const [DeviceOrientation.portraitUp],
      };
}

class OrientationPolicy {
  OrientationPolicy({required this.apply, required this.preference, this.log});

  /// Передає список дозволених орієнтацій системі (порожній — автоповорот за датчиком)
  final Future<void> Function(List<DeviceOrientation> orientations) apply;

  /// Поточне налаштування користувача
  final PlayerOrientation Function() preference;

  /// Запис у журнал (необовʼязково)
  final void Function(String message)? log;

  List<DeviceOrientation> _current = const [];
  bool _locked = false;
  bool _inPlayer = false;
  List<DeviceOrientation>? _saved;
  bool _savedLocked = false;

  /// Поворот зафіксовано (налаштуванням або кнопкою); інакше орієнтацію визначає датчик
  bool get locked => _locked;

  /// Плеєр зараз на екрані
  bool get inPlayer => _inPlayer;

  List<DeviceOrientation> get current => _current;

  /// Плеєр зʼявився на екрані: запамʼятовуємо поточну орієнтацію і вмикаємо ту, що задана в налаштуваннях
  void enterPlayer() {
    if (_inPlayer) return;
    _inPlayer = true;
    _saved = List<DeviceOrientation>.of(_current);
    _savedLocked = _locked;
    final want = preference().orientations;
    log?.call('плеєр відкрито; до цього: ${_describe(_current, _locked)}; налаштування: ${preference().label}');
    if (want != null) _set(want, locked: true);
  }

  /// Плеєр зник з екрана (вихід або згортання): повертаємо орієнтацію, що була до нього
  void leavePlayer() {
    if (!_inPlayer) return;
    _inPlayer = false;
    final saved = _saved;
    _saved = null;
    if (saved == null) return;
    if (!_same(saved, _current) || _locked != _savedLocked) {
      log?.call('плеєр закрито; повертаю: ${_describe(saved, _savedLocked)}');
      _set(saved, locked: _savedLocked);
    }
  }

  /// Налаштування змінили, поки плеєр відкритий
  void preferenceChanged() {
    if (!_inPlayer) return;
    final want = preference().orientations;
    if (want != null) {
      _set(want, locked: true);
    } else if (_saved != null) {
      _set(_saved!, locked: _savedLocked);
    }
  }

  /// Кнопка повороту: портрет ↔ альбомна (і фіксація вибору)
  void toggle({required bool landscapeNow}) {
    _set(
      landscapeNow
          ? const [DeviceOrientation.portraitUp]
          : const [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight],
      locked: true,
    );
  }

  /// Повертає автоповорот за датчиком
  void unlock() {
    if (!_locked) return;
    _set(const [], locked: false);
  }

  void _set(List<DeviceOrientation> orientations, {required bool locked}) {
    _current = orientations;
    _locked = locked;
    apply(orientations);
  }

  static bool _same(List<DeviceOrientation> a, List<DeviceOrientation> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static String _describe(List<DeviceOrientation> o, bool locked) {
    if (o.isEmpty) return 'автоповорот';
    return '${locked ? 'зафіксовано' : 'дозволено'}: ${o.map((e) => e.name).join('+')}';
  }
}
