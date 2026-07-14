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
  swiping, // 3-finger swipe or 2-finger page flick (both phased)
  spreading, // 4-finger spread/pinch (phased)
  zooming, // 2-finger pinch-zoom (phased)
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

  /// When the last one-finger tap lifted; a touch beginning within
  /// [GestureConfig.tapDragTimeout] of it drags as soon as it moves.
  Duration? _lastTapUp;
  bool _tapDragArmed = false;

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
    if ((_mode == _Mode.swiping ||
            _mode == _Mode.spreading ||
            _mode == _Mode.zooming) &&
        _swipeKind != null) {
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
    _tapDragArmed = false; // _lastTapUp survives: it arms the NEXT touch
  }

  List<InputEvent> _onDown(PointerSample s) {
    _fingers[s.pointerId] = _Finger(s.x, s.y);
    switch (_mode) {
      case _Mode.idle:
        _mode = _Mode.touching;
        _touchStart = s.timestamp;
        final lastTap = _lastTapUp;
        _tapDragArmed =
            lastTap != null && s.timestamp - lastTap <= config.tapDragTimeout;
        return const [];
      case _Mode.touching:
        // More fingers landing while undecided; > 4 aborts the episode.
        _tapDragArmed = false; // tap-drag is strictly one-finger
        if (_fingers.length > 4) _mode = _Mode.waitingForUp;
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
      case _Mode.spreading:
      case _Mode.zooming:
        // Extra finger mid-gesture cancels it.
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
        // Compute the scroll delta first (needs the pre-sample position),
        // then promote to zoom if both fingers are now pinching.
        final scrollEvents = _scrollDelta(s, finger);
        finger.lastX = s.x;
        finger.lastY = s.y;
        final zoomKind = _detectPinch();
        if (zoomKind != null) {
          _swipeKind = zoomKind;
          _mode = _Mode.zooming;
          _swipeProgress = _spreadProgress(_spreadRatio());
          events = [GesturePhase(zoomKind, GesturePhaseKind.began, _swipeProgress)];
        } else {
          events = scrollEvents;
        }
      case _Mode.swiping:
        // Centroid math must see this sample's position, not the previous one.
        finger.lastX = s.x;
        finger.lastY = s.y;
        events = _swipeUpdate();
      case _Mode.spreading:
      case _Mode.zooming:
        finger.lastX = s.x;
        finger.lastY = s.y;
        events = _spreadUpdate();
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
      // Drag via tap-and-drag (touch right after a tap) or long-press.
      if (_tapDragArmed || held >= config.longPressTimeout) {
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
      // Fast, dominantly-horizontal motion is a page flick (browser
      // back/forward); anything slower or steeper is a scroll. Pinch-zoom
      // is detected later as a transition out of scrolling, once both
      // fingers have moved (see _detectPinch) — a single moving finger is
      // always scroll/flick, never zoom.
      final dxTotal = s.x - finger.downX;
      final dyTotal = s.y - finger.downY;
      final elapsedMs =
          (s.timestamp - _touchStart).inMicroseconds / 1000.0;
      final speed = elapsedMs <= 0 ? double.infinity : disp / elapsedMs;
      if (dxTotal.abs() >= 2 * dyTotal.abs() &&
          speed >= config.pageFlickMinVelocity) {
        finger.lastX = s.x;
        finger.lastY = s.y;
        _swipeKind = dxTotal > 0
            ? GestureKind.pageSwipeRight
            : GestureKind.pageSwipeLeft;
        _mode = _Mode.swiping;
        final (cdx, cdy) = _centroidDisplacement();
        _swipeProgress = _progressFor(cdx, cdy);
        return [
          GesturePhase(_swipeKind!, GesturePhaseKind.began, _swipeProgress)
        ];
      }
      _mode = _Mode.scrolling;
      return _scrollDelta(s, finger);
    }

    if (n == 3) {
      // Lock direction once dominant-axis travel clears slop.
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

    // n == 4: fingers apart → spread (show desktop); together → pinch
    // (restore windows).
    finger.lastX = s.x;
    finger.lastY = s.y;
    final ratio = _spreadRatio();
    if (ratio >= 1 + config.spreadBeginRatio) {
      _swipeKind = GestureKind.spread;
    } else if (ratio <= 1 - config.spreadBeginRatio) {
      _swipeKind = GestureKind.pinch;
    } else {
      return const [];
    }
    _mode = _Mode.spreading;
    _swipeProgress = _spreadProgress(ratio);
    return [GesturePhase(_swipeKind!, GesturePhaseKind.began, _swipeProgress)];
  }

  /// Accelerated pointer motion: out = |d|^exponent · gain, direction
  /// preserved, sub-unit remainders carried, clamped ±127 per report.
  List<InputEvent> _pointerDelta(PointerSample s, _Finger finger) {
    final dx = s.x - finger.lastX;
    final dy = s.y - finger.lastY;
    final mag = math.sqrt(dx * dx + dy * dy);
    if (mag == 0) return const [];
    final scale = math.pow(mag, config.accelExponent) *
        config.pointerGain *
        GestureConfig.basePointerScale /
        mag;
    _pointerRemX += dx * scale;
    _pointerRemY += dy * scale;
    final outX = _pointerRemX.truncate().clamp(-127, 127);
    final outY = _pointerRemY.truncate().clamp(-127, 127);
    _pointerRemX -= outX;
    _pointerRemY -= outY;
    if (outX == 0 && outY == 0) return const [];
    return [PointerMove(outX, outY)];
  }

  /// Two-finger scroll: this finger's delta → tick accumulator. Sign logic:
  /// in raw HID semantics natural scrolling means +wheel for fingers-down
  /// and the AC Pan axis runs opposite to the wheel axis; a host that
  /// applies its own scroll inversion (macOS "natural scrolling" default)
  /// flips both axes once more. Verified against macOS; Windows/Linux use
  /// the uninverted-host convention.
  List<InputEvent> _scrollDelta(PointerSample s, _Finger finger) {
    final hostFlip = config.hostInvertsScroll ? -1.0 : 1.0;
    final sign = (config.naturalScroll ? 1.0 : -1.0) * hostFlip;
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

  List<InputEvent> _spreadUpdate() {
    final kind = _swipeKind;
    if (kind == null) return const [];
    final progress = _spreadProgress(_spreadRatio());
    if (progress == _swipeProgress) return const [];
    _swipeProgress = progress;
    return [GesturePhase(kind, GesturePhaseKind.changed, progress)];
  }

  /// Detects a two-finger pinch: both fingers displaced beyond slop with
  /// opposing radial motion (moving apart or together along the line that
  /// joined them). Returns the zoom direction, or null when the pair is
  /// translating together (scroll). Requiring *both* fingers to move is
  /// what keeps a one-finger scroll or horizontal flick from reading as a
  /// zoom. Only meaningful with exactly two fingers down.
  GestureKind? _detectPinch() {
    if (_fingers.length != 2) return null;
    final fs = _fingers.values.toList(growable: false);
    final a = fs[0], b = fs[1];
    final axisX = a.downX - b.downX, axisY = a.downY - b.downY;
    final len = math.sqrt(axisX * axisX + axisY * axisY);
    if (len == 0) return null;
    final ux = axisX / len, uy = axisY / len;
    // Both radial displacements projected on the same axis: a translating
    // pair shares their sign, a pinching pair opposes.
    final ra = (a.lastX - a.downX) * ux + (a.lastY - a.downY) * uy;
    final rb = (b.lastX - b.downX) * ux + (b.lastY - b.downY) * uy;
    final floor = config.touchSlopPx;
    if (ra.abs() < floor || rb.abs() < floor || ra * rb >= 0) return null;
    // ra − rb is the inter-finger distance change: positive = apart.
    return (ra - rb) > 0 ? GestureKind.zoomIn : GestureKind.zoomOut;
  }

  /// Current mean finger-to-centroid distance relative to the same measure
  /// at touch-down. > 1 means the fingers have spread apart.
  double _spreadRatio() {
    final n = _fingers.length;
    if (n < 2) return 1;
    var cx0 = 0.0, cy0 = 0.0, cx1 = 0.0, cy1 = 0.0;
    for (final f in _fingers.values) {
      cx0 += f.downX;
      cy0 += f.downY;
      cx1 += f.lastX;
      cy1 += f.lastY;
    }
    cx0 /= n;
    cy0 /= n;
    cx1 /= n;
    cy1 /= n;
    var d0 = 0.0, d1 = 0.0;
    for (final f in _fingers.values) {
      d0 += math.sqrt(math.pow(f.downX - cx0, 2) + math.pow(f.downY - cy0, 2));
      d1 += math.sqrt(math.pow(f.lastX - cx1, 2) + math.pow(f.lastY - cy1, 2));
    }
    return d0 == 0 ? 1 : d1 / d0;
  }

  /// Spread commits at [GestureConfig.spreadTriggerRatio]; the shrinking
  /// gestures (pinch, zoom-out) commit at its reciprocal, so both
  /// directions need the same relative finger travel.
  double _spreadProgress(double ratio) {
    if (_swipeKind == GestureKind.pinch || _swipeKind == GestureKind.zoomOut) {
      final trigger = 1 - 1 / config.spreadTriggerRatio;
      return ((1 - ratio) / trigger).clamp(0.0, 1.0);
    }
    return ((ratio - 1) / (config.spreadTriggerRatio - 1)).clamp(0.0, 1.0);
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
      GestureKind.swipeRight || GestureKind.pageSwipeRight => dx,
      GestureKind.swipeLeft || GestureKind.pageSwipeLeft => -dx,
      GestureKind.swipeDown => dy,
      GestureKind.swipeUp => -dy,
      // Scale gestures use _spreadProgress instead.
      GestureKind.spread ||
      GestureKind.pinch ||
      GestureKind.zoomIn ||
      GestureKind.zoomOut =>
        0.0,
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
          _lastTapUp = s.timestamp;
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
        if (isTap && n == 3) {
          _mode = _Mode.waitingForUp;
          _settleIfClear();
          return const [
            ButtonEvent(Button.middle, down: true),
            ButtonEvent(Button.middle, down: false),
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
      case _Mode.spreading:
      case _Mode.zooming:
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
      case _Mode.spreading:
      case _Mode.zooming:
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
