package dev.taira.helm

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothHidDevice
import android.bluetooth.BluetoothHidDeviceAppSdpSettings
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.content.Context
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import java.util.concurrent.Executors

/**
 * Owns the BluetoothHidDevice session: profile proxy → registerApp →
 * connect → sendReport. Runs for as long as HidService keeps the process
 * foregrounded. Profile callbacks arrive on the main thread, HID app
 * callbacks on [executor], and reports go out on a dedicated send thread.
 *
 * Bluetooth permissions are requested by MainActivity before any of this
 * is invoked, hence the SuppressLint.
 */
@SuppressLint("MissingPermission")
object HidManager {
    enum class State { DISCONNECTED, CONNECTING, CONNECTED, ERROR }

    interface Listener {
        fun onStateChanged(state: State)
    }

    var listener: Listener? = null
    var lastError: String? = null
        private set

    private var adapter: BluetoothAdapter? = null
    @Volatile private var hidDevice: BluetoothHidDevice? = null
    private var starting = false
    private var registered = false
    @Volatile private var connectedDevice: BluetoothDevice? = null
    private var pendingConnectAddress: String? = null

    private val mainHandler = Handler(Looper.getMainLooper())
    private val executor = Executors.newSingleThreadExecutor()

    // sendReport is a blocking binder call; on the main thread it stalled
    // touch dispatch. One serial queue keeps mouse/keyboard/consumer order.
    private val sendHandler: Handler by lazy {
        Handler(HandlerThread("helm-hid-send").apply { start() }.looper)
    }

    val isConnected: Boolean get() = connectedDevice != null
    val connectedAddress: String? get() = connectedDevice?.address

    private fun post(state: State) {
        mainHandler.post { listener?.onStateChanged(state) }
    }

    private fun fail(message: String) {
        lastError = message
        post(State.ERROR)
    }

    /** Opens the HID profile proxy and registers the Helm SDP record. */
    fun start(context: Context) {
        if (registered || starting) return
        starting = true
        val manager = context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        val a = manager.adapter ?: run {
            starting = false
            return fail("Bluetooth is not available on this device")
        }
        adapter = a
        val ok = a.getProfileProxy(context.applicationContext, object : BluetoothProfile.ServiceListener {
            override fun onServiceConnected(profile: Int, proxy: BluetoothProfile) {
                if (profile != BluetoothProfile.HID_DEVICE) return
                hidDevice = proxy as BluetoothHidDevice
                registerApp()
            }

            override fun onServiceDisconnected(profile: Int) {
                if (profile != BluetoothProfile.HID_DEVICE) return
                registered = false
                hidDevice = null
                connectedDevice = null
                post(State.DISCONNECTED)
            }
        }, BluetoothProfile.HID_DEVICE)
        if (!ok) {
            starting = false
            // OEM builds may disable the HID Device profile entirely.
            fail("This device's Bluetooth stack does not expose the HID Device profile")
        }
    }

    private fun registerApp() {
        val hid = hidDevice ?: return
        val sdp = BluetoothHidDeviceAppSdpSettings(
            "Helm",
            "Virtual trackpad & keyboard",
            "Helm",
            BluetoothHidDevice.SUBCLASS1_COMBO,
            HelmHidDescriptor.BYTES,
        )
        val ok = hid.registerApp(sdp, null, null, executor, callback)
        if (!ok) fail("Failed to register the HID app with the Bluetooth stack")
    }

    private val callback = object : BluetoothHidDevice.Callback() {
        override fun onAppStatusChanged(pluggedDevice: BluetoothDevice?, isRegistered: Boolean) {
            registered = isRegistered
            starting = false
            if (!isRegistered) {
                connectedDevice = null
                post(State.DISCONNECTED)
                return
            }
            // Registration completed while a connect was queued.
            pendingConnectAddress?.let { address ->
                pendingConnectAddress = null
                connect(address)
            }
        }

        override fun onConnectionStateChanged(device: BluetoothDevice, state: Int) {
            when (state) {
                BluetoothProfile.STATE_CONNECTED -> {
                    connectedDevice = device
                    post(State.CONNECTED)
                }
                BluetoothProfile.STATE_CONNECTING -> post(State.CONNECTING)
                BluetoothProfile.STATE_DISCONNECTED, BluetoothProfile.STATE_DISCONNECTING -> {
                    if (connectedDevice?.address == device.address) connectedDevice = null
                    if (state == BluetoothProfile.STATE_DISCONNECTED) {
                        // A queued host switch continues once the old link is gone.
                        val pending = pendingConnectAddress
                        if (pending != null) {
                            pendingConnectAddress = null
                            connect(pending)
                        } else {
                            post(State.DISCONNECTED)
                        }
                    }
                }
            }
        }
    }

