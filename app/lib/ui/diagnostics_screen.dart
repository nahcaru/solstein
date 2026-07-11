import 'package:flutter/material.dart';

import '../app_model.dart';

/// Shown when the Bluetooth stack rejects the HID setup — most commonly
/// OEM builds that disable the HID Device profile (docs/architecture.md:
/// this must inform, never crash).
class DiagnosticsScreen extends StatelessWidget {
  const DiagnosticsScreen({super.key, required this.model});

  final AppModel model;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Diagnostics')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: FutureBuilder<String?>(
          future: model.lastError(),
          builder: (context, snapshot) => ListView(
            children: [
              const Icon(Icons.bluetooth_disabled, size: 56),
              const SizedBox(height: 16),
              Text(
                'Bluetooth HID unavailable',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              if (snapshot.data != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(snapshot.data!),
                  ),
                ),
              const SizedBox(height: 12),
              const Text(
                'Helm works by emulating a Bluetooth trackpad and keyboard '
                '(the HID Device profile). A few manufacturers disable this '
                'profile in their Android build.\n\n'
                'Things to try:\n'
                '• Toggle Bluetooth off and on, then reopen Helm\n'
                '• Check for a system update\n'
                '• If the error persists, this phone\'s Bluetooth stack '
                'likely cannot host HID — a future Helm release adds a '
                'BLE + desktop-helper mode that works everywhere.',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
