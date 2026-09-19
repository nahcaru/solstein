/// Tunables for [MotionEngine]. Unlike GestureConfig this has value
/// equality: the presenter surface rebuilds on every settings notification,
/// and a config swap resets the engine — which would discard the learned
/// gyro bias and the spotlight reference mid-sweep if a freshly built but
/// identical config read as "changed".
library;

class MotionConfig {
  const MotionConfig({
    this.pointerGain = 1.0,
    this.fieldOfView = 0.70,
    this.countsPerRadian = 2400.0,
    this.deadzoneRadPerSec = 0.01,
    this.gravityTau = 0.25,
    this.pitchTau = 0.8,
    this.biasTau = 4.0,
    this.stillnessRadPerSec = 0.05,
    this.aspect = 16 / 9,
  });

  /// User speed multiplier for relative gliding (Settings slider).
  final double pointerGain;

  /// Horizontal angle, in radians, that spans the full screen width while
  /// the spotlight is held (≈40° by default).
  final double fieldOfView;

  /// Relative mode: HID counts per radian of rotation at gain 1.0
  /// (≈42 counts/degree). A first estimate — tune on hardware.
  final double countsPerRadian;

  /// Angular rates below this are treated as no motion (kills creep).
  final double deadzoneRadPerSec;

  /// Accelerometer low-pass time constant (seconds).
  final double gravityTau;

  /// Complementary-filter time constant pulling the integrated pitch toward
  /// the gravity-derived pitch (seconds).
  final double pitchTau;

  /// Gyro-bias learning time constant while the device is still (seconds).
  final double biasTau;

  /// Corrected angular rate below which the device counts as still.
  final double stillnessRadPerSec;

  /// Screen width / height; vertical field of view is [fieldOfView] / aspect.
  final double aspect;

  MotionConfig copyWith({
    double? pointerGain,
    double? fieldOfView,
    double? countsPerRadian,
    double? deadzoneRadPerSec,
    double? gravityTau,
    double? pitchTau,
    double? biasTau,
    double? stillnessRadPerSec,
    double? aspect,
  }) =>
      MotionConfig(
        pointerGain: pointerGain ?? this.pointerGain,
        fieldOfView: fieldOfView ?? this.fieldOfView,
        countsPerRadian: countsPerRadian ?? this.countsPerRadian,
        deadzoneRadPerSec: deadzoneRadPerSec ?? this.deadzoneRadPerSec,
        gravityTau: gravityTau ?? this.gravityTau,
        pitchTau: pitchTau ?? this.pitchTau,
        biasTau: biasTau ?? this.biasTau,
        stillnessRadPerSec: stillnessRadPerSec ?? this.stillnessRadPerSec,
        aspect: aspect ?? this.aspect,
      );

  @override
  bool operator ==(Object other) =>
      other is MotionConfig &&
      other.pointerGain == pointerGain &&
      other.fieldOfView == fieldOfView &&
      other.countsPerRadian == countsPerRadian &&
      other.deadzoneRadPerSec == deadzoneRadPerSec &&
      other.gravityTau == gravityTau &&
      other.pitchTau == pitchTau &&
      other.biasTau == biasTau &&
      other.stillnessRadPerSec == stillnessRadPerSec &&
      other.aspect == aspect;

  @override
  int get hashCode => Object.hash(
        pointerGain,
        fieldOfView,
        countsPerRadian,
        deadzoneRadPerSec,
        gravityTau,
        pitchTau,
        biasTau,
        stillnessRadPerSec,
        aspect,
      );
}
