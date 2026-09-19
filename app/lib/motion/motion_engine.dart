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
/// Like a presentation remote's button, motion is a *virtual clutch*: the
/// cursor moves only between [engage] and [disengage]. While disengaged the
/// engine still tracks gravity and learns the gyro bias (the phone is usually
/// resting in a hand), it just emits nothing.
///
/// While engaged, each projected rate goes through
///   One Euro filter (tremor)  →  deadzone  →  ballistics curve
///   →  counts per second  →  ×dt with sub-unit remainder carry
/// and comes out as a relative [PointerMove].
///
/// Relative output means there is no wind-up to guard against: the host stops
/// the cursor at the screen edge and the rotation beyond it is simply lost,
/// so swinging back responds immediately.
library;

import 'dart:math' as math;

import '../core/input_event.dart';
import 'motion_config.dart';
import 'motion_sample.dart';
import 'one_euro_filter.dart';

class MotionEngine {
  MotionEngine({MotionConfig config = const MotionConfig()})
      : _config = config,
        _yawFilter = _newFilter(config),
        _pitchFilter = _newFilter(config);

  MotionConfig _config;

  static OneEuroFilter _newFilter(MotionConfig c) => OneEuroFilter(
        minCutoffHz: c.smoothingMinCutoffHz,
        beta: c.smoothingBeta,
      );

  MotionConfig get config => _config;

  /// Swaps the tunables in place. Unlike building a new engine this keeps the
  /// learned gyro bias and gravity, so dragging a Settings slider does not
  /// throw away seconds of calibration. Filters and remainders start fresh.
  set config(MotionConfig value) {
    if (value == _config) return;
    _config = value;
    _yawFilter = _newFilter(value);
    _pitchFilter = _newFilter(value);
    _remX = _remY = 0;
  }

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

  /// During [recalibrate] the device is assumed still, so learning is fast;
  /// but a rate above this is obviously not a still device and is skipped.
  static const double _calibrationTau = 0.3;
  static const double _calibrationMaxRadPerSec = 0.5;

  OneEuroFilter _yawFilter;
  OneEuroFilter _pitchFilter;

  // Gravity direction in the device frame (accelerometer at rest = up).
  double _gx = 0, _gy = 0, _gz = 1;
  bool _hasGravity = false;

  // Learned gyro bias (rad/s, device frame).
  double _biasX = 0, _biasY = 0, _biasZ = 0;
  double _learnedSeconds = 0;
  double _calibrateRemaining = 0;

  // Last horizontal axis perpendicular to the pointing axis (device frame).
  double _rx = 1, _ry = 0, _rz = 0;

  Duration? _lastTimestamp;

  // Sub-unit remainders carried between samples.
  double _remX = 0, _remY = 0;

  bool _engaged = false;
  bool _clickDown = false;

  /// Whether the clutch is held (the cursor is following the phone).
  bool get engaged => _engaged;

  /// Whether a [recalibrate] is still in progress.
  bool get calibrating => _calibrateRemaining > 0;

  /// The gyro zero-offset learned so far (rad/s, device frame).
  ({double x, double y, double z}) get gyroBias =>
      (x: _biasX, y: _biasY, z: _biasZ);

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

    if (!_hasGravity) {
      _gx = s.accelX;
      _gy = s.accelY;
      _gz = s.accelZ;
      _hasGravity = true;
    }
    if (last == null) return const [];
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

    // 2. Gyro bias.
    var wx = s.gyroX - _biasX;
    var wy = s.gyroY - _biasY;
    var wz = s.gyroZ - _biasZ;
    _learnBias(s, dt, math.sqrt(wx * wx + wy * wy + wz * wz));
    wx = s.gyroX - _biasX;
    wy = s.gyroY - _biasY;
    wz = s.gyroZ - _biasZ;

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

