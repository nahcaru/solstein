import 'package:flutter/material.dart';

import '../app_model.dart';
import '../core/input_sink.dart';
import 'keyboard_screen.dart';
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
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => SettingsScreen(model: model),
              ),
            ),
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
                  child: TrackpadSurface(
                    sink: model.sink,
                    config: model.gestureConfig,
                  ),
                ),
              ),
            if (_keyboardVisible && capabilities.contains(Capability.keyboard))
              KeyboardScreen(sink: model.sink),
          ],
        ),
      ),
    );
  }
}
