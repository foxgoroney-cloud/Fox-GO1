package fox.Delivery.app

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val settingsChannel = "fox.delivery/device_settings"
    private val fullScreenChannel = "deliveryman/full_screen_intent"
    private val overlayChannel = "overlay_channel"
    private val retainChannel = "fox.delivery/app_retain"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, settingsChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "openNotificationSettings" -> result.success(openNotificationSettings())
                "openBatteryOptimizationSettings" -> result.success(openBatteryOptimizationSettings())
                "openBatteryOptimizationListSettings" -> result.success(openBatteryOptimizationListSettings())
                "openAppDetailsSettings" -> result.success(openAppDetailsSettings())
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, fullScreenChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "openSettings" -> {
                    openFullScreenIntentSettings()
                    result.success(true)
                }
                "launchFullScreenOrder" -> {
                    launchFullScreenOrder()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, overlayChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "show_overlay" -> {
                    startOverlayService()
                    result.success(true)
                }
                "remove_overlay" -> {
                    stopOverlayService()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, retainChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "sendToBackground" -> result.success(moveTaskToBack(true))
                else -> result.notImplemented()
            }
        }
    }

    private fun openNotificationSettings(): Boolean {
        val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
            putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
            putExtra("app_package", packageName)
            putExtra("app_uid", applicationInfo.uid)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return launchIntent(intent, appDetailsIntent())
    }

    private fun openBatteryOptimizationSettings(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            if (!powerManager.isIgnoringBatteryOptimizations(packageName)) {
                val directIntent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                    data = Uri.parse("package:$packageName")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                if (launchIntent(directIntent)) {
                    return true
                }
            }
            if (openBatteryOptimizationListSettings()) {
                return true
            }
        }

        return openAppDetailsSettings()
    }

    private fun openBatteryOptimizationListSettings(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val batterySettingsIntent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            if (launchIntent(batterySettingsIntent)) {
                return true
            }
        }
        return openAppDetailsSettings()
    }

    private fun openAppDetailsSettings(): Boolean {
        return launchIntent(appDetailsIntent())
    }

    private fun launchFullScreenOrder() {
        val intent = Intent(this, FullScreenOrderActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
    }

    private fun startOverlayService() {
        val intent = Intent(this, OverlayService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun stopOverlayService() {
        val intent = Intent(this, OverlayService::class.java)
        stopService(intent)
    }

    private fun openFullScreenIntentSettings() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            val intent = Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT).apply {
                data = Uri.parse("package:$packageName")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
        }
    }

    private fun appDetailsIntent(): Intent {
        return Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.fromParts("package", packageName, null)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
    }

    private fun launchIntent(intent: Intent, fallback: Intent? = null): Boolean {
        return try {
            when {
                intent.resolveActivity(packageManager) != null -> {
                    startActivity(intent)
                    true
                }
                fallback != null && fallback.resolveActivity(packageManager) != null -> {
                    startActivity(fallback)
                    true
                }
                else -> false
            }
        } catch (_: Exception) {
            false
        }
    }
}
