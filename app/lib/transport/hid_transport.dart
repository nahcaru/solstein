/// Dart side of the v0.1 HID transport. The Kotlin module owns the
/// `BluetoothHidDevice` session (see android/ HidService.kt); this class
/// encodes [InputEvent]s into report bytes and enforces Tier 1 semantics.
library;

import 'dart:async';

import 'package:flutter/services.dart';

import '../core/input_event.dart';
import '../core/input_sink.dart';
import '../hid/hid_reports.dart';
import '../hid/shortcut_tables.dart';

class HidTransport implements InputSink {
  HidTransport({this.targetOs = TargetOs.macos}) {
    _stateSubscription = _stateChannel
        .receiveBroadcastStream()
        .map(_parseState)
        .listen(_state.add, onError: (Object _) => _state.add(SinkState.error));
  }

  static const _channel = MethodChannel('dev.taira.helm/hid');
  static const _stateChannel = EventChannel('dev.taira.helm/hid_state');

  /// Which shortcut table 3-finger swipes resolve against (Settings toggle).
  TargetOs targetOs;

  /// Natural (content-follows-fingers) semantics for horizontal 3-finger
  /// swipes: swiping left moves to the space on the right, like a real
  /// trackpad. Vertical swipes are never inverted (up is Mission Control
  /// in both modes on every OS).
  bool naturalScroll = true;

  final _state = StreamController<SinkState>.broadcast();
  StreamSubscription<SinkState>? _stateSubscription;

  // Latest-wins coalescing: motion accumulates here and flushes once per
  // microtask; button/key events flush immediately (never dropped).
  int _pendingDx = 0, _pendingDy = 0, _pendingWheel = 0, _pendingPan = 0;
  bool _flushScheduled = false;
  int _buttons = 0;

  // Host-mode estimate so repeated gestures don't undo themselves — the
  // collapsed shortcuts (Ctrl+↑, F11, Win+Tab…) all toggle on the host.
  // Vertical level walks the macOS stack: −1 App Exposé / desktop shown,
  // 0 normal, +1 Mission Control / Task View. Clicking or typing interacts
  // with the host UI and closes these overlays, so it resets the estimate.
  int _verticalLevel = 0;
  bool _desktopShown = false;

  void _resetHostModes() {
    _verticalLevel = 0;
    _desktopShown = false;
  }

  @override
  Set<Capability> get capabilities => const {
        Capability.pointer,
        Capability.keyboard,
        Capability.discreteGesture,
        Capability.mediaKeys,
      };

  @override
  Stream<SinkState> get state => _state.stream;

  static SinkState _parseState(dynamic raw) => switch (raw as String) {
        'connecting' => SinkState.connecting,
        'connected' => SinkState.connected,
        'error' => SinkState.error,
        _ => SinkState.disconnected,
      };

  /// Requests runtime Bluetooth permissions (API 31+ trio, notifications on
  /// 33+). Returns true when everything needed is granted.
  Future<bool> ensurePermissions() async =>
      await _channel.invokeMethod<bool>('ensurePermissions') ?? false;

  /// Human-readable reason for the last [SinkState.error], if any
  /// (e.g. OEM builds that disable the HID Device profile).
  Future<String?> lastError() => _channel.invokeMethod<String>('getLastError');

  /// Address of the host currently receiving input, or null.
  Future<String?> connectedDeviceId() =>
      _channel.invokeMethod<String>('getConnectedDevice');

  /// Bonded Bluetooth devices eligible as hosts.
  Future<List<DeviceTarget>> bondedDevices() async {
    final raw = await _channel.invokeListMethod<Map<Object?, Object?>>(
        'getBondedDevices');
    return [
      for (final d in raw ?? const [])
        DeviceTarget(
          id: d['address']! as String,
          name: d['name']! as String,
          connected: d['connected'] as bool? ?? false,
        ),
    ];
  }

  @override
  Future<void> connect(DeviceTarget target) {
    _resetHostModes(); // new session, unknown host state
    return _channel.invokeMethod<void>('connect', {'address': target.id});
  }

  @override
  Future<void> disconnect() async {
    await releaseAll();
    await _channel.invokeMethod<void>('disconnect');
  }

  /// Neutralizes the host: all buttons and keys up. Called on disconnect,
  /// app pause, and any gesture abort (stuck-key prevention).
  Future<void> releaseAll() async {
    _pendingDx = _pendingDy = _pendingWheel = _pendingPan = 0;
    _buttons = 0;
    await _sendMouse(mouseReleaseAll());
    await _sendKeyboard(keyboardReleaseAll());
    await _sendConsumer(consumerReleaseAll());
  }

