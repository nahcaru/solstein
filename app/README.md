# Helm client (Android)

Flutter app that turns the phone into a Bluetooth HID trackpad + keyboard. See the repo root README and `docs/` for architecture.

- Run: `fvm flutter run` (physical device required — emulators have no Bluetooth)
- Tests: `fvm flutter test`
- Kotlin tests: `cd android && ./gradlew :app:testDebugUnitTest`
