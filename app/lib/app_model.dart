import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/input_sink.dart';
import 'engine/gesture_config.dart';
import 'hid/shortcut_tables.dart';
import 'transport/hid_transport.dart';

/// App-wide state: the transport, user settings, and connection status.
/// UI reads [sink] as an [InputSink] and adapts to its capabilities.
class AppModel extends ChangeNotifier {
  AppModel({HidTransport? transport}) : _transport = transport ?? HidTransport() {
    _transport.state.listen((s) {
      // Navigation follows real state transitions: landing on connected
      // opens the control surface, losing the link falls back to the list.
      if (s == SinkState.connected && sinkState != SinkState.connected) {
        showControl = true;
      } else if (s != SinkState.connected) {
        showControl = false;
      }
      sinkState = s;
      notifyListeners();
    });
  }

  /// Whether the UI should show the control surface (trackpad/keyboard)
  /// rather than the device list. The user can browse back to the list
  /// while staying connected; connection state itself is managed by the
  /// OS Bluetooth settings, not by Helm.
  bool showControl = false;

  void openControl() {
    if (sinkState != SinkState.connected) return;
    showControl = true;
    notifyListeners();
  }

  void closeControl() {
    showControl = false;
    notifyListeners();
  }

  final HidTransport _transport;

  InputSink get sink => _transport;

  SinkState sinkState = SinkState.disconnected;

  TargetOs get targetOs => _transport.targetOs;
  double pointerGain = 1.0;
  double scrollGain = 1.0;
  bool naturalScroll = true;

  GestureConfig get gestureConfig => GestureConfig(
        pointerGain: pointerGain,
        scrollGain: scrollGain,
        naturalScroll: naturalScroll,
      );

  static const _kTargetOs = 'targetOs';
  static const _kPointerGain = 'pointerGain';
  static const _kScrollGain = 'scrollGain';
  static const _kNaturalScroll = 'naturalScroll';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _transport.targetOs =
        TargetOs.values[prefs.getInt(_kTargetOs) ?? TargetOs.macos.index];
    pointerGain = prefs.getDouble(_kPointerGain) ?? 1.0;
    scrollGain = prefs.getDouble(_kScrollGain) ?? 1.0;
    naturalScroll = prefs.getBool(_kNaturalScroll) ?? true;
    _transport.naturalScroll = naturalScroll;
    notifyListeners();
  }

  Future<void> setTargetOs(TargetOs os) async {
    _transport.targetOs = os;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kTargetOs, os.index);
  }

  Future<void> setPointerGain(double gain) async {
    pointerGain = gain;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kPointerGain, gain);
  }

  Future<void> setScrollGain(double gain) async {
    scrollGain = gain;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kScrollGain, gain);
  }

  Future<void> setNaturalScroll(bool value) async {
    naturalScroll = value;
    _transport.naturalScroll = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kNaturalScroll, value);
  }

  Future<bool> ensurePermissions() => _transport.ensurePermissions();

  Future<String?> lastError() => _transport.lastError();

  Future<List<DeviceTarget>> bondedDevices() => _transport.bondedDevices();

  Future<void> connect(DeviceTarget target) => _transport.connect(target);

  Future<void> disconnect() => _transport.disconnect();

  /// Called from the app lifecycle observer on pause (stuck-key prevention).
  Future<void> releaseAll() => _transport.releaseAll();

  @override
  void dispose() {
    _transport.dispose();
    super.dispose();
  }
}
