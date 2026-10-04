import 'package:flutter_test/flutter_test.dart';
import 'package:solstein/core/input_event.dart';
import 'package:solstein/hid/hid_reports.dart';
import 'package:solstein/hid/keymap.dart';

void main() {
  group('mouse report', () {
    test('encodes buttons and deltas into 5 bytes', () {
      expect(
        encodeMouseReport(buttons: buttonLeftBit, dx: 10, dy: -5, wheel: 1),
        [0x01, 0x0A, 0xFB, 0x01, 0x00],
      );
    });

    test('negative deltas are two\'s complement bytes', () {
      expect(encodeMouseReport(dx: -1, dy: -127), [0x00, 0xFF, 0x81, 0x00, 0x00]);
    });

    test('release-all is five zero bytes', () {
      expect(mouseReleaseAll(), [0, 0, 0, 0, 0]);
    });

    test('splits deltas beyond ±127 across consecutive reports', () {
      final reports = encodeMouseReports(dx: 300, dy: -200);
      expect(reports, [
        [0x00, 127, 0x81, 0x00, 0x00], // 127, −127
        [0x00, 127, 0xB7, 0x00, 0x00], // 127, −73
        [0x00, 46, 0x00, 0x00, 0x00], // 46, 0
      ]);
      // Sums reconstruct the original deltas.
      var sx = 0, sy = 0;
      for (final r in reports) {
        sx += r[1].toSigned(8);
        sy += r[2].toSigned(8);
      }
      expect(sx, 300);
      expect(sy, -200);
    });

    test('held buttons repeat on every split report', () {
      final reports = encodeMouseReports(buttons: buttonLeftBit, dx: 200);
      expect(reports.length, 2);
      expect(reports.every((r) => r[0] == buttonLeftBit), isTrue);
    });

    test('in-range delta produces a single report', () {
      expect(encodeMouseReports(dx: 5, dy: 5).length, 1);
    });

    test('zero motion still produces one (idle) report', () {
      expect(encodeMouseReports(), [
        [0, 0, 0, 0, 0]
      ]);
    });
  });

  group('keyboard report', () {
    test('is 8 bytes: modifiers, reserved, six keys', () {
      expect(
        encodeKeyboardReport(modifiers: Mod.lShift, keys: [0x04]),
        [0x02, 0x00, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00],
      );
    });

    test('Mission Control example from docs: LCtrl + UpArrow', () {
      final reports = encodeShortcut(modifiers: Mod.lCtrl, usage: 0x52);
      expect(reports, [
        [0x01, 0x00, 0x52, 0, 0, 0, 0, 0],
        [0x00, 0x00, 0x00, 0, 0, 0, 0, 0],
      ]);
    });

    test('caps concurrent keys at 6-key rollover', () {
      final r = encodeKeyboardReport(keys: [1, 2, 3, 4, 5, 6, 7]);
      expect(r.sublist(2), [1, 2, 3, 4, 5, 6]);
    });

    test('release-all is eight zero bytes', () {
      expect(keyboardReleaseAll(), List.filled(8, 0));
    });
  });

  group('consumer report', () {
    test('one bit per media key, in enum order', () {
      expect(encodeConsumerReport(MediaKey.playPause), [0x01]);
      expect(encodeConsumerReport(MediaKey.nextTrack), [0x02]);
      expect(encodeConsumerReport(MediaKey.volumeUp), [0x08]);
      expect(encodeConsumerReport(MediaKey.mute), [0x20]);
      expect(encodeConsumerReport(MediaKey.brightnessDown), [0x80]);
    });

    test('every media key fits the single-byte bitmap', () {
      for (final key in MediaKey.values) {
        final report = encodeConsumerReport(key);
        expect(report.length, 1);
        expect(report[0], 1 << key.index);
      }
    });

    test('release-all is one zero byte', () {
      expect(consumerReleaseAll(), [0]);
    });
  });
}
