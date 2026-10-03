/// Keystrokes for the controls a media player offers beyond the Consumer
/// Control keys: seek, captions and fullscreen.
///
/// HID's consumer page has no usage for any of these, so Media mode sends
/// ordinary keys. One set covers the web players checked against their
/// official shortcut pages (2026-10-04):
///
/// | Player        | ← / → seek | C captions | F fullscreen |
/// |---------------|------------|------------|--------------|
/// | YouTube       | 5 s        | yes        | yes          |
/// | Netflix       | 10 s       | no key     | yes          |
/// | Prime Video   | 10 s       | yes        | yes          |
///
/// A button whose key the player lacks does nothing (Netflix has no captions
/// shortcut). Players that differ — VLC seeks with Shift/Alt/Ctrl + arrow and
/// uses V for subtitles; Spotify seeks with Shift + arrow — are not covered;
/// supporting one means adding a set and a way to choose it. The host cannot
/// be asked what is playing, so it could not be chosen automatically.
///
/// The steps are the player's, so the buttons say "Seek", not "10 s".
library;

import 'keymap.dart';

class PlayerShortcuts {
  const PlayerShortcuts({
    required this.back,
    required this.forward,
    required this.captions,
    required this.fullscreen,
  });

  final KeyStroke back;
  final KeyStroke forward;
  final KeyStroke captions;
  final KeyStroke fullscreen;
}

/// The player keys, or null when [layout] cannot produce a letter they need
/// (the row is then hidden). Letters come from the host's [layout], since
/// players react to the character the key produces.
PlayerShortcuts? playerShortcuts(HostLayout layout) {
  final c = layout.strokeFor('c');
  final f = layout.strokeFor('f');
  if (c == null || f == null) return null;
  return PlayerShortcuts(
    back: const KeyStroke(Mod.none, Usage.arrowLeft),
    forward: const KeyStroke(Mod.none, Usage.arrowRight),
    captions: c,
    fullscreen: f,
  );
}
