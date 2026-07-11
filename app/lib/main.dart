import 'package:flutter/material.dart';

import 'app_model.dart';
import 'core/input_sink.dart';
import 'ui/control_screen.dart';
import 'ui/pairing_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final model = AppModel();
  model.load();
  runApp(HelmApp(model: model));
}

class HelmApp extends StatefulWidget {
  const HelmApp({super.key, required this.model});

  final AppModel model;

  @override
  State<HelmApp> createState() => _HelmAppState();
}

class _HelmAppState extends State<HelmApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Stuck-key prevention: neutralize the host whenever the app leaves
    // the foreground mid-gesture.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      widget.model.releaseAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Helm',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: ListenableBuilder(
        listenable: widget.model,
        builder: (context, _) => widget.model.sinkState == SinkState.connected &&
                widget.model.showControl
            ? ControlScreen(model: widget.model)
            : PairingScreen(model: widget.model),
      ),
    );
  }
}
