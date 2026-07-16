import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/input_sink.dart';
import 'engine/gesture_config.dart';
import 'hid/keymap.dart';
import 'hid/layouts.dart';
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
      if (s == SinkState.connected) {
        _transport.connectedDeviceId().then((id) async {
          connectedDeviceId = id;
          notifyListeners();
          if (id != null) {
            await _applyTargetOsForDevice(id);
            await _applyHostLayoutForDevice(id);
          }
        });
      } else {
        connectedDeviceId = null;
      }
      notifyListeners();
    });
  }

  /// Applies this host's remembered target OS, or guesses it from the
  /// Bluetooth name on first connect. An explicit Settings choice always
  /// wins ([setTargetOs] stores it per device).
  Future<void> _applyTargetOsForDevice(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getInt('$_kTargetOs.$id');
    TargetOs? os = stored != null ? TargetOs.values[stored] : null;
    if (os == null) {
      final devices = await _transport.bondedDevices();
      for (final device in devices) {
        if (device.id == id) {
          os = guessTargetOs(device.name);
          break;
        }
      }
    }
    if (os != null && os != targetOs) {
      _transport.targetOs = os;
      notifyListeners();
    }
  }

  /// Applies this host's remembered layout, if it has one. No guess exists
  /// for layout the way [guessTargetOs] guesses the OS from a device name.
  Future<void> _applyHostLayoutForDevice(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getInt('$_kHostLayout.$id');
    if (stored == null) return;
    final layout = _layoutFromIndex(stored);
    if (layout != _hostLayoutId) {
      _hostLayoutId = layout;
      notifyListeners();
    }
  }

  /// Address of the host currently receiving input; drives the list's
  /// "which one am I controlling" indicator and switch-vs-reopen taps.
  String? connectedDeviceId;

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

  /// Whether to show the かな / 英数 keys. Off by default — they mean nothing
  /// to users who don't run a host IME. Deliberately not tied to the host
  /// layout: running the Japanese IME on a US-layout Mac is common.
  bool showImeKeys = false;

  /// The host's physical keyboard layout. Independent of [targetOs] — a Mac
  /// can be JIS, a Linux box AZERTY.
  HostLayoutId _hostLayoutId = HostLayoutId.us;

  HostLayout get hostLayout => hostLayouts[_hostLayoutId]!;

  GestureConfig get gestureConfig => GestureConfig(
        pointerGain: pointerGain,
        scrollGain: scrollGain,
        naturalScroll: naturalScroll,
        // macOS flips incoming scroll itself (its "natural scrolling"
        // default); Windows/Linux deliver wheel/pan untouched.
        hostInvertsScroll: targetOs == TargetOs.macos,
      );

  static const _kTargetOs = 'targetOs';
  static const _kPointerGain = 'pointerGain';
  static const _kScrollGain = 'scrollGain';
  static const _kNaturalScroll = 'naturalScroll';
  static const _kHostLayout = 'hostLayout';
  static const _kShowImeKeys = 'showImeKeys';

  static HostLayoutId _layoutFromIndex(int? index) =>
      (index != null && index >= 0 && index < HostLayoutId.values.length)
          ? HostLayoutId.values[index]
          : HostLayoutId.us;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _transport.targetOs =
        TargetOs.values[prefs.getInt(_kTargetOs) ?? TargetOs.macos.index];
    // Clamp: earlier builds persisted values outside the current 0.1–2.0
    // slider range, which would crash the Slider widget.
    pointerGain = (prefs.getDouble(_kPointerGain) ?? 1.0).clamp(0.1, 2.0);
    scrollGain = (prefs.getDouble(_kScrollGain) ?? 1.0).clamp(0.1, 2.0);
    naturalScroll = prefs.getBool(_kNaturalScroll) ?? true;
    _transport.naturalScroll = naturalScroll;
    _hostLayoutId = _layoutFromIndex(prefs.getInt(_kHostLayout));
    showImeKeys = prefs.getBool(_kShowImeKeys) ?? false;
    notifyListeners();
  }

  Future<void> setTargetOs(TargetOs os) async {
    _transport.targetOs = os;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kTargetOs, os.index);
    // Remember the explicit choice for this host; it beats name-guessing.
    final id = connectedDeviceId;
    if (id != null) await prefs.setInt('$_kTargetOs.$id', os.index);
  }

  Future<void> setHostLayout(HostLayoutId id) async {
    _hostLayoutId = id;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kHostLayout, id.index);
    final deviceId = connectedDeviceId;
    if (deviceId != null) {
      await prefs.setInt('$_kHostLayout.$deviceId', id.index);
    }
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

  Future<void> setShowImeKeys(bool value) async {
    showImeKeys = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kShowImeKeys, value);
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
