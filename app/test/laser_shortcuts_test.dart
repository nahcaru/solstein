import 'package:flutter_test/flutter_test.dart';
import 'package:helm/hid/keymap_us.dart';
import 'package:helm/hid/laser_shortcuts.dart';
import 'package:helm/hid/shortcut_tables.dart';

void main() {
  // HID Keyboard/Keypad page usages (USB HID Usage Tables): C = 0x06, L = 0x0F.
  const usageC = 0x06, usageL = 0x0F;

  test('PowerPoint: Ctrl+L on Windows, ⌘L on macOS, none on Linux', () {
    expect(laserShortcut(DeckApp.powerpoint, TargetOs.windows),
        const KeyStroke(Mod.lCtrl, usageL));
    expect(laserShortcut(DeckApp.powerpoint, TargetOs.macos),
        const KeyStroke(Mod.lGui, usageL));
    expect(laserShortcut(DeckApp.powerpoint, TargetOs.linux), isNull);
  });

  test('Google Slides: plain L everywhere', () {
    for (final os in TargetOs.values) {
      expect(laserShortcut(DeckApp.googleSlides, os),
          const KeyStroke(Mod.none, usageL),
          reason: '$os');
    }
  });

  test('Keynote: C on macOS only', () {
    expect(laserShortcut(DeckApp.keynote, TargetOs.macos),
        const KeyStroke(Mod.none, usageC));
    expect(laserShortcut(DeckApp.keynote, TargetOs.windows), isNull);
    expect(laserShortcut(DeckApp.keynote, TargetOs.linux), isNull);
  });

  test('every app has a label', () {
    expect(DeckApp.values.map((a) => a.label),
        ['PowerPoint', 'Google Slides', 'Keynote']);
  });
}
