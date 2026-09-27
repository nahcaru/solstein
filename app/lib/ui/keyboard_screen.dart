import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../core/input_event.dart';
import '../core/input_sink.dart';
import '../hid/ime_keys.dart';
import '../hid/keymap.dart';
import '../hid/shortcut_tables.dart';

/// Keyboard input: a text field that forwards keystrokes (resolved through
/// the host's keyboard layout), a 3×4 grid mixing modifiers in among
/// navigation keys ([_keyGridRows]), and a media row.
/// Modifiers are one-shot (sticky-keys style): toggle ⌘, tap a key, modifier
/// releases. The modifier lineup and labels follow the target OS.
class KeyboardScreen extends StatefulWidget {
  const KeyboardScreen({
    super.key,
    required this.sink,
    required this.targetOs,
    required this.hostLayout,
    required this.showImeKeys,
  });

  final InputSink sink;
  final TargetOs targetOs;
  final HostLayout hostLayout;
  final bool showImeKeys;

  @override
  State<KeyboardScreen> createState() => _KeyboardScreenState();
}

/// A modifier key: either a dedicated icon (with a [tooltip] naming it, since
/// the glyph alone can't) or a text [label], never both. [testKey] identifies
/// the button in widget tests independent of which one it renders as.
class _ModifierSpec {
  const _ModifierSpec.icon(
    this.icon,
    this.tooltip,
    this.bit,
    this.testKey, {
    this.showCaption = false,
  }) : label = null;
  const _ModifierSpec.label(this.label, this.bit, this.testKey)
      : icon = null,
        tooltip = null,
        showCaption = false;

  final String? label;
  final IconData? icon;
  final String? tooltip;
  final int bit;
  final String testKey;

  /// Control/Option/Command print their name below the symbol, the way a
  /// physical Mac keyboard does — Shift doesn't need the same help.
  final bool showCaption;
}

/// Modifier lineup per target OS: native order and naming. Every OS shows the
/// same dedicated icon for Ctrl/Shift (they're the same key everywhere); ⌘/⌥
/// get macOS's own icons. Win, Super, and Alt stay text — no Windows-logo or
/// Super icon exists, and "Alt" reads clearer as text than as a generic icon.
const Map<TargetOs, List<_ModifierSpec>> _modifierRows = {
  TargetOs.macos: [
    _ModifierSpec.icon(Icons.keyboard_control_key, 'Control', Mod.lCtrl, 'mod-ctrl', showCaption: true),
    _ModifierSpec.icon(Icons.keyboard_option_key, 'Option', Mod.lAlt, 'mod-alt', showCaption: true),
    _ModifierSpec.icon(Icons.keyboard_command_key, 'Command', Mod.lGui, 'mod-gui', showCaption: true),
    _ModifierSpec.icon(Symbols.shift, 'Shift', Mod.lShift, 'mod-shift'),
  ],
  TargetOs.windows: [
    _ModifierSpec.icon(Icons.keyboard_control_key, 'Control', Mod.lCtrl, 'mod-ctrl', showCaption: true),
    _ModifierSpec.label('Win', Mod.lGui, 'mod-gui'),
    _ModifierSpec.label('Alt', Mod.lAlt, 'mod-alt'),
    _ModifierSpec.icon(Symbols.shift, 'Shift', Mod.lShift, 'mod-shift'),
  ],
  TargetOs.linux: [
    _ModifierSpec.icon(Icons.keyboard_control_key, 'Control', Mod.lCtrl, 'mod-ctrl', showCaption: true),
    _ModifierSpec.label('Super', Mod.lGui, 'mod-gui'),
    _ModifierSpec.label('Alt', Mod.lAlt, 'mod-alt'),
    _ModifierSpec.icon(Symbols.shift, 'Shift', Mod.lShift, 'mod-shift'),
  ],
};

