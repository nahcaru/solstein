/// Phone-side facilities that make presenting possible without looking at the
/// screen: keeping it awake and reading the volume keys. Behind an interface
/// so the presenter surface stays testable without a device.
library;

import 'dart:async';

import 'package:flutter/services.dart';

enum VolumeKey { up, down }

/// Which control modes hold the screen on. Presenter is the default: a phone
/// that dims out mid-talk pauses the app and stops the motion sensors.
enum KeepAwake {
  none('None'),
  trackpad('Trackpad'),
  presenter('Presenter'),
  both('Both');

  const KeepAwake(this.label);

  final String label;

  bool appliesTo({required bool presenting}) => switch (this) {
        KeepAwake.none => false,
        KeepAwake.trackpad => !presenting,
        KeepAwake.presenter => presenting,
        KeepAwake.both => true,
      };
}

abstract interface class PresenterHost {
  /// Keeps the screen on; see [KeepAwake] for when the app asks for it.
  Future<void> setKeepScreenOn(bool on);

  /// While captured, the volume keys are delivered on [volumeKeys] instead of
  /// changing the system volume. Release it when leaving presenter mode.
  Future<void> setVolumeKeysCaptured(bool on);

  Stream<VolumeKey> get volumeKeys;
}

/// Android implementation (PresenterBridge.kt).
class MethodChannelPresenterHost implements PresenterHost {
  static const _channel = MethodChannel('dev.taira.helm/presenter');
  static const _keys = EventChannel('dev.taira.helm/presenter_keys');

  @override
  Future<void> setKeepScreenOn(bool on) =>
      _channel.invokeMethod<void>('setKeepScreenOn', on).catchError((_) {});

  @override
  Future<void> setVolumeKeysCaptured(bool on) => _channel
      .invokeMethod<void>('setVolumeKeysCaptured', on)
      .catchError((_) {});

  @override
  Stream<VolumeKey> get volumeKeys => _keys.receiveBroadcastStream().map(
        (e) => e == 'up' ? VolumeKey.up : VolumeKey.down,
      );
}
