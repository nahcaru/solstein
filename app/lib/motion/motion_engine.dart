/// Presenter motion engine: timestamped [MotionSample]s in, [InputEvent]s
/// out. Pure Dart — no Flutter or platform imports, like GestureEngine, and
/// all timing comes from sample timestamps (never wall-clock).
///
/// The phone is held like a wand: its top edge (device +Y) is the pointing
/// axis. Rotation rates are projected onto *world* axes using gravity, so a
/// sweep stays horizontal however the phone is rolled about that axis.
///
///   yaw   = rotation about world-up            → horizontal cursor motion
///   pitch = rotation about the horizontal axis → vertical cursor motion
///           perpendicular to the pointing axis
///
/// Two mappings:
///   * gliding (default): angular velocity → relative [PointerMove], with
///     sub-unit remainder carry so slow sweeps are not truncated to zero.
///   * spotlight (held): orientation → absolute [PointerAbsolute]. Yaw has
///     no absolute reference indoors, so it is zeroed on every press and the
///     pointer lands at dead centre; pitch comes from gravity and cannot
///     drift.
library;

import 'dart:math' as math;

import '../core/input_event.dart';
import 'motion_config.dart';
import 'motion_sample.dart';

class MotionEngine {
  MotionEngine({
    this.config = const MotionConfig(),
    this.absoluteSpotlight = true,
  });

  final MotionConfig config;

  /// Whether a held spotlight maps absolutely. When false (sink without
  /// Capability.absolutePointer, or a host that rejects the report) the
  /// spotlight degrades to slow relative "precision" pointing and this
  /// engine never emits [PointerAbsolute].
  final bool absoluteSpotlight;

  /// Precision (degraded spotlight) scaling of gain and deadzone.
  static const double precisionGainScale = 0.35;
  static const double precisionDeadzoneScale = 0.5;

  /// Longest dt integrated in one step; a stalled sensor stream must not
  /// produce one enormous jump.
  static const double _maxDt = 0.1;

  /// Below this |cross(p, up)| the phone points near-vertically and the
  /// horizontal axis is ill-defined; keep the previous one instead.
  static const double _minHorizontalNorm = 0.15;

  /// Until [MotionConfig.biasTau] seconds of bias learning have accrued the
  /// stillness gate is this wide, so a bias larger than
  /// [MotionConfig.stillnessRadPerSec] (which would otherwise never look
  /// "still", and so never be learned) can still be found.
  static const double _warmupStillnessRadPerSec = 0.15;

  /// Absolute position changes smaller than this (normalized) are not
  /// re-sent; ≈1 px on a 1920-wide desktop.
  static const double _absoluteEpsilon = 0.0005;

  // Gravity direction in the device frame (accelerometer at rest = up).
  double _gx = 0, _gy = 0, _gz = 1;
  bool _hasGravity = false;

  // Learned gyro bias (rad/s, device frame).
  double _biasX = 0, _biasY = 0, _biasZ = 0;

  // Last horizontal axis perpendicular to the pointing axis (device frame).
  double _rx = 1, _ry = 0, _rz = 0;

  double _learnedSeconds = 0;

  Duration? _lastTimestamp;

  // Relative-mode sub-unit remainders.
  double _remX = 0, _remY = 0;

  // Complementary-filtered elevation of the pointing axis (radians).
  double _pitch = 0;

  // Spotlight state.
  bool _spotlight = false;

  /// Spotlight pressed before gravity was known: the reference pitch (and the
  /// centring position) is taken from the first sample instead of a
  /// placeholder, which would teleport the pointer once real data arrived.
  bool _pendingSpotlightRef = false;
  double _yaw = 0;
  double _pitchRef = 0;
  double? _lastAbsX, _lastAbsY;

  bool _clickDown = false;

  bool get spotlightActive => _spotlight;

  /// Whether [handleSample] currently maps to absolute positions.
  bool get _absoluteNow => _spotlight && absoluteSpotlight;