/// The modifier row and the nav/arrow row are no longer separate: this is
/// three rows of four keys each, mixing modifiers in among navigation keys.
/// Each entry is a key identifier — 'mod-*' resolves against the current
/// OS's modifier spec, everything else is a fixed nav/arrow key.
const List<List<String>> _keyGridRows = [
  ['nav-esc', 'nav-tab', 'mod-ctrl', 'nav-enter'],
  ['mod-alt', 'mod-gui', 'nav-up', 'nav-backspace'],
  ['mod-shift', 'nav-left', 'nav-down', 'nav-right'],
];

class _KeyboardScreenState extends State<KeyboardScreen> {
  final _controller = TextEditingController();
  int _heldModifiers = 0;
  String _lastText = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Sends a HID keystroke, ORing in any held modifier and then consuming it
  /// (one-shot: it applies to exactly one key).
  ///
  /// [trackedByDiff] must be true only for calls from [_onTextChanged]'s own
  /// diff loop — that loop tracks the buffer itself and, after the fact,
  /// decides whether the result can be trusted (see the taint check there).
  /// Every other caller (nav row, IME keys row) sends a keystroke the buffer
  /// never accounted for, so by default this resets the buffer immediately:
  /// the field and the host are about to disagree, and an empty field is
  /// the one state that's always true to what the host has received.
  void _sendStroke(int usage, int modifiers, {bool trackedByDiff = false}) {
    final mods = modifiers | _heldModifiers;
    widget.sink.send(KeyInput(usage, mods, down: true));
    widget.sink.send(KeyInput(usage, mods, down: false));
    if (_heldModifiers != 0) setState(() => _heldModifiers = 0);
    if (!trackedByDiff) _resetBuffer();
  }

  /// Collapses the buffer to the one state that's always safe: empty holds
  /// nothing unsent. Used whenever a keystroke reaches the host by a path
  /// the diff loop doesn't account for, or when the diff loop's own send
  /// turned out not to be trustworthy (see the taint check in
  /// [_onTextChanged]) — same remedy as the overflow trim below, reused
  /// rather than repeated.
  void _resetBuffer() {
    _lastText = '';
    _controller.value = const TextEditingValue(
      text: '',
      selection: TextSelection.collapsed(offset: 0),
    );
  }

  void _toggleModifier(int bit) {
    setState(() => _heldModifiers ^= bit);
  }

  /// Diffs the text field against its previous value: removals become
  /// backspaces, additions become keystrokes.
  ///
  /// Invariant: the field only ever holds text the host is known to have
  /// received, character for character, via this diff. Anything that would
  /// break that gets a full reset ([_resetBuffer]) instead of a best-effort
  /// patch-up:
  ///  - a character the host layout cannot produce is refused rather than
  ///    silently dropped;
  ///  - a stroke sent while a modifier was held reaches the host as a
  ///    shortcut, not as the plain key — the loop below detects that
  ///    ("tainted") and collapses `settled` to empty rather than recording a
  ///    character the host never actually typed;
  ///  - a keystroke sent from outside this diff entirely (nav row, IME keys)
  ///    resets via [_sendStroke]'s own default.
  /// An empty buffer always satisfies the invariant, which is why every one
  /// of these lands there instead of trying to reconstruct the real state.
  void _onTextChanged(String text) {
    var common = 0;
    while (common < _lastText.length &&
        common < text.length &&
        _lastText.codeUnitAt(common) == text.codeUnitAt(common)) {
      common++;
    }
    var tainted = false;
    for (var i = 0; i < _lastText.length - common; i++) {
      if (_heldModifiers != 0) tainted = true;
      _sendStroke(Usage.backspace, Mod.none, trackedByDiff: true);
    }

    final accepted = StringBuffer(text.substring(0, common));
    final refused = <String>[];
    for (final char in text.substring(common).characters) {
      final stroke = widget.hostLayout.strokeFor(char);
      if (stroke == null) {
        refused.add(char);
        continue;
      }
      if (_heldModifiers != 0) tainted = true;
      _sendStroke(stroke.usage, stroke.modifiers, trackedByDiff: true);
      accepted.write(char);
    }

    // Collapse to empty if any stroke above was tainted by a held modifier,
    // or to keep the buffer from growing without bound.
    if (tainted || accepted.length > 200) {
      _resetBuffer();
    } else {
      final settled = accepted.toString();
      _lastText = settled;
      if (settled != text) {
        // Programmatic edits do not re-enter onChanged.
        _controller.value = TextEditingValue(
          text: settled,
          selection: TextSelection.collapsed(offset: settled.length),
        );
      }
    }

    if (refused.isNotEmpty) _reportRefused(refused);
  }

