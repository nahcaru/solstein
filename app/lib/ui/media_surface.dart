import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:vibration/vibration.dart';

import '../core/input_event.dart';
import '../core/input_sink.dart';
import '../hid/keymap.dart';
import '../hid/player_shortcuts.dart';
import '../presenter/presenter_host.dart';
import 'key_repeat.dart';
import 'trackpad_surface.dart' show fireHaptic, hapticForClick;

/// Media control mode: a couch remote for the host's media keys.
///
/// Large play/pause, previous/next and volume buttons. The phone's own volume
/// keys are captured while this is showing and drive the host's volume
/// instead, so volume works without looking at the screen. Holding either
/// volume control repeats at the same pace as a held backspace.
class MediaSurface extends StatefulWidget {
  const MediaSurface({
    super.key,
    required this.sink,
    required this.host,
    required this.active,
    required this.hapticsEnabled,
    this.player,
  });

  final InputSink sink;
  final PresenterHost host;

  /// False while something is covering this (Settings): the volume keys go
  /// back to the phone.
  final bool active;
  final bool hapticsEnabled;

  /// Keys for the seek, captions and fullscreen row; null hides the row.
  final PlayerShortcuts? player;

  @override
  State<MediaSurface> createState() => _MediaSurfaceState();
}

class _MediaSurfaceState extends State<MediaSurface>
    with WidgetsBindingObserver {
  final _hardwareRepeater = KeyRepeater();
  StreamSubscription<VolumeKeyEvent>? _volumeKeySub;
  VolumeKey? _hardwareHeld;
  bool _attached = false;
  late final Future<bool> _amplitudeSupported = Vibration.hasAmplitudeControl();

  static final _tap = hapticForClick(Button.left, down: true);

  void _buzz() {
    if (!widget.hapticsEnabled) return;
    _amplitudeSupported
        .then((supported) =>
            fireHaptic(_tap, amplitudeSupported: supported))
        .catchError((_) {});
  }

  void _send(MediaKey key) => widget.sink.send(MediaTap(key));

  void _tapStroke(KeyStroke stroke) {
    widget.sink.send(KeyInput(stroke.usage, stroke.modifiers, down: true));
    widget.sink.send(KeyInput(stroke.usage, stroke.modifiers, down: false));
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.active) _attach();
  }

  @override
  void didUpdateWidget(MediaSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) {
      widget.active ? _attach() : _detach();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hardwareRepeater.dispose();
    _detach();
    super.dispose();
  }

  // Dropped on deactivate rather than dispose: when the mode changes, the
  // incoming surface's initState runs before this one's dispose, so a release
  // in dispose would land after (and undo) the new surface's capture.
  @override
  void deactivate() {
    _detach();
    super.deactivate();
  }

  // Reparenting under a GlobalKey (rotation) deactivates then reactivates.
  @override
  void activate() {
    super.activate();
    if (widget.active) _attach();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        if (widget.active) _attach();
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        // The native side drops the capture when the app pauses; match it so
        // a key held across the switch can't keep repeating.
        _detach();
    }
  }

  void _attach() {
    if (_attached) return;
    _attached = true;
    widget.host.setVolumeKeysCaptured(true);
    _volumeKeySub = widget.host.volumeKeys.listen(_onVolumeKey);
  }

  void _detach() {
    if (!_attached) return;
    _attached = false;
    _volumeKeySub?.cancel();
    _volumeKeySub = null;
    _hardwareRepeater.release();
    _hardwareHeld = null;
    widget.host.setVolumeKeysCaptured(false);
  }

  void _onVolumeKey(VolumeKeyEvent event) {
    if (event.pressed) {
      _buzz();
      _hardwareHeld = event.key;
      final key = event.key == VolumeKey.up
          ? MediaKey.volumeUp
          : MediaKey.volumeDown;
      _hardwareRepeater.press(() => _send(key));
    } else if (_hardwareHeld == event.key) {
      // Lifting the other key must not cut short the one still held.
      _hardwareHeld = null;
      _hardwareRepeater.release();
    }
  }

  Widget _button(
    String tooltip,
    IconData icon,
    MediaKey key, {
    bool repeat = false,
    double iconSize = 40,
    int flex = 1,
  }) =>
      Expanded(
        flex: flex,
        child: _MediaButton(
          tooltip: tooltip,
          icon: icon,
          iconSize: iconSize,
          repeat: repeat,
          onPress: _buzz,
          onFire: () => _send(key),
        ),
      );

  Widget _strokeButton(String tooltip, IconData icon, KeyStroke stroke) =>
      Expanded(
        child: _MediaButton(
          tooltip: tooltip,
          icon: icon,
          iconSize: 32,
          repeat: false,
          onPress: _buzz,
          onFire: () => _tapStroke(stroke),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final transport = [
      _button('Previous', Icons.skip_previous, MediaKey.prevTrack),
      _button('Play/Pause', Symbols.play_pause, MediaKey.playPause,
          iconSize: 56, flex: 2),
      _button('Next', Icons.skip_next, MediaKey.nextTrack),
    ];
    final volume = [
      _button('Volume down', Icons.volume_down, MediaKey.volumeDown,
          repeat: true),
      _button('Mute', Icons.volume_off, MediaKey.mute),
      _button('Volume up', Icons.volume_up, MediaKey.volumeUp, repeat: true),
    ];
    final player = widget.player;
    final playerRow = player == null
        ? null
        : [
            _strokeButton('Captions', Icons.closed_caption, player.captions),
            _strokeButton('Seek back', Icons.fast_rewind, player.back),
            _strokeButton('Seek forward', Icons.fast_forward, player.forward),
            _strokeButton('Fullscreen', Icons.fullscreen, player.fullscreen),
          ];
    const gap = 12.0;

    Widget row(List<Widget> buttons) => Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < buttons.length; i++) ...[
              if (i > 0) const SizedBox(width: gap),
              buttons[i],
            ],
          ],
        );

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth > constraints.maxHeight;
        // Playback on top, the optional player row under it, volume last.
        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 3, child: row(transport)),
                    if (playerRow != null) ...[
                      const SizedBox(height: gap),
                      Expanded(flex: 2, child: row(playerRow)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: gap),
              Expanded(flex: 2, child: row(volume)),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: 3, child: row(transport)),
            if (playerRow != null) ...[
              const SizedBox(height: gap),
              Expanded(flex: 2, child: row(playerRow)),
            ],
            const SizedBox(height: gap),
            Expanded(flex: 2, child: row(volume)),
          ],
        );
      },
    );
  }
}

