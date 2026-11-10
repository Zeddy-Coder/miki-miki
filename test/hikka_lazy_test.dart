import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miki_miki/widgets/hikka/hikka_page_kit.dart';

void main() {
  testWidgets('HikkaLazy будує секцію лише біля видимої частини й лишає її', (tester) async {
    var built = 0;
    final controller = ScrollController();
    await tester.pumpWidget(MaterialApp(
      home: SingleChildScrollView(
        controller: controller,
        child: Column(children: [
          const SizedBox(height: 4000),
          HikkaLazy(
            height: 200,
            builder: (_) {
              built++;
              return const SizedBox(height: 200, child: Text('нижня полиця'));
            },
          ),
          const SizedBox(height: 600),
        ]),
      ),
    ));
    await tester.pump();
    await tester.pump();
    expect(built, 0, reason: 'далеко за екраном — не будується');
    expect(find.text('нижня полиця'), findsNothing);

    controller.jumpTo(2500);
    await tester.pump();
    await tester.pump();
    expect(built, 0, reason: 'ще далі, ніж запас');

    controller.jumpTo(3500);
    await tester.pump();
    await tester.pump();
    expect(built, greaterThan(0));
    expect(find.text('нижня полиця'), findsOneWidget);

    final after = built;
    controller.jumpTo(0);
    await tester.pump();
    await tester.pump();
    expect(find.text('нижня полиця'), findsOneWidget, reason: 'раз змонтована — лишається');
    expect(built, greaterThanOrEqualTo(after));
  });

  testWidgets('HikkaLazy: секція, що вже на екрані, будується одразу', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SingleChildScrollView(child: Column(children: [HikkaLazy(height: 100, builder: (_) => const Text('одразу'))])),
    ));
    await tester.pump();
    await tester.pump();
    expect(find.text('одразу'), findsOneWidget);
  });
}
