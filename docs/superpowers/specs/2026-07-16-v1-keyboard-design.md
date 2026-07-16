# v1 Keyboard: non-US layouts and CJK

**Date**: 2026-07-16
**Status**: Approved, pending implementation plan
**Scope**: the v1 roadmap bullet "Non-US keyboards / CJK". Onboarding, haptics, theming, and the
Play Store release are a separate spec.

## Summary

CJK input over Tier-1 HID already works and shipped in v0.1 undetected: the host's own IME converts
romaji sent as ordinary US usage codes. Verified 2026-07-16 on a Pixel 7a — pressing かな on the
MacBook and typing `nihongo` through Helm produces 日本語, and Korean and Pinyin behave identically.

This spec therefore does **not** build CJK input. It builds the four things that are actually
missing: per-host-layout tables, かな/英数 keys so the phone can toggle the host IME itself, a fix
for characters that currently vanish, and a protocol seam so v2 can do this properly.

## Background: why HID cannot send 日

HID transmits *key positions* (usage codes), not characters. There is no usage for 日, the way
`0x04` is the A key. Three consequences drove the design:

1. **The clipboard-paste route in the old roadmap cannot work.** Nothing in HID lets a peripheral
   write the host's clipboard, and no host software is listening. `Cmd+V` would paste whatever the
   host already had. The idea needs the thing v1 is defined as lacking.
2. **The phone's IME cannot help.** `keyboard_screen.dart:117` sets
   `keyboardType: TextInputType.visiblePassword` with autocorrect and suggestions off. Confirmed on
   device: Gboard permits the language switch but withholds hiragana flick; Shimeji renders its flick
   UI and its output never lands. Composed characters do not reach the field at all. This is
   desirable — it is what keeps romaji unmangled for the host IME — but it was never documented.
3. **Uncomposed non-ASCII does reach us.** Confirmed on device: Spanish `ñ` (a direct key, no
   composition) appears in Helm's field, and is then dropped by `keyboard_screen.dart:87`. This is
   why no compose-and-send mode is needed: every character we cannot send is already in our hands.

### Prior art: Chrome Remote Desktop

Chromium's remoting protocol (`remoting/proto/event.proto`) defines two input paths: `KeyEvent`
with a `usb_keycode` field — the same HID usages Helm sends — and:

```proto
// Text input event for input method different from physical keyboards,
// including software keyboard, gesture typing, voice input, etc.
message TextEvent {
  // Unicode sequence for the event in UTF-8.
  optional string text = 1;
}
```

CRD hit this exact wall and solved it by sending the *string* when the keycode path cannot express
the input — possible only because CRD installs host software, which injects via
`CGEventKeyboardSetUnicodeString` (macOS, bypasses the keyboard layout entirely) or
`KEYEVENTF_UNICODE` (Windows). Helm reaches the same place in v2. See ADR-006.

**Unicode Hex Input was considered and rejected** (Option+hex on macOS, `Ctrl+Shift+U` on Linux,
registry-hacked Alt+numpad on Windows). It is the only Tier-1 route to arbitrary Unicode, but it
requires the user to reconfigure their host — eroding the zero-install premise — is three fragile
per-OS implementations, and on macOS is an input source *mutually exclusive with the Japanese IME*
that makes CJK work. It would buy ñ-on-a-US-host, which a Spanish layout table sends natively as
usage 0x33, and which v2 solves cleanly for every character at once.

## Design

### 1. Layout registry

`keyStrokeForChar(String char)` in `app/lib/hid/keymap_us.dart:82` hardcodes US. It becomes
layout-aware: `keyStrokeForChar(String char, HostLayout layout)`.

A layout is a base char→`KeyStroke` map plus an overrides map, merged:

```dart
HostLayout(base: qwertyAlnum, overrides: { '@': KeyStroke(Mod.none, 0x2F), /* … */ })
```

v1 ships **US** and **JIS**. They share the alphanumeric block and differ in symbol positions (JIS
puts `@` at the `[` position, `:` at `'`, `^` at `=`, and adds ¥ and ろ via International3 `0x89`
and International1 `0x87`).

The base+overrides shape — rather than a shared alphanumeric core with a symbol table — exists
because European layouts override *letters*: QWERTZ swaps y/z, AZERTY swaps a/q and z/w. A new
layout must be a data-only addition (one const map, no code). Additional layouts ship by request,
not speculatively; each needs a real host to verify.

Settings gains a **host keyboard layout** picker. It is independent of target OS: a Mac can be JIS,
a Linux box AZERTY. Persisted per device alongside the existing target-OS guess.

### 2. IME keys

Two keys, かな and 英数, so the user need not reach for the host to toggle its IME.

The usages are **per target OS**, following the existing `shortcut_tables.dart` pattern:

