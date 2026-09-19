# Architecture Decision Records

## ADR-001: Hybrid Bluetooth architecture — pure HID first, BLE + helper later

**Status**: Accepted
**Date**: 2026-07-10

### Context

Two viable ways to control a computer from a phone over Bluetooth: emulate a real HID peripheral (zero install on the host), or run a custom BLE link to a helper app that injects input (rich capabilities).

### Decision

v0.1 ships **pure HID** (Path A). v2 adds a **BLE GATT + desktop helper** (Path B) behind the same `InputSink` abstraction. The seam is designed in from day one.

### Alternatives Considered

- **Path A only**: dead end for iOS clients (no HID peripheral API) and for interactive gestures.
- **Path B only**: forces every user to install and trust a helper with Accessibility permissions just to move a cursor; loses login-screen support and free Windows/Linux compat.

### Consequences

Fastest path to a useful product; HID gives Windows/Linux support for free. Cost: two transports to maintain long-term.

---

## ADR-002: Flutter for client (and helper) UI

**Status**: Accepted
**Date**: 2026-07-10

### Context

iOS support is a future requirement, so a cross-platform framework is preferred. A trackpad app lives or dies on touch latency.

### Decision

Flutter for the client; Flutter desktop for the v2 helper. Transport layers are native modules regardless of framework (Kotlin for HID, Swift for iOS BLE).

### Alternatives Considered

- **Expo / React Native**: keeps TypeScript, but raw-touch pipeline crosses the JS boundary; lag-free trackpad requires worklet/JSI engineering.
- **Native Kotlin**: fastest MVP but UI layer rewritten for iOS.

### Consequences

Single UI/gesture codebase across Android/iOS/desktop; owner has prior Flutter experience. No plugin exists for the HID Device profile → custom platform channel (accepted in all options anyway).

---

## ADR-003: Combo HID descriptor (mouse + keyboard) instead of mouse-only

**Status**: Accepted
**Date**: 2026-07-10

### Context

A HID mouse alone cannot trigger Mission Control / Spaces. macOS only recognizes multi-touch gestures from devices it believes are Apple trackpads.

### Decision

Register one HID device with two report IDs: mouse (ID 1: buttons/ΔX/ΔY/wheel/pan) and keyboard (ID 2: modifiers + 6 keys). Phone-side gesture detection fires keyboard-shortcut reports (`Ctrl+↑` etc.).

### Alternatives Considered

- **Mouse-only descriptor**: no gestures at all in v0.1.
- **Emulating an Apple trackpad's HID descriptor**: macOS gesture recognition for trackpads runs through private vendor-specific protocols, not standard HID — not reproducible.

### Consequences

Gestures work with zero host software, but are **fire-and-forget** (Tier 1) — no mid-gesture pause/scrub. Interactive gestures deferred to Tier 3 (ADR-005).

---

## ADR-004: Phone is the GATT server; wire protocol streams gesture phases from v1

**Status**: Accepted
**Date**: 2026-07-10

### Context

For Path B, either side could host the BLE connection, and gestures could be sent as discrete flags or as phased streams.

### Decision

Phone = BLE peripheral/GATT server; helper = central. The `GesturePhase` packet (began/changed/ended + progress + velocity) is part of Wire Protocol v1 even though v2 helpers only consume it discretely.

### Alternatives Considered

- **Helper as server**: phones running servers fight mobile background-execution limits; desktop centrals reconnect more reliably.
- **Discrete gesture flags in protocol**: simpler, but upgrading to interactive scrubbing (Tier 3) would break the protocol and require client updates.

### Consequences

Tier 3 becomes a pure helper-side upgrade. Slightly larger packets and coalescing logic needed at ~90 Hz.

---

## ADR-005: Interactive gesture scrubbing (Tier 3) is a v2+ stretch goal

**Status**: Accepted
**Date**: 2026-07-10

### Context

Pausable, scrubbing Mission Control/Spaces transitions (stop fingers → animation pauses) are impossible via public APIs; they require synthesizing private macOS Dock gesture events (prior art: Mac Mouse Fix).

### Decision

Ship Tier 2 (helper + public-API shortcuts) first; pursue Tier 3 afterward, version-gated per macOS release with automatic fallback to Tier 2. Review Mac Mouse Fix's license before reading its source.

