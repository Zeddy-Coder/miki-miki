import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miki_miki/widgets/app_ui_kit.dart';

void main() {
  testWidgets('після оновлення потягом горизонтальні каруселі прокручуються так само, як і до нього', (tester) async {
    final horizontal = ScrollController();
    final done = Completer<void>();
    late StateSetter rebuild;
    var generation = 0;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(builder: (context, setState) {
          rebuild = setState;
          return AppPullToRefresh(
            onRefresh: () => done.future,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: 160,
                  // Нова карусель при кожному «оновленні даних» (як на головній)
                  child: ListView.builder(
                    key: ValueKey('carousel-$generation'),
                    controller: generation == 0 ? horizontal : null,
                    scrollDirection: Axis.horizontal,
                    itemCount: 20,
                    itemBuilder: (_, i) => SizedBox(width: 120, child: Text('item $i')),
                  ),
                ),
                for (var i = 0; i < 20; i++) SizedBox(height: 80, child: Text('row $i')),
              ],
            ),
          );
        }),
      ),
    ));

    // Потяг униз від верху запускає оновлення
    final pull = await tester.startGesture(const Offset(300, 400));
    for (var i = 0; i < 12; i++) {
      await pull.moveBy(const Offset(0, 14));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await pull.up();
    await tester.pump(const Duration(milliseconds: 50));

    // Оновлення триває, дані перемалювалися — нова карусель
    rebuild(() => generation++);
    await tester.pump();
    done.complete();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    final carousel = find.byKey(const ValueKey('carousel-1'));
    final before = tester.state<ScrollableState>(find.descendant(of: carousel, matching: find.byType(Scrollable))).position.pixels;
    await tester.drag(carousel, const Offset(-300, 0));
    await tester.pump(const Duration(milliseconds: 300));
    final after = tester.state<ScrollableState>(find.descendant(of: carousel, matching: find.byType(Scrollable))).position.pixels;
    expect(after, greaterThan(before + 100), reason: 'карусель реагує на горизонтальний жест');
  });
}
