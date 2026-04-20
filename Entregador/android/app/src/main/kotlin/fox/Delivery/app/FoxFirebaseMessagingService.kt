package fox.Delivery.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.media.RingtoneManager
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import kotlin.math.abs

class FoxFirebaseMessagingService : FirebaseMessagingService() {

    override fun onNewToken(token: String) {
        super.onNewToken(token)
        Log.i(TAG, "FCM onNewToken received token=$token")
        pushTokenToBackend(token)
    }

    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        super.onMessageReceived(remoteMessage)

        Log.i(
            TAG,
            "FCM raw message id=${remoteMessage.messageId} from=${remoteMessage.from} dataKeys=${remoteMessage.data.keys} hasNotification=${remoteMessage.notification != null}",
        )

        if (remoteMessage.notification != null) {
            Log.w(TAG, "Non data-only push detected. Native overlay depends on the data payload.")
        }

        if (remoteMessage.data.isEmpty()) {
            Log.w(TAG, "FCM ignored: empty data payload")
            return
        }

        val normalizedPayload = normalizePayload(remoteMessage.data)
        val type = normalizedPayload.type
        val orderId = normalizedPayload.orderId

        if (type != ORDER_REQUEST_TYPE && type != NEW_ORDER_TYPE && type != ASSIGN_TYPE) {
            Log.d(TAG, "FCM type does not require native order overlay: $type")
            return
        }

        if (orderId.isNullOrBlank() || orderId.toIntOrNull() == null) {
            Log.w(TAG, "FCM ignored because order_id is missing or invalid for type=$type")
            return
        }

        if (isAppInForeground()) {
            Log.d(TAG, "App is in foreground. Native overlay skipped for order_id=$orderId")
            return
        }

        val refreshOnly = isDuplicateOverlay(orderId)
        if (refreshOnly) {
            Log.d(TAG, "Duplicate incoming delivery suppressed for order_id=$orderId")
            return
        }

