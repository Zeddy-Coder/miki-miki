import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:miki_miki/services/anime4k_service.dart';
import 'package:miki_miki/services/keyboard_shortcuts.dart';
import 'package:miki_miki/services/shortcut_catalog.dart';

import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('каталог клавіш', () {
    test('ідентифікатори унікальні', () {
      final ids = ShortcutCatalog.all.map((d) => d.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    for (final scheme in KeyScheme.values) {
      test('у схемі ${scheme.name} жодна комбінація не прив’язана до двох дій', () {
        final seen = <(int, bool, bool, bool), String>{};
        for (final def in ShortcutCatalog.all) {
          for (final chord in def.chordsFor(scheme)) {
            final other = seen[chord.lookupKey];
            expect(other, isNull, reason: '${def.id} конфліктує з $other (${chord.caps.join('+')})');
            seen[chord.lookupKey] = def.id;
          }
        }
      });
    }

    test('кожна дія каталогу має обробник у PlayerActions', () {
      final actions = FakeController().actions;
      final missing = [
        for (final def in ShortcutCatalog.all)
          if (def.id != 'escape' && !actions.has(def.id)) def.id,
      ];
      expect(missing, isEmpty);
    });

    test('усі обробники мають запис у каталозі (немає «мертвих» дій)', () {
      final actions = FakeController().actions;
      final orphan = [
        for (final id in actions.table.keys)
          if (!ShortcutCatalog.byId.containsKey(id)) id,
      ];
      expect(orphan, isEmpty);
    });

    test('режими Anime4K прив’язані до Ctrl+цифра з каталогу', () {
      for (final mode in Anime4kMode.values) {
        final def = ShortcutCatalog.byId[mode.shortcutId];
        expect(def, isNotNull, reason: mode.name);
        final chord = def!.chords.single;
        expect(chord.ctrl, isTrue);
        expect(chord.caps, ['Ctrl', '${mode.digit}']);
      }
      expect(ShortcutCatalog.byId['a4k_off']!.chords.single.caps, ['Ctrl', '0']);
    });

    test('кожна група має комбінації в обох схемах', () {
      for (final scheme in KeyScheme.values) {
        final grouped = ShortcutCatalog.grouped(scheme);
        for (final group in ShortcutGroup.values) {
          expect(grouped[group], isNotEmpty, reason: '${group.name} / ${scheme.name}');
        }
      }
    });

    test('схеми розрізняються саме там, де клавіші конфліктують із mpv', () {
      KeyChord? chord(KeyScheme s, PhysicalKeyboardKey k, {bool shift = false}) {
        final def = ShortcutCatalog.find(s, k, ctrl: false, shift: shift, alt: false);
        return def == null ? null : def.chords.first;
      }

      expect(ShortcutCatalog.find(KeyScheme.standard, PhysicalKeyboardKey.arrowUp, ctrl: false, shift: false, alt: false)!.id,
          'volume_up_5');
      expect(ShortcutCatalog.find(KeyScheme.mpv, PhysicalKeyboardKey.arrowUp, ctrl: false, shift: false, alt: false)!.id,
          'seek_fwd_60');
      expect(ShortcutCatalog.find(KeyScheme.standard, PhysicalKeyboardKey.keyJ, ctrl: false, shift: false, alt: false)!.id,
          'seek_step_back');
      expect(ShortcutCatalog.find(KeyScheme.mpv, PhysicalKeyboardKey.keyJ, ctrl: false, shift: false, alt: false)!.id,
          'sub_cycle');
      expect(ShortcutCatalog.find(KeyScheme.mpv, PhysicalKeyboardKey.keyL, ctrl: false, shift: false, alt: false)!.id,
          'ab_loop');
      expect(chord(KeyScheme.standard, PhysicalKeyboardKey.keyL, shift: true), isNull);
      expect(chord(KeyScheme.mpv, PhysicalKeyboardKey.keyL, shift: true), isNotNull);
    });

    test('довідка не показує приховані комбінації й має підписи', () {
      for (final scheme in KeyScheme.values) {
        for (final defs in ShortcutCatalog.grouped(scheme).values) {
          for (final def in defs) {
            expect(def.label.trim(), isNotEmpty);
            for (final chord in def.chordsFor(scheme).where((c) => !c.hidden)) {
              expect(chord.caps, isNotEmpty);
              for (final cap in chord.caps) {
                expect(cap.trim(), isNotEmpty);
              }
            }
          }
        }
      }
    });
  });

  group('обробник клавіш', () {
    Future<FakeController> pumpHandler(WidgetTester tester, {KeyScheme scheme = KeyScheme.standard}) async {
      final c = FakeController(scheme: scheme);
      await tester.pumpWidget(MaterialApp(
        home: Focus(
          autofocus: true,
          onKeyEvent: (node, event) => KeyboardShortcuts.handle(event, c),
          child: const SizedBox.expand(),
        ),
      ));
      await tester.pump();
      return c;
    }

    testWidgets('Space — пауза, K і P теж', (tester) async {
      final c = await pumpHandler(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
      expect(c.fakePlayer.playPauseCalls, 3);
    });

    testWidgets('стандартна схема: ↑/↓ — гучність, J/L — крок перемотки', (tester) async {
      final c = await pumpHandler(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      expect(c.volumeDeltas, [5, -5]);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
      await tester.pump();
      expect(c.fakePlayer.seeks.single, const Duration(minutes: 20, seconds: 10));
    });

    testWidgets('схема mpv: ↑/↓ — хвилина, L — цикл A–B, O — прогрес', (tester) async {
      final c = await pumpHandler(tester, scheme: KeyScheme.mpv);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(c.volumeDeltas, isEmpty);
      expect(c.fakePlayer.seeks.last, const Duration(minutes: 21));

      await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
      await tester.pump();
      expect(c.commands, contains(equals(['ab-loop'])));

      await tester.sendKeyEvent(LogicalKeyboardKey.keyO);
      await tester.pump();
      expect(c.osdLog.last.progress, isNotNull);
    });

    testWidgets('Ctrl+цифра перемикає режим Anime4K, Ctrl+0 вимикає', (tester) async {
      final c = await pumpHandler(tester);

      Future<void> chord(LogicalKeyboardKey key) async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(key);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      }

      int glslCommands() => c.commands.where((a) => a.contains('glsl-shaders')).length;

      await chord(LogicalKeyboardKey.digit2);
      expect(c.anime4k.enabled, isTrue);
      expect(c.anime4k.mode, Anime4kMode.b);
      await settle(tester, () => glslCommands() >= 1);

      await chord(LogicalKeyboardKey.digit5);
      expect(c.anime4k.mode, Anime4kMode.bb);
      await settle(tester, () => glslCommands() >= 2);

      await chord(LogicalKeyboardKey.digit0);
      expect(c.anime4k.enabled, isFalse);
      await settle(tester, () => glslCommands() >= 3);
      expect(c.commands.where((a) => a.contains('glsl-shaders')).last, ['change-list', 'glsl-shaders', 'clr', '']);

      // Звичайна «2» (без Ctrl) — контраст, а не режим Anime4K
      await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
      await tester.pump();
      expect(c.commands.any((a) => a.length > 1 && a[0] == 'add' && a[1] == 'contrast'), isTrue);
      expect(c.anime4k.enabled, isFalse);
    });

    testWidgets('Shift+/ і F1 відкривають довідку', (tester) async {
      final c = await pumpHandler(tester);
      int opened = 0;
      c.onShowShortcuts = () => opened++;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.slash);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.f1);
      expect(opened, 2);
    });

    testWidgets('утримання клавіші повторює лише безперервні дії', (tester) async {
      final c = await pumpHandler(tester);
      // ↑ (гучність) повторюється, M (mute) — ні
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowUp);
      expect(c.volumeDeltas.length, 3);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyM);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.keyM);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.keyM);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyM);
      expect(c.muteToggles, 1);
    });

    testWidgets('на головній діють лише відкриття файлу, довідка, повний екран', (tester) async {
      final c = await pumpHandler(tester);
      c.home = true;
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      expect(c.fakePlayer.playPauseCalls, 0);
      expect(c.volumeDeltas, isEmpty);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      expect(c.fullscreenToggles, 1);
    });

    testWidgets('у текстовому полі клавіші плеєра не перехоплюються', (tester) async {
      final c = FakeController();
      await tester.pumpWidget(MaterialApp(
        home: Material(
          child: Focus(
            onKeyEvent: (node, event) => KeyboardShortcuts.handle(event, c),
            child: const TextField(autofocus: true),
          ),
        ),
      ));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      expect(c.fakePlayer.playPauseCalls, 0);
    });

    testWidgets('Win+клавіша не обробляється', (tester) async {
      final c = await pumpHandler(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      expect(c.fakePlayer.playPauseCalls, 0);
    });

    testWidgets('українська розкладка: клавіша визначається фізично', (tester) async {
      final c = await pumpHandler(tester);
      // Українська розкладка: на фізичній клавіші M стоїть «ь», тож логічна клавіша інша, а фізична — M
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN, physicalKey: PhysicalKeyboardKey.keyM);
      expect(c.muteToggles, 1);
    });
  });

  group('дії плеєра', () {
    test('швидка серія перемоток рахується від попередньої цілі', () async {
      final c = FakeController();
      final actions = c.actions;
      await actions.run('seek_fwd_5');
      await actions.run('seek_fwd_5');
      await actions.run('seek_fwd_5');
      expect(c.fakePlayer.seeks, [
        const Duration(minutes: 20, seconds: 5),
        const Duration(minutes: 20, seconds: 10),
        const Duration(minutes: 20, seconds: 15),
      ]);
    });

    test('перемотка не виходить за межі відео', () async {
      final c = FakeController();
      c.fakePlayer.current = PlayerState(
        playlist: c.fakePlayer.current.playlist,
        duration: const Duration(minutes: 90),
        position: const Duration(seconds: 3),
      );
      await c.actions.run('seek_back_60');
      expect(c.fakePlayer.seeks.single, Duration.zero);
    });

    test('швидкість: ] множить на 1.1, { ділить навпіл, Backspace скидає', () async {
      final c = FakeController();
      await c.actions.run('speed_up');
      await c.actions.run('speed_double');
      await c.actions.run('speed_reset');
      expect(c.fakePlayer.rates.first, closeTo(1.1, 1e-9));
      expect(c.fakePlayer.rates.last, 1.0);
    });

    test('зображення: контраст, яскравість, гамма, насиченість — через add', () async {
      final c = FakeController();
      for (final id in ['contrast_up', 'brightness_down', 'gamma_up', 'saturation_down']) {
        await c.actions.run(id);
      }
      final props = c.commands.where((a) => a.first == 'add').map((a) => a[1]).toList();
      expect(props, ['contrast', 'brightness', 'gamma', 'saturation']);
    });

    test('цикл A–B показує стан за значеннями mpv', () async {
      final c = FakeController();
      c.props['ab-loop-a'] = 'no';
      await c.actions.run('ab_loop');
      expect(c.osdLog.last.title, 'Цикл A–B вимкнено');
      c.props['ab-loop-a'] = '12.5';
      await c.actions.run('ab_loop');
      expect(c.osdLog.last.title, 'Початок циклу (A)');
      c.props['ab-loop-b'] = '65';
      await c.actions.run('ab_loop');
      expect(c.osdLog.last.title, 'Цикл A–B');
      expect(c.osdLog.last.detail, contains('0:12'));
    });

    test('співвідношення сторін обходить цикл і повертається до початкового', () async {
      final c = FakeController();
      for (int i = 0; i < 4; i++) {
        await c.actions.run('aspect');
      }
      final sets = c.commands.where((a) => a.length > 2 && a[1] == 'video-aspect-override').map((a) => a[2]).toList();
      expect(sets, ['16:9', '4:3', '2.35:1', '-1']);
    });

    test('повтор файлу перемикає режим плейлиста', () async {
      final c = FakeController();
      await c.actions.run('loop_file');
      expect(c.fakePlayer.modes.last, PlaylistMode.single);
      await c.actions.run('loop_file');
      expect(c.fakePlayer.modes.last, PlaylistMode.none);
    });

    test('скидання масштабу обнуляє всі властивості', () async {
      final c = FakeController();
      await c.actions.run('zoom_reset');
      final props = c.commands.where((a) => a.first == 'set').map((a) => a[1]).toSet();
      expect(props, containsAll(['video-zoom', 'panscan', 'video-pan-x', 'video-pan-y']));
    });
  });
}