  List<InputEvent> handleSample(MotionSample s) {
    // One bad sensor reading must not poison the integrators (NaN would
    // throw in truncate() and stay in every later state).
    if (!(s.gyroX.isFinite &&
        s.gyroY.isFinite &&
        s.gyroZ.isFinite &&
        s.accelX.isFinite &&
        s.accelY.isFinite &&
        s.accelZ.isFinite)) {
      return const [];
    }
    final last = _lastTimestamp;
    _lastTimestamp = s.timestamp;

    List<InputEvent> seeded = const [];
    if (!_hasGravity) {
      _gx = s.accelX;
      _gy = s.accelY;
      _gz = s.accelZ;
      _hasGravity = true;
      _pitch = _elevationFromGravity();
      if (_pendingSpotlightRef) {
        _pendingSpotlightRef = false;
        _pitchRef = _pitch;
        _lastAbsX = _lastAbsY = 0.5;
        seeded = const [PointerAbsolute(0.5, 0.5)];
      }
    }
    if (last == null) return seeded;
    final dt = ((s.timestamp - last).inMicroseconds / 1e6).clamp(0.0, _maxDt);
    if (dt == 0) return const [];

    // 1. Gravity, low-passed.
    final ga = dt / (config.gravityTau + dt);
    _gx += (s.accelX - _gx) * ga;
    _gy += (s.accelY - _gy) * ga;
    _gz += (s.accelZ - _gz) * ga;
    var ux = _gx, uy = _gy, uz = _gz;
    final gn = math.sqrt(ux * ux + uy * uy + uz * uz);
    if (gn < 1e-6) return const []; // free fall: no usable gravity
    ux /= gn;
    uy /= gn;
    uz /= gn;

    // 2. Gyro bias: learn only while genuinely still, then subtract.
    var wx = s.gyroX - _biasX;
    var wy = s.gyroY - _biasY;
    var wz = s.gyroZ - _biasZ;
    final gate = _learnedSeconds < config.biasTau
        ? _warmupStillnessRadPerSec
        : config.stillnessRadPerSec;
    // Never learn while the spotlight is held: deliberate slow pointing
    // (exactly what precision mode invites) would be absorbed as bias.
    if (!_spotlight && math.sqrt(wx * wx + wy * wy + wz * wz) < gate) {
      _learnedSeconds += dt;
      final ba = dt / (config.biasTau + dt);
      _biasX += (s.gyroX - _biasX) * ba;
      _biasY += (s.gyroY - _biasY) * ba;
      _biasZ += (s.gyroZ - _biasZ) * ba;
      wx = s.gyroX - _biasX;
      wy = s.gyroY - _biasY;
      wz = s.gyroZ - _biasZ;
    }

    // 3. Project onto world axes. p = device +Y, so cross(p, up) =
    //    (uz, 0, -ux): the horizontal axis to the pointing axis's right.
    final rn = math.sqrt(uz * uz + ux * ux);
    if (rn >= _minHorizontalNorm) {
      _rx = uz / rn;
      _ry = 0;
      _rz = -ux / rn;
    }
    final yawRate = wx * ux + wy * uy + wz * uz; // + = turning left
    final pitchRate = wx * _rx + wy * _ry + wz * _rz; // + = tip rising

    // 4. Pitch: integrate the gyro, pull toward gravity (complementary).
    final pa = dt / (config.pitchTau + dt);
    _pitch += pitchRate * dt;
    _pitch += (math.asin(uy.clamp(-1.0, 1.0)) - _pitch) * pa;

    return _absoluteNow
        ? _absoluteStep(yawRate, dt)
        : _relativeStep(yawRate, pitchRate, dt);
  }

  List<InputEvent> processAll(Iterable<MotionSample> samples) =>
      [for (final s in samples) ...handleSample(s)];

  /// Spotlight pressed: snapshot the reference and, when absolute mapping is
  /// available, land the pointer at dead centre.
  List<InputEvent> beginSpotlight() {
    if (_spotlight) return const [];
    _spotlight = true;
    _remX = _remY = 0;
    _yaw = 0;
    if (!absoluteSpotlight) return const [];
    if (!_hasGravity) {
      _pendingSpotlightRef = true;
      return const [];
    }
    _pitchRef = _pitch;
    _lastAbsX = 0.5;
    _lastAbsY = 0.5;
    return const [PointerAbsolute(0.5, 0.5)];
  }

