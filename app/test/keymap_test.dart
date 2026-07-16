import 'package:flutter_test/flutter_test.dart';
import 'package:helm/hid/keymap.dart';
import 'package:helm/hid/layouts.dart';

void main() {
  final us = hostLayouts[HostLayoutId.us]!;

  group('US layout', () {
    test('lowercase letters have no modifier', () {
      expect(us.strokeFor('a'), const KeyStroke(Mod.none, 0x04));
      expect(us.strokeFor('z'), const KeyStroke(Mod.none, 0x1D));
    });

    test('uppercase letters add left shift', () {
      expect(us.strokeFor('A'), const KeyStroke(Mod.lShift, 0x04));
      expect(us.strokeFor('Z'), const KeyStroke(Mod.lShift, 0x1D));
    });

    test('digits 1–9 then 0', () {
      expect(us.strokeFor('1'), const KeyStroke(Mod.none, 0x1E));
      expect(us.strokeFor('9'), const KeyStroke(Mod.none, 0x26));
      expect(us.strokeFor('0'), const KeyStroke(Mod.none, 0x27));
    });

    test('shifted digit symbols map to the digit key + shift', () {
      expect(us.strokeFor('!'), const KeyStroke(Mod.lShift, 0x1E));
      expect(us.strokeFor('('), const KeyStroke(Mod.lShift, 0x26));
      expect(us.strokeFor(')'), const KeyStroke(Mod.lShift, 0x27));
    });

    test('plain punctuation', () {
      expect(us.strokeFor('-'), const KeyStroke(Mod.none, 0x2D));
      expect(us.strokeFor('/'), const KeyStroke(Mod.none, 0x38));
      expect(us.strokeFor("'"), const KeyStroke(Mod.none, 0x34));
    });

    test('shifted punctuation', () {
      expect(us.strokeFor('_'), const KeyStroke(Mod.lShift, 0x2D));
      expect(us.strokeFor('?'), const KeyStroke(Mod.lShift, 0x38));
      expect(us.strokeFor('"'), const KeyStroke(Mod.lShift, 0x34));
    });

    test('whitespace maps to space / enter / tab usages', () {
      expect(us.strokeFor(' '), const KeyStroke(Mod.none, Usage.space));
      expect(us.strokeFor('\n'), const KeyStroke(Mod.none, Usage.enter));
      expect(us.strokeFor('\t'), const KeyStroke(Mod.none, Usage.tab));
    });

    test('unmappable characters return null', () {
      expect(us.strokeFor('é'), isNull);
      expect(us.strokeFor('あ'), isNull);
      expect(us.strokeFor('ab'), isNull);
      expect(us.strokeFor(''), isNull);
    });

    test('every printable ASCII character is mappable', () {
      for (var c = 0x20; c <= 0x7E; c++) {
        final char = String.fromCharCode(c);
        expect(us.strokeFor(char), isNotNull,
            reason: 'no mapping for "$char" (0x${c.toRadixString(16)})');
      }
    });
  });

  group('registry', () {
    test('every registered layout is keyed by its own id', () {
      hostLayouts.forEach((id, layout) => expect(layout.id, id));
    });

    test('every layout has a non-empty label', () {
      for (final layout in hostLayouts.values) {
        expect(layout.label, isNotEmpty);
      }
    });

    test('US is registered', () {
      expect(hostLayouts[HostLayoutId.us], isNotNull);
    });
  });
}
