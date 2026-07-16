import 'package:flutter/material.dart';

import '../core/input_event.dart';
import '../core/input_sink.dart';
import '../hid/keymap.dart';
import '../hid/shortcut_tables.dart';

/// Keyboard input: a text field that forwards keystrokes (resolved through
/// the host's keyboard layout) plus modifier / navigation / media rows.
/// Modifiers are one-shot (sticky-keys style): toggle ⌘, tap a key, modifier
/// releases. The modifier lineup and labels follow the target OS.
class KeyboardScreen extends StatefulWidget {
  const KeyboardScreen({
    super.key,
    required this.sink,
    required this.targetOs,
    required this.hostLayout,
  });

  final InputSink sink;
  final TargetOs targetOs;
  final HostLayout hostLayout;

  @override
  State<KeyboardScreen> createState() => _KeyboardScreenState();
}

class _ModifierSpec {
  const _ModifierSpec(this.label, this.bit);

  final String label;
  final int bit;
}

/// Modifier lineup per target OS: native order and naming.
const Map<TargetOs, List<_ModifierSpec>> _modifierRows = {
  TargetOs.macos: [
    _ModifierSpec('⌃', Mod.lCtrl),
    _ModifierSpec('⌥', Mod.lAlt),
    _ModifierSpec('⌘', Mod.lGui),
    _ModifierSpec('⇧', Mod.lShift),
  ],
  TargetOs.windows: [
    _ModifierSpec('Ctrl', Mod.lCtrl),
    _ModifierSpec('⊞ Win', Mod.lGui),
    _ModifierSpec('Alt', Mod.lAlt),
    _ModifierSpec('Shift', Mod.lShift),
  ],
  TargetOs.linux: [
    _ModifierSpec('Ctrl', Mod.lCtrl),
    _ModifierSpec('Super', Mod.lGui),
    _ModifierSpec('Alt', Mod.lAlt),
    _ModifierSpec('Shift', Mod.lShift),
  ],
};

class _KeyboardScreenState extends State<KeyboardScreen> {
  final _controller = TextEditingController();
  int _heldModifiers = 0;
  String _lastText = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _sendStroke(int usage, int modifiers) {
    final mods = modifiers | _heldModifiers;
    widget.sink.send(KeyInput(usage, mods, down: true));
    widget.sink.send(KeyInput(usage, mods, down: false));
    if (_heldModifiers != 0) setState(() => _heldModifiers = 0);
  }

  void _toggleModifier(int bit) {
    setState(() => _heldModifiers ^= bit);
  }

  /// Diffs the text field against its previous value: removals become
  /// backspaces, additions become keystrokes.
  ///
  /// Invariant: the field only ever holds what the host actually received.
  /// A character the host layout cannot produce is refused rather than
  /// silently dropped — otherwise the buffer this diff reads would describe
  /// text the host never got, and the next backspace would delete the wrong
  /// character on the host.
  void _onTextChanged(String text) {
    var common = 0;
    while (common < _lastText.length &&
        common < text.length &&
        _lastText.codeUnitAt(common) == text.codeUnitAt(common)) {
      common++;
    }
    for (var i = 0; i < _lastText.length - common; i++) {
      _sendStroke(Usage.backspace, Mod.none);
    }

    final accepted = StringBuffer(text.substring(0, common));
    final refused = <String>[];
    for (final char in text.substring(common).characters) {
      final stroke = widget.hostLayout.strokeFor(char);
      if (stroke == null) {
        refused.add(char);
        continue;
      }
      _sendStroke(stroke.usage, stroke.modifiers);
      accepted.write(char);
    }

    var settled = accepted.toString();
    // Keep the buffer from growing without bound.
    if (settled.length > 200) settled = '';

    _lastText = settled;
    if (settled != text) {
      // Programmatic edits do not re-enter onChanged.
      _controller.value = TextEditingValue(
        text: settled,
        selection: TextSelection.collapsed(offset: settled.length),
      );
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
        _keyRow([
          for (final spec in modifiers)
            _Key(
              label: spec.label,
              active: _heldModifiers & spec.bit != 0,
              onTap: () => _toggleModifier(spec.bit),
            ),
        ]),
        const SizedBox(height: 8),
        _keyRow([
          _Key(label: 'esc', onTap: () => _sendStroke(Usage.escape, Mod.none)),
          _Key(label: 'tab', onTap: () => _sendStroke(Usage.tab, Mod.none)),
          _Key(label: '⌫', onTap: () => _sendStroke(Usage.backspace, Mod.none)),
          _Key(label: '⏎', onTap: () => _sendStroke(Usage.enter, Mod.none)),
        ]),
        const SizedBox(height: 8),
        _keyRow([
          _Key(label: '←', onTap: () => _sendStroke(Usage.arrowLeft, Mod.none)),
          _Key(label: '↑', onTap: () => _sendStroke(Usage.arrowUp, Mod.none)),
          _Key(label: '↓', onTap: () => _sendStroke(Usage.arrowDown, Mod.none)),
          _Key(label: '→', onTap: () => _sendStroke(Usage.arrowRight, Mod.none)),
        ]),
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
/// Modifiers pass [active] to render latched (filled) state.
class _Key extends StatelessWidget {
  const _Key({this.label, this.icon, required this.onTap, this.active = false})
      : assert(label != null || icon != null);

  final String? label;
  final IconData? icon;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 44,
      child: Material(
        color: active ? scheme.primaryContainer : scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Center(
            child: icon != null
                ? Icon(icon, size: 20)
                : Text(
                    label!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: label!.length > 2 ? 14 : 18,
                      fontWeight:
                          active ? FontWeight.w600 : FontWeight.w400,
                      color: active
                          ? scheme.onPrimaryContainer
                          : scheme.onSurface,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