  /// Spotlight released: gliding resumes from wherever the pointer is.
  List<InputEvent> endSpotlight() {
    if (!_spotlight) return const [];
    _spotlight = false;
    _pendingSpotlightRef = false;
    _remX = _remY = 0;
    _lastAbsX = _lastAbsY = null;
    return const [];
  }

  /// Click button edge. The engine tracks it so [reset] can release it.
  List<InputEvent> click({required bool down}) {
    if (_clickDown == down) return const [];
    _clickDown = down;
    return [ButtonEvent(Button.left, down: down)];
  }

  /// Aborts everything in flight: releases a held click and forgets bias,
  /// gravity and the spotlight reference.
  List<InputEvent> reset() {
    final events = <InputEvent>[
      if (_clickDown) const ButtonEvent(Button.left, down: false),
    ];
    _clickDown = false;
    _spotlight = false;
    _pendingSpotlightRef = false;
    _learnedSeconds = 0;
    _hasGravity = false;
    _biasX = _biasY = _biasZ = 0;
    _gx = 0;
    _gy = 0;
    _gz = 1;
    _rx = 1;
    _ry = 0;
    _rz = 0;
    _lastTimestamp = null;
    _remX = _remY = 0;
    _yaw = 0;
    _pitch = 0;
    _pitchRef = 0;
    _lastAbsX = _lastAbsY = null;
    return events;
  }

  double _elevationFromGravity() {
    final n = math.sqrt(_gx * _gx + _gy * _gy + _gz * _gz);
    return n < 1e-6 ? 0 : math.asin((_gy / n).clamp(-1.0, 1.0));
  }

  List<InputEvent> _relativeStep(double yawRate, double pitchRate, double dt) {
    final precision = _spotlight; // degraded spotlight
    final gain = config.pointerGain * (precision ? precisionGainScale : 1.0);
    final deadzone =
        config.deadzoneRadPerSec * (precision ? precisionDeadzoneScale : 1.0);
    final k = config.countsPerRadian * gain;
    // Sweep right → yawRate < 0 → cursor right; tip up → cursor up (−y).
    var vx = yawRate.abs() < deadzone ? 0.0 : -yawRate * dt * k;
    var vy = pitchRate.abs() < deadzone ? 0.0 : -pitchRate * dt * k;
    _remX += vx;
    _remY += vy;
    // Carry only the sub-unit fraction. Whatever exceeds the ±127 report cap
    // is discarded, not banked: a fast flick would otherwise keep the cursor
    // sliding at full speed for seconds after the phone stopped.
    final rawX = _remX.truncate();
    final rawY = _remY.truncate();
    final outX = rawX.clamp(-127, 127);
    final outY = rawY.clamp(-127, 127);
    _remX -= rawX;
    _remY -= rawY;
    if (outX == 0 && outY == 0) return const [];
    return [PointerMove(outX, outY)];
  }

  List<InputEvent> _absoluteStep(double yawRate, double dt) {
    // Clamp the integrator to the screen edges: an unbounded one winds up
    // past the edge and the pointer stays dead until the user sweeps all the
    // way back. (Pitch is gravity-anchored, so it needs no such bound.)
    final half = config.fieldOfView / 2;
    if (yawRate.abs() >= config.deadzoneRadPerSec) {
      _yaw = (_yaw + yawRate * dt).clamp(-half, half);
    }
    final fovY = config.fieldOfView / config.aspect;
    final x = (0.5 - _yaw / config.fieldOfView).clamp(0.0, 1.0);
    final y = (0.5 - (_pitch - _pitchRef) / fovY).clamp(0.0, 1.0);
    final lx = _lastAbsX, ly = _lastAbsY;
    if (lx != null &&
        ly != null &&
        (x - lx).abs() < _absoluteEpsilon &&
        (y - ly).abs() < _absoluteEpsilon) {
      return const [];
    }
    _lastAbsX = x;
    _lastAbsY = y;
    return [PointerAbsolute(x, y)];
  }
}
