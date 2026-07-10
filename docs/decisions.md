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
