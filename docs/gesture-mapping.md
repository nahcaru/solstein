# Gesture Mapping

## Three-tier capability model

**Core constraint: discrete shortcuts cannot pause mid-animation; only phased gesture injection can.**

| Tier | Transport | Mechanism | Pause/scrub/cancel? | When |
|---|---|---|---|---|
| 1 | HID | Phone detects gesture → shortcut key report | ❌ | v0.1, all host OSes |
| 2 | BLE + helper | Helper injects shortcuts via public APIs | ❌ | v2 |
| 3 | BLE + helper | Private macOS Dock gesture-phase events | ✅ | v2+ stretch, macOS only |

Exception: two-finger **scroll** is continuous input, hence naturally pausable at every tier (no native momentum below Tier 3).

## Gesture Engine state machine

```
IDLE ─pointer down─▶ TOUCHING(n)
  n=1: move ≥ slop            → POINTING (stream PointerMove)
       up < tapTimeout & slop → Tap (left click)
       long-press then move   → DRAGGING (button held)
       tap, re-touch < tapDragTimeout, move → DRAGGING (tap-and-drag)
  n=2: move                   → SCROLLING (stream Scroll dx,dy)
       fast horizontal (≥ flickVelocity, |dx|≥2|dy|) → PAGE_SWIPE(dir): phased
       both fingers opposing-radial (apart/together) → ZOOM(in/out): phased
       up < tapTimeout        → RightTap
  n=3: dominant-axis ≥ trigger→ SWIPE(dir): began/changed(progress)/ended
       up < tapTimeout        → MiddleTap (middle click)
  n=4: mean finger↔centroid distance grows ≥ spreadRatio → SPREAD: phased
       …or shrinks ≤ 1/spreadRatio → PINCH: phased (restore windows)
```

Defaults (settings-tunable, unit-tested): tap timeout 250 ms · touch slop 8 px · swipe trigger 48 px · tap-drag window 300 ms · page-flick velocity 0.6 px/ms · spread trigger ratio 1.4 · pointer response linear (`f(d)=d`, distance-proportional; the host's own mouse acceleration is the only curve — exponent configurable) clamped ±127/report.

## InputEvent vocabulary

```dart
sealed class InputEvent {}
class PointerMove(int dx, int dy);
class ButtonEvent(Button b, bool down);
class Scroll(int dx, int dy);
class KeyEvent(int usage, int modifiers, bool down);   // KeyInput in code
class MediaTap(MediaKey key);                          // volume/playback/brightness
class GesturePhase(GestureKind kind, Phase phase, double progress);
```

`HidTransport` collapses `GesturePhase` → shortcut at `ended && progress ≥ 0.5`. `BleTransport` forwards phases verbatim (see `protocol.md`).

## Gesture → action per target OS

| Gesture | macOS | Windows | Linux (GNOME v0.1 default) |
|---|---|---|---|
| 3-finger ↑ | `Ctrl+↑` Mission Control | `Win+Tab` Task View | `Super` Activities |
| 3-finger ↓ | `Ctrl+↓` App Exposé | `Win+D` show desktop | `Super+D` |
| 3-finger ←/→ | `Ctrl+←/→` Spaces | `Ctrl+Win+←/→` desktops | `Super+PgUp/PgDn` |
| 2-finger fast flick ←/→ | `Cmd+[/]` back/forward | `Alt+←/→` | `Alt+←/→` |
| 4-finger spread | `F11` show desktop | `Win+D` | `Super+D` |
| 4-finger pinch | `F11` restore windows | `Win+D` | `Super+D` |
| 2-finger pinch | `Cmd ±` zoom (discrete) | `Ctrl ±` | `Ctrl ±` |
| 2-finger tap | right click | right click | right click |
| 3-finger tap | middle click | middle click | middle click |

Horizontal kinds (3-finger ←/→, page flicks) swap under natural scrolling — content follows fingers, like a real trackpad. Vertical kinds never invert.

Two-finger zoom is a **discrete** Tier-1 approximation (`Cmd ±` steps): it works wherever those shortcuts do (browsers, editors, Finder), but not the continuous native pinch in Preview/Maps/Photos. **Smart zoom** (two-finger double-tap) and **rotate** have no system keyboard shortcut on macOS and cannot be done over Tier-1 HID — they wait for the v2 helper (Tier 2/3).

Target OS is a Settings toggle in v0.1, guessed from the host's Bluetooth name on first connect and remembered per device (an explicit choice wins); helper-side config in v2 (Linux DE variants live there).

Since the collapsed shortcuts toggle host modes, the transport keeps a host-mode estimate (vertical Exposé⇄desktop⇄Mission-Control level + desktop-shown flag) so repeated gestures never undo themselves; clicks/keys reset it.

## Tier 3 implementation notes (v2+)

- Synthesize dock-swipe gesture-phase events consumed by the Dock. Uses **public** `CGEventTap`/`CGEventPost`; only the CGEvent field indices (55, 110, 132…) are undocumented — stable since macOS 10.11 (see prior art).
- Phone streams `GesturePhase(progress)` at 60–90 Hz; helper maps progress → event deltas. Release <50% → macOS springs back (cancel); ≥50% → commits.
- Version-gate per macOS release; auto-fallback to Tier 2 shortcuts on failure.

### Prior art

- [joshuarli/iss](https://github.com/joshuarli/iss) — minimal synthetic dock-swipe (Begin+End, high velocity); best starting point
- [noah-nuebling/mac-mouse-fix](https://github.com/noah-nuebling/mac-mouse-fix) — production phased scrubbing. **MMF License restricts reuse: technique reference only, do not copy code**
- Path A references: [ginkage/wearmouse](https://github.com/ginkage/wearmouse) (canonical `BluetoothHidDevice` sample, Apache-2.0), [jqssun/android-bt-remote](https://github.com/jqssun/android-bt-remote)
- Descriptor validation: [Eleccelerator parser](https://eleccelerator.com/usbdescreqparser/) — run `SOLSTEIN_DESCRIPTOR` through it before first pairing test
- v2 BLE candidate: [`bluetooth_low_energy`](https://pub.dev/packages/bluetooth_low_energy) (PeripheralManager on Android & iOS) — evaluate before writing custom GATT channels
