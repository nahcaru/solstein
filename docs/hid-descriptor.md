# HID Report Descriptor Spec

One combo device, three report IDs. The keyboard report is what makes gestures possible without host software; the consumer report (v0.2) adds media keys.

## Registration (Kotlin)

```kotlin
val sdp = BluetoothHidDeviceAppSdpSettings(
    "Solstein", "Virtual trackpad & keyboard", "Solstein",
    BluetoothHidDevice.SUBCLASS1_COMBO,   // combo — not MOUSE/KEYBOARD alone
    SOLSTEIN_DESCRIPTOR
)
hidDevice.registerApp(sdp, null, null, executor, callback)
```

- API 28+; runtime permissions on 31+: `BLUETOOTH_CONNECT`, `BLUETOOTH_SCAN`, `BLUETOOTH_ADVERTISE`.
- Foreground service: `android:foregroundServiceType="connectedDevice"`.
- `sendReport(device, reportId, payload)` — payload **excludes** the report ID byte.

## Descriptor bytes

```kotlin
val SOLSTEIN_DESCRIPTOR = byteArrayOf(
    // ---------- Report ID 1: Mouse ----------
    0x05, 0x01,        // Usage Page (Generic Desktop)
    0x09, 0x02,        // Usage (Mouse)
    0xA1, 0x01,        // Collection (Application)
    0x85, 0x01,        //   Report ID (1)
    0x09, 0x01,        //   Usage (Pointer)
    0xA1, 0x00,        //   Collection (Physical)
    0x05, 0x09,        //     Usage Page (Button)
    0x19, 0x01, 0x29, 0x03,  // Buttons 1–3
    0x15, 0x00, 0x25, 0x01,
    0x95, 0x03, 0x75, 0x01,
    0x81, 0x02,        //     Input (Data,Var,Abs) — 3 button bits
    0x95, 0x01, 0x75, 0x05,
    0x81, 0x03,        //     Input (Const) — 5 pad bits
    0x05, 0x01,        //     Usage Page (Generic Desktop)
    0x09, 0x30, 0x09, 0x31, 0x09, 0x38,  // X, Y, Wheel
    0x15, 0x81, 0x25, 0x7F,              // −127…127
    0x75, 0x08, 0x95, 0x03,
    0x81, 0x06,        //     Input (Data,Var,Rel)
    0x05, 0x0C,        //     Usage Page (Consumer)
    0x0A, 0x38, 0x02,  //     Usage (AC Pan) — horizontal scroll
    0x95, 0x01,
    0x81, 0x06,        //     Input (Data,Var,Rel)
    0xC0, 0xC0,

    // ---------- Report ID 2: Keyboard ----------
    0x05, 0x01,        // Usage Page (Generic Desktop)
    0x09, 0x06,        // Usage (Keyboard)
    0xA1, 0x01,        // Collection (Application)
    0x85, 0x02,        //   Report ID (2)
    0x05, 0x07,        //   Usage Page (Keyboard/Keypad)
    0x19, 0xE0, 0x29, 0xE7,  // LCtrl…RGUI
    0x15, 0x00, 0x25, 0x01,
    0x75, 0x01, 0x95, 0x08,
    0x81, 0x02,        //   Input — modifier bits
    0x95, 0x01, 0x75, 0x08,
    0x81, 0x03,        //   Input (Const) — reserved byte
    0x95, 0x06, 0x75, 0x08,
    0x15, 0x00, 0x25, 0x65,
    0x05, 0x07,
    0x19, 0x00, 0x29, 0x65,
    0x81, 0x00,        //   Input (Data,Array) — 6-key rollover
    0xC0,

    // ---------- Report ID 3: Consumer Control (media keys, v0.2) ----------
    0x05, 0x0C,        // Usage Page (Consumer)
    0x09, 0x01,        // Usage (Consumer Control)
    0xA1, 0x01,        // Collection (Application)
    0x85, 0x03,        //   Report ID (3)
    0x15, 0x00, 0x25, 0x01,
    0x75, 0x01, 0x95, 0x08,
    0x0A, 0xCD, 0x00,  //   Play/Pause          (bit 0)
    0x0A, 0xB5, 0x00,  //   Scan Next Track     (bit 1)
    0x0A, 0xB6, 0x00,  //   Scan Previous Track (bit 2)
    0x0A, 0xE9, 0x00,  //   Volume Up           (bit 3)
    0x0A, 0xEA, 0x00,  //   Volume Down         (bit 4)
    0x0A, 0xE2, 0x00,  //   Mute                (bit 5)
    0x0A, 0x6F, 0x00,  //   Brightness Up       (bit 6)
    0x0A, 0x70, 0x00,  //   Brightness Down     (bit 7)
    0x81, 0x02,        //   Input (Data,Var,Abs)
    0xC0,
).map { it.toByte() }.toByteArray()
```

## Report layouts

### Mouse (ID 1) — 5 bytes

| Byte | Field | Range |
|---|---|---|
| 0 | Buttons (bit0=L, bit1=R, bit2=M) | 0–7 |
| 1 | ΔX | −127…127 |
| 2 | ΔY | −127…127 |
| 3 | Wheel (vertical) | −127…127 |
| 4 | AC Pan (horizontal) | −127…127 |

Deltas > ±127 per frame are split across consecutive reports.

### Keyboard (ID 2) — 8 bytes

| Byte | Field |
|---|---|
| 0 | Modifiers: bit0 LCtrl, bit1 LShift, bit2 LAlt, bit3 LGUI/⌘, bits4–7 right-side |
| 1 | Reserved 0x00 |
| 2–7 | Up to 6 concurrent usage codes |

### Consumer (ID 3) — 1 byte

One bit per media function, in the order listed in the descriptor (bit 0 = Play/Pause … bit 7 = Brightness Down). Press = bit set, release = `0x00`; bit order mirrors the Dart `MediaKey` enum.

**Every key sequence ends with an all-zero report.** Example — Mission Control:

```
[0x01, 0x00, 0x52, 0,0,0,0,0]   // LCtrl + UpArrow(0x52)
[0x00, 0x00, 0x00, 0,0,0,0,0]   // release all
```

## Keyboard layout

HID transmits key *positions*, not characters: the same usage means different
characters under different host layouts. `app/lib/hid/layouts.dart` holds one
table per host layout (US, JIS), selected in Settings independently of target OS.

**CJK works without any of this.** The host's own IME converts romaji sent as
ordinary usage codes — verified 2026-07-16, Pixel 7a → macOS. The phone's IME is
deliberately suppressed (`TextInputType.visiblePassword`) so romaji arrives
unmangled. The かな/英数 keys (LANG1/LANG2 on macOS) toggle the host IME so the
user need not touch the host.

Characters no host layout can produce (é, €) wait for the v2 helper's `Text`
packet; see ADR-006. Clipboard-paste was never possible here — nothing in HID
lets a peripheral write the host's clipboard.

## Gotchas

- Descriptor bugs are silent: device pairs fine, inputs just don't arrive. Unit-test exact bytes; verify on macOS **and** Windows early.
- After changing the descriptor, macOS may cache the old bond → remove the device in Bluetooth settings and re-pair.
- OEM builds may disable the HID Device profile → handle `getProfileProxy` failure with a diagnostics screen.
