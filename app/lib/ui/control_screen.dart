import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_model.dart';
import '../core/control_mode.dart';
import '../core/input_sink.dart';
import 'keyboard_screen.dart';
import 'media_surface.dart';
import 'presenter_surface.dart';
import 'settings_screen.dart';
import 'trackpad_surface.dart';

/// Connected-state shell: trackpad with an optional keyboard drawer below.
/// Adapts to the sink's capabilities, never to the transport type.
class ControlScreen extends StatefulWidget {
  const ControlScreen({super.key, required this.model});

  final AppModel model;

  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen>
    with WidgetsBindingObserver {
  bool _keyboardVisible = false;
  ControlMode _mode = ControlMode.trackpad;

  /// Settings is pushed over this screen; the presenter underneath must go
  /// quiet while it is open.
  bool _covered = false;

  // The landscape and portrait branches below build structurally different
  // widget trees (different Scaffold body shape, different ancestor
  // chain), so without a stable identity, rotating mid-build disposes the
  // pointer surface and keyboard drawer and creates fresh ones instead of
  // just relaying them out. Mid-gesture that drops a held presenter clutch
  // and can throw when the finger lifts against an already-disposed pad
  // (_PadButtonState in presenter_surface.dart). A GlobalKey lets Flutter
  // find and reparent the existing Element across the two shapes instead.
  // (It doesn't defeat the *intentional* dispose when _mode toggles the
  // surface's type between TrackpadSurface, PresenterSurface and
  // MediaSurface — a GlobalKey only preserves identity when the widget
  // type at that key is unchanged.)
  final _pointerSurfaceKey = GlobalKey();
  final _keyboardKey = GlobalKey();

  // Landscape gives the rail the full screen edge instead of a status/nav
  // bar-adjacent AppBar, so it hides both system bars there — a swipe from
  // the edge still reveals them (sticky, not fully locked out). Portrait
  // restores them. Tracked so the platform call only fires on an actual
  // orientation change, not every build. This screen stays mounted under a
  // pushed SettingsScreen, so it also applies there while Settings is on
  // top and Settings is in landscape — bars restore fully on returning to
  // portrait or leaving this screen either way.
  //
  // This app's default targetSdkVersion (36, set by the Flutter Gradle
  // plugin) means Android enforces edge-to-edge content layout with no
  // opt-out — but hiding the bars themselves is a separate axis from that
  // layout, so immersiveSticky still applies here; confirmed working on
  // Android 17. Don't add android:windowOptOutEdgeToEdgeEnforcement to
  // styles.xml — that's for disabling edge-to-edge layout, unrelated to
  // this, and can crash on 16+ without versioned resources.
  Orientation? _systemUiOrientation;

  void _syncSystemUi(Orientation orientation) {
    if (_systemUiOrientation == orientation) return;
    _systemUiOrientation = orientation;
    if (orientation == Orientation.landscape) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
          overlays: SystemUiOverlay.values);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncSystemUi(MediaQuery.orientationOf(context));
  }

