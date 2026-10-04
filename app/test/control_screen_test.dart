import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solstein/app_model.dart';
import 'package:solstein/core/control_mode.dart';
import 'package:solstein/core/input_event.dart';
import 'package:solstein/core/input_sink.dart';
import 'package:solstein/hid/keymap.dart';
import 'package:solstein/presenter/presenter_host.dart';
import 'package:solstein/transport/hid_transport.dart';
import 'package:solstein/ui/control_screen.dart';
import 'package:solstein/ui/keyboard_screen.dart';
import 'package:solstein/ui/media_surface.dart';
import 'package:solstein/ui/presenter_surface.dart';
import 'package:solstein/ui/trackpad_surface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_motion_source.dart';
import 'support/fake_presenter_host.dart';

/// Records what the screen sends, to check which keys a button produced.
class _RecordingTransport extends HidTransport {
  final events = <InputEvent>[];

  @override
  void send(InputEvent event) => events.add(event);
}

/// A host with media keys only: no pointer, no keyboard.
class _MediaOnlyTransport extends HidTransport {
  @override
  Set<Capability> get capabilities => const {Capability.mediaKeys};
}

/// A host with media keys but no pointer.
class _NoPointerTransport extends HidTransport {
  @override
  Set<Capability> get capabilities =>
      const {Capability.keyboard, Capability.mediaKeys};
}

/// A host that can move the pointer but has no Consumer Control report.
class _NoMediaTransport extends HidTransport {
  @override
  Set<Capability> get capabilities =>
      const {Capability.pointer, Capability.keyboard};
}

