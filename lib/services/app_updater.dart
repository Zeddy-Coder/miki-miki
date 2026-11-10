import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../constants/app_identity.dart';
import 'app_log.dart';
import 'storage_service.dart';

/// Нова версія з GitHub Releases
class UpdateInfo {
  final String version;
  final String notes;
  final String pageUrl;

  /// Прямий файл для цієї платформи (APK на Android, zip/exe на Windows); порожньо — лише сторінка релізу
  final String downloadUrl;
  final String assetName;
  final int size;

  const UpdateInfo({
    required this.version,
    required this.notes,
    required this.pageUrl,
    this.downloadUrl = '',
    this.assetName = '',
    this.size = 0,
  });

  /// Що відкривати користувачу: файл або, якщо його немає, сторінку релізу
  String get target => downloadUrl.isNotEmpty ? downloadUrl : pageUrl;

  Map<String, dynamic> toJson() =>
      {'version': version, 'notes': notes, 'page': pageUrl, 'url': downloadUrl, 'name': assetName, 'size': size};

  static UpdateInfo? fromJson(Object? j) {
    if (j is! Map) return null;
    final v = j['version'];
    final p = j['page'];
    if (v is! String || p is! String) return null;
    return UpdateInfo(
      version: v,
      notes: (j['notes'] as String?) ?? '',
      pageUrl: p,
      downloadUrl: (j['url'] as String?) ?? '',
      assetName: (j['name'] as String?) ?? '',
      size: (j['size'] as num?)?.toInt() ?? 0,
    );
  }
}

sealed class UpdateState {
  const UpdateState();
}

class UpdateIdle extends UpdateState {
  const UpdateIdle();
}

class UpdateChecking extends UpdateState {
  const UpdateChecking();
}

class UpdateUpToDate extends UpdateState {
  const UpdateUpToDate();
}

class UpdateAvailable extends UpdateState {
  final UpdateInfo info;
  const UpdateAvailable(this.info);
}

class UpdateFailed extends UpdateState {
  final String message;
  const UpdateFailed(this.message);
}

/// `(статус, тіло)` для GET; у тестах підміняється
typedef UpdateTransport = Future<(int, String)> Function(String url);

/// Перевіряє GitHub Releases на нову версію. Нічого не завантажує й не встановлює сам: показує, що є
/// новіша, а файл відкривається в браузері (на Android далі встановлює система).
class AppUpdater {
  static AppUpdater instance = AppUpdater();

  /// Репозиторій із релізами
  static const String repo = 'Zeddy-Coder/miki-miki';
  static const String section = 'updates';

  /// Не частіше, ніж раз на стільки, коли перевірка йде сама
  static const Duration autoEvery = Duration(hours: 12);

  final UpdateTransport _transport;
  final SectionLoader _load;
  final SectionSaver _save;
  final String currentVersion;
  final bool Function() _isAndroid;

  /// Поточний стан для інтерфейсу
  final ValueNotifier<UpdateState> state = ValueNotifier<UpdateState>(const UpdateIdle());

  late final Map<String, dynamic> _data = Map<String, dynamic>.of(_load());
  Future<void>? _running;

  AppUpdater({
    UpdateTransport? transport,
    SectionLoader? load,
    SectionSaver? save,
    String? currentVersion,
    bool Function()? isAndroid,
  })  : _transport = transport ?? _httpTransport,
        _load = load ?? (() => StorageService.getSection(section)),
        _save = save ?? ((d) => StorageService.saveSection(section, d)),
        currentVersion = currentVersion ?? AppIdentity.version,
        _isAndroid = isAndroid ?? (() => Platform.isAndroid) {
    // Знайдена раніше новіша версія видна одразу, ще до нової перевірки
    final saved = UpdateInfo.fromJson(_data['latest']);
    if (saved != null && compareVersions(saved.version, this.currentVersion) > 0) {
      state.value = UpdateAvailable(saved);
    }
  }

