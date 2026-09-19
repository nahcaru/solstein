import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:helm/core/input_event.dart';
import 'package:helm/motion/motion_config.dart';
import 'package:helm/motion/motion_engine.dart';
import 'package:helm/motion/motion_sample.dart';

/// A sample stream (100 Hz by default). Defaults to a phone lying face-up and
/// still: the accelerometer reads +Z (specific force points up), gyro is
/// zero. [ms] is the span covered; the first sample carries dt = 0.
List<MotionSample> stream({
  double gx = 0,
  double gy = 0,
  double gz = 0,
  double ax = 0,
  double ay = 0,
  double az = 9.81,
  int ms = 1000,
  int startMs = 0,
  int stepMs = 10,
}) =>
    [
      for (var t = 0; t <= ms; t += stepMs)
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

/// A yaw rate that oscillates: gz = amp·sin(2π·hz·t).
List<MotionSample> wave({
  required double hz,
  required double amp,
  int ms = 2000,
  int startMs = 0,
}) =>
    [
      for (var t = 0; t <= ms; t += 10)
        MotionSample(
          gyroX: 0,
          gyroY: 0,
          gyroZ: amp * math.sin(2 * math.pi * hz * t / 1000),
          accelX: 0,
          accelY: 0,
          accelZ: 9.81,
          timestamp: Duration(milliseconds: startMs + t),
        ),
    ];

/// Smoothing effectively off, so a test sees the ballistics curve alone.
const rawConfig = MotionConfig(smoothingMinCutoffHz: 1e6, smoothingBeta: 0);

MotionEngine engaged({MotionConfig config = const MotionConfig()}) =>
    MotionEngine(config: config)..engage();

int sumDx(List<InputEvent> events) =>
    events.whereType<PointerMove>().fold(0, (a, e) => a + e.dx);
int sumDy(List<InputEvent> events) =>
    events.whereType<PointerMove>().fold(0, (a, e) => a + e.dy);
int travel(List<InputEvent> events) => events
    .whereType<PointerMove>()
    .fold(0, (a, e) => a + e.dx.abs() + e.dy.abs());

void main() {
  group('clutch', () {
    test('disengaged: sweeping the phone moves nothing', () {
      final engine = MotionEngine();
      expect(engine.engaged, isFalse);
      expect(engine.processAll(stream(gz: -1.0, gx: 0.8, ms: 1000)), isEmpty);
    });

    test('engaged: sweeping moves the cursor; disengaged again: it freezes',
        () {
      final engine = MotionEngine()..processAll(stream(ms: 100));
      engine.engage();
      expect(engine.engaged, isTrue);
      expect(engine.processAll(stream(gz: -1.0, ms: 300, startMs: 110)),
          isNotEmpty);
      engine.disengage();
      expect(engine.engaged, isFalse);
      expect(engine.processAll(stream(gz: -1.0, ms: 500, startMs: 420)),
          isEmpty);
    });

    test('motion made while released does not burst out on engage', () {
      final engine = MotionEngine();
      engine.processAll(stream(gz: -3.0, ms: 1000)); // waving around, released
      engine.engage();
      // Held still the moment the clutch closes: nothing to say.
      expect(engine.processAll(stream(ms: 1000, startMs: 1010)), isEmpty);
    });

    test('engage and disengage are idempotent', () {
      final engine = MotionEngine();
      expect(engine.engage(), isEmpty);
      expect(engine.engage(), isEmpty);
      expect(engine.disengage(), isEmpty);
      expect(engine.disengage(), isEmpty);
      expect(engine.engaged, isFalse);
    });
  });

  group('gliding', () {
    test('deterministic: same input, same output', () {
      final samples = stream(gz: -0.8, gx: 0.3);
      expect(engaged().processAll(samples), engaged().processAll(samples));
    });

    test('sweep right → cursor right, no vertical motion', () {
      final events = engaged().processAll(stream(gz: -1.0, ms: 500));
      // 1 rad/s is the ballistics reference: 1 rad/s × 0.5 s × 2400 counts/rad
      expect(sumDx(events), closeTo(1200, 3));
      expect(sumDy(events), 0);
    });

    test('sweep left → cursor left', () {
      final events = engaged().processAll(stream(gz: 1.0, ms: 500));
      expect(sumDx(events), closeTo(-1200, 3));
    });

    test('tip up → cursor up (negative dy), no horizontal motion', () {
      final events = engaged().processAll(stream(gx: 1.0, ms: 500));
      expect(sumDy(events), closeTo(-1200, 3));
      expect(sumDx(events), 0);
    });

    test('pointerGain scales the output', () {
      final events = engaged(config: const MotionConfig(pointerGain: 0.5))
          .processAll(stream(gz: -1.0, ms: 500));
      expect(sumDx(events), closeTo(600, 3));
    });

    test('roll about the pointing axis does not change the mapping', () {
      // Roll 45° about device +Y: world-up in the device frame becomes
      // (s, 0, c). A world sweep of ω about up reads as ω·up on the gyro.
      final s = math.sin(math.pi / 4), c = math.cos(math.pi / 4);
      final flatSweep = engaged().processAll(stream(gz: -1.0, ms: 500));
      final rolledSweep = engaged().processAll(
        stream(gx: -s, gz: -c, ax: 9.81 * s, az: 9.81 * c, ms: 500),
      );
      expect(sumDx(rolledSweep), closeTo(sumDx(flatSweep), 3));
      expect(sumDy(rolledSweep), closeTo(0, 3));

      // Tip-up about the rolled horizontal axis r = (c, 0, -s).
      final flatTilt = engaged().processAll(stream(gx: 1.0, ms: 500));
      final rolledTilt = engaged().processAll(
        stream(gx: c, gz: -s, ax: 9.81 * s, az: 9.81 * c, ms: 500),
      );
      expect(sumDy(rolledTilt), closeTo(sumDy(flatTilt), 3));
      expect(sumDx(rolledTilt), closeTo(0, 3));
    });

    test('an engaged still device emits nothing over 5 seconds', () {
      final events = engaged().processAll(
        stream(gx: 0.004, gy: -0.003, gz: 0.005, ms: 5000),
      );
      expect(events, isEmpty);
    });

    test('sub-unit motion accumulates through the remainder carry', () {
      final events = engaged(config: const MotionConfig(countsPerRadian: 40))
          .processAll(stream(gz: -1.0, ms: 1000));
      // 0.4 counts per sample: individual events are 1 count, never lost.
      expect(events.every((e) => e is PointerMove && e.dx.abs() <= 1), isTrue);
      expect(sumDx(events), inInclusiveRange(39, 40));
    });

    test('near-vertical pointing keeps a stable horizontal axis', () {
      // Phone pointing straight up: cross(p, up) vanishes, so the previous
      // axis is reused. Tip motion must stay purely vertical and steady.
      final events = engaged().processAll(
        stream(gx: 1.0, ay: 9.81, az: 0, ms: 300),
      );
      expect(events.every((e) => e is PointerMove && e.dx == 0 && e.dy <= 0),
          isTrue);
      expect(sumDy(events), closeTo(-720, 3)); // 1 rad/s × 0.3 s × 2400
    });

    test('a stalled sensor stream does not integrate the gap', () {
      final engine = engaged();
      engine.processAll(stream(ms: 100));
      // One sample after a 5 s stall, then the phone is still. dt clamps to
      // 0.1 s, and the output cap must not leave a backlog leaking out.
      final stall = engine.processAll(stream(gz: -1.0, ms: 0, startMs: 5000));
      final after = engine.processAll(stream(ms: 2000, startMs: 5010));
      expect(sumDx(stall) + sumDx(after), lessThanOrEqualTo(240));
      expect(engine.processAll(stream(ms: 1000, startMs: 7020)), isEmpty);
    });

    test('a fast flick that saturates the report cap leaves no backlog', () {
      // ω = 6 rad/s asks for far more than the ±127 cap per 10 ms sample.
      final engine = engaged();
      engine.processAll(stream(ms: 100));
      final flick = engine.processAll(stream(gz: -6.0, ms: 1000, startMs: 110));
      expect(flick.whereType<PointerMove>().any((e) => e.dx == 127), isTrue,
          reason: 'the flick must actually saturate the cap');
      // The smoothing tail is over within 0.3 s; after that, nothing.
      engine.processAll(stream(ms: 300, startMs: 1120));
      expect(engine.processAll(stream(ms: 2000, startMs: 1430)), isEmpty);
    });

    test('a non-finite sample is ignored as if it never happened', () {
      final bad = MotionSample(
        gyroX: double.nan,
        gyroY: 0,
        gyroZ: 0,
        accelX: 0,
        accelY: 0,
        accelZ: 9.81,
        timestamp: const Duration(milliseconds: 110),
      );
      List<InputEvent> run({required bool withBad}) {
        final engine = engaged();
        engine.processAll(stream(ms: 100));
        if (withBad) expect(() => engine.handleSample(bad), returnsNormally);
        return engine.processAll(stream(gz: -1.0, ms: 500, startMs: 120));
      }

      expect(run(withBad: true), run(withBad: false));
    });
  });

  group('gyro bias', () {
    test('a steady bias is learned away while the clutch is released', () {
      final engine = MotionEngine();
      engine.processAll(stream(gz: 0.03, ms: 15000)); // resting in a hand
      engine.engage();
      expect(engine.processAll(stream(gz: 0.03, ms: 5000, startMs: 15010)),
          isEmpty);
    });

    test('a bias above the stillness threshold is still learned', () {
      final engine = MotionEngine();
      engine.processAll(stream(gz: 0.08, ms: 25000));
      engine.engage();
      expect(engine.processAll(stream(gz: 0.08, ms: 5000, startMs: 25010)),
          isEmpty);
    });

    test('nothing is learned while engaged: a bias keeps creeping', () {
      final engine = engaged();
      final first = engine.processAll(stream(gz: 0.08, ms: 10000));
      final later =
          engine.processAll(stream(gz: 0.08, ms: 5000, startMs: 10010));
      expect(first, isNotEmpty);
      expect(later, isNotEmpty,
          reason: 'deliberate slow motion is never absorbed');
    });

    test('recalibrate relearns a large bias within its duration', () {
      final engine = MotionEngine();
      engine.processAll(stream(gz: 0.3, ms: 200));
      engine.recalibrate();
      expect(engine.calibrating, isTrue);
      engine.processAll(stream(gz: 0.3, ms: 2100, startMs: 210));
      expect(engine.calibrating, isFalse);
      expect(engine.gyroBias.z, closeTo(0.3, 0.01));
      engine.engage();
      expect(engine.processAll(stream(gz: 0.3, ms: 2000, startMs: 2320)),
          isEmpty);
    });

    test('recalibrate skips samples that are obviously not still', () {
      final engine = MotionEngine();
      engine.processAll(stream(ms: 100));
      engine.recalibrate();
      engine.processAll(stream(gz: 3.0, ms: 1000, startMs: 110)); // shaking
      expect(engine.gyroBias.z.abs(), lessThan(0.01));
    });
  });

  group('ballistics', () {
    test('exponent 1 is the old linear response', () {
      final events =
          engaged(config: rawConfig.copyWith(ballisticsExponent: 1.0))
              .processAll(stream(gz: -3.0, ms: 500));
      expect(sumDx(events), closeTo(3 * 0.5 * 2400, 3600 * 0.03));
    });

    test('slow motion gets finer, fast motion reaches further', () {
      int total(double omega) => sumDx(
          engaged(config: rawConfig).processAll(stream(gz: -omega, ms: 1000)));
      final slow = total(0.25), reference = total(1.0), fast = total(3.0);
      // Displacement per radian of rotation grows with speed.
      expect(slow / 0.25, lessThan(reference / 1.0));
      expect(fast / 3.0, greaterThan(reference / 1.0));
    });

    test('follows |ω|^p with unit gain at the reference speed', () {
      for (final omega in [0.25, 1.0, 3.0]) {
        final expected = math.pow(omega, 1.4) * 2400; // 1 s
        final actual = sumDx(engaged(config: rawConfig)
            .processAll(stream(gz: -omega, ms: 1000)));
        expect(actual, closeTo(expected, expected * 0.03),
            reason: '$omega rad/s');
      }
    });

    test('has unit gain at whatever the reference speed is set to', () {
      // At the default reference (1 rad/s) normalizing is invisible, so use a
      // different one: at exactly the reference, output must be linear.
      final config = rawConfig.copyWith(ballisticsRefRadPerSec: 2.0);
      final atRef =
          sumDx(engaged(config: config).processAll(stream(gz: -2.0, ms: 1000)));
      expect(atRef, closeTo(2.0 * 1.0 * 2400, 2.0 * 2400 * 0.03));
    });

    test('does not depend on the sampling rate', () {
      int at(int stepMs) => sumDx(engaged(config: rawConfig)
          .processAll(stream(gz: -2.0, ms: 1000, stepMs: stepMs)));
      expect(at(10), closeTo(at(20), at(20) * 0.03));
    });

    test('motion below the deadzone is ignored', () {
      expect(
        engaged(config: rawConfig).processAll(stream(gz: -0.005, ms: 2000)),
        isEmpty,
      );
    });
  });

  group('tremor smoothing', () {
    // A 9 Hz, ±0.2 rad/s shake is well inside the 4–12 Hz tremor band.
    final tremor = wave(hz: 9, amp: 0.2, ms: 3000);

    test('a hand tremor is strongly attenuated', () {
      final smoothed = travel(engaged().processAll(tremor));
      final raw = travel(engaged(config: rawConfig).processAll(tremor));
      // Measured: ≈370 counts raw, ≈11 smoothed (3%), across 6–12 Hz.
      expect(raw, greaterThan(200), reason: 'the tremor must be visible raw');
      expect(smoothed, lessThan(raw * 0.1));
    });

    test('a deliberate slow sweep still gets through', () {
      // 0.5 Hz, ±1 rad/s: a real sweep. Filtering may lag but not eat it.
      final sweep = wave(hz: 0.5, amp: 1.0, ms: 4000);
      final smoothed = travel(engaged().processAll(sweep));
      final raw = travel(engaged(config: rawConfig).processAll(sweep));
      expect(smoothed, greaterThan(raw * 0.9));
    });

    test('a fast flick follows with little lag', () {
      // 6 rad/s for 0.3 s: the filter must open up rather than smear it.
      final fast = engaged().processAll(stream(gz: -6.0, ms: 300));
      final raw =
          engaged(config: rawConfig).processAll(stream(gz: -6.0, ms: 300));
      expect(sumDx(fast), greaterThan(sumDx(raw) * 0.8));
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

    test('reset releases the clutch and forgets the learned bias', () {
      final engine = MotionEngine();
      engine.processAll(stream(gz: 0.03, ms: 15000));
      expect(engine.gyroBias.z, greaterThan(0.01));
      engine.engage();
      engine.reset();
      expect(engine.engaged, isFalse);
      expect(engine.gyroBias.z, 0);
    });
  });

  group('MotionConfig', () {
    test('has value equality so identical rebuilds do not reset the engine',
        () {
      expect(const MotionConfig(), const MotionConfig());
      expect(const MotionConfig().hashCode, const MotionConfig().hashCode);
      expect(const MotionConfig(pointerGain: 1.5), isNot(const MotionConfig()));
      expect(const MotionConfig().copyWith(pointerGain: 1.5),
          const MotionConfig(pointerGain: 1.5));
    });
  });
}
