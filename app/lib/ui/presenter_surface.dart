import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vibration/vibration.dart';

import '../core/input_event.dart';
import '../core/input_sink.dart';
import '../hid/keymap.dart';
import '../motion/motion_sample.dart';
import '../motion/motion_session.dart';
import '../presenter/presenter_host.dart';
import 'trackpad_surface.dart' show ClickHaptic, fireHaptic, hapticForClick;

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
    required this.host,
    required this.clutch,
    required this.volumeKeys,
    this.laser,
    this.active = true,
    this.hapticsEnabled = true,
  });

  final InputSink sink;

  /// The shared engine and sensor feed (see [MotionSession]).
  final MotionSession session;

  /// Keep-awake and volume-key access.
  final PresenterHost host;

  /// Whether volume up/down act as Prev/Next.
  final bool volumeKeys;

  /// False while another screen (Settings, diagnostics) is on top. The
  /// presenter stays mounted underneath, so without this it would keep moving
  /// the host cursor, hold the volume keys and keep the sensors running while
  /// the user scrolls a settings list.
  final bool active;

  /// Vibrate on button presses, like the trackpad (Settings › Haptics on
  /// click). Uses the same direct vibrator path, which — unlike Flutter's
  /// HapticFeedback — does not depend on the system touch-feedback toggle.
  final bool hapticsEnabled;

  /// Keystroke that toggles the slideshow app's built-in laser pointer;
  /// null hides the Laser button.
  final KeyStroke? laser;

  /// True: the cursor moves only while the pad is held. False ("always on"):
  /// it moves unless the pad is held, which freezes it.
  final bool clutch;

  @override
  State<PresenterSurface> createState() => _PresenterSurfaceState();
}