void main() {
  const hidChannel = MethodChannel('dev.taira.solstein/hid');
  const stateChannel = MethodChannel('dev.taira.solstein/hid_state');
  late AppModel model;
  late FakePresenterHost presenterHost;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(hidChannel, (_) async => null);
    messenger.setMockMethodCallHandler(stateChannel, (_) async => null);
    presenterHost = FakePresenterHost();
    model = AppModel(
      motionSource: FakeMotionSource(),
      presenterHost: presenterHost,
    );
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(hidChannel, null);
    messenger.setMockMethodCallHandler(stateChannel, null);
  });

  // The default 800x600 test view is itself landscape.
  void portrait(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
  }

  void landscape(WidgetTester tester) {
    // A realistic landscape phone (800x360 logical), not the unrealistically
    // tall screen devicePixelRatio 1.0 would give — that gap is how the
    // header-rail overflow and keyboard-inset bugs both slipped through
    // earlier review.
    tester.view.physicalSize = const Size(2400, 1080);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
  }

  Widget app() => MaterialApp(home: ControlScreen(model: model));
  Finder settings() => find.widgetWithIcon(IconButton, Icons.settings);

  /// Opens the header's mode menu and picks [label] (Trackpad, Presenter or
  /// Media).
  Future<void> selectMode(WidgetTester tester, String label) async {
    await tester.tap(find.byTooltip('Mode'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(
      find.widgetWithText(CheckedPopupMenuItem<ControlMode>, label),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  group('keep awake', () {
    var presenting = false;
    setUp(() => presenting = false);

    // Flips between Trackpad and Presenter.
    Future<void> toggleMode(WidgetTester tester) async {
      presenting = !presenting;
      await selectMode(tester, presenting ? 'Presenter' : 'Trackpad');
    }

    testWidgets('default: awake only in Presenter', (tester) async {
      portrait(tester);
      await tester.pumpWidget(app());
      expect(presenterHost.keepScreenOn, isFalse);
      await toggleMode(tester);
      expect(presenterHost.keepScreenOn, isTrue);
      await toggleMode(tester);
      expect(presenterHost.keepScreenOn, isFalse);
    });

    testWidgets('Trackpad setting: awake only in Trackpad', (tester) async {
      portrait(tester);
      await model.setKeepAwake(KeepAwake.trackpad);
      await tester.pumpWidget(app());
      expect(presenterHost.keepScreenOn, isTrue);
      await toggleMode(tester);
      expect(presenterHost.keepScreenOn, isFalse);
    });

    testWidgets('Both: awake in either mode', (tester) async {
      portrait(tester);
      await model.setKeepAwake(KeepAwake.both);
      await tester.pumpWidget(app());
      expect(presenterHost.keepScreenOn, isTrue);
      await toggleMode(tester);
      expect(presenterHost.keepScreenOn, isTrue);
    });

    testWidgets('None: never awake', (tester) async {
      portrait(tester);
      await model.setKeepAwake(KeepAwake.none);
      await tester.pumpWidget(app());
      await toggleMode(tester);
      expect(presenterHost.keepScreenOn, isFalse);
    });

    testWidgets('is asked for again after the app resumes', (tester) async {
      portrait(tester);
      await model.setKeepAwake(KeepAwake.both);
      await tester.pumpWidget(app());
      // MainActivity clears the native flag on pause.
      await presenterHost.setKeepScreenOn(false);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(presenterHost.keepScreenOn, isTrue);
    });

    testWidgets('leaving the screen releases it', (tester) async {
      portrait(tester);
      await model.setKeepAwake(KeepAwake.both);
      await tester.pumpWidget(app());
      expect(presenterHost.keepScreenOn, isTrue);
      await tester.pumpWidget(const SizedBox());
      expect(presenterHost.keepScreenOn, isFalse);
    });

    testWidgets('changing it in Settings applies on return', (tester) async {
      portrait(tester);
      await tester.pumpWidget(app());
      expect(presenterHost.keepScreenOn, isFalse);
      await tester.tap(settings());
      await tester.pumpAndSettle();
      final dropdown = find.byType(DropdownButton<KeepAwake>);
      await tester.scrollUntilVisible(dropdown, 200);
      await tester.ensureVisible(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Trackpad').last);
      await tester.pumpAndSettle();
      expect(model.keepAwake, KeepAwake.trackpad);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(presenterHost.keepScreenOn, isTrue);
    });
  });

  testWidgets('portrait keeps the app bar with the header buttons', (
    tester,
  ) async {
    portrait(tester);
    await tester.pumpWidget(app());
    expect(find.byType(AppBar), findsOneWidget);
    expect(
      find.descendant(of: find.byType(AppBar), matching: settings()),
      findsOneWidget,
    );
    expect(
      tester.getCenter(settings()).dy,
      lessThan(tester.getCenter(find.byType(TrackpadSurface)).dy),
    );
  });

  testWidgets('landscape moves the header to a rail on the left', (
    tester,
  ) async {
    landscape(tester);
    await tester.pumpWidget(app());
    expect(find.byType(AppBar), findsNothing);
    for (final tooltip in [
      'Back to device list',
      'Mode',
      'Keyboard',
      'Settings',
    ]) {
      expect(find.byTooltip(tooltip), findsOneWidget, reason: tooltip);
    }
    final trackpad = tester.getRect(find.byType(TrackpadSurface));
    expect(tester.getCenter(settings()).dx, lessThan(trackpad.left));
  });

  testWidgets(
      'landscape rail pins back to the top and the other buttons to the '
      'bottom, matching the app bar\'s leading/actions split', (tester) async {
    landscape(tester);
    await tester.pumpWidget(app());
    final screenHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    final backY = tester.getCenter(find.byTooltip('Back to device list')).dy;
    final settingsY = tester.getCenter(settings()).dy;
    expect(backY, lessThan(screenHeight * 0.25));
    expect(settingsY, greaterThan(screenHeight * 0.75));
  });

  testWidgets(
      'landscape rail does not overflow or move when the on-screen '
      'keyboard opens', (tester) async {
    // Gboard's height simulated as a bottom view inset — regression for a
    // RenderFlex overflow when the inset shrank the rail below the
    // buttons' natural height.
    landscape(tester);
    await tester.pumpWidget(app());
    await tester.tap(find.byTooltip('Keyboard'));
    await tester.pumpAndSettle();
    final backBefore =
        tester.getCenter(find.byTooltip('Back to device list')).dy;
    final settingsBefore = tester.getCenter(settings()).dy;
    // The keyboard drawer's media row (bottom of its key grid) was never at
    // risk from this bug — it's wrapped in a SingleChildScrollView, so a
    // shrinking viewport just makes it scrollable instead of overflowing.
    // Assert it anyway as a plain "nothing moves" invariant for the drawer.
    final volumeUp = find.byIcon(Icons.volume_up);
    final volumeUpBefore = tester.getCenter(volumeUp);

    tester.view.viewInsets = const FakeViewPadding(bottom: 300 * 3.0);
    addTearDown(() => tester.view.viewInsets = FakeViewPadding.zero);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(tester.getCenter(find.byTooltip('Back to device list')).dy,
        backBefore);
    expect(tester.getCenter(settings()).dy, settingsBefore);
    expect(tester.getCenter(volumeUp), volumeUpBefore);
  });

  testWidgets('landscape puts the keyboard beside the trackpad', (
    tester,
  ) async {
    landscape(tester);
    await tester.pumpWidget(app());
    await tester.tap(find.byTooltip('Keyboard'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final trackpad = tester.getRect(find.byType(TrackpadSurface));
    final keyboard = tester.getRect(find.byType(KeyboardScreen));
    expect(keyboard.left, greaterThanOrEqualTo(trackpad.right));
  });

  testWidgets('landscape presenter toggle swaps in the presenter deck', (
    tester,
  ) async {
    landscape(tester);
    await tester.pumpWidget(app());
    await selectMode(tester, 'Presenter');
    expect(find.byKey(const ValueKey('clutch')), findsOneWidget);
    expect(find.byType(TrackpadSurface), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'rotating mid-press keeps the presenter pad\'s identity — lifting '
      'the finger afterwards does not throw', (tester) async {
    // Regression: the landscape/portrait branches used to build
    // structurally different widget trees with no stable key, so an
    // orientation change (easy to trigger by sweeping the phone while
    // holding the presenter's clutch pad) disposed and recreated
    // PresenterSurface mid-gesture. The finger's pointer route still
    // pointed at the disposed _PadButtonState, and lifting it threw
    // "setState() called after dispose()".
    portrait(tester);
    await tester.pumpWidget(app());
    await selectMode(tester, 'Presenter');

    final clutch = find.byKey(const ValueKey('clutch'));
    final before = tester.state(find.byType(PresenterSurface));
    final gesture = await tester.startGesture(tester.getCenter(clutch));
    await tester.pump();

    landscape(tester);
    await tester.pump();

    // Still the same element (reparented, not disposed) — the actual fix,
    // not just the absence of a crash.
    expect(tester.state(find.byType(PresenterSurface)), same(before));

    await gesture.up();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  group('system UI', () {
    // The platform channel also carries unrelated calls we don't care about
    // here (AppBar's status-bar style via AnnotatedRegion, IconButton's
    // click sound, …) — only the two calls SystemChrome.setEnabledSystemUIMode
    // makes are relevant.
    final calls = <MethodCall>[];
    Iterable<MethodCall> uiModeCalls() =>
        calls.where((c) => c.method.startsWith('SystemChrome.setEnabledSystemUI'));

    setUp(() {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        calls.add(call);
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    testWidgets('landscape hides both system bars', (tester) async {
      landscape(tester);
      await tester.pumpWidget(app());
      expect(uiModeCalls(), hasLength(1));
      expect(uiModeCalls().single.method, 'SystemChrome.setEnabledSystemUIMode');
      expect(uiModeCalls().single.arguments, 'SystemUiMode.immersiveSticky');
    });

    testWidgets('portrait restores both system bars', (tester) async {
      portrait(tester);
      await tester.pumpWidget(app());
      expect(uiModeCalls(), hasLength(1));
      expect(
          uiModeCalls().single.method, 'SystemChrome.setEnabledSystemUIOverlays');
      expect(
        uiModeCalls().single.arguments,
        containsAll(['SystemUiOverlay.top', 'SystemUiOverlay.bottom']),
      );
    });

    testWidgets('rotating mid-session updates the system UI mode', (
      tester,
    ) async {
      landscape(tester);
      await tester.pumpWidget(app());
      calls.clear();

      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      await tester.pumpAndSettle();

      expect(uiModeCalls(), hasLength(1));
      expect(
          uiModeCalls().single.method, 'SystemChrome.setEnabledSystemUIOverlays');
    });

    testWidgets('an unrelated rebuild does not re-fire the platform call', (
      tester,
    ) async {
      landscape(tester);
      await tester.pumpWidget(app());
      calls.clear();

      await selectMode(tester, 'Presenter');

      expect(uiModeCalls(), isEmpty);
    });

    testWidgets('leaving the screen restores both system bars', (
      tester,
    ) async {
      landscape(tester);
      await tester.pumpWidget(app());
      calls.clear();

      await tester.pumpWidget(const SizedBox());

      expect(uiModeCalls(), hasLength(1));
      expect(
          uiModeCalls().single.method, 'SystemChrome.setEnabledSystemUIOverlays');
      expect(
        uiModeCalls().single.arguments,
        containsAll(['SystemUiOverlay.top', 'SystemUiOverlay.bottom']),
      );
    });
  });
  group('media mode', () {
    testWidgets('the mode menu switches between all three surfaces', (
      tester,
    ) async {
      portrait(tester);
      await tester.pumpWidget(app());
      expect(find.byType(TrackpadSurface), findsOneWidget);

      await selectMode(tester, 'Media');
      expect(find.byType(MediaSurface), findsOneWidget);
      expect(find.byType(TrackpadSurface), findsNothing);

      await selectMode(tester, 'Presenter');
      expect(find.byType(PresenterSurface), findsOneWidget);
      expect(find.byType(MediaSurface), findsNothing);

      await selectMode(tester, 'Trackpad');
      expect(find.byType(TrackpadSurface), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('shows the player row (seek, captions, fullscreen)', (
      tester,
    ) async {
      portrait(tester);
      await tester.pumpWidget(app());
      await selectMode(tester, 'Media');
      for (final t in ['Seek back', 'Seek forward', 'Captions', 'Fullscreen']) {
        expect(find.byTooltip(t), findsOneWidget, reason: t);
      }
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('no keyboard capability, no player row', (tester) async {
      portrait(tester);
      model = AppModel(
        transport: _MediaOnlyTransport(),
        motionSource: FakeMotionSource(),
        presenterHost: presenterHost,
      );
      await tester.pumpWidget(app());
      expect(find.byType(MediaSurface), findsOneWidget);
      expect(find.byTooltip('Seek back'), findsNothing);
      expect(find.byTooltip('Play/Pause'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    group('player buttons send the arrow, C and F keys', () {
      late _RecordingTransport transport;

      setUp(() {
        transport = _RecordingTransport();
        model = AppModel(
          transport: transport,
          motionSource: FakeMotionSource(),
          presenterHost: presenterHost,
        );
      });

      Future<List<InputEvent>> tapAndRecord(
        WidgetTester tester,
        String tooltip,
      ) async {
        portrait(tester);
        await tester.pumpWidget(app());
        await selectMode(tester, 'Media');
        transport.events.clear();
        await tester.tap(find.byTooltip(tooltip));
        await tester.pump();
        final sent = List<InputEvent>.of(transport.events);
        await tester.pumpWidget(const SizedBox());
        return sent;
      }

      testWidgets('Fullscreen is F', (tester) async {
        expect(await tapAndRecord(tester, 'Fullscreen'), [
          const KeyInput(0x09, Mod.none, down: true),
          const KeyInput(0x09, Mod.none, down: false),
        ]);
      });

      testWidgets('Captions is C', (tester) async {
        expect(await tapAndRecord(tester, 'Captions'), [
          const KeyInput(0x06, Mod.none, down: true),
          const KeyInput(0x06, Mod.none, down: false),
        ]);
      });

      testWidgets('Seek back is ←', (tester) async {
        expect(await tapAndRecord(tester, 'Seek back'), [
          const KeyInput(Usage.arrowLeft, Mod.none, down: true),
          const KeyInput(Usage.arrowLeft, Mod.none, down: false),
        ]);
      });

      testWidgets('Seek forward is →', (tester) async {
        expect(await tapAndRecord(tester, 'Seek forward'), [
          const KeyInput(Usage.arrowRight, Mod.none, down: true),
          const KeyInput(Usage.arrowRight, Mod.none, down: false),
        ]);
      });
    });

    testWidgets('keeps the keyboard drawer available', (tester) async {
      portrait(tester);
      await tester.pumpWidget(app());
      await selectMode(tester, 'Media');
      await tester.tap(find.byTooltip('Keyboard'));
      await tester.pump();
      expect(find.byType(KeyboardScreen), findsOneWidget);
      expect(find.byType(MediaSurface), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the phone volume keys are taken only while Media shows', (
      tester,
    ) async {
      portrait(tester);
      await tester.pumpWidget(app());
      expect(presenterHost.volumeKeysCaptured, isFalse);
      await selectMode(tester, 'Media');
      expect(presenterHost.volumeKeysCaptured, isTrue);
      await selectMode(tester, 'Trackpad');
      expect(presenterHost.volumeKeysCaptured, isFalse);
      await tester.pumpWidget(const SizedBox());
    });

    // The incoming surface's initState runs before the outgoing one's
    // dispose, so a naive release-in-dispose would undo the new capture.
    testWidgets('Presenter → Media keeps the volume keys captured', (
      tester,
    ) async {
      portrait(tester);
      await tester.pumpWidget(app());
      await selectMode(tester, 'Presenter');
      expect(presenterHost.volumeKeysCaptured, isTrue);
      await selectMode(tester, 'Media');
      expect(presenterHost.volumeKeysCaptured, isTrue);
      await tester.pumpWidget(const SizedBox());
      expect(presenterHost.volumeKeysCaptured, isFalse);
    });

    testWidgets('Media → Presenter keeps the volume keys captured', (
      tester,
    ) async {
      portrait(tester);
      await tester.pumpWidget(app());
      await selectMode(tester, 'Media');
      await selectMode(tester, 'Presenter');
      expect(presenterHost.volumeKeysCaptured, isTrue);
      await tester.pumpWidget(const SizedBox());
      expect(presenterHost.volumeKeysCaptured, isFalse);
    });

    testWidgets('rotating keeps the volume keys captured', (tester) async {
      portrait(tester);
      await tester.pumpWidget(app());
      await selectMode(tester, 'Media');
      landscape(tester);
      await tester.pump();
      expect(presenterHost.volumeKeysCaptured, isTrue);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('rotating mid-press does not throw when the finger lifts', (
      tester,
    ) async {
      portrait(tester);
      await tester.pumpWidget(app());
      await selectMode(tester, 'Media');
      final gesture =
          await tester.startGesture(tester.getCenter(find.byTooltip('Volume up')));
      await tester.pump();
      landscape(tester);
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a sink with no pointer shows Media, with no menu', (
      tester,
    ) async {
      portrait(tester);
      model = AppModel(
        transport: _NoPointerTransport(),
        motionSource: FakeMotionSource(),
        presenterHost: presenterHost,
      );
      await tester.pumpWidget(app());
      expect(find.byType(MediaSurface), findsOneWidget);
      expect(find.byType(TrackpadSurface), findsNothing);
      expect(find.byTooltip('Mode'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('opening Settings gives the volume keys back', (tester) async {
      portrait(tester);
      await tester.pumpWidget(app());
      await selectMode(tester, 'Media');
      await tester.tap(settings());
      await tester.pumpAndSettle();
      expect(presenterHost.volumeKeysCaptured, isFalse);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Media keep-awake setting: awake only in Media', (
      tester,
    ) async {
      portrait(tester);
      await model.setKeepAwake(KeepAwake.media);
      await tester.pumpWidget(app());
      expect(presenterHost.keepScreenOn, isFalse);
      await selectMode(tester, 'Media');
      expect(presenterHost.keepScreenOn, isTrue);
      await selectMode(tester, 'Presenter');
      expect(presenterHost.keepScreenOn, isFalse);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('without the Consumer Control report there is no Media entry', (
      tester,
    ) async {
      portrait(tester);
      model = AppModel(
        transport: _NoMediaTransport(),
        motionSource: FakeMotionSource(),
        presenterHost: presenterHost,
      );
      await tester.pumpWidget(app());
      await tester.tap(find.byTooltip('Mode'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Presenter'), findsOneWidget);
      expect(find.text('Media'), findsNothing);
      await tester.tapAt(const Offset(5, 5)); // dismiss the menu
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
    });
  });
}
