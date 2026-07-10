# Roadmap

## v0.1 — MVP (HID, Android → any OS)

Control a Mac with nothing installed on it.

- [ ] `flutter create` in `app/` + Kotlin `HidTransport` platform channel
- [ ] Combo HID descriptor registers; macOS pairs and sees "Helm"
- [ ] Trackpad: pointer + acceleration, tap-click, 2-finger tap (right click), 2-finger scroll (v+h)
- [ ] Keyboard: US layout + modifier row
- [ ] 3-finger swipes → shortcut reports (target-OS table in Settings)
- [ ] Foreground service; release-all reports on disconnect/pause
- [ ] Unit tests: gesture engine, report encoding
- [ ] Manual checklist passes on macOS

## v0.2 — Polish

- [ ] Tap-and-drag, middle click
- [ ] Media keys (Consumer Control, report ID 3)
- [ ] Reconnect UX; multi-host bonded-device switching
- [ ] Windows/Linux checklists verified

## v1 — Store-ready

- [ ] Non-US keyboards / CJK (clipboard-paste route candidate)
- [ ] Onboarding, haptics, theming; Play Store release

## v2 — Helper (Tier 2)

- [ ] `BleTransport` + Wire Protocol v1 (`docs/protocol.md`)
- [ ] Flutter desktop helper in `helper/`: macOS (CGEvent + Accessibility onboarding) → Windows (SendInput) → Linux (uinput + udev rule)
- [ ] Helper-side gesture→action config per OS/DE

## v2+ — Stretch: Tier 3 interactive gestures (macOS)

- [ ] Research private Dock gesture injection (license-review Mac Mouse Fix first)
- [ ] Phased Mission Control/Spaces scrubbing with pause + cancel
- [ ] macOS version gate + Tier 2 auto-fallback

## v3 — iOS client (BLE only — iOS cannot do HID)

- [ ] Swift `BleTransport` (`CBPeripheralManager`); same Flutter UI; App Store release
