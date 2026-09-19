import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/input_sink.dart';
import 'engine/gesture_config.dart';
import 'hid/shortcut_tables.dart';
import 'motion/motion_config.dart';
import 'motion/motion_source.dart';
import 'motion/sensors_motion_source.dart';
import 'transport/hid_transport.dart';

/// App-wide state: the transport, user settings, and connection status.
/// UI reads [sink] as an [InputSink] and adapts to its capabilities.
class AppModel extends ChangeNotifier {
  AppModel({HidTransport? transport, MotionSource? motionSource})
      : _transport = transport ?? HidTransport(),
        motionSource = motionSource ?? SensorsMotionSource() {
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
            await _applyAbsoluteSpotlightForDevice(id);
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

  /// Whether this host accepts the absolute-pointer report (spotlight
  /// mapping). Remembered per host: a Mac and a Linux box behind the same
  /// transport can disagree, so this is a setting, not a capability.
  Future<void> _applyAbsoluteSpotlightForDevice(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getBool('$_kAbsoluteSpotlight.$id');
    if (stored != null && stored != absoluteSpotlight) {
      absoluteSpotlight = stored;
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

  /// Gyro + accelerometer feed for presenter mode.
  final MotionSource motionSource;

  SinkState sinkState = SinkState.disconnected;

  TargetOs get targetOs => _transport.targetOs;
  double pointerGain = 1.0;
  double scrollGain = 1.0;
  bool naturalScroll = true;

  /// Presenter mode: relative-glide speed, spotlight field of view (degrees
  /// spanning the full screen width), and whether the spotlight maps
  /// absolutely on the current host.
  double motionGain = 1.0;
  double spotlightFovDegrees = 40;
  bool absoluteSpotlight = true;

  /// What the presenter surface should actually do: needs both the user's
  /// per-host setting and a sink that can accept absolute positions.
  bool get absoluteSpotlightEffective =>
      absoluteSpotlight && sink.capabilities.contains(Capability.absolutePointer);

  MotionConfig get motionConfig => MotionConfig(
        pointerGain: motionGain,
        fieldOfView: spotlightFovDegrees * math.pi / 180,
      );

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
  static const _kMotionGain = 'motionGain';
  static const _kSpotlightFov = 'spotlightFov';
  static const _kAbsoluteSpotlight = 'absoluteSpotlight';

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
    motionGain = (prefs.getDouble(_kMotionGain) ?? 1.0).clamp(0.1, 2.0);
    spotlightFovDegrees =
        (prefs.getDouble(_kSpotlightFov) ?? 40).clamp(20.0, 80.0);
    absoluteSpotlight = prefs.getBool(_kAbsoluteSpotlight) ?? true;
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

  Future<void> setMotionGain(double gain) async {
    motionGain = gain;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kMotionGain, gain);
  }

  Future<void> setSpotlightFov(double degrees) async {
    spotlightFovDegrees = degrees;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kSpotlightFov, degrees);
  }

  Future<void> setAbsoluteSpotlight(bool value) async {
    absoluteSpotlight = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAbsoluteSpotlight, value);
    // Remember the choice for this host, like the target OS.
    final id = connectedDeviceId;
    if (id != null) await prefs.setBool('$_kAbsoluteSpotlight.$id', value);
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
