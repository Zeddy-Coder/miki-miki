import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miki_miki/services/media_controls.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('miki_miki/media_controls');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    MediaControls.debugEnabled = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (c) async {
      calls.add(c);
      return null;
    });
  });

  tearDown(() async {
    await MediaControls.clear();
    MediaControls.debugEnabled = false;
    MediaControls.onButton = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  test('update sends the state once; identical updates are skipped', () async {
    await MediaControls.update(title: 'Frieren · Серія 3', playing: true, hasNext: true);
    await MediaControls.update(title: 'Frieren · Серія 3', playing: true, hasNext: true);
    expect(calls, hasLength(1));
    expect(calls.single.method, 'update');
    final a = calls.single.arguments as Map;
    expect(a['title'], 'Frieren · Серія 3');
    expect(a['playing'], true);
    expect(a['hasNext'], true);
    expect(a['hasPrevious'], false);
    expect(a['thumbnail'], '');
  });

  test('a changed play state is sent again', () async {
    await MediaControls.update(title: 'A', playing: true);
    await MediaControls.update(title: 'A', playing: false);
    expect(calls.map((c) => (c.arguments as Map)['playing']), [true, false]);
  });

  test('clear is sent only after something was published', () async {
    await MediaControls.clear();
    expect(calls, isEmpty);
    await MediaControls.update(title: 'A', playing: true);
    await MediaControls.clear();
    expect(calls.map((c) => c.method), ['update', 'clear']);
    // After clearing, the same state must be published again
    await MediaControls.update(title: 'A', playing: true);
    expect(calls.map((c) => c.method), ['update', 'clear', 'update']);
  });

  test('button presses from the system reach the handler', () async {
    MediaControls.init();
    final pressed = <String>[];
    MediaControls.onButton = pressed.add;
    for (final b in ['toggle', 'next']) {
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(MethodCall('button', b)),
        (_) {},
      );
    }
    expect(pressed, ['toggle', 'next']);
  });

  test('a failing native side never throws', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (c) async => throw PlatformException(code: 'x'));
    await MediaControls.update(title: 'A', playing: true);
  });
}
