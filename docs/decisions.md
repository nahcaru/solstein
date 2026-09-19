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

## ADR-006: CJK rides the host's IME; arbitrary text waits for the helper

**Status**: Accepted
**Date**: 2026-07-16

### Context

HID transmits key positions, not characters — there is no usage code for 日. Yet
device testing (2026-07-16, Pixel 7a → macOS) showed CJK already working in v0.1:
pressing かな on the host and typing romaji through Helm produces 日本語, because
the *host's* IME does the conversion. Korean and Pinyin behave identically.

### Decision

CJK input is the host IME's job. Helm sends romaji as ordinary usage codes, keeps
its own field free of phone-side IME composition
(`TextInputType.visiblePassword`), and offers かな/英数 (LANG1/LANG2 on macOS) so
the phone can toggle the host IME. Characters no host layout can produce are
refused visibly and wait for the v2 helper's `Text` packet.

### Alternatives Considered

- **Clipboard-paste** (the original roadmap candidate): impossible. Nothing in HID
  lets a peripheral write the host's clipboard, and no host software is listening.
  It needs the thing v1 is defined as lacking. It is also worse than the
  alternative it was standing in for — pasting clobbers the user's clipboard.
- **Unicode Hex Input** (Option+hex / `Ctrl+Shift+U` / Alt+numpad): the only Tier-1
  route to arbitrary Unicode, but it requires the user to reconfigure their host —
  eroding the zero-install premise — is three fragile per-OS implementations, and
  on macOS is an input source *mutually exclusive with the IME* that makes CJK work
  at all. It would buy ñ-on-a-US-host, which a Spanish layout table sends natively.
- **Phone-side IME composition**: the phone can compose 日本語 but cannot transmit
  it; there is no usage code to carry the result.

### Consequences

CJK works at Tier 1 with zero host software, for Japanese, Korean, and Chinese
alike — at the cost of requiring the host to have its own IME configured, and of
telling users to keep their phone keyboard in English (the counterintuitive part).
Anything the host layout cannot express is deferred to v2. Prior art agrees:
Chromium's remoting protocol pairs a `usb_keycode` `KeyEvent` with a UTF-8
`TextEvent` for "input method different from physical keyboards, including
software keyboard" — the split Helm now mirrors across v1/v2.

---

## ADR-007: Host layout scope is US and JIS only

**Status**: Accepted
**Date**: 2026-09-18

### Context

Once `HostLayout` shipped as a data-only seam (see the design note in
`app/lib/hid/keymap.dart` and `docs/superpowers/specs/2026-07-16-v1-keyboard-design.md`),
the natural next question was how many layouts to add — French, German,
Thai, Arabic, Korean physical layout, etc. Each requires per-key verification
against a real host, per the existing rule that layouts ship only once
confirmed (the JIS table's own `¥ | \ _` and Option+¥ backslash mistakes,
caught only by real-device testing, are the cautionary example). CJK scripts
already type via the host's own IME on top of the existing US/JIS tables
(ADR-006) — they were never blocked on a new layout.

### Decision

v1 ships US and JIS only. The other layouts aren't ruled out architecturally —
`HostLayout` already supports letter-level overrides for a future AZERTY or
QWERTZ — but building and verifying tables for languages nobody here actually
types on is effort without a way to confirm correctness. Add a layout when
someone has a real host to test it against, not before.

### Consequences

Non-US-non-JIS hosts (French, German, Thai, Arabic keyboards, etc.) aren't
supported yet; typing on Helm against one of those layouts will send
US-positioned usage codes, matching pre-JIS v1 behavior for that host. Revisit
per-layout, on demand, each as its own small verified addition — not a batch.
