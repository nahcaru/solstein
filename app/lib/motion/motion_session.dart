/// Owns the presenter's [MotionEngine] and its sensor feed, so everything that
/// wants motion shares one engine: the presenter surface and the motion
/// diagnostics screen see the same learned gyro bias, and "Recalibrate" in
/// diagnostics really recalibrates the engine that is doing the pointing.
///
/// The sensors run only while something is attached (reference counted): the
/// presenter surface while it is on screen, the diagnostics screen while it is
/// open. Both may be open at once (Settings is pushed over the presenter).
library;

import 'dart:async';

import '../core/input_event.dart';
import 'motion_config.dart';
import 'motion_engine.dart';
import 'motion_sample.dart';
import 'motion_source.dart';

class MotionSession {
  MotionSession({
    required this.source,
    required this.emit,
    MotionConfig config = const MotionConfig(),
  }) : _engine = MotionEngine(config: config);

  final MotionSource source;

  /// Where engine output goes (the InputSink).
  final void Function(InputEvent event) emit;

  final MotionEngine _engine;
  final _samples = StreamController<MotionSample>.broadcast(sync: true);
  final _errors = StreamController<Object>.broadcast(sync: true);
  StreamSubscription<MotionSample>? _subscription;
  int _users = 0;
  bool _disposed = false;

  /// The shared engine. Callers drive the clutch and click through it and
  /// forward the returned events with [emitAll].
  MotionEngine get engine => _engine;

  /// Every sample the sensors deliver, for raw views such as diagnostics.
  Stream<MotionSample> get samples => _samples.stream;

  /// Sensor failures (e.g. a phone without a gyroscope).
  Stream<Object> get errors => _errors.stream;

  /// Whether the sensors are currently running.
  bool get active => _users > 0;

  set config(MotionConfig value) => _engine.config = value;

  void emitAll(Iterable<InputEvent> events) => events.forEach(emit);

  /// Registers a user of the sensors; the first one starts them.
  Future<void> attach() async {
    if (_disposed) return;
    if (_users++ > 0) return;
    _subscription = source.samples.listen(_onSample, onError: _onError);
    try {
      await source.start();
    } catch (e) {
      _onError(e);
    }
    // A detach that landed while start() was still pending has already asked
    // the source to stop; make sure a slow start cannot outlive it.
    if (_users == 0) await source.stop();
  }

  /// Releases a user; the last one stops the sensors. Nothing may stay held
  /// while nobody is looking, so the clutch and click are released too.
  void detach() {
    if (_users == 0) return;
    if (--_users > 0) return;
    _subscription?.cancel();
    _subscription = null;
    source.stop();
    release();
  }

  /// Opens the clutch and releases a held click (stuck-input prevention).
  void release() {
    emitAll(_engine.disengage());
    emitAll(_engine.click(down: false));
  }

  void recalibrate() => _engine.recalibrate();

  void _onSample(MotionSample s) {
    emitAll(_engine.handleSample(s));
    _samples.add(s);
  }

  /// Errors can arrive after [dispose] closed the controller — e.g. a start()
  /// that was still in flight and then failed — so this must not add blindly.
  void _onError(Object error) {
    if (!_disposed) _errors.add(error);
  }

  /// Stops the sensors and releases anything held. Safe to call twice; later
  /// [attach] calls do nothing.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    release(); // nothing may stay held on the host
    await _subscription?.cancel();
    _subscription = null;
    _users = 0;
    await source.stop();
    await _samples.close();
    await _errors.close();
  }
}
