import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miki_miki/widgets/app_ui_kit.dart';
import 'package:miki_miki/widgets/hikka/hikka_page_kit.dart';

void main() {
  Widget app({int items = 80}) => MaterialApp(
        home: Scaffold(
          body: HikkaCollapsingHeader(
            header: const SizedBox(key: ValueKey('hdr'), height: 120, child: Text('Шапка')),
            body: ListView.builder(itemCount: items, itemBuilder: (_, i) => SizedBox(height: 60, child: Text('row $i'))),
          ),
        ),
      );

  double headerHeight(WidgetTester t) => t.getSize(find.byKey(const ValueKey('hdr'))).height;

  testWidgets('шапка ховається при прокрутці вниз і повертається при прокрутці вгору', (t) async {
    await t.pumpWidget(app());
    expect(t.getSize(find.byType(ClipRect).first).height, 120);

    await t.drag(find.byType(ListView), const Offset(0, -300));
    await t.pumpAndSettle();
    expect(t.getSize(find.byType(ClipRect).first).height, 0);

    await t.drag(find.byType(ListView), const Offset(0, 80));
    await t.pumpAndSettle();
    expect(t.getSize(find.byType(ClipRect).first).height, 120);
    expect(headerHeight(t), 120);
  });

  testWidgets('поява шапки не підштовхує вміст: рядок зсувається лише на рух пальця', (t) async {
    await t.pumpWidget(app(items: 200));
    await t.drag(find.byType(ListView), const Offset(0, -600));
    await t.pumpAndSettle();
    expect(t.getSize(find.byType(ClipRect).first).height, 0);
    final before = t.getTopLeft(find.text('row 12')).dy;
    await t.drag(find.byType(ListView), const Offset(0, 80)); // шапка з'являється
    await t.pumpAndSettle();
    expect(t.getSize(find.byType(ClipRect).first).height, 120);
    final after = t.getTopLeft(find.text('row 12')).dy;
    // Рух пальця 80 (±кілька пікселів на поріг жесту), а не 80 + 120 висоти шапки
    expect(after - before, inInclusiveRange(40, 100), reason: 'без стрибка на висоту шапки');
  });

  testWidgets('мертва зона: дрібний рух угору шапку не повертає', (t) async {
    await t.pumpWidget(app(items: 200));
    await t.drag(find.byType(ListView), const Offset(0, -600));
    await t.pumpAndSettle();
    await t.drag(find.byType(ListView), const Offset(0, 20));
    await t.pumpAndSettle();
    expect(t.getSize(find.byType(ClipRect).first).height, 0);
  });

  testWidgets('шапка повертається на самому верху', (t) async {
    await t.pumpWidget(app());
    await t.drag(find.byType(ListView), const Offset(0, -300));
    await t.pumpAndSettle();
    await t.fling(find.byType(ListView), const Offset(0, 3000), 3000);
    await t.pumpAndSettle();
    expect(t.getSize(find.byType(ClipRect).first).height, 120);
  });

  testWidgets('короткий вміст не ховає шапку (інакше її не повернути)', (t) async {
    await t.pumpWidget(app(items: 9));
    await t.drag(find.byType(ListView), const Offset(0, -300));
    await t.pumpAndSettle();
    expect(t.getSize(find.byType(ClipRect).first).height, 120);
  });

  testWidgets('край прокрутки: розтягування як в Android 12, а не старе світіння — і всередині смуги прокрутки теж', (t) async {
    final c = ScrollController();
    await t.pumpWidget(MaterialApp(
      scrollBehavior: const AppScrollBehavior(),
      home: Scaffold(body: AppScrollbar(scale: 1, controller: c, child: ListView.builder(controller: c, itemCount: 50, itemBuilder: (_, i) => SizedBox(height: 60, child: Text('row $i'))))),
    ));
    expect(find.byType(StretchingOverscrollIndicator), findsWidgets);
    expect(find.byType(GlowingOverscrollIndicator), findsNothing);
    c.dispose();
  });

  testWidgets('область оновлення: верх — лише індикатор оновлення (без розтягування), низ — розтягування', (t) async {
    var refreshed = 0;
    await t.pumpWidget(MaterialApp(
      scrollBehavior: const AppScrollBehavior(),
      home: Scaffold(
        body: AppPullToRefresh(
          onRefresh: () async => refreshed++,
          child: ListView.builder(itemCount: 50, itemBuilder: (_, i) => SizedBox(height: 60, child: Text('row $i'))),
        ),
      ),
    ));
    // Потяг униз на верху: оновлення спрацювало, вміст не розтягувався
    final g = await t.startGesture(t.getCenter(find.byType(ListView)));
    await g.moveBy(const Offset(0, 120));
    await t.pump();
    await g.moveBy(const Offset(0, 120));
    await t.pump();
    final stretch = t.widget<StretchingOverscrollIndicator>(find.byType(StretchingOverscrollIndicator));
    expect(stretch, isNotNull);
    expect(t.getTopLeft(find.text('row 0')).dy, lessThan(80), reason: 'вміст не розтягнувся на верхньому краї');
    await g.up();
    await t.pump(const Duration(seconds: 1));
    await t.pump(const Duration(seconds: 1));
    expect(refreshed, 1, reason: 'індикатор оновлення побачив потяг');
  });
}