  bool _keepingAwake = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  // The native side clears the flag whenever the app pauses (MainActivity),
  // so coming back has to ask for it again.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _keepingAwake) {
      widget.model.presenterHost.setKeepScreenOn(true);
    }
  }

  /// Holds the screen on when the setting covers the mode on show. Called
  /// from build so a settings change or mode toggle takes effect at once.
  void _syncKeepAwake(AppModel model, ControlMode? mode) {
    final want = mode != null && model.keepAwake.appliesTo(mode);
    if (want == _keepingAwake) return;
    _keepingAwake = want;
    model.presenterHost.setKeepScreenOn(want);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_keepingAwake) widget.model.presenterHost.setKeepScreenOn(false);
    // Leaving this screen (back to the device list) restores both bars,
    // regardless of which orientation the phone was left in.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
        overlays: SystemUiOverlay.values);
    super.dispose();
  }

  Future<void> _openSettings(AppModel model) async {
    setState(() => _covered = true);
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SettingsScreen(model: model)),
    );
    if (mounted) setState(() => _covered = false);
  }

  Widget _backButton(AppModel model) => IconButton(
        // Back to the device list; the Bluetooth link itself stays up —
        // connection state is managed from the OS settings, not Helm.
        icon: const Icon(Icons.arrow_back),
        tooltip: 'Back to device list',
        onPressed: model.closeControl,
      );

  static const _modeIcons = {
    ControlMode.trackpad: Icons.touch_app,
    ControlMode.presenter: Icons.ads_click,
    ControlMode.media: Icons.music_note,
  };

  static const _modeLabels = {
    ControlMode.trackpad: 'Trackpad',
    ControlMode.presenter: 'Presenter',
    ControlMode.media: 'Media',
  };

  /// Modes the sink can serve. Gated on capabilities, never on the transport.
  List<ControlMode> _availableModes(Set<Capability> capabilities) => [
        if (capabilities.contains(Capability.pointer)) ...[
          ControlMode.trackpad,
          ControlMode.presenter,
        ],
        if (capabilities.contains(Capability.mediaKeys)) ControlMode.media,
      ];

  /// The mode actually showing: the chosen one if the sink can still serve
  /// it, else the first it can (null if it serves none).
  ControlMode? _effectiveMode(Set<Capability> capabilities) {
    final modes = _availableModes(capabilities);
    if (modes.contains(_mode)) return _mode;
    return modes.isEmpty ? null : modes.first;
  }

  List<Widget> _headerActions(AppModel model, Set<Capability> capabilities) =>
      [
        if (_availableModes(capabilities).length > 1)
          PopupMenuButton<ControlMode>(
            icon: Icon(_modeIcons[_effectiveMode(capabilities)]),
            tooltip: 'Mode',
            initialValue: _effectiveMode(capabilities),
            onSelected: (mode) => setState(() => _mode = mode),
            itemBuilder: (_) => [
              for (final mode in _availableModes(capabilities))
                CheckedPopupMenuItem(
                  value: mode,
                  checked: mode == _effectiveMode(capabilities),
                  child: Text(_modeLabels[mode]!),
                ),
            ],
          ),
        if (capabilities.contains(Capability.keyboard))
          IconButton(
            icon: Icon(
              _keyboardVisible ? Icons.keyboard_hide : Icons.keyboard,
            ),
            tooltip: 'Keyboard',
            onPressed: () =>
                setState(() => _keyboardVisible = !_keyboardVisible),
          ),
        IconButton(
          icon: const Icon(Icons.settings),
          tooltip: 'Settings',
          onPressed: () => _openSettings(model),
        ),
      ];

  Widget _pointerSurface(AppModel model, ControlMode mode) => Padding(
        padding: const EdgeInsets.all(12),
        child: switch (mode) {
          ControlMode.presenter => PresenterSurface(
              key: _pointerSurfaceKey,
              sink: model.sink,
              session: model.motion,
              host: model.presenterHost,
              clutch: model.motionClutch,
              volumeKeys: model.volumeKeys,
              laser: model.laserStroke,
              active: !_covered,
              hapticsEnabled: model.hapticsEnabled,
            ),
          ControlMode.media => MediaSurface(
              key: _pointerSurfaceKey,
              sink: model.sink,
              host: model.presenterHost,
              active: !_covered,
              hapticsEnabled: model.hapticsEnabled,
              // The keys are ordinary keyboard strokes, so they need that
              // capability; without it the row is simply absent.
              player: model.sink.capabilities.contains(Capability.keyboard)
                  ? model.playerKeys
                  : null,
            ),
          ControlMode.trackpad => TrackpadSurface(
              key: _pointerSurfaceKey,
              sink: model.sink,
              config: model.gestureConfig,
              hapticsEnabled: model.hapticsEnabled,
            ),
        },
      );

  Widget _keyboard(AppModel model) => KeyboardScreen(
        key: _keyboardKey,
        sink: model.sink,
        targetOs: model.targetOs,
        hostLayout: model.hostLayout,
        showImeKeys: model.showImeKeys,
      );

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    final capabilities = model.sink.capabilities;
    final mode = _effectiveMode(capabilities);
    _syncKeepAwake(model, mode);
    final showKeyboard =
        _keyboardVisible && capabilities.contains(Capability.keyboard);

    if (MediaQuery.orientationOf(context) == Orientation.landscape) {
      return Scaffold(
        // The on-screen keyboard opening for the IME text field shouldn't
        // shrink this layout: in the rail that squeezes the bottom three
        // buttons toward the back button and can overflow (a landscape
        // phone leaves little height once the keyboard's height is
        // subtracted). The rail and deck stay put; only the keyboard
        // drawer's own TextField needs to stay reachable, and it already
        // sits above the key grid, not near the bottom.
        resizeToAvoidBottomInset: false,
        body: SafeArea(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _HeaderRail(
                back: _backButton(model),
                actions: _headerActions(model, capabilities),
              ),
              Expanded(
                child: ListenableBuilder(
                  listenable: model,
                  // The keyboard sits beside the pad: stacked below, it
                  // would leave no height for either on a landscape screen.
                  builder: (context, _) => Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (mode != null)
                        Expanded(
                          flex: 55,
                          child: _pointerSurface(model, mode),
                        ),
                      if (showKeyboard)
                        Expanded(
                          flex: 45,
                          child: SingleChildScrollView(
                            child: _keyboard(model),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        // No title, matching the landscape rail, which has never shown one.
        leading: _backButton(model),
        actions: _headerActions(model, capabilities),
      ),
      body: ListenableBuilder(
        listenable: model,
        builder: (context, _) => Column(
          children: [
            if (mode != null)
              Expanded(child: _pointerSurface(model, mode)),
            if (showKeyboard) _keyboard(model),
          ],
        ),
      ),
    );
  }
}

/// Landscape stand-in for the app bar: the same buttons down the left edge,
/// matching an AppBar's leading/actions split — back at the top (where
/// leading sits at the reading-start edge), the rest at the bottom (where
/// actions sit at the far edge).
class _HeaderRail extends StatelessWidget {
  const _HeaderRail({required this.back, required this.actions});

  final Widget back;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.appBarTheme.backgroundColor ?? theme.colorScheme.surface,
      child: SizedBox(
        width: 64,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              back,
              Column(mainAxisSize: MainAxisSize.min, children: actions),
            ],
          ),
        ),
      ),
    );
  }
}
