// Автовибір доріжок субтитрів і звуку за пріоритетом мов із налаштувань. mpv сам вмикає лише доріжку «за замовчуванням»,
// тож без цього логіку мови з налаштувань ніхто не застосовував, а субтитрів у файлах без такої позначки не було видно.
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:miki_miki/services/lang_match.dart';
import 'package:miki_miki/services/track_defaults.dart';

SubtitleTrack sub(String id, {String? lang, String? title, bool def = false, bool image = false}) =>
    SubtitleTrack(id, title, lang, isDefault: def, image: image);

AudioTrack aud(String id, {String? lang, String? title, bool def = false}) => AudioTrack(id, title, lang, isDefault: def);

/// Як у media_kit: спершу службові «авто» й «вимкнено», далі доріжки файлу
List<SubtitleTrack> subs(List<SubtitleTrack> real) => [SubtitleTrack.auto(), SubtitleTrack.no(), ...real];
List<AudioTrack> auds(List<AudioTrack> real) => [AudioTrack.auto(), AudioTrack.no(), ...real];

const List<String> prio = ['uk', 'ja', 'en'];

void main() {
  group('коди мов', () {
    test('двобуквений код і всі його тризначні записи', () {
      expect(LangMatch.aliases('uk'), {'uk', 'ukr'});
      expect(LangMatch.aliases('de'), {'de', 'ger', 'deu'});
      expect(LangMatch.aliases('ru'), {'ru', 'rus'});
      expect(LangMatch.aliases('xx'), {'xx'});
      expect(LangMatch.aliases(''), isEmpty);
      expect(LangMatch.aliases(' UK '), {'uk', 'ukr'});
    });

    test('мітка мови з контейнера: регістр, регіон, «не задано»', () {
      expect(LangMatch.normalizeTag('UKR'), 'ukr');
      expect(LangMatch.normalizeTag('pt-BR'), 'pt');
      expect(LangMatch.normalizeTag('en_US'), 'en');
      expect(LangMatch.normalizeTag(' en '), 'en');
      for (final none in [null, '', 'und', 'UND', 'zxx', 'mul']) {
        expect(LangMatch.normalizeTag(none), '', reason: '$none');
      }
    });
  });

  group('збіг мови', () {
    test('за міткою: «ukr» і «uk» — українська, «eng» — ні', () {
      expect(LangMatch.matches('uk', language: 'ukr'), isTrue);
      expect(LangMatch.matches('uk', language: 'uk'), isTrue);
      expect(LangMatch.matches('uk', language: 'eng'), isFalse);
      expect(LangMatch.matches('en', language: 'eng'), isTrue);
      expect(LangMatch.matches('ja', language: 'jpn'), isTrue);
    });

    test('мітка важливіша за назву: «eng» із назвою «Ukrainian» — англійська', () {
      expect(LangMatch.matches('uk', language: 'eng', title: 'Ukrainian'), isFalse);
      expect(LangMatch.matches('en', language: 'eng', title: 'Ukrainian'), isTrue);
    });

    test('мітки нема або «und» — мову видно з назви', () {
      for (final lang in [null, '', 'und']) {
        expect(LangMatch.matches('uk', language: lang, title: 'Українські (FanVoxUA)'), isTrue, reason: 'укр. назва, мітка «$lang»');
        expect(LangMatch.matches('uk', language: lang, title: 'Ukrainian [FanVox]'), isTrue);
        expect(LangMatch.matches('uk', language: lang, title: 'UA'), isTrue);
        expect(LangMatch.matches('uk', language: lang, title: 'ukr'), isTrue);
        expect(LangMatch.matches('en', language: lang, title: 'English'), isTrue);
        expect(LangMatch.matches('en', language: lang, title: 'Англійські'), isTrue);
        expect(LangMatch.matches('ja', language: lang, title: 'Japanese'), isTrue);
        expect(LangMatch.matches('ja', language: lang, title: 'JP'), isTrue);
      }
    });

    test('мову з назви беремо й для рідкісних мов — за коренем української назви', () {
      expect(LangMatch.matches('tr', language: 'und', title: 'Турецькі субтитри'), isTrue);
      expect(LangMatch.matches('tr', language: 'tur'), isTrue);
      expect(LangMatch.matches('tr', language: 'und', title: 'Українські'), isFalse);
    });

    test('нічого не відомо про мову — не збігається; неправильний код не збігається ні з чим', () {
      expect(LangMatch.matches('uk'), isFalse);
      expect(LangMatch.matches('uk', language: 'und', title: 'Signs & Songs'), isFalse);
      expect(LangMatch.matches('', language: 'ukr'), isFalse);
    });
  });

  group('зовнішні доріжки за підписом', () {
    test('вища за пріоритетом мова виграє, а не порядок у списку', () {
      expect(LangMatch.pickByLabel(['English', 'Українська'], const ['uk', 'en']), 1);
      expect(LangMatch.pickByLabel(['English', 'Українська'], const ['en', 'uk']), 0);
      expect(LangMatch.pickByLabel(['Deutsch', 'jpn', 'ukr'], const ['ja', 'uk']), 1);
    });

    test('підпис — і назва мови, і трилітерна мітка, і двобуквений код', () {
      expect(LangMatch.pickByLabel(['English', 'ukr'], const ['uk']), 1);
      expect(LangMatch.pickByLabel(['English', 'uk'], const ['uk']), 1);
      expect(LangMatch.pickByLabel(['Українські (FanVoxUA)', 'en'], const ['en', 'uk']), 1);
    });

    test('жодного збігу, порожні список чи пріоритет — перша доріжка', () {
      expect(LangMatch.pickByLabel(['Deutsch', 'Français'], const ['uk', 'en']), 0);
      expect(LangMatch.pickByLabel(['English', 'Українська'], const []), 0);
      expect(LangMatch.pickByLabel(const [], const ['uk']), 0);
    });
  });

  group('який субтитр увімкнути', () {
    test('мова з налаштувань, а не доріжка «за замовчуванням»', () {
      final tracks = subs([
        sub('1', lang: 'eng', title: 'English', def: true),
        sub('2', lang: 'jpn', title: 'Japanese'),
        sub('3', lang: 'ukr', title: 'Ukrainian'),
      ]);
      expect(TrackDefaults.pickSubtitle(tracks, prio)?.id, '3');
    });

    test('першої мови нема — наступна за пріоритетом', () {
      final tracks = subs([sub('1', lang: 'eng'), sub('2', lang: 'jpn')]);
      expect(TrackDefaults.pickSubtitle(tracks, prio)?.id, '2');
      expect(TrackDefaults.pickSubtitle(subs([sub('1', lang: 'eng')]), prio)?.id, '1');
    });

    test('жодна мова зі списку не знайшлася — нічого не обираємо, лишається вибір mpv', () {
      expect(TrackDefaults.pickSubtitle(subs([sub('1', lang: 'fra'), sub('2', lang: 'deu')]), prio), isNull);
      expect(TrackDefaults.pickSubtitle(subs([sub('1', lang: 'ukr')]), const []), isNull);
      expect(TrackDefaults.pickSubtitle(subs(const []), prio), isNull);
    });

    test('службові «авто» й «вимкнено» ніколи не обираються', () {
      final tracks = [SubtitleTrack.auto(), SubtitleTrack.no()];
      expect(TrackDefaults.pickSubtitle(tracks, ['auto', 'no', 'uk']), isNull);
    });

    test('повні субтитри перед «Signs & Songs» і «Forced», але якщо інших нема — беремо й такі', () {
      final both = subs([
        sub('1', lang: 'ukr', title: 'Signs & Songs', def: true),
        sub('2', lang: 'ukr', title: 'Full'),
        sub('3', lang: 'ukr', title: 'Forced'),
      ]);
      expect(TrackDefaults.pickSubtitle(both, prio)?.id, '2');

      final onlySigns = subs([sub('1', lang: 'ukr', title: 'Надписи'), sub('2', lang: 'eng', title: 'Full')]);
      expect(TrackDefaults.pickSubtitle(onlySigns, prio)?.id, '1'); // українські написи, а не повні англійські: мова важливіша
    });

    test('текстові перед зображеннями (PGS), «за замовчуванням» перед рештою, далі — порядок у файлі', () {
      final text = sub('2', lang: 'ukr', title: 'srt');
      final pgs = sub('1', lang: 'ukr', title: 'pgs', def: true, image: true);
      expect(TrackDefaults.pickSubtitle(subs([pgs, text]), prio)?.id, '2');

      final plain = sub('1', lang: 'ukr');
      final marked = sub('2', lang: 'ukr', def: true);
      expect(TrackDefaults.pickSubtitle(subs([plain, marked]), prio)?.id, '2');
      expect(TrackDefaults.pickSubtitle(subs([marked, plain]), prio)?.id, '2');

      final a = sub('7', lang: 'ukr');
      final b = sub('8', lang: 'ukr');
      expect(TrackDefaults.pickSubtitle(subs([a, b]), prio)?.id, '7');
      expect(TrackDefaults.pickSubtitle(subs([b, a]), prio)?.id, '8');
    });

    test('мітки мови нема, але в назві «Українські» — теж знаходиться', () {
      final tracks = subs([sub('1', lang: 'und', title: 'Українські (FanVoxUA)'), sub('2', lang: 'eng', title: 'English', def: true)]);
      expect(TrackDefaults.pickSubtitle(tracks, prio)?.id, '1');
    });

    test('пріоритет за порядком списку: інший порядок — інша доріжка', () {
      final tracks = subs([sub('1', lang: 'eng'), sub('2', lang: 'jpn'), sub('3', lang: 'ukr')]);
      expect(TrackDefaults.pickSubtitle(tracks, const ['en', 'uk'])?.id, '1');
      expect(TrackDefaults.pickSubtitle(tracks, const ['ja', 'uk', 'en'])?.id, '2');
    });
  });

  group('яку аудіодоріжку увімкнути', () {
    test('за пріоритетом мов, а не за позначкою «за замовчуванням»', () {
      final tracks = auds([aud('1', lang: 'ukr', title: 'Дубляж', def: true), aud('2', lang: 'jpn', title: 'Original')]);
      expect(TrackDefaults.pickAudio(tracks, const ['ja', 'uk', 'en'])?.id, '2');
      expect(TrackDefaults.pickAudio(tracks, const ['uk', 'ja'])?.id, '1');
    });

    test('коментарі режисера — лише якщо іншої доріжки цією мовою нема', () {
      final tracks = auds([aud('1', lang: 'jpn', title: 'Director commentary'), aud('2', lang: 'jpn', title: 'Main')]);
      expect(TrackDefaults.pickAudio(tracks, const ['ja'])?.id, '2');
      expect(TrackDefaults.pickAudio(auds([aud('1', lang: 'jpn', title: 'Коментар режисера')]), const ['ja'])?.id, '1');
    });

    test('жодної мови зі списку нема — нічого не обираємо', () {
      expect(TrackDefaults.pickAudio(auds([aud('1', lang: 'fra')]), const ['ja', 'uk']), isNull);
      expect(TrackDefaults.pickAudio(auds(const []), const ['ja']), isNull);
    });
  });

  group('план для файлу', () {
    final tracks = Tracks(
      audio: auds([aud('1', lang: 'ukr'), aud('2', lang: 'jpn')]),
      subtitle: subs([sub('1', lang: 'eng', def: true), sub('2', lang: 'ukr')]),
    );

    test('автовибір увімкнено: українські субтитри й японська доріжка за пріоритетами', () {
      final plan = TrackDefaults.plan(tracks, subtitlesEnabled: true, subPriorities: prio, audioPriorities: const ['ja', 'uk', 'en']);
      expect(plan.subtitle?.id, '2');
      expect(plan.audio?.id, '2');
      expect(plan.isEmpty, isFalse);
    });

    test('«Автоматично завантажувати субтитри» вимкнено: субтитри вимикаються, звук — за пріоритетом', () {
      final plan = TrackDefaults.plan(tracks, subtitlesEnabled: false, subPriorities: prio, audioPriorities: const ['uk']);
      expect(plan.subtitle?.id, 'no');
      expect(plan.audio?.id, '1');
    });

    test('вимкнено, а субтитрів у файлі нема — вимикати нічого', () {
      final plan = TrackDefaults.plan(const Tracks(), subtitlesEnabled: false, subPriorities: prio, audioPriorities: prio);
      expect(plan.subtitle, isNull);
      expect(plan.isEmpty, isTrue);
    });

    test('порожній файл (доріжки ще не відомі): плану нема', () {
      final plan = TrackDefaults.plan(const Tracks(), subtitlesEnabled: true, subPriorities: prio, audioPriorities: prio);
      expect(plan.isEmpty, isTrue);
    });
  });
}
