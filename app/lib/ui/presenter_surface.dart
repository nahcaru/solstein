import 'dart:async';

import 'package:flutter/material.dart';

import '../core/input_event.dart';
import '../core/input_sink.dart';
import '../hid/keymap_us.dart';
import '../motion/motion_session.dart';

/// Presenter / laser-pointer mode: phone motion drives the host cursor.
///
/// Like a presentation remote's button, the big pad is a clutch: the cursor
/// follows the phone only while it is held, so the shake of tapping Click or
/// Next never reaches the cursor, and an arm at its limit can let go and
/// re-grip. Prev/Next step slides and Click clicks. Never a GestureDetector —
/// like the trackpad, presses use raw pointer events.
class PresenterSurface extends StatefulWidget {
  const PresenterSurface({
    super.key,
    required this.sink,
    required this.session,
    required this.clutch,
  });

  final InputSink sink;

  /// The shared engine and sensor feed (see [MotionSession]).
  final MotionSession session;

  /// True: the cursor moves only while the pad is held. False ("always on"):
  /// it moves unless the pad is held, which freezes it.
  final bool clutch;

  @override
  State<PresenterSurface> createState() => _PresenterSurfaceState();
}

class _PresenterSurfaceState extends State<PresenterSurface>
    with WidgetsBindingObserver {
  StreamSubscription<Object>? _errors;
  bool _attached = false;
  bool _padHeld = false;
  String? _sensorError;

  MotionSession get _session => widget.session;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _errors = _session.errors.listen((_) {
      if (mounted) setState(() => _sensorError = 'Motion sensors unavailable');
    });
    _attach();
  }

  @override
  void didUpdateWidget(PresenterSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.clutch != widget.clutch) {
      // The pad changes meaning; whatever the finger is doing, start over.
      _padHeld = false;
      _syncClutch();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _errors?.cancel();
    _session.release(); // nothing may stay held after this screen is gone
    _detach();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _attach();
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        // A backgrounded app must not keep streaming gyro (battery) or leave
        // the clutch or a click held (stuck input). AppModel.releaseAll()
        // covers the transport; this covers the engine.
        _session.release();
        _detach();
        if (mounted && _padHeld) setState(() => _padHeld = false);
    }
  }

  void _attach() {
    if (_attached) return;
    _attached = true;
    _session.attach();
    _syncClutch();
  }

  void _detach() {
    if (!_attached) return;
    _attached = false;
    _session.detach();
  }

  /// Brings the engine's clutch in line with the pad and the setting.
  void _syncClutch() {
    final moving = widget.clutch ? _padHeld : !_padHeld;
    _session.emitAll(
      moving ? _session.engine.engage() : _session.engine.disengage(),
    );
  }

  void _setPad(bool held) {
    if (_padHeld == held) return;
    setState(() => _padHeld = held);
    _syncClutch();
  }

  /// Slide keys are plain Page Up / Page Down on every OS and every deck app
  /// (Keynote, PowerPoint, Google Slides, PDF viewers), so they need no
  /// per-OS shortcut table.
  void _tapKey(int usage) {
    widget.sink.send(KeyInput(usage, Mod.none, down: true));
    widget.sink.send(KeyInput(usage, Mod.none, down: false));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final String label;
    final String hint;
    if (widget.clutch) {
      label = _padHeld ? 'Moving' : 'Hold to move';
      hint = 'Hold, then sweep the phone';
    } else {
      label = _padHeld ? 'Frozen' : 'Moving';
      hint = 'Hold to freeze the pointer';
    }
    return Column(
      children: [
        Expanded(
          child: _PadButton(
            key: const ValueKey('clutch'),
            icon: _padHeld == widget.clutch ? Icons.open_with : Icons.adjust,
            label: label,
            hint: _sensorError ?? hint,
            color: scheme.surfaceContainerLow,
            activeColor: scheme.primaryContainer,
            onDown: () => _setPad(true),
            onUp: () => _setPad(false),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 96,
          child: Row(
            children: [
              Expanded(
                child: _PadButton(
                  key: const ValueKey('prev'),
                  icon: Icons.chevron_left,
                  label: 'Prev',
                  color: scheme.surfaceContainerHigh,
                  activeColor: scheme.primaryContainer,
                  onDown: () => _tapKey(Usage.pageUp),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _PadButton(
                  key: const ValueKey('click'),
                  icon: Icons.mouse,
                  label: 'Click',
                  color: scheme.surfaceContainerHigh,
                  activeColor: scheme.primaryContainer,
                  onDown: () =>
                      _session.emitAll(_session.engine.click(down: true)),
                  onUp: () =>
                      _session.emitAll(_session.engine.click(down: false)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2, // Next is the button pressed most, often blind
                child: _PadButton(
                  key: const ValueKey('next'),
                  icon: Icons.chevron_right,
                  label: 'Next',
                  color: scheme.surfaceContainerHigh,
                  activeColor: scheme.primaryContainer,
                  onDown: () => _tapKey(Usage.pageDown),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A press-and-hold pad on a raw [Listener]: [onDown] on touch-down, [onUp]
/// on release or cancel (a cancelled press must never leave input held).
class _PadButton extends StatefulWidget {
  const _PadButton({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.activeColor,
    required this.onDown,
    this.onUp,
    this.hint,
  });

  final IconData icon;
  final String label;
  final String? hint;
  final Color color;
  final Color activeColor;
  final VoidCallback onDown;
  final VoidCallback? onUp;

  @override
  State<_PadButton> createState() => _PadButtonState();
}

class _PadButtonState extends State<_PadButton> {
  bool _pressed = false;

  void _down() {
    setState(() => _pressed = true);
    widget.onDown();
  }

  void _up() {
    if (!_pressed) return;
    setState(() => _pressed = false);
    widget.onUp?.call();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => _down(),
      onPointerUp: (_) => _up(),
      onPointerCancel: (_) => _up(),
      child: Container(
        decoration: BoxDecoration(
          color: _pressed ? widget.activeColor : widget.color,
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(widget.icon, size: 36, color: scheme.onSurfaceVariant),
            const SizedBox(height: 4),
            Text(widget.label, style: Theme.of(context).textTheme.titleMedium),
            if (widget.hint != null) ...[
              const SizedBox(height: 4),
              Text(
                widget.hint!,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
