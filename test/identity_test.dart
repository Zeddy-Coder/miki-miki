import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:miki_miki/constants/app_identity.dart';

void main() {
  group('Назва й ідентифікатори', () {
    test('назва для людей і технічні імена узгоджені', () {
      expect(AppIdentity.name, 'Miki Miki');
      expect(AppIdentity.packageName, 'miki_miki');
      expect(AppIdentity.dataDirName, isNot(AppIdentity.legacyDataDirName));
      expect(AppIdentity.userAgent('тест'), startsWith('MikiMiki/'));
      expect(AppIdentity.userAgent('тест'), contains('(Flutter; тест)'));
    });
  });

  group('Перенос даних зі старої теки', () {
    late Directory root;
    setUp(() => root = Directory.systemTemp.createTempSync('identity_test_'));
    tearDown(() => root.deleteSync(recursive: true));

    test('стара тека переїжджає цілком, разом із вкладеними файлами', () async {
      final legacy = Directory('${root.path}/${AppIdentity.legacyDataDirName}')..createSync();
      File('${legacy.path}/app_state.json').writeAsStringSync('{"a":1}');
      Directory('${legacy.path}/logs').createSync();
      File('${legacy.path}/logs/my_player_20200101_000000.log').writeAsStringSync('рядок');
      final current = Directory('${root.path}/${AppIdentity.dataDirName}');

      expect(await AppIdentity.migrateLegacyData(legacy, current), isTrue);

      expect(File('${current.path}/app_state.json').readAsStringSync(), '{"a":1}');
      expect(File('${current.path}/logs/my_player_20200101_000000.log').readAsStringSync(), 'рядок');
      expect(legacy.existsSync(), isFalse);
    });

    test('нова тека вже є — стара не чіпається, дані не перезаписуються', () async {
      final legacy = Directory('${root.path}/old')..createSync();
      File('${legacy.path}/app_state.json').writeAsStringSync('старе');
      final current = Directory('${root.path}/new')..createSync();
      File('${current.path}/app_state.json').writeAsStringSync('нове');

      expect(await AppIdentity.migrateLegacyData(legacy, current), isFalse);

      expect(File('${current.path}/app_state.json').readAsStringSync(), 'нове');
      expect(File('${legacy.path}/app_state.json').readAsStringSync(), 'старе');
    });

    test('старої теки немає — нічого не робиться й не падає', () async {
      final r = await AppIdentity.migrateLegacyData(Directory('${root.path}/немає'), Directory('${root.path}/нова'));
      expect(r, isFalse);
      expect(Directory('${root.path}/нова').existsSync(), isFalse);
    });
  });
}
