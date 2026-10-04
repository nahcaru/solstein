package dev.taira.solstein

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Pins SOLSTEIN_DESCRIPTOR byte-for-byte against docs/hid-descriptor.md.
 * Descriptor bugs are silent (pairing succeeds, input never arrives), and
 * macOS caches the descriptor per bond — so drift must fail loudly here.
 */
class SolsteinHidDescriptorTest {

    private val golden = (
        // Report ID 1: Mouse
        "05 01 09 02 A1 01 85 01 09 01 A1 00 " +
        "05 09 19 01 29 03 15 00 25 01 95 03 75 01 81 02 " +
        "95 01 75 05 81 03 " +
        "05 01 09 30 09 31 09 38 15 81 25 7F 75 08 95 03 81 06 " +
        "05 0C 0A 38 02 95 01 81 06 C0 C0 " +
        // Report ID 2: Keyboard
        "05 01 09 06 A1 01 85 02 05 07 19 E0 29 E7 15 00 25 01 " +
        "75 01 95 08 81 02 95 01 75 08 81 03 " +
        "95 06 75 08 15 00 25 65 05 07 19 00 29 65 81 00 C0 " +
        // Report ID 3: Consumer Control (media keys)
        "05 0C 09 01 A1 01 85 03 15 00 25 01 75 01 95 08 " +
        "0A CD 00 0A B5 00 0A B6 00 0A E9 00 0A EA 00 0A E2 00 " +
        "0A 6F 00 0A 70 00 81 02 C0"
    ).split(" ").map { it.toInt(16).toByte() }.toByteArray()

    @Test
    fun descriptorMatchesGoldenBytes() {
        assertEquals(golden.toHex(), SolsteinHidDescriptor.BYTES.toHex())
    }

    @Test
    fun releasePayloadsMatchReportSizes() {
        assertEquals(5, SolsteinHidDescriptor.MOUSE_RELEASE_ALL.size)   // buttons + X/Y/wheel/pan
        assertEquals(8, SolsteinHidDescriptor.KEYBOARD_RELEASE_ALL.size) // mods + reserved + 6 keys
        assertEquals(1, SolsteinHidDescriptor.CONSUMER_RELEASE_ALL.size) // 8 media bits
        assertEquals(0, SolsteinHidDescriptor.MOUSE_RELEASE_ALL.sumOf { it.toInt() })
        assertEquals(0, SolsteinHidDescriptor.KEYBOARD_RELEASE_ALL.sumOf { it.toInt() })
        assertEquals(0, SolsteinHidDescriptor.CONSUMER_RELEASE_ALL.sumOf { it.toInt() })
    }

    private fun ByteArray.toHex() = joinToString(" ") { "%02X".format(it) }
}
