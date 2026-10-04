import 'package:flutter_test/flutter_test.dart';
import 'package:solstein/hid/keymap.dart';
import 'package:solstein/hid/layouts.dart';

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

  group('JIS layout', () {
    final jis = hostLayouts[HostLayoutId.jis]!;

    test('letters and digits match QWERTY', () {
      expect(jis.strokeFor('a'), const KeyStroke(Mod.none, 0x04));
      expect(jis.strokeFor('Z'), const KeyStroke(Mod.lShift, 0x1D));
      expect(jis.strokeFor('0'), const KeyStroke(Mod.none, 0x27));
    });

    test('digit-row symbols shift left from & onward', () {
      expect(jis.strokeFor('&'), const KeyStroke(Mod.lShift, 0x23)); // 6, not 7
      expect(jis.strokeFor("'"), const KeyStroke(Mod.lShift, 0x24)); // 7
      expect(jis.strokeFor('('), const KeyStroke(Mod.lShift, 0x25)); // 8
      expect(jis.strokeFor(')'), const KeyStroke(Mod.lShift, 0x26)); // 9
      expect(jis.strokeFor('"'), const KeyStroke(Mod.lShift, 0x1F)); // 2
    });

    test('@ sits at the US [ position', () {
      expect(jis.strokeFor('@'), const KeyStroke(Mod.none, 0x2F));
      expect(jis.strokeFor('`'), const KeyStroke(Mod.lShift, 0x2F));
    });

    test('brackets move one key right', () {
      expect(jis.strokeFor('['), const KeyStroke(Mod.none, 0x30));
      expect(jis.strokeFor(']'), const KeyStroke(Mod.none, 0x31));
    });

    test('colon and semicolon are separate keys', () {
      expect(jis.strokeFor(';'), const KeyStroke(Mod.none, 0x33));
      expect(jis.strokeFor(':'), const KeyStroke(Mod.none, 0x34));
      expect(jis.strokeFor('*'), const KeyStroke(Mod.lShift, 0x34));
    });

    test('JIS-only keys: ¥ on International3, backslash is Option+¥', () {
      expect(jis.strokeFor('¥'), const KeyStroke(Mod.none, Usage.intl3));
      expect(jis.strokeFor('|'), const KeyStroke(Mod.lShift, Usage.intl3));
      expect(jis.strokeFor(r'\'), const KeyStroke(Mod.lAlt, Usage.intl3));
      expect(jis.strokeFor('_'), const KeyStroke(Mod.lShift, Usage.intl1));
    });

    test('caret and tilde live on the US = key', () {
      expect(jis.strokeFor('^'), const KeyStroke(Mod.none, 0x2E));
      expect(jis.strokeFor('~'), const KeyStroke(Mod.lShift, 0x2E));
      expect(jis.strokeFor('='), const KeyStroke(Mod.lShift, 0x2D));
    });

    test('every printable ASCII character is mappable', () {
      for (var c = 0x20; c <= 0x7E; c++) {
        final char = String.fromCharCode(c);
        expect(jis.strokeFor(char), isNotNull,
            reason: 'no mapping for "$char" (0x${c.toRadixString(16)})');
      }
    });

    test('CJK is still unmappable — the host IME converts romaji instead', () {
      expect(jis.strokeFor('日'), isNull);
      expect(jis.strokeFor('あ'), isNull);
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

    test('every HostLayoutId has a layout', () {
      for (final id in HostLayoutId.values) {
        expect(hostLayouts[id], isNotNull, reason: 'no layout for $id');
      }
    });

    test('strokeFor is injective for every registered layout', () {
      // A layout that moves letters (QWERTZ, AZERTY) must override them, not
      // just symbols. If a future table forgets one, the fallback silently
      // returns the QWERTY key for it — so that letter and whatever
      // character legitimately owns the displaced key resolve to the same
      // KeyStroke. Sweeping printable ASCII plus ¥ (JIS) and asserting no
      // two distinct characters collide catches that even though both
      // resolve non-null.
      final sweep = [
        for (var c = 0x20; c <= 0x7E; c++) String.fromCharCode(c),
        '¥',
      ];
      for (final layout in hostLayouts.values) {
        final seen = <KeyStroke, String>{};
        for (final char in sweep) {
          final stroke = layout.strokeFor(char);
          if (stroke == null) continue;
          final prior = seen[stroke];
          expect(prior, isNull,
              reason: '${layout.label}: "$prior" and "$char" both resolve '
                  'to $stroke');
          seen[stroke] = char;
        }
      }
    });
  });
}
