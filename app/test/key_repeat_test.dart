import 'package:fake_async/fake_async.dart';
import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter_test/flutter_test.dart';
import 'package:helm/ui/key_repeat.dart';

void main() {
  test('backspace rate: 40 ms repeat interval', () {
    expect(kKeyRepeatInterval, const Duration(milliseconds: 40));
  });

  test('press fires once immediately', () {
    fakeAsync((async) {
      var fired = 0;
      final repeater = KeyRepeater();
      repeater.press(() => fired++);
      expect(fired, 1);
      repeater.dispose();
    });
  });

  test('does not repeat before the long-press delay', () {
    fakeAsync((async) {
      var fired = 0;
      final repeater = KeyRepeater();
      repeater.press(() => fired++);
      async.elapse(kLongPressTimeout - const Duration(milliseconds: 1));
      expect(fired, 1);
      repeater.dispose();
    });
  });

  test('repeats every interval after the delay until released', () {
    fakeAsync((async) {
      var fired = 0;
      final repeater = KeyRepeater();
      repeater.press(() => fired++);
      async.elapse(kLongPressTimeout);
      expect(fired, 2, reason: 'one repeat as the delay elapses');
      async.elapse(kKeyRepeatInterval * 3);
      expect(fired, 5);
      repeater.release();
      async.elapse(const Duration(seconds: 1));
      expect(fired, 5);
    });
  });

  test('release before the delay prevents any repeat', () {
    fakeAsync((async) {
      var fired = 0;
      final repeater = KeyRepeater();
      repeater.press(() => fired++);
      async.elapse(const Duration(milliseconds: 100));
      repeater.release();
      async.elapse(const Duration(seconds: 1));
      expect(fired, 1);
    });
  });

  test('dispose stops a repeat in flight', () {
    fakeAsync((async) {
      var fired = 0;
      final repeater = KeyRepeater();
      repeater.press(() => fired++);
      async.elapse(kLongPressTimeout + kKeyRepeatInterval);
      final before = fired;
      repeater.dispose();
      async.elapse(const Duration(seconds: 1));
      expect(fired, before);
    });
  });

  test('a second press restarts the cycle', () {
    fakeAsync((async) {
      var fired = 0;
      final repeater = KeyRepeater();
      repeater.press(() => fired++);
      async.elapse(const Duration(milliseconds: 300));
      repeater.press(() => fired++);
      expect(fired, 2);
      async.elapse(const Duration(milliseconds: 300));
      expect(fired, 2, reason: 'the first delay no longer applies');
      repeater.dispose();
    });
  });
}