  static Future<(int, String)> _httpTransport(String url) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.getUrl(Uri.parse(url)).timeout(const Duration(seconds: 15));
      req.headers.set('Accept', 'application/vnd.github+json');
      req.headers.set('User-Agent', AppIdentity.userAgent('updates'));
      final res = await req.close().timeout(const Duration(seconds: 20));
      final text = await utf8.decodeStream(res).timeout(const Duration(seconds: 20));
      return (res.statusCode, text);
    } finally {
      client.close(force: true);
    }
  }

  /// Порівняння версій виду `1.2.3` (з необов'язковим `v`, без урахування сніпетів після `-`/`+`):
  /// додатне, якщо [a] новіша за [b]
  static int compareVersions(String a, String b) {
    List<int> parse(String s) {
      final core = s.trim().replaceFirst(RegExp(r'^[vV]'), '').split(RegExp(r'[-+]')).first;
      return core.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    }

    final x = parse(a);
    final y = parse(b);
    for (var i = 0; i < (x.length > y.length ? x.length : y.length); i++) {
      final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
      if (d != 0) return d;
    }
    return 0;
  }

  /// Вибирає файл релізу для платформи: APK (arm64 бажано) на Android, zip/exe/msix на Windows
  @visibleForTesting
  static Map<String, dynamic>? pickAsset(List<dynamic> assets, {required bool android}) {
    final list = assets.whereType<Map>().map((e) => e.cast<String, dynamic>()).where((a) => a['browser_download_url'] is String).toList();
    bool has(Map<String, dynamic> a, String s) => '${a['name']}'.toLowerCase().contains(s);
    bool ends(Map<String, dynamic> a, List<String> e) => e.any((x) => '${a['name']}'.toLowerCase().endsWith(x));
    if (android) {
      final apks = list.where((a) => ends(a, ['.apk'])).toList();
      if (apks.isEmpty) return null;
      return apks.firstWhere((a) => has(a, 'arm64'), orElse: () => apks.first);
    }
    final win = list.where((a) => ends(a, ['.zip', '.exe', '.msix']) && !has(a, 'android')).toList();
    if (win.isEmpty) return null;
    return win.firstWhere((a) => has(a, 'win'), orElse: () => win.first);
  }

  /// Перевіряє оновлення. `auto: true` — тиха перевірка, не частіше [autoEvery] і без показу помилок
  Future<void> check({bool auto = false}) {
    final running = _running;
    if (running != null) return running;
    if (auto) {
      final last = DateTime.tryParse('${_data['checkedAt'] ?? ''}');
      if (last != null && DateTime.now().difference(last) < autoEvery) return Future.value();
    }
    return _running = _run(auto).whenComplete(() => _running = null);
  }

  Future<void> _run(bool auto) async {
    final before = state.value;
    if (!auto) state.value = const UpdateChecking();
    try {
      final (status, body) = await _transport('https://api.github.com/repos/$repo/releases/latest');
      if (status == 404) {
        // Релізів ще немає: це не помилка
        _done(null);
        return;
      }
      if (status != 200) throw 'GitHub відповів $status';
      final j = jsonDecode(body);
      if (j is! Map) throw 'неочікувана відповідь';
      final tag = (j['tag_name'] as String?) ?? '';
      if (tag.isEmpty) throw 'у релізі немає версії';
      final asset = pickAsset((j['assets'] as List?) ?? const [], android: _isAndroid());
      final info = UpdateInfo(
        version: tag.replaceFirst(RegExp(r'^[vV]'), ''),
        notes: ((j['body'] as String?) ?? '').trim(),
        pageUrl: (j['html_url'] as String?) ?? 'https://github.com/$repo/releases',
        downloadUrl: (asset?['browser_download_url'] as String?) ?? '',
        assetName: (asset?['name'] as String?) ?? '',
        size: (asset?['size'] as num?)?.toInt() ?? 0,
      );
      _done(compareVersions(info.version, currentVersion) > 0 ? info : null);
    } catch (e) {
      AppLog.w('Updater', 'перевірка не вдалася: $e');
      // Тиха перевірка нічого не показує; ручна — повідомляє
      state.value = auto ? before : UpdateFailed('Не вдалося перевірити: ${e is SocketException ? 'немає мережі' : e}');
    }
  }

  void _done(UpdateInfo? info) {
    _data['checkedAt'] = DateTime.now().toIso8601String();
    if (info == null) {
      _data.remove('latest');
    } else {
      _data['latest'] = info.toJson();
    }
    try {
      _save(_data);
    } catch (_) {}
    state.value = info == null ? const UpdateUpToDate() : UpdateAvailable(info);
  }
}
