import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:miki_miki/services/anime4k_service.dart';
import 'package:miki_miki/widgets/app_ui_kit.dart';

void main() {
  testWidgets('AppMenuRow: назва, значення під нею і тап; шеврон лише в рядку без значення', (t) async {
    var taps = 0;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(body: AppMenuRow(scale: 1, icon: Symbols.tune_rounded, title: 'Джерела', value: 'Mikai', onTap: () => taps++)),
    ));
    expect(find.text('Джерела'), findsOneWidget);
    expect(find.text('Mikai'), findsOneWidget);
    expect(find.byIcon(Symbols.chevron_right_rounded), findsNothing, reason: 'значення вже показує, що рядок відкриває вибір');
    expect(t.getTopLeft(find.text('Mikai')).dy, greaterThan(t.getTopLeft(find.text('Джерела')).dy), reason: 'значення стоїть під назвою');
    await t.tap(find.text('Джерела'));
    expect(taps, 1);
    await t.pumpWidget(MaterialApp(home: Scaffold(body: AppMenuRow(scale: 1, icon: Symbols.tune_rounded, title: 'Більше', onTap: () {}))));
    expect(find.byIcon(Symbols.chevron_right_rounded), findsOneWidget);
  });

  test('Anime4K: для телефона підказка без назв відеокарт', () {
    for (final q in Anime4kQuality.values) {
      expect(q.deviceHint, isNot(contains('GTX')));
      expect(q.deviceHint, isNot(contains('RTX')));
      expect(q.deviceHint, isNot(contains('RX ')));
      expect(q.deviceHint, isNotEmpty);
    }
  });
}