/// A big remote button. Fires on the press itself (raw pointer events, like
/// the trackpad's buttons) so there is no tap-recognition delay; with
/// [repeat] a held press keeps firing until the finger lifts.
class _MediaButton extends StatefulWidget {
  const _MediaButton({
    required this.tooltip,
    required this.icon,
    required this.iconSize,
    required this.repeat,
    required this.onPress,
    required this.onFire,
  });

  final String tooltip;
  final IconData icon;
  final double iconSize;
  final bool repeat;

  /// Once per touch, not per repeat: a held button must not buzz 25 times a
  /// second.
  final VoidCallback onPress;
  final VoidCallback onFire;

  @override
  State<_MediaButton> createState() => _MediaButtonState();
}

class _MediaButtonState extends State<_MediaButton> {
  final _repeater = KeyRepeater();
  final _pointers = <int>{};
  bool _down = false;

  void _press() {
    if (!mounted) return;
    setState(() => _down = true);
    widget.onPress();
    if (widget.repeat) {
      _repeater.press(widget.onFire);
    } else {
      widget.onFire();
    }
  }

  void _release() {
    _repeater.release();
    // The layout can swap between portrait and landscape shapes mid-press,
    // disposing this button while the finger's pointer route still points at
    // it.
    if (mounted && _down) setState(() => _down = false);
  }

  // Only the first finger presses and only the last lifting releases, so a
  // second finger can neither double-fire nor cut a held repeat short.
  void _pointerDown(int pointer) {
    if (_pointers.add(pointer) && _pointers.length == 1) _press();
  }

  void _pointerUp(int pointer) {
    if (_pointers.remove(pointer) && _pointers.isEmpty) _release();
  }

  @override
  void dispose() {
    _repeater.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: widget.tooltip,
      child: Semantics(
        button: true,
        label: widget.tooltip,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (e) => _pointerDown(e.pointer),
          onPointerUp: (e) => _pointerUp(e.pointer),
          onPointerCancel: (e) => _pointerUp(e.pointer),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: _down
                  ? scheme.primaryContainer
                  : scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Center(
              child: Icon(
                widget.icon,
                size: widget.iconSize,
                color: _down ? scheme.onPrimaryContainer : scheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