        showIncomingOrderFullScreenNotification(orderId)
        Log.d(TAG, "Incoming delivery full-screen notification requested for order_id=$orderId")
    }

    private fun normalizePayload(data: Map<String, String>): IncomingOrderPayload {
        val type = data["type"]?.trim().orEmpty().ifBlank {
            data["body_loc_key"]?.trim().orEmpty().ifBlank {
                data["notification_type"]?.trim().orEmpty()
            }
        }
        val orderId =
            data["order_id"]?.trim().orEmpty().ifBlank {
                data["orderId"]?.trim().orEmpty().ifBlank {
                    data["id"]?.trim().orEmpty().ifBlank {
                        data["order"]?.trim().orEmpty()
                    }
                }
            }.ifBlank { null }
        return IncomingOrderPayload(type = type, orderId = orderId)
    }

    private fun isAppInForeground(): Boolean {
        val runningAppProcesses =
            (getSystemService(ACTIVITY_SERVICE) as? ActivityManager)?.runningAppProcesses
                ?: return false
        val currentPackageName = applicationContext.packageName
        return runningAppProcesses.any {
            it.processName == currentPackageName &&
                it.importance == ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND
        }
    }

    private fun isDuplicateOverlay(orderId: String): Boolean {
        val preferences = getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
        val lastOrderId = preferences.getString(KEY_LAST_OVERLAY_ORDER_ID, null)
        val lastTimestamp = preferences.getLong(KEY_LAST_OVERLAY_TIMESTAMP, 0L)
        val now = System.currentTimeMillis()
        val isDuplicate = lastOrderId == orderId && now - lastTimestamp < DEDUPE_WINDOW_MS

        preferences.edit()
            .putString(KEY_LAST_OVERLAY_ORDER_ID, orderId)
            .putLong(KEY_LAST_OVERLAY_TIMESTAMP, now)
            .apply()

        return isDuplicate
    }

    private fun showIncomingOrderFullScreenNotification(orderId: String) {
        val notificationManager =
            getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        createIncomingOrderChannel(notificationManager)

        val intent = Intent(this, IncomingOrderActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            putExtra("order_id", orderId)
            putExtra("open_requests_fallback", false)
        }
        val pendingIntentFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            abs(orderId.hashCode()),
            intent,
            pendingIntentFlags,
        )

        val notification = NotificationCompat.Builder(this, INCOMING_ORDER_CHANNEL_ID)
            .setSmallIcon(R.drawable.notification_icon)
            .setContentTitle("Nova entrega")
            .setContentText("Pedido #$orderId aguardando aceite")
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setAutoCancel(true)
            .setOngoing(false)
            .setSound(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION))
            .setContentIntent(pendingIntent)
            .setFullScreenIntent(pendingIntent, true)
            .build()

        notificationManager.notify(
            INCOMING_ORDER_NOTIFICATION_ID_BASE + abs(orderId.hashCode()),
            notification,
        )
    }

    private fun createIncomingOrderChannel(notificationManager: NotificationManager) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }

        val channel = NotificationChannel(
            INCOMING_ORDER_CHANNEL_ID,
            "Nova entrega",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Alertas prioritarios de novas entregas"
            enableVibration(true)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }
        notificationManager.createNotificationChannel(channel)
    }

    private fun pushTokenToBackend(fcmToken: String) {
        Thread {
            val flutterPrefs = getSharedPreferences(FLUTTER_PREFS_NAME, MODE_PRIVATE)
            val authToken = flutterPrefs.getString(FLUTTER_PREF_TOKEN_KEY, "").orEmpty()
            if (authToken.isBlank()) {
                Log.w(TAG, "Skipping token sync because auth token is empty")
                return@Thread
            }

            try {
                val endpoint = URL("$BASE_URL$UPDATE_FCM_TOKEN_URI")
                val payload =
                    "_method=put&token=${URLEncoder.encode(authToken, "UTF-8")}&fcm_token=${URLEncoder.encode(fcmToken, "UTF-8")}"
                val connection = (endpoint.openConnection() as HttpURLConnection).apply {
                    requestMethod = "POST"
                    setRequestProperty("Content-Type", "application/x-www-form-urlencoded")
                    connectTimeout = 5000
                    readTimeout = 5000
                    doOutput = true
                }

                connection.outputStream.use { output ->
                    output.write(payload.toByteArray())
                }

                val responseCode = connection.responseCode
                if (responseCode in 200..299) {
                    Log.i(TAG, "FCM token synchronized with backend successfully. code=$responseCode")
                } else {
                    Log.e(TAG, "Failed to sync FCM token with backend. code=$responseCode")
                }
            } catch (exception: Exception) {
                Log.e(TAG, "Error syncing FCM token with backend: ${exception.message}", exception)
            }
        }.start()
    }

    data class IncomingOrderPayload(
        val type: String,
        val orderId: String?,
    )

    companion object {
        private const val TAG = "FoxFirebaseMsgService"
        private const val ORDER_REQUEST_TYPE = "order_request"
        private const val NEW_ORDER_TYPE = "new_order"
        private const val ASSIGN_TYPE = "assign"
        private const val PREFS_NAME = "fox_delivery_overlay_prefs"
        private const val KEY_LAST_OVERLAY_ORDER_ID = "last_overlay_order_id"
        private const val KEY_LAST_OVERLAY_TIMESTAMP = "last_overlay_timestamp"
        private const val DEDUPE_WINDOW_MS = 30_000L
        private const val INCOMING_ORDER_CHANNEL_ID = "fox_delivery_incoming_order_native"
        private const val INCOMING_ORDER_NOTIFICATION_ID_BASE = 9500
        private const val FLUTTER_PREFS_NAME = "FlutterSharedPreferences"
        private const val FLUTTER_PREF_TOKEN_KEY = "flutter.fox_delivery_driver_token"
        private const val BASE_URL = "https://www.foxgodelivery.com.br"
        private const val UPDATE_FCM_TOKEN_URI = "/api/v1/delivery-man/update-fcm-token"
    }
}
