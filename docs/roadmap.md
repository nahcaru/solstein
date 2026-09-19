# Roadmap

## v0.1 — MVP (HID, Android → any OS)

Control a Mac with nothing installed on it.

- [x] `flutter create` in `app/` + Kotlin `HidTransport` platform channel
- [x] Combo HID descriptor registers; macOS pairs and sees "Helm"
- [x] Trackpad: pointer + acceleration, tap-click, 2-finger tap (right click), 2-finger scroll (v+h)
- [x] Keyboard: US layout + modifier row
- [x] 3-finger swipes → shortcut reports (target-OS table in Settings)
- [x] Foreground service; release-all reports on disconnect/pause
- [x] Unit tests: gesture engine, report encoding (62 Dart + 2 Kotlin golden-descriptor tests)
- [x] Manual checklist passes on macOS (verified 2026-07-11 on a Pixel 7a)

## v0.2 — Polish

- [x] Tap-and-drag, middle click
- [x] Media keys (Consumer Control, report ID 3)
- [x] Reconnect UX; multi-host bonded-device switching
- [x] Windows/Linux checklists verified
- [x] Beyond scope, shipped anyway: 2-finger page flick, 4-finger spread/pinch, 2-finger zoom; per-OS keyboard + scroll sign; speed sliders; per-device OS guess
- [x] Manual checklist (extended to the v0.2 gesture set) passes on macOS, Windows, and Linux (verified 2026-07-16)

## v1 — Store-ready

- [x] Host layouts: US, JIS (verified on a real JIS Mac) + かな/英数 IME keys
      — CJK itself already works via the host's IME (see ADR-006). Other
      layouts (French, German, Thai, Arabic, etc.) deferred by design until
      someone has a real host to verify against (see ADR-007)
- [ ] Onboarding, haptics, theming; Play Store release

## v2 — Helper (Tier 2)

- [ ] `BleTransport` + Wire Protocol v1 (`docs/protocol.md`), incl. `Text`
      packets → native Unicode injection (replaces the clipboard-paste idea)
- [ ] Flutter desktop helper in `helper/`: macOS (CGEvent + Accessibility onboarding) → Windows (SendInput) → Linux (uinput + udev rule)
- [ ] Helper-side gesture→action config per OS/DE

## v2+ — Stretch: Tier 3 interactive gestures (macOS)

- [ ] Research private Dock gesture injection (license-review Mac Mouse Fix first)
- [ ] Phased Mission Control/Spaces scrubbing with pause + cancel
- [ ] macOS version gate + Tier 2 auto-fallback

## v3 — iOS client (BLE only — iOS cannot do HID)

- [ ] Swift `BleTransport` (`CBPeripheralManager`); same Flutter UI; App Store release