class _PresenterSurfaceState extends State<PresenterSurface>
    with WidgetsBindingObserver {
  StreamSubscription<Object>? _errors;
  StreamSubscription<MotionSample>? _recovered;
  StreamSubscription<VolumeKeyEvent>? _volumeKeySub;
  bool _attached = false;
  bool _capturingVolume = false;
  bool _padHeld = false;
  String? _sensorError;
  late final Future<bool> _amplitudeSupported = Vibration.hasAmplitudeControl();

  MotionSession get _session => widget.session;

  /// A press-strength tap for buttons; the softer release-strength one when
  /// the clutch closes.
  static final _tap = hapticForClick(Button.left, down: true);
  static final _soft = hapticForClick(Button.left, down: false);

  void _buzz(ClickHaptic haptic) {
    if (!widget.hapticsEnabled) return;
    _amplitudeSupported
        .then((supported) =>
            fireHaptic(haptic, amplitudeSupported: supported))
        .catchError((_) {});
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _errors = _session.errors.listen((_) {
      if (mounted) setState(() => _sensorError = 'Motion sensors unavailable');
    });
    // Samples arriving again mean a transient error is over.
    _recovered = _session.samples.listen((_) {
      if (_sensorError != null && mounted) setState(() => _sensorError = null);
    });
    if (widget.active) _attach();
  }

  @override
  void didUpdateWidget(PresenterSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) {
      if (widget.active) {
        _attach();
      } else {
        _session.release();
        _detach();
        _padHeld = false;
      }
    }
    if (oldWidget.clutch != widget.clutch && _attached) {
      // The pad changes meaning; whatever the finger is doing, start over.
      _padHeld = false;
      _syncClutch();
    }
    if (oldWidget.volumeKeys != widget.volumeKeys && _attached) {
      _syncVolumeKeys();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _errors?.cancel();
    _recovered?.cancel();
    _session.release(); // nothing may stay held after this screen is gone
    _detach();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        if (widget.active) _attach();
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
    _syncVolumeKeys();
  }

  void _detach() {
    if (!_attached) return;
    _attached = false;
    _session.detach();
    _releaseVolumeKeys();
  }

  // The capture is dropped as soon as this element is deactivated, not
  // left to dispose: when the mode changes, the incoming surface's initState
  // runs before this one's dispose, so a release in dispose would land after
  // (and undo) the new surface's capture.
  @override
  void deactivate() {
    _releaseVolumeKeys();
    super.deactivate();
  }

  // Reparenting under a GlobalKey (rotation) deactivates then reactivates.
  @override
  void activate() {
    super.activate();
    if (_attached) _syncVolumeKeys();
  }

  void _releaseVolumeKeys() {
    _volumeKeySub?.cancel();
    _volumeKeySub = null;
    if (!_capturingVolume) return;
    _capturingVolume = false;
    widget.host.setVolumeKeysCaptured(false);
  }

  /// Volume keys are captured only while presenting and only if enabled, so
  /// the phone's volume works normally everywhere else.
  void _syncVolumeKeys() {
    _volumeKeySub?.cancel();
    _volumeKeySub = null;
    _capturingVolume = widget.volumeKeys;
    widget.host.setVolumeKeysCaptured(widget.volumeKeys);
    if (!widget.volumeKeys) return;
    _volumeKeySub = widget.host.volumeKeys.listen((event) {
      if (!event.pressed) return;
      _buzz(_tap);
      _tapKey(event.key == VolumeKey.up ? Usage.pageUp : Usage.pageDown);
    });
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
    if (held) _buzz(_soft);
    setState(() => _padHeld = held);
    _syncClutch();
  }

  /// Slide keys are plain Page Up / Page Down on every OS and every deck app
  /// (Keynote, PowerPoint, Google Slides, PDF viewers), so they need no
  /// per-OS shortcut table.
  void _tapKey(int usage, {int modifiers = Mod.none}) {
    widget.sink.send(KeyInput(usage, modifiers, down: true));
    widget.sink.send(KeyInput(usage, modifiers, down: false));
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
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    // Landscape: the deck runs down the right edge, beside the pad.
    final axis = landscape ? Axis.horizontal : Axis.vertical;
    final deckAxis = landscape ? Axis.vertical : Axis.horizontal;
    Widget gap(Axis along) => along == Axis.horizontal
        ? const SizedBox(width: 12)
        : const SizedBox(height: 12);
    final deck = <Widget>[
      _PadButton(
        key: const ValueKey('prev'),
        icon: Icons.chevron_left,
        label: 'Prev',
        color: scheme.surfaceContainerHigh,
        activeColor: scheme.primaryContainer,
        onDown: () {
          _buzz(_tap);
          _tapKey(Usage.pageUp);
        },
      ),
      _PadButton(
        key: const ValueKey('click'),
        icon: Icons.mouse,
        label: 'Click',
        color: scheme.surfaceContainerHigh,
        activeColor: scheme.primaryContainer,
        onDown: () {
          _buzz(_tap);
          _session.emitAll(_session.engine.click(down: true));
        },
        onUp: () {
          _buzz(_soft);
          _session.emitAll(_session.engine.click(down: false));
        },
      ),
      if (widget.laser case final laser?)
        _PadButton(
          key: const ValueKey('laser'),
          icon: Icons.gps_fixed,
          label: 'Laser',
          color: scheme.surfaceContainerHigh,
          activeColor: scheme.primaryContainer,
          onDown: () {
            _buzz(_tap);
            _tapKey(laser.usage, modifiers: laser.modifiers);
          },
        ),
      _PadButton(
        key: const ValueKey('next'),
        icon: Icons.chevron_right,
        label: 'Next',
        color: scheme.surfaceContainerHigh,
        activeColor: scheme.primaryContainer,
        onDown: () {
          _buzz(_tap);
          _tapKey(Usage.pageDown);
        },
      ),
    ];
    return Flex(
      direction: axis,
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
        gap(axis),
        SizedBox(
          width: landscape ? 120 : null,
          height: landscape ? null : 96,
          child: Flex(
            direction: deckAxis,
            children: [
              for (final (i, button) in deck.indexed) ...[
                if (i > 0) gap(deckAxis),
                Expanded(
                  // Next is the button pressed most, often blind.
                  flex: i == deck.length - 1 ? 2 : 1,
                  child: button,
                ),
              ],
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
  /// Fingers currently on the pad. The pad is pressed from the first finger
  /// down to the last finger up, so a second finger lifting early does not
  /// release it.
  final _pointers = <int>{};

  bool get _pressed => _pointers.isNotEmpty;

  void _down(int pointer) {
    // Defensive: an orientation change can dispose this pad out from under
    // an in-progress touch (control_screen.dart keeps identity across
    // rotation with a GlobalKey now, but this guards any other path that
    // tears the pad down mid-press). The disposed pad's own dispose() has
    // already released whatever it held, so there's nothing left to do.
    if (!mounted) return;
    final first = _pointers.isEmpty;
    _pointers.add(pointer);
    if (!first) return;
    setState(() {});
    widget.onDown();
  }

  void _up(int pointer) {
    if (!mounted) return;
    if (!_pointers.remove(pointer) || _pointers.isNotEmpty) return;
    setState(() {});
    widget.onUp?.call();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) => _down(e.pointer),
      onPointerUp: (e) => _up(e.pointer),
      onPointerCancel: (e) => _up(e.pointer),
      child: Container(
        decoration: BoxDecoration(
          color: _pressed ? widget.activeColor : widget.color,
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.center,
        // Landscape gives the deck a fixed width but only a share of the
        // screen height, sometimes less than the icon+label need. Scale the
        // content down to fit rather than overflow; it renders at natural
        // size whenever there's room (BoxFit.scaleDown never enlarges).
        child: FittedBox(
          fit: BoxFit.scaleDown,
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
      ),
    );
  }
}
