import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helm/core/input_event.dart';
import 'package:helm/core/input_sink.dart';
import 'package:helm/hid/keymap.dart';
import 'package:helm/motion/motion_sample.dart';
import 'package:helm/motion/motion_session.dart';
import 'package:helm/presenter/presenter_host.dart';
import 'package:helm/ui/presenter_surface.dart';

import 'support/fake_motion_source.dart';
import 'support/fake_presenter_host.dart';

class RecordingSink implements InputSink {
  final events = <InputEvent>[];

  @override
  Set<Capability> get capabilities =>
      const {Capability.pointer, Capability.keyboard};

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
  late MotionSession session;
  late FakePresenterHost presenterHost;

  setUp(() {
    sink = RecordingSink();
    source = FakeMotionSource();
    presenterHost = FakePresenterHost();
    session = MotionSession(source: source, emit: sink.send);
  });

  tearDown(() => session.dispose());

  Widget host({
    bool clutch = true,
    bool volumeKeys = true,
    KeyStroke? laser,
    bool active = true,
    bool haptics = true,
  }) =>
      MaterialApp(
        home: Scaffold(
          body: PresenterSurface(
            sink: sink,
            session: session,
            host: presenterHost,
            clutch: clutch,
            volumeKeys: volumeKeys,
            laser: laser,
            active: active,
            hapticsEnabled: haptics,
          ),
        ),
      );

  /// Records the vibrations fired through the `vibration` plugin (the same
  /// direct-vibrator path the trackpad uses), as their duration in ms. Only
  /// the duration is checked: off a physical Android/iOS device the plugin
  /// always reports no amplitude control, so the amplitude is not observable
  /// here (`fireHaptic`'s amplitude handling is covered in the trackpad tests).
  List<String> captureHaptics(WidgetTester tester) {
    final log = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('vibration'),
      (call) async {
        if (call.method == 'vibrate') {
          log.add('${(call.arguments as Map)['duration']}');
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('vibration'), null));
    return log;
  }

  // The trackpad's own click haptics (hapticForClick): a 12 ms press and a
  // softer, shorter 8 ms release.
  const press = '12', release = '8';

  Finder pad(String key) => find.byKey(ValueKey(key));

  // The default 800x600 test view is landscape; the horizontal deck needs a
  // portrait phone.
  void portrait(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
  }
  Iterable<PointerMove> moves() => sink.events.whereType<PointerMove>();

  testWidgets('portrait puts the deck below the pad', (tester) async {
    portrait(tester);
    await tester.pumpWidget(host());
    expect(tester.getCenter(pad('next')).dy,
        greaterThan(tester.getCenter(pad('clutch')).dy));
  });

