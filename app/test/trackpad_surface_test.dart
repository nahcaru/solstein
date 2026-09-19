import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helm/core/input_event.dart';
import 'package:helm/core/input_sink.dart';
import 'package:helm/engine/gesture_config.dart';
import 'package:helm/ui/trackpad_surface.dart';

/// Captures what the transport would have sent.
class FakeSink implements InputSink {
  final List<InputEvent> events = [];

  @override
  void send(InputEvent event) => events.add(event);

  @override
  Set<Capability> get capabilities => const {Capability.pointer};

  @override
  Future<void> connect(DeviceTarget target) async {}

  @override
  Future<void> disconnect() async {}

  @override
  Stream<SinkState> get state => const Stream.empty();
}

const _vibrationChannel = MethodChannel('vibration');

void main() {
  group('hapticForClick', () {
    test('right and middle press share one intensity', () {
      expect(
        hapticForClick(Button.right, down: true),
        hapticForClick(Button.middle, down: true),
      );
    });

    test('left press is lighter than right/middle press', () {
      final left = hapticForClick(Button.left, down: true);
      final right = hapticForClick(Button.right, down: true);
      expect(left.amplitude, lessThan(right.amplitude));
    });

    test('release is weaker than press for every button', () {
      for (final button in Button.values) {
        final press = hapticForClick(button, down: true);
        final release = hapticForClick(button, down: false);
        expect(release.amplitude, lessThan(press.amplitude));
        expect(release.duration, lessThanOrEqualTo(press.duration));
      }
    });
  });

  group('fireHaptic', () {
    late List<MethodCall> calls;

    setUp(() {
      calls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_vibrationChannel, (call) async {
        calls.add(call);
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_vibrationChannel, null);
    });

    test('sends amplitude when the device supports it', () async {
      const haptic = ClickHaptic(12, 200);
      await fireHaptic(haptic, amplitudeSupported: true);
      expect(calls.single.method, 'vibrate');
      expect(calls.single.arguments['duration'], 12);
      expect(calls.single.arguments['amplitude'], 200);
    });

    test('omits amplitude when the device does not support it', () async {
      const haptic = ClickHaptic(12, 200);
      await fireHaptic(haptic, amplitudeSupported: false);
      expect(calls.single.method, 'vibrate');
      expect(calls.single.arguments['duration'], 12);
      expect(calls.single.arguments['amplitude'], -1);
    });
  });

  group('TrackpadSurface', () {
    late List<MethodCall> calls;

    setUp(() {
      calls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_vibrationChannel, (call) async {
        calls.add(call);
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_vibrationChannel, null);
    });

    Future<void> pumpTrackpad(
      WidgetTester tester,
      FakeSink sink, {
      required bool hapticsEnabled,
    }) {
      return tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TrackpadSurface(
            sink: sink,
            config: const GestureConfig(),
            hapticsEnabled: hapticsEnabled,
          ),
        ),
      ));
    }

    testWidgets('a tap-click vibrates on both press and release when enabled',
        (tester) async {
      final sink = FakeSink();
      await pumpTrackpad(tester, sink, hapticsEnabled: true);

      final gesture = await tester.startGesture(const Offset(100, 100));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(
        sink.events.whereType<ButtonEvent>().map((e) => e.down),
        [true, false],
      );
      final vibrateCalls = calls.where((c) => c.method == 'vibrate').toList();
      expect(vibrateCalls.length, 2);
      expect(
        vibrateCalls[0].arguments['duration'],
        hapticForClick(Button.left, down: true).duration,
      );
      expect(
        vibrateCalls[1].arguments['duration'],
        hapticForClick(Button.left, down: false).duration,
      );
    });

    testWidgets('no vibration fires when the setting is off', (tester) async {
      final sink = FakeSink();
      await pumpTrackpad(tester, sink, hapticsEnabled: false);

      final gesture = await tester.startGesture(const Offset(100, 100));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(
        sink.events.whereType<ButtonEvent>().map((e) => e.down),
        [true, false],
      );
      expect(calls.where((c) => c.method == 'vibrate'), isEmpty);
    });
  });
}
