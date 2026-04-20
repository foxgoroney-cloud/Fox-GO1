package fox.Delivery.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.graphics.PixelFormat
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.util.Log
import android.view.LayoutInflater
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.TextView
import androidx.core.app.NotificationCompat
import org.json.JSONObject

class OverlayService : Service() {

    private var windowManager: WindowManager? = null
    private var overlayView: View? = null
    private val handler = Handler(Looper.getMainLooper())
    private var countdownRunnable: Runnable? = null
    private var remainingSeconds = OVERLAY_TIMEOUT_SECONDS
    private var currentOrderId: String? = null
    private var currentDataJson: String? = null
    private var timerTextView: TextView? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        startOverlayForeground()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        currentOrderId = intent?.getStringExtra("order_id")
        currentDataJson = intent?.getStringExtra("data_json")
        val refreshOnly = intent?.getBooleanExtra("refresh_timer_only", false) ?: false

        if (currentOrderId.isNullOrBlank()) {
            Log.w(TAG, "OverlayService started without order_id. Stopping.")
            stopSelf()
            return START_NOT_STICKY
        }

        if (!Settings.canDrawOverlays(this)) {
            Log.w(TAG, "Overlay permission denied. Falling back to IncomingOrderActivity.")
            openIncomingOrderActivity(openRequestsFallback = false)
            stopSelf()
            return START_NOT_STICKY
        }

        if (overlayView == null && !refreshOnly) {
            showOverlay()
        } else if (overlayView != null) {
            bindOverlayData()
            startTimer(timerTextView)
        } else {
            stopSelf()
        }

        return START_NOT_STICKY
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Canal para manter o alerta de novo pedido ativo"
            }

            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun startOverlayForeground() {
        val intent = Intent(this, MainActivity::class.java)
        val pendingIntentFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val pendingIntent = PendingIntent.getActivity(this, 0, intent, pendingIntentFlags)

        val notification: Notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Fox Delivery")
            .setContentText("Novo pedido em destaque")
            .setSmallIcon(R.drawable.notification_icon)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfoTypes.FOREGROUND_TYPE,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun showOverlay() {
        if (overlayView != null) {
            return
        }

        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        val windowType =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_PHONE
            }
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            windowType,
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT,
        )

        overlayView = LayoutInflater.from(this).inflate(R.layout.overlay_order, null)
        timerTextView = overlayView?.findViewById(R.id.tvTimer)
        bindOverlayData()

        overlayView?.findViewById<Button>(R.id.btnAccept)?.setOnClickListener {
            openIncomingOrderActivity(openRequestsFallback = false)
            stopOverlay()
        }

        overlayView?.findViewById<Button>(R.id.btnReject)?.setOnClickListener {
            openIncomingOrderActivity(openRequestsFallback = true)
            stopOverlay()
        }

        try {
            windowManager?.addView(overlayView, params)
            startTimer(timerTextView)
        } catch (exception: Exception) {
            Log.e(TAG, "Unable to display overlay: ${exception.message}", exception)
            openIncomingOrderActivity(openRequestsFallback = false)
            stopOverlay()
        }
    }

    private fun bindOverlayData() {
        val titleText = overlayView?.findViewById<TextView>(R.id.tvTitle)
        val addressText = overlayView?.findViewById<TextView>(R.id.tvAddress)
        val amountText = overlayView?.findViewById<TextView>(R.id.tvAmount)

        titleText?.text = "Novo pedido #$currentOrderId"

        var detailsFound = false
        if (!currentDataJson.isNullOrBlank()) {
            try {
                val json = JSONObject(currentDataJson ?: "{}")
                val pickup = json.optString("pickup")
                val address = json.optString("address")
                val storeName = json.optString("store_name")
                val amount = json.optString("amount")

                when {
                    pickup.isNotBlank() -> {
                        addressText?.text = "Coleta: $pickup"
                        detailsFound = true
                    }
                    address.isNotBlank() -> {
                        addressText?.text = "Destino: $address"
                        detailsFound = true
                    }
                    storeName.isNotBlank() -> {
                        addressText?.text = "Origem: $storeName"
                        detailsFound = true
                    }
                }

                if (amount.isNotBlank()) {
                    amountText?.text = "Valor: $amount"
                } else {
                    amountText?.text = ""
                }
            } catch (exception: Exception) {
                Log.w(TAG, "Failed to parse overlay payload: ${exception.message}")
            }
        }

        if (!detailsFound) {
            addressText?.text = "Abra o app para ver os detalhes."
        }
    }

    private fun openIncomingOrderActivity(openRequestsFallback: Boolean) {
        val intent = Intent(this, IncomingOrderActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            putExtra("order_id", currentOrderId)
            putExtra("open_requests_fallback", openRequestsFallback)
        }
        startActivity(intent)
    }

    private fun startTimer(timerText: TextView?) {
        remainingSeconds = OVERLAY_TIMEOUT_SECONDS
        countdownRunnable?.let { handler.removeCallbacks(it) }

        countdownRunnable = object : Runnable {
            override fun run() {
                timerText?.text = "Tempo restante: ${remainingSeconds}s"

                if (remainingSeconds <= 0) {
                    stopOverlay()
                    return
                }

                remainingSeconds -= 1
                handler.postDelayed(this, 1000)
            }
        }

        handler.post(countdownRunnable!!)
    }

    private fun removeOverlay() {
        countdownRunnable?.let { handler.removeCallbacks(it) }
        countdownRunnable = null

        overlayView?.let { view ->
            try {
                windowManager?.removeView(view)
            } catch (exception: Exception) {
                Log.w(TAG, "removeView failed: ${exception.message}", exception)
            }
        }

        overlayView = null
        timerTextView = null
    }

    private fun stopOverlay() {
        removeOverlay()
        stopSelf()
    }

    override fun onDestroy() {
        removeOverlay()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    object ServiceInfoTypes {
        const val FOREGROUND_TYPE =
            android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC or
                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
    }

    companion object {
        private const val TAG = "OverlayService"
        private const val CHANNEL_ID = "fox_delivery_overlay"
        private const val CHANNEL_NAME = "Fox Delivery overlay"
        private const val NOTIFICATION_ID = 9411
        private const val OVERLAY_TIMEOUT_SECONDS = 40
    }
}
