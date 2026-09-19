import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helm/core/input_event.dart';
import 'package:helm/core/input_sink.dart';
import 'package:helm/hid/shortcut_tables.dart';
import 'package:helm/transport/hid_transport.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('dev.taira.helm/hid');
  late List<(String, Uint8List?)> calls;
  late HidTransport transport;

  setUp(() {
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add((call.method, call.arguments is Uint8List
          ? call.arguments as Uint8List
          : null));
      return null;
    });
    transport = HidTransport();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('button press and release send immediate mouse reports', () async {
    transport
      ..send(const ButtonEvent(Button.left, down: true))
      ..send(const ButtonEvent(Button.left, down: false));
    await pumpEventQueue();
    expect(calls.map((c) => c.$1), ['sendMouseReport', 'sendMouseReport']);
    expect(calls[0].$2, [0x01, 0, 0, 0, 0]);
    expect(calls[1].$2, [0x00, 0, 0, 0, 0]);
  });

  test('pointer moves coalesce into one report per microtask', () async {
    transport
      ..send(const PointerMove(3, 4))
      ..send(const PointerMove(2, -1))
      ..send(const Scroll(0, 1));
    await pumpEventQueue();
    final mouse = calls.where((c) => c.$1 == 'sendMouseReport').toList();
    expect(mouse.length, 1);
    expect(mouse.single.$2, [0x00, 5, 3, 1, 0]);
  });

  test('held button is carried in coalesced motion reports', () async {
    transport.send(const ButtonEvent(Button.left, down: true));
    transport.send(const PointerMove(10, 0));
    await pumpEventQueue();
    expect(calls.last.$2!.first, 0x01);
  });

  test('committed swipe fires shortcut press + release', () async {
    transport.send(const GesturePhase(
        GestureKind.swipeUp, GesturePhaseKind.ended, 0.8));
    await pumpEventQueue();
    final kb = calls.where((c) => c.$1 == 'sendKeyboardReport').toList();
    expect(kb.length, 2);
    expect(kb[0].$2, [0x01, 0x00, 0x52, 0, 0, 0, 0, 0]); // Ctrl+↑
    expect(kb[1].$2, List.filled(8, 0));
  });

  test('swipe released below half progress fires nothing', () async {
    transport.send(const GesturePhase(
        GestureKind.swipeUp, GesturePhaseKind.ended, 0.4));
    await pumpEventQueue();
    expect(calls, isEmpty);
  });

  test('changed/cancelled phases never fire, even at full progress',
      () async {
    transport
      ..send(const GesturePhase(
          GestureKind.swipeLeft, GesturePhaseKind.changed, 1.0))
      ..send(const GesturePhase(
          GestureKind.swipeLeft, GesturePhaseKind.cancelled, 1.0));
    await pumpEventQueue();
    expect(calls, isEmpty);
  });

  test('target OS switches the shortcut table', () async {
    transport.targetOs = TargetOs.windows;
    transport.send(const GesturePhase(
        GestureKind.swipeUp, GesturePhaseKind.ended, 1.0));
    await pumpEventQueue();
    final kb = calls.where((c) => c.$1 == 'sendKeyboardReport').toList();
    expect(kb.first.$2, [0x08, 0x00, 0x2B, 0, 0, 0, 0, 0]); // Win+Tab
  });

  test('modifier-only keystroke sends modifier byte with no usage', () async {
    transport.targetOs = TargetOs.linux;
    transport.send(const GesturePhase(
        GestureKind.swipeUp, GesturePhaseKind.ended, 1.0));
    await pumpEventQueue();
    final kb = calls.where((c) => c.$1 == 'sendKeyboardReport').toList();
    expect(kb.first.$2, [0x08, 0x00, 0x00, 0, 0, 0, 0, 0]); // bare Super
  });

  test('natural mode swaps horizontal swipes (left swipe → right shortcut)',
      () async {
    transport.send(const GesturePhase(
        GestureKind.swipeLeft, GesturePhaseKind.ended, 1.0));
    await pumpEventQueue();
    final kb = calls.where((c) => c.$1 == 'sendKeyboardReport').toList();
    expect(kb.first.$2, [0x01, 0x00, 0x4F, 0, 0, 0, 0, 0]); // Ctrl+→
  });

  test('reverse mode keeps physical swipe direction', () async {
    transport.naturalScroll = false;
    transport.send(const GesturePhase(
        GestureKind.swipeLeft, GesturePhaseKind.ended, 1.0));
    await pumpEventQueue();
    final kb = calls.where((c) => c.$1 == 'sendKeyboardReport').toList();
    expect(kb.first.$2, [0x01, 0x00, 0x50, 0, 0, 0, 0, 0]); // Ctrl+←
  });

  test('page flick maps to browser back/forward (natural swap applies)',
      () async {
    // Natural mode (default): fingers moving right = go back = Cmd+[.
    transport.send(const GesturePhase(
        GestureKind.pageSwipeRight, GesturePhaseKind.ended, 1.0));
    await pumpEventQueue();
    final kb = calls.where((c) => c.$1 == 'sendKeyboardReport').toList();
    expect(kb.first.$2, [0x08, 0x00, 0x2F, 0, 0, 0, 0, 0]); // Cmd+[
  });

  test('spread fires show desktop (F11 on macOS), unaffected by natural mode',
      () async {
    transport.send(const GesturePhase(
        GestureKind.spread, GesturePhaseKind.ended, 0.9));
    await pumpEventQueue();
    final kb = calls.where((c) => c.$1 == 'sendKeyboardReport').toList();
    expect(kb.first.$2, [0x00, 0x00, 0x44, 0, 0, 0, 0, 0]); // F11
    expect(kb.last.$2, List.filled(8, 0));
  });

  test('zoom-in fires Cmd+= and repeats freely', () async {
    const zoom = GesturePhase(GestureKind.zoomIn, GesturePhaseKind.ended, 1.0);
    transport
      ..send(zoom)
      ..send(zoom);
    await pumpEventQueue();
    final kb = calls.where((c) => c.$1 == 'sendKeyboardReport').toList();
    expect(kb.length, 4); // both fire; zoom is not a toggle
    expect(kb.first.$2, [0x08, 0x00, 0x2E, 0, 0, 0, 0, 0]); // Cmd+=
  });

  test('zoom-out fires Cmd+-', () async {
    transport.send(
        const GesturePhase(GestureKind.zoomOut, GesturePhaseKind.ended, 1.0));
    await pumpEventQueue();
    final kb = calls.where((c) => c.$1 == 'sendKeyboardReport').toList();
    expect(kb.first.$2, [0x08, 0x00, 0x2D, 0, 0, 0, 0, 0]); // Cmd+-
  });

  test('vertical swipes are never inverted', () async {
    transport.send(const GesturePhase(
        GestureKind.swipeUp, GesturePhaseKind.ended, 1.0));
    await pumpEventQueue();
    final kb = calls.where((c) => c.$1 == 'sendKeyboardReport').toList();
    expect(kb.first.$2, [0x01, 0x00, 0x52, 0, 0, 0, 0, 0]); // Ctrl+↑
  });

  group('host-mode tracking (repeats must not undo)', () {
    const up = GesturePhase(GestureKind.swipeUp, GesturePhaseKind.ended, 1.0);
    const down =
        GesturePhase(GestureKind.swipeDown, GesturePhaseKind.ended, 1.0);
    const spread =
        GesturePhase(GestureKind.spread, GesturePhaseKind.ended, 1.0);

    int keyboardSends() =>
        calls.where((c) => c.$1 == 'sendKeyboardReport').length;

    test('repeated up-swipe fires only once', () async {
      transport
        ..send(up)
        ..send(up);
      await pumpEventQueue();
      expect(keyboardSends(), 2); // one press + release pair
    });

    test('vertical swipes walk the three-level stack', () async {
      transport
        ..send(up) // desktop → Mission Control: sends
        ..send(up) // already at the top: suppressed
        ..send(down) // MC → desktop: sends
        ..send(down) // desktop → App Exposé: sends
        ..send(down); // already at the bottom: suppressed
      await pumpEventQueue();
      expect(keyboardSends(), 6); // three pairs
    });

    test('repeated spread fires only once', () async {
      transport
        ..send(spread)
        ..send(spread);
      await pumpEventQueue();
      expect(keyboardSends(), 2);
    });

    test('a click resets the estimate (host overlay was dismissed)',
        () async {
      transport
        ..send(up)
        ..send(const ButtonEvent(Button.left, down: true))
        ..send(const ButtonEvent(Button.left, down: false))
        ..send(up);
      await pumpEventQueue();
      expect(keyboardSends(), 4); // both up-swipes fired
    });

    test('typing resets the estimate', () async {
      transport
        ..send(spread)
        ..send(const KeyInput(0x29, 0, down: true)) // Esc
        ..send(const KeyInput(0x29, 0, down: false))
        ..send(spread);
      await pumpEventQueue();
      // 2 gesture pairs + Esc press/release = 6 keyboard sends.
      expect(keyboardSends(), 6);
    });

    test('pinch restores the desktop once, only after a spread', () async {
      const pinch =
          GesturePhase(GestureKind.pinch, GesturePhaseKind.ended, 1.0);
      transport.send(pinch); // nothing shown yet: suppressed
      await pumpEventQueue();
      expect(keyboardSends(), 0);

      transport
        ..send(spread) // show desktop: sends
        ..send(pinch) // restore: sends
        ..send(pinch); // already restored: suppressed
      await pumpEventQueue();
      expect(keyboardSends(), 4); // spread pair + pinch pair
    });

    test('horizontal swipes repeat freely', () async {
      const left =
          GesturePhase(GestureKind.swipeLeft, GesturePhaseKind.ended, 1.0);
      transport
        ..send(left)
        ..send(left)
        ..send(left);
      await pumpEventQueue();
      expect(keyboardSends(), 6); // three pairs, none suppressed
    });
  });

  test('key events send press then release-all', () async {
    transport
      ..send(const KeyInput(0x04, 0x02, down: true)) // Shift+A
      ..send(const KeyInput(0x04, 0x02, down: false));
    await pumpEventQueue();
    final kb = calls.where((c) => c.$1 == 'sendKeyboardReport').toList();
    expect(kb[0].$2, [0x02, 0x00, 0x04, 0, 0, 0, 0, 0]);
    expect(kb[1].$2, List.filled(8, 0));
  });

  test('media tap sends consumer press then release', () async {
    transport.send(const MediaTap(MediaKey.volumeUp));
    await pumpEventQueue();
    final consumer =
        calls.where((c) => c.$1 == 'sendConsumerReport').toList();
    expect(consumer.length, 2);
    expect(consumer[0].$2, [0x08]);
    expect(consumer[1].$2, [0x00]);
  });

  test('disconnect sends release-all for every report first', () async {
    await transport.disconnect();
    expect(calls.map((c) => c.$1).toList(), [
      'sendMouseReport',
      'sendKeyboardReport',
      'sendConsumerReport',
      'disconnect',
    ]);
    expect(calls[0].$2, [0, 0, 0, 0, 0]);
    expect(calls[1].$2, List.filled(8, 0));
    expect(calls[2].$2, [0]);
  });

  test('bondedDevices parses name, address, and connected flag', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'getBondedDevices');
      return [
        {'address': 'AA:BB', 'name': 'MacBook', 'connected': true},
        {'address': 'CC:DD', 'name': 'Earbuds', 'connected': false},
        {'address': 'EE:FF', 'name': 'Old laptop'}, // flag missing
      ];
    });
    final devices = await transport.bondedDevices();
    expect(devices.length, 3);
    expect(devices[0].name, 'MacBook');
    expect(devices[0].connected, isTrue);
    expect(devices[1].connected, isFalse);
    expect(devices[2].connected, isFalse);
  });

  test('motion queued before a click flushes ahead of the click edge',
      () async {
    transport
      ..send(const PointerMove(5, 5))
      ..send(const ButtonEvent(Button.left, down: true));
    await pumpEventQueue();
    expect(calls[0].$2, [0x00, 5, 5, 0, 0]);
    expect(calls[1].$2, [0x01, 0, 0, 0, 0]);
  });

  group('absolute pointing is not supported over HID', () {
    test('does not declare the absolutePointer capability', () {
      expect(transport.capabilities, isNot(contains(Capability.absolutePointer)));
    });

    test('an absolute position is dropped, never faked with relative motion',
        () async {
      transport.send(const PointerAbsolute(0.9, 0.9));
      await pumpEventQueue();
      expect(calls, isEmpty);
    });

    test('clicks still reach the mouse report after an absolute event',
        () async {
      transport
        ..send(const PointerAbsolute(0.5, 0.5))
        ..send(const ButtonEvent(Button.left, down: true))
        ..send(const ButtonEvent(Button.left, down: false));
      await pumpEventQueue();
      expect(calls.map((c) => c.$2), [
        [0x01, 0, 0, 0, 0],
        [0x00, 0, 0, 0, 0],
      ]);
    });
  });
}
