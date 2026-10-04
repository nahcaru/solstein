import 'package:flutter_test/flutter_test.dart';
import 'package:solstein/hid/ime_keys.dart';
import 'package:solstein/hid/keymap.dart';
import 'package:solstein/hid/shortcut_tables.dart';

void main() {
  group('IME keys', () {
    test('macOS uses LANG1 for かな and LANG2 for 英数', () {
      final keys = imeKeysFor(TargetOs.macos)!;
      expect(keys[ImeKey.kana], const KeyStroke(Mod.none, Usage.lang1));
      expect(keys[ImeKey.eisu], const KeyStroke(Mod.none, Usage.lang2));
    });

    test('unverified OSes return null so the row stays hidden', () {
      // Populate only when confirmed against real hardware; a guessed usage
      // is worse than no key, because it fails silently.
      expect(imeKeysFor(TargetOs.windows), isNull);
      expect(imeKeysFor(TargetOs.linux), isNull);
    });

    test('a populated table defines both keys', () {
      for (final os in TargetOs.values) {
        final keys = imeKeysFor(os);
        if (keys == null) continue;
        expect(keys[ImeKey.kana], isNotNull, reason: '$os is missing かな');
        expect(keys[ImeKey.eisu], isNotNull, reason: '$os is missing 英数');
      }
    });
  });
}
