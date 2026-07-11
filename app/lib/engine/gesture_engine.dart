/// Gesture engine: deterministic `PointerSample → InputEvent` state machine
/// (docs/gesture-mapping.md). Pure Dart — no platform imports. All timing
/// decisions use sample timestamps, never wall-clock timers.
library;

import 'dart:math' as math;

import '../core/input_event.dart';
import 'gesture_config.dart';
import 'pointer_sample.dart';

enum _Mode {
  idle,
  touching, // fingers down, intent undecided
  pointing,
  dragging,
  scrolling,
  swiping,
  waitingForUp, // episode over; swallow everything until all fingers lift
}

class _Finger {
  _Finger(this.downX, this.downY)
      : lastX = downX,
        lastY = downY;

  final double downX;
  final double downY;
  double lastX;
  double lastY;

  double displacementTo(double x, double y) {
    final dx = x - downX;
    final dy = y - downY;
    return math.sqrt(dx * dx + dy * dy);
  }
}

class GestureEngine {
  GestureEngine({this.config = const GestureConfig()});

  final GestureConfig config;

  final Map<int, _Finger> _fingers = {};
  _Mode _mode = _Mode.idle;
  Duration _touchStart = Duration.zero;

  // Sub-unit remainders so slow motion is not truncated away.
  double _pointerRemX = 0, _pointerRemY = 0;
  double _scrollRemX = 0, _scrollRemY = 0;

  GestureKind? _swipeKind;
  double _swipeProgress = 0;

  /// Convenience for tests and offline analysis: full stream in, events out.
  List<InputEvent> processAll(Iterable<PointerSample> samples) =>
      [for (final s in samples) ...handleSample(s)];

  /// Feed one sample; returns the events it produced (often empty).
  List<InputEvent> handleSample(PointerSample sample) {
    switch (sample.phase) {
      case SamplePhase.down:
        return _onDown(sample);
      case SamplePhase.move:
        return _onMove(sample);
      case SamplePhase.up:
        return _onUp(sample);
      case SamplePhase.cancel:
        return _onCancel(sample);
    }
  }

  /// Aborts any in-flight gesture (app pause, disconnect). Emits the events
  /// needed to leave the host in a neutral state.
  List<InputEvent> reset() {
    final events = <InputEvent>[];
    if (_mode == _Mode.dragging) {
      events.add(const ButtonEvent(Button.left, down: false));
    }
    if (_mode == _Mode.swiping && _swipeKind != null) {
      events.add(
          GesturePhase(_swipeKind!, GesturePhaseKind.cancelled, _swipeProgress));
    }
    _fingers.clear();
    _toIdle();
    return events;
  }

  void _toIdle() {
    _mode = _Mode.idle;
    _pointerRemX = _pointerRemY = 0;
    _scrollRemX = _scrollRemY = 0;
    _swipeKind = null;
    _swipeProgress = 0;
  }

  List<InputEvent> _onDown(PointerSample s) {
    _fingers[s.pointerId] = _Finger(s.x, s.y);
    switch (_mode) {
      case _Mode.idle:
        _mode = _Mode.touching;
        _touchStart = s.timestamp;
        return const [];
      case _Mode.touching:
        // More fingers landing while undecided; > 3 aborts the episode.
        if (_fingers.length > 3) _mode = _Mode.waitingForUp;
        return const [];
      case _Mode.pointing:
      case _Mode.scrolling:
        // Extra finger mid-gesture ends the episode cleanly.
        _mode = _Mode.waitingForUp;
        return const [];
      case _Mode.dragging:
        _mode = _Mode.waitingForUp;
        return const [ButtonEvent(Button.left, down: false)];
      case _Mode.swiping:
        _mode = _Mode.waitingForUp;
        final kind = _swipeKind;
        _swipeKind = null;
        return kind == null
            ? const []
            : [GesturePhase(kind, GesturePhaseKind.cancelled, _swipeProgress)];
      case _Mode.waitingForUp:
        return const [];
    }
  }

