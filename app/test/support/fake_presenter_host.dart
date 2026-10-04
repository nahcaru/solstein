import 'dart:async';

import 'package:solstein/presenter/presenter_host.dart';

/// Records what presenter mode asks of the phone and lets a test press keys.
class FakePresenterHost implements PresenterHost {
  final _keys = StreamController<VolumeKeyEvent>.broadcast(sync: true);
  bool keepScreenOn = false;
  bool volumeKeysCaptured = false;
  final calls = <String>[];

  @override
  Future<void> setKeepScreenOn(bool on) async {
    keepScreenOn = on;
    calls.add('keepScreenOn:$on');
  }

  @override
  Future<void> setVolumeKeysCaptured(bool on) async {
    volumeKeysCaptured = on;
    calls.add('volumeKeys:$on');
  }

  @override
  Stream<VolumeKeyEvent> get volumeKeys => _keys.stream;

  void press(VolumeKey key) => _keys.add(VolumeKeyEvent(key, pressed: true));

  void release(VolumeKey key) =>
      _keys.add(VolumeKeyEvent(key, pressed: false));
}
