import 'package:flutter_test/flutter_test.dart';
import 'package:miki_miki/services/touch_hide_timer.dart';

void main() {
  testWidgets('панелі ховаються через delay, якщо їх не треба лишати', (tester) async {
    var hidden = 0;
    final t = TouchHideTimer(shouldStayVisible: () => false, onHide: () => hidden++);
    t.arm();
    expect(t.isArmed, isTrue);
    await tester.pump(const Duration(seconds: 3));
    expect(hidden, 0);
    await tester.pump(const Duration(milliseconds: 1100));
    expect(hidden, 1);
    expect(t.isArmed, isFalse);
  });

  testWidgets('кожен дотик (arm) відкладає приховування', (tester) async {
    var hidden = 0;
    final t = TouchHideTimer(shouldStayVisible: () => false, onHide: () => hidden++);
    t.arm();
    await tester.pump(const Duration(seconds: 3));
    t.arm(); // дотик на 3-й секунді
    await tester.pump(const Duration(seconds: 3)); // 6 с від початку, 3 с від дотику
    expect(hidden, 0);
    await tester.pump(const Duration(milliseconds: 1100));
    expect(hidden, 1);
  });

  testWidgets('на паузі/з відкритим меню панелі не ховаються', (tester) async {
    var hidden = 0;
    var stay = true;
    final t = TouchHideTimer(shouldStayVisible: () => stay, onHide: () => hidden++);
    t.arm();
    await tester.pump(const Duration(seconds: 5));
    expect(hidden, 0);
    expect(t.isArmed, isFalse, reason: 'таймер відпрацював і чекає наступного дотику');
    stay = false; // відновили відтворення, потім будь-який дотик знову запускає відлік
    t.arm();
    await tester.pump(const Duration(seconds: 5));
    expect(hidden, 1);
  });

  testWidgets('cancel скасовує приховування', (tester) async {
    var hidden = 0;
    final t = TouchHideTimer(shouldStayVisible: () => false, onHide: () => hidden++);
    t.arm();
    t.cancel();
    expect(t.isArmed, isFalse);
    await tester.pump(const Duration(seconds: 10));
    expect(hidden, 0);
  });

  testWidgets('інший delay враховується', (tester) async {
    var hidden = 0;
    final t = TouchHideTimer(shouldStayVisible: () => false, onHide: () => hidden++, delay: const Duration(milliseconds: 500));
    t.arm();
    await tester.pump(const Duration(milliseconds: 600));
    expect(hidden, 1);
  });
}