  @override
  void send(InputEvent event) {
    switch (event) {
      case PointerMove(:final dx, :final dy):
        _pendingDx += dx;
        _pendingDy += dy;
        _scheduleFlush();
      case Scroll(:final dx, :final dy):
        _pendingWheel += dy;
        _pendingPan += dx;
        _scheduleFlush();
      case ButtonEvent(:final button, :final down):
        if (down) _resetHostModes();
        _flushMotion(); // preserve ordering: motion before the click edge
        final bit = switch (button) {
          Button.left => buttonLeftBit,
          Button.right => buttonRightBit,
          Button.middle => buttonMiddleBit,
        };
        _buttons = down ? (_buttons | bit) : (_buttons & ~bit);
        _sendMouse(encodeMouseReport(buttons: _buttons));
      case KeyInput(:final usage, :final modifiers, :final down):
        if (down) _resetHostModes();
        _sendKeyboard(down
            ? encodeKeyboardReport(
                modifiers: modifiers, keys: usage == 0 ? const [] : [usage])
            : keyboardReleaseAll());
      case MediaTap(:final key):
        _sendConsumer(encodeConsumerReport(key));
        _sendConsumer(consumerReleaseAll());
      case GesturePhase(:final kind, :final phase, :final progress):
        // Tier 1: discrete collapse. Fire only on a committed swipe.
        if (phase == GesturePhaseKind.ended && progress >= 0.5) {
          final effectiveKind = naturalScroll
              ? switch (kind) {
                  GestureKind.swipeLeft => GestureKind.swipeRight,
                  GestureKind.swipeRight => GestureKind.swipeLeft,
                  GestureKind.pageSwipeLeft => GestureKind.pageSwipeRight,
                  GestureKind.pageSwipeRight => GestureKind.pageSwipeLeft,
                  _ => kind,
                }
              : kind;
          if (!_commitHostMode(effectiveKind)) return;
          final stroke = shortcutFor(targetOs, effectiveKind);
          for (final report in encodeShortcut(
              modifiers: stroke.modifiers, usage: stroke.usage)) {
            _sendKeyboard(report);
          }
        }
    }
  }

  /// Updates the host-mode estimate for a committed gesture. Returns false
  /// when the gesture would only undo its own previous action (repeat at
  /// the top/bottom of the vertical stack, spread while desktop shown).
  bool _commitHostMode(GestureKind kind) {
    switch (kind) {
      case GestureKind.swipeUp:
        if (_verticalLevel >= 1) return false;
        _verticalLevel++;
        return true;
      case GestureKind.swipeDown:
        if (_verticalLevel <= -1) return false;
        _verticalLevel--;
        return true;
      case GestureKind.spread:
        if (_desktopShown) return false;
        _desktopShown = true;
        return true;
      case GestureKind.pinch:
        // Restore only undoes a spread we performed; otherwise the toggle
        // key would *show* the desktop instead.
        if (!_desktopShown) return false;
        _desktopShown = false;
        return true;
      default:
        return true; // spaces/page navigation repeat freely
    }
  }

  void _scheduleFlush() {
    if (_flushScheduled) return;
    _flushScheduled = true;
    scheduleMicrotask(() {
      _flushScheduled = false;
      _flushMotion();
    });
  }

  void _flushMotion() {
    if (_pendingDx == 0 &&
        _pendingDy == 0 &&
        _pendingWheel == 0 &&
        _pendingPan == 0) {
      return;
    }
    final reports = encodeMouseReports(
      buttons: _buttons,
      dx: _pendingDx,
      dy: _pendingDy,
      wheel: _pendingWheel,
      pan: _pendingPan,
    );
    _pendingDx = _pendingDy = _pendingWheel = _pendingPan = 0;
    for (final report in reports) {
      _sendMouse(report);
    }
  }

  Future<void> _sendMouse(Uint8List payload) =>
      _channel.invokeMethod<void>('sendMouseReport', payload).catchError((_) {});

  Future<void> _sendKeyboard(Uint8List payload) => _channel
      .invokeMethod<void>('sendKeyboardReport', payload)
      .catchError((_) {});

  Future<void> _sendConsumer(Uint8List payload) => _channel
      .invokeMethod<void>('sendConsumerReport', payload)
      .catchError((_) {});

  Future<void> dispose() async {
    await _stateSubscription?.cancel();
    await _state.close();
  }
}
