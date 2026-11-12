package com.hayyaun.bottogram.bottogram

import android.app.ActivityManager
import android.app.Application
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.embedding.engine.FlutterShellArgs
import io.flutter.plugin.common.MethodChannel

class BottogramApplication : Application() {
    companion object { const val ENGINE = "bottogram-runtime" }
    var activity: MainActivity? = null
    var service: BotService? = null
    private var channel: MethodChannel? = null

    // One process, engine, Dart isolate and Hive owner. Reopening the Activity
    // attaches to this engine instead of creating a second bot registry.
    fun engineFor(host: MainActivity): FlutterEngine {
        FlutterEngineCache.getInstance().get(ENGINE)?.let { return it }
        val engine = FlutterEngine(this, FlutterShellArgs.fromIntent(host.intent).toArray())
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, "bottogram/background")
        channel!!.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "getState" -> result.success(state())
                    "openBatterySettings" -> result.success(openSettings(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)))
                    "openAppSettings" -> result.success(openSettings(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))))
                    "requestNotifications" -> {
                        val current = activity
                        if (current == null) result.error("activity_required", "Open Bottogram first.", null)
                        else current.requestNotifications(result)
                    }
                    "startService" -> {
                        val active = call.argument<Int>("active") ?: 0
                        val total = call.argument<Int>("total") ?: 0
                        require(total > 0 && active in 0..total)
                        val current = service
                        if (current?.running == true) {
                            current.updateCounts(active, total)
                        } else {
                            check(activity?.foreground == true) { "Open Bottogram to start bots." }
                            val intent = Intent(this, BotService::class.java)
                                .putExtra(BotService.ACTIVE, active)
                                .putExtra(BotService.TOTAL, total)
                            ContextCompat.startForegroundService(this, intent)
                        }
                        result.success(null)
                    }
                    "updateService" -> {
                        val current = service ?: error("The bot service is no longer running.")
                        val active = call.argument<Int>("active") ?: 0
                        val total = call.argument<Int>("total") ?: 0
                        current.updateCounts(active, total)
                        result.success(null)
                    }
                    "updateConnectionWarning" -> {
                        val affected = call.argument<Int>("affected") ?: 0
                        BotService.updateConnectionWarning(this, affected)
                        result.success(null)
                    }
                    "stopService" -> {
                        service?.stopExplicitly()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (_: Exception) {
                result.error("background_operation_failed", "Android could not complete this operation. Open Bottogram and check background settings.", null)
            }
        }
        FlutterEngineCache.getInstance().put(ENGINE, engine)
        engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
        return engine
    }

    private fun state(): Map<String, Any> = mapOf(
        "batteryExempt" to getSystemService(PowerManager::class.java).isIgnoringBatteryOptimizations(packageName),
        "backgroundRestricted" to (Build.VERSION.SDK_INT >= 28 && getSystemService(ActivityManager::class.java).isBackgroundRestricted),
        "notificationsEnabled" to (NotificationManagerCompat.from(this).areNotificationsEnabled() &&
            (Build.VERSION.SDK_INT < 26 || getSystemService(NotificationManager::class.java).getNotificationChannel(BotService.CHANNEL)?.importance != NotificationManager.IMPORTANCE_NONE)),
        "serviceRunning" to (service?.running == true)
    )
    private fun openSettings(intent: Intent): Boolean {
        val host = activity ?: return false
        if (intent.resolveActivity(packageManager) == null) return false
        host.startActivity(intent)
        return true
    }
    fun serviceEnded() { channel?.invokeMethod("serviceEnded", null) }
    fun stateChanged() { channel?.invokeMethod("stateChanged", null) }
    fun stopBots(done: (Boolean) -> Unit) {
        val target = channel
        if (target == null) { done(false); return }
        target.invokeMethod("stopBots", null, object : MethodChannel.Result {
            override fun success(result: Any?) = done(true)
            override fun error(code: String, message: String?, details: Any?) = done(false)
            override fun notImplemented() = done(false)
        })
    }
}
