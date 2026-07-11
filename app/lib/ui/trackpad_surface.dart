import 'package:flutter/material.dart';

import '../core/input_sink.dart';
import '../engine/gesture_config.dart';
import '../engine/gesture_engine.dart';
import '../engine/pointer_sample.dart';

/// The trackpad: a full-screen [Listener] feeding raw pointer events into
/// the gesture engine. Never a GestureDetector — its recognizers add
/// latency and drop the raw stream (docs/architecture.md).
class TrackpadSurface extends StatefulWidget {
  const TrackpadSurface({super.key, required this.sink, required this.config});

  final InputSink sink;
  final GestureConfig config;

  @override
  State<TrackpadSurface> createState() => _TrackpadSurfaceState();
}

class _TrackpadSurfaceState extends State<TrackpadSurface> {
  late GestureEngine _engine = GestureEngine(config: widget.config);

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
