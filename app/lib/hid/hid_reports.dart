/// HID report byte encoders (see docs/hid-descriptor.md).
///
/// Payloads EXCLUDE the report ID byte — Android's
/// `BluetoothHidDevice.sendReport(device, reportId, payload)` prepends it.
library;

import 'dart:typed_data';

import '../core/input_event.dart' show MediaKey;

/// Report IDs as declared in the descriptor.
const int mouseReportId = 1;
const int keyboardReportId = 2;
const int consumerReportId = 3;

/// Mouse button bits (payload byte 0).
const int buttonLeftBit = 0x01;
const int buttonRightBit = 0x02;
const int buttonMiddleBit = 0x04;

const int _deltaMax = 127;
const int _deltaMin = -127; // logical min is −127, not −128

int _clampDelta(int v) => v.clamp(_deltaMin, _deltaMax);

int _toInt8Byte(int v) => v & 0xFF;

/// Encodes one mouse report payload: [buttons, dx, dy, wheel, pan].
/// All deltas must already be within −127…127; use [encodeMouseReports]
/// for arbitrary deltas.
Uint8List encodeMouseReport({
  int buttons = 0,
  int dx = 0,
  int dy = 0,
  int wheel = 0,
  int pan = 0,
}) {
  assert(buttons >= 0 && buttons <= 7);
  assert(dx >= _deltaMin && dx <= _deltaMax);
  assert(dy >= _deltaMin && dy <= _deltaMax);
  assert(wheel >= _deltaMin && wheel <= _deltaMax);
  assert(pan >= _deltaMin && pan <= _deltaMax);
  return Uint8List.fromList([
    buttons,
    _toInt8Byte(dx),
    _toInt8Byte(dy),
    _toInt8Byte(wheel),
    _toInt8Byte(pan),
  ]);
}

/// Encodes mouse motion/scroll of arbitrary magnitude, splitting deltas
/// beyond ±127 across consecutive reports. [buttons] is repeated on every
/// report so the held-button state is never lost mid-split.
List<Uint8List> encodeMouseReports({
  int buttons = 0,
  int dx = 0,
  int dy = 0,
  int wheel = 0,
  int pan = 0,
}) {
  final reports = <Uint8List>[];
  var rdx = dx, rdy = dy, rwheel = wheel, rpan = pan;
  do {
    final sdx = _clampDelta(rdx);
    final sdy = _clampDelta(rdy);
    final swheel = _clampDelta(rwheel);
    final span = _clampDelta(rpan);
    reports.add(encodeMouseReport(
      buttons: buttons,
      dx: sdx,
      dy: sdy,
      wheel: swheel,
      pan: span,
    ));
    rdx -= sdx;
    rdy -= sdy;
    rwheel -= swheel;
    rpan -= span;
  } while (rdx != 0 || rdy != 0 || rwheel != 0 || rpan != 0);
  return reports;
}

/// All-zero mouse report: releases every button (stuck-button prevention).
Uint8List mouseReleaseAll() => Uint8List(5);

/// Encodes one keyboard report payload:
/// [modifiers, 0x00, k1, k2, k3, k4, k5, k6].
/// Up to 6 concurrent usage codes; extras are dropped (6-key rollover).
Uint8List encodeKeyboardReport({int modifiers = 0, List<int> keys = const []}) {
  assert(modifiers >= 0 && modifiers <= 0xFF);
  assert(keys.every((k) => k >= 0 && k <= 0xFF));
  final report = Uint8List(8);
  report[0] = modifiers;
  for (var i = 0; i < keys.length && i < 6; i++) {
    report[2 + i] = keys[i];
  }
  return report;
}

/// All-zero keyboard report: releases all keys and modifiers. Every key
/// sequence MUST end with this (stuck-key prevention).
Uint8List keyboardReleaseAll() => Uint8List(8);

/// Encodes one Consumer Control report payload (ID 3): a single byte
/// where bit N = MediaKey with index N, matching the descriptor's
/// usage order.
Uint8List encodeConsumerReport(MediaKey key) =>
    Uint8List.fromList([1 << key.index]);

/// All-zero consumer report: releases any held media key.
Uint8List consumerReleaseAll() => Uint8List(1);

/// Press-then-release pair for a keyboard shortcut, e.g. Mission Control
/// (LCtrl+↑): `[0x01,0,0x52,0,0,0,0,0]` then all-zero.
List<Uint8List> encodeShortcut({required int modifiers, required int usage}) =>
    [
      encodeKeyboardReport(modifiers: modifiers, keys: [usage]),
      keyboardReleaseAll(),
    ];
