import 'dart:async';

import 'package:flutter/material.dart';

import '../motion/motion_sample.dart';
import '../motion/motion_session.dart';

/// Live view of the motion sensors, for tuning and for recalibrating the gyro.
/// Shows the same engine the presenter uses, so "Recalibrate" here is a real
/// recalibration of the pointer, not of a private copy.
class MotionDiagnosticsScreen extends StatefulWidget {
  const MotionDiagnosticsScreen({super.key, required this.session});

  final MotionSession session;

  @override
  State<MotionDiagnosticsScreen> createState() =>
      _MotionDiagnosticsScreenState();
}

class _MotionDiagnosticsScreenState extends State<MotionDiagnosticsScreen>
    with WidgetsBindingObserver {
  StreamSubscription<MotionSample>? _samples;
  Timer? _refresh;
  bool _attached = false;
  MotionSample? _last;
  Duration? _windowStart;
  int _windowCount = 0;
  double _rateHz = 0;

  MotionSession get _session => widget.session;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _samples = _session.samples.listen(_onSample);
    _attach();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _samples?.cancel();
    _detach();
    super.dispose();
  }

  /// A backgrounded app must not keep streaming gyro or repainting; and since
  /// the sensor feed is reference counted, holding it here would also defeat
  /// the presenter's own stop-on-pause.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _attach();
    } else {
      _detach();
    }
  }

  void _attach() {
    if (_attached) return;
    _attached = true;
    _session.attach();
    // The sensors run at ~100 Hz; repaint at 10 Hz.
    _refresh = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => mounted ? setState(() {}) : null,
    );
  }

  void _detach() {
    if (!_attached) return;
    _attached = false;
    _refresh?.cancel();
    _refresh = null;
    _session.detach();
  }

  /// Measures the delivered sample rate from the sensor timestamps over
  /// one-second windows.
  void _onSample(MotionSample s) {
    _last = s;
    final start = _windowStart ??= s.timestamp;
    _windowCount++;
    final elapsed = s.timestamp - start;
    if (elapsed >= const Duration(seconds: 1)) {
      _rateHz = _windowCount * 1e6 / elapsed.inMicroseconds;
      _windowStart = s.timestamp;
      _windowCount = 0;
    }
  }

  static String _f(double v) => v.toStringAsFixed(3).padLeft(7);

  @override
  Widget build(BuildContext context) {
    final engine = _session.engine;
    final s = _last;
    final bias = engine.gyroBias;
    final still = s != null && engine.still;
    final mono = Theme.of(context)
        .textTheme
        .bodyMedium
        ?.copyWith(fontFamily: 'monospace');
    return Scaffold(
      appBar: AppBar(title: const Text('Motion sensors')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            title: const Text('Sample rate'),
            trailing: Text(
              s == null ? 'no data' : '${_rateHz.toStringAsFixed(0)} Hz',
              style: mono,
            ),
          ),
          ListTile(
            title: const Text('Gyro (rad/s)'),
            subtitle: Text(
              s == null
                  ? '—'
                  : 'x ${_f(s.gyroX)}\ny ${_f(s.gyroY)}\nz ${_f(s.gyroZ)}',
              style: mono,
            ),
          ),
          ListTile(
            title: const Text('Learned bias (rad/s)'),
            subtitle: Text(
              'x ${_f(bias.x)}\ny ${_f(bias.y)}\nz ${_f(bias.z)}',
              style: mono,
            ),
          ),
          ListTile(
            title: const Text('Phone is'),
            trailing: Text(still ? 'still' : 'moving'),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: FilledButton.icon(
              icon: const Icon(Icons.refresh),
              label: Text(engine.calibrating
                  ? 'Hold still…'
                  : 'Recalibrate (2 s, hold still)'),
              onPressed: engine.calibrating ? null : _session.recalibrate,
            ),
          ),
          const Text(
            'Put the phone down or hold it still, then press Recalibrate. '
            'The bias is also learned automatically whenever the phone is '
            'still — with the pad released, or held while moving.',
          ),
        ],
      ),
    );
  }
}
