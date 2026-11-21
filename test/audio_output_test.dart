import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:miki_miki/services/audio_route_guard.dart';
import 'package:miki_miki/services/mpv_config.dart';
import 'package:miki_miki/services/system_controls.dart';

/// mpv's property calls as the app makes them (`player.platform.setProperty`)
class _Recorder extends Fake implements PlatformPlayer {
  final Map<String, String> props = {};
  final List<String> order = [];

  Future<void> setProperty(String key, String value) async {
    props[key] = value;
    order.add('$key=$value');
  }
}

class _Player extends Fake implements Player {
  final _Recorder recorder = _Recorder();

  @override
  PlatformPlayer? get platform => recorder;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('вихід звуку mpv', () {
    test('вихід іде за форматом кожної серії; на Android — AudioTrack, запасний OpenSL ES', () {
      expect(MpvConfig.audioOptions(android: true), {'gapless-audio': 'weak', 'ao': 'audiotrack,opensles'});
      expect(MpvConfig.audioOptions(android: false), {'gapless-audio': 'weak'}, reason: 'на ПК вихід лишається типовий (WASAPI)');
    });

    test('рушій більше не тримає формат першого файлу на всю сесію', () async {
      final player = _Player();
      await MpvConfig.configureEngine(player, 'auto');
      expect(player.recorder.props['gapless-audio'], 'weak');
      expect(player.recorder.order.where((p) => p == 'gapless-audio=yes'), isEmpty);
    });

    test('у статистиці видно, що йде на динаміки', () {
      expect(MpvConfig.describeAudioOutput(ao: 'audiotrack', source: '5.1', output: 'stereo', rate: '48000'), '5.1 → стерео · 48 кГц · audiotrack');
      expect(MpvConfig.describeAudioOutput(ao: 'opensles', source: 'stereo', output: 'stereo', rate: '44100'), 'стерео · 44.1 кГц · opensles');
      expect(MpvConfig.describeAudioOutput(ao: 'audiotrack', source: 'mono', output: 'mono', rate: '48000'), 'моно · 48 кГц · audiotrack');
      expect(MpvConfig.describeAudioOutput(), '—', reason: 'нічого не грає');
    });
  });

  group('маршрут звуку', () {
    late int reloads;
    late int pauses;
    late bool media;
    late bool playing;
    late List<String> notices;
    late AudioRouteGuard guard;

    setUp(() {
      reloads = 0;
      pauses = 0;
      media = true;
      playing = true;
      notices = [];
      guard = AudioRouteGuard(
        reload: () async => reloads++,
        hasMedia: () => media,
        isPlaying: () => playing,
        pause: () {
          pauses++;
          playing = false;
        },
        notice: notices.add,
        settle: const Duration(milliseconds: 300),
      );
    });
    tearDown(() => guard.dispose());

    testWidgets('Bluetooth підʼєднався кількома подіями — вихід перевідкривається один раз, коли все вляглося', (t) async {
      guard.routeChanged(change: 'added', devices: ['Bluetooth (A2DP)'], route: 'Bluetooth (A2DP)');
      await t.pump(const Duration(milliseconds: 100));
      guard.routeChanged(change: 'added', devices: ['Bluetooth LE (навушники)'], route: 'Bluetooth (A2DP)');
      await t.pump(const Duration(milliseconds: 200));
      expect(reloads, 0, reason: 'маршрут ще встановлюється');
      await t.pump(const Duration(milliseconds: 150));
      expect(reloads, 1);
      expect(guard.route, 'Bluetooth (A2DP)');
      await t.pump(const Duration(seconds: 2));
      expect(reloads, 1);
    });

    testWidgets('без відкритого відео перевідкривати нічого: наступна серія відкриє вихід сама', (t) async {
      media = false;
      guard.routeChanged(change: 'removed', devices: ['дротові навушники'], route: 'динамік');
      await t.pump(const Duration(seconds: 1));
      expect(reloads, 0);
    });

    test('навушники зняли — пауза з поясненням; на паузі нічого не відбувається', () {
      guard.becomingNoisy();
      expect(pauses, 1);
      expect(notices, ['Пауза: навушники відʼєднано']);
      guard.becomingNoisy();
      expect(pauses, 1);
    });

    test('події з Android доходять до плеєра', () async {
      final calls = <String>[];
      SystemControls.debugEnabled = true;
      addTearDown(() {
        SystemControls.debugEnabled = false;
        SystemControls.onAudioRoute = null;
        SystemControls.onAudioNoisy = null;
      });
      SystemControls.init();
      SystemControls.onAudioRoute = ({required String change, List<String> devices = const [], String route = ''}) =>
          calls.add('$change ${devices.join('+')} → $route');
      SystemControls.onAudioNoisy = () => calls.add('noisy');

      const codec = StandardMethodCodec();
      Future<void> send(String method, [Object? args]) => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage('miki_miki/system', codec.encodeMethodCall(MethodCall(method, args)), (_) {});
      await send('audioRoute', {
        'change': 'added',
        'devices': ['Bluetooth (A2DP)'],
        'route': 'Bluetooth (A2DP)',
      });
      await send('audioNoisy');
      expect(calls, ['added Bluetooth (A2DP) → Bluetooth (A2DP)', 'noisy']);
    });
  });
}
