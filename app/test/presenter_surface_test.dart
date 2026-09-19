import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helm/core/input_event.dart';
import 'package:helm/core/input_sink.dart';
import 'package:helm/motion/motion_config.dart';
import 'package:helm/motion/motion_sample.dart';
import 'package:helm/ui/presenter_surface.dart';

import 'support/fake_motion_source.dart';

class RecordingSink implements InputSink {
  final events = <InputEvent>[];

  @override
  Set<Capability> get capabilities =>
      const {Capability.pointer, Capability.keyboard, Capability.absolutePointer};

  @override
  void send(InputEvent event) => events.add(event);

  @override
  Stream<SinkState> get state => const Stream.empty();

  @override
  Future<void> connect(DeviceTarget target) async {}

  @override
  Future<void> disconnect() async {}
}

/// Pushes a level (or sweeping) 100 Hz stream through the fake source.
void feed(FakeMotionSource source,
    {double gz = 0, int ms = 500, int startMs = 0}) {
  for (var t = 0; t <= ms; t += 10) {
    source.emit(MotionSample(
      gyroX: 0,
      gyroY: 0,
      gyroZ: gz,
      accelX: 0,
      accelY: 0,
      accelZ: 9.81,
      timestamp: Duration(milliseconds: startMs + t),
    ));
  }
}

void main() {
  late RecordingSink sink;
  late FakeMotionSource source;

  setUp(() {
    sink = RecordingSink();
    source = FakeMotionSource();
  });

  Widget host({
    MotionConfig config = const MotionConfig(),
    bool absoluteSpotlight = true,
  }) =>
      MaterialApp(
        home: Scaffold(
          body: PresenterSurface(
            sink: sink,
            source: source,
            config: config,
            absoluteSpotlight: absoluteSpotlight,
          ),
        ),
      );

  Finder pad(String key) => find.byKey(ValueKey(key));

  testWidgets('starts the sensors on mount and stops them on unmount',
      (tester) async {
    await tester.pumpWidget(host());
    expect(source.running, isTrue);
    await tester.pumpWidget(const SizedBox());
    expect(source.running, isFalse);
  });

  testWidgets('holding Spotlight points absolutely; releasing resumes gliding',
      (tester) async {
    await tester.pumpWidget(host());
    feed(source, ms: 100); // let the engine learn gravity
    final touch = await tester.startGesture(tester.getCenter(pad('spotlight')));
    await tester.pump();
    expect(sink.events.last, const PointerAbsolute(0.5, 0.5));

    feed(source, gz: -0.3, ms: 300, startMs: 110);
    final absolute = sink.events.whereType<PointerAbsolute>().toList();
    expect(absolute.last.x, greaterThan(0.5));

    await touch.up();
    await tester.pump();
    sink.events.clear();
    feed(source, gz: -1.0, ms: 300, startMs: 420);
    expect(sink.events.whereType<PointerAbsolute>(), isEmpty);
    expect(sink.events.whereType<PointerMove>(), isNotEmpty);
  });

  testWidgets('a cancelled Spotlight press ends the spotlight',
      (tester) async {
    await tester.pumpWidget(host());
    feed(source, ms: 100);
    final touch = await tester.startGesture(tester.getCenter(pad('spotlight')));
    await tester.pump();
    await touch.cancel();
    await tester.pump();
    sink.events.clear();
    feed(source, gz: -1.0, ms: 200, startMs: 110);
    expect(sink.events.whereType<PointerAbsolute>(), isEmpty);
  });

  testWidgets('without absolute support Spotlight is Precision and never '
      'emits an absolute position', (tester) async {
    await tester.pumpWidget(host(absoluteSpotlight: false));
    expect(find.text('Precision'), findsOneWidget);
    feed(source, ms: 100);
    final touch = await tester.startGesture(tester.getCenter(pad('spotlight')));
    await tester.pump();
    feed(source, gz: -1.0, ms: 300, startMs: 110);
    await touch.up();
    expect(sink.events.whereType<PointerAbsolute>(), isEmpty);
    expect(sink.events.whereType<PointerMove>(), isNotEmpty);
  });

  testWidgets('Next and Prev tap Page Down and Page Up', (tester) async {
    await tester.pumpWidget(host());
    await tester.tap(pad('next'));
    await tester.tap(pad('prev'));
    expect(sink.events, [
      const KeyInput(0x4E, 0, down: true),
      const KeyInput(0x4E, 0, down: false),
      const KeyInput(0x4B, 0, down: true),
      const KeyInput(0x4B, 0, down: false),
    ]);
  });

  testWidgets('Click presses on touch-down and releases on touch-up',
      (tester) async {
    await tester.pumpWidget(host());
    final touch = await tester.startGesture(tester.getCenter(pad('click')));
    expect(sink.events, [const ButtonEvent(Button.left, down: true)]);
    await touch.up();
    expect(sink.events.last, const ButtonEvent(Button.left, down: false));
    expect(sink.events.length, 2);
  });

  testWidgets('leaving presenter mode mid-click releases the button once',
      (tester) async {
    await tester.pumpWidget(host());
    await tester.startGesture(tester.getCenter(pad('click')));
    await tester.pumpWidget(const SizedBox());
    final releases = sink.events
        .where((e) => e == const ButtonEvent(Button.left, down: false));
    expect(releases.length, 1);
  });

  testWidgets('backgrounding mid-click releases it and stops the sensors; '
      'resuming restarts them', (tester) async {
    await tester.pumpWidget(host());
    await tester.startGesture(tester.getCenter(pad('click')));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(sink.events.last, const ButtonEvent(Button.left, down: false));
    expect(source.running, isFalse);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(source.running, isTrue);
  });

  testWidgets('a rebuild with an equal config keeps the spotlight going',
      (tester) async {
    await tester.pumpWidget(host());
    feed(source, ms: 100);
    await tester.startGesture(tester.getCenter(pad('spotlight')));
    await tester.pump();
    feed(source, gz: -0.3, ms: 200, startMs: 110);
    final before = sink.events.whereType<PointerAbsolute>().length;

    await tester.pumpWidget(host(config: const MotionConfig())); // new, equal
    feed(source, gz: -0.3, ms: 200, startMs: 320);
    expect(sink.events.whereType<PointerAbsolute>().length, greaterThan(before));
  });

  testWidgets('a changed config aborts the spotlight instead of leaving it '
      'half-mapped', (tester) async {
    await tester.pumpWidget(host());
    feed(source, ms: 100);
    await tester.startGesture(tester.getCenter(pad('spotlight')));
    await tester.pump();

    await tester.pumpWidget(host(config: const MotionConfig(pointerGain: 1.5)));
    sink.events.clear();
    feed(source, gz: -1.0, ms: 200, startMs: 110);
    expect(sink.events.whereType<PointerAbsolute>(), isEmpty);
  });

  testWidgets('a sensor error is shown, and the buttons still work',
      (tester) async {
    await tester.pumpWidget(host());
    source.emitError(Exception('no gyroscope'));
    await tester.pump();
    expect(find.text('Motion sensors unavailable'), findsOneWidget);
    await tester.tap(pad('next'));
    expect(sink.events.whereType<KeyInput>(), isNotEmpty);
  });
}
