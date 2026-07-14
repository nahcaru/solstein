import 'package:flutter/material.dart';

import '../app_model.dart';
import '../hid/shortcut_tables.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.model});

  final AppModel model;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListenableBuilder(
        listenable: model,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ListTile(
              title: const Text('Computer runs'),
              subtitle: const Text(
                  'Guessed from the computer\'s name on first connect; '
                  'your choice here is remembered per computer'),
              trailing: DropdownButton<TargetOs>(
                value: model.targetOs,
                onChanged: (os) {
                  if (os != null) model.setTargetOs(os);
                },
                items: const [
                  DropdownMenuItem(
                      value: TargetOs.macos, child: Text('macOS')),
                  DropdownMenuItem(
                      value: TargetOs.windows, child: Text('Windows')),
                  DropdownMenuItem(
                      value: TargetOs.linux, child: Text('Linux (GNOME)')),
                ],
              ),
            ),
            const Divider(),
            ListTile(
              title: const Text('Pointer speed'),
              subtitle: Slider(
                value: model.pointerGain,
                min: 0.1,
                max: 2.0,
                divisions: 19,
                label: '${model.pointerGain.toStringAsFixed(1)}×',
                onChanged: model.setPointerGain,
              ),
            ),
            ListTile(
              title: const Text('Scroll speed'),
              subtitle: Slider(
                value: model.scrollGain,
                min: 0.1,
                max: 2.0,
                divisions: 19,
                label: '${model.scrollGain.toStringAsFixed(1)}×',
                onChanged: model.setScrollGain,
              ),
            ),
            SwitchListTile(
              title: const Text('Natural scrolling'),
              subtitle: const Text(
                  'Content and spaces follow your fingers'),
              value: model.naturalScroll,
              onChanged: model.setNaturalScroll,
            ),
          ],
        ),
      ),
    );
  }
}