  List<InputEvent> _onMove(PointerSample s) {
    final finger = _fingers[s.pointerId];
    if (finger == null) return const [];

    List<InputEvent> events;
    switch (_mode) {
      case _Mode.touching:
        events = _decideFromTouching(s, finger);
      case _Mode.pointing:
        events = _pointerDelta(s, finger);
      case _Mode.dragging:
        events = _pointerDelta(s, finger);
      case _Mode.scrolling:
        events = _scrollDelta(s, finger);
      case _Mode.swiping:
        // Centroid math must see this sample's position, not the previous one.
        finger.lastX = s.x;
        finger.lastY = s.y;
        events = _swipeUpdate();
      case _Mode.idle:
      case _Mode.waitingForUp:
        events = const [];
    }
    finger.lastX = s.x;
    finger.lastY = s.y;
    return events;
  }

  List<InputEvent> _decideFromTouching(PointerSample s, _Finger finger) {
    final disp = finger.displacementTo(s.x, s.y);
    final n = _fingers.length;

    if (n == 1) {
      if (disp < config.touchSlopPx) return const [];
      final held = s.timestamp - _touchStart;
      if (held >= config.longPressTimeout) {
        _mode = _Mode.dragging;
        return [
          const ButtonEvent(Button.left, down: true),
          ..._pointerDelta(s, finger),
        ];
      }
      _mode = _Mode.pointing;
      return _pointerDelta(s, finger);
    }

    if (n == 2) {
      if (disp < config.touchSlopPx) return const [];
      _mode = _Mode.scrolling;
      return _scrollDelta(s, finger);
    }

    // n == 3: lock direction once dominant-axis travel clears slop.
    // Include this sample's position in the centroid (see _onMove).
    finger.lastX = s.x;
    finger.lastY = s.y;
    final (dx, dy) = _centroidDisplacement();
    if (math.max(dx.abs(), dy.abs()) < config.touchSlopPx) return const [];
    _swipeKind = dx.abs() >= dy.abs()
        ? (dx > 0 ? GestureKind.swipeRight : GestureKind.swipeLeft)
        : (dy > 0 ? GestureKind.swipeDown : GestureKind.swipeUp);
    _mode = _Mode.swiping;
    _swipeProgress = _progressFor(dx, dy);
    return [GesturePhase(_swipeKind!, GesturePhaseKind.began, _swipeProgress)];
  }

  /// Accelerated pointer motion: out = |d|^exponent · gain, direction
  /// preserved, sub-unit remainders carried, clamped ±127 per report.
  List<InputEvent> _pointerDelta(PointerSample s, _Finger finger) {
    final dx = s.x - finger.lastX;
    final dy = s.y - finger.lastY;
    final mag = math.sqrt(dx * dx + dy * dy);
    if (mag == 0) return const [];
    final scale =
        math.pow(mag, config.accelExponent) * config.pointerGain / mag;
    _pointerRemX += dx * scale;
    _pointerRemY += dy * scale;
    final outX = _pointerRemX.truncate().clamp(-127, 127);
    final outY = _pointerRemY.truncate().clamp(-127, 127);
    _pointerRemX -= outX;
    _pointerRemY -= outY;
    if (outX == 0 && outY == 0) return const [];
    return [PointerMove(outX, outY)];
  }

  /// Two-finger scroll: this finger's delta → tick accumulator. Natural
  /// scrolling (content follows fingers) needs the sign flipped relative
  /// to raw HID wheel semantics, and the AC Pan (horizontal) axis runs
  /// opposite to the wheel axis — both verified against macOS.
  List<InputEvent> _scrollDelta(PointerSample s, _Finger finger) {
    final sign = config.naturalScroll ? -1.0 : 1.0;
    final ticksPerPx = config.scrollGain / config.scrollPxPerTick;
    _scrollRemX += (s.x - finger.lastX) * ticksPerPx * -sign;
    _scrollRemY += (s.y - finger.lastY) * ticksPerPx * sign;
    final tx = _scrollRemX.truncate().clamp(-127, 127);
    final ty = _scrollRemY.truncate().clamp(-127, 127);
    _scrollRemX -= tx;
    _scrollRemY -= ty;
    if (tx == 0 && ty == 0) return const [];
    return [Scroll(tx, ty)];
  }

