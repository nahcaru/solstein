/// [MotionSource] backed by `sensors_plus`: raw gyroscope joined with the
/// accelerometer (gravity included). The engine does the fusion.
library;

import 'dart:async';

import 'package:sensors_plus/sensors_plus.dart';

import 'motion_sample.dart';
import 'motion_source.dart';

class SensorsMotionSource implements MotionSource {
  /// [samplingPeriod] defaults to 100 Hz: hand tremor (4–12 Hz) needs headroom
  /// over Nyquist to be filtered, and Android 12+ allows up to 200 Hz without
  /// the HIGH_SAMPLING_RATE_SENSORS permission. Fall back to
  /// `SensorInterval.gameInterval` (50 Hz) if the Bluetooth link cannot keep
  /// up with the report rate.
  SensorsMotionSource({this.samplingPeriod = defaultSamplingPeriod});

  static const defaultSamplingPeriod = Duration(milliseconds: 10);

  final Duration samplingPeriod;

  final _controller = StreamController<MotionSample>.broadcast();
  StreamSubscription<GyroscopeEvent>? _gyroSub;
  StreamSubscription<AccelerometerEvent>? _accelSub;
  AccelerometerEvent? _accel;
  int? _originMicros;

  @override
  Stream<MotionSample> get samples => _controller.stream;

  @override
  Future<void> start() async {
    if (_gyroSub != null) return;
    _accel = null;
    _originMicros = null;
    _accelSub = accelerometerEventStream(samplingPeriod: samplingPeriod)
        .listen((e) => _accel = e, onError: _controller.addError);
    _gyroSub = gyroscopeEventStream(samplingPeriod: samplingPeriod)
        .listen(_onGyro, onError: _controller.addError);
  }

  /// One [MotionSample] per gyro event, paired with the latest accelerometer
  /// reading. Timestamps are the sensor's own (differences only), not
  /// delivery time: batching would otherwise jitter the engine's dt.
  void _onGyro(GyroscopeEvent g) {
    final a = _accel;
    if (a == null) return; // no gravity reference yet
    final micros = g.timestamp.microsecondsSinceEpoch;
    _originMicros ??= micros;
    _controller.add(MotionSample(
      gyroX: g.x,
      gyroY: g.y,
      gyroZ: g.z,
      accelX: a.x,
      accelY: a.y,
      accelZ: a.z,
      timestamp: Duration(microseconds: micros - _originMicros!),
    ));
  }

  @override
  Future<void> stop() async {
    final gyro = _gyroSub, accel = _accelSub;
    _gyroSub = _accelSub = null;
    await gyro?.cancel();
    await accel?.cancel();
  }
}
