import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miki_miki/services/app_layers.dart';

void main() {
  testWidgets('накладка займає шар, поки відкрита, і звільняє його при закритті', (tester) async {
    expect(AppLayers.blocked, isFalse);
    Widget app(bool open) => MaterialApp(home: AppLayerClaim(active: open, child: const SizedBox()));
    await tester.pumpWidget(app(false));
    await tester.pump();
    expect(AppLayers.blocked, isFalse);
    await tester.pumpWidget(app(true));
    await tester.pump();
    expect(AppLayers.blocked, isTrue, reason: 'мініплеєр має сховатися під шторкою');
    await tester.pumpWidget(app(false));
    await tester.pump();
    expect(AppLayers.blocked, isFalse);
    await tester.pumpWidget(app(true));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(AppLayers.blocked, isFalse, reason: 'знищена накладка звільняє шар');
  });
}
