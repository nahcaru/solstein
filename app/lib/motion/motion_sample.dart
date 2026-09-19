/// One instant of device motion, in the Android/Flutter device frame:
/// +X right across the screen, +Y up the screen, +Z out of the screen.
///
/// Pure data — the engine never sees a sensor package type, so it stays
/// deterministic and free of platform imports.
library;

class MotionSample {
  const MotionSample({
    required this.gyroX,
    required this.gyroY,
    required this.gyroZ,
    required this.accelX,
    required this.accelY,
    required this.accelZ,
    required this.timestamp,
  });

  /// Angular velocity in rad/s (right-hand rule about each device axis).
  final double gyroX, gyroY, gyroZ;

  /// Accelerometer in m/s², **including** gravity. At rest this is the
  /// specific force, which points *up* (a phone lying face-up reads +Z).
  final double accelX, accelY, accelZ;

  /// Monotonic time; only differences are meaningful.
  final Duration timestamp;

  @override
  String toString() => 'MotionSample(gyro: ($gyroX, $gyroY, $gyroZ), '
      'accel: ($accelX, $accelY, $accelZ), t: $timestamp)';
}
