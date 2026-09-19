import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:helm/motion/one_euro_filter.dart';

/// RMS of a filtered sinusoid (after the transient), relative to the input's.
double gainAt(OneEuroFilter f, double hz,
    {double amp = 1.0, double dt = 0.01}) {
  final n = (6 / dt).round();
  var inSq = 0.0, outSq = 0.0;
  for (var i = 0; i < n; i++) {
    final x = amp * math.sin(2 * math.pi * hz * i * dt);
    final y = f.filter(x, dt);
    if (i >= n ~/ 3) {
      inSq += x * x;
      outSq += y * y;
    }
  }
  return math.sqrt(outSq / inSq);
}

void main() {
  OneEuroFilter make({double minCutoff = 1.5, double beta = 0.08}) =>
      OneEuroFilter(minCutoffHz: minCutoff, beta: beta);

  test('the first value passes through unchanged', () {
    expect(make().filter(0.7, 0.01), 0.7);
  });

  test('a constant input stays constant', () {
    final f = make();
    for (var i = 0; i < 100; i++) {
      expect(f.filter(0.4, 0.01), closeTo(0.4, 1e-12));
    }
  });

  test('a step converges to the new value', () {
    final f = make()..filter(0, 0.01);
    double y = 0;
    for (var i = 0; i < 400; i++) {
      y = f.filter(1, 0.01);
    }
    expect(y, closeTo(1, 1e-3));
  });

  test('attenuates a tremor-band tone and passes a slow one', () {
    // Small amplitude keeps the speed-adaptive cutoff near its minimum.
    expect(gainAt(make(), 9, amp: 0.2), lessThan(0.25));
    expect(gainAt(make(), 0.5, amp: 0.2), greaterThan(0.9));
  });

  test('a lower minimum cutoff smooths harder', () {
    expect(gainAt(make(minCutoff: 0.5), 4, amp: 0.2),
        lessThan(gainAt(make(minCutoff: 3.0), 4, amp: 0.2)));
  });

  test('a higher beta lags less on a fast ramp', () {
    double lag(double beta) {
      final f = make(beta: beta)..filter(0, 0.01);
      double y = 0, x = 0;
      for (var i = 0; i < 100; i++) {
        x = 5.0 * (i + 1) * 0.01; // 5 units/s ramp
        y = f.filter(x, 0.01);
      }
      return x - y;
    }

    expect(lag(2.0), lessThan(lag(0.0)));
  });

  test('honours the time step: the same tone is filtered the same at any '
      'sampling rate', () {
    // A filter that ignored dt would smooth a 200 Hz stream far harder than a
    // 50 Hz one. Android sensor timing also jitters, so dt really varies.
    final at50 = gainAt(make(), 4, amp: 0.2, dt: 0.02);
    final at100 = gainAt(make(), 4, amp: 0.2, dt: 0.01);
    final at200 = gainAt(make(), 4, amp: 0.2, dt: 0.005);
    expect(at50, closeTo(at100, 0.06));
    expect(at200, closeTo(at100, 0.06));
  });

  test('reset forgets its state', () {
    final f = make();
    f.filter(10, 0.01);
    f.filter(10, 0.01);
    f.reset();
    expect(f.filter(-3, 0.01), -3);
  });

  test('deterministic: same inputs, same outputs', () {
    List<double> run() {
      final f = make();
      return [
        for (var i = 0; i < 50; i++)
          f.filter(math.sin(i * 0.3), 0.01),
      ];
    }

    expect(run(), run());
  });
}
