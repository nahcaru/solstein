/// Tunables for [MotionEngine]. Unlike GestureConfig this has value
/// equality: the presenter surface rebuilds on every settings notification,
/// and a config swap resets the engine — which would discard the learned
/// gyro bias if a freshly built but identical config read as "changed".
///
/// The smoothing and ballistics defaults are first estimates, meant to be
/// tuned on a real phone with the motion diagnostics screen.
library;

class MotionConfig {
  const MotionConfig({
    this.pointerGain = 1.0,
    this.countsPerRadian = 2400.0,
    this.ballisticsExponent = 1.4,
    this.ballisticsRefRadPerSec = 1.0,
    this.deadzoneRadPerSec = 0.01,
    this.smoothingMinCutoffHz = 1.5,
    this.smoothingBeta = 0.08,
    this.gravityTau = 0.25,
    this.biasTau = 4.0,
    this.stillnessRadPerSec = 0.05,
  }) : assert(ballisticsRefRadPerSec > 0);

  /// User speed multiplier (Settings slider).
  final double pointerGain;

  /// HID counts per radian of rotation at gain 1.0 and the reference speed
  /// (≈42 counts/degree). A first estimate — tune on hardware.
  final double countsPerRadian;

  /// Ballistics curve exponent p: output rate ∝ |ω|^p, normalized so that
  /// speed [ballisticsRefRadPerSec] keeps a gain of exactly 1. p = 1 is
  /// linear; p > 1 makes slow motion finer and fast motion reach further.
  final double ballisticsExponent;

  /// Angular speed at which the ballistics curve has unit gain (rad/s).
  final double ballisticsRefRadPerSec;

  /// Angular rates below this are treated as no motion (kills creep).
  final double deadzoneRadPerSec;

  /// One Euro cutoff at zero speed (Hz): the tremor filter's strength.
  final double smoothingMinCutoffHz;

  /// One Euro speed coefficient: how quickly the filter opens up for fast
  /// motion.
  final double smoothingBeta;

  /// Accelerometer low-pass time constant (seconds).
  final double gravityTau;

  /// Gyro-bias learning time constant while the device is still (seconds).
  final double biasTau;

  /// Corrected angular rate below which the device counts as still.
  final double stillnessRadPerSec;

  MotionConfig copyWith({
    double? pointerGain,
    double? countsPerRadian,
    double? ballisticsExponent,
    double? ballisticsRefRadPerSec,
    double? deadzoneRadPerSec,
    double? smoothingMinCutoffHz,
    double? smoothingBeta,
    double? gravityTau,
    double? biasTau,
    double? stillnessRadPerSec,
  }) =>
      MotionConfig(
        pointerGain: pointerGain ?? this.pointerGain,
        countsPerRadian: countsPerRadian ?? this.countsPerRadian,
        ballisticsExponent: ballisticsExponent ?? this.ballisticsExponent,
        ballisticsRefRadPerSec:
            ballisticsRefRadPerSec ?? this.ballisticsRefRadPerSec,
        deadzoneRadPerSec: deadzoneRadPerSec ?? this.deadzoneRadPerSec,
        smoothingMinCutoffHz: smoothingMinCutoffHz ?? this.smoothingMinCutoffHz,
        smoothingBeta: smoothingBeta ?? this.smoothingBeta,
        gravityTau: gravityTau ?? this.gravityTau,
        biasTau: biasTau ?? this.biasTau,
        stillnessRadPerSec: stillnessRadPerSec ?? this.stillnessRadPerSec,
      );

  @override
  bool operator ==(Object other) =>
      other is MotionConfig &&
      other.pointerGain == pointerGain &&
      other.countsPerRadian == countsPerRadian &&
      other.ballisticsExponent == ballisticsExponent &&
      other.ballisticsRefRadPerSec == ballisticsRefRadPerSec &&
      other.deadzoneRadPerSec == deadzoneRadPerSec &&
      other.smoothingMinCutoffHz == smoothingMinCutoffHz &&
      other.smoothingBeta == smoothingBeta &&
      other.gravityTau == gravityTau &&
      other.biasTau == biasTau &&
      other.stillnessRadPerSec == stillnessRadPerSec;

  @override
  int get hashCode => Object.hash(
        pointerGain,
        countsPerRadian,
        ballisticsExponent,
        ballisticsRefRadPerSec,
        deadzoneRadPerSec,
        smoothingMinCutoffHz,
        smoothingBeta,
        gravityTau,
        biasTau,
        stillnessRadPerSec,
      );
}
