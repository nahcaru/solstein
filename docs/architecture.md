# Architecture

## System

```
┌─────────────────────────────────────────────┐
│ Flutter Client (app/) — Android v0.1, iOS v3│
│                                             │
│  UI: TrackpadSurface · PresenterSurface ·   │
│      MediaSurface · KeyboardScreen ·        │
│      PairingScreen · Settings               │
│   ↓ raw PointerEvents    ↓ gyro + accel     │
│  Gesture Engine        Motion Engine        │
│  (pure Dart)           (pure Dart)          │
│        ↓ InputEvent                         │
│  InputSink interface   ← transport seam     │
│        ↓                        ↓           │
│  HidTransport (Kotlin)    BleTransport (v2) │
│  BluetoothHidDevice       BLE GATT server   │
└────────┬──────────────────────┬─────────────┘
         │ BT Classic HID       │ BLE GATT
         ▼                      ▼
   Any OS natively        Helm Helper (helper/, v2)
   (mac/Win/Linux,        Flutter desktop, BLE central
    zero install)         → native input injection
```

## Client layers

### UI
- `TrackpadSurface`: full-screen `Listener` consuming raw `PointerEvent`s. Never `GestureDetector` — too lossy/latent for a trackpad.
- `KeyboardScreen`: text input + modifier row (⌃⌥⌘⇧, arrows, Esc).
- `Settings`: target-OS selector (switches gesture→shortcut table), pointer speed, scroll direction.

### Gesture Engine
- Pure Dart, zero platform imports. `List<PointerSample> → List<InputEvent>`, deterministic, unit-tested.
- State machine keyed on pointer count — see `gesture-mapping.md`.

### InputSink

```dart
abstract interface class InputSink {
  Future<void> connect(DeviceTarget target);
  Future<void> disconnect();
  void send(InputEvent event);
  Stream<SinkState> get state;
  Set<Capability> get capabilities;
  // {pointer, keyboard, discreteGesture, phasedGesture, mediaKeys,
  //  absolutePointer}
}
```

UI adapts to `capabilities`; it never branches on concrete transport type.

### Presenter mode (laser pointer)

`PresenterSurface` is a sibling of `TrackpadSurface`, toggled from the app bar. Phone motion flows `MotionSource` (`sensors_plus`, 100 Hz gyro + accelerometer) → `MotionSession` → `MotionEngine` (pure Dart, timestamped `MotionSample`s in, `InputEvent`s out) → `InputSink`. The engine mirrors `GestureEngine`: deterministic, no platform imports, unit-tested on synthetic streams. `MotionSession` (owned by `AppModel`) holds the one shared engine and a reference-counted sensor feed, so the presenter and the motion-diagnostics screen see the same learned gyro bias and "Recalibrate" acts on the engine doing the pointing.

The design follows how a presentation remote works (research note: Logicool Spotlight):

