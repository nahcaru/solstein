/// Raw touch samples fed to the gesture engine. The UI layer converts
/// Flutter `PointerEvent`s into these; the engine never imports Flutter.
library;

enum SamplePhase { down, move, up, cancel }

class PointerSample {
  const PointerSample({
    required this.pointerId,
    required this.phase,
    required this.x,
    required this.y,
    required this.timestamp,
  });

  final int pointerId;
  final SamplePhase phase;
  final double x;
  final double y;

  /// Monotonic time since an arbitrary epoch (PointerEvent.timeStamp).
  final Duration timestamp;

  @override
  String toString() =>
      'PointerSample(#$pointerId $phase ($x, $y) @${timestamp.inMilliseconds}ms)';
}
