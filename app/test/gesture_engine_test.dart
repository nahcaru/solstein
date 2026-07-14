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
        s(1, SamplePhase.move, 110, 100, 20), // 10 px × base 2.0 = 20 counts
        s(1, SamplePhase.up, 110, 100, 500),
      ]);
      expect(events, const [PointerMove(20, 0)]);
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
      expect(total(burst), 32); // 16 px × base 2.0
      expect(total(gradual), 32);
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
      expect(total, 28); // (10 px burst + 8 × 0.5 px) × base 2.0, nothing lost
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

    test('tap then touch-and-move → drag without long-press', () {
      final engine = GestureEngine();
      final events = engine.processAll([
        // Tap…
        s(1, SamplePhase.down, 100, 100, 0),
        s(1, SamplePhase.up, 100, 100, 80),
        // …touch again within tapDragTimeout and move immediately.
        s(2, SamplePhase.down, 100, 100, 200),
        s(2, SamplePhase.move, 120, 100, 230),
        s(2, SamplePhase.up, 120, 100, 300),
      ]);
      expect(events, const [
        ButtonEvent(Button.left, down: true), // tap click
        ButtonEvent(Button.left, down: false),
        ButtonEvent(Button.left, down: true), // drag begins
        PointerMove(40, 0),
        ButtonEvent(Button.left, down: false), // drag ends on lift
      ]);
    });

    test('touch after the tap-drag window points instead of dragging', () {
      final engine = GestureEngine();
      final events = engine.processAll([
        s(1, SamplePhase.down, 100, 100, 0),
        s(1, SamplePhase.up, 100, 100, 80),
        s(2, SamplePhase.down, 100, 100, 500), // 420 ms after the tap
        s(2, SamplePhase.move, 120, 100, 530),
        s(2, SamplePhase.up, 120, 100, 600),
      ]);
      expect(events.sublist(2), const [PointerMove(40, 0)]);
    });

    test('second finger disarms tap-drag', () {
      final engine = GestureEngine();
      final events = engine.processAll([
        s(1, SamplePhase.down, 100, 100, 0),
        s(1, SamplePhase.up, 100, 100, 80),
        // Two fingers land right after the tap and scroll.
        s(2, SamplePhase.down, 100, 100, 200),
        s(3, SamplePhase.down, 130, 100, 210),
        s(2, SamplePhase.move, 100, 132, 240),
      ]);
      expect(events.sublist(2), const [Scroll(0, -1)]);
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
        s(1, SamplePhase.move, 100, 132, 50), // 32 px / 32 px-per-tick = 1
        s(1, SamplePhase.up, 100, 132, 200),
        s(2, SamplePhase.up, 130, 100, 210),
      ]);
      expect(events, const [Scroll(0, -1)]);
    });

    test('horizontal movement → horizontal ticks (natural sign)', () {
      final engine = GestureEngine();
      final events = engine.processAll([
        s(1, SamplePhase.down, 100, 100, 0),
        s(2, SamplePhase.down, 100, 130, 0),
        s(1, SamplePhase.move, 68, 100, 300), // 32 px left, slow (no flick)
        s(1, SamplePhase.up, 68, 100, 400),
        s(2, SamplePhase.up, 100, 130, 410),
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
        s(1, SamplePhase.move, 100, 132, 200),
        s(1, SamplePhase.move, 68, 132, 500),
      ]);
      expect(events, const [Scroll(0, 1), Scroll(1, 0)]);
    });

    test('Windows/Linux (no host inversion) flip both axes vs macOS', () {
      final engine = GestureEngine(
          config: const GestureConfig(hostInvertsScroll: false));
      final events = engine.processAll([
        s(1, SamplePhase.down, 100, 100, 0),
        s(2, SamplePhase.down, 130, 100, 0),
        s(1, SamplePhase.move, 100, 132, 200), // fingers down
        s(1, SamplePhase.move, 68, 132, 500), // fingers left
      ]);
      // Natural semantics on an uninverted host: fingers down → +wheel,
      // fingers left → +pan (content follows fingers either way).
      expect(events, const [Scroll(0, 1), Scroll(1, 0)]);
    });

    test('scroll gain scales tick rate', () {
      final engine =
          GestureEngine(config: const GestureConfig(scrollGain: 2.0));
      final events = engine.processAll([
        s(1, SamplePhase.down, 100, 100, 0),
        s(2, SamplePhase.down, 130, 100, 0),
        s(1, SamplePhase.move, 100, 116, 50), // 16 px × 2.0 / 32 px-per-tick
      ]);
      expect(events, const [Scroll(0, -1)]);
    });

    test('fast horizontal flick → page swipe phases, no scrolling', () {
      final engine = GestureEngine();
      final events = engine.processAll([
        s(1, SamplePhase.down, 100, 100, 0),
        s(2, SamplePhase.down, 130, 100, 0),
        s(1, SamplePhase.move, 160, 100, 20), // 60 px in 20 ms = 3 px/ms
        s(1, SamplePhase.up, 160, 100, 40),
        s(2, SamplePhase.up, 130, 100, 50),
      ]);
      final phases = events.whereType<GesturePhase>().toList();
      expect(phases.first.phase, GesturePhaseKind.began);
      expect(phases.first.kind, GestureKind.pageSwipeRight);
      expect(phases.last.phase, GesturePhaseKind.ended);
      expect(phases.last.progress, greaterThanOrEqualTo(0.5));
      expect(events.whereType<Scroll>(), isEmpty);
    });

    test('leftward flick → pageSwipeLeft', () {
      final engine = GestureEngine();
      final events = engine.processAll([
        s(1, SamplePhase.down, 100, 100, 0),
        s(2, SamplePhase.down, 130, 100, 0),
        s(1, SamplePhase.move, 40, 100, 20),
      ]);
      expect(events.whereType<GesturePhase>().first.kind,
          GestureKind.pageSwipeLeft);
    });

    test('slow horizontal motion stays a scroll, never a page swipe', () {
      final engine = GestureEngine();
      final events = engine.processAll([
        s(1, SamplePhase.down, 100, 100, 0),
        s(2, SamplePhase.down, 130, 100, 0),
        s(1, SamplePhase.move, 148, 100, 300), // 48 px in 300 ms = 0.16 px/ms
      ]);
      expect(events.whereType<GesturePhase>(), isEmpty);
      expect(events.whereType<Scroll>(), isNotEmpty);
    });

    test('fast vertical motion is a scroll, not a flick', () {
      final engine = GestureEngine();
      final events = engine.processAll([
        s(1, SamplePhase.down, 100, 100, 0),
        s(2, SamplePhase.down, 130, 100, 0),
        s(1, SamplePhase.move, 100, 160, 20), // fast but vertical
      ]);
      expect(events.whereType<GesturePhase>(), isEmpty);
      expect(events.whereType<Scroll>(), isNotEmpty);
    });

    test('both fingers moving apart → zoom-in phases', () {
      final engine = GestureEngine();
      final events = engine.processAll([
        s(1, SamplePhase.down, 150, 100, 0),
        s(2, SamplePhase.down, 250, 100, 0), // 100 px apart, horizontal
        s(1, SamplePhase.move, 110, 100, 100), // finger 1 pulls left (slow)
        s(2, SamplePhase.move, 290, 100, 130), // finger 2 pulls right
        s(1, SamplePhase.up, 110, 100, 180),
        s(2, SamplePhase.up, 290, 100, 190),
      ]);
      final phases = events.whereType<GesturePhase>().toList();
      expect(phases.first.kind, GestureKind.zoomIn);
      expect(phases.first.phase, GesturePhaseKind.began);
      expect(phases.last.phase, GesturePhaseKind.ended);
      expect(phases.every((p) => p.kind == GestureKind.zoomIn), isTrue);
    });

    test('both fingers drawing together → zoom-out phases', () {
      final engine = GestureEngine();
      final events = engine.processAll([
        s(1, SamplePhase.down, 150, 100, 0),
        s(2, SamplePhase.down, 250, 100, 0),
        s(1, SamplePhase.move, 190, 100, 100), // finger 1 moves right, inward
        s(2, SamplePhase.move, 210, 100, 130), // finger 2 moves left, inward
        s(1, SamplePhase.up, 190, 100, 180),
        s(2, SamplePhase.up, 210, 100, 190),
      ]);
      final phases = events.whereType<GesturePhase>().toList();
      expect(phases.first.kind, GestureKind.zoomOut);
      expect(phases.last.phase, GesturePhaseKind.ended);
    });

    test('two fingers translating together stay a scroll, not a zoom', () {
      final engine = GestureEngine();
      final events = engine.processAll([
        s(1, SamplePhase.down, 100, 100, 0),
        s(2, SamplePhase.down, 200, 100, 0),
        // Both fingers move down by the same amount (inter-finger distance
        // unchanged) — pure scroll, no opposing radial motion.
        s(1, SamplePhase.move, 100, 140, 40),
        s(2, SamplePhase.move, 200, 140, 45),
      ]);
      expect(events.whereType<GesturePhase>(), isEmpty);
      expect(events.whereType<Scroll>(), isNotEmpty);
    });

    test('one finger moving (other resting) stays a scroll', () {
      final engine = GestureEngine();
      final events = engine.processAll([
        s(1, SamplePhase.down, 150, 100, 0),
        s(2, SamplePhase.down, 250, 100, 0),
        // Only finger 1 moves radially (slow, so not a flick); finger 2
        // rests. Not a pinch.
        s(1, SamplePhase.move, 110, 100, 100),
        s(1, SamplePhase.move, 90, 100, 200),
      ]);
      expect(events.whereType<GesturePhase>(), isEmpty);
      expect(events.whereType<Scroll>(), isNotEmpty);
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

  group('three fingers', () {
    test('quick three-finger tap → middle click', () {
      final engine = GestureEngine();
      final events = engine.processAll([
        s(1, SamplePhase.down, 100, 100, 0),
        s(2, SamplePhase.down, 120, 100, 5),
        s(3, SamplePhase.down, 140, 100, 10),
        s(1, SamplePhase.up, 100, 100, 90),
        s(2, SamplePhase.up, 120, 100, 95),
        s(3, SamplePhase.up, 140, 100, 100),
      ]);
      expect(events, const [
        ButtonEvent(Button.middle, down: true),
        ButtonEvent(Button.middle, down: false),
      ]);
    });
  });

  group('four-finger spread', () {
    test('fingers moving apart → spread phases, ends committed', () {
      final engine = GestureEngine();
      final events = engine.processAll([
        s(1, SamplePhase.down, 100, 100, 0),
        s(2, SamplePhase.down, 140, 100, 0),
        s(3, SamplePhase.down, 100, 140, 0),
        s(4, SamplePhase.down, 140, 140, 0),
        s(1, SamplePhase.move, 60, 60, 30), // far outward
        s(1, SamplePhase.up, 60, 60, 60),
        s(2, SamplePhase.up, 140, 100, 70),
        s(3, SamplePhase.up, 100, 140, 80),
        s(4, SamplePhase.up, 140, 140, 90),
      ]);
      final phases = events.whereType<GesturePhase>().toList();
      expect(phases.first.phase, GesturePhaseKind.began);
      expect(phases.first.kind, GestureKind.spread);
      expect(phases.last.phase, GesturePhaseKind.ended);
      expect(phases.last.progress, greaterThanOrEqualTo(0.5));
      expect(events.whereType<Scroll>(), isEmpty);
      expect(events.whereType<PointerMove>(), isEmpty);
    });

    test('fingers moving together → pinch phases', () {
      final engine = GestureEngine();
      final events = engine.processAll([
        s(1, SamplePhase.down, 100, 100, 0),
        s(2, SamplePhase.down, 140, 100, 0),
        s(3, SamplePhase.down, 100, 140, 0),
        s(4, SamplePhase.down, 140, 140, 0),
        s(1, SamplePhase.move, 118, 118, 30), // far inward
        s(1, SamplePhase.up, 118, 118, 60),
        s(2, SamplePhase.up, 140, 100, 70),
        s(3, SamplePhase.up, 100, 140, 80),
        s(4, SamplePhase.up, 140, 140, 90),
      ]);
      final phases = events.whereType<GesturePhase>().toList();
      expect(phases.first.phase, GesturePhaseKind.began);
      expect(phases.first.kind, GestureKind.pinch);
      expect(phases.last.phase, GesturePhaseKind.ended);
      expect(phases.last.progress, greaterThanOrEqualTo(0.5));
    });

    test('four fingers resting produce nothing', () {
      final engine = GestureEngine();
      final events = engine.processAll([
        s(1, SamplePhase.down, 100, 100, 0),
        s(2, SamplePhase.down, 140, 100, 0),
        s(3, SamplePhase.down, 100, 140, 0),
        s(4, SamplePhase.down, 140, 140, 0),
        s(1, SamplePhase.up, 100, 100, 400),
        s(2, SamplePhase.up, 140, 100, 410),
        s(3, SamplePhase.up, 100, 140, 420),
        s(4, SamplePhase.up, 140, 140, 430),
      ]);
      expect(events, isEmpty);
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
