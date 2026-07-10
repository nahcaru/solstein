# Architecture

## System

```
┌─────────────────────────────────────────────┐
│ Flutter Client (app/) — Android v0.1, iOS v3│
│                                             │
│  UI: TrackpadSurface · KeyboardScreen ·     │
│      PairingScreen · Settings               │
│        ↓ raw PointerEvents (Listener)       │
│  Gesture Engine (pure Dart)                 │
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
  // {pointer, keyboard, discreteGesture, phasedGesture}
}
```

UI adapts to `capabilities`; it never branches on concrete transport type.

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
- Link congestion → latest-wins coalescing for moves/scroll/phases; **never** drop button/key events.

## Testing

- Unit (CI): gesture engine on synthetic pointer streams; HID report byte encoding; protocol round-trips.
- Manual integration checklist (per host OS): pair → pointer → tap/right-tap → 2-finger scroll → typing with modifiers → 3-finger swipes → screen-off survival → reconnect after host sleep.