  testWidgets('landscape puts the deck to the right of the pad',
      (tester) async {
    // A realistic landscape phone (800x360 logical), not the unrealistically
    // tall screen devicePixelRatio 1.0 would give.
    tester.view.physicalSize = const Size(2400, 1080);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(laser: const KeyStroke(Mod.none, 0x0F)));
    final clutch = tester.getCenter(pad('clutch'));
    for (final key in ['prev', 'click', 'laser', 'next']) {
      expect(tester.getCenter(pad(key)).dx, greaterThan(clutch.dx),
          reason: key);
    }
    // Stacked top to bottom, with Next still the biggest target.
    expect(tester.getCenter(pad('prev')).dy,
        lessThan(tester.getCenter(pad('next')).dy));
    expect(tester.getSize(pad('next')).height,
        greaterThan(tester.getSize(pad('prev')).height));
  });

  testWidgets('does not overflow on a real phone-sized landscape screen',
      (tester) async {
    // A realistic landscape phone: 2400x1080 physical at 3x density gives an
    // 800x360 logical screen, far shorter than the earlier test's 1080dp.
    // Four stacked deck buttons then have too little height for icon+label
    // unless the content scales down (regression: RenderFlex overflow).
    tester.view.physicalSize = const Size(2400, 1080);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(laser: const KeyStroke(Mod.none, 0x0F)));
    expect(tester.takeException(), isNull);
  });

  testWidgets('starts the sensors on mount and stops them on unmount',
      (tester) async {
    await tester.pumpWidget(host());
    expect(source.running, isTrue);
    await tester.pumpWidget(const SizedBox());
    expect(source.running, isFalse);
  });

  group('clutch (hold to move)', () {
    testWidgets('the pointer follows the phone only while the pad is held',
        (tester) async {
      await tester.pumpWidget(host());
      feed(source, ms: 100); // let the engine learn gravity

      feed(source, gz: -1.0, ms: 300, startMs: 110);
      expect(moves(), isEmpty, reason: 'pad not held yet');

      final touch = await tester.startGesture(tester.getCenter(pad('clutch')));
      await tester.pump();
      feed(source, gz: -1.0, ms: 300, startMs: 420);
      expect(moves(), isNotEmpty);
      expect(moves().every((m) => m.dx > 0), isTrue);

      await touch.up();
      await tester.pump();
      sink.events.clear();
      feed(source, gz: -1.0, ms: 500, startMs: 730);
      expect(moves(), isEmpty, reason: 'released: the cursor freezes');
    });

    testWidgets('the pad shows when it is engaged', (tester) async {
      await tester.pumpWidget(host());
      expect(find.text('Hold to move'), findsOneWidget);
      final touch = await tester.startGesture(tester.getCenter(pad('clutch')));
      await tester.pump();
      expect(find.text('Moving'), findsOneWidget);
      await touch.up();
      await tester.pump();
      expect(find.text('Hold to move'), findsOneWidget);
    });

    testWidgets('a cancelled press freezes the pointer', (tester) async {
      await tester.pumpWidget(host());
      feed(source, ms: 100);
      final touch = await tester.startGesture(tester.getCenter(pad('clutch')));
      await tester.pump();
      await touch.cancel();
      await tester.pump();
      sink.events.clear();
      feed(source, gz: -1.0, ms: 300, startMs: 110);
      expect(moves(), isEmpty);
    });

    testWidgets('tapping Click or Next while the pad is up moves nothing',
        (tester) async {
      // The whole point of the clutch: the shake of a tap stays out.
      await tester.pumpWidget(host());
      feed(source, ms: 100);
      await tester.tap(pad('click'));
      feed(source, gz: -2.0, ms: 200, startMs: 110); // the phone jolts
      await tester.tap(pad('next'));
      expect(moves(), isEmpty);
    });
  });

  group('always on (clutch setting off)', () {
    testWidgets('the pointer follows the phone; holding the pad freezes it',
        (tester) async {
      await tester.pumpWidget(host(clutch: false));
      expect(find.text('Moving'), findsOneWidget);
      feed(source, ms: 100);
      feed(source, gz: -1.0, ms: 300, startMs: 110);
      expect(moves(), isNotEmpty);

      final touch = await tester.startGesture(tester.getCenter(pad('clutch')));
      await tester.pump();
      expect(find.text('Frozen'), findsOneWidget);
      sink.events.clear();
      feed(source, gz: -1.0, ms: 300, startMs: 420);
      expect(moves(), isEmpty);

      await touch.up();
      await tester.pump();
      feed(source, gz: -1.0, ms: 300, startMs: 730);
      expect(moves(), isNotEmpty);
    });

    testWidgets('changing the setting mid-session switches the meaning',
        (tester) async {
      await tester.pumpWidget(host());
      feed(source, ms: 100);
      feed(source, gz: -1.0, ms: 200, startMs: 110);
      expect(moves(), isEmpty); // clutch mode, pad up

      await tester.pumpWidget(host(clutch: false));
      feed(source, gz: -1.0, ms: 300, startMs: 320);
      expect(moves(), isNotEmpty); // always on now
    });
  });

  group('buttons', () {
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

    testWidgets('Next is the widest button', (tester) async {
      portrait(tester);
      await tester.pumpWidget(host());
      final next = tester.getSize(pad('next')).width;
      expect(next, greaterThan(tester.getSize(pad('prev')).width * 1.5));
      expect(next, greaterThan(tester.getSize(pad('click')).width * 1.5));
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
  });

  group('laser toggle', () {
    testWidgets('is hidden when the slide app has no laser shortcut',
        (tester) async {
      await tester.pumpWidget(host());
      expect(pad('laser'), findsNothing);
    });

    testWidgets('sends the app\'s shortcut, modifiers included',
        (tester) async {
      final haptics = captureHaptics(tester);
      await tester.pumpWidget(host(laser: const KeyStroke(Mod.lCtrl, 0x0F)));
      await tester.tap(pad('laser'));
      expect(sink.events, [
        const KeyInput(0x0F, Mod.lCtrl, down: true), // Ctrl+L
        const KeyInput(0x0F, Mod.lCtrl, down: false),
      ]);
      await tester.pump();
      expect(haptics, [press]);
    });

    testWidgets('does not squeeze Next off the screen', (tester) async {
      portrait(tester);
      await tester.pumpWidget(host(laser: const KeyStroke(Mod.none, 0x0F)));
      expect(tester.takeException(), isNull);
      expect(tester.getSize(pad('next')).width,
          greaterThan(tester.getSize(pad('laser')).width * 1.5));
    });
  });

  group('lifecycle', () {
    testWidgets('leaving presenter mode mid-click releases the button once',
        (tester) async {
      await tester.pumpWidget(host());
      await tester.startGesture(tester.getCenter(pad('click')));
      await tester.pumpWidget(const SizedBox());
      final releases = sink.events
          .where((e) => e == const ButtonEvent(Button.left, down: false));
      expect(releases.length, 1);
    });

    testWidgets('leaving with the pad held opens the clutch', (tester) async {
      await tester.pumpWidget(host());
      await tester.startGesture(tester.getCenter(pad('clutch')));
      await tester.pump();
      expect(session.engine.engaged, isTrue);
      await tester.pumpWidget(const SizedBox());
      expect(session.engine.engaged, isFalse);
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

    testWidgets('after resuming, always-on mode moves again', (tester) async {
      await tester.pumpWidget(host(clutch: false));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(session.engine.engaged, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(session.engine.engaged, isTrue);
    });

    testWidgets('leaving frees the clutch and click even if another screen '
        'still uses the sensors', (tester) async {
      await tester.pumpWidget(host());
      await session.attach(); // e.g. the diagnostics screen
      await tester.startGesture(tester.getCenter(pad('clutch')));
      await tester.startGesture(tester.getCenter(pad('click')));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      expect(session.engine.engaged, isFalse);
      expect(sink.events.last, const ButtonEvent(Button.left, down: false));
      session.detach();
    });

    testWidgets('the sensors keep running while another screen still uses '
        'them', (tester) async {
      await tester.pumpWidget(host());
      await session.attach(); // e.g. the diagnostics screen
      await tester.pumpWidget(const SizedBox());
      expect(source.running, isTrue);
      session.detach();
      expect(source.running, isFalse);
    });
  });

  group('hands-free', () {
    testWidgets('volume up/down are Prev/Next while captured', (tester) async {
      await tester.pumpWidget(host());
      expect(presenterHost.volumeKeysCaptured, isTrue);
      presenterHost.press(VolumeKey.down);
      presenterHost.press(VolumeKey.up);
      expect(sink.events, [
        const KeyInput(0x4E, 0, down: true), // Page Down = next
        const KeyInput(0x4E, 0, down: false),
        const KeyInput(0x4B, 0, down: true), // Page Up = prev
        const KeyInput(0x4B, 0, down: false),
      ]);
    });

    testWidgets('lifting a volume key does nothing', (tester) async {
      await tester.pumpWidget(host());
      presenterHost.press(VolumeKey.down);
      sink.events.clear();
      presenterHost.release(VolumeKey.down);
      expect(sink.events, isEmpty);
    });

    testWidgets('with the setting off, volume keys are left to the system',
        (tester) async {
      await tester.pumpWidget(host(volumeKeys: false));
      expect(presenterHost.volumeKeysCaptured, isFalse);
      presenterHost.press(VolumeKey.down);
      expect(sink.events, isEmpty);
    });

    testWidgets('turning the setting off mid-session releases the keys',
        (tester) async {
      await tester.pumpWidget(host());
      expect(presenterHost.volumeKeysCaptured, isTrue);
      await tester.pumpWidget(host(volumeKeys: false));
      expect(presenterHost.volumeKeysCaptured, isFalse);
      presenterHost.press(VolumeKey.up);
      expect(sink.events, isEmpty);
      await tester.pumpWidget(host());
      expect(presenterHost.volumeKeysCaptured, isTrue);
    });

    testWidgets('leaving presenter mode gives the volume keys back',
        (tester) async {
      await tester.pumpWidget(host());
      await tester.pumpWidget(const SizedBox());
      expect(presenterHost.volumeKeysCaptured, isFalse);
      presenterHost.press(VolumeKey.down);
      expect(sink.events, isEmpty);
    });

    testWidgets('backgrounding releases keys and screen; resuming retakes them',
        (tester) async {
      await tester.pumpWidget(host());
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(presenterHost.volumeKeysCaptured, isFalse);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(presenterHost.volumeKeysCaptured, isTrue);
      presenterHost.press(VolumeKey.down);
      expect(sink.events.whereType<KeyInput>(), isNotEmpty);
    });

    testWidgets('slide buttons tap the phone; Click presses and releases '
        'like the trackpad', (tester) async {
      final haptics = captureHaptics(tester);
      await tester.pumpWidget(host());
      await tester.tap(pad('next'));
      await tester.tap(pad('prev'));
      await tester.pump();
      expect(haptics, [press, press]);
      await tester.tap(pad('click')); // down then up
      await tester.pump();
      expect(haptics, [press, press, press, release]);
    });

    testWidgets('engaging the clutch is felt softly, releasing is not',
        (tester) async {
      final haptics = captureHaptics(tester);
      await tester.pumpWidget(host());
      final touch = await tester.startGesture(tester.getCenter(pad('clutch')));
      await tester.pump();
      expect(haptics, [release]);
      await touch.up();
      await tester.pump();
      expect(haptics.length, 1);
    });

    testWidgets('a volume-key slide change is felt too', (tester) async {
      final haptics = captureHaptics(tester);
      await tester.pumpWidget(host());
      presenterHost.press(VolumeKey.down);
      await tester.pump();
      expect(haptics, [press]);
    });

    testWidgets('nothing vibrates when haptics are off in Settings',
        (tester) async {
      final haptics = captureHaptics(tester);
      await tester.pumpWidget(
          host(haptics: false, laser: const KeyStroke(Mod.none, 0x0F)));
      await tester.tap(pad('next'));
      await tester.tap(pad('click'));
      await tester.tap(pad('laser'));
      await tester.startGesture(tester.getCenter(pad('clutch')));
      presenterHost.press(VolumeKey.up);
      await tester.pump();
      expect(haptics, isEmpty);
      // ...and the buttons still work.
      expect(sink.events.whereType<KeyInput>(), isNotEmpty);
    });
  });

  group('always on: bias', () {
    testWidgets('a steady gyro bias is learned away, not left to creep',
        (tester) async {
      // Always-on keeps the engine engaged; it must still learn the bias.
      await tester.pumpWidget(host(clutch: false));
      feed(source, gz: 0.03, ms: 30000);
      expect(session.engine.gyroBias.z, closeTo(0.03, 0.005));
      sink.events.clear();
      feed(source, gz: 0.03, ms: 5000, startMs: 30010);
      expect(moves(), isEmpty);
    });
  });

  group('covered by another screen', () {
    testWidgets('goes quiet while Settings is on top, and resumes after',
        (tester) async {
      await tester.pumpWidget(host(clutch: false, laser: null));
      expect(session.engine.engaged, isTrue);
      expect(presenterHost.volumeKeysCaptured, isTrue);

      await tester.pumpWidget(host(clutch: false, active: false));
      expect(session.engine.engaged, isFalse,
          reason: 'scrolling a settings list must not move the cursor');
      expect(presenterHost.volumeKeysCaptured, isFalse);
      expect(source.running, isFalse);

      await tester.pumpWidget(host(clutch: false));
      expect(session.engine.engaged, isTrue);
      expect(presenterHost.volumeKeysCaptured, isTrue);
      expect(source.running, isTrue);
    });

    testWidgets('a held click and the pad are released when covered',
        (tester) async {
      await tester.pumpWidget(host());
      await tester.startGesture(tester.getCenter(pad('click')));
      await tester.startGesture(tester.getCenter(pad('clutch')));
      await tester.pump();
      await tester.pumpWidget(host(active: false));
      expect(sink.events.last, const ButtonEvent(Button.left, down: false));
      expect(session.engine.engaged, isFalse);
    });

    testWidgets('resuming from the background stays quiet if still covered',
        (tester) async {
      await tester.pumpWidget(host(active: false));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(source.running, isFalse);
      expect(presenterHost.volumeKeysCaptured, isFalse);
    });
  });

  group('pads and fingers', () {
    testWidgets('the clutch stays held until the last finger lifts',
        (tester) async {
      await tester.pumpWidget(host());
      final first = await tester.startGesture(tester.getCenter(pad('clutch')));
      final second = await tester.startGesture(
          tester.getCenter(pad('clutch')) + const Offset(20, 20));
      await tester.pump();
      expect(session.engine.engaged, isTrue);
      await first.up();
      await tester.pump();
      expect(session.engine.engaged, isTrue,
          reason: 'one finger is still down');
      await second.up();
      await tester.pump();
      expect(session.engine.engaged, isFalse);
    });

    testWidgets('a second finger does not press Click twice', (tester) async {
      await tester.pumpWidget(host());
      final a = await tester.startGesture(tester.getCenter(pad('click')));
      final b = await tester.startGesture(
          tester.getCenter(pad('click')) + const Offset(10, 10));
      await a.up();
      await b.up();
      expect(sink.events, [
        const ButtonEvent(Button.left, down: true),
        const ButtonEvent(Button.left, down: false),
      ]);
    });
  });

  testWidgets('a transient sensor error clears once samples resume',
      (tester) async {
    await tester.pumpWidget(host());
    source.emitError(Exception('blip'));
    await tester.pump();
    expect(find.text('Motion sensors unavailable'), findsOneWidget);
    feed(source, ms: 50);
    await tester.pump();
    expect(find.text('Motion sensors unavailable'), findsNothing);
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
