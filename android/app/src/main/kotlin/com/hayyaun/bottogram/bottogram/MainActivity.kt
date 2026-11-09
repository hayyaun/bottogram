package com.hayyaun.bottogram.bottogram

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build

class MainActivity : FlutterActivity() {
    var foreground = false
    private var permissionResult: MethodChannel.Result? = null
    override fun provideFlutterEngine(context: Context): FlutterEngine =
        (application as BottogramApplication).engineFor(this)
    override fun shouldDestroyEngineWithHost() = false
    override fun onResume() {
        super.onResume()
        foreground = true
        (application as BottogramApplication).activity = this
    }
    override fun onPause() { foreground = false; super.onPause() }
    override fun onDestroy() {
        val app = application as BottogramApplication
        if (app.activity === this) app.activity = null
        permissionResult?.error("activity_closed", "Reopen notification settings.", null)
        permissionResult = null
        super.onDestroy()
    }
    fun requestNotifications(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < 33 || checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
            result.success(null); return
        }
        if (permissionResult != null) { result.error("request_pending", "A request is already open.", null); return }
        permissionResult = result
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 8102)
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 8102) { permissionResult?.success(null); permissionResult = null }
    }
}
