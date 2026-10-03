import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helm/core/input_event.dart';
import 'package:helm/core/input_sink.dart';
import 'package:helm/hid/keymap.dart';
import 'package:helm/hid/layouts.dart';
import 'package:helm/hid/player_shortcuts.dart';
import 'package:helm/presenter/presenter_host.dart';
import 'package:helm/ui/key_repeat.dart';
import 'package:helm/ui/media_surface.dart';

import 'support/fake_presenter_host.dart';

class RecordingSink implements InputSink {
  final events = <InputEvent>[];

  @override
  Set<Capability> get capabilities => const {Capability.mediaKeys};

  @override
  void send(InputEvent event) => events.add(event);

  @override
  Stream<SinkState> get state => const Stream.empty();

  @override
  Future<void> connect(DeviceTarget target) async {}

  @override
  Future<void> disconnect() async {}
}

void main() {
  late RecordingSink sink;
  late FakePresenterHost host;

  setUp(() {
    sink = RecordingSink();
    host = FakePresenterHost();
  });

  Widget surface({bool active = true, PlayerShortcuts? player}) =>
      MaterialApp(
        home: Scaffold(
          body: MediaSurface(
            sink: sink,
            host: host,
            active: active,
            hapticsEnabled: false,
            player: player,
          ),
        ),
      );

  Finder button(String tooltip) => find.byTooltip(tooltip);

  List<MediaKey> keys() =>
      sink.events.whereType<MediaTap>().map((e) => e.key).toList();

  group('buttons', () {
    for (final (tooltip, key) in [
      ('Play/Pause', MediaKey.playPause),
      ('Previous', MediaKey.prevTrack),
      ('Next', MediaKey.nextTrack),
      ('Mute', MediaKey.mute),
      ('Volume down', MediaKey.volumeDown),
      ('Volume up', MediaKey.volumeUp),
    ]) {
      testWidgets('$tooltip sends one $key', (tester) async {
        await tester.pumpWidget(surface());
        await tester.tap(button(tooltip));
        await tester.pump(kLongPressTimeout * 2);
        expect(keys(), [key]);
      });
    }

    testWidgets('has no brightness controls', (tester) async {
      await tester.pumpWidget(surface());
      expect(button('Brightness up'), findsNothing);
      expect(button('Brightness down'), findsNothing);
    });

    testWidgets('holding Play/Pause does not repeat', (tester) async {
      await tester.pumpWidget(surface());
      final g = await tester.startGesture(tester.getCenter(button('Play/Pause')));
      await tester.pump(kLongPressTimeout + kKeyRepeatInterval * 5);
      await g.up();
      expect(keys(), [MediaKey.playPause]);
    });
  });

  group('player keys', () {
    final shortcuts = playerShortcuts(hostLayouts.values.first);

    List<InputEvent> keyEvents() =>
        sink.events.whereType<KeyInput>().toList();

    testWidgets('are hidden without a player', (tester) async {
      await tester.pumpWidget(surface());
      for (final t in ['Seek back', 'Seek forward', 'Captions', 'Fullscreen']) {
        expect(button(t), findsNothing, reason: t);
      }
    });

    for (final (tooltip, pick) in <(String, KeyStroke Function(PlayerShortcuts))>[
      ('Seek back', (s) => s.back),
      ('Seek forward', (s) => s.forward),
      ('Captions', (s) => s.captions),
      ('Fullscreen', (s) => s.fullscreen),
    ]) {
      testWidgets('$tooltip taps its key once', (tester) async {
        await tester.pumpWidget(surface(player: shortcuts));
        await tester.tap(button(tooltip));
        await tester.pump(kLongPressTimeout * 2);
        final stroke = pick(shortcuts!);
        expect(keyEvents(), [
          KeyInput(stroke.usage, stroke.modifiers, down: true),
          KeyInput(stroke.usage, stroke.modifiers, down: false),
        ]);
      });
    }

    testWidgets('holding Seek does not repeat', (tester) async {
      await tester.pumpWidget(surface(player: shortcuts));
      final g = await tester.startGesture(tester.getCenter(button('Seek back')));
      await tester.pump(kLongPressTimeout + kKeyRepeatInterval * 5);
      await g.up();
      expect(keyEvents().length, 2);
    });

    testWidgets('lay out in a landscape phone', (tester) async {
      tester.view.physicalSize = const Size(2400, 1080);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(surface(player: shortcuts));
      expect(tester.takeException(), isNull);
      expect(button('Fullscreen'), findsOneWidget);
    });
  });

  group('multiple fingers', () {
    testWidgets('a second finger neither double-fires nor ends the hold', (
      tester,
    ) async {
      await tester.pumpWidget(surface());
      final at = tester.getCenter(button('Volume up'));
      final first = await tester.startGesture(at, pointer: 1);
      final second = await tester.startGesture(at, pointer: 2);
      expect(keys().length, 1);
      await tester.pump(kLongPressTimeout);
      await first.up();
      final count = keys().length;
      await tester.pump(kKeyRepeatInterval * 3);
      expect(keys().length, count + 3, reason: 'still held by the 2nd finger');
      await second.up();
      final after = keys().length;
      await tester.pump(const Duration(seconds: 1));
      expect(keys().length, after);
    });
  });

  group('hold to repeat', () {
    testWidgets('holding Volume up repeats at the backspace rate',
        (tester) async {
      await tester.pumpWidget(surface());
      final g = await tester.startGesture(tester.getCenter(button('Volume up')));
      expect(keys(), [MediaKey.volumeUp]);
      await tester.pump(kLongPressTimeout - const Duration(milliseconds: 1));
      expect(keys().length, 1, reason: 'nothing before the delay');
      await tester.pump(const Duration(milliseconds: 1));
      expect(keys().length, 2);
      await tester.pump(kKeyRepeatInterval * 3);
      expect(keys().length, 5);
      await g.up();
      await tester.pump(const Duration(seconds: 1));
      expect(keys().length, 5, reason: 'lifting the finger stops it');
    });

    testWidgets('a cancelled press stops repeating', (tester) async {
      await tester.pumpWidget(surface());
      final g = await tester.startGesture(tester.getCenter(button('Volume down')));
      await tester.pump(kLongPressTimeout);
      await g.cancel();
      final count = keys().length;
      await tester.pump(const Duration(seconds: 1));
      expect(keys().length, count);
    });

    testWidgets('leaving mid-hold stops repeating', (tester) async {
      await tester.pumpWidget(surface());
      await tester.startGesture(tester.getCenter(button('Volume up')));
      await tester.pump(kLongPressTimeout);
      await tester.pumpWidget(const SizedBox());
      final count = keys().length;
      await tester.pump(const Duration(seconds: 1));
      expect(keys().length, count);
    });
  });

  group('hardware volume keys', () {
    testWidgets('are captured while active', (tester) async {
      await tester.pumpWidget(surface());
      expect(host.volumeKeysCaptured, isTrue);
    });

    testWidgets('a press sends the matching media key once', (tester) async {
      await tester.pumpWidget(surface());
      host.press(VolumeKey.up);
      host.release(VolumeKey.up);
      host.press(VolumeKey.down);
      host.release(VolumeKey.down);
      await tester.pump(kLongPressTimeout * 2);
      expect(keys(), [MediaKey.volumeUp, MediaKey.volumeDown]);
    });

    testWidgets('holding repeats at the backspace rate until released',
        (tester) async {
      await tester.pumpWidget(surface());
      host.press(VolumeKey.up);
      expect(keys().length, 1);
      await tester.pump(kLongPressTimeout);
      expect(keys().length, 2);
      await tester.pump(kKeyRepeatInterval * 2);
      expect(keys().length, 4);
      host.release(VolumeKey.up);
      await tester.pump(const Duration(seconds: 1));
      expect(keys().length, 4);
      expect(keys().toSet(), {MediaKey.volumeUp});
    });

    testWidgets("releasing the other key doesn't stop the held one",
        (tester) async {
      await tester.pumpWidget(surface());
      host.press(VolumeKey.up);
      await tester.pump(kLongPressTimeout);
      final count = keys().length;
      host.release(VolumeKey.down);
      await tester.pump(kKeyRepeatInterval * 2);
      expect(keys().length, greaterThan(count));
      host.release(VolumeKey.up);
    });

    testWidgets('are released when the surface goes inactive', (tester) async {
      await tester.pumpWidget(surface());
      host.press(VolumeKey.up);
      await tester.pump(kLongPressTimeout);
      await tester.pumpWidget(surface(active: false));
      expect(host.volumeKeysCaptured, isFalse);
      final count = keys().length;
      await tester.pump(const Duration(seconds: 1));
      expect(keys().length, count, reason: 'the held repeat stopped too');
      host.press(VolumeKey.up);
      expect(keys().length, count, reason: 'no longer listening');
    });

    testWidgets('are captured again when it becomes active', (tester) async {
      await tester.pumpWidget(surface(active: false));
      expect(host.volumeKeysCaptured, isFalse);
      await tester.pumpWidget(surface());
      expect(host.volumeKeysCaptured, isTrue);
    });

    testWidgets('are released on dispose', (tester) async {
      await tester.pumpWidget(surface());
      await tester.pumpWidget(const SizedBox());
      expect(host.volumeKeysCaptured, isFalse);
    });

    testWidgets('are released when the app is backgrounded and retaken on '
        'resume', (tester) async {
      await tester.pumpWidget(surface());
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(host.volumeKeysCaptured, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(host.volumeKeysCaptured, isTrue);
    });
  });
}
