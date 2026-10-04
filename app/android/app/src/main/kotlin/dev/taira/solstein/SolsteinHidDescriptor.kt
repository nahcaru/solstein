package dev.taira.solstein

/**
 * Combo HID report descriptor: mouse (report ID 1) + keyboard (report ID 2).
 * Byte-for-byte from docs/hid-descriptor.md — validated with the
 * Eleccelerator parser. Descriptor bugs are silent (device pairs, inputs
 * never arrive), so SolsteinHidDescriptorTest pins these bytes.
 *
 * No Android imports here: this must stay testable on the plain JVM.
 */
object SolsteinHidDescriptor {
    const val REPORT_ID_MOUSE = 1
    const val REPORT_ID_KEYBOARD = 2
    const val REPORT_ID_CONSUMER = 3

    val BYTES: ByteArray = intArrayOf(
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

        // ---------- Report ID 3: Consumer Control (media keys) ----------
        // Bit order matches Dart's MediaKey enum: playPause, next, prev,
        // volUp, volDown, mute, brightnessUp, brightnessDown.
        0x05, 0x0C,        // Usage Page (Consumer)
        0x09, 0x01,        // Usage (Consumer Control)
        0xA1, 0x01,        // Collection (Application)
        0x85, 0x03,        //   Report ID (3)
        0x15, 0x00, 0x25, 0x01,
        0x75, 0x01, 0x95, 0x08,
        0x0A, 0xCD, 0x00,  //   Play/Pause
        0x0A, 0xB5, 0x00,  //   Scan Next Track
        0x0A, 0xB6, 0x00,  //   Scan Previous Track
        0x0A, 0xE9, 0x00,  //   Volume Up
        0x0A, 0xEA, 0x00,  //   Volume Down
        0x0A, 0xE2, 0x00,  //   Mute
        0x0A, 0x6F, 0x00,  //   Display Brightness Increment
        0x0A, 0x70, 0x00,  //   Display Brightness Decrement
        0x81, 0x02,        //   Input (Data,Var,Abs) — 8 media bits
        0xC0,
    ).map { it.toByte() }.toByteArray()

    /** All-zero payloads for stuck-input prevention (exclude report ID). */
    val MOUSE_RELEASE_ALL = ByteArray(5)
    val KEYBOARD_RELEASE_ALL = ByteArray(8)
    val CONSUMER_RELEASE_ALL = ByteArray(1)
}
