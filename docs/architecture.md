# Architecture

## System

```
┌─────────────────────────────────────────────┐
│ Flutter Client (app/) — Android v0.1, iOS v3│
│                                             │
│  UI: TrackpadSurface · PresenterSurface ·   │
│      KeyboardScreen · PairingScreen ·       │
│      Settings                               │
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

`PresenterSurface` is a sibling of `TrackpadSurface`, toggled from the app bar. Phone motion flows `MotionSource` (`sensors_plus`: gyro + accelerometer) → `MotionEngine` (pure Dart, timestamped `MotionSample`s in, `InputEvent`s out) → `InputSink`. The engine mirrors `GestureEngine`: deterministic, no platform imports, unit-tested on synthetic streams.

- **Gliding** (default): angular velocity → relative `PointerMove`, like an air mouse.
- **Spotlight** (held): orientation → absolute `PointerAbsolute`, gated on `Capability.absolutePointer` and a per-host setting. `HidTransport` does **not** declare that capability (a separate absolute HID report made hosts ignore the mouse buttons — ADR-007), so over HID the spotlight is slow relative "precision" pointing. The absolute path stays in the engine for a v2 helper that injects positions natively; a sink without the capability drops `PointerAbsolute`, never fakes it with relative deltas.
- Rates are projected onto world axes using gravity, so a sweep stays horizontal however the phone is rolled about its pointing axis. Yaw has no absolute reference indoors, so it is re-zeroed on every spotlight press; pitch comes from gravity and cannot drift.
- Prev/Next are plain Page Up / Page Down, sent directly — not through the per-OS gesture tables.

Rationale and rejected alternatives: ADR-007.

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
- Presenter mode stops the sensor stream and resets the motion engine on app pause and on leaving the mode.
- Link congestion → latest-wins coalescing for moves/scroll/phases; **never** drop button/key events.

## Testing

- Unit (CI): gesture engine on synthetic pointer streams; HID report byte encoding; protocol round-trips.
- Manual integration checklist (per host OS) — unit tests cannot cover timing under a real thumb, nor whether a collapsed shortcut does what the host actually does:
  - **Pair/link**: pair → pointer moves → screen-off survival → reconnect after host sleep → switch to a second bonded host and back.
  - **Pointer**: tap-click → 2-finger tap (right click) → 3-finger tap (middle click) → long-press drag → tap-and-drag (tap, re-touch, move) inside the 300 ms window.
  - **Scroll/flick**: 2-finger scroll v+h → sign matches the host's natural-scroll setting → fast h-flick pages back/forward without a stray scroll.
  - **Gestures**: 3-finger ↑/↓/←/→ → 4-finger spread/pinch → 2-finger pinch-zoom → repeat each 3×, confirming the host-mode estimate never undoes itself; then click and confirm it resets.
  - **Keyboard**: typing with modifiers → per-OS modifier lineup → media row (volume/playback).
  - **Presenter**: toggle the mode → sweep the phone and the cursor glides → roll the phone 45° and sweep horizontally, still horizontal → hold Spotlight ("Precision"): slower, finer gliding → hold still 5 s, no creep → Prev/Next step slides in Keynote, PowerPoint and Google Slides → Click clicks → background the app mid-click: no stuck button → leave presenter mode and **tap the trackpad: it must still click** (this is what a descriptor change broke — see ADR-007). If motion is inverted, flip both negations in the relative step *and* both in the absolute step together.
