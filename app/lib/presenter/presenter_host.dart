/// Phone-side facilities that make presenting possible without looking at the
/// screen: keeping it awake and reading the volume keys. Behind an interface
/// so the presenter surface stays testable without a device.
library;

import 'dart:async';

import 'package:flutter/services.dart';

enum VolumeKey { up, down }

abstract interface class PresenterHost {
  /// Keeps the screen on. A phone that dims out pauses the app, which stops
  /// the motion sensors mid-talk.
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
