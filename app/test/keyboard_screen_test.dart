import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helm/core/input_event.dart';
import 'package:helm/core/input_sink.dart';
import 'package:helm/hid/keymap.dart';
import 'package:helm/hid/layouts.dart';
import 'package:helm/hid/shortcut_tables.dart';
import 'package:helm/ui/keyboard_screen.dart';

/// Captures what the transport would have sent.
class FakeSink implements InputSink {
  final List<InputEvent> events = [];

  /// Usages of key-down events only — the shape assertions care about.
  List<int> get downUsages =>
      events.whereType<KeyInput>().where((e) => e.down).map((e) => e.usage).toList();

  @override
  void send(InputEvent event) => events.add(event);

  @override
  Set<Capability> get capabilities => const {Capability.keyboard};

  @override
  Future<void> connect(DeviceTarget target) async {}

  @override
  Future<void> disconnect() async {}

  @override
  Stream<SinkState> get state => const Stream.empty();
}

Future<void> pumpKeyboard(
  WidgetTester tester,
  FakeSink sink,
  HostLayout layout, {
  bool showImeKeys = false,
}) {
  return tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: KeyboardScreen(
        sink: sink,
        targetOs: TargetOs.macos,
        hostLayout: layout,
        showImeKeys: showImeKeys,
      ),
    ),
  ));
}

void main() {
  final us = hostLayouts[HostLayoutId.us]!;

  testWidgets('sendable characters are sent and retained', (tester) async {
    final sink = FakeSink();
    await pumpKeyboard(tester, sink, us);

    await tester.enterText(find.byType(TextField), 'hi');
    await tester.pump();

    expect(sink.downUsages, [0x0B, 0x0C]); // h, i
    expect(find.text('hi'), findsOneWidget);
  });

  testWidgets('an unsendable character is rejected from the field', (tester) async {
    final sink = FakeSink();
    await pumpKeyboard(tester, sink, us);

    await tester.enterText(find.byType(TextField), 'ñ');
    await tester.pump();

    expect(sink.events, isEmpty, reason: 'ñ has no US usage — nothing to send');
    expect(find.text('ñ'), findsNothing, reason: 'field must mirror the host');
  });

  testWidgets('mixed text sends and keeps only the sendable characters',
      (tester) async {
    final sink = FakeSink();
    await pumpKeyboard(tester, sink, us);

    await tester.enterText(find.byType(TextField), 'café');
    await tester.pump();

    expect(sink.downUsages, [0x06, 0x04, 0x09]); // c, a, f — é dropped
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'caf');
  });

  testWidgets('rejection surfaces a message naming the character',
      (tester) async {
    final sink = FakeSink();
    await pumpKeyboard(tester, sink, us);

    await tester.enterText(find.byType(TextField), 'ñ');
    await tester.pump();

    expect(find.textContaining('ñ'), findsOneWidget);
  });

  testWidgets('backspace after a rejection deletes the right character',
      (tester) async {
    final sink = FakeSink();
    await pumpKeyboard(tester, sink, us);

    await tester.enterText(find.byType(TextField), 'añ');
    await tester.pump();
    sink.events.clear();

    // The field now holds "a". Deleting it must send exactly one backspace —
    // the pre-fix code sent one for ñ too, corrupting the host's text.
    await tester.enterText(find.byType(TextField), '');
    await tester.pump();

    expect(sink.downUsages, [Usage.backspace]);
  });

  testWidgets('JIS layout sends @ at the US bracket position', (tester) async {
    final sink = FakeSink();
    await pumpKeyboard(tester, sink, hostLayouts[HostLayoutId.jis]!);

    await tester.enterText(find.byType(TextField), '@');
    await tester.pump();

    expect(sink.downUsages, [0x2F]);
  });

  testWidgets(
      'a character typed with a held modifier reaches the host as a '
      'shortcut and resets the buffer', (tester) async {
    final sink = FakeSink();
    await pumpKeyboard(tester, sink, us);

    // Tap ⌘ (rendered as an icon, found by its test key), then type "a": the
    // pre-fix code OR'd ⌘ into the keystroke (sending ⌘A — select all, not
    // the character) but still recorded "a" in the field, so the next
    // backspace count would have been wrong.
    await tester.tap(find.byKey(const ValueKey('mod-gui')));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'a');
    await tester.pump();

    final down = sink.events
        .whereType<KeyInput>()
        .firstWhere((e) => e.down && e.usage == 0x04);
    expect(down.modifiers, Mod.lGui, reason: 'host received ⌘A, not "a"');

    // The field must not claim the host has "a" it never received as such —
    // it resets to empty, the one state that's always true.
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, isEmpty);
  });

  testWidgets('tapping a modifier alone does not reset the buffer',
      (tester) async {
    final sink = FakeSink();
    await pumpKeyboard(tester, sink, us);

    await tester.enterText(find.byType(TextField), 'hi');
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('mod-gui')));
    await tester.pump();

    // Toggling a modifier sends nothing and must not disturb the field.
    expect(find.text('hi'), findsOneWidget);
  });

  testWidgets(
      'the nav-row backspace resets the buffer instead of letting it '
      'desync from the host', (tester) async {
    final sink = FakeSink();
    await pumpKeyboard(tester, sink, us);

    await tester.enterText(find.byType(TextField), 'abc');
    await tester.pump();
    sink.events.clear();

    // The on-screen ⌫ (rendered as an icon) sends a raw backspace straight to
    // the host without going through the diff loop at all.
    await tester.tap(find.byKey(const ValueKey('nav-backspace')));
    await tester.pump();

    expect(sink.downUsages, [Usage.backspace]);

    // Pre-fix, the field still read "abc" here even though the host now
    // has "ab" — the next diff would have computed its backspace count
    // against fiction. The fix resets to empty instead.
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, isEmpty);
  });
}
