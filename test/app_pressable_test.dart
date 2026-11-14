import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miki_miki/widgets/app_ui_kit.dart';

void main() {
  testWidgets('AppPressable: highlight shows while pressed and goes away after release', (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Center(child: AppPressable(onTap: () => taps++, child: const SizedBox(width: 80, height: 40))),
    ));
    double opacity() => tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity;
    expect(opacity(), 0);
    final g = await tester.startGesture(tester.getCenter(find.byType(AppPressable)));
    await tester.pump();
    expect(opacity(), 1);
    await g.up();
    await tester.pumpAndSettle();
    expect(opacity(), 0);
    expect(taps, 1);
  });
}
