import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solstein/motion/motion_sample.dart';
import 'package:solstein/motion/motion_session.dart';
import 'package:solstein/ui/motion_diagnostics_screen.dart';

import 'support/fake_motion_source.dart';

void feed(FakeMotionSource source, {double gz = 0, int ms = 2000, int from = 0}) {
  for (var t = 0; t <= ms; t += 10) {
    source.emit(MotionSample(
      gyroX: 0,
      gyroY: 0,
      gyroZ: gz,
      accelX: 0,
      accelY: 0,
      accelZ: 9.81,
      timestamp: Duration(milliseconds: from + t),
    ));
  }
}

void main() {
  late FakeMotionSource source;
  late MotionSession session;

  setUp(() {
    source = FakeMotionSource();
    session = MotionSession(source: source, emit: (_) {});
  });

  tearDown(() => session.dispose());

  Widget screen() => MaterialApp(home: MotionDiagnosticsScreen(session: session));

  testWidgets('starts the sensors on open and stops them on close',
      (tester) async {
    await tester.pumpWidget(screen());
    expect(source.running, isTrue);
    await tester.pumpWidget(const SizedBox());
    expect(source.running, isFalse);
  });

  testWidgets('shows the measured sample rate and learned bias',
      (tester) async {
    await tester.pumpWidget(screen());
    feed(source, gz: 0.03, ms: 3000);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('100 Hz'), findsOneWidget);
    expect(find.textContaining('0.030', findRichText: true), findsWidgets);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Recalibrate starts a recalibration of the shared engine',
      (tester) async {
    await tester.pumpWidget(screen());
    feed(source, ms: 100);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byType(FilledButton));
    await tester.pump(const Duration(milliseconds: 200));
    expect(session.engine.calibrating, isTrue);
    expect(find.text('Hold still…'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('backgrounding stops the sensors even though this screen is '
      'open; resuming restarts them', (tester) async {
    await tester.pumpWidget(screen());
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(source.running, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(source.running, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('does not keep the presenter\'s sensors alive after pause',
      (tester) async {
    await session.attach(); // the presenter underneath
    await tester.pumpWidget(screen());
    session.detach(); // the presenter pauses and lets go
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(source.running, isFalse);
    await tester.pumpWidget(const SizedBox());
  });
}
