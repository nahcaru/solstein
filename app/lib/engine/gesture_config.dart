/// Tunable gesture-engine parameters (defaults per docs/gesture-mapping.md).
/// Settings injects overrides; the engine itself stays pure.
library;

class GestureConfig {
  const GestureConfig({
    this.tapTimeout = const Duration(milliseconds: 250),
    this.touchSlopPx = 8.0,
    this.swipeTriggerPx = 48.0,
    this.longPressTimeout = const Duration(milliseconds: 300),
    this.accelExponent = 1.0,
    this.pointerGain = 1.0,
    this.scrollPxPerTick = 16.0,
    this.scrollGain = 1.0,
    this.naturalScroll = true,
  });

  /// Finger must lift within this to count as a tap.
  final Duration tapTimeout;

  /// Movement below this is jitter, not intent.
  final double touchSlopPx;

  /// Dominant-axis travel at which a 3-finger swipe reaches progress 1.0.
  final double swipeTriggerPx;

  /// Hold longer than this before moving to start a drag.
  final Duration longPressTimeout;

  /// Pointer response curve: out = |d|^exponent scaled by [pointerGain].
  /// 1.0 (default) is linear — distance-proportional, so the host's own
  /// acceleration is the only curve applied and content tracks the finger
  /// like a real mouse/trackpad. >1.0 adds phone-side acceleration on top.
  final double accelExponent;

  /// Linear pointer speed multiplier (Settings: pointer speed).
  final double pointerGain;

  /// Pixels of two-finger travel per scroll tick.
  final double scrollPxPerTick;

  /// Linear scroll speed multiplier (Settings: scroll speed).
  final double scrollGain;

  /// Content follows fingers (trackpad-style) when true.
  final bool naturalScroll;

  GestureConfig copyWith({
    Duration? tapTimeout,
    double? touchSlopPx,
    double? swipeTriggerPx,
    Duration? longPressTimeout,
    double? accelExponent,
    double? pointerGain,
    double? scrollPxPerTick,
    double? scrollGain,
    bool? naturalScroll,
  }) =>
      GestureConfig(
        tapTimeout: tapTimeout ?? this.tapTimeout,
        touchSlopPx: touchSlopPx ?? this.touchSlopPx,
        swipeTriggerPx: swipeTriggerPx ?? this.swipeTriggerPx,
        longPressTimeout: longPressTimeout ?? this.longPressTimeout,
        accelExponent: accelExponent ?? this.accelExponent,
        pointerGain: pointerGain ?? this.pointerGain,
        scrollPxPerTick: scrollPxPerTick ?? this.scrollPxPerTick,
        scrollGain: scrollGain ?? this.scrollGain,
        naturalScroll: naturalScroll ?? this.naturalScroll,
      );
}
