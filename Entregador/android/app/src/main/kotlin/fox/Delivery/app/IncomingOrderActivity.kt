package fox.Delivery.app

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.util.Log
import io.flutter.embedding.android.FlutterActivity

class IncomingOrderActivity : FlutterActivity() {

    private var orderId: String? = null
    private var openRequestsFallback: Boolean = false

    override fun onCreate(savedInstanceState: Bundle?) {
        orderId = intent?.getStringExtra("order_id")
        openRequestsFallback = intent?.getBooleanExtra("open_requests_fallback", false) ?: false
        Log.d(TAG, "IncomingOrderActivity opening route for order_id=$orderId fallback=$openRequestsFallback")

        super.onCreate(savedInstanceState)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        }

        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        @Suppress("DEPRECATION")
        val wakeLock = powerManager.newWakeLock(
            PowerManager.SCREEN_BRIGHT_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP,
            "FoxDelivery:IncomingOrder",
        )
        wakeLock.acquire(4000)

        if (orderId.isNullOrBlank()) {
            Log.w(TAG, "IncomingOrderActivity missing order_id extra. Redirecting to dashboard.")
            startActivity(
                Intent(this, MainActivity::class.java).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                },
            )
            finish()
        }
    }

    override fun getInitialRoute(): String {
        val parsedOrderId = orderId?.toIntOrNull()
        return if (parsedOrderId == null) {
            "/main"
        } else if (!openRequestsFallback) {
            "/main?page=home&order_id=$parsedOrderId"
        } else {
            "/main?page=order-request&order_id=$parsedOrderId"
        }
    }

    companion object {
        private const val TAG = "IncomingOrderActivity"
    }
}
