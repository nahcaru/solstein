import 'package:flutter_test/flutter_test.dart';
import 'package:helm/hid/keymap_us.dart';

void main() {
  group('US keymap', () {
    test('lowercase letters have no modifier', () {
      expect(keyStrokeForChar('a'), const KeyStroke(Mod.none, 0x04));
      expect(keyStrokeForChar('z'), const KeyStroke(Mod.none, 0x1D));
    });

    test('uppercase letters add left shift', () {
      expect(keyStrokeForChar('A'), const KeyStroke(Mod.lShift, 0x04));
      expect(keyStrokeForChar('Z'), const KeyStroke(Mod.lShift, 0x1D));
    });

    test('digits 1–9 then 0', () {
      expect(keyStrokeForChar('1'), const KeyStroke(Mod.none, 0x1E));
      expect(keyStrokeForChar('9'), const KeyStroke(Mod.none, 0x26));
      expect(keyStrokeForChar('0'), const KeyStroke(Mod.none, 0x27));
    });

    test('shifted digit symbols map to the digit key + shift', () {
      expect(keyStrokeForChar('!'), const KeyStroke(Mod.lShift, 0x1E));
      expect(keyStrokeForChar('('), const KeyStroke(Mod.lShift, 0x26));
      expect(keyStrokeForChar(')'), const KeyStroke(Mod.lShift, 0x27));
    });

    test('plain punctuation', () {
      expect(keyStrokeForChar('-'), const KeyStroke(Mod.none, 0x2D));
      expect(keyStrokeForChar('/'), const KeyStroke(Mod.none, 0x38));
      expect(keyStrokeForChar("'"), const KeyStroke(Mod.none, 0x34));
    });

    test('shifted punctuation', () {
      expect(keyStrokeForChar('_'), const KeyStroke(Mod.lShift, 0x2D));
      expect(keyStrokeForChar('?'), const KeyStroke(Mod.lShift, 0x38));
      expect(keyStrokeForChar('"'), const KeyStroke(Mod.lShift, 0x34));
    });

    test('whitespace maps to space / enter / tab usages', () {
      expect(keyStrokeForChar(' '), const KeyStroke(Mod.none, Usage.space));
      expect(keyStrokeForChar('\n'), const KeyStroke(Mod.none, Usage.enter));
      expect(keyStrokeForChar('\t'), const KeyStroke(Mod.none, Usage.tab));
    });

    test('unmappable characters return null', () {
      expect(keyStrokeForChar('é'), isNull);
      expect(keyStrokeForChar('あ'), isNull);
      expect(keyStrokeForChar('ab'), isNull);
      expect(keyStrokeForChar(''), isNull);
    });

    test('every printable ASCII character is mappable', () {
      for (var c = 0x20; c <= 0x7E; c++) {
        final char = String.fromCharCode(c);
        expect(keyStrokeForChar(char), isNotNull,
            reason: 'no mapping for "$char" (0x${c.toRadixString(16)})');
      }
    });
  });
}
