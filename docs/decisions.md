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

---

## ADR-010: HID motion is throttled to ~66 Hz and sent off the main thread

**Status**: Accepted
**Date**: 2026-09-27

### Context

With Bluetooth headphones playing music, moving the pointer broke up the audio. With the headphones on the Mac, the music stuttered while the pointer moved. With them on the phone, the pointer itself lagged. Two causes combined:

- **An unthrottled report stream.** `HidTransport` flushed accumulated motion once per microtask, which in practice meant one HID report per touch sample (120 Hz or more) or per gyro sample in presenter mode (100 Hz, flagged in ADR-009). Each report is a separate over-the-air transmission competing with A2DP for radio time on whichever side is also streaming audio. `docs/protocol.md` already asked for "≤ ~90 Hz, latest-wins", but that was never implemented for HID.
- **`sendReport` on the main thread.** `BluetoothHidDevice.sendReport` is a blocking binder call, and it ran on Android's main thread, the same thread that delivers touch events. When the stack was busy with audio, touch dispatch waited on it.

### Decision

- **Throttled coalescing in `HidTransport`.** A single constant, `_motionInterval` = 15 ms (~66 Hz). The first move after idle still flushes on the next microtask, so the first move has no added latency. That flush opens a 15 ms window. Moves and scrolls inside the window accumulate and go out as one report when it closes, and the next window opens only if something was sent. Buttons, keys and media keys are never throttled. A click flushes *all* pending motion ahead of its edge (not just one throttled tick's worth — see ADR-011's second fix), and `releaseAll()` and `dispose()` cancel the pending window. (Superseded in one respect by ADR-011: a throttled flush now sends at most one report, not a split run of several.)
- **A dedicated send thread in `HidManager`.** All `sendReport` calls are posted to one `HandlerThread` ("helm-hid-send"), which keeps mouse, keyboard and consumer reports in order. `disconnect()`, the host-switch path of `connect()`, and `stop()` post their Bluetooth teardown calls to the same queue, behind the release-all reports, so the releases are sent before the link drops.
- **QoS stays best-effort.** `registerApp` still passes `null` QoS. Reserving bandwidth with `BluetoothHidDeviceAppQosSettings` would take guaranteed airtime from A2DP, which is the opposite of what we want.

### Alternatives Considered

- **~90 Hz, the protocol.md ceiling.** Closer to the touch rate, but fewer reports is the whole point. 66 Hz is still above the display rate of most hosts, and the pointer still feels smooth.
- **Adaptive rate (drop further when audio is detected).** The phone cannot see the Mac's audio link. A fixed interval is simpler and handles both cases.
- **Throttle in Kotlin instead of Dart.** It would also cover future callers, but accumulated deltas and the button-ordering rule already live in `HidTransport`. Throttling in Kotlin would duplicate that state across the channel.

### Consequences

- Pointer motion arrives at up to ~66 Hz, in slightly larger steps. It has not yet been checked on hardware whether this is enough on every host and headset. The interval is one constant, so it is easy to tune.
- Sends are fire-and-forget: the Dart side can no longer see the `sendReport` return value (it was already ignored).
- `stop()` clears its fields right away and unregisters asynchronously. A `start()` issued within the same few milliseconds could briefly overlap the old proxy's teardown.

---

## ADR-011: a flush sends at most one HID report, never a split burst

**Status**: Accepted
**Date**: 2026-09-28

### Context

On-device testing of ADR-010's throttle found pointer movement noticeably more responsive, as intended, but Bluetooth music stutter got *worse*, not better.

