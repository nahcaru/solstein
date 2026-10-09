# Roadmap

## v0.1 — MVP (HID, Android → any OS)

Control a Mac with nothing installed on it.

- [x] `flutter create` in `app/` + Kotlin `HidTransport` platform channel
- [x] Combo HID descriptor registers; macOS pairs and sees "Solstein"
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
- [x] Brand Identity & App Icon System (ADR-015): The Double-Refraction Cursor (Concept #2) vector suite, full-bleed native app icon, Android Adaptive + Material You monochrome themed icon, iOS 18 AppIcon catalog, and web favicons.
- [ ] Onboarding, haptics, theming; Play Store release
- [x] Media control mode (ADR-012): a couch-remote surface (play/pause, prev/next, volume and mute buttons) beside Trackpad and Presenter, with the phone's volume keys driving the host's volume. Verified on a phone.
- [ ] Media player keys (ADR-013): seek back/forward (←/→), captions (C) and fullscreen (F) buttons in Media mode. The key set is confirmed against YouTube's, Netflix's and Prime Video's own shortcut pages; still to try on a phone. Players that differ (VLC: Shift/Alt/Ctrl + arrow, V for subtitles; Spotify: Shift + arrow) would need a second key set and a way to choose it — not built.
- [x] Presenter / laser-pointer mode over HID (ADR-008, ADR-009): gyro pointing with a hold-to-move clutch, ballistics, tremor smoothing, Prev/Next/Click, haptics, volume keys, screen kept on, motion diagnostics. Verified on a Pixel 7a with one host.
- [ ] Presenter: verify the Laser button's shortcuts (PowerPoint Ctrl/⌘+L, Google Slides L, Keynote C) in real slideshows; tune the smoothing, ballistics and `countsPerRadian` defaults on a phone; check the other OSes.
- [ ] Presenter with true absolute pointing. A second Mouse collection in the HID descriptor broke the host's mouse buttons (ADR-008), so this waits for the v2 helper (native injection) unless a Digitizer-based report is proven on real hosts.
- [ ] Presenter on-screen effects (v2 helper): dimmed spotlight, magnifier and digital laser drawn in an always-on-top overlay (CGEvent/overlay window on macOS, a topmost layer on Windows) — the part of a presentation remote that cannot be done over HID.

## v2 — Helper (Tier 2)

- [ ] `BleTransport` + Wire Protocol v1 (`docs/protocol.md`), incl. `Text`
      packets → native Unicode injection (replaces the clipboard-paste idea)
- [ ] Flutter desktop helper in `helper/`: macOS (CGEvent + Accessibility onboarding) → Windows (SendInput) → Linux (uinput + udev rule)
- [ ] Helper-side gesture→action config per OS/DE
- [ ] Now-playing display in Media mode (title, artist, position). HID is one-way, so a peripheral cannot read what the host is playing; this needs the helper to read the OS's media session (e.g. SMTC on Windows, MPRIS on Linux; macOS has no public API for other apps' now-playing info) and send it over BLE. Until then Media mode is a remote with no display.

## v2+ — Stretch: Tier 3 interactive gestures (macOS)

- [ ] Research private Dock gesture injection (license-review Mac Mouse Fix first)
- [ ] Phased Mission Control/Spaces scrubbing with pause + cancel
- [ ] macOS version gate + Tier 2 auto-fallback

## v3 — iOS client (BLE only — iOS cannot do HID)

- [ ] Swift `BleTransport` (`CBPeripheralManager`); same Flutter UI; App Store release