| Target OS | かな | 英数 | Status |
|---|---|---|---|
| macOS | LANG1 `0x90` | LANG2 `0x91` | High confidence; Apple JIS keyboards send these. Verify. |
| Windows | International2 `0x88`? | ? | **Unverified.** Windows IMEs use the International codes, and the 半角/全角 toggle may be the real target. Determine on hardware. |
| Linux | ? | ? | **Unverified.** IBus-configuration dependent; may have no fixed usage. |

LANG1/LANG2 are also Hangul/Hanja, which is why the device test found Korean behaving identically —
one pair of usages covers CJK on macOS.

Do not guess the Windows and Linux codes. Verify each against a real host before shipping; v0.2
established that passing unit tests are not evidence of working HID. If an OS turns out to have no
usable fixed usage — plausible on Linux, where the IME toggle is an IBus-configured shortcut rather
than a key — then the IME keys are hidden for that target OS and the spec's claim narrows to the
OSes where they demonstrably work. That is an acceptable outcome, not a blocker.

Visibility: a Settings toggle, **default off**. Not tied to the host-layout picker — running the
Japanese IME on a US-layout Mac is common, so layout is the wrong signal.

### 3. Field invariant: only what the host received

`keyboard_screen.dart:75` diffs the field against `_lastText` and turns additions into keystrokes.
Line 87 drops unsendable characters, but line 89 records them into `_lastText` regardless.

This is a live bug, not just a missing feature. The phone's field and the host's text **diverge**,
and the next backspace is computed against a buffer the host never agreed to, so it deletes the
wrong character on the host.

One invariant fixes both: **the field only ever contains what the host actually received.** A
character with no stroke in the active layout is rejected from the field rather than merely
undelivered, and a SnackBar names the reason ("ñ isn't on the US host layout"). The diff math stays
true because the buffer it reads is, by construction, what the host has.

Concretely: added characters are processed in order; each sendable one is sent and retained, each
unsendable one is skipped. Afterwards the controller's text is rewritten to the retained characters
only and `_lastText` set to match, so pasting `café` sends `c a f`, leaves `caf` in the field, and
reports é. The rewrite must not fire a recursive `onChanged`.

### 4. Protocol and documentation

`docs/protocol.md` stops at packet type `5=GesturePhase`. Two additions:

- **`6=MediaTap`** — an existing v0.2 gap. `MediaTap` is in the `InputEvent` vocabulary and the
  consumer report ships, but the protocol never gained it.
- **`7=Text`** — `u8 flags` (bit 0 = more fragments) followed by UTF-8 bytes. Reassembled by the
  helper; fragments may split mid-codepoint since the helper concatenates before decoding.
  Classed with Button/Key as **never dropped, never coalesced** — text loss corrupts rather than
  degrades.

`Text` is defined now and consumed by no one until v2, following ADR-004's precedent: `GesturePhase`
was put in the protocol early so Tier 3 would be a pure helper-side upgrade. Same reasoning.

Documentation to correct — both currently tell the clipboard story:

- `docs/hid-descriptor.md:123` — "CJK/IME is a v1 problem (candidate: clipboard-paste via `Cmd+V`)"
- `app/lib/hid/keymap_us.dart:1` — same claim in the library doc comment
- `docs/roadmap.md` — the v1 bullet, and the v2 clipboard-paste route → `TextEvent`
- `docs/architecture.md` — manual checklist gains an IME/layout section

### ADR-006 (new)

Record the decision: **CJK rides the host's IME; arbitrary text injection waits for the helper.**
Context — HID sends key positions, not characters. Alternatives — clipboard-paste (impossible
without host software), Unicode hex (host reconfiguration, per-OS fragility, macOS input-source
conflict with the IME). Consequence — CJK works at Tier 1 with zero host software, at the cost of
requiring the user's host to have its own IME configured; anything the host layout cannot express
waits for v2's `TextEvent`.

## Testing

**Unit** (no hardware):

- US and JIS tables: representative char → expected `KeyStroke`, including JIS `@ : ^ ¥ ろ`.
- Unsendable characters return null for each layout (ñ, é, €, 日).
- The diff loop under rejection: typing `ñ` leaves field and `_lastText` unchanged and emits no
  report; a subsequent backspace deletes the correct character.
- Per-OS IME key table resolves to the expected usages.

**Manual** (extends the v0.2 checklist in `docs/architecture.md`):

- かな/英数 keys toggle the host IME without touching the host.
- Romaji → 日本語 end to end via the phone alone; spot-check Korean and Pinyin.
- JIS host layout: `@ : ^ ¥ ろ` land correctly; US host layout unaffected.
- ñ on a US host is refused visibly, and the following backspace deletes the right character.
- Windows and Linux: confirm the IME usages, or record that none exist.

## Out of scope

Phone-side IME composition; Unicode hex; ñ-on-a-US-host (Spanish layout table, by request, or v2);
European layout tables (by request); onboarding, haptics, theming, Play Store release.
