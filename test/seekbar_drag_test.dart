import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:miki_miki/widgets/app_dock_widgets.dart';

import 'support/fakes.dart';

void main() {
  // Шрифт тестового середовища ширший за справжній — переповнення підказки не стосується перевірки жесту
  Future<void> pumpMs(WidgetTester tester, int ms) async {
    await tester.pump(Duration(milliseconds: ms));
    final e = tester.takeException();
    if (e != null && !e.toString().contains('overflowed')) throw e;
  }

  Future<void> mount(WidgetTester tester, FakePlayer p, List<bool> events, {bool live = true}) {
    return tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 400,
            child: AppSeekBar(
              scale: 1.45,
              hitHeight: 48,
              player: p,
              chapters: const [],
              live: live,
              onDragChanged: events.add,
            ),
          ),
        ),
      ),
    ));
  }

  testWidgets('повзунок: перетягування не зависає, іде за пальцем і завершується перемоткою', (tester) async {
    final p = FakePlayer()..current = FakePlayer().current.copyWith(playlist: Playlist([Media('https://example.com/ep.m3u8')]));
    final events = <bool>[];
    await mount(tester, p, events);
    final rect = tester.getRect(find.byType(AppSeekBar));
    final g = await tester.startGesture(Offset(rect.left + 40, rect.center.dy));
    await pumpMs(tester, 50);
    expect(events, [true]);
    // довге перетягування (понад 4 с автоприховування) з багатьма кроками
    for (var i = 1; i <= 40; i++) {
      await g.moveTo(Offset(rect.left + 40 + i * 7.0, rect.center.dy));
      await pumpMs(tester, 120);
    }
    expect(events, [true], reason: 'жест не скасовується посеред перетягування');
    // панель «ховається» посеред жесту (live=false) — перетягування триває
    await mount(tester, p, events, live: false);
    await g.moveTo(Offset(rect.left + 360, rect.center.dy));
    await pumpMs(tester, 120);
    expect(events, [true]);
    await g.up();
    await pumpMs(tester, 50);
    expect(events, [true, false]);
    final last = p.seeks.last;
    // 360/400 від 90 хв ≈ 81 хв
    expect(last.inMinutes, inInclusiveRange(79, 83));
  });

  testWidgets('повзунок: другий і наступні дотики працюють так само', (tester) async {
    final p = FakePlayer()..current = FakePlayer().current.copyWith(playlist: Playlist([Media('https://example.com/ep.m3u8')]));
    final events = <bool>[];
    await mount(tester, p, events);
    final rect = tester.getRect(find.byType(AppSeekBar));
    for (var round = 0; round < 3; round++) {
      final g = await tester.startGesture(Offset(rect.left + 50, rect.center.dy));
      await pumpMs(tester, 30);
      for (var i = 1; i <= 10; i++) {
        await g.moveTo(Offset(rect.left + 50 + i * 20.0, rect.center.dy));
        await pumpMs(tester, 40);
      }
      await g.up();
      await pumpMs(tester, 30);
      expect(p.seeks.last.inMinutes, inInclusiveRange(55, 58), reason: 'коло $round');
    }
    expect(events, [true, false, true, false, true, false]);
  });
}
