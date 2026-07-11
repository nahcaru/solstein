/// Gesture → keyboard-shortcut tables per target OS (Tier 1; see
/// docs/gesture-mapping.md). Target OS is a Settings toggle in v0.1.
library;

import '../core/input_event.dart';
import 'keymap_us.dart';

enum TargetOs { macos, windows, linux }

/// Usage 0 with a non-zero modifier means "tap the modifier alone"
/// (e.g. Super → GNOME Activities).
const Map<TargetOs, Map<GestureKind, KeyStroke>> shortcutTables = {
  TargetOs.macos: {
    GestureKind.swipeUp: KeyStroke(Mod.lCtrl, Usage.arrowUp), // Mission Control
    GestureKind.swipeDown: KeyStroke(Mod.lCtrl, Usage.arrowDown), // App Exposé
    GestureKind.swipeLeft: KeyStroke(Mod.lCtrl, Usage.arrowLeft), // Space left
    GestureKind.swipeRight: KeyStroke(Mod.lCtrl, Usage.arrowRight), // Space right
  },
  TargetOs.windows: {
    GestureKind.swipeUp: KeyStroke(Mod.lGui, 0x2B), // Win+Tab Task View
    GestureKind.swipeDown: KeyStroke(Mod.lGui, 0x07), // Win+D show desktop
    GestureKind.swipeLeft: KeyStroke(Mod.lCtrl | Mod.lGui, Usage.arrowLeft),
    GestureKind.swipeRight: KeyStroke(Mod.lCtrl | Mod.lGui, Usage.arrowRight),
  },
  TargetOs.linux: {
    // GNOME defaults; other DEs are a v2 helper-side concern.
    GestureKind.swipeUp: KeyStroke(Mod.lGui, 0), // Super → Activities
    GestureKind.swipeDown: KeyStroke(Mod.lGui, 0x07), // Super+D
    GestureKind.swipeLeft: KeyStroke(Mod.lGui, Usage.pageUp),
    GestureKind.swipeRight: KeyStroke(Mod.lGui, Usage.pageDown),
  },
};

KeyStroke shortcutFor(TargetOs os, GestureKind kind) =>
    shortcutTables[os]![kind]!;
