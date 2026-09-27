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

  // Throttled coalescing: motion accumulates here and goes out as at most
  // one report per [_motionInterval] (ADR-010, ADR-011). An unthrottled
  // per-sample stream starves A2DP audio sharing the radio; so does bursting
  // several reports back-to-back in one flush, which is why a flush sends
  // only one ±127-clamped report and carries any remainder into the next
  // window rather than splitting (see _flushMotion). The first move after
  // idle still flushes on the next microtask. Button/key events are never
  // throttled.
  static const _motionInterval = Duration(milliseconds: 15); // ~66 Hz
  int _pendingDx = 0, _pendingDy = 0, _pendingWheel = 0, _pendingPan = 0;
  bool _flushScheduled = false;
  // Non-null while inside the throttle window opened by the last flush.
  Timer? _motionWindow;
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
    _motionWindow?.cancel();
    _motionWindow = null;
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
      case PointerAbsolute():
        // Dropped on purpose, never faked with relative deltas. This transport
        // does not declare Capability.absolutePointer: a separate absolute
        // report (ID 4) made hosts ignore the mouse buttons (see ADR-008).
        break;
      case Scroll(:final dx, :final dy):
        _pendingWheel += dy;
        _pendingPan += dx;
        _scheduleFlush();
      case ButtonEvent(:final button, :final down):
        if (down) _resetHostModes();
        // Preserve ordering: ALL pending motion before the click edge, not
        // just one throttled tick's worth — otherwise motion from before
        // the edge could arrive after it carrying the new button state (a
        // drag's tail end continuing to move with the button released, or
        // pre-click hover motion turning a plain click into a drag).
        _flushAllMotion();
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
    if (_flushScheduled || _motionWindow != null) return;
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
    // Never send more than one mouse report per flush. A fast swipe can
    // accumulate beyond ±127 in a single window; splitting that into
    // several reports fired back-to-back (encodeMouseReports) bursted onto
    // the radio and made Bluetooth audio coexistence *worse* than the old
    // one-report-per-touch-sample stream did, even though the average
    // report rate is lower (ADR-011). Clamp to one report and carry the
    // remainder into the next window instead — no distance is lost, an
    // extreme flick just catches up over a couple more ticks.
    final dx = _pendingDx.clamp(-127, 127);
    final dy = _pendingDy.clamp(-127, 127);
    final wheel = _pendingWheel.clamp(-127, 127);
    final pan = _pendingPan.clamp(-127, 127);
    _pendingDx -= dx;
    _pendingDy -= dy;
    _pendingWheel -= wheel;
    _pendingPan -= pan;
    _sendMouse(
        encodeMouseReport(buttons: _buttons, dx: dx, dy: dy, wheel: wheel, pan: pan));
    _motionWindow?.cancel();
    _motionWindow = Timer(_motionInterval, () {
      _motionWindow = null;
      _flushMotion();
    });
  }

  /// Drains ALL pending motion immediately, as however many reports it
  /// takes (never holding any back) — used only for the button-edge
  /// ordering guarantee in [send]. This can burst several reports at once,
  /// but only at a click boundary, which is rare; unlike a continuous
  /// swipe, it doesn't reintroduce the continuous back-to-back bursting
  /// ADR-011 fixed. Cancels the throttle window: nothing is left pending
  /// for it to pick up, and the next motion event opens a fresh one.
  void _flushAllMotion() {
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
    _motionWindow?.cancel();
    _motionWindow = null;
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
    _motionWindow?.cancel();
    _motionWindow = null;
    // A flush already scheduled via scheduleMicrotask (send() called just
    // before dispose()) can't be cancelled, but it checks these for zero
    // before sending anything, so zeroing them here makes that stray flush
    // a no-op instead of sending one last report after disposal.
    _pendingDx = _pendingDy = _pendingWheel = _pendingPan = 0;
    await _stateSubscription?.cancel();
    await _state.close();
  }
}
