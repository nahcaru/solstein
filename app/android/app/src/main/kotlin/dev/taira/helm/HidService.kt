package dev.taira.helm

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * Foreground service (connectedDevice type) that keeps the process alive
 * while a HID session is active. The actual Bluetooth work lives in
 * [HidManager]; this class only manages lifecycle and the notification.
 */
class HidService : Service() {

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        HidManager.start(this)
        return START_STICKY
    }

    override fun onDestroy() {
        // Neutralize the host before the process can die (stuck-key rule),
        // but keep the HID app registered — the service stops on every
        // disconnect, and unregistering here would break reconnects.
        // Full teardown belongs to MainActivity.onDestroy.
        HidManager.releaseAll()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun buildNotification(): Notification {
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                "HID session",
                NotificationManager.IMPORTANCE_LOW,
            ).apply { description = "Shown while Helm is acting as a trackpad/keyboard" }
        )
        val contentIntent = PendingIntent.getActivity(
            this,
            0,
            packageManager.getLaunchIntentForPackage(packageName),
            PendingIntent.FLAG_IMMUTABLE,
        )
        return Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("Helm is active")
            .setContentText("Serving as Bluetooth trackpad & keyboard")
            .setSmallIcon(android.R.drawable.stat_sys_data_bluetooth)
            .setContentIntent(contentIntent)
            .setOngoing(true)
            .build()
    }

    companion object {
        private const val CHANNEL_ID = "helm_hid"
        private const val NOTIFICATION_ID = 1

        fun start(context: Context) {
            try {
                context.startForegroundService(Intent(context, HidService::class.java))
            } catch (_: Exception) {
                // API 31+ forbids foreground-service starts from the
                // background (e.g. a host auto-reconnecting while Helm is
                // not on screen). MainActivity.onResume retries.
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, HidService::class.java))
        }
    }
}
