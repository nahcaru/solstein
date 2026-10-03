import 'package:flutter_test/flutter_test.dart';
import 'package:helm/app_model.dart';
import 'package:helm/hid/keymap.dart';
import 'package:helm/hid/shortcut_tables.dart';
import 'package:helm/presenter/presenter_host.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('host layout defaults to US', () async {
    final model = AppModel();
    await model.load();
    expect(model.hostLayout.id, HostLayoutId.us);
  });

  test('setHostLayout persists as the global default', () async {
    final model = AppModel();
    await model.load();
    await model.setHostLayout(HostLayoutId.jis);
    expect(model.hostLayout.id, HostLayoutId.jis);

    final restored = AppModel();
    await restored.load();
    expect(restored.hostLayout.id, HostLayoutId.jis);
  });

  test('setHostLayout also remembers the choice for the connected host',
      () async {
    SharedPreferences.setMockInitialValues({});
    final model = AppModel();
    await model.load();
    model.connectedDeviceId = 'AA:BB:CC';
    await model.setHostLayout(HostLayoutId.jis);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('hostLayout.AA:BB:CC'), HostLayoutId.jis.index);
  });

  test('host layout is independent of target OS', () async {
    final model = AppModel();
    await model.load();
    await model.setHostLayout(HostLayoutId.jis);
    // Changing the OS must not disturb the layout.
    await model.setTargetOs(TargetOs.windows);
    expect(model.hostLayout.id, HostLayoutId.jis);
  });

  test('an out-of-range stored index falls back to US', () async {
    SharedPreferences.setMockInitialValues({'hostLayout': 99});
    final model = AppModel();
    await model.load();
    expect(model.hostLayout.id, HostLayoutId.us);
  });

  test('IME keys default to off and persist when enabled', () async {
    final model = AppModel();
    await model.load();
    expect(model.showImeKeys, isFalse);

    await model.setShowImeKeys(true);
    final restored = AppModel();
    await restored.load();
    expect(restored.showImeKeys, isTrue);
  });

  test('keep-awake indices saved by earlier builds keep their meaning',
      () async {
    // Persisted by index, so adding Media must not shift the older values.
    for (final (index, expected) in [
      (0, KeepAwake.none),
      (1, KeepAwake.trackpad),
      (2, KeepAwake.presenter),
      (3, KeepAwake.both),
    ]) {
      SharedPreferences.setMockInitialValues({'keepAwake': index});
      final model = AppModel();
      await model.load();
      expect(model.keepAwake, expected);
    }
  });

  test('Media keep-awake persists, and an unknown index falls back', () async {
    final model = AppModel();
    await model.load();
    await model.setKeepAwake(KeepAwake.media);
    final restored = AppModel();
    await restored.load();
    expect(restored.keepAwake, KeepAwake.media);

    SharedPreferences.setMockInitialValues({'keepAwake': 99});
    final fallback = AppModel();
    await fallback.load();
    expect(fallback.keepAwake, KeepAwake.presenter);
  });
}
