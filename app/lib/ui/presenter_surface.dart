import 'dart:async';

import 'package:flutter/material.dart';

import '../core/input_event.dart';
import '../core/input_sink.dart';
import '../hid/keymap_us.dart';
import '../motion/motion_config.dart';
import '../motion/motion_engine.dart';
import '../motion/motion_sample.dart';
import '../motion/motion_source.dart';

/// Presenter / laser-pointer mode: phone motion drives the host cursor.
///
/// Glide the phone to move the pointer (relative); hold Spotlight to point
/// directly (absolute). Prev/Next step slides and Click clicks. Never a
/// GestureDetector — like the trackpad, presses use raw pointer events.
class PresenterSurface extends StatefulWidget {
  const PresenterSurface({
    super.key,
    required this.sink,
    required this.source,
    required this.config,
    required this.absoluteSpotlight,
  });

  final InputSink sink;
  final MotionSource source;
  final MotionConfig config;

  /// Whether a held spotlight maps absolutely. False degrades it to slow
  /// relative "precision" pointing.
  final bool absoluteSpotlight;

  @override
  State<PresenterSurface> createState() => _PresenterSurfaceState();
}

class _PresenterSurfaceState extends State<PresenterSurface>
    with WidgetsBindingObserver {
  late MotionEngine _engine = _newEngine();
  StreamSubscription<MotionSample>? _subscription;
  bool _spotlightHeld = false;
  String? _sensorError;

  MotionEngine _newEngine() => MotionEngine(
        config: widget.config,
        absoluteSpotlight: widget.absoluteSpotlight,
      );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startSensors();
  }

  @override
  void didUpdateWidget(PresenterSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    // MotionConfig has value equality, so a rebuild with an identical config
    // does not land here and does not discard the learned gyro bias.
    if (oldWidget.config != widget.config ||
        oldWidget.absoluteSpotlight != widget.absoluteSpotlight) {
      _emit(_engine.reset()); // abort in-flight state before swapping
      _engine = _newEngine();
      _spotlightHeld = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopSensors();
    _emit(_engine.reset());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _startSensors();
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        // A backgrounded app must not keep streaming gyro (battery) or leave
        // a spotlight/click held (stuck input). AppModel.releaseAll() covers
        // the transport; this covers the engine.
        _emit(_engine.reset());
        _stopSensors();
        if (mounted && _spotlightHeld) setState(() => _spotlightHeld = false);
    }
  }

  void _startSensors() {
    if (_subscription != null) return;
    _subscription = widget.source.samples.listen(
      (s) => _emit(_engine.handleSample(s)),
      onError: (Object e) {
        if (mounted) setState(() => _sensorError = 'Motion sensors unavailable');
      },
    );
    widget.source.start().catchError((Object _) {
      if (mounted) setState(() => _sensorError = 'Motion sensors unavailable');
    });
  }

  void _stopSensors() {
    _subscription?.cancel();
    _subscription = null;
    widget.source.stop();
  }

  void _emit(List<InputEvent> events) {
    for (final event in events) {
      widget.sink.send(event);
    }
  }

  void _setSpotlight(bool held) {
    if (_spotlightHeld == held) return;
    setState(() => _spotlightHeld = held);
    _emit(held ? _engine.beginSpotlight() : _engine.endSpotlight());
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
    final precision = !widget.absoluteSpotlight;
    return Column(
      children: [
        Expanded(
          child: _PadButton(
            key: const ValueKey('spotlight'),
            icon: Icons.adjust,
            label: precision ? 'Precision' : 'Spotlight',
            hint: _sensorError ??
                (_spotlightHeld
                    ? 'Pointing…'
                    : 'Hold to point · sweep the phone to glide'),
            color: scheme.surfaceContainerLow,
            activeColor: scheme.primaryContainer,
            onDown: () => _setSpotlight(true),
            onUp: () => _setSpotlight(false),
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
                  onDown: () => _emit(_engine.click(down: true)),
                  onUp: () => _emit(_engine.click(down: false)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
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