  void _reportRefused(List<String> chars) {
    final unique = chars.toSet().join(' ');
    final layout = widget.hostLayout.label;
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('$unique isn\'t on the $layout keyboard layout'),
      ));
  }

  _Key _modifierKey(_ModifierSpec spec) => _Key(
        key: ValueKey(spec.testKey),
        label: spec.label,
        icon: spec.icon,
        tooltip: spec.tooltip,
        caption: spec.showCaption ? spec.tooltip : null,
        active: _heldModifiers & spec.bit != 0,
        onTap: () => _toggleModifier(spec.bit),
      );

  /// The eight keys that are never modifiers: esc/tab/backspace/enter and
  /// the four arrows. Split out from [_keyGridRows] so their icons/tooltips
  /// live in exactly one place regardless of which row they're placed in.
  _Key _fixedKey(String id) => switch (id) {
        'nav-esc' => _Key(
            key: const ValueKey('nav-esc'),
            label: 'esc',
            onTap: () => _sendStroke(Usage.escape, Mod.none),
          ),
        'nav-tab' => _Key(
            key: const ValueKey('nav-tab'),
            icon: Icons.keyboard_tab,
            tooltip: 'Tab',
            onTap: () => _sendStroke(Usage.tab, Mod.none),
          ),
        'nav-backspace' => _Key(
            key: const ValueKey('nav-backspace'),
            icon: Icons.backspace,
            tooltip: 'Backspace',
            onTap: () => _sendStroke(Usage.backspace, Mod.none),
          ),
        'nav-enter' => _Key(
            key: const ValueKey('nav-enter'),
            icon: Icons.keyboard_return,
            tooltip: 'Enter',
            onTap: () => _sendStroke(Usage.enter, Mod.none),
          ),
        'nav-left' => _Key(
            key: const ValueKey('nav-left'),
            icon: Symbols.arrow_left_alt,
            tooltip: 'Left',
            onTap: () => _sendStroke(Usage.arrowLeft, Mod.none),
          ),
        'nav-up' => _Key(
            key: const ValueKey('nav-up'),
            icon: Symbols.arrow_upward_alt,
            tooltip: 'Up',
            onTap: () => _sendStroke(Usage.arrowUp, Mod.none),
          ),
        'nav-down' => _Key(
            key: const ValueKey('nav-down'),
            icon: Symbols.arrow_downward_alt,
            tooltip: 'Down',
            onTap: () => _sendStroke(Usage.arrowDown, Mod.none),
          ),
        'nav-right' => _Key(
            key: const ValueKey('nav-right'),
            icon: Symbols.arrow_right_alt,
            tooltip: 'Right',
            onTap: () => _sendStroke(Usage.arrowRight, Mod.none),
          ),
        _ => throw ArgumentError('unknown fixed key id: $id'),
      };

  Widget _keyRow(List<Widget> keys) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            for (var i = 0; i < keys.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(child: keys[i]),
            ],
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final modifiers =
        _modifierRows[widget.targetOs] ?? _modifierRows[TargetOs.macos]!;
    final modsByKey = {for (final s in modifiers) s.testKey: s};
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _controller,
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.visiblePassword,
            maxLines: 3,
            minLines: 1,
            onChanged: _onTextChanged,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Type here — keystrokes go to the computer',
            ),
          ),
        ),
        for (var i = 0; i < _keyGridRows.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _keyRow([
            for (final id in _keyGridRows[i])
              id.startsWith('mod-')
                  ? _modifierKey(modsByKey[id]!)
                  : _fixedKey(id),
          ]),
        ],
        if (widget.showImeKeys) ...[
          const SizedBox(height: 8),
          Builder(builder: (context) {
            final keys = imeKeysFor(widget.targetOs);
            if (keys == null) return const SizedBox.shrink();
            // Force-unwrapped: safe because `keys` is non-null here, and
            // ime_keys_test.dart's "a populated table defines both keys"
            // asserts every populated table in _imeKeyTables has both
            // ImeKey.kana and ImeKey.eisu. A future table (e.g. Windows,
            // once verified against hardware) that defines one but not the
            // other passes that check silently at compile time and NPEs
            // here at runtime instead of failing the build — keep the test
            // in sync with any new table.
            return _keyRow([
              _Key(
                label: '英数',
                onTap: () => _sendStroke(
                    keys[ImeKey.eisu]!.usage, keys[ImeKey.eisu]!.modifiers),
              ),
              _Key(
                label: 'かな',
                onTap: () => _sendStroke(
                    keys[ImeKey.kana]!.usage, keys[ImeKey.kana]!.modifiers),
              ),
            ]);
          }),
        ],
        if (widget.sink.capabilities.contains(Capability.mediaKeys)) ...[
          const SizedBox(height: 8),
          _keyRow([
            _Key(icon: Icons.brightness_low, onTap: () => _media(MediaKey.brightnessDown)),
            _Key(icon: Icons.brightness_high, onTap: () => _media(MediaKey.brightnessUp)),
            _Key(icon: Icons.skip_previous, onTap: () => _media(MediaKey.prevTrack)),
            _Key(icon: Icons.play_arrow, onTap: () => _media(MediaKey.playPause)),
            _Key(icon: Icons.skip_next, onTap: () => _media(MediaKey.nextTrack)),
            _Key(icon: Icons.volume_off, onTap: () => _media(MediaKey.mute)),
            _Key(icon: Icons.volume_down, onTap: () => _media(MediaKey.volumeDown)),
            _Key(icon: Icons.volume_up, onTap: () => _media(MediaKey.volumeUp)),
          ]),
        ],
        const SizedBox(height: 12),
      ],
    );
  }

  void _media(MediaKey key) => widget.sink.send(MediaTap(key));
}

