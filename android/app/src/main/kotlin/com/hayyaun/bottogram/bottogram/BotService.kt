package com.hayyaun.bottogram.bottogram

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat

/** Holds the user-started automation runtime, never another Flutter engine. */
class BotService : Service() {
    companion object { const val CHANNEL = "bot_runtime"; const val NOTICE = 8101; const val STOP = "bottogram.STOP_BOTS" }
    var running = false
        private set
    private var count = 0
    private var explicitStop = false
    private var wakeLock: PowerManager.WakeLock? = null
    private val app get() = application as BottogramApplication
    override fun onBind(intent: Intent?): IBinder? = null
    override fun onCreate() {
        super.onCreate()
        if (Build.VERSION.SDK_INT >= 26) {
            getSystemService(NotificationManager::class.java).createNotificationChannel(
                NotificationChannel(CHANNEL, "Running bots", NotificationManager.IMPORTANCE_LOW)
                    .apply { description = "User-started Telegram bot automations" })
        }
    }
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == STOP) {
            app.stopBots { success -> if (success) stopExplicitly() else updateCount(count) }
            return START_NOT_STICKY
        }
        count = intent?.getIntExtra("count", 0) ?: 0
        // A service may not resurrect stopped bots or create an unowned engine.
        if (count <= 0) { stopSelf(); return START_NOT_STICKY }
        try {
            if (Build.VERSION.SDK_INT >= 34) startForeground(NOTICE, notification(), ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
            else startForeground(NOTICE, notification())
            if (wakeLock == null) {
                wakeLock = getSystemService(PowerManager::class.java)
                    .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "bottogram:running-bots")
                    .apply { setReferenceCounted(false); acquire() }
            }
            running = true; app.service = this; app.stateChanged()
        } catch (_: Exception) { stopSelf() }
        // After process death, reboot or force-stop the user explicitly starts
        // again. Persisted automation progress survives; active state does not.
        return START_NOT_STICKY
    }
    fun updateCount(value: Int) {
        if (value <= 0) { stopExplicitly(); return }
        count = value
        getSystemService(NotificationManager::class.java).notify(NOTICE, notification())
    }
    fun stopExplicitly() {
        explicitStop = true
        running = false
        if (app.service === this) app.service = null
        if (wakeLock?.isHeld == true) wakeLock?.release()
        wakeLock = null
        if (Build.VERSION.SDK_INT >= 24) stopForeground(STOP_FOREGROUND_REMOVE)
        else @Suppress("DEPRECATION") stopForeground(true)
        stopSelf(); app.stateChanged()
    }
    private fun notification(): Notification {
        val open = PendingIntent.getActivity(this, 0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val stop = PendingIntent.getService(this, 1, Intent(this, BotService::class.java).setAction(STOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        return NotificationCompat.Builder(this, CHANNEL)
            .setSmallIcon(R.drawable.ic_bot_service)
            .setContentTitle("Bottogram is running")
            .setContentText("$count ${if (count == 1) "bot" else "bots"} started · tap to open")
            .setContentIntent(open).setOngoing(true).setOnlyAlertOnce(true)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .addAction(0, "Stop bots", stop).build()
    }
    override fun onDestroy() {
        running = false
        if (app.service === this) app.service = null
        if (wakeLock?.isHeld == true) wakeLock?.release()
        wakeLock = null
        if (!explicitStop) app.stopBots { }
        app.stateChanged(); super.onDestroy()
    }
}
