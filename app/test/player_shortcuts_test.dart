import 'package:flutter_test/flutter_test.dart';
import 'package:solstein/hid/keymap.dart';
import 'package:solstein/hid/layouts.dart';
import 'package:solstein/hid/player_shortcuts.dart';

void main() {
  // HID Keyboard/Keypad page usages: C = 0x06, F = 0x09. Letters sit at the
  // same key position on US and JIS.
  const usageC = 0x06, usageF = 0x09;

  for (final layout in hostLayouts.values) {
    test('on a ${layout.label} host: ← / → seek, C captions, F fullscreen', () {
      final s = playerShortcuts(layout)!;
      expect(s.back, const KeyStroke(Mod.none, Usage.arrowLeft));
      expect(s.forward, const KeyStroke(Mod.none, Usage.arrowRight));
      expect(s.captions, const KeyStroke(Mod.none, usageC));
      expect(s.fullscreen, const KeyStroke(Mod.none, usageF));
    });
  }
}
