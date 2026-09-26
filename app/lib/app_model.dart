import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/input_sink.dart';
import 'engine/gesture_config.dart';
import 'hid/keymap_us.dart' show KeyStroke;
import 'hid/laser_shortcuts.dart';
import 'hid/shortcut_tables.dart';
import 'motion/motion_config.dart';
import 'motion/motion_session.dart';
import 'motion/motion_source.dart';
import 'motion/sensors_motion_source.dart';
import 'presenter/presenter_host.dart';
import 'transport/hid_transport.dart';

/// App-wide state: the transport, user settings, and connection status.
/// UI reads [sink] as an [InputSink] and adapts to its capabilities.
class AppModel extends ChangeNotifier {
  AppModel({
    HidTransport? transport,
    MotionSource? motionSource,
    PresenterHost? presenterHost,
  })  : _transport = transport ?? HidTransport(),
        _motionSource = motionSource ?? SensorsMotionSource(),
        presenterHost = presenterHost ?? MethodChannelPresenterHost() {
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
          if (id != null) await _applyTargetOsForDevice(id);
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

  final MotionSource _motionSource;

  /// Keep-awake and volume-key access for presenting hands-free.
  final PresenterHost presenterHost;

  /// Presenter mode's shared engine and sensor feed. One instance for the app
  /// session, so the learned gyro bias survives leaving and re-entering
  /// presenter mode, and diagnostics recalibrates the engine doing the pointing.
  late final MotionSession motion = MotionSession(
    source: _motionSource,
    emit: _transport.send,
    config: motionConfig,
  );

  SinkState sinkState = SinkState.disconnected;

  TargetOs get targetOs => _transport.targetOs;
  double pointerGain = 1.0;
  double scrollGain = 1.0;
  bool naturalScroll = true;

  /// Presenter mode: cursor speed, the ballistics exponent (how much faster
  /// quick motion is than slow motion; 1.0 = linear), and whether the cursor
  /// follows the phone only while the clutch pad is held.
  double motionGain = 1.0;
  double motionAccel = 1.15;
  bool motionClutch = true;

  /// Volume up/down act as Prev/Next while presenting.
  bool volumeKeys = true;

  /// Which slideshow app's built-in laser the Laser button toggles.
  DeckApp deckApp = DeckApp.powerpoint;

  MotionConfig get motionConfig => MotionConfig(
        pointerGain: motionGain,
        ballisticsExponent: motionAccel,
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
  static const _kMotionAccel = 'motionAccel';
  static const _kMotionClutch = 'motionClutch';
  static const _kVolumeKeys = 'volumeKeys';
  static const _kDeckApp = 'deckApp';

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
    motionAccel = (prefs.getDouble(_kMotionAccel) ?? 1.15).clamp(1.0, 1.6);
    motionClutch = prefs.getBool(_kMotionClutch) ?? true;
    volumeKeys = prefs.getBool(_kVolumeKeys) ?? true;
    final deck = prefs.getInt(_kDeckApp);
    deckApp = deck != null && deck >= 0 && deck < DeckApp.values.length
        ? DeckApp.values[deck]
        : DeckApp.powerpoint;
    motion.config = motionConfig;
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
    motion.config = motionConfig;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kMotionGain, gain);
  }

  Future<void> setMotionAccel(double exponent) async {
    motionAccel = exponent;
    motion.config = motionConfig;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kMotionAccel, exponent);
  }

  Future<void> setMotionClutch(bool value) async {
    motionClutch = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kMotionClutch, value);
  }

  Future<void> setVolumeKeys(bool value) async {
    volumeKeys = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kVolumeKeys, value);
  }

  Future<void> setDeckApp(DeckApp app) async {
    deckApp = app;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kDeckApp, app.index);
  }

  /// The Laser button's keystroke for the current app and computer, or null
  /// when that app has none there (the button is then hidden).
  KeyStroke? get laserStroke => laserShortcut(deckApp, targetOs);

  Future<bool> ensurePermissions() => _transport.ensurePermissions();

  Future<String?> lastError() => _transport.lastError();

  Future<List<DeviceTarget>> bondedDevices() => _transport.bondedDevices();

  Future<void> connect(DeviceTarget target) => _transport.connect(target);

  Future<void> disconnect() => _transport.disconnect();

  /// Called from the app lifecycle observer on pause (stuck-key prevention).
  Future<void> releaseAll() => _transport.releaseAll();

  @override
  void dispose() {
    motion.dispose();
    _transport.dispose();
    super.dispose();
  }
}