### Alternatives Considered

- **Tier 3 as the v2 headline**: highest-value feature but open-ended research risk on undocumented APIs.
- **Dropping Tier 3**: simplest, but forfeits the helper's killer feature.

### Consequences

Predictable v2 milestone; Tier 3 fragility is contained behind a compatibility gate. macOS-only — Windows/Linux stay at Tier 2.

---

## ADR-007: Presenter mode maps phone orientation to the pointer; absolute HID pointing rejected

**Status**: Accepted (absolute pointing over HID rejected after hardware test)
**Date**: 2026-09-19

### Context

A presenter needs to point at the screen from across the room. Premium presenters (Logitech Spotlight and kin) do this with a hybrid: relative deltas while gliding, and direct absolute pointing while a spotlight button is held. Helm's event vocabulary had no absolute position, its descriptor had no absolute report, and its only motion source was the touchscreen.

### Decision

1. `MotionEngine`, a second pure-Dart engine beside `GestureEngine`: timestamped `MotionSample`s in, `InputEvent`s out, no platform imports. Rates come from a `MotionSource` seam (`sensors_plus` today), with gyro-bias learning while still, a gravity-derived complementary filter for pitch, and roll compensation about the pointing axis.
2. Gliding maps angular velocity to relative `PointerMove` on the existing mouse report. Holding Spotlight over HID is slow relative "precision" pointing.
3. `PointerAbsolute(double x, double y)` (normalized 0.0–1.0) and `Capability.absolutePointer` exist in the vocabulary and the engine, but **`HidTransport` does not declare the capability and drops the event**. A v2 helper injecting positions natively can honour it.
4. Prev/Next are Page Up / Page Down sent directly as `KeyInput`.

### Result of the hardware test

An absolute pointer was added as a fourth top-level descriptor collection (report ID 4, Generic Desktop / Mouse, 16-bit absolute X/Y, plus three button bits). On a Pixel 7a paired with a host, the phone sent correct reports (`ok=true`, verified in logcat), and pointing worked, **but the host stopped acting on the mouse buttons of report 1**: trackpad taps and the presenter Click did nothing, while keyboard reports (Prev/Next) kept working. Removing report 4 and re-pairing restored the buttons. So a second Mouse application collection breaks button handling on at least that host. The cause inside the host was not investigated.

### Alternatives Considered

- **A Digitizer/Stylus collection for the absolute report**: not tried. Might avoid the clash, but host behaviour for a generic Bluetooth digitizer is unpredictable and each attempt costs a remove-and-re-pair on every host. Revisit only with a way to test all three OSes.
- **A native Kotlin `SensorManager` channel on `TYPE_GAME_ROTATION_VECTOR`**: better long-horizon yaw stability, but rewritten in Swift for the v3 iOS client. Kept as a drop-in behind `MotionSource`.
- **`PointerAbsolute` as `int` 0…32767**: leaks one transport's quantization grid into the shared vocabulary.
- **Slide keys in `shortcut_tables.dart`**: that map is keyed by `GestureKind`; a `GestureKind.nextSlide` would break `GestureEngine`'s exhaustive switches.
- **Synthesizing absolute over the relative report** (home to a corner, then dead-reckon): hosts apply their own pointer acceleration, so the position is unknowable and guessing causes cursor runaway. Hence: a sink without the capability drops `PointerAbsolute`.

### Consequences

- Presenter mode works over HID with **no descriptor change and no re-pairing**.
- The spotlight over HID is precision gliding, not direct pointing. True absolute pointing waits for the v2 helper.
- **Any future descriptor change must be tested for regressions in the existing reports on real hosts**, not only by the golden-bytes test: the descriptor was well formed and its reports correct, and it still broke unrelated buttons.
- Yaw has no absolute reference indoors (the magnetometer is unreliable), so an absolute spotlight would re-zero yaw on every press; pitch is gravity-anchored and does not drift.
- `MotionConfig` has value equality, `GestureConfig` does not. A config change resets the engine, and a motion reset discards the gyro-bias estimate, so a freshly built but identical config must not read as "changed". `GestureConfig` has the same latent behaviour today; harmless there, worth fixing separately.
- Sign conventions and `countsPerRadian` are derived, not measured; tune on a real phone.
