import 'dart:async';

import 'package:solstein/motion/motion_sample.dart';
import 'package:solstein/motion/motion_source.dart';

/// Scriptable [MotionSource]: tests push samples or errors by hand.
class FakeMotionSource implements MotionSource {
  final _controller = StreamController<MotionSample>.broadcast(sync: true);
  int startCount = 0;
  int stopCount = 0;
  bool get running => startCount > stopCount;

  @override
  Stream<MotionSample> get samples => _controller.stream;

  @override
  Future<void> start() async => startCount++;

  @override
  Future<void> stop() async => stopCount++;

  void emit(MotionSample s) => _controller.add(s);
  void emitError(Object e) => _controller.addError(e);
}
