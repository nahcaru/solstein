import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helm/app_model.dart';
import 'package:helm/ui/control_screen.dart';
import 'package:helm/ui/keyboard_screen.dart';
import 'package:helm/ui/trackpad_surface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_motion_source.dart';
import 'support/fake_presenter_host.dart';

void main() {
  const hidChannel = MethodChannel('dev.taira.helm/hid');
  const stateChannel = MethodChannel('dev.taira.helm/hid_state');
  late AppModel model;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(hidChannel, (_) async => null);
    messenger.setMockMethodCallHandler(stateChannel, (_) async => null);
    model = AppModel(
      motionSource: FakeMotionSource(),
      presenterHost: FakePresenterHost(),
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
    tester.view.physicalSize = const Size(2400, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Widget app() => MaterialApp(home: ControlScreen(model: model));
  Finder settings() => find.widgetWithIcon(IconButton, Icons.settings);

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
}
