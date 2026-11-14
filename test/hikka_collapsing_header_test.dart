import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:miki_miki/widgets/app_ui_kit.dart';
import 'package:miki_miki/widgets/hikka/hikka_page_kit.dart';

void main() {
  Widget app({int items = 80}) => MaterialApp(
        home: Scaffold(
          body: HikkaCollapsingHeader(
            header: const SizedBox(key: ValueKey('hdr'), height: 120, child: Text('Шапка')),
            body: Builder(
              builder: (context) => ListView.builder(
                padding: EdgeInsets.only(top: AppHeaderInset.of(context)),
                itemCount: items,
                itemBuilder: (_, i) => SizedBox(height: 60, child: Text('row $i')),
              ),
            ),
          ),
        ),
      );

  // Видима частина шапки: нижня межа відносно верху екрана
  double hdrBottom(WidgetTester t) => t.getBottomLeft(find.byKey(const ValueKey('hdr'))).dy;

  testWidgets('шапка лежить над вмістом: на верху вміст починається під нею', (t) async {
    await t.pumpWidget(app());
    await t.pumpAndSettle();
    expect(hdrBottom(t), 120);
    expect(t.getTopLeft(find.text('row 0')).dy, 128);
  });

  testWidgets('шапка ховається при прокрутці вниз і повністю виїжджає назад угору', (t) async {
    await t.pumpWidget(app(items: 300));
    await t.pumpAndSettle();
    expect(hdrBottom(t), 120, reason: 'на верху сторінки шапка на місці');
    await t.drag(find.byType(ListView), const Offset(0, -600));
    await t.pumpAndSettle();
    expect(hdrBottom(t), lessThanOrEqualTo(0), reason: 'прокрутили вниз: шапка сховалась');
  });

  testWidgets('шапка виїжджає в середині сторінки слідом за пальцем (1:1) і докочується', (t) async {
    await t.pumpWidget(app(items: 300));
    await t.pumpAndSettle();
    await t.drag(find.byType(ListView), const Offset(0, -600));
    await t.pumpAndSettle();
    final before = t.getTopLeft(find.text('row 12')).dy;
    await t.drag(find.byType(ListView), const Offset(0, 50));
    await t.pump();
    final b = hdrBottom(t);
    expect(b, inInclusiveRange(25, 70), reason: 'частково виїхала пропорційно руху');
    await t.pumpAndSettle();
    expect(hdrBottom(t), anyOf(120, lessThanOrEqualTo(0)), reason: 'після жесту докотилась до краю');
    expect(t.getTopLeft(find.text('row 12')).dy - before, inInclusiveRange(30, 70), reason: 'вміст не штовхається шапкою');
    await t.drag(find.byType(ListView), const Offset(0, 220));
    await t.pumpAndSettle();
    expect(hdrBottom(t), 120);
  });

  testWidgets('на початку сторінки шапка їде разом із вмістом без порожнього місця', (t) async {
    await t.pumpWidget(app(items: 300));
    await t.pumpAndSettle();
    await t.drag(find.byType(ListView), const Offset(0, -50));
    await t.pump();
    final off = t.getTopLeft(find.text('row 0')).dy - 128; // скільки вмісту пішло вгору
    expect(off, closeTo(-50, 2));
    expect(hdrBottom(t), closeTo(120 + off, 2), reason: 'шапка зсунулась на стільки ж, нижче неї вміст без щілини');
    // Повільне повернення до початку: шапка завжди прикриває відступ над вмістом
    await t.drag(find.byType(ListView), const Offset(0, -600));
    await t.pumpAndSettle();
    await t.fling(find.byType(ListView), const Offset(0, 4000), 4000);
    await t.pumpAndSettle();
    expect(hdrBottom(t), 120, reason: 'на самому верху шапка завжди з\'являється');
  });

  testWidgets('щілини немає на жодній позиції прокрутки: шапка закриває відступ над вмістом', (t) async {
    final c = ScrollController();
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HikkaCollapsingHeader(
          header: const SizedBox(key: ValueKey('hdr'), height: 120, child: Text('Шапка')),
          body: Builder(
            builder: (context) => ListView.builder(
              controller: c,
              padding: EdgeInsets.only(top: AppHeaderInset.of(context)),
              itemCount: 300,
              itemBuilder: (_, i) => SizedBox(height: 60, child: Text('row $i')),
            ),
          ),
        ),
      ),
    ));
    await t.pumpAndSettle();
    await t.drag(find.byType(ListView), const Offset(0, -600));
    await t.pumpAndSettle();
    for (var i = 0; i < 25; i++) {
      await t.drag(find.byType(ListView), const Offset(0, 30));
      await t.pump();
      final gapEnd = 128 - c.offset; // де закінчується порожній відступ над першим рядком
      if (gapEnd > 0) expect(hdrBottom(t) + 8, greaterThanOrEqualTo(gapEnd - 0.5), reason: 'на offset ${c.offset}');
    }
    c.dispose();
  });

  testWidgets('вкладений список усередині сторінки шапку не рухає', (t) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HikkaCollapsingHeader(
          header: const SizedBox(key: ValueKey('hdr'), height: 120, child: Text('Шапка')),
          body: Builder(
            builder: (context) => ListView(
              padding: EdgeInsets.only(top: AppHeaderInset.of(context)),
              children: [
                SizedBox(
                  key: const ValueKey('inner'),
                  height: 300,
                  child: ListView.builder(itemCount: 100, itemBuilder: (_, i) => SizedBox(height: 50, child: Text('inner $i'))),
                ),
                for (var i = 0; i < 30; i++) SizedBox(height: 60, child: Text('outer $i')),
              ],
            ),
          ),
        ),
      ),
    ));
    await t.pumpAndSettle();
    expect(hdrBottom(t), 120);
    await t.drag(find.byKey(const ValueKey('inner')), const Offset(0, -200));
    await t.pumpAndSettle();
    expect(find.text('inner 0').evaluate(), isEmpty, reason: 'вкладений список прокрутився');
    expect(hdrBottom(t), 120, reason: 'шапка лишилась');
  });

  testWidgets('короткий вміст не ховає шапку (інакше її не повернути)', (t) async {
    await t.pumpWidget(app(items: 9));
    await t.pumpAndSettle();
    await t.drag(find.byType(ListView), const Offset(0, -300));
    await t.pumpAndSettle();
    expect(hdrBottom(t), 120);
  });

  testWidgets('вкладена шапка сидить під зовнішньою', (t) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HikkaCollapsingHeader(
          header: const SizedBox(key: ValueKey('outer'), height: 100, child: Text('Зовнішня')),
          body: HikkaCollapsingHeader(
            header: const SizedBox(key: ValueKey('hdr'), height: 50, child: Text('Внутрішня')),
            body: Builder(
              builder: (context) => ListView.builder(
                padding: EdgeInsets.only(top: AppHeaderInset.of(context)),
                itemCount: 50,
                itemBuilder: (_, i) => SizedBox(height: 60, child: Text('row $i')),
              ),
            ),
          ),
        ),
      ),
    ));
    await t.pumpAndSettle();
    expect(t.getTopLeft(find.byKey(const ValueKey('hdr'))).dy, 108);
    expect(t.getTopLeft(find.text('row 0')).dy, 166);
    await t.drag(find.byType(ListView), const Offset(0, -400));
    await t.pumpAndSettle();
    expect(t.getBottomLeft(find.byKey(const ValueKey('hdr'))).dy, lessThanOrEqualTo(0), reason: 'обидві шапки ховаються разом');
  });

  testWidgets('край прокрутки: розтягування як в Android 12, а не старе світіння — і всередині смуги прокрутки теж', (t) async {
    final c = ScrollController();
    await t.pumpWidget(MaterialApp(
      scrollBehavior: const AppScrollBehavior(),
      home: Scaffold(body: AppScrollbar(scale: 1, controller: c, child: ListView.builder(controller: c, itemCount: 50, itemBuilder: (_, i) => SizedBox(height: 60, child: Text('row $i'))))),
    ));
    expect(find.byType(StretchingOverscrollIndicator), findsWidgets);
    expect(find.byType(GlowingOverscrollIndicator), findsNothing);
    expect(find.byType(RawScrollbar), findsNothing, reason: 'смуги прокрутки в застосунку немає');
    expect(find.byType(Scrollbar), findsNothing);
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

  testWidgets('під час оновлення прокрутка заблокована, після нього — знову працює', (t) async {
    final done = Completer<void>();
    final c = ScrollController();
    await t.pumpWidget(MaterialApp(
      scrollBehavior: const AppScrollBehavior(),
      home: Scaffold(
        body: AppPullToRefresh(
          onRefresh: () => done.future,
          child: ListView.builder(controller: c, itemCount: 80, itemBuilder: (_, i) => SizedBox(height: 60, child: Text('row $i'))),
        ),
      ),
    ));
    final g = await t.startGesture(t.getCenter(find.byType(ListView)));
    await g.moveBy(const Offset(0, 120));
    await t.pump();
    await g.moveBy(const Offset(0, 120));
    await t.pump();
    await g.up();
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    // Оновлення триває: тягнемо вміст угору — він не рухається
    await t.drag(find.byType(ListView), const Offset(0, -300));
    await t.pump(const Duration(milliseconds: 500));
    expect(c.offset, 0, reason: 'прокрутка заблокована, доки триває оновлення');
    done.complete();
    await t.pumpAndSettle();
    await t.drag(find.byType(ListView), const Offset(0, -300));
    await t.pumpAndSettle();
    expect(c.offset, greaterThan(100), reason: 'після оновлення прокрутка знову працює');
    c.dispose();
  });

  Widget refreshApp(ScrollController c, {Future<void> Function()? onRefresh}) => MaterialApp(
        scrollBehavior: const AppScrollBehavior(),
        home: Scaffold(
          body: AppPullToRefresh(
            onRefresh: onRefresh ?? () async {},
            child: ListView.builder(controller: c, itemCount: 80, itemBuilder: (_, i) => SizedBox(height: 60, child: Text('row $i'))),
          ),
        ),
      );

  testWidgets('стрілка лишається, поки тримаєш палець, йде за пальцем униз і назад угору', (t) async {
    final c = ScrollController();
    await t.pumpWidget(refreshApp(c));
    final g = await t.startGesture(t.getCenter(find.byType(ListView)));
    await g.moveBy(const Offset(0, 90));
    await t.pump();
    expect(find.byIcon(Symbols.arrow_downward_rounded), findsOneWidget);
    final y1 = t.getTopLeft(find.byIcon(Symbols.arrow_downward_rounded)).dy;
    await g.moveBy(const Offset(0, 60));
    await t.pump();
    final y2 = t.getTopLeft(find.byIcon(Symbols.arrow_downward_rounded)).dy;
    expect(y2, greaterThan(y1), reason: 'стрілка йде вниз за пальцем');
    await g.moveBy(const Offset(0, -70));
    await t.pump();
    final y3 = t.getTopLeft(find.byIcon(Symbols.arrow_downward_rounded)).dy;
    expect(y3, lessThan(y2), reason: 'стрілка повертається вгору разом із пальцем');
    for (final dy in [-3.0, 2.0, -4.0, 3.0, -2.0]) {
      await g.moveBy(Offset(0, dy));
      await t.pump(const Duration(milliseconds: 50));
    }
    await t.pump(const Duration(seconds: 1)); // палець тримається
    expect(find.byIcon(Symbols.arrow_downward_rounded), findsOneWidget, reason: 'стрілка лишилась');
    expect(c.offset, 0, reason: 'вміст під час потягу стоїть');
    await g.up();
    await t.pumpAndSettle();
    expect(find.byIcon(Symbols.arrow_downward_rounded), findsNothing);
    c.dispose();
  });

  testWidgets('потяг скасовується поверненням стрілки назад, далі звичайна прокрутка', (t) async {
    final c = ScrollController();
    await t.pumpWidget(refreshApp(c));
    final g = await t.startGesture(t.getCenter(find.byType(ListView)));
    await g.moveBy(const Offset(0, 80));
    await t.pump();
    await g.moveBy(const Offset(0, -40));
    await t.pump();
    expect(c.offset, 0);
    await g.moveBy(const Offset(0, -140));
    await t.pump();
    expect(c.offset, greaterThan(50));
    await g.up();
    await t.pumpAndSettle();
    c.dispose();
  });
}
