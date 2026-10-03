package dev.taira.helm

import android.app.Activity
import android.view.KeyEvent
import android.view.WindowManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * What a key event means while volume keys are captured for presenting.
 * Kept free of Android objects so it can be unit-tested on the plain JVM.
 */
object VolumeKeys {
    /** [consume]: swallow the event (no system volume UI). [emit]: "up"/"down" for Dart, or null. */
    data class Decision(val consume: Boolean, val emit: String?)

    private val PASS = Decision(consume = false, emit = null)

    /**
     * Both the DOWN and the UP of a volume key are consumed while captured —
     * letting either through would still show the system volume slider. Only
     * the first DOWN of a press emits ("up"/"down"): holding the key
     * auto-repeats, and a slide should advance once per press. The UP emits
     * "up:release"/"down:release" so a consumer that repeats while held knows
     * when to stop.
     */
    fun decide(captured: Boolean, keyCode: Int, action: Int, repeatCount: Int): Decision {
        if (!captured) return PASS
        val name = when (keyCode) {
            KeyEvent.KEYCODE_VOLUME_UP -> "up"
            KeyEvent.KEYCODE_VOLUME_DOWN -> "down"
            else -> return PASS
        }
        val emit = when {
            action == KeyEvent.ACTION_DOWN && repeatCount == 0 -> name
            action == KeyEvent.ACTION_UP -> "$name:release"
            else -> null
        }
        return Decision(consume = true, emit = emit)
    }
}

/**
 * Hands presenter mode two things only Android can do: keep the screen on
 * (a dimmed-out phone pauses the app and stops the sensors) and use the
 * volume keys as Prev/Next, which can be pressed without looking.
 *
 * Nothing here touches the HID descriptor or reports.
 */
class PresenterBridge(private val activity: Activity) : EventChannel.StreamHandler {
    private var events: EventChannel.EventSink? = null

    var volumeKeysCaptured = false
        private set

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "setKeepScreenOn" -> {
                    setKeepScreenOn(call.arguments as? Boolean ?: false)
                    result.success(null)
                }
                "setVolumeKeysCaptured" -> {
                    volumeKeysCaptured = call.arguments as? Boolean ?: false
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        EventChannel(messenger, KEYS_CHANNEL).setStreamHandler(this)
    }

    /** Returns true if the event was consumed. */
    fun handleKeyEvent(event: KeyEvent): Boolean {
        val decision = VolumeKeys.decide(
            volumeKeysCaptured, event.keyCode, event.action, event.repeatCount,
        )
        decision.emit?.let { events?.success(it) }
        return decision.consume
    }

    /** Gives the phone back to the system (called when the app pauses). */
    fun release() {
        volumeKeysCaptured = false
        setKeepScreenOn(false)
    }

    private fun setKeepScreenOn(on: Boolean) {
        val flag = WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
        if (on) activity.window.addFlags(flag) else activity.window.clearFlags(flag)
    }

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
        events = sink
    }

    override fun onCancel(arguments: Any?) {
        events = null
    }

    companion object {
        private const val METHOD_CHANNEL = "dev.taira.helm/presenter"
        private const val KEYS_CHANNEL = "dev.taira.helm/presenter_keys"
    }
}
