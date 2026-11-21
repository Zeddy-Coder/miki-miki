// A description that opens in place (variant A): links do nothing while it is closed, work once it is open
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miki_miki/widgets/hikka/hikka_markdown_view.dart';

const String _long =
    'Фрірен була магинею у групі героя [Гіммеля](https://hikka.io/characters/himmel-17d919 "Гіммель"). Вони вирушили разом '
    'зі священиком Гайтером і воїном Айзеном у десятирічну подорож, щоб перемогти Короля демонів. Вона була останньою, '
    'кого залучили до групи, і, незважаючи на початкове враження Гайтера про те, що її мана середня, Гіммель мав '
    'відчуття, що вона наймогутніша магиня, яку він коли-небудь зустрічав. Будучи ельфійкою, яка прожила понад тисячу '
    'років, Фрірен важко налагоджувати значущі стосунки з людьми.';

void main() {
  Future<List<String>> pump(WidgetTester tester, String text, {bool open = false}) async {
    final opened = <String>[];
    tester.view.physicalSize = const Size(412 * 2.8, 900 * 2.8);
    tester.view.devicePixelRatio = 2.8;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(child: HikkaSynopsis(source: text, scale: 1, open: open, onLink: opened.add)),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return opened;
  }

  testWidgets('згорнутий: посилання не діє, дотик по ньому лише розгортає опис', (tester) async {
    final opened = await pump(tester, _long);
    expect(find.byKey(const ValueKey('synopsis-closed')), findsOneWidget);
    expect(find.text('Читати далі'), findsOneWidget);
    await tester.tapOnText(find.textRange.ofSubstring('Гіммеля'));
    await tester.pumpAndSettle();
    expect(opened, isEmpty, reason: 'у згорнутому описі посилання не натискається');
    expect(find.byKey(const ValueKey('synopsis-open')), findsOneWidget, reason: 'дотик розгорнув опис');
    expect(find.text('Згорнути'), findsOneWidget);
  });

  testWidgets('розгорнутий: посилання працює, «Згорнути» повертає чотири рядки', (tester) async {
    final opened = await pump(tester, _long, open: true);
    await tester.tapOnText(find.textRange.ofSubstring('Гіммеля'));
    await tester.pumpAndSettle();
    expect(opened, ['https://hikka.io/characters/himmel-17d919']);
    await tester.tap(find.text('Згорнути'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('synopsis-closed')), findsOneWidget);
  });

  testWidgets('короткий опис показано повністю одразу, без «Читати далі», посилання працює', (tester) async {
    final opened = await pump(tester, 'Учениця [Гіммеля](https://hikka.io/characters/himmel-17d919).');
    expect(find.text('Читати далі'), findsNothing);
    expect(find.byKey(const ValueKey('synopsis-closed')), findsNothing);
    await tester.tapOnText(find.textRange.ofSubstring('Гіммеля'));
    await tester.pumpAndSettle();
    expect(opened, ['https://hikka.io/characters/himmel-17d919']);
  });
}
