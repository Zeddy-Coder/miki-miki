import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miki_miki/services/orientation_policy.dart';

void main() {
  const landscape = [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight];
  const portrait = [DeviceOrientation.portraitUp];

  late List<List<DeviceOrientation>> applied;
  late PlayerOrientation pref;
  late OrientationPolicy policy;

  setUp(() {
    applied = [];
    pref = PlayerOrientation.system;
    policy = OrientationPolicy(
      apply: (o) async => applied.add(List.of(o)),
      preference: () => pref,
    );
  });

  test('«Як у системі»: орієнтацію не чіпаємо ні при вході, ні при виході', () {
    policy.enterPlayer();
    policy.leavePlayer();
    expect(applied, isEmpty);
    expect(policy.locked, isFalse);
  });

  test('«Альбомна»: при вході фіксується, при виході повертається автоповорот', () {
    pref = PlayerOrientation.landscape;
    policy.enterPlayer();
    expect(applied.last, landscape);
    expect(policy.locked, isTrue);
    policy.leavePlayer();
    expect(applied.last, isEmpty, reason: 'до плеєра був автоповорот');
    expect(policy.locked, isFalse);
  });

  test('«Портретна» діє так само', () {
    pref = PlayerOrientation.portrait;
    policy.enterPlayer();
    expect(applied.last, portrait);
    policy.leavePlayer();
    expect(applied.last, isEmpty);
  });

  test('згортання й повторне розгортання: орієнтація знову береться з налаштування', () {
    pref = PlayerOrientation.landscape;
    policy.enterPlayer();
    policy.leavePlayer();
    policy.enterPlayer();
    expect(applied.length, 3);
    expect(applied.last, landscape);
    policy.leavePlayer();
    expect(applied.length, 4);
  });

  test('повторні виклики входу / виходу нічого не дублюють', () {
    pref = PlayerOrientation.landscape;
    policy.enterPlayer();
    policy.enterPlayer();
    policy.leavePlayer();
    policy.leavePlayer();
    expect(applied.length, 2);
  });

  test('кнопка повороту всередині плеєра: при виході все одно повертається попередня орієнтація', () {
    policy.enterPlayer();
    policy.toggle(landscapeNow: false); // портрет → альбомна
    expect(applied.last, landscape);
    expect(policy.locked, isTrue);
    policy.leavePlayer();
    expect(applied.last, isEmpty);
    expect(policy.locked, isFalse);
  });

  test('кнопка повороту: альбомна → портрет', () {
    policy.enterPlayer();
    policy.toggle(landscapeNow: true);
    expect(applied.last, portrait);
  });

  test('довге утримування кнопки повертає автоповорот', () {
    pref = PlayerOrientation.landscape;
    policy.enterPlayer();
    policy.unlock();
    expect(applied.last, isEmpty);
    expect(policy.locked, isFalse);
    policy.unlock(); // вдруге нічого не робить
    expect(applied.length, 2);
  });

  test('налаштування змінили, поки плеєр відкритий', () {
    policy.enterPlayer();
    expect(applied, isEmpty);
    pref = PlayerOrientation.portrait;
    policy.preferenceChanged();
    expect(applied.last, portrait);
    pref = PlayerOrientation.system;
    policy.preferenceChanged();
    expect(applied.last, isEmpty, reason: '«Як у системі» повертає те, що було до плеєра');
    policy.leavePlayer();
  });

  test('зміна налаштування на головній нічого не робить', () {
    pref = PlayerOrientation.landscape;
    policy.preferenceChanged();
    expect(applied, isEmpty);
  });

  test('розбір збереженого значення', () {
    expect(PlayerOrientation.parse('landscape'), PlayerOrientation.landscape);
    expect(PlayerOrientation.parse('portrait'), PlayerOrientation.portrait);
    expect(PlayerOrientation.parse('щось'), PlayerOrientation.system);
    expect(PlayerOrientation.parse(null), PlayerOrientation.system);
  });
}
