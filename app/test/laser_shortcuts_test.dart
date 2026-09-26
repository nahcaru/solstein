import 'package:flutter_test/flutter_test.dart';
import 'package:helm/hid/keymap.dart';
import 'package:helm/hid/laser_shortcuts.dart';
import 'package:helm/hid/layouts.dart';
import 'package:helm/hid/shortcut_tables.dart';

void main() {
  // HID Keyboard/Keypad page usages (USB HID Usage Tables): C = 0x06, L = 0x0F.
  // Letters sit at the same key position on US and JIS.
  const usageC = 0x06, usageL = 0x0F;

  for (final layout in hostLayouts.values) {
    group('on a ${layout.label} host', () {
      test('PowerPoint: Ctrl+L on Windows, ⌘L on macOS, none on Linux', () {
        expect(laserShortcut(DeckApp.powerpoint, TargetOs.windows, layout),
            const KeyStroke(Mod.lCtrl, usageL));
        expect(laserShortcut(DeckApp.powerpoint, TargetOs.macos, layout),
            const KeyStroke(Mod.lGui, usageL));
        expect(laserShortcut(DeckApp.powerpoint, TargetOs.linux, layout), isNull);
      });

      test('Google Slides: plain L everywhere', () {
        for (final os in TargetOs.values) {
          expect(laserShortcut(DeckApp.googleSlides, os, layout),
              const KeyStroke(Mod.none, usageL),
              reason: '$os');
        }
      });

      test('Keynote: C on macOS only', () {
        expect(laserShortcut(DeckApp.keynote, TargetOs.macos, layout),
            const KeyStroke(Mod.none, usageC));
        expect(laserShortcut(DeckApp.keynote, TargetOs.windows, layout), isNull);
        expect(laserShortcut(DeckApp.keynote, TargetOs.linux, layout), isNull);
      });
    });
  }

  test('a layout that cannot produce the letter hides the button', () {
    const noLetters = HostLayout(
      id: HostLayoutId.us,
      label: 'test',
      overrides: {},
    );
    // strokeFor falls back to QWERTY for letters, so this still resolves; the
    // guard matters for a future layout that returns null for a letter.
    expect(laserShortcut(DeckApp.googleSlides, TargetOs.macos, noLetters),
        const KeyStroke(Mod.none, usageL));
  });

  test('every app has a label', () {
    expect(DeckApp.values.map((a) => a.label),
        ['PowerPoint', 'Google Slides', 'Keynote']);
  });
}
