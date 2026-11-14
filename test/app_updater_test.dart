import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:miki_miki/services/app_updater.dart';

String release(String tag, {List<Map<String, Object?>> assets = const []}) => jsonEncode({
      'tag_name': tag,
      'body': 'Що нового',
      'html_url': 'https://github.com/Zeddy-Coder/miki-miki/releases/tag/$tag',
      'assets': assets,
    });

Map<String, Object?> asset(String name, [int size = 1000]) =>
    {'name': name, 'size': size, 'browser_download_url': 'https://dl/$name'};

AppUpdater make(Future<(int, String)> Function(String) t, {String v = '1.1.0', bool android = true, Map<String, dynamic>? store}) {
  final saved = store ?? <String, dynamic>{};
  return AppUpdater(transport: t, load: () => saved, save: (d) => saved..clear()..addAll(d), currentVersion: v, isAndroid: () => android);
}

void main() {
  test('порівняння версій', () {
    expect(AppUpdater.compareVersions('1.2.0', '1.1.9') > 0, true);
    expect(AppUpdater.compareVersions('v1.10.0', '1.9.0') > 0, true);
    expect(AppUpdater.compareVersions('1.1', '1.1.0'), 0);
    expect(AppUpdater.compareVersions('1.0.9', '1.1.0') < 0, true);
    expect(AppUpdater.compareVersions('1.2.0-beta', '1.2.0'), 0);
  });

  test('вибір файлу: Android бере arm64 apk, Windows — zip', () {
    final a = [asset('notes.txt'), asset('miki_miki-v1.2.0-win.zip'), asset('miki_miki-v1.2.0-x86.apk'), asset('miki_miki-v1.2.0-arm64.apk')];
    expect(AppUpdater.pickAsset(a, android: true)!['name'], 'miki_miki-v1.2.0-arm64.apk');
    expect(AppUpdater.pickAsset(a, android: false)!['name'], 'miki_miki-v1.2.0-win.zip');
    expect(AppUpdater.pickAsset([asset('a.txt')], android: true), isNull);
  });

  test('знаходить новішу версію й зберігає її', () async {
    final store = <String, dynamic>{};
    final u = make((_) async => (200, release('v1.2.0', assets: [asset('m-arm64.apk', 5000)])), store: store);
    await u.check();
    final st = u.state.value as UpdateAvailable;
    expect(st.info.version, '1.2.0');
    expect(st.info.target, 'https://dl/m-arm64.apk');
    expect(st.info.size, 5000);
    // Після перезапуску стан відновлюється без мережі
    final again = make((_) async => throw 'no net', store: store);
    expect(again.state.value, isA<UpdateAvailable>());
  });

  test('та сама версія — актуально; без файлу відкривається сторінка релізу', () async {
    final same = make((_) async => (200, release('v1.1.0')));
    await same.check();
    expect(same.state.value, isA<UpdateUpToDate>());
    final noAsset = make((_) async => (200, release('v1.3.0')));
    await noAsset.check();
    final info = (noAsset.state.value as UpdateAvailable).info;
    expect(info.downloadUrl, '');
    expect(info.target, contains('/releases/tag/v1.3.0'));
  });

  test('немає релізів (404) — не помилка', () async {
    final u = make((_) async => (404, '{}'));
    await u.check();
    expect(u.state.value, isA<UpdateUpToDate>());
  });

  test('помилка: ручна показує, тиха мовчить', () async {
    final manual = make((_) async => (500, ''));
    await manual.check();
    expect(manual.state.value, isA<UpdateFailed>());
    final quiet = make((_) async => (500, ''));
    await quiet.check(auto: true);
    expect(quiet.state.value, isA<UpdateIdle>());
  });

  test('тиха перевірка не частіше, ніж раз на 12 годин; ручна завжди', () async {
    var calls = 0;
    final store = <String, dynamic>{};
    final u = make((_) async {
      calls++;
      return (200, release('v1.1.0'));
    }, store: store);
    await u.check(auto: true);
    await u.check(auto: true);
    expect(calls, 1);
    await u.check();
    expect(calls, 2);
  });

  test('вікно оновлення: пропущену версію більше не пропонує, а новішу — так', () async {
    final store = <String, dynamic>{};
    final u = make((_) async => (200, release('v1.2.0')), store: store);
    await u.check();
    final info = (u.state.value as UpdateAvailable).info;
    expect(u.shouldPrompt(info), isTrue);
    u.skip('1.2.0');
    expect(u.shouldPrompt(info), isFalse);
    // Пропуск переживає перезапуск
    expect(make((_) async => throw 'x', store: store).shouldPrompt(info), isFalse);
    expect(u.shouldPrompt(const UpdateInfo(version: '1.3.0', notes: '', pageUrl: 'p')), isTrue, reason: 'ще новіша версія знову пропонується');
    expect(u.shouldPrompt(const UpdateInfo(version: '1.1.0', notes: '', pageUrl: 'p')), isFalse, reason: 'не новіша за поточну');
  });
}
