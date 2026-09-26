import 'package:flutter/material.dart';

import '../app_model.dart';
import '../core/input_sink.dart';
import 'keyboard_screen.dart';
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

class _ControlScreenState extends State<ControlScreen> {
  bool _keyboardVisible = false;
  bool _presenterVisible = false;

  /// Settings is pushed over this screen; the presenter underneath must go
  /// quiet while it is open.
  bool _covered = false;

  Future<void> _openSettings(AppModel model) async {
    setState(() => _covered = true);
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SettingsScreen(model: model)),
    );
    if (mounted) setState(() => _covered = false);
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    final capabilities = model.sink.capabilities;
    return Scaffold(
      appBar: AppBar(
        // Back to the device list; the Bluetooth link itself stays up —
        // connection state is managed from the OS settings, not Helm.
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back to device list',
          onPressed: model.closeControl,
        ),
        title: const Text('Helm'),
        actions: [
          if (capabilities.contains(Capability.pointer))
            IconButton(
              icon: Icon(
                _presenterVisible ? Icons.touch_app : Icons.ads_click,
              ),
              tooltip: _presenterVisible ? 'Trackpad' : 'Presenter',
              onPressed: () =>
                  setState(() => _presenterVisible = !_presenterVisible),
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
        ],
      ),
      body: ListenableBuilder(
        listenable: model,
        builder: (context, _) => Column(
          children: [
            if (capabilities.contains(Capability.pointer))
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: _presenterVisible
                      ? PresenterSurface(
                          sink: model.sink,
                          session: model.motion,
                          host: model.presenterHost,
                          clutch: model.motionClutch,
                          volumeKeys: model.volumeKeys,
                          laser: model.laserStroke,
                          active: !_covered,
                          hapticsEnabled: model.hapticsEnabled,
                        )
                      : TrackpadSurface(
                          sink: model.sink,
                          config: model.gestureConfig,
                          hapticsEnabled: model.hapticsEnabled,
                        ),
                ),
              ),
            if (_keyboardVisible && capabilities.contains(Capability.keyboard))
              KeyboardScreen(
                sink: model.sink,
                targetOs: model.targetOs,
                hostLayout: model.hostLayout,
                showImeKeys: model.showImeKeys,
              ),
          ],
        ),
      ),
    );
  }
}