The cause: `_flushMotion()` called `encodeMouseReports`, which splits an accumulated delta beyond ±127 into as many reports as needed and sends every one of them back-to-back with no gap, in the same microtask. Before ADR-010, each touch sample produced at most one report (the gesture engine already clamps a single sample's output to ±127), sent roughly every 8 ms on a 120 Hz+ touchscreen — never more than one report in a row. After ADR-010, a 15 ms window can accumulate more than one sample's worth of motion; a fast swipe easily sums past ±127, and the fix as first written then fired two or three reports at once every 15 ms instead of one report every 8 ms. Fewer reports on average, but bursty: several back-to-back over-the-air transmissions apparently cost the shared radio more than the same total data spread out, even at a higher steady rate.

### Decision

A *throttled* flush now sends **at most one** report: the pending deltas are clamped to ±127 for that report, and whatever remains subtracted back into the pending accumulators instead of being sent immediately. The already-armed 15 ms window picks up the remainder on its next tick. No distance is lost, an extreme flick just catches up over a couple of extra ticks instead of arriving all at once.

`encodeMouseReports` (the multi-report splitter) is still used, but no longer by the throttled path — `_flushMotion()` stopped being one of its callers. It moved to a second, separate method, `_flushAllMotion()`, used only for the button-edge ordering guarantee: a `ButtonEvent` must send *all* pending motion before its edge, not just one throttled tick's worth, or motion from before the edge can arrive after it carrying the new button state — a drag's tail end continuing to move with the button released, or pre-click hover motion turning a plain click into an accidental drag. This was a regression caught by review shortly after this ADR's first version, not by device testing; the burst it can cause only happens at a click boundary (rare), not continuously during a swipe, so it doesn't reintroduce the problem this ADR fixes.

### Alternatives Considered

- **Shorten `_motionInterval`.** A smaller window accumulates less per tick, but does not eliminate bursts outright — a fast enough swipe still exceeds ±127 in any fixed window, and a shorter interval also gives back some of ADR-010's reduction in report count.
- **Lower the gesture engine's per-sample gain.** Would shrink deltas app-wide, changing pointer feel to work around a transport-layer problem.

### Consequences

- Very fast flicks lag the finger by up to a couple of throttle ticks (~30 ms) before the pointer catches up, rather than jumping the full distance in one 15 ms step. Confirmed on hardware: pointer motion is smoother and Bluetooth audio contention is markedly better than both the pre-ADR-010 baseline and this ADR's first version.
- A click or drag release with a large backlog queued (a fast flick immediately followed by lifting the finger) can still burst several reports at once via `_flushAllMotion()` — rare enough, and discrete enough, not to matter for audio coexistence.

---

## ADR-012: Media control mode — a third surface, phone volume keys, Dart-driven repeat

**Status**: Accepted
**Date**: 2026-10-03

### Context

Media keys were reachable only from a small row in the keyboard drawer. The goal is a couch remote: large targets for play/pause, previous/next and volume, usable without looking, with the phone's own volume rocker controlling the computer's volume. The Consumer Control report (ID 3) already existed, so this is a UI and phone-side change.

### Decision

- **A third mode, not a second boolean.** `ControlMode { trackpad, presenter, media }` replaces `_presenterVisible`; the header offers one mode menu whose entries are gated on sink capabilities. Two flags could be true at once.
- **Volume as buttons**, with hold-to-repeat at the backspace pace (`KeyRepeater`, 40 ms after the long-press delay). HID consumer controls have no absolute level, so a slider would only be a disguised repeat gesture.
- **Hardware volume keys are captured while Media shows**, reusing the Presenter capture. The native side previously reported only the first DOWN, so it now also reports the release. Repeat is driven from Dart rather than from Android's key auto-repeat, so on-screen and hardware volume repeat identically.
- **Not gated by the Presenter "Volume keys" setting.** Volume control is the point of this mode.
- **Keep-awake** gains a Media option, appended so saved indices keep their meaning.

### Alternatives Considered

- **A separate pushed screen** (like Settings): loses the shared keyboard drawer and keep-awake wiring, and is inconsistent with Presenter.
- **Use Android's repeatCount events for hardware repeat:** its delay and rate are the OS's, so they would differ from the on-screen buttons.
- **Brightness on the remote:** not a couch control; it stays on the keyboard row.

### Consequences

- The Presenter event stream changed type (`VolumeKeyEvent` with `pressed`); Presenter filters to presses.
- Each `MediaTap` is a self-contained press and release, so nothing is ever left held on the host; backgrounding or covering the surface only has to stop the Dart-side repeat, which it does.
- Volume-key capture is released in `deactivate()`, not `dispose()`, in both Presenter and Media. When the mode changes, the incoming surface's `initState` runs before the outgoing one's `dispose`, so a release in `dispose` landed last and switched the capture off.
- Verified on a phone after implementation.
- The play button shows a fixed combined play/pause icon, not the current state: HID is one-way, so the phone cannot read whether the host is playing, and a guess from its own taps would go wrong whenever something else changes the state (the keyboard, a video ending, another app).

---

## ADR-013: Media player keys — seek, captions, fullscreen as one fixed key set

**Status**: Accepted (not yet tried on a phone)
**Date**: 2026-10-04

### Context

A couch remote also needs to jump back and forward, toggle captions and go fullscreen. The Consumer Control page has no usage for any of these, and there is no way to ask the host what is playing, so the phone cannot tell which player is open.

### Decision

Send ordinary key strokes, as four buttons in a row under the playback buttons: **←, →, C and F**. This is the largest set common to the major web players, checked against each vendor's own shortcut page:

| Player | ← / → | C captions | F fullscreen | Source |
|---|---|---|---|---|
| YouTube | seek 5 s | yes | yes | support.google.com/youtube/answer/7631406 |
| Netflix | seek 10 s | **no key** | yes | help.netflix.com/en/node/24855 |
| Prime Video | seek 10 s | yes | yes | amazon.com/gp/help/customer/display.html?nodeId=GH5GWCRVQCKEEFM8 |

- **Arrows, not J / L.** YouTube's J / L seek 10 s, but Netflix's and Prime Video's shortcut pages list no J / L; the arrows work in all three.
- **No player setting.** An earlier version chose between a J / L set and an arrow set; with J / L dropped the two were identical, so the setting and its persistence were removed.
- **Seek, captions and fullscreen do not repeat when held**, unlike volume: at the 40 ms backspace pace a held seek would jump minutes in a second.
- **The buttons say "Seek", not "10 s"**, since the step is the player's.
- **The row needs `Capability.keyboard`**, and is hidden when the host layout cannot type C or F.

The research was delegated to Antigravity and then checked against the vendor pages: several of its URLs and some of its rows were wrong (a dead Netflix link, unsupported claims for QuickTime, Hulu and Windows media apps), so only rows confirmed on the vendor's own page are used.

### Alternatives Considered

- **A per-player setting (YouTube / Arrow keys / VLC / ...).** Needed only for players whose keys differ. VLC (Shift = 5 s, Alt = 10 s, Ctrl = 1 min + arrow; V cycles subtitles; per wiki.videolan.org/Hotkeys/) and Spotify (Shift + arrow) are the known examples. Not built until someone wants one; the setting can be re-added with a second key set.
- **Detect the player.** Not possible from a HID peripheral.
- **Per-OS keys.** The three web players use the same keys on every OS.

### Consequences

- On Netflix the Captions button does nothing; on VLC the seek buttons do nothing useful.
- Mac-native players (QuickTime, Apple TV app) and mpv/IINA are not verified here and may or may not respond to the same keys.
- A now-playing display remains out of reach until the v2 helper (roadmap).
