import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miki_miki/services/app_updater.dart';
import 'package:miki_miki/widgets/update_prompt.dart';

void main() {
  const info = UpdateInfo(
    version: '1.2.0',
    notes: '## 1.2.0\n\n**Нове**\n- Список «Дивлюсь»\n- `Пріоритет` команд',
    pageUrl: 'https://github.com/x/y/releases/tag/v1.2.0',
    downloadUrl: 'https://dl/m.apk',
    size: 3 * 1048576,
  );

  test('нотатки релізу очищаються від markdown', () {
    final t = UpdatePrompt.cleanNotes(info.notes);
    expect(t, isNot(contains('##')));
    expect(t, isNot(contains('**')));
    expect(t, isNot(contains('`')));
    expect(t, contains('Список «Дивлюсь»'));
  });

  testWidgets('вікно: версія, нотатки, три кнопки; «Пропустити версію» запам\'ятовує вибір', (t) async {
    final store = <String, dynamic>{};
    final updater = AppUpdater(transport: (_) async => throw 'no', load: () => store, save: (d) => store..clear()..addAll(d), currentVersion: '1.1.0');
    await t.pumpWidget(MaterialApp(
      home: Builder(builder: (context) => Scaffold(body: TextButton(onPressed: () => UpdatePrompt.show(context, scale: 1, info: info, updater: updater), child: const Text('go')))),
    ));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    expect(find.text('Доступне оновлення'), findsOneWidget);
    expect(find.textContaining('Версія 1.2.0'), findsOneWidget);
    expect(find.textContaining('3.0 МБ'), findsOneWidget);
    expect(find.textContaining('Зараз встановлено 1.1.0'), findsOneWidget);
    expect(find.textContaining('Пріоритет команд'), findsOneWidget);
    expect(find.text('Завантажити'), findsOneWidget);
    expect(find.text('Пізніше'), findsOneWidget);

    await t.tap(find.text('Пропустити версію'));
    await t.pumpAndSettle();
    expect(find.text('Доступне оновлення'), findsNothing);
    expect(updater.skippedVersion, '1.2.0');
  });
}
