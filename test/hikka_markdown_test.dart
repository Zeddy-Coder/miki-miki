import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:miki_miki/services/hikka_markdown.dart';

List<MdSpan> spans(String s) {
  final blocks = HikkaMarkdown.parse(s);
  expect(blocks, hasLength(1), reason: s);
  final b = blocks.single;
  return switch (b) {
    MdParagraph() => b.spans,
    MdListItem() => b.spans,
    _ => fail('очікувався абзац: $b'),
  };
}

void main() {
  group('Markdown: рядкова розмітка', () {
    test('звичайний текст і порожні значення', () {
      expect(HikkaMarkdown.parse(null), isEmpty);
      expect(HikkaMarkdown.parse(''), isEmpty);
      expect(HikkaMarkdown.parse('  \n\n ​\n'), isEmpty);
      expect(spans('Привіт, світе'), [const MdSpan('Привіт, світе')]);
    });

    test('посилання з підказкою', () {
      final s = spans('Див. [Фрірен](https://hikka.io/characters/frieren-7f706c "Фрірен") тут');
      expect(s, [
        const MdSpan('Див. '),
        const MdSpan('Фрірен', url: 'https://hikka.io/characters/frieren-7f706c', title: 'Фрірен'),
        const MdSpan(' тут'),
      ]);
    });

    test('підказка з екранованими лапками', () {
      final s = spans(r'[Kanade](https://hikka.io/characters/k-1 "Kanade \"Angel\" Tachibana")');
      expect(s.single.title, 'Kanade "Angel" Tachibana');
      expect(s.single.text, 'Kanade');
      expect(s.single.url, 'https://hikka.io/characters/k-1');
    });

    test('екранована дужка, посилання й одинока `]`', () {
      final s = spans(r'\[Written [by MAL Rewrite](https://myanimelist.net/anime/1/A_b?q=x.\&cat=anime "by MAL Rewrite")]');
      expect(s.map((e) => e.text).join(), '[Written by MAL Rewrite]');
      final link = s.firstWhere((e) => e.isLink);
      expect(link.text, 'by MAL Rewrite');
      expect(link.url, 'https://myanimelist.net/anime/1/A_b?q=x.&cat=anime');
    });

    test('жирний, курсив, жирний курсив', () {
      final s = spans("напав на **Коноху** (_селище приховане в листі_) і ***все***");
      expect(s, [
        const MdSpan('напав на '),
        const MdSpan('Коноху', bold: true),
        const MdSpan(' ('),
        const MdSpan('селище приховане в листі', italic: true),
        const MdSpan(') і '),
        const MdSpan('все', bold: true, italic: true),
      ]);
      expect(spans('_**Ель Псай Конґру.**_'), [const MdSpan('Ель Псай Конґру.', bold: true, italic: true)]);
      expect(spans('*один* і __два__'), [const MdSpan('один', italic: true), const MdSpan(' і '), const MdSpan('два', bold: true)]);
    });

    test('вкладене виділення', () {
      expect(spans('**жирний *курсив* жирний**'), [
        const MdSpan('жирний ', bold: true),
        const MdSpan('курсив', bold: true, italic: true),
        const MdSpan(' жирний', bold: true),
      ]);
    });

    test('курсив у тексті посилання й одинока крапка курсивом', () {
      final s = spans('Другий сезон [_Chitose-kun_](https://hikka.io/anime/chitose-758a52)_._');
      expect(s, [
        const MdSpan('Другий сезон '),
        const MdSpan('Chitose-kun', italic: true, url: 'https://hikka.io/anime/chitose-758a52'),
        const MdSpan('.', italic: true),
      ]);
    });

    test('символи розмітки, що виділенням не є, лишаються текстом', () {
      expect(spans('5 * 3 = 15').single.text, '5 * 3 = 15');
      expect(spans('snake_case_word').single.text, 'snake_case_word');
      expect(spans('зірочка * без пари').single.text, 'зірочка * без пари');
      expect(spans('**не закрито').single.text, '**не закрито');
      expect(spans('[не посилання] і (дужки)').single.text, '[не посилання] і (дужки)');
      expect(spans('[a](   )').single.text, '[a](   )');
    });

    test('підкреслення в адресі не ламає виділення', () {
      final s = spans('_курсив_ [x](https://a.com/Kimi_no_Na_wa?q=1) _ще_');
      expect(s.where((e) => e.italic).map((e) => e.text), ['курсив', 'ще']);
      expect(s.firstWhere((e) => e.isLink).url, 'https://a.com/Kimi_no_Na_wa?q=1');
    });

    test('голі й кутові посилання', () {
      final bare = spans('Дивись https://example.com/a_b, потім далі');
      expect(bare.firstWhere((e) => e.isLink).url, 'https://example.com/a_b');
      expect(bare.last.text, ', потім далі');
      final angle = spans('<https://example.com/x>');
      expect(angle.single.url, 'https://example.com/x');
      final inParens = spans('(https://example.com/x)');
      expect(inParens.firstWhere((e) => e.isLink).url, 'https://example.com/x');
    });

    test('HTML-сутності', () {
      expect(spans('Кінець&#x20;').single.text, 'Кінець');
      expect(spans('a&amp;b &lt;c&gt; &#65;&#x42; &nbsp;|').single.text, 'a&b <c> AB  |');
      expect(spans('&unknown; &#xZZ;').single.text, '&unknown; &#xZZ;');
      expect(spans('&#42;не курсив&#42;').single.text, '*не курсив*');
    });

    test('розрив рядка всередині абзацу', () {
      final s = spans('перший\nдругий');
      expect(s, [const MdSpan('перший'), const MdSpan('\n'), const MdSpan('другий')]);
    });
  });

  group('Markdown: блоки', () {
    test('абзаци розділені порожніми рядками', () {
      final b = HikkaMarkdown.parse('один\n\nдва\n\n\n\nтри\n');
      expect(b, hasLength(3));
      expect(b.every((e) => e is MdParagraph), isTrue);
    });

    test('цитата', () {
      final b = HikkaMarkdown.parse('> Я відродилася як **дочка**.\n\nПісля');
      expect(b[0], isA<MdQuote>());
      final inner = (b[0] as MdQuote).blocks.single as MdParagraph;
      expect(inner.spans.map((e) => e.text).join(), 'Я відродилася як дочка.');
      expect((b[1] as MdParagraph).spans.single.text, 'Після');
    });

    test('спойлер: прихований блок усередині тексту', () {
      final b = HikkaMarkdown.parse('Вступ.\n\n:::spoiler\nТаємниця [тут](https://hikka.io/anime/x-1).\n:::\n\nКінець.');
      expect(b, hasLength(3));
      expect(b[1], isA<MdSpoiler>());
      final inner = (b[1] as MdSpoiler).blocks.single as MdParagraph;
      expect(inner.spans.any((e) => e.isLink), isTrue);
      expect((b[2] as MdParagraph).spans.single.text, 'Кінець.');
    });

    test('спойлер із заголовком, без закриття й порожній', () {
      final b = HikkaMarkdown.parse(':::spoiler Фінал\nтекст');
      expect((b.single as MdSpoiler).title, 'Фінал');
      expect(HikkaMarkdown.parse(':::spoiler\n:::'), isEmpty);
      expect(HikkaMarkdown.parse(':::\nтекст\n:::'), hasLength(1));
    });

    test('списки й заголовки', () {
      final b = HikkaMarkdown.parse('## Назва\n- перший\n- другий\n2. третій');
      expect((b[0] as MdParagraph).heading, 2);
      expect((b[1] as MdListItem).marker, '•');
      expect((b[3] as MdListItem).marker, '2.');
      expect((b[2] as MdListItem).spans.single.text, 'другий');
    });

    test('звичайний текст: нульова ширина, \\r, пропуски по краях', () {
      final b = HikkaMarkdown.parse('​  Початок\r\nпродовження  ​\n');
      final p = b.single as MdParagraph;
      expect(p.spans.map((e) => e.text).join(), 'Початок\nпродовження');
    });

    test('plain(): без розмітки й без спойлерів', () {
      const src = 'Це **важливо** і [посилання](https://a.com).\n\n:::spoiler\nсекрет\n:::\n\nКінець';
      expect(HikkaMarkdown.plain(src), 'Це важливо і посилання.\nКінець');
      expect(HikkaMarkdown.plain(src, separator: ' '), 'Це важливо і посилання. Кінець');
      expect(HikkaMarkdown.plain(src, includeSpoilers: true), contains('секрет'));
      expect(HikkaMarkdown.plain(null), '');
    });
  });

  group('Markdown: посилання на сторінки каталогу', () {
    test('аніме, персонаж, зовнішнє', () {
      var t = HikkaLinkTarget.classify('https://hikka.io/anime/sousou-no-frieren-97e05f');
      expect((t.kind, t.slug), (HikkaLinkKind.anime, 'sousou-no-frieren-97e05f'));
      t = HikkaLinkTarget.classify('https://hikka.io/characters/frieren-7f706c');
      expect((t.kind, t.slug), (HikkaLinkKind.character, 'frieren-7f706c'));
      t = HikkaLinkTarget.classify('https://www.hikka.io/characters/frieren-7f706c/?tab=1#x');
      expect((t.kind, t.slug), (HikkaLinkKind.character, 'frieren-7f706c'));
      t = HikkaLinkTarget.classify('/anime/abc-123');
      expect((t.kind, t.slug), (HikkaLinkKind.anime, 'abc-123'));
      expect(t.isInternal, isTrue);
    });

    test('чужі та непідтримувані адреси відкриваються назовні', () {
      for (final u in [
        'https://frieren.fandom.com/wiki/Hero_Party',
        'https://t.me/UAanimeNews',
        'https://hikka.io/manga/some-manga-1',
        'https://hikka.io/people/someone-1',
        'https://hikka.io/anime',
        'https://evil.com/anime/abc-123',
        'https://hikka.io.evil.com/anime/abc-123',
        '',
        'ht!tp://%%',
      ]) {
        final t = HikkaLinkTarget.classify(u);
        expect(t.kind, HikkaLinkKind.external, reason: u);
        expect(t.isInternal, isFalse);
      }
    });
  });

  test('усі збережені описи розбираються без розмітки, що «протекла»', () {
    final list = (jsonDecode(File('test/data/hikka_descriptions.json').readAsStringSync()) as List).cast<String>();
    expect(list.length, greaterThan(50));
    var links = 0, spoilers = 0, bold = 0, italic = 0;
    void walk(List<MdBlock> blocks) {
      for (final b in blocks) {
        switch (b) {
          case MdParagraph():
            for (final s in b.spans) {
              links += s.isLink ? 1 : 0;
              bold += s.bold ? 1 : 0;
              italic += s.italic ? 1 : 0;
              expect(s.text, isNot(contains('](')), reason: 'не розібране посилання: ${s.text}');
              expect(s.text, isNot(contains('​')));
              expect(s.text, isNot(contains(':::')));
              expect(s.text, isNot(contains('**')));
              expect(s.text, isNot(matches(r'&#x?[0-9a-fA-F]+;')));
            }
          case MdListItem():
            break;
          case MdQuote():
            walk(b.blocks);
          case MdSpoiler():
            spoilers++;
            walk(b.blocks);
        }
      }
    }

    for (final s in list) {
      final blocks = HikkaMarkdown.parse(s);
      expect(blocks, isNotEmpty, reason: s);
      walk(blocks);
      final plain = HikkaMarkdown.plain(s, includeSpoilers: true);
      expect(plain.trim(), isNotEmpty);
    }
    expect(links, greaterThan(50));
    expect(spoilers, greaterThan(3));
    expect(bold, greaterThan(3));
    expect(italic, greaterThan(3));
  });
}
