package dev.taira.helm

import android.view.KeyEvent
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class VolumeKeysTest {
    private val up = KeyEvent.KEYCODE_VOLUME_UP
    private val down = KeyEvent.KEYCODE_VOLUME_DOWN
    private val pressed = KeyEvent.ACTION_DOWN
    private val released = KeyEvent.ACTION_UP

    @Test
    fun capturedVolumePressEmitsItsDirection() {
        assertEquals("up", VolumeKeys.decide(true, up, pressed, 0).emit)
        assertEquals("down", VolumeKeys.decide(true, down, pressed, 0).emit)
    }

    @Test
    fun capturedVolumeKeysAreConsumedOnBothEdges() {
        // Letting the UP through would still pop the system volume slider.
        assertTrue(VolumeKeys.decide(true, up, pressed, 0).consume)
        assertTrue(VolumeKeys.decide(true, up, released, 0).consume)
    }

    @Test
    fun holdingAKeyDoesNotAdvanceRepeatedly() {
        val repeat = VolumeKeys.decide(true, down, pressed, 3)
        assertTrue(repeat.consume)
        assertNull(repeat.emit)
    }

    @Test
    fun releaseEdgeEmitsItsDirectionWithARelease() {
        // Media mode repeats a held key until it sees this.
        assertEquals("up:release", VolumeKeys.decide(true, up, released, 0).emit)
        assertEquals("down:release", VolumeKeys.decide(true, down, released, 0).emit)
    }

    @Test
    fun notCapturedPassesEverythingThrough() {
        val d = VolumeKeys.decide(false, up, pressed, 0)
        assertFalse(d.consume)
        assertNull(d.emit)
    }

    @Test
    fun otherKeysAreNeverTouched() {
        val d = VolumeKeys.decide(true, KeyEvent.KEYCODE_BACK, pressed, 0)
        assertFalse(d.consume)
        assertNull(d.emit)
    }
}
