# HID Report Descriptor Spec

One combo device, two report IDs. The keyboard report is what makes gestures possible without host software.

## Registration (Kotlin)

```kotlin
val sdp = BluetoothHidDeviceAppSdpSettings(
    "Helm", "Virtual trackpad & keyboard", "Helm",
    BluetoothHidDevice.SUBCLASS1_COMBO,   // combo — not MOUSE/KEYBOARD alone
    HELM_DESCRIPTOR
)
hidDevice.registerApp(sdp, null, null, executor, callback)
```

- API 28+; runtime permissions on 31+: `BLUETOOTH_CONNECT`, `BLUETOOTH_SCAN`, `BLUETOOTH_ADVERTISE`.
- Foreground service: `android:foregroundServiceType="connectedDevice"`.
- `sendReport(device, reportId, payload)` — payload **excludes** the report ID byte.

## Descriptor bytes

```kotlin
val HELM_DESCRIPTOR = byteArrayOf(
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

**Every key sequence ends with an all-zero report.** Example — Mission Control:

```
[0x01, 0x00, 0x52, 0,0,0,0,0]   // LCtrl + UpArrow(0x52)
[0x00, 0x00, 0x00, 0,0,0,0,0]   // release all
```

## Keyboard layout

v0.1: US layout only, per-character char → (modifier, usage) table. CJK/IME is a v1 problem (candidate: clipboard-paste via `Cmd+V`).

## Gotchas

- Descriptor bugs are silent: device pairs fine, inputs just don't arrive. Unit-test exact bytes; verify on macOS **and** Windows early.
- After changing the descriptor, macOS may cache the old bond → remove the device in Bluetooth settings and re-pair.
- OEM builds may disable the HID Device profile → handle `getProfileProxy` failure with a diagnostics screen.
