import 'package:flutter/material.dart';

import '../app_model.dart';
import '../core/input_sink.dart';
import 'diagnostics_screen.dart';

/// Entry screen: permissions → bonded-device list → connect.
class PairingScreen extends StatefulWidget {
  const PairingScreen({super.key, required this.model});

  final AppModel model;

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  List<DeviceTarget> _devices = const [];
  bool _permissionsGranted = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    // Re-query the list whenever connection state changes, so a host
    // appearing/disconnecting shows up without a manual pull-to-refresh.
    widget.model.addListener(_onModelChanged);
    _init();
  }

  @override
  void dispose() {
    widget.model.removeListener(_onModelChanged);
    super.dispose();
  }

  void _onModelChanged() {
    if (_permissionsGranted) _refresh();
  }

  Future<void> _init() async {
    final granted = await widget.model.ensurePermissions();
    if (!mounted) return;
    setState(() => _permissionsGranted = granted);
    if (granted) await _refresh();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _refresh() async {
    final devices = await widget.model.bondedDevices();
    // Paired-but-absent devices (old laptops, earbuds…) are noise here:
    // only hosts with a live Bluetooth link are actionable.
    if (mounted) {
      setState(
          () => _devices = devices.where((d) => d.connected).toList());
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.model.sinkState;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Solstein'),
        actions: [
          if (state == SinkState.error)
            IconButton(
              icon: const Icon(Icons.error_outline, color: Colors.orange),
              tooltip: 'Diagnostics',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => DiagnosticsScreen(model: widget.model),
                ),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : !_permissionsGranted
              ? _PermissionsPrompt(onRetry: _init)
              : RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (state == SinkState.connecting)
                        const ListTile(
                          leading: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          title: Text('Connecting…'),
                        ),
                      Text(
                        'Connected computers',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      if (_devices.isEmpty)
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Text(
                              'No connected computers.\n\n'
                              'Not paired yet? Keep Solstein open and pair this '
                              'phone from the computer\'s Bluetooth settings '
                              '(it appears under the phone\'s own name).\n\n'
                              'Already paired? Connect to this phone from '
                              'the computer\'s Bluetooth menu, then pull '
                              'down here to refresh.',
                            ),
                          ),
                        ),
                      for (final device in _devices)
                        Card(
                          child: Builder(builder: (context) {
                            final isCurrent = state == SinkState.connected &&
                                device.id == widget.model.connectedDeviceId;
                            return ListTile(
                              leading: const Icon(Icons.computer),
                              title: Text(device.name),
                              subtitle: Text(
                                  isCurrent ? 'Controlling now' : device.id),
                              trailing: isCurrent
                                  ? const Icon(Icons.chevron_right)
                                  : null,
                              // Current host → reopen the trackpad; any
                              // other → switch the HID link to it.
                              onTap: isCurrent
                                  ? widget.model.openControl
                                  : () => widget.model.connect(device),
                            );
                          }),
                        ),
                    ],
                  ),
                ),
    );
  }
}

class _PermissionsPrompt extends StatelessWidget {
  const _PermissionsPrompt({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.bluetooth_disabled, size: 56),
            const SizedBox(height: 16),
            const Text(
              'Solstein needs Bluetooth permissions to act as a trackpad '
              'and keyboard for your computer.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onRetry,
              child: const Text('Grant permissions'),
            ),
          ],
        ),
      ),
    );
  }
}
