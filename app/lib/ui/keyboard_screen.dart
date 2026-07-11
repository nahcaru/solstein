import 'package:flutter/material.dart';

import '../core/input_event.dart';
import '../core/input_sink.dart';
import '../hid/keymap_us.dart';

/// Keyboard input: a text field that forwards keystrokes (US layout) plus a
/// modifier/navigation row. Modifiers are one-shot (sticky-keys style):
/// toggle ⌘, tap a key, modifier releases.
class KeyboardScreen extends StatefulWidget {
  const KeyboardScreen({super.key, required this.sink});

  final InputSink sink;

  @override
  State<KeyboardScreen> createState() => _KeyboardScreenState();
}

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
    for (final char in text.substring(common).characters) {
      final stroke = keyStrokeForChar(char);
      if (stroke != null) _sendStroke(stroke.usage, stroke.modifiers);
    }
    _lastText = text;
    // Keep the buffer from growing without bound.
    if (text.length > 200) {
      _controller.clear();
      _lastText = '';
    }
  }

  @override
  Widget build(BuildContext context) {
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
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            _ModChip(
              label: '⌃',
              active: _heldModifiers & Mod.lCtrl != 0,
              onTap: () => _toggleModifier(Mod.lCtrl),
            ),
            _ModChip(
              label: '⌥',
              active: _heldModifiers & Mod.lAlt != 0,
              onTap: () => _toggleModifier(Mod.lAlt),
            ),
            _ModChip(
              label: '⌘',
              active: _heldModifiers & Mod.lGui != 0,
              onTap: () => _toggleModifier(Mod.lGui),
            ),
            _ModChip(
              label: '⇧',
              active: _heldModifiers & Mod.lShift != 0,
              onTap: () => _toggleModifier(Mod.lShift),
            ),
            _KeyButton(
                label: 'esc', onTap: () => _sendStroke(Usage.escape, Mod.none)),
            _KeyButton(
                label: 'tab', onTap: () => _sendStroke(Usage.tab, Mod.none)),
            _KeyButton(
                label: '⌫',
                onTap: () => _sendStroke(Usage.backspace, Mod.none)),
            _KeyButton(
                label: '⏎', onTap: () => _sendStroke(Usage.enter, Mod.none)),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          alignment: WrapAlignment.center,
          children: [
            _KeyButton(
                label: '←',
                onTap: () => _sendStroke(Usage.arrowLeft, Mod.none)),
            _KeyButton(
                label: '↑', onTap: () => _sendStroke(Usage.arrowUp, Mod.none)),
            _KeyButton(
                label: '↓',
                onTap: () => _sendStroke(Usage.arrowDown, Mod.none)),
            _KeyButton(
                label: '→',
                onTap: () => _sendStroke(Usage.arrowRight, Mod.none)),
          ],
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

class _ModChip extends StatelessWidget {
  const _ModChip({required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label, style: const TextStyle(fontSize: 18)),
      selected: active,
      onSelected: (_) => onTap(),
      showCheckmark: false,
    );
  }
}

class _KeyButton extends StatelessWidget {
  const _KeyButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      child: Text(label, style: const TextStyle(fontSize: 16)),
    );
  }
}
