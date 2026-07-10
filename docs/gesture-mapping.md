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
  n=2: move                   → SCROLLING (stream Scroll dx,dy)
       up < tapTimeout        → RightTap
  n=3: dominant-axis ≥ trigger→ SWIPE(dir): began/changed(progress)/ended
```

Defaults (settings-tunable, unit-tested): tap timeout 250 ms · touch slop 8 px · swipe trigger 48 px · pointer acceleration `f(v)=v^1.4` clamped ±127/report.

## InputEvent vocabulary

```dart
sealed class InputEvent {}
class PointerMove(int dx, int dy);
class ButtonEvent(Button b, bool down);
class Scroll(int dx, int dy);
class KeyEvent(int usage, int modifiers, bool down);
class GesturePhase(GestureKind kind, Phase phase, double progress);
```

`HidTransport` collapses `GesturePhase` → shortcut at `ended && progress ≥ 0.5`. `BleTransport` forwards phases verbatim (see `protocol.md`).

## Gesture → action per target OS

| Gesture | macOS | Windows | Linux (GNOME v0.1 default) |
|---|---|---|---|
| 3-finger ↑ | `Ctrl+↑` Mission Control | `Win+Tab` Task View | `Super` Activities |
| 3-finger ↓ | `Ctrl+↓` App Exposé | `Win+D` show desktop | `Super+D` |
| 3-finger ←/→ | `Ctrl+←/→` Spaces | `Ctrl+Win+←/→` desktops | `Super+PgUp/PgDn` |
| 2-finger tap | right click | right click | right click |

Target OS is a Settings toggle in v0.1; helper-side config in v2 (Linux DE variants live there).

## Tier 3 implementation notes (v2+)

- Synthesize undocumented gesture-phase events consumed by the Dock (prior art: **Mac Mouse Fix** — review its license first; treat source as documentation of the technique).
- Phone streams `GesturePhase(progress)` at 60–90 Hz; helper maps progress → event deltas. Release <50% → macOS springs back (cancel); ≥50% → commits.
- Version-gate per macOS release; auto-fallback to Tier 2 shortcuts on failure.
