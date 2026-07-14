/// Tunable gesture-engine parameters (defaults per docs/gesture-mapping.md).
/// Settings injects overrides; the engine itself stays pure.
library;

class GestureConfig {
  const GestureConfig({
    this.tapTimeout = const Duration(milliseconds: 250),
    this.touchSlopPx = 8.0,
    this.swipeTriggerPx = 48.0,
    this.longPressTimeout = const Duration(milliseconds: 300),
    this.tapDragTimeout = const Duration(milliseconds: 300),
    this.pageFlickMinVelocity = 0.6,
    this.spreadTriggerRatio = 1.4,
    this.spreadBeginRatio = 0.08,
    this.accelExponent = 1.0,
    this.pointerGain = 1.0,
    this.scrollPxPerTick = 32.0,
    this.scrollGain = 1.0,
    this.naturalScroll = true,
    this.hostInvertsScroll = true,
  });

  /// Baseline pointer counts per touch pixel at [pointerGain] 1.0.
  static const double basePointerScale = 2.0;

  /// Finger must lift within this to count as a tap.
  final Duration tapTimeout;

  /// Movement below this is jitter, not intent.
  final double touchSlopPx;

  /// Dominant-axis travel at which a 3-finger swipe reaches progress 1.0.
  final double swipeTriggerPx;

  /// Hold longer than this before moving to start a drag.
  final Duration longPressTimeout;

  /// A touch beginning within this window after a tap couples into a drag
  /// as soon as it moves (tap-and-drag, no long-press needed).
  final Duration tapDragTimeout;

  /// Two-finger horizontal motion at or above this speed (px/ms measured
  /// at slop-crossing) is a page-swipe flick; below it, a scroll.
  final double pageFlickMinVelocity;

  /// Four-finger spread commits (progress 1.0) when the mean
  /// finger-to-centroid distance grows by this ratio.
  final double spreadTriggerRatio;

  /// Spread growth at which the gesture begins (progress > 0).
  final double spreadBeginRatio;

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

  /// Whether the host OS flips incoming wheel/pan itself. macOS does with
  /// its default "natural scrolling" preference; Windows/Linux do not.
  /// Derived from the target-OS setting, not user-facing.
  final bool hostInvertsScroll;

  GestureConfig copyWith({
    Duration? tapTimeout,
    double? touchSlopPx,
    double? swipeTriggerPx,
    Duration? longPressTimeout,
    Duration? tapDragTimeout,
    double? pageFlickMinVelocity,
    double? spreadTriggerRatio,
    double? spreadBeginRatio,
    double? accelExponent,
    double? pointerGain,
    double? scrollPxPerTick,
    double? scrollGain,
    bool? naturalScroll,
    bool? hostInvertsScroll,
  }) =>
      GestureConfig(
        tapTimeout: tapTimeout ?? this.tapTimeout,
        touchSlopPx: touchSlopPx ?? this.touchSlopPx,
        swipeTriggerPx: swipeTriggerPx ?? this.swipeTriggerPx,
        longPressTimeout: longPressTimeout ?? this.longPressTimeout,
        tapDragTimeout: tapDragTimeout ?? this.tapDragTimeout,
        pageFlickMinVelocity: pageFlickMinVelocity ?? this.pageFlickMinVelocity,
        spreadTriggerRatio: spreadTriggerRatio ?? this.spreadTriggerRatio,
        spreadBeginRatio: spreadBeginRatio ?? this.spreadBeginRatio,
        accelExponent: accelExponent ?? this.accelExponent,
        pointerGain: pointerGain ?? this.pointerGain,
        scrollPxPerTick: scrollPxPerTick ?? this.scrollPxPerTick,
        scrollGain: scrollGain ?? this.scrollGain,
        naturalScroll: naturalScroll ?? this.naturalScroll,
        hostInvertsScroll: hostInvertsScroll ?? this.hostInvertsScroll,
      );
}
