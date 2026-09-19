/// One Euro filter (Casiez et al., CHI 2012): an adaptive low-pass for noisy
/// pointing signals. At low speed the cutoff is low, which removes jitter such
/// as hand tremor (4–12 Hz); as the signal speeds up the cutoff rises, so a
/// deliberate fast motion is followed with little lag.
///
/// Pure Dart. The time step comes from the caller (sample timestamps), so the
/// same input always yields the same output.
library;

import 'dart:math' as math;

class OneEuroFilter {
  OneEuroFilter({
    required this.minCutoffHz,
    required this.beta,
    this.derivativeCutoffHz = 1.0,
  });

  /// Cutoff at zero speed, in Hz. Lower = smoother and laggier when slow.
  final double minCutoffHz;

  /// How fast the cutoff rises with speed. Higher = less lag on fast motion.
  final double beta;

  /// Cutoff of the low-pass applied to the speed estimate.
  final double derivativeCutoffHz;

  double? _x;
  double _dx = 0;

  /// Filters [x], sampled [dt] seconds after the previous call (dt > 0).
  /// The first value after construction or [reset] passes through unchanged.
  double filter(double x, double dt) {
    final prev = _x;
    if (prev == null) {
      _x = x;
      _dx = 0;
      return x;
    }
    final rawSpeed = (x - prev) / dt;
    _dx += _alpha(derivativeCutoffHz, dt) * (rawSpeed - _dx);
    final cutoff = minCutoffHz + beta * _dx.abs();
    final filtered = prev + _alpha(cutoff, dt) * (x - prev);
    _x = filtered;
    return filtered;
  }

  void reset() {
    _x = null;
    _dx = 0;
  }

  static double _alpha(double cutoffHz, double dt) {
    final tau = 1 / (2 * math.pi * cutoffHz);
    return 1 / (1 + tau / dt);
  }
}
