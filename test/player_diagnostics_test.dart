import 'package:flutter_test/flutter_test.dart';
import 'package:miki_miki/services/player_diagnostics.dart';

SyncSnapshot snap(
  int sec, {
  int posMs = 0,
  bool playing = true,
  bool buffering = false,
  double rate = 1.0,
  double? avsync = 0.0,
  int drops = 0,
  int dec = 0,
  int vo = 0,
}) {
  return SyncSnapshot(
    at: DateTime(2026, 11, 3, 12, 0, sec),
    position: Duration(milliseconds: posMs),
    playing: playing,
    buffering: buffering,
    rate: rate,
    avsync: avsync,
    drops: drops,
    decoderDrops: dec,
    voDrops: vo,
  );
}

void main() {
  test('нормальне відтворення — без попереджень', () {
    final a = snap(0, posMs: 10000);
    final b = snap(3, posMs: 13000, avsync: 0.02);
    expect(analyzeSync(a, b), isEmpty);
    expect(analyzeSync(null, b), isEmpty);
  });

  test('розбіжність A/V понад 0,1 с', () {
    final w = analyzeSync(null, snap(3, avsync: 0.25));
    expect(w.single, contains('+0.250'));
    expect(analyzeSync(null, snap(3, avsync: -0.4)).single, contains('-0.400'));
    expect(analyzeSync(null, snap(3, avsync: 0.09)), isEmpty);
  });

  test('на паузі й під час буферизації розбіжність не лічиться', () {
    expect(analyzeSync(null, snap(3, avsync: 0.5, playing: false)), isEmpty);
    expect(analyzeSync(null, snap(3, avsync: 0.5, buffering: true)), isEmpty);
  });

  test('різке зростання втрачених кадрів', () {
    final a = snap(0, posMs: 0, drops: 2);
    final b = snap(3, posMs: 3000, drops: 40, dec: 5, vo: 33);
    final w = analyzeSync(a, b);
    expect(w.single, contains('+38'));
    expect(w.single, contains('декодер +5'));
    expect(w.single, contains('вивід +33'));
    expect(analyzeSync(a, snap(3, posMs: 3000, drops: 7)), isEmpty);
  });

  test('позиція стоїть без буферизації', () {
    final w = analyzeSync(snap(0, posMs: 5000), snap(3, posMs: 5000));
    expect(w.single, contains('не рухається'));
    // а при буферизації — це нормально
    expect(analyzeSync(snap(0, posMs: 5000), snap(3, posMs: 5000, buffering: true)), isEmpty);
    // і на паузі
    expect(analyzeSync(snap(0, posMs: 5000, playing: false), snap(3, posMs: 5000, playing: false)), isEmpty);
  });

  test('відтворення відстає від годинника', () {
    final w = analyzeSync(snap(0, posMs: 0), snap(3, posMs: 1500));
    expect(w.single, contains('×0.50'));
  });

  test('швидкість відтворення враховується', () {
    // ×2: за 3 с позиція має зрости на 6 с
    expect(analyzeSync(snap(0, posMs: 0, rate: 2), snap(3, posMs: 6000, rate: 2)), isEmpty);
  });

  test('перемотка вперед не вважається збоєм', () {
    expect(analyzeSync(snap(0, posMs: 0), snap(3, posMs: 600000)), isEmpty);
  });
}
