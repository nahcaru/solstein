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

---

## ADR-008: Presenter mode maps phone orientation to the pointer; absolute HID pointing rejected

**Status**: Accepted (absolute pointing over HID rejected after hardware test)
**Date**: 2026-09-19

### Context

A presenter needs to point at the screen from across the room. Premium presenters (Logitech Spotlight and kin) do this with a hybrid: relative deltas while gliding, and direct absolute pointing while a spotlight button is held. Helm's event vocabulary had no absolute position, its descriptor had no absolute report, and its only motion source was the touchscreen.

### Decision

1. `MotionEngine`, a second pure-Dart engine beside `GestureEngine`: timestamped `MotionSample`s in, `InputEvent`s out, no platform imports. Rates come from a `MotionSource` seam (`sensors_plus` today), with gyro-bias learning while still, a gravity-derived complementary filter for pitch, and roll compensation about the pointing axis.
2. Gliding maps angular velocity to relative `PointerMove` on the existing mouse report. (A separate Spotlight/Precision pad was tried and is superseded by the clutch and ballistics of ADR-009.)
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
- There is no direct-pointing (absolute) spotlight over HID. True absolute pointing waits for the v2 helper.
- **Any future descriptor change must be tested for regressions in the existing reports on real hosts**, not only by the golden-bytes test: the descriptor was well formed and its reports correct, and it still broke unrelated buttons.
- Yaw has no absolute reference indoors (the magnetometer is unreliable), so an absolute spotlight would re-zero yaw on every press; pitch is gravity-anchored and does not drift.
- `MotionConfig` has value equality, `GestureConfig` does not. A config change resets the engine, and a motion reset discards the gyro-bias estimate, so a freshly built but identical config must not read as "changed". `GestureConfig` has the same latent behaviour today; harmless there, worth fixing separately.
- Sign conventions and `countsPerRadian` are derived, not measured; tune on a real phone.

---

## ADR-009: Presenter mode is a hold-to-move clutch with ballistics and tremor smoothing

**Status**: Accepted
**Date**: 2026-09-19

### Context

The first presenter mode moved the cursor whenever the phone moved. On a phone that is a real problem: tapping Click or Next shakes the phone, and the shake lands on the cursor. Its speed response was linear, with no hand-tremor handling. A research note on how the Logicool Spotlight remote works (gyro + accelerometer, a button as a virtual clutch, roll compensation, tremor filtering, non-linear acceleration) described the missing pieces.

### Decision

- **Virtual clutch.** The cursor follows the phone only while the big pad is held. A "Hold to move" setting turns this off ("always on"), in which case the pad freezes the pointer. The pad replaces the separate Spotlight/Precision pad.
- **Ballistics.** Output angular rate goes through `sign(ω)·ω_ref·(|ω|/ω_ref)^p`, so unit gain sits at `ω_ref` and p = 1 is the old linear response. Defaults: `ω_ref` = 0.4 rad/s (ordinary pointing speed, ≈23°/s) and p = 1.15, adjustable in Settings (1.0–1.6). It acts on angular rate, so it does not depend on the sampling rate. The first defaults (`ω_ref` = 1 rad/s, p = 1.4) put unit gain at a fast sweep, so ordinary 10–30°/s pointing got only 0.5–0.76× of a linear response and felt too slow on a real phone; a regression test now pins slow pointing at ≥85% of linear and 3 rad/s flicks at 1.1–1.5×.
- **Tremor smoothing.** A One Euro filter on the projected yaw/pitch rates (min cutoff 1.5 Hz, beta 0.08). Measured on synthetic input against the same curve with smoothing off: a ±0.2 rad/s tremor keeps ~8% of its movement at 9 Hz, ~4% at 12 Hz and ~20% at 6 Hz; a 0.5 Hz, ±1 rad/s sweep passes at ~99.6%.
- **Bias is learned whenever the phone is still**, with a wide gate (0.15 rad/s) while the clutch is released and a tight one (0.05 rad/s) while engaged. An independent review showed the first design (learn only while released) let "always on" mode creep forever, and that a one-shot narrowing gate locked out a bias that grew later; neither gate is one-shot now. A 2-second Recalibrate is available from a motion-diagnostics screen showing sample rate, raw gyro and learned bias.
- **One shared engine.** `MotionSession`, owned by `AppModel`, holds the engine and a reference-counted sensor feed, so the presenter and diagnostics share the learned bias and Recalibrate acts on the engine doing the pointing. `MotionEngine.config` is swappable in place so dragging a slider does not discard calibration.
- **Sampling at 100 Hz.**
- **Hands-free.** Haptics, keep-screen-on, and volume keys as Prev/Next through a small `PresenterBridge`. No HID descriptor change.
- **Slideshow laser toggle.** A Laser button sends the app's own laser-pointer shortcut (PowerPoint Ctrl/⌘+L, Google Slides L, Keynote C). Because the host cursor already follows the phone, the built-in laser follows it too, with nothing installed. Not verified on hardware yet.

### Alternatives Considered

- **Keep always-on motion.** No new concept, but tap-shake on the cursor stays and there is no way to re-grip at the end of an arm's range.
- **Keep a separate Precision pad.** Explicit fine positioning, but one more control to learn; the ballistics curve gives the same control automatically.
- **A low-pass filter with a fixed cutoff.** Simpler, but it either smears fast flicks or lets tremor through. One Euro adapts to speed.
- **Anti-wind-up clamping (from the research note).** Not needed: output is relative, so the host clamps at the edge and the rotation beyond it is lost. It would matter only for absolute mapping, which HID cannot carry (ADR-008).
- **Screen overlays (dimmed spotlight, magnifier, digital laser).** They need software on the computer; left to the v2 helper.

### Consequences

- The behaviour users saw first (always following) changes; "Hold to move" off restores it.
- A bias that jumps by more than the tight gate while engaged in always-on mode is only recovered by releasing the pad (wide gate) or Recalibrate.
- The smoothing and ballistics defaults are estimates. The diagnostics screen exists so they can be tuned on a real phone.
- Volume-key capture depends on the device and OS version and must be tested on hardware.
- The research note says the trackpad uses `f(v) = v^1.4`; the code's `accelExponent` default is 1.0 (linear), so there was no shared curve to reuse.
- 100 Hz motion means about 100 HID mouse reports per second while moving. Watch for congestion; the sampling period can be lowered.
