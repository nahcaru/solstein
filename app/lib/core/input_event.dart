/// Input event vocabulary emitted by the gesture engine and consumed by
/// transports. Pure Dart — no platform imports (see docs/gesture-mapping.md).
library;

enum Button { left, right, middle }

enum GestureKind {
  // Three-finger swipes.
  swipeUp,
  swipeDown,
  swipeLeft,
  swipeRight,
  // Two-finger horizontal flick (fast) — browser back/forward. Slow
  // two-finger motion is scrolling, never a gesture.
  pageSwipeLeft,
  pageSwipeRight,
  // Four-finger spread — show desktop; pinch — restore windows.
  spread,
  pinch,
  // Two-finger pinch — zoom. Discrete Tier-1 approximation (Cmd±); true
  // continuous pinch-zoom needs the v2 helper.
  zoomIn,
  zoomOut,
}

enum GesturePhaseKind { began, changed, ended, cancelled }

/// Media functions exposed by the Consumer Control report. Declaration
/// order defines the bit position in the report (bit 0 = playPause) and
/// must match the descriptor's usage order.
enum MediaKey {
  playPause,
  nextTrack,
  prevTrack,
  volumeUp,
  volumeDown,
  mute,
  brightnessUp,
  brightnessDown,
}

sealed class InputEvent {
  const InputEvent();
}

/// Relative pointer motion in HID delta units (post-acceleration).
class PointerMove extends InputEvent {
  const PointerMove(this.dx, this.dy);

  final int dx;
  final int dy;

  @override
  bool operator ==(Object other) =>
      other is PointerMove && other.dx == dx && other.dy == dy;

  @override
  int get hashCode => Object.hash(PointerMove, dx, dy);

  @override
  String toString() => 'PointerMove($dx, $dy)';
}

class ButtonEvent extends InputEvent {
  const ButtonEvent(this.button, {required this.down});

  final Button button;
  final bool down;

  @override
  bool operator ==(Object other) =>
      other is ButtonEvent && other.button == button && other.down == down;

  @override
  int get hashCode => Object.hash(ButtonEvent, button, down);

  @override
  String toString() => 'ButtonEvent($button, down: $down)';
}

/// Scroll deltas: [dy] vertical wheel, [dx] horizontal pan.
class Scroll extends InputEvent {
  const Scroll(this.dx, this.dy);

  final int dx;
  final int dy;

  @override
  bool operator ==(Object other) =>
      other is Scroll && other.dx == dx && other.dy == dy;

  @override
  int get hashCode => Object.hash(Scroll, dx, dy);

  @override
  String toString() => 'Scroll($dx, $dy)';
}

/// A single key transition. [usage] is a HID Keyboard/Keypad page usage code;
/// [modifiers] is the modifier bitmask held during the transition.
/// (Named KeyEvent in the docs; renamed here to avoid colliding with
/// Flutter's KeyEvent, which material.dart re-exports.)
class KeyInput extends InputEvent {
  const KeyInput(this.usage, this.modifiers, {required this.down});

  final int usage;
  final int modifiers;
  final bool down;

  @override
  bool operator ==(Object other) =>
      other is KeyInput &&
      other.usage == usage &&
      other.modifiers == modifiers &&
      other.down == down;

  @override
  int get hashCode => Object.hash(KeyInput, usage, modifiers, down);

  @override
  String toString() =>
      'KeyInput(0x${usage.toRadixString(16)}, mods: 0x${modifiers.toRadixString(16)}, down: $down)';
}

/// A tap of a media function (volume, playback, brightness). Transports
/// emit the press-and-release pair themselves.
class MediaTap extends InputEvent {
  const MediaTap(this.key);

  final MediaKey key;

  @override
  bool operator ==(Object other) => other is MediaTap && other.key == key;

  @override
  int get hashCode => Object.hash(MediaTap, key);

  @override
  String toString() => 'MediaTap($key)';
}

/// Phased gesture progress. Streams began → changed* → ended/cancelled.
/// Transports without [Capability.phasedGesture] collapse this (HidTransport
/// fires the shortcut at ended && progress >= 0.5); the phased form must
/// survive end-to-end otherwise (Tier 3 invariant).
class GesturePhase extends InputEvent {
  const GesturePhase(this.kind, this.phase, this.progress);

  final GestureKind kind;
  final GesturePhaseKind phase;

  /// 0.0–1.0 completion toward the gesture trigger.
  final double progress;

  @override
  bool operator ==(Object other) =>
      other is GesturePhase &&
      other.kind == kind &&
      other.phase == phase &&
      other.progress == progress;

  @override
  int get hashCode => Object.hash(GesturePhase, kind, phase, progress);

  @override
  String toString() => 'GesturePhase($kind, $phase, $progress)';
}