    fun bondedDevices(context: Context): List<Map<String, Any>> {
        val a = adapter
            ?: (context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager)
                .adapter?.also { adapter = it }
        return a?.bondedDevices.orEmpty().map {
            mapOf(
                "address" to it.address,
                "name" to (it.name ?: it.address),
                "connected" to isAclConnected(it),
            )
        }
    }

    /**
     * Whether the phone currently holds an ACL link to [device].
     * BluetoothDevice.isConnected() is hidden but greylisted; if reflection
     * ever breaks, err on the side of showing the device.
     */
    private fun isAclConnected(device: BluetoothDevice): Boolean =
        try {
            device.javaClass.getMethod("isConnected").invoke(device) as Boolean
        } catch (_: Exception) {
            true
        }

    fun connect(address: String) {
        val hid = hidDevice
        if (hid == null || !registered) {
            pendingConnectAddress = address
            return
        }
        val current = connectedDevice
        if (current != null) {
            if (current.address == address) return
            // Host switch: neutralize and drop the old link first; the new
            // connect fires from onConnectionStateChanged(DISCONNECTED).
            pendingConnectAddress = address
            post(State.CONNECTING)
            releaseAll()
            sendHandler.post { hid.disconnect(current) }
            return
        }
        val device = adapter?.getRemoteDevice(address)
            ?: return fail("Unknown Bluetooth device: $address")
        post(State.CONNECTING)
        if (!hid.connect(device)) fail("Bluetooth stack rejected the connection request")
    }

    /**
     * Sends release-all reports first so the host never sees stuck input.
     * The disconnect rides the same send queue so it cannot overtake them.
     */
    fun disconnect() {
        releaseAll()
        val hid = hidDevice ?: return
        val device = connectedDevice ?: return
        sendHandler.post { hid.disconnect(device) }
    }

    fun releaseAll() {
        sendMouseReport(HelmHidDescriptor.MOUSE_RELEASE_ALL)
        sendKeyboardReport(HelmHidDescriptor.KEYBOARD_RELEASE_ALL)
        sendConsumerReport(HelmHidDescriptor.CONSUMER_RELEASE_ALL)
    }

    fun sendMouseReport(payload: ByteArray) =
        sendReport(HelmHidDescriptor.REPORT_ID_MOUSE, payload)

    fun sendKeyboardReport(payload: ByteArray) =
        sendReport(HelmHidDescriptor.REPORT_ID_KEYBOARD, payload)

    fun sendConsumerReport(payload: ByteArray) =
        sendReport(HelmHidDescriptor.REPORT_ID_CONSUMER, payload)

    /**
     * Fire-and-forget. The proxy and host are captured at post time so a
     * report queued before stop() still reaches the host that was current
     * when it was sent, even though stop() clears the fields right away.
     */
    private fun sendReport(reportId: Int, payload: ByteArray) {
        val hid = hidDevice ?: return
        val device = connectedDevice ?: return
        sendHandler.post { hid.sendReport(device, reportId, payload) }
    }

    /**
     * Full teardown: neutralize the host, unregister, close the proxy.
     * The Bluetooth calls are posted behind the release-all reports on the
     * send queue, so the releases are transmitted before the link drops.
     * Local state is cleared immediately so nothing new gets queued.
     */
    fun stop() {
        releaseAll()
        val hid = hidDevice
        val device = connectedDevice
        val a = adapter
        starting = false
        pendingConnectAddress = null
        registered = false
        connectedDevice = null
        hidDevice = null
        if (hid != null) {
            sendHandler.post {
                device?.let { hid.disconnect(it) }
                hid.unregisterApp()
                a?.closeProfileProxy(BluetoothProfile.HID_DEVICE, hid)
            }
        }
        post(State.DISCONNECTED)
    }
}
