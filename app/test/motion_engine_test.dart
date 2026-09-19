import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:helm/core/input_event.dart';
import 'package:helm/motion/motion_config.dart';
import 'package:helm/motion/motion_engine.dart';
import 'package:helm/motion/motion_sample.dart';

/// A 100 Hz sample stream. Defaults to a phone lying face-up and still:
/// the accelerometer reads +Z (specific force points up), gyro is zero.
/// [ms] is the span covered; the first sample carries dt = 0.
List<MotionSample> stream({
  double gx = 0,
  double gy = 0,
  double gz = 0,
  double ax = 0,
  double ay = 0,
  double az = 9.81,
  int ms = 1000,
  int startMs = 0,
}) =>
    [
      for (var t = 0; t <= ms; t += 10)
        MotionSample(
          gyroX: gx,
          gyroY: gy,
          gyroZ: gz,
          accelX: ax,
          accelY: ay,
          accelZ: az,
          timestamp: Duration(milliseconds: startMs + t),
        ),
    ];

int sumDx(List<InputEvent> events) =>
    events.whereType<PointerMove>().fold(0, (a, e) => a + e.dx);
int sumDy(List<InputEvent> events) =>
    events.whereType<PointerMove>().fold(0, (a, e) => a + e.dy);

void main() {
  group('relative gliding', () {
    test('deterministic: same input, same output', () {
      final samples = stream(gz: -0.8, gx: 0.3);
      expect(MotionEngine().processAll(samples),
          MotionEngine().processAll(samples));
    });

    test('sweep right → cursor right, no vertical motion', () {
      final events = MotionEngine().processAll(stream(gz: -1.0, ms: 500));
      // 1 rad/s × 0.5 s × 2400 counts/rad
      expect(sumDx(events), closeTo(1200, 3));
      expect(sumDy(events), 0);
    });

    test('sweep left → cursor left', () {
      final events = MotionEngine().processAll(stream(gz: 1.0, ms: 500));
      expect(sumDx(events), closeTo(-1200, 3));
    });

    test('tip up → cursor up (negative dy), no horizontal motion', () {
      final events = MotionEngine().processAll(stream(gx: 1.0, ms: 500));
      expect(sumDy(events), closeTo(-1200, 3));
      expect(sumDx(events), 0);
    });

    test('pointerGain scales the output', () {
      final events = MotionEngine(config: const MotionConfig(pointerGain: 0.5))
          .processAll(stream(gz: -1.0, ms: 500));
      expect(sumDx(events), closeTo(600, 3));
    });

    test('roll about the pointing axis does not change the mapping', () {
      // Roll 45° about device +Y: world-up in the device frame becomes
      // (s, 0, c). A world sweep of ω about up reads as ω·up on the gyro.
      final s = math.sin(math.pi / 4), c = math.cos(math.pi / 4);
      final flatSweep = MotionEngine().processAll(stream(gz: -1.0, ms: 500));
      final rolledSweep = MotionEngine().processAll(
        stream(gx: -s, gz: -c, ax: 9.81 * s, az: 9.81 * c, ms: 500),
      );
      expect(sumDx(rolledSweep), closeTo(sumDx(flatSweep), 3));
      expect(sumDy(rolledSweep), closeTo(0, 3));

      // Tip-up about the rolled horizontal axis r = (c, 0, -s).
      final flatTilt = MotionEngine().processAll(stream(gx: 1.0, ms: 500));
      final rolledTilt = MotionEngine().processAll(
        stream(gx: c, gz: -s, ax: 9.81 * s, az: 9.81 * c, ms: 500),
      );
      expect(sumDy(rolledTilt), closeTo(sumDy(flatTilt), 3));
      expect(sumDx(rolledTilt), closeTo(0, 3));
    });

    test('a still device emits nothing over 5 seconds', () {
      final events = MotionEngine().processAll(
        stream(gx: 0.004, gy: -0.003, gz: 0.005, ms: 5000),
      );
      expect(events, isEmpty);
    });

    test('a steady gyro bias is learned away instead of creeping', () {
      final engine = MotionEngine();
      final warmup = engine.processAll(stream(gz: 0.03, ms: 15000));
      expect(warmup, isNotEmpty, reason: 'bias not yet learned at first');
      final settled = engine.processAll(stream(gz: 0.03, ms: 5000, startMs: 15010));
      expect(settled, isEmpty);
    });

    test('sub-unit motion accumulates through the remainder carry', () {
      const config = MotionConfig(countsPerRadian: 40);
      final events = MotionEngine(config: config)
          .processAll(stream(gz: -1.0, ms: 1000));
      // 0.4 counts per sample: individual events are 1 count, never lost.
      expect(events.every((e) => e is PointerMove && e.dx.abs() <= 1), isTrue);
      expect(sumDx(events), inInclusiveRange(39, 40));
    });

    test('near-vertical pointing keeps a stable horizontal axis', () {
      // Phone pointing straight up: cross(p, up) vanishes, so the previous
      // axis is reused. Tip motion must stay purely vertical and steady.
      final events = MotionEngine().processAll(
        stream(gx: 1.0, ay: 9.81, az: 0, ms: 300),
      );
      expect(events.every((e) => e is PointerMove && e.dx == 0 && e.dy <= 0),
          isTrue);
      expect(sumDy(events), closeTo(-720, 3)); // 1 rad/s × 0.3 s × 2400
    });

    test('a stalled sensor stream does not integrate the gap', () {
      final engine = MotionEngine();
      engine.processAll(stream(ms: 100));
      // One sample after a 5 s stall, then the phone is still. dt clamps to
      // 0.1 s (240 counts), and the output cap (127) must not leave a
      // backlog leaking out afterwards.
      final stall = engine.processAll(stream(gz: -1.0, ms: 0, startMs: 5000));
      final after = engine.processAll(stream(ms: 2000, startMs: 5010));
      expect(sumDx(stall).abs(), lessThanOrEqualTo(127));
      expect(after, isEmpty);
    });

    test('a fast flick that saturates the report cap leaves no backlog', () {
      // 6 rad/s asks for 144 counts per 10 ms sample, above the ±127 cap.
      final engine = MotionEngine();
      engine.processAll(stream(ms: 100));
      final flick = engine.processAll(stream(gz: -6.0, ms: 1000, startMs: 110));
      expect(flick, isNotEmpty);
      // The instant the phone stops, the cursor stops.
      final after = engine.processAll(stream(ms: 2000, startMs: 1120));
      expect(after, isEmpty);
    });

    test('a non-finite sample is ignored and does not brick the engine', () {
      final engine = MotionEngine();
      engine.processAll(stream(ms: 100));
      final bad = MotionSample(
        gyroX: double.nan,
        gyroY: 0,
        gyroZ: 0,
        accelX: 0,
        accelY: 0,
        accelZ: 9.81,
        timestamp: const Duration(milliseconds: 110),
      );
      expect(() => engine.handleSample(bad), returnsNormally);
      final events = engine.processAll(stream(gz: -1.0, ms: 500, startMs: 120));
      // 500 ms of sweep, plus the 20 ms back to the last *good* sample.
      expect(sumDx(events), closeTo(1248, 5));
    });

    test('a gyro bias above the stillness threshold is still learned away',
        () {
      final engine = MotionEngine();
      engine.processAll(stream(gz: 0.08, ms: 25000));
      expect(engine.processAll(stream(gz: 0.08, ms: 5000, startMs: 25010)),
          isEmpty);
    });
  });

  group('spotlight (absolute)', () {
    test('begin lands the pointer at dead centre', () {
      final engine = MotionEngine()..processAll(stream(ms: 100));
      expect(engine.beginSpotlight(), [const PointerAbsolute(0.5, 0.5)]);
    });

    test('sweeping right moves x above centre, left below', () {
      final right = MotionEngine()..processAll(stream(ms: 100));
      right.beginSpotlight();
      final rightEvents =
          right.processAll(stream(gz: -0.3, ms: 500, startMs: 110));
      expect((rightEvents.last as PointerAbsolute).x, greaterThan(0.5));

      final left = MotionEngine()..processAll(stream(ms: 100));
      left.beginSpotlight();
      final leftEvents =
          left.processAll(stream(gz: 0.3, ms: 500, startMs: 110));
      expect((leftEvents.last as PointerAbsolute).x, lessThan(0.5));
    });

    test('x is proportional to yaw over the field of view', () {
      final engine = MotionEngine()..processAll(stream(ms: 100));
      engine.beginSpotlight();
      // Yaw right by fieldOfView/4 → a quarter of the width right of centre.
      const fov = 0.70;
      final events = engine.processAll(
        stream(gz: -(fov / 4) / 0.5, ms: 500, startMs: 110),
      );
      expect((events.last as PointerAbsolute).x, closeTo(0.75, 0.02));
    });

    test('positions clamp to 0…1 and never overrun the screen', () {
      final engine = MotionEngine()..processAll(stream(ms: 100));
      engine.beginSpotlight();
      final events = engine.processAll(stream(gz: 1.0, ms: 1500, startMs: 110));
      final positions = events.whereType<PointerAbsolute>().toList();
      expect(positions.every((p) => p.x >= 0 && p.x <= 1), isTrue);
      expect(positions.every((p) => p.y >= 0 && p.y <= 1), isTrue);
      expect(positions.last.x, 0.0);
    });

    test('sweeping past the screen edge does not wind up; coming back responds '
        'immediately', () {
      final engine = MotionEngine()..processAll(stream(ms: 100));
      engine.beginSpotlight();
      // Sweep left far beyond the field of view (1 rad vs ±0.35 rad edge)…
      engine.processAll(stream(gz: 1.0, ms: 1000, startMs: 110));
      // …then back right by only 0.09 rad. The pointer must leave the edge.
      final back = engine.processAll(stream(gz: -0.3, ms: 300, startMs: 1120));
      final positions = back.whereType<PointerAbsolute>().toList();
      expect(positions, isNotEmpty);
      expect(positions.last.x, greaterThan(0.05));
    });

    test('pressing Spotlight before any sample does not teleport the pointer',
        () {
      final engine = MotionEngine();
      expect(engine.beginSpotlight(), isEmpty); // nothing to reference yet
      // First samples arrive with the phone already tilted 30° up.
      final tilt = 30 * math.pi / 180;
      final events = engine.processAll(
        stream(ay: 9.81 * math.sin(tilt), az: 9.81 * math.cos(tilt), ms: 500),
      );
      final positions = events.whereType<PointerAbsolute>().toList();
      expect(positions.first, const PointerAbsolute(0.5, 0.5));
      expect(
        positions.every((p) => (p.x - 0.5).abs() < 0.05 && (p.y - 0.5).abs() < 0.05),
        isTrue,
      );
    });

    test('the same holds after a reset (app resumed from the background)', () {
      final engine = MotionEngine()..processAll(stream(ms: 100));
      engine.reset();
      expect(engine.beginSpotlight(), isEmpty);
      final tilt = 30 * math.pi / 180;
      final events = engine.processAll(
        stream(ay: 9.81 * math.sin(tilt), az: 9.81 * math.cos(tilt), ms: 300),
      );
      expect(events.whereType<PointerAbsolute>().first,
          const PointerAbsolute(0.5, 0.5));
    });

    test('pitch comes from gravity: a held tilt gives a stable y', () {
      final engine = MotionEngine()..processAll(stream(ms: 100));
      engine.beginSpotlight();
      // Tip raised 10° with zero gyro — only gravity can say so.
      final tilt = 10 * math.pi / 180;
      final ay = 9.81 * math.sin(tilt), az = 9.81 * math.cos(tilt);
      final settle = engine.processAll(stream(ay: ay, az: az, ms: 10000, startMs: 110));
      final y = (settle.last as PointerAbsolute).y;
      const fovY = 0.70 / (16 / 9);
      expect(y, closeTo(0.5 - tilt / fovY, 0.02));
      expect(y, lessThan(0.5));
      // Converged: nothing more to say.
      expect(engine.processAll(stream(ay: ay, az: az, ms: 1000, startMs: 10120)),
          isEmpty);
    });

    test('a still device holds its position without emitting', () {
      final engine = MotionEngine()..processAll(stream(ms: 100));
      engine.beginSpotlight();
      expect(engine.processAll(stream(ms: 3000, startMs: 110)), isEmpty);
    });

    test('near-vertical pointing yields finite positions', () {
      final engine = MotionEngine()
        ..processAll(stream(ay: 9.81, az: 0, ms: 100));
      engine.beginSpotlight();
      final events = engine.processAll(
        stream(gz: 0.4, ay: 9.81, az: 0, ms: 300, startMs: 110),
      );
      for (final p in events.whereType<PointerAbsolute>()) {
        expect(p.x.isFinite && p.y.isFinite, isTrue);
      }
    });

    test('end resumes relative gliding from where the pointer is', () {
      final engine = MotionEngine()..processAll(stream(ms: 100));
      engine.beginSpotlight();
      engine.processAll(stream(gz: -0.3, ms: 300, startMs: 110));
      expect(engine.endSpotlight(), isEmpty);
      final glide = engine.processAll(stream(gz: -1.0, ms: 300, startMs: 420));
      expect(glide.whereType<PointerAbsolute>(), isEmpty);
      expect(sumDx(glide), greaterThan(0));
    });
  });

  group('spotlight without absolute support (precision)', () {
    test('begin emits no absolute position', () {
      final engine = MotionEngine(absoluteSpotlight: false)
        ..processAll(stream(ms: 100));
      expect(engine.beginSpotlight(), isEmpty);
    });

    test('never emits PointerAbsolute, and glides at reduced gain', () {
      final normal = MotionEngine()..processAll(stream(ms: 100));
      final normalEvents =
          normal.processAll(stream(gz: -1.0, ms: 500, startMs: 110));

      final engine = MotionEngine(absoluteSpotlight: false)
        ..processAll(stream(ms: 100));
      engine.beginSpotlight();
      final events = engine.processAll(stream(gz: -1.0, ms: 500, startMs: 110));

      expect(events.whereType<PointerAbsolute>(), isEmpty);
      expect(sumDx(events),
          closeTo(sumDx(normalEvents) * MotionEngine.precisionGainScale, 4));
    });
  });

  group('click and reset', () {
    test('click emits button edges once per change', () {
      final engine = MotionEngine();
      expect(engine.click(down: true),
          [const ButtonEvent(Button.left, down: true)]);
      expect(engine.click(down: true), isEmpty);
      expect(engine.click(down: false),
          [const ButtonEvent(Button.left, down: false)]);
    });

    test('reset mid-click releases the button', () {
      final engine = MotionEngine()..click(down: true);
      expect(engine.reset(), [const ButtonEvent(Button.left, down: false)]);
      expect(engine.reset(), isEmpty);
    });

    test('reset mid-spotlight forgets the reference', () {
      final engine = MotionEngine()..processAll(stream(ms: 100));
      engine.beginSpotlight();
      engine.reset();
      expect(engine.spotlightActive, isFalse);
      // A fresh spotlight after reset lands at centre again.
      engine.processAll(stream(ms: 100));
      expect(engine.beginSpotlight(), [const PointerAbsolute(0.5, 0.5)]);
    });
  });

  group('MotionConfig', () {
    test('has value equality so identical rebuilds do not reset the engine', () {
      expect(const MotionConfig(), const MotionConfig());
      expect(const MotionConfig().hashCode, const MotionConfig().hashCode);
      expect(const MotionConfig(pointerGain: 1.5), isNot(const MotionConfig()));
      expect(const MotionConfig().copyWith(pointerGain: 1.5),
          const MotionConfig(pointerGain: 1.5));
    });
  });
}
