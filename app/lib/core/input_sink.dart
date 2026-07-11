/// Transport seam: every transport (HID now, BLE in v2) implements
/// [InputSink]. UI adapts to [capabilities] and never branches on the
/// concrete transport type (see docs/architecture.md).
library;

import 'input_event.dart';

enum Capability { pointer, keyboard, discreteGesture, phasedGesture }

enum SinkState { disconnected, connecting, connected, error }

/// Identifies a host to connect to. For HID this is a bonded Bluetooth
/// device; the address format is transport-specific.
class DeviceTarget {
  const DeviceTarget({
    required this.id,
    required this.name,
    this.connected = false,
  });

  final String id;
  final String name;

  /// Whether the phone currently holds a live link to this host.
  final bool connected;

  @override
  String toString() => 'DeviceTarget($name, $id, connected: $connected)';
}

abstract interface class InputSink {
  Future<void> connect(DeviceTarget target);

  Future<void> disconnect();

  void send(InputEvent event);

  Stream<SinkState> get state;

  Set<Capability> get capabilities;
}
