/// Keyboard vocabulary and the host-layout seam. A layout resolves a
/// character to the key position that produces it *on the host* — the same
/// usage code means different characters under different host layouts.
/// See docs/superpowers/specs/2026-07-16-v1-keyboard-design.md.
library;

/// HID keyboard modifier bits (report byte 0).
abstract final class Mod {
  static const int none = 0x00;
  static const int lCtrl = 0x01;
  static const int lShift = 0x02;
  static const int lAlt = 0x04;
  static const int lGui = 0x08; // ⌘ on macOS, Win key on Windows, Super on Linux
  static const int rCtrl = 0x10;
  static const int rShift = 0x20;
  static const int rAlt = 0x40;
  static const int rGui = 0x80;
}

/// HID Keyboard/Keypad page usage codes for non-character keys.
abstract final class Usage {
  static const int enter = 0x28;
  static const int escape = 0x29;
  static const int backspace = 0x2A;
  static const int tab = 0x2B;
  static const int space = 0x2C;
  static const int delete = 0x4C; // forward delete
  static const int home = 0x4A;
  static const int end = 0x4D;
  static const int pageUp = 0x4B;
  static const int pageDown = 0x4E;
  static const int arrowRight = 0x4F;
  static const int arrowLeft = 0x50;
  static const int arrowDown = 0x51;
  static const int arrowUp = 0x52;
  static const int f11 = 0x44;
  static const int bracketLeft = 0x2F; // [
  static const int bracketRight = 0x30; // ]
  static const int minus = 0x2D; // - / _  (zoom out)
  static const int equal = 0x2E; // = / +  (zoom in)
  static const int lang1 = 0x90; // かな / Hangul toggle
  static const int lang2 = 0x91; // 英数 / Hanja
  static const int intl1 = 0x87; // ろ / backslash on JIS
  static const int intl3 = 0x89; // ¥ on JIS
}

/// A resolved keystroke: modifier bitmask + usage code.
class KeyStroke {
  const KeyStroke(this.modifiers, this.usage);

  final int modifiers;
  final int usage;

  @override
  bool operator ==(Object other) =>
      other is KeyStroke &&
      other.modifiers == modifiers &&
      other.usage == usage;

  @override
  int get hashCode => Object.hash(modifiers, usage);

  @override
  String toString() =>
      'KeyStroke(mods: 0x${modifiers.toRadixString(16)}, usage: 0x${usage.toRadixString(16)})';
}

enum HostLayoutId { us, jis }

const int _usageA = 0x04;
const int _usage1 = 0x1E;

/// Letters and digits at their QWERTY positions. Layouts that move letters
/// (QWERTZ swaps y/z, AZERTY swaps a/q and z/w) override them instead.
KeyStroke? _qwertyAlnum(String char) {
  final code = char.codeUnitAt(0);
  if (code >= 0x61 && code <= 0x7A) {
    return KeyStroke(Mod.none, _usageA + (code - 0x61)); // a–z
  }
  if (code >= 0x41 && code <= 0x5A) {
    return KeyStroke(Mod.lShift, _usageA + (code - 0x41)); // A–Z
  }
  if (code >= 0x31 && code <= 0x39) {
    return KeyStroke(Mod.none, _usage1 + (code - 0x31)); // 1–9
  }
  if (code == 0x30) return const KeyStroke(Mod.none, 0x27); // 0
  return null;
}

/// A host keyboard layout: the shared QWERTY alphanumeric core plus
/// [overrides], which win. A new layout is a data-only addition.
class HostLayout {
  const HostLayout({
    required this.id,
    required this.label,
    required this.overrides,
  });

  final HostLayoutId id;

  /// Shown in Settings.
  final String label;

  /// Everything this layout does differently from bare QWERTY: symbols,
  /// whitespace, and — for non-QWERTY layouts — letters.
  final Map<String, KeyStroke> overrides;

  /// The keystroke that produces [char] on this host layout, or null if the
  /// layout cannot produce it.
  KeyStroke? strokeFor(String char) {
    if (char.length != 1) return null;
    return overrides[char] ?? _qwertyAlnum(char);
  }
}
