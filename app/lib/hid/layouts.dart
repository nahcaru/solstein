/// Host layout data. Each layout is one const map; adding a layout requires
/// no code. Layouts ship only once verified against a real host.
library;

import 'keymap.dart';

const Map<String, KeyStroke> _usOverrides = {
  // Shifted digit row.
  '!': KeyStroke(Mod.lShift, 0x1E),
  '@': KeyStroke(Mod.lShift, 0x1F),
  '#': KeyStroke(Mod.lShift, 0x20),
  r'$': KeyStroke(Mod.lShift, 0x21),
  '%': KeyStroke(Mod.lShift, 0x22),
  '^': KeyStroke(Mod.lShift, 0x23),
  '&': KeyStroke(Mod.lShift, 0x24),
  '*': KeyStroke(Mod.lShift, 0x25),
  '(': KeyStroke(Mod.lShift, 0x26),
  ')': KeyStroke(Mod.lShift, 0x27),
  // Punctuation, unshifted then shifted.
  '-': KeyStroke(Mod.none, 0x2D),
  '_': KeyStroke(Mod.lShift, 0x2D),
  '=': KeyStroke(Mod.none, 0x2E),
  '+': KeyStroke(Mod.lShift, 0x2E),
  '[': KeyStroke(Mod.none, 0x2F),
  '{': KeyStroke(Mod.lShift, 0x2F),
  ']': KeyStroke(Mod.none, 0x30),
  '}': KeyStroke(Mod.lShift, 0x30),
  r'\': KeyStroke(Mod.none, 0x31),
  '|': KeyStroke(Mod.lShift, 0x31),
  ';': KeyStroke(Mod.none, 0x33),
  ':': KeyStroke(Mod.lShift, 0x33),
  "'": KeyStroke(Mod.none, 0x34),
  '"': KeyStroke(Mod.lShift, 0x34),
  '`': KeyStroke(Mod.none, 0x35),
  '~': KeyStroke(Mod.lShift, 0x35),
  ',': KeyStroke(Mod.none, 0x36),
  '<': KeyStroke(Mod.lShift, 0x36),
  '.': KeyStroke(Mod.none, 0x37),
  '>': KeyStroke(Mod.lShift, 0x37),
  '/': KeyStroke(Mod.none, 0x38),
  '?': KeyStroke(Mod.lShift, 0x38),
  // Whitespace.
  ' ': KeyStroke(Mod.none, Usage.space),
  '\n': KeyStroke(Mod.none, Usage.enter),
  '\t': KeyStroke(Mod.none, Usage.tab),
};

const HostLayout usLayout = HostLayout(
  id: HostLayoutId.us,
  label: 'US / ANSI',
  overrides: _usOverrides,
);

/// JIS reads the same usage codes as US but produces different characters.
///
/// Transcribed from the v1 keyboard spec, not yet confirmed against a real
/// JIS host. Unit tests cannot catch a mapping pointed at the wrong key —
/// only typing `@ : ^ ¥ ろ` on a JIS host can. See the Layout/IME section of
/// the manual checklist in docs/architecture.md.
const Map<String, KeyStroke> _jisOverrides = {
  // Digit row: shifted symbols shift left by one from & onward.
  '!': KeyStroke(Mod.lShift, 0x1E), // 1
  '"': KeyStroke(Mod.lShift, 0x1F), // 2
  '#': KeyStroke(Mod.lShift, 0x20), // 3
  r'$': KeyStroke(Mod.lShift, 0x21), // 4
  '%': KeyStroke(Mod.lShift, 0x22), // 5
  '&': KeyStroke(Mod.lShift, 0x23), // 6
  "'": KeyStroke(Mod.lShift, 0x24), // 7
  '(': KeyStroke(Mod.lShift, 0x25), // 8
  ')': KeyStroke(Mod.lShift, 0x26), // 9
  // - and = share the US - key; ^ and ~ take the US = key.
  '-': KeyStroke(Mod.none, 0x2D),
  '=': KeyStroke(Mod.lShift, 0x2D),
  '^': KeyStroke(Mod.none, 0x2E),
  '~': KeyStroke(Mod.lShift, 0x2E),
  // JIS-only keys.
  '¥': KeyStroke(Mod.none, Usage.intl3),
  '|': KeyStroke(Mod.lShift, Usage.intl3),
  r'\': KeyStroke(Mod.none, Usage.intl1), // ろ
  '_': KeyStroke(Mod.lShift, Usage.intl1),
  // @ takes the US [ position; brackets move one key right.
  '@': KeyStroke(Mod.none, 0x2F),
  '`': KeyStroke(Mod.lShift, 0x2F),
  '[': KeyStroke(Mod.none, 0x30),
  '{': KeyStroke(Mod.lShift, 0x30),
  ']': KeyStroke(Mod.none, 0x31),
  '}': KeyStroke(Mod.lShift, 0x31),
  // : is its own key rather than shift-;.
  ';': KeyStroke(Mod.none, 0x33),
  '+': KeyStroke(Mod.lShift, 0x33),
  ':': KeyStroke(Mod.none, 0x34),
  '*': KeyStroke(Mod.lShift, 0x34),
  // Unchanged from US.
  ',': KeyStroke(Mod.none, 0x36),
  '<': KeyStroke(Mod.lShift, 0x36),
  '.': KeyStroke(Mod.none, 0x37),
  '>': KeyStroke(Mod.lShift, 0x37),
  '/': KeyStroke(Mod.none, 0x38),
  '?': KeyStroke(Mod.lShift, 0x38),
  ' ': KeyStroke(Mod.none, Usage.space),
  '\n': KeyStroke(Mod.none, Usage.enter),
  '\t': KeyStroke(Mod.none, Usage.tab),
};

const HostLayout jisLayout = HostLayout(
  id: HostLayoutId.jis,
  label: 'Japanese / JIS',
  overrides: _jisOverrides,
);

const Map<HostLayoutId, HostLayout> hostLayouts = {
  HostLayoutId.us: usLayout,
  HostLayoutId.jis: jisLayout,
};
