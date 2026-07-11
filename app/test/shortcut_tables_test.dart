import 'package:flutter_test/flutter_test.dart';
import 'package:helm/core/input_event.dart';
import 'package:helm/hid/keymap_us.dart';
import 'package:helm/hid/shortcut_tables.dart';

void main() {
  group('shortcut tables', () {
    test('every OS maps every gesture', () {
      for (final os in TargetOs.values) {
        for (final kind in GestureKind.values) {
          expect(shortcutTables[os]?[kind], isNotNull,
              reason: 'missing $os / $kind');
        }
      }
    });

    test('macOS: Mission Control and Spaces via Ctrl+arrows', () {
      expect(shortcutFor(TargetOs.macos, GestureKind.swipeUp),
          const KeyStroke(Mod.lCtrl, Usage.arrowUp));
      expect(shortcutFor(TargetOs.macos, GestureKind.swipeDown),
          const KeyStroke(Mod.lCtrl, Usage.arrowDown));
      expect(shortcutFor(TargetOs.macos, GestureKind.swipeLeft),
          const KeyStroke(Mod.lCtrl, Usage.arrowLeft));
      expect(shortcutFor(TargetOs.macos, GestureKind.swipeRight),
          const KeyStroke(Mod.lCtrl, Usage.arrowRight));
    });

    test('Windows: Task View, show desktop, virtual desktops', () {
      expect(shortcutFor(TargetOs.windows, GestureKind.swipeUp),
          const KeyStroke(Mod.lGui, 0x2B)); // Win+Tab
      expect(shortcutFor(TargetOs.windows, GestureKind.swipeDown),
          const KeyStroke(Mod.lGui, 0x07)); // Win+D
      expect(shortcutFor(TargetOs.windows, GestureKind.swipeLeft),
          const KeyStroke(Mod.lCtrl | Mod.lGui, Usage.arrowLeft));
    });

    test('Linux GNOME: bare Super means modifier-only tap (usage 0)', () {
      final activities = shortcutFor(TargetOs.linux, GestureKind.swipeUp);
      expect(activities.modifiers, Mod.lGui);
      expect(activities.usage, 0);
      expect(shortcutFor(TargetOs.linux, GestureKind.swipeLeft),
          const KeyStroke(Mod.lGui, Usage.pageUp));
      expect(shortcutFor(TargetOs.linux, GestureKind.swipeRight),
          const KeyStroke(Mod.lGui, Usage.pageDown));
    });
  });
}
