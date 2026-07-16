/// Gesture → keyboard-shortcut tables per target OS (Tier 1; see
/// docs/gesture-mapping.md). Target OS is a Settings toggle in v0.1.
library;

import '../core/input_event.dart';
import 'keymap.dart';

enum TargetOs { macos, windows, linux }

/// Usage 0 with a non-zero modifier means "tap the modifier alone"
/// (e.g. Super → GNOME Activities).
const Map<TargetOs, Map<GestureKind, KeyStroke>> shortcutTables = {
  TargetOs.macos: {
    GestureKind.swipeUp: KeyStroke(Mod.lCtrl, Usage.arrowUp), // Mission Control
    GestureKind.swipeDown: KeyStroke(Mod.lCtrl, Usage.arrowDown), // App Exposé
    GestureKind.swipeLeft: KeyStroke(Mod.lCtrl, Usage.arrowLeft), // Space left
    GestureKind.swipeRight: KeyStroke(Mod.lCtrl, Usage.arrowRight), // Space right
    GestureKind.pageSwipeLeft: KeyStroke(Mod.lGui, Usage.bracketLeft), // Back
    GestureKind.pageSwipeRight: KeyStroke(Mod.lGui, Usage.bracketRight), // Fwd
    GestureKind.spread: KeyStroke(Mod.none, Usage.f11), // Show desktop
    GestureKind.pinch: KeyStroke(Mod.none, Usage.f11), // Restore windows
    GestureKind.zoomIn: KeyStroke(Mod.lGui, Usage.equal), // Cmd+=
    GestureKind.zoomOut: KeyStroke(Mod.lGui, Usage.minus), // Cmd+-
  },
  TargetOs.windows: {
    GestureKind.swipeUp: KeyStroke(Mod.lGui, 0x2B), // Win+Tab Task View
    GestureKind.swipeDown: KeyStroke(Mod.lGui, 0x07), // Win+D show desktop
    GestureKind.swipeLeft: KeyStroke(Mod.lCtrl | Mod.lGui, Usage.arrowLeft),
    GestureKind.swipeRight: KeyStroke(Mod.lCtrl | Mod.lGui, Usage.arrowRight),
    GestureKind.pageSwipeLeft: KeyStroke(Mod.lAlt, Usage.arrowLeft), // Back
    GestureKind.pageSwipeRight: KeyStroke(Mod.lAlt, Usage.arrowRight), // Fwd
    GestureKind.spread: KeyStroke(Mod.lGui, 0x07), // Win+D show desktop
    GestureKind.pinch: KeyStroke(Mod.lGui, 0x07), // Win+D restore
    GestureKind.zoomIn: KeyStroke(Mod.lCtrl, Usage.equal), // Ctrl+=
    GestureKind.zoomOut: KeyStroke(Mod.lCtrl, Usage.minus), // Ctrl+-
  },
  TargetOs.linux: {
    // GNOME defaults; other DEs are a v2 helper-side concern.
    GestureKind.swipeUp: KeyStroke(Mod.lGui, 0), // Super → Activities
    GestureKind.swipeDown: KeyStroke(Mod.lGui, 0x07), // Super+D
    GestureKind.swipeLeft: KeyStroke(Mod.lGui, Usage.pageUp),
    GestureKind.swipeRight: KeyStroke(Mod.lGui, Usage.pageDown),
    GestureKind.pageSwipeLeft: KeyStroke(Mod.lAlt, Usage.arrowLeft), // Back
    GestureKind.pageSwipeRight: KeyStroke(Mod.lAlt, Usage.arrowRight), // Fwd
    GestureKind.spread: KeyStroke(Mod.lGui, 0x07), // Super+D show desktop
    GestureKind.pinch: KeyStroke(Mod.lGui, 0x07), // Super+D restore
    GestureKind.zoomIn: KeyStroke(Mod.lCtrl, Usage.equal), // Ctrl+=
    GestureKind.zoomOut: KeyStroke(Mod.lCtrl, Usage.minus), // Ctrl+-
  },
};

KeyStroke shortcutFor(TargetOs os, GestureKind kind) =>
    shortcutTables[os]![kind]!;

/// Best-effort OS guess from a Bluetooth device name. No API exposes a
/// host's OS, but default hostnames are strong hints ("Taira's MacBook
/// Pro", "DESKTOP-A1B2C3", "ubuntu-desktop"). Null when unrecognizable —
/// callers keep their current setting.
TargetOs? guessTargetOs(String name) {
  final n = name.toLowerCase();
  if (n.contains('mac')) return TargetOs.macos; // MacBook, iMac, Mac mini
  if (n.contains('windows') ||
      n.startsWith('desktop-') ||
      n.startsWith('laptop-')) {
    return TargetOs.windows;
  }
  const linuxHints = ['linux', 'ubuntu', 'fedora', 'debian', 'arch', 'mint'];
  if (linuxHints.any(n.contains)) return TargetOs.linux;
  return null;
}
