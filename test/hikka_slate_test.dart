import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miki_miki/models/hikka_models.dart';
import 'package:miki_miki/services/hikka_nav.dart';
import 'package:miki_miki/widgets/hikka/hikka_slate_view.dart';

import 'support/hikka_fakes.dart';

// Текст статті Hikka (документ Slate): розмітка, посилання, спойлери, картинки. Без шрифтів і знімків.

SlateNode leaf(String text, {bool bold = false, bool italic = false}) => SlateNode(text: text, bold: bold, italic: italic);
SlateNode node(String type, List<SlateNode> children, {String? url}) => SlateNode(type: type, children: children, url: url);
SlateNode para(String text) => node('p', [leaf(text)]);

Widget host(Widget child, {double width = 420}) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: Align(alignment: Alignment.topLeft, child: SizedBox(width: width, child: child))),
      ),
    );

Finder rich(String text) => find.text(text, findRichText: true);

void main() {
  late HikkaTestEnv env;

  setUp(() => env = HikkaTestEnv());
  tearDown(() => env.dispose());

  testWidgets('абзаци, заголовок і виділення текстом; порожній документ нічого не малює', (tester) async {
    await tester.pumpWidget(host(HikkaSlateView(
      scale: 1,
      nodes: [
        node('h2', [leaf('Заголовок')]),
        node('p', [leaf('Звичайний '), leaf('жирний', bold: true), leaf(' і '), leaf('курсив', italic: true)]),
      ],
    )));
    expect(rich('Заголовок'), findsOneWidget);
    expect(find.textContaining('Звичайний жирний і курсив', findRichText: true), findsOneWidget);

    final headingHeight = tester.getSize(rich('Заголовок')).height;
    final bodyHeight = tester.getSize(find.textContaining('Звичайний жирний і курсив', findRichText: true)).height;
    expect(headingHeight, greaterThan(bodyHeight), reason: 'заголовок вищий за рядок основного тексту');

    await tester.pumpWidget(host(const HikkaSlateView(scale: 1, nodes: [])));
    expect(find.byType(RichText), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('списки: нумерований, маркований і вкладений мають свої позначки', (tester) async {
    SlateNode li(String t, [List<SlateNode> nested = const []]) => node('li', [node('lic', [leaf(t)]), ...nested]);
    await tester.pumpWidget(host(HikkaSlateView(
      scale: 1,
      nodes: [
        node('ol', [li('Перший'), li('Другий')]),
        node('ul', [
          li('Маркер', [
            node('ul', [li('Вкладений')]),
          ]),
        ]),
      ],
    )));
    expect(find.text('1.'), findsOneWidget);
    expect(find.text('2.'), findsOneWidget);
    expect(find.text('•'), findsOneWidget);
    expect(find.text('–'), findsOneWidget, reason: 'вкладений список — тире');
    for (final t in ['Перший', 'Другий', 'Маркер', 'Вкладений']) {
      expect(rich(t), findsOneWidget, reason: t);
    }
  });

  testWidgets('цитата й невідомий блок: текст не губиться', (tester) async {
    await tester.pumpWidget(host(HikkaSlateView(
      scale: 1,
      nodes: [
        node('blockquote', [para('Цитата автора')]),
        node('callout', [para('Блок невідомого виду')]),
      ],
    )));
    expect(rich('Цитата автора'), findsOneWidget);
    expect(rich('Блок невідомого виду'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('посилання: власний обробник, сторінка каталогу всередині застосунку, чуже — у браузер', (tester) async {
    final got = <String>[];
    await tester.pumpWidget(host(HikkaSlateView(
      scale: 1,
      onLink: got.add,
      nodes: [
        node('p', [
          node('a', [leaf('Фрірен')], url: 'https://hikka.io/anime/frieren'),
        ]),
      ],
    )));
    await tester.tap(rich('Фрірен'));
    await tester.pump();
    expect(got, ['https://hikka.io/anime/frieren']);

    // Без власного обробника: аніме відкривається в застосунку, а зовнішнє посилання — у браузері
    await tester.pumpWidget(host(HikkaSlateView(
      scale: 1,
      nodes: [
        node('p', [
          node('a', [leaf('Фрірен')], url: 'https://hikka.io/anime/frieren-slug'),
        ]),
        node('p', [
          node('a', [leaf('Чужий сайт')], url: 'https://example.com/page'),
        ]),
        node('p', [
          node('a', [leaf('Колекція')], url: 'https://hikka.io/collections/abc123'),
        ]),
      ],
    )));
    await tester.tap(rich('Фрірен'));
    await tester.pump();
    expect(HikkaNav.instance.top?.kind, HikkaRouteKind.anime);
    expect(HikkaNav.instance.top?.slug, 'frieren-slug');
    await tester.tap(rich('Колекція'));
    await tester.pump();
    expect(HikkaNav.instance.top?.kind, HikkaRouteKind.collection);
    expect(HikkaNav.instance.top?.slug, 'abc123');
    await tester.tap(rich('Чужий сайт'));
    await tester.pump();
    expect(env.opened, ['https://example.com/page']);
  });

  testWidgets('спойлер: закритий ховає текст, натискання показує', (tester) async {
    await tester.pumpWidget(host(HikkaSlateView(
      scale: 1,
      nodes: [
        node('spoiler', [para('Це розв’язка')]),
      ],
    )));
    expect(rich('Це розв’язка'), findsNothing);
    expect(find.textContaining('натисніть, щоб показати'), findsOneWidget);
    await tester.tap(find.textContaining('натисніть, щоб показати'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(rich('Це розв’язка'), findsOneWidget);
    expect(find.textContaining('сховати'), findsOneWidget);
  });

  testWidgets('відео: картка із сайтом; натискання передає адресу', (tester) async {
    final got = <String>[];
    await tester.pumpWidget(host(HikkaSlateView(
      scale: 1,
      onLink: got.add,
      nodes: [node('video', const [], url: 'https://www.youtube.com/watch?v=abc')],
    )));
    expect(find.text('Відео'), findsOneWidget);
    expect(find.text('youtube.com'), findsOneWidget, reason: 'без «www.»');
    await tester.tap(find.text('Відео'));
    await tester.pump();
    expect(got, ['https://www.youtube.com/watch?v=abc']);
  });

  testWidgets('картинки без адреси й порожні групи мовчки пропускаються', (tester) async {
    await tester.pumpWidget(host(HikkaSlateView(
      scale: 1,
      nodes: [
        node('image', const []),
        node('image_group', const []),
        node('video', const []),
        para('Після порожніх блоків'),
      ],
    )));
    expect(find.byType(HikkaSlateImage), findsNothing);
    expect(rich('Після порожніх блоків'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('картинка відкриває перегляд на весь екран, який закривається', (tester) async {
    await tester.pumpWidget(host(HikkaSlateView(
      scale: 1,
      nodes: [node('image', const [], url: 'https://img.hikka.io/a.jpg')],
    )));
    expect(find.byType(HikkaSlateImage), findsOneWidget);
    expect(find.byType(HikkaImageViewer), findsNothing);
    await tester.tap(find.byType(HikkaSlateImage));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(HikkaImageViewer), findsOneWidget);
    expect(find.textContaining(' / '), findsNothing, reason: 'для однієї картинки лічильника немає');
    await tester.tap(find.byTooltip('Закрити'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(HikkaImageViewer), findsNothing);
  });

  testWidgets('група картинок: плитки відкривають перегляд з потрібної картинки й лічильником', (tester) async {
    final urls = ['https://img.hikka.io/1.jpg', 'https://img.hikka.io/2.jpg', 'https://img.hikka.io/3.jpg'];
    await tester.pumpWidget(host(HikkaSlateView(
      scale: 1,
      nodes: [
        node('image_group', [for (final u in urls) node('image', const [], url: u)]),
      ],
    )));
    expect(find.byType(HikkaSlateImage), findsNWidgets(3));
    await tester.tap(find.byType(HikkaSlateImage).at(1));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(HikkaImageViewer), findsOneWidget);
    expect(find.text('2 / 3'), findsOneWidget, reason: 'відкрито другу картинку групи');
    expect(tester.takeException(), isNull);
  });
}
