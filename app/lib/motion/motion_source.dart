/// Where [MotionSample]s come from. The seam that keeps MotionEngine free of
/// any sensor package: swap in a native rotation-vector channel (better
/// long-horizon yaw) or a scripted fake without touching the engine.
library;

import 'motion_sample.dart';

abstract interface class MotionSource {
  /// Broadcast stream of fused gyro + accelerometer samples. Emits nothing
  /// until [start]; errors (e.g. no gyroscope) arrive as stream errors.
  Stream<MotionSample> get samples;

  /// Begins sensor delivery. Idempotent.
  Future<void> start();

  /// Stops sensor delivery (battery). Idempotent.
  Future<void> stop();
}
