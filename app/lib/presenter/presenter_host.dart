/// Phone-side facilities that make presenting possible without looking at the
/// screen: keeping it awake and reading the volume keys. Behind an interface
/// so the presenter surface stays testable without a device.
library;

import 'dart:async';

import 'package:flutter/services.dart';

import '../core/control_mode.dart';

enum VolumeKey { up, down }

/// One edge of a captured hardware volume key. [pressed] is false on release.
/// Holding the key sends a single press, not repeats; a consumer that wants
/// auto-repeat starts it on the press and stops it on the release.
class VolumeKeyEvent {
  const VolumeKeyEvent(this.key, {required this.pressed});

  final VolumeKey key;
  final bool pressed;
}

/// Which control modes hold the screen on. Presenter is the default: a phone
/// that dims out mid-talk pauses the app and stops the motion sensors.
enum KeepAwake {
  none('None'),
  trackpad('Trackpad'),
  presenter('Presenter'),
  both('All modes'),
  // Appended, not inserted: the setting is persisted by index.
  media('Media');

  const KeepAwake(this.label);

  final String label;

  bool appliesTo(ControlMode mode) => switch (this) {
        KeepAwake.none => false,
        KeepAwake.trackpad => mode == ControlMode.trackpad,
        KeepAwake.presenter => mode == ControlMode.presenter,
        KeepAwake.media => mode == ControlMode.media,
        KeepAwake.both => true,
      };
}

abstract interface class PresenterHost {
  /// Keeps the screen on; see [KeepAwake] for when the app asks for it.
  Future<void> setKeepScreenOn(bool on);

  /// While captured, the volume keys are delivered on [volumeKeys] instead of
  /// changing the system volume. Release it when leaving presenter mode.
  Future<void> setVolumeKeysCaptured(bool on);

  Stream<VolumeKeyEvent> get volumeKeys;
}

/// Android implementation (PresenterBridge.kt).
class MethodChannelPresenterHost implements PresenterHost {
  static const _channel = MethodChannel('dev.taira.solstein/presenter');
  static const _keys = EventChannel('dev.taira.solstein/presenter_keys');

  @override
  Future<void> setKeepScreenOn(bool on) =>
      _channel.invokeMethod<void>('setKeepScreenOn', on).catchError((_) {});

  @override
  Future<void> setVolumeKeysCaptured(bool on) => _channel
      .invokeMethod<void>('setVolumeKeysCaptured', on)
      .catchError((_) {});

  @override
  Stream<VolumeKeyEvent> get volumeKeys =>
      _keys.receiveBroadcastStream().map((e) {
        // "up" / "down" on the press, "up:release" / "down:release" on lift.
        final name = e as String;
        return VolumeKeyEvent(
          name.startsWith('up') ? VolumeKey.up : VolumeKey.down,
          pressed: !name.endsWith(':release'),
        );
      });
}
