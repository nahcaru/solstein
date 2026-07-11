import 'package:flutter_test/flutter_test.dart';
import 'package:helm/core/input_event.dart';
import 'package:helm/engine/gesture_config.dart';
import 'package:helm/engine/gesture_engine.dart';
import 'package:helm/engine/pointer_sample.dart';

PointerSample s(int id, SamplePhase phase, double x, double y, int ms) =>
    PointerSample(
      pointerId: id,
      phase: phase,
      x: x,
      y: y,
      timestamp: Duration(milliseconds: ms),
    );

void main() {
  group('one finger', () {
    test('quick still tap → left click down+up', () {
      final engine = GestureEngine();
      final events = engine.processAll([
        s(1, SamplePhase.down, 100, 100, 0),
        s(1, SamplePhase.up, 101, 100, 100),
      ]);
      expect(events, const [
        ButtonEvent(Button.left, down: true),
        ButtonEvent(Button.left, down: false),
      ]);
    });

    test('lift after tap timeout is not a tap', () {
      final engine = GestureEngine();
      final events = engine.processAll([
        s(1, SamplePhase.down, 100, 100, 0),
        s(1, SamplePhase.up, 100, 100, 400),
      ]);
      expect(events, isEmpty);
    });

    test('sub-slop jitter then lift within timeout still taps', () {
      final engine = GestureEngine();
      final events = engine.processAll([
        s(1, SamplePhase.down, 100, 100, 0),
        s(1, SamplePhase.move, 103, 102, 50),
        s(1, SamplePhase.up, 103, 102, 120),
      ]);
      expect(events.whereType<ButtonEvent>().length, 2);
      expect(events.whereType<PointerMove>(), isEmpty);
    });

    test('move beyond slop → linear, distance-proportional pointer motion',
        () {
      final engine = GestureEngine();
      final events = engine.processAll([
        s(1, SamplePhase.down, 100, 100, 0),
        s(1, SamplePhase.move, 110, 100, 20), // 10 px → 10 counts, 1:1
        s(1, SamplePhase.up, 110, 100, 500),
      ]);
      expect(events, const [PointerMove(10, 0)]);
    });

    test('same distance yields same output regardless of sample rate', () {
      // 16 px in one sample vs. 16 px in eight samples must move equally —
      // distance-proportional, not velocity-proportional.
      final burst = GestureEngine().processAll([
        s(1, SamplePhase.down, 100, 100, 0),
        s(1, SamplePhase.move, 116, 100, 10),
      ]);
      final gradual = GestureEngine().processAll([
        s(1, SamplePhase.down, 100, 100, 0),
        s(1, SamplePhase.move, 110, 100, 10), // clears slop
        for (var i = 1; i <= 3; i++)
          s(1, SamplePhase.move, 110 + i * 2.0, 100, 10 + i * 30),
      ]);
      int total(List<InputEvent> events) => events
          .whereType<PointerMove>()
          .fold<int>(0, (sum, e) => sum + e.dx);
      expect(total(burst), 16);
      expect(total(gradual), 16);
    });

    test('slow sub-unit motion accumulates instead of vanishing', () {
      final engine = GestureEngine();
      final samples = [
        s(1, SamplePhase.down, 100, 100, 0),
        s(1, SamplePhase.move, 110, 100, 10), // enter pointing (10 px burst)
        for (var i = 1; i <= 8; i++)
          s(1, SamplePhase.move, 110 + i * 0.5, 100, 10 + i * 10),
      ];
      final events = engine.processAll(samples);
      final total = events
          .whereType<PointerMove>()
          .fold<int>(0, (sum, e) => sum + e.dx);
      expect(total, 14); // 10 px burst + 8 × 0.5 px, nothing lost
    });

    test('per-report deltas clamp to ±127', () {
      final engine = GestureEngine();
      final events = engine.processAll([
        s(1, SamplePhase.down, 0, 0, 0),
        s(1, SamplePhase.move, 500, 0, 10), // 500^1.4 is way past 127
      ]);
      final move = events.whereType<PointerMove>().single;
      expect(move.dx, 127);
    });

    test('long-press then move → drag with held button', () {
      final engine = GestureEngine();
      final events = engine.processAll([
        s(1, SamplePhase.down, 100, 100, 0),
        s(1, SamplePhase.move, 110, 100, 350), // past longPressTimeout
        s(1, SamplePhase.move, 120, 100, 370),
        s(1, SamplePhase.up, 120, 100, 400),
      ]);
      expect(events.first, const ButtonEvent(Button.left, down: true));
      expect(events.last, const ButtonEvent(Button.left, down: false));
      expect(events.whereType<PointerMove>(), isNotEmpty);
    });
  });

  group('two fingers', () {
    test('quick two-finger tap → right click', () {
      final engine = GestureEngine();
      final events = engine.processAll([
        s(1, SamplePhase.down, 100, 100, 0),
        s(2, SamplePhase.down, 130, 100, 10),
        s(1, SamplePhase.up, 100, 100, 100),
        s(2, SamplePhase.up, 130, 100, 110),
      ]);
      expect(events, const [
        ButtonEvent(Button.right, down: true),
        ButtonEvent(Button.right, down: false),
      ]);
    });

    test('vertical movement → scroll ticks (natural: fingers down, wheel −)',
        () {
      final engine = GestureEngine();
      final events = engine.processAll([
        s(1, SamplePhase.down, 100, 100, 0),
        s(2, SamplePhase.down, 130, 100, 0),
        s(1, SamplePhase.move, 100, 116, 50), // 16 px / 16 px-per-tick = 1
        s(1, SamplePhase.up, 100, 116, 200),
        s(2, SamplePhase.up, 130, 100, 210),
      ]);
      expect(events, const [Scroll(0, -1)]);
    });

    test('horizontal movement → horizontal ticks (natural sign)', () {
      final engine = GestureEngine();
      final events = engine.processAll([
        s(1, SamplePhase.down, 100, 100, 0),
        s(2, SamplePhase.down, 100, 130, 0),
        s(1, SamplePhase.move, 84, 100, 50), // 16 px left
        s(1, SamplePhase.up, 84, 100, 200),
        s(2, SamplePhase.up, 100, 130, 210),
      ]);
      // Pan axis is inverted relative to wheel: fingers left → negative pan.
      expect(events, const [Scroll(-1, 0)]);
    });

    test('reverse scroll setting flips the sign on both axes', () {
      final engine =
          GestureEngine(config: const GestureConfig(naturalScroll: false));
      final events = engine.processAll([
        s(1, SamplePhase.down, 100, 100, 0),
        s(2, SamplePhase.down, 130, 100, 0),
        s(1, SamplePhase.move, 100, 116, 50),
        s(1, SamplePhase.move, 84, 116, 80),
      ]);
      expect(events, const [Scroll(0, 1), Scroll(1, 0)]);
    });

    test('scroll gain scales tick rate', () {
      final engine =
          GestureEngine(config: const GestureConfig(scrollGain: 2.0));
      final events = engine.processAll([
        s(1, SamplePhase.down, 100, 100, 0),
        s(2, SamplePhase.down, 130, 100, 0),
        s(1, SamplePhase.move, 100, 116, 50), // 16 px × 2.0 gain = 2 ticks
      ]);
      expect(events, const [Scroll(0, -2)]);
    });

    test('no click leaks after a scroll ends', () {
      final engine = GestureEngine();
      final events = engine.processAll([
        s(1, SamplePhase.down, 100, 100, 0),
        s(2, SamplePhase.down, 130, 100, 0),
        s(1, SamplePhase.move, 100, 130, 50),
        s(1, SamplePhase.up, 100, 130, 300),
        s(2, SamplePhase.up, 130, 100, 320),
      ]);
      expect(events.whereType<ButtonEvent>(), isEmpty);
    });
  });

  group('three-finger swipe', () {
    List<PointerSample> swipe({required double dx, required double dy}) => [
          s(1, SamplePhase.down, 100, 100, 0),
          s(2, SamplePhase.down, 120, 100, 0),
          s(3, SamplePhase.down, 140, 100, 0),
          // Each finger travels the full distance, one at a time; centroid
          // displacement grows in thirds.
          s(1, SamplePhase.move, 100 + dx, 100 + dy, 30),
          s(2, SamplePhase.move, 120 + dx, 100 + dy, 40),
          s(3, SamplePhase.move, 140 + dx, 100 + dy, 50),
          s(1, SamplePhase.up, 100 + dx, 100 + dy, 80),
          s(2, SamplePhase.up, 120 + dx, 100 + dy, 90),
          s(3, SamplePhase.up, 140 + dx, 100 + dy, 100),
        ];

    test('up-swipe streams began/changed/ended with rising progress', () {
      final engine = GestureEngine();
      final events = engine.processAll(swipe(dx: 0, dy: -48));
      final phases = events.whereType<GesturePhase>().toList();
      expect(phases.first.phase, GesturePhaseKind.began);
      expect(phases.first.kind, GestureKind.swipeUp);
      expect(phases.last.phase, GesturePhaseKind.ended);
      expect(phases.last.progress, 1.0);
      final progresses = phases.map((p) => p.progress).toList();
      expect(progresses, orderedEquals([...progresses]..sort()));
      expect(events.whereType<PointerMove>(), isEmpty);
      expect(events.whereType<ButtonEvent>(), isEmpty);
    });

    test('direction detection for all four swipes', () {
      GestureKind kindOf(double dx, double dy) {
        final events = GestureEngine().processAll(swipe(dx: dx, dy: dy));
        return events.whereType<GesturePhase>().first.kind;
      }

      expect(kindOf(0, -48), GestureKind.swipeUp);
      expect(kindOf(0, 48), GestureKind.swipeDown);
      expect(kindOf(-48, 0), GestureKind.swipeLeft);
      expect(kindOf(48, 0), GestureKind.swipeRight);
    });

    test('short swipe ends below half progress (transport will not fire)',
        () {
      final engine = GestureEngine();
      final events = engine.processAll(swipe(dx: 0, dy: -18));
      final ended = events
          .whereType<GesturePhase>()
          .lastWhere((p) => p.phase == GesturePhaseKind.ended);
      expect(ended.progress, lessThan(0.5));
    });

    test('full swipe ends at progress ≥ 0.5', () {
      final engine = GestureEngine();
      final events = engine.processAll(swipe(dx: 0, dy: -48));
      final ended = events
          .whereType<GesturePhase>()
          .lastWhere((p) => p.phase == GesturePhaseKind.ended);
      expect(ended.progress, greaterThanOrEqualTo(0.5));
    });

    test('fourth finger cancels the swipe', () {
      final engine = GestureEngine();
      final events = engine.processAll([
        s(1, SamplePhase.down, 100, 100, 0),
        s(2, SamplePhase.down, 120, 100, 0),
        s(3, SamplePhase.down, 140, 100, 0),
        s(1, SamplePhase.move, 100, 52, 30),
        s(2, SamplePhase.move, 120, 52, 40),
        s(4, SamplePhase.down, 160, 100, 50),
      ]);
      expect(events.whereType<GesturePhase>().last.phase,
          GesturePhaseKind.cancelled);
    });
  });

  group('lifecycle', () {
    test('reset during drag releases the button', () {
      final engine = GestureEngine();
      engine.processAll([
        s(1, SamplePhase.down, 100, 100, 0),
        s(1, SamplePhase.move, 110, 100, 350),
      ]);
      expect(engine.reset(), const [ButtonEvent(Button.left, down: false)]);
    });

    test('cancel sample during drag releases the button', () {
      final engine = GestureEngine();
      final events = engine.processAll([
        s(1, SamplePhase.down, 100, 100, 0),
        s(1, SamplePhase.move, 110, 100, 350),
        s(1, SamplePhase.cancel, 110, 100, 400),
      ]);
      expect(events.last, const ButtonEvent(Button.left, down: false));
    });

    test('engine is reusable after an episode', () {
      final engine = GestureEngine();
      final tap = [
        s(1, SamplePhase.down, 100, 100, 0),
        s(1, SamplePhase.up, 100, 100, 100),
      ];
      expect(engine.processAll(tap).length, 2);
      expect(engine.processAll(tap).length, 2);
    });

    test('deterministic: same input, same output', () {
      final input = [
        s(1, SamplePhase.down, 100, 100, 0),
        s(1, SamplePhase.move, 117, 93, 30),
        s(1, SamplePhase.move, 140, 81, 60),
        s(1, SamplePhase.up, 140, 81, 90),
      ];
      final a = GestureEngine().processAll(input).map((e) => e.toString());
      final b = GestureEngine().processAll(input).map((e) => e.toString());
      expect(a, b);
    });
  });
}