  List<InputEvent> _swipeUpdate() {
    final kind = _swipeKind;
    if (kind == null) return const [];
    final (dx, dy) = _centroidDisplacement();
    final progress = _progressFor(dx, dy);
    if (progress == _swipeProgress) return const [];
    _swipeProgress = progress;
    return [GesturePhase(kind, GesturePhaseKind.changed, progress)];
  }

  /// Centroid displacement from touch-down across all active fingers.
  (double, double) _centroidDisplacement() {
    var dx = 0.0, dy = 0.0;
    for (final f in _fingers.values) {
      dx += f.lastX - f.downX;
      dy += f.lastY - f.downY;
    }
    final n = _fingers.length;
    return n == 0 ? (0, 0) : (dx / n, dy / n);
  }

  double _progressFor(double dx, double dy) {
    final kind = _swipeKind;
    if (kind == null) return 0;
    final along = switch (kind) {
      GestureKind.swipeRight => dx,
      GestureKind.swipeLeft => -dx,
      GestureKind.swipeDown => dy,
      GestureKind.swipeUp => -dy,
    };
    return (along / config.swipeTriggerPx).clamp(0.0, 1.0);
  }

  List<InputEvent> _onUp(PointerSample s) {
    final finger = _fingers.remove(s.pointerId);
    if (finger == null) return const [];
    final remaining = _fingers.length;

    switch (_mode) {
      case _Mode.touching:
        final elapsed = s.timestamp - _touchStart;
        final moved = finger.displacementTo(s.x, s.y) >= config.touchSlopPx;
        final isTap = elapsed < config.tapTimeout && !moved;
        // Finger count at decision time includes the one lifting.
        final n = remaining + 1;
        if (isTap && n == 1) {
          _toIdle();
          return const [
            ButtonEvent(Button.left, down: true),
            ButtonEvent(Button.left, down: false),
          ];
        }
        if (isTap && n == 2) {
          _mode = _Mode.waitingForUp;
          _settleIfClear();
          return const [
            ButtonEvent(Button.right, down: true),
            ButtonEvent(Button.right, down: false),
          ];
        }
        _mode = _Mode.waitingForUp;
        _settleIfClear();
        return const [];

      case _Mode.pointing:
        _toIdle();
        return const [];

      case _Mode.dragging:
        _toIdle();
        return const [ButtonEvent(Button.left, down: false)];

      case _Mode.scrolling:
        _mode = _Mode.waitingForUp;
        _settleIfClear();
        return const [];

      case _Mode.swiping:
        final kind = _swipeKind;
        _swipeKind = null;
        _mode = _Mode.waitingForUp;
        final progress = _swipeProgress;
        _settleIfClear();
        return kind == null
            ? const []
            : [GesturePhase(kind, GesturePhaseKind.ended, progress)];

      case _Mode.idle:
      case _Mode.waitingForUp:
        _settleIfClear();
        return const [];
    }
  }

  List<InputEvent> _onCancel(PointerSample s) {
    _fingers.remove(s.pointerId);
    final events = <InputEvent>[];
    switch (_mode) {
      case _Mode.dragging:
        events.add(const ButtonEvent(Button.left, down: false));
      case _Mode.swiping:
        final kind = _swipeKind;
        _swipeKind = null;
        if (kind != null) {
          events.add(
              GesturePhase(kind, GesturePhaseKind.cancelled, _swipeProgress));
        }
      default:
        break;
    }
    _mode = _Mode.waitingForUp;
    _settleIfClear();
    return events;
  }

  void _settleIfClear() {
    if (_fingers.isEmpty) _toIdle();
  }
}
