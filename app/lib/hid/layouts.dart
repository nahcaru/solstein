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

const Map<HostLayoutId, HostLayout> hostLayouts = {
  HostLayoutId.us: usLayout,
};
