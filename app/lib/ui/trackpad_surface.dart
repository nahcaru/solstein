import 'package:flutter/material.dart';
import 'package:vibration/vibration.dart';

import '../core/input_event.dart';
import '../core/input_sink.dart';
import '../engine/gesture_config.dart';
import '../engine/gesture_engine.dart';
import '../engine/pointer_sample.dart';

/// A vibration to fire: how long, and at what intensity (1-255) if the
/// device supports amplitude control. Tune these to taste against a real
/// Magic Trackpad — this is the only place the feel lives.
class ClickHaptic {
  const ClickHaptic(this.duration, this.amplitude);

  final int duration;
  final int amplitude;

  @override
  bool operator ==(Object other) =>
      other is ClickHaptic &&
      other.duration == duration &&
      other.amplitude == amplitude;

  @override
  int get hashCode => Object.hash(duration, amplitude);

  @override
  String toString() => 'ClickHaptic(${duration}ms @ $amplitude)';
}

const _leftPress = ClickHaptic(12, 200);
const _leftRelease = ClickHaptic(8, 90);
const _rightMiddlePress = ClickHaptic(15, 220);
const _rightMiddleRelease = ClickHaptic(8, 90);

/// The haptic to fire for a button transition. Pure — exposed for testing.
ClickHaptic hapticForClick(Button button, {required bool down}) {
  final isLeft = button == Button.left;
  if (down) return isLeft ? _leftPress : _rightMiddlePress;
  return isLeft ? _leftRelease : _rightMiddleRelease;
}

/// Fires [haptic] via the OS vibrator directly — unlike
/// [HapticFeedback](https://api.flutter.dev/flutter/services/HapticFeedback-class.html),
/// this does not depend on the "touch feedback" system toggle. Falls back to
/// duration-only on devices without amplitude control.
Future<void> fireHaptic(ClickHaptic haptic, {required bool amplitudeSupported}) {
  return amplitudeSupported
      ? Vibration.vibrate(duration: haptic.duration, amplitude: haptic.amplitude)
      : Vibration.vibrate(duration: haptic.duration);
}

/// The trackpad: a full-screen [Listener] feeding raw pointer events into
/// the gesture engine. Never a GestureDetector — its recognizers add
/// latency and drop the raw stream (docs/architecture.md).
class TrackpadSurface extends StatefulWidget {
  const TrackpadSurface({
    super.key,
    required this.sink,
    required this.config,
    required this.hapticsEnabled,
  });

  final InputSink sink;
  final GestureConfig config;
  final bool hapticsEnabled;

  @override
  State<TrackpadSurface> createState() => _TrackpadSurfaceState();
}

class _TrackpadSurfaceState extends State<TrackpadSurface> {
  late GestureEngine _engine = GestureEngine(config: widget.config);

  /// Checked once per surface, not per click — it's a platform round trip.
  late final Future<bool> _amplitudeSupported = Vibration.hasAmplitudeControl();

  @override
  void didUpdateWidget(TrackpadSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config != widget.config) {
      // Abort any in-flight gesture cleanly before swapping tunables.
      for (final event in _engine.reset()) {
        widget.sink.send(event);
      }
      _engine = GestureEngine(config: widget.config);
    }
  }

  @override
  void dispose() {
    for (final event in _engine.reset()) {
      widget.sink.send(event);
    }
    super.dispose();
  }

  void _handle(PointerEvent event, SamplePhase phase) {
    final sample = PointerSample(
      pointerId: event.pointer,
      phase: phase,
      x: event.localPosition.dx,
      y: event.localPosition.dy,
      timestamp: event.timeStamp,
    );
    for (final inputEvent in _engine.handleSample(sample)) {
      widget.sink.send(inputEvent);
      if (widget.hapticsEnabled && inputEvent is ButtonEvent) {
        final haptic = hapticForClick(inputEvent.button, down: inputEvent.down);
        _amplitudeSupported.then(
          (supported) => fireHaptic(haptic, amplitudeSupported: supported),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) => _handle(e, SamplePhase.down),
      onPointerMove: (e) => _handle(e, SamplePhase.move),
      onPointerUp: (e) => _handle(e, SamplePhase.up),
      onPointerCancel: (e) => _handle(e, SamplePhase.cancel),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.center,
        child: Icon(
          Icons.touch_app_outlined,
          size: 48,
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
    );
  }
}
