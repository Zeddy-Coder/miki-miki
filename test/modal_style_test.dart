import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:miki_miki/services/anime4k_service.dart';
import 'package:miki_miki/widgets/app_ui_kit.dart';

void main() {
  testWidgets('AppMenuRow: назва, значення, шеврон і тап', (t) async {
    var taps = 0;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(body: AppMenuRow(scale: 1, icon: Symbols.tune_rounded, title: 'Джерела', value: 'Mikai', onTap: () => taps++)),
    ));
    expect(find.text('Джерела'), findsOneWidget);
    expect(find.text('Mikai'), findsOneWidget);
    expect(find.byIcon(Symbols.chevron_right_rounded), findsOneWidget);
    await t.tap(find.text('Джерела'));
    expect(taps, 1);
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
