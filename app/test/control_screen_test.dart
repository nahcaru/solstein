import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helm/app_model.dart';
import 'package:helm/presenter/presenter_host.dart';
import 'package:helm/ui/control_screen.dart';
import 'package:helm/ui/keyboard_screen.dart';
import 'package:helm/ui/presenter_surface.dart';
import 'package:helm/ui/trackpad_surface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_motion_source.dart';
import 'support/fake_presenter_host.dart';

void main() {
  const hidChannel = MethodChannel('dev.taira.helm/hid');
  const stateChannel = MethodChannel('dev.taira.helm/hid_state');
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

  group('keep awake', () {
    Future<void> toggleMode(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Presenter').evaluate().isNotEmpty
          ? find.byTooltip('Presenter')
          : find.byTooltip('Trackpad'));
      await tester.pump();
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
      'Presenter',
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
    await tester.tap(find.byTooltip('Presenter'));
    await tester.pump();
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
    await tester.tap(find.byTooltip('Presenter'));
    await tester.pump();

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

      await tester.tap(find.byTooltip('Presenter'));
      await tester.pump();

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
}
