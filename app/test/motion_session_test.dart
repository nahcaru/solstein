import 'package:flutter_test/flutter_test.dart';
import 'package:helm/core/input_event.dart';
import 'package:helm/motion/motion_config.dart';
import 'package:helm/motion/motion_sample.dart';
import 'package:helm/motion/motion_session.dart';
import 'package:helm/motion/motion_source.dart';

import 'support/fake_motion_source.dart';

MotionSample sample(int ms, {double gz = 0}) => MotionSample(
      gyroX: 0,
      gyroY: 0,
      gyroZ: gz,
      accelX: 0,
      accelY: 0,
      accelZ: 9.81,
      timestamp: Duration(milliseconds: ms),
    );

void feed(FakeMotionSource source, {double gz = 0, int ms = 500, int from = 0}) {
  for (var t = 0; t <= ms; t += 10) {
    source.emit(sample(from + t, gz: gz));
  }
}

/// A source whose start() fails, like a phone with no gyroscope.
class FailingSource implements MotionSource {
  @override
  Stream<MotionSample> get samples => const Stream.empty();
  @override
  Future<void> start() async => throw StateError('no gyroscope');
  @override
  Future<void> stop() async {}
}

void main() {
  late FakeMotionSource source;
  late List<InputEvent> out;
  late MotionSession session;

  setUp(() {
    source = FakeMotionSource();
    out = [];
    session = MotionSession(source: source, emit: out.add);
  });

  tearDown(() => session.dispose());

  test('the first attach starts the sensors, the last detach stops them',
      () async {
    await session.attach();
    await session.attach(); // e.g. diagnostics opened over the presenter
    expect(source.startCount, 1);
    expect(session.active, isTrue);

    session.detach();
    expect(source.running, isTrue, reason: 'one user is still attached');
    session.detach();
    expect(source.running, isFalse);
    expect(session.active, isFalse);
  });

  test('detach without attach is a no-op, and a later attach restarts',
      () async {
    session.detach();
    expect(source.stopCount, 0);
    await session.attach();
    session.detach();
    await session.attach();
    expect(source.startCount, 2);
    expect(source.running, isTrue);
  });

  test('samples drive the shared engine and its output is emitted', () async {
    await session.attach();
    session.emitAll(session.engine.engage());
    feed(source, gz: -1.0);
    expect(out.whereType<PointerMove>(), isNotEmpty);
    expect(out.whereType<PointerMove>().every((e) => e.dx > 0), isTrue);
  });

  test('a released clutch emits nothing however the phone moves', () async {
    await session.attach();
    feed(source, gz: -1.0);
    expect(out, isEmpty);
  });

  test('raw samples are forwarded for diagnostics', () async {
    final seen = <MotionSample>[];
    final sub = session.samples.listen(seen.add);
    await session.attach();
    feed(source, ms: 100);
    await sub.cancel();
    expect(seen.length, 11);
  });

  test('the last detach opens the clutch and releases a held click',
      () async {
    await session.attach();
    session.emitAll(session.engine.engage());
    session.emitAll(session.engine.click(down: true));
    out.clear();
    session.detach();
    expect(out, [const ButtonEvent(Button.left, down: false)]);
    expect(session.engine.engaged, isFalse);
  });

  test('a config change keeps the learned gyro bias', () async {
    await session.attach();
    feed(source, gz: 0.03, ms: 15000); // resting in a hand, learning
    final learned = session.engine.gyroBias.z;
    expect(learned, greaterThan(0.01));
    session.config = const MotionConfig(pointerGain: 1.5);
    expect(session.engine.config.pointerGain, 1.5);
    expect(session.engine.gyroBias.z, learned);
  });

  test('recalibrate reaches the shared engine', () async {
    await session.attach();
    session.recalibrate();
    expect(session.engine.calibrating, isTrue);
  });

  test('sensor errors are surfaced', () async {
    final errors = <Object>[];
    final sub = session.errors.listen(errors.add);
    await session.attach();
    source.emitError(Exception('sensor died'));
    await sub.cancel();
    expect(errors, hasLength(1));
  });

  test('a source that cannot start reports the error instead of throwing',
      () async {
    final failing = MotionSession(source: FailingSource(), emit: out.add);
    final errors = <Object>[];
    final sub = failing.errors.listen(errors.add);
    await failing.attach();
    await sub.cancel();
    expect(errors.single, isA<StateError>());
    await failing.dispose();
  });
}