    if (!_engaged) return const [];
    return _glide(yawRate, pitchRate, dt);
  }

  List<InputEvent> processAll(Iterable<MotionSample> samples) =>
      [for (final s in samples) ...handleSample(s)];

  /// Clutch pressed: motion starts moving the cursor. Filter state and
  /// remainders start fresh so nothing stale carries over from before.
  List<InputEvent> engage() {
    if (_engaged) return const [];
    _engaged = true;
    _resetGlide();
    return const [];
  }

  /// Clutch released: the cursor freezes.
  List<InputEvent> disengage() {
    if (!_engaged) return const [];
    _engaged = false;
    _resetGlide();
    return const [];
  }

  /// Click button edge. The engine tracks it so [reset] can release it.
  List<InputEvent> click({required bool down}) {
    if (_clickDown == down) return const [];
    _clickDown = down;
    return [ButtonEvent(Button.left, down: down)];
  }

  /// Relearns the gyro zero-offset quickly, assuming the phone is held still
  /// for [duration]. Watch [calibrating] for completion.
  void recalibrate({Duration duration = const Duration(seconds: 2)}) {
    _calibrateRemaining = duration.inMicroseconds / 1e6;
  }

  /// Aborts everything in flight: releases a held click and forgets bias,
  /// gravity and the clutch.
  List<InputEvent> reset() {
    final events = <InputEvent>[
      if (_clickDown) const ButtonEvent(Button.left, down: false),
    ];
    _clickDown = false;
    _engaged = false;
    _hasGravity = false;
    _biasX = _biasY = _biasZ = 0;
    _learnedSeconds = 0;
    _calibrateRemaining = 0;
    _gx = 0;
    _gy = 0;
    _gz = 1;
    _rx = 1;
    _ry = 0;
    _rz = 0;
    _lastTimestamp = null;
    _resetGlide();
    return events;
  }

  void _resetGlide() {
    _remX = _remY = 0;
    _yawFilter.reset();
    _pitchFilter.reset();
  }

  /// Learns the gyro bias while it is safe to: during a [recalibrate], or
  /// while the clutch is released and the device is still. Never while
  /// engaged — slow deliberate pointing would be absorbed as bias.
  void _learnBias(MotionSample s, double dt, double correctedRate) {
    final calibrating = _calibrateRemaining > 0;
    final double tau;
    if (calibrating) {
      _calibrateRemaining -= dt;
      if (correctedRate > _calibrationMaxRadPerSec) return;
      tau = _calibrationTau;
    } else {
      if (_engaged) return;
      final gate = _learnedSeconds < config.biasTau
          ? _warmupStillnessRadPerSec
          : config.stillnessRadPerSec;
      if (correctedRate >= gate) return;
      tau = config.biasTau;
    }
    _learnedSeconds += dt;
    final a = dt / (tau + dt);
    _biasX += (s.gyroX - _biasX) * a;
    _biasY += (s.gyroY - _biasY) * a;
    _biasZ += (s.gyroZ - _biasZ) * a;
  }

  /// Ballistics: |ω|^p, normalized so [MotionConfig.ballisticsRefRadPerSec]
  /// has unit gain. Slow motion gets finer, fast motion reaches further.
  double _ballistics(double omega) {
    final ref = config.ballisticsRefRadPerSec;
    return omega.sign *
        ref *
        math.pow(omega.abs() / ref, config.ballisticsExponent);
  }

  List<InputEvent> _glide(double yawRate, double pitchRate, double dt) {
    var yaw = _yawFilter.filter(yawRate, dt);
    var pitch = _pitchFilter.filter(pitchRate, dt);
    if (yaw.abs() < config.deadzoneRadPerSec) yaw = 0;
    if (pitch.abs() < config.deadzoneRadPerSec) pitch = 0;
    final k = config.countsPerRadian * config.pointerGain;
    // Sweep right → yaw < 0 → cursor right; tip up → cursor up (−y).
    _remX += -_ballistics(yaw) * dt * k;
    _remY += -_ballistics(pitch) * dt * k;
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
}
