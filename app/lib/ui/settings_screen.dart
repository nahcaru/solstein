import 'package:flutter/material.dart';

import '../app_model.dart';
import '../hid/ime_keys.dart';
import '../hid/keymap.dart';
import '../hid/laser_shortcuts.dart';
import '../hid/layouts.dart';
import '../hid/shortcut_tables.dart';
import '../presenter/presenter_host.dart';
import 'motion_diagnostics_screen.dart';

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
              title: const Text('Computer\'s keyboard layout'),
              subtitle: const Text(
                  'Which physical keyboard the computer thinks is attached'),
              trailing: DropdownButton<HostLayoutId>(
                value: model.hostLayout.id,
                onChanged: (id) {
                  if (id != null) model.setHostLayout(id);
                },
                items: [
                  for (final layout in hostLayouts.values)
                    DropdownMenuItem(
                      value: layout.id,
                      child: Text(layout.label),
                    ),
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
            SwitchListTile(
              title: const Text('Haptics on click'),
              subtitle: const Text('Vibrate on tap, right, and middle click'),
              value: model.hapticsEnabled,
              onChanged: model.setHapticsEnabled,
            ),
            if (imeKeysFor(model.targetOs) != null)
              SwitchListTile(
                title: const Text('Show IME keys (かな / 英数)'),
                subtitle: const Text(
                    'Toggle the computer\'s own IME. Type romaji and the '
                    'computer converts it — keep your phone keyboard in English'),
                value: model.showImeKeys,
                onChanged: model.setShowImeKeys,
              ),
            ListTile(
              title: const Text('Keep screen awake'),
              subtitle: const Text(
                  'Stops the phone dimming while you use these modes'),
              trailing: DropdownButton<KeepAwake>(
                value: model.keepAwake,
                onChanged: (value) {
                  if (value != null) model.setKeepAwake(value);
                },
                items: [
                  // Display order; the persisted index order is separate.
                  for (final value in const [
                    KeepAwake.none,
                    KeepAwake.trackpad,
                    KeepAwake.presenter,
                    KeepAwake.media,
                    KeepAwake.both,
                  ])
                    DropdownMenuItem(value: value, child: Text(value.label)),
                ],
              ),
            ),
            const Divider(),
            const ListTile(
              title: Text('Presenter'),
              subtitle: Text('Laser pointer using the phone\'s motion sensors'),
            ),
            ListTile(
              title: const Text('Pointer speed'),
              subtitle: Slider(
                value: model.motionGain,
                min: 0.1,
                max: 2.0,
                divisions: 19,
                label: '${model.motionGain.toStringAsFixed(1)}×',
                onChanged: model.setMotionGain,
              ),
            ),
            ListTile(
              title: const Text('Acceleration'),
              subtitle: Slider(
                value: model.motionAccel,
                min: 1.0,
                max: 1.6,
                divisions: 12,
                label: model.motionAccel.toStringAsFixed(2),
                onChanged: model.setMotionAccel,
              ),
              trailing: const Tooltip(
                message: 'Higher: slow motion is finer, quick flicks reach '
                    'further. 1.0 is linear.',
                child: Icon(Icons.info_outline),
              ),
            ),
            SwitchListTile(
              title: const Text('Hold to move'),
              subtitle: const Text(
                  'The pointer follows the phone only while you hold the pad. '
                  'Off: it always follows, and holding the pad freezes it'),
              value: model.motionClutch,
              onChanged: model.setMotionClutch,
            ),
            ListTile(
              title: const Text('Slide app'),
              subtitle: Text(
                model.laserStroke == null
                    ? '${model.deckApp.label} has no laser pointer shortcut on '
                        'this computer, so the Laser button is hidden'
                    : 'The Laser button turns on ${model.deckApp.label}\'s '
                        'built-in laser pointer',
              ),
              trailing: DropdownButton<DeckApp>(
                value: model.deckApp,
                onChanged: (app) {
                  if (app != null) model.setDeckApp(app);
                },
                items: [
                  for (final app in DeckApp.values)
                    DropdownMenuItem(value: app, child: Text(app.label)),
                ],
              ),
            ),
            SwitchListTile(
              title: const Text('Volume keys'),
              subtitle: const Text(
                  'While presenting: volume up = Prev, volume down = Next, '
                  'without looking at the screen'),
              value: model.volumeKeys,
              onChanged: model.setVolumeKeys,
            ),
            ListTile(
              title: const Text('Motion sensors'),
              subtitle: const Text('Sample rate, gyro bias, recalibrate'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => MotionDiagnosticsScreen(session: model.motion),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
