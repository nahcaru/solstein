/// US keyboard layout: character → (modifiers, HID usage). v0.1 is US-only;
/// CJK/IME is a v1 problem (see docs/hid-descriptor.md).
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

const int _usageA = 0x04;
const int _usage1 = 0x1E;

/// Shifted-symbol → base-key usage for the US layout.
const Map<String, int> _shiftedSymbols = {
  '!': 0x1E, '@': 0x1F, '#': 0x20, r'$': 0x21, '%': 0x22,
  '^': 0x23, '&': 0x24, '*': 0x25, '(': 0x26, ')': 0x27,
  '_': 0x2D, '+': 0x2E, '{': 0x2F, '}': 0x30, '|': 0x31,
  ':': 0x33, '"': 0x34, '~': 0x35, '<': 0x36, '>': 0x37, '?': 0x38,
};

/// Unshifted symbols and whitespace.
const Map<String, int> _plainSymbols = {
  '-': 0x2D, '=': 0x2E, '[': 0x2F, ']': 0x30, r'\': 0x31,
  ';': 0x33, "'": 0x34, '`': 0x35, ',': 0x36, '.': 0x37, '/': 0x38,
  ' ': Usage.space, '\n': Usage.enter, '\t': Usage.tab,
};

/// Resolves a single character to a [KeyStroke] on the US layout.
/// Returns null for characters the layout cannot produce.
KeyStroke? keyStrokeForChar(String char) {
  if (char.length != 1) return null;
  final code = char.codeUnitAt(0);

  // a–z
  if (code >= 0x61 && code <= 0x7A) {
    return KeyStroke(Mod.none, _usageA + (code - 0x61));
  }
  // A–Z
  if (code >= 0x41 && code <= 0x5A) {
    return KeyStroke(Mod.lShift, _usageA + (code - 0x41));
  }
  // 1–9
  if (code >= 0x31 && code <= 0x39) {
    return KeyStroke(Mod.none, _usage1 + (code - 0x31));
  }
  // 0
  if (code == 0x30) return const KeyStroke(Mod.none, 0x27);

  final plain = _plainSymbols[char];
  if (plain != null) return KeyStroke(Mod.none, plain);

  final shifted = _shiftedSymbols[char];
  if (shifted != null) return KeyStroke(Mod.lShift, shifted);

  return null;
}
