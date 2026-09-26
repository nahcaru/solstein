/// Host IME toggle keys, per target OS.
///
/// CJK input over HID works because the *host's* IME converts romaji sent as
/// ordinary usage codes (see the v1 keyboard spec). These keys let the phone
/// toggle that IME instead of the user reaching for the host.
///
/// macOS: Apple JIS keyboards send LANG1/LANG2, which double as Hangul/Hanja —
/// one pair covers Japanese, Korean, and Pinyin.
///
/// Windows and Linux are **unverified**. A guessed usage is worse than no key:
/// it fails silently, which is exactly the class of bug the descriptor gotchas
/// in docs/hid-descriptor.md warn about. Null hides the row.
library;

import 'keymap.dart';
import 'shortcut_tables.dart';

enum ImeKey { kana, eisu }

const Map<TargetOs, Map<ImeKey, KeyStroke>> _imeKeyTables = {
  TargetOs.macos: {
    ImeKey.kana: KeyStroke(Mod.none, Usage.lang1),
    ImeKey.eisu: KeyStroke(Mod.none, Usage.lang2),
  },
};

/// The IME keys for [os], or null when this OS has no verified keys.
Map<ImeKey, KeyStroke>? imeKeysFor(TargetOs os) => _imeKeyTables[os];