- **Virtual clutch**: the cursor follows the phone only while the big pad is held. The shake of tapping Click/Next never reaches the cursor, and an arm at its limit can let go and re-grip. "Hold to move" can be turned off; the pad then freezes the pointer instead.
- **Roll compensation**: angular rates are projected onto world axes using gravity, so a sweep stays horizontal however the phone is rolled about its pointing axis.
- **Tremor smoothing**: a One Euro filter on the projected rates. Low speed → low cutoff (measured on synthetic input: a 9 Hz tremor keeps ~8% of its movement, 12 Hz ~4%, 6 Hz ~20%); high speed → the cutoff opens so a flick is not smeared.
- **Ballistics**: output rate ∝ `|ω|^p`, normalized to unit gain at 0.4 rad/s (≈23°/s, ordinary pointing speed), p = 1.15. Slow pointing stays close to 1:1 like a laser, quick flicks reach somewhat further (gain ≈1.35 at 3 rad/s). A first version pivoted at 1 rad/s with p = 1.4, which made 10–30°/s pointing run at about half speed. (The trackpad's `accelExponent` defaults to 1.0, i.e. linear — there was no existing curve to reuse.)
- **Drift**: the gyro bias is learned whenever the phone is still — with a wide gate (0.15 rad/s) while the clutch is released and a tight one (0.05 rad/s) while engaged, so "always on" mode does not creep either and a bias that grows later is still found. It can be relearned in 2 s from the diagnostics screen.
- **No wind-up handling needed**: output is relative, so the host stops the cursor at the screen edge and rotation beyond it is lost; swinging back responds immediately. (Wind-up only exists for absolute mapping, which HID cannot carry — ADR-008.)
- **Quiet when covered**: Settings and the diagnostics screen are pushed over the presenter, so it releases the clutch, the volume keys and the sensors while they are open.
- **Hands-free**: haptics on every button, screen kept on while presenting, and volume up/down as Prev/Next (`PresenterBridge.kt`; captured only while presenting, released on pause).
- **Slide and laser keys** are sent directly, not through the per-OS gesture tables: Prev/Next are Page Up / Page Down; Laser toggles the slideshow app's own laser pointer (`hid/laser_shortcuts.dart`, PowerPoint / Google Slides / Keynote — **shortcuts not yet verified on hardware**).

`PointerAbsolute` and `Capability.absolutePointer` stay in the shared vocabulary for a future helper; `HidTransport` does not declare the capability and drops the event. On-screen effects (dimmed spotlight, magnifier, digital laser) need software on the computer and are v2 helper work (roadmap).

Rationale and rejected alternatives: ADR-008 (HID), ADR-009 (presenter design).

### Media control mode

`MediaSurface` is the third pointer-area surface, picked from the app bar's mode menu (`ControlMode`: trackpad, presenter, media; an entry appears only if the sink declares the capability it needs, `Capability.mediaKeys` for media). It sends `MediaTap` through the existing Consumer Control report (ID 3), so there is no descriptor, protocol or Kotlin transport change.

- **Buttons** fire on pointer-down. Volume down/up repeat while held via `KeyRepeater` (`ui/key_repeat.dart`), which uses the same pace as a held backspace: a long-press delay, then every `kKeyRepeatInterval` (40 ms).
- **Hardware volume keys** are captured while the surface is showing and drive the host's volume instead of the phone's. `PresenterBridge` now also reports the key's release (`up:release` / `down:release`) so Dart can start and stop the repeat; Presenter ignores releases and behaves as before. Capture is dropped when Settings covers the surface, on pause and on leaving the mode.
- **Keep-awake** has a Media option; the persisted index order is unchanged (`Media` was appended).

A second row under the playback buttons, shown only if the sink has `Capability.keyboard`, sends **seek back, seek forward, captions and fullscreen**. The consumer page has no usage for them, so they are ordinary key strokes (`hid/player_shortcuts.dart`): ←, →, C and F. That one set matches YouTube (arrows seek 5 s), Netflix (10 s; it has no captions key, so the C button does nothing there) and Prime Video (10 s), per their official shortcut pages. Letters resolve through the host layout like the Laser shortcut, and the buttons do not repeat when held. Players with other keys (VLC, Spotify) are not covered. A now-playing display is not possible over HID; it is on the v2 helper list in the roadmap.

Rationale: ADR-012, ADR-013.

### Transports
- **`HidTransport`** (v0.1): Dart side of a MethodChannel; Kotlin module owns `BluetoothHidDevice` (`registerApp` → callbacks → `sendReport`) inside a foreground service (`connectedDevice`). Collapses `GesturePhase` events into shortcut key reports at `ended && progress ≥ 0.5`. Spec: `hid-descriptor.md`.
- **`BleTransport`** (v2): phone-side GATT server. Forwards phases verbatim. Spec: `protocol.md`.

## Helper (v2)

Shared Dart core (BLE central, protocol decode, tray UI, per-OS gesture config) + thin native injection:

| OS | API | Notes |
|---|---|---|
| macOS | `CGEvent` → `cghidEventTap` | Accessibility permission onboarding. Tier 3: private Dock gesture events, version-gated |
| Windows | `SendInput` | No special permissions |
| Linux | `/dev/uinput` (FFI) | Ship udev rule; kernel-level → X11 and Wayland |

## Error handling rules

- `getProfileProxy` failure (OEM disabled HID profile) → diagnostics screen, never crash.
- Any disconnect/pause → send release-all mouse + keyboard reports (stuck-key prevention).
- Presenter mode stops the sensor stream, opens the clutch, releases a held click, gives back the volume keys and the screen timeout on app pause and on leaving the mode.
- Link congestion → latest-wins coalescing for moves/scroll/phases; **never** drop button/key events.
  - Over HID this is a fixed ~66 Hz (15 ms) throttle window in `HidTransport`, and reports are sent from a background thread (ADR-010).

## Testing

- Unit (CI): gesture engine on synthetic pointer streams; HID report byte encoding; protocol round-trips.
- Manual integration checklist (per host OS) — unit tests cannot cover timing under a real thumb, nor whether a collapsed shortcut does what the host actually does:
  - **Pair/link**: pair → pointer moves → screen-off survival → reconnect after host sleep → switch to a second bonded host and back.
  - **Pointer**: tap-click → 2-finger tap (right click) → 3-finger tap (middle click) → long-press drag → tap-and-drag (tap, re-touch, move) inside the 300 ms window.
  - **Scroll/flick**: 2-finger scroll v+h → sign matches the host's natural-scroll setting → fast h-flick pages back/forward without a stray scroll.
  - **Gestures**: 3-finger ↑/↓/←/→ → 4-finger spread/pinch → 2-finger pinch-zoom → repeat each 3×, confirming the host-mode estimate never undoes itself; then click and confirm it resets.
  - **Keyboard**: typing with modifiers → per-OS modifier lineup → media row (volume/playback).
  - **Layout/IME**: set the host layout in Settings → JIS host types `@ : ^ ¥ ろ`
    correctly, US host unaffected → 英数/かな toggle the host IME from the phone →
    romaji becomes 日本語 without touching the host (spot-check Korean, Pinyin) →
    a character the layout can't produce (ñ on US) is refused visibly, and the
    next backspace deletes the right character.
  - **Media** (no re-pairing needed): Mode menu › Media → play/pause, previous and next control a player on the host → mute toggles → holding volume up/down ramps the host's volume at the same pace as a held backspace and stops on lift → the phone's volume rocker moves the host's volume and the phone's own volume UI does not appear → open Settings, or leave Media: the rocker moves the phone's volume again → background the app while holding the rocker: the host volume stops changing → Presenter's rocker still steps one slide per press → the row below play/pause: seek back/forward jump the video in a YouTube tab, in Netflix and in Prime Video; captions toggles subtitles in YouTube and Prime Video (Netflix has no key for it); fullscreen toggles fullscreen in all three (correct `player_shortcuts.dart` where one is wrong).
  - **Presenter** (no re-pairing needed; first confirm the **trackpad tap still clicks** — a descriptor change once broke it, ADR-008): pad released → shaking the phone moves nothing; hold the pad → the cursor follows → tapping Click/Next does not nudge the cursor → slow motion is fine, a quick flick reaches far → hold still 5 s, no creep → roll the phone 45° and sweep horizontally, still horizontal → Prev/Next step slides in Keynote, PowerPoint and Google Slides → haptic on each button → the screen does not dim while presenting → volume up/down = Prev/Next, and normal volume again after leaving → **Laser** toggles the built-in laser in each app (PowerPoint Ctrl/⌘+L, Google Slides L, Keynote C with its pointer preference on; correct `laser_shortcuts.dart` where one is wrong) → background the app mid-click: no stuck button → Settings › Motion sensors: ~100 Hz, Recalibrate settles the bias. If motion is inverted, flip both negations in `MotionEngine._glide`.