/// The one key style used across modifier, navigation, and media rows.
/// Modifiers pass [active] to render latched (filled) state. An icon key
/// needs [tooltip] naming it — unlike a text label, the glyph alone doesn't.
class _Key extends StatelessWidget {
  const _Key({
    super.key,
    this.label,
    this.icon,
    this.tooltip,
    this.caption,
    required this.onTap,
    this.active = false,
  })  : assert(label != null || icon != null),
        assert(caption == null || icon != null,
            'caption prints below the icon; it needs one to sit under');

  final String? label;
  final IconData? icon;
  final String? tooltip;

  /// A short word printed below the icon, e.g. "Control" under ⌃ — the way a
  /// physical Mac keyboard prints the name under the symbol. Height stays 44:
  /// the icon shrinks slightly to leave room for it.
  final String? caption;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = active ? scheme.onPrimaryContainer : scheme.onSurface;
    final Widget content;
    if (icon != null && caption != null) {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(height: 2),
          Text(
            caption!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 9, color: fg),
          ),
        ],
      );
    } else if (icon != null) {
      content = Icon(icon, size: 20, color: fg);
    } else {
      content = Text(
        label!,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: label!.length > 2 ? 14 : 18,
          fontWeight: active ? FontWeight.w600 : FontWeight.w400,
          color: fg,
        ),
      );
    }
    final key = SizedBox(
      height: 44,
      child: Material(
        color: active ? scheme.primaryContainer : scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Center(child: content),
        ),
      ),
    );
    return tooltip != null ? Tooltip(message: tooltip!, child: key) : key;
  }
}
