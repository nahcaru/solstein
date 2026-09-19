package dev.taira.helm

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.view.KeyEvent
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity(), HidManager.Listener {

    private var stateSink: EventChannel.EventSink? = null
    private var permissionResult: MethodChannel.Result? = null
    private lateinit var presenterBridge: PresenterBridge

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        HidManager.listener = this
        presenterBridge = PresenterBridge(this).also {
            it.register(flutterEngine.dartExecutor.binaryMessenger)
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "ensurePermissions" -> ensurePermissions(result)
                    "getBondedDevices" -> result.success(HidManager.bondedDevices(this))
                    "connect" -> {
                        val address = call.argument<String>("address")
                        if (address == null) {
                            result.error("bad_args", "connect requires an address", null)
                        } else {
                            HidService.start(this)
                            HidManager.connect(address)
                            result.success(null)
                        }
                    }
                    "disconnect" -> {
                        HidManager.disconnect()
                        HidService.stop(this)
                        result.success(null)
                    }
                    "sendMouseReport" -> {
                        HidManager.sendMouseReport(call.arguments as ByteArray)
                        result.success(null)
                    }
                    "sendKeyboardReport" -> {
                        HidManager.sendKeyboardReport(call.arguments as ByteArray)
                        result.success(null)
                    }
                    "sendConsumerReport" -> {
                        HidManager.sendConsumerReport(call.arguments as ByteArray)
                        result.success(null)
                    }
                    "getConnectedDevice" -> result.success(HidManager.connectedAddress)
                    "getLastError" -> result.success(HidManager.lastError)
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, STATE_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    stateSink = events
                }

                override fun onCancel(arguments: Any?) {
                    stateSink = null
                }
            })
    }

    override fun onStateChanged(state: HidManager.State) {
        // Scope the foreground service (and its mandatory notification) to
        // the time we're actually serving as an input device.
        when (state) {
            HidManager.State.CONNECTED -> HidService.start(this)
            HidManager.State.DISCONNECTED, HidManager.State.ERROR ->
                HidService.stop(this)
            else -> {}
        }
        stateSink?.success(
            when (state) {
                HidManager.State.DISCONNECTED -> "disconnected"
                HidManager.State.CONNECTING -> "connecting"
                HidManager.State.CONNECTED -> "connected"
                HidManager.State.ERROR -> "error"
            }
        )
    }

    private fun requiredPermissions(): Array<String> {
        val permissions = mutableListOf<String>()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            permissions += Manifest.permission.BLUETOOTH_CONNECT
            permissions += Manifest.permission.BLUETOOTH_SCAN
            permissions += Manifest.permission.BLUETOOTH_ADVERTISE
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            permissions += Manifest.permission.POST_NOTIFICATIONS
        }
        return permissions.toTypedArray()
    }

    private fun ensurePermissions(result: MethodChannel.Result) {
        val missing = requiredPermissions().filter {
            ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
        }
        if (missing.isEmpty()) {
            // Register the HID app immediately: the host must see the HID
            // service during (re-)pairing, long before any connect call.
            HidManager.start(applicationContext)
            result.success(true)
            return
        }
        permissionResult = result
        ActivityCompat.requestPermissions(this, missing.toTypedArray(), PERMISSION_REQUEST)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != PERMISSION_REQUEST) return
        val granted = grantResults.isNotEmpty() &&
            grantResults.all { it == PackageManager.PERMISSION_GRANTED }
        if (granted) HidManager.start(applicationContext)
        permissionResult?.success(granted)
        permissionResult = null
    }

    override fun onResume() {
        super.onResume()
        // A host may have auto-reconnected while we were backgrounded, where
        // Android forbids starting a foreground service. Catch up now.
        if (HidManager.isConnected) HidService.start(this)
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (::presenterBridge.isInitialized && presenterBridge.handleKeyEvent(event)) {
            return true
        }
        return super.dispatchKeyEvent(event)
    }

    override fun onPause() {
        // Stuck-key prevention: neutralize the host whenever the UI pauses.
        HidManager.releaseAll()
        if (::presenterBridge.isInitialized) presenterBridge.release()
        super.onPause()
    }

    override fun onDestroy() {
        if (HidManager.listener === this) HidManager.listener = null
        // Only unregister the HID app when the app is really going away —
        // not on configuration changes.
        if (isFinishing) HidManager.stop()
        super.onDestroy()
    }

    companion object {
        private const val METHOD_CHANNEL = "dev.taira.helm/hid"
        private const val STATE_CHANNEL = "dev.taira.helm/hid_state"
        private const val PERMISSION_REQUEST = 7001
    }
}
