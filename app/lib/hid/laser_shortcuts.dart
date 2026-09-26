/// Shortcuts that switch on a presentation app's own laser pointer.
///
/// Rendering an on-screen laser or spotlight normally needs software on the
/// computer (see docs/roadmap.md, v2 helper). These apps ship one built in,
/// and the phone already moves the host cursor, so toggling the built-in laser
/// gives a visible dot with nothing installed. The host toggles on every
/// press; there is no way to read its state back.
///
/// **Not verified on hardware.** Candidates from the apps' published shortcut
/// lists — confirm each in a real slideshow and correct the table (and its
/// test) where one is wrong.
library;

import 'keymap.dart';
import 'shortcut_tables.dart';

enum DeckApp {
  powerpoint('PowerPoint'),
  googleSlides('Google Slides'),
  keynote('Keynote');

  const DeckApp(this.label);
  final String label;
}

/// The keystroke that toggles [app]'s laser pointer on [os], or null when the
/// app has none there (Keynote runs only on macOS, PowerPoint not on Linux).
/// The letter comes from the host's [layout], since the apps react to the
/// character the key produces.
///
/// Keynote also needs Preferences › Slideshow › "Show pointer when the mouse
/// moves" turned on for the pointer to appear.
KeyStroke? laserShortcut(DeckApp app, TargetOs os, HostLayout layout) {
  final l = layout.strokeFor('l');
  final c = layout.strokeFor('c');
  if (l == null || c == null) return null;
  return switch ((app, os)) {
    (DeckApp.powerpoint, TargetOs.windows) => KeyStroke(Mod.lCtrl, l.usage),
    (DeckApp.powerpoint, TargetOs.macos) => KeyStroke(Mod.lGui, l.usage),
    (DeckApp.googleSlides, _) => l,
    (DeckApp.keynote, TargetOs.macos) => c,
    _ => null,
  };
}
