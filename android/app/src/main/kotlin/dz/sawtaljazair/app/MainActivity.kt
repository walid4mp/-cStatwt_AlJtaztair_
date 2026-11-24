package dz.sawtaljazair.app

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts a tiny native bridge for system notifications so the app needs no extra plugin.
 * Channel: dz.sawtaljazair.app/notifications
 */
class MainActivity : FlutterActivity() {
    private val channelName = "dz.sawtaljazair.app/notifications"
    private val channelId = "sawt_general"
    private val permissionCode = 7321
    private var methodChannel: MethodChannel? = null
    private var initialPayload: String? = null
    private var pendingPermission: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        initialPayload = intent?.getStringExtra("payload")
        createChannel()
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        methodChannel = ch
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "requestPermission" -> requestPermission(result)
                "enabled" -> result.success(isEnabled())
                "getInitialPayload" -> {
                    result.success(initialPayload)
                    initialPayload = null
                }
                "show" -> {
                    val id = (call.argument<Number>("id") ?: 0).toInt()
                    val title = call.argument<String>("title") ?: ""
                    val body = call.argument<String>("body") ?: ""
                    val payload = call.argument<String>("payload")
                    result.success(show(id, title, body, payload))
                }
                "cancelAll" -> {
                    (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancelAll()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val payload = intent.getStringExtra("payload")
        if (payload != null) methodChannel?.invokeMethod("onTap", payload)
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val ch = NotificationChannel(channelId, "Sawt Aljazair", NotificationManager.IMPORTANCE_HIGH)
            ch.description = "Messages, reports and updates"
            nm.createNotificationChannel(ch)
        }
    }

    private fun isEnabled(): Boolean {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val allowed = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        } else true
        return allowed && nm.areNotificationsEnabled()
    }

    private fun requestPermission(result: MethodChannel.Result) {
        if (isEnabled()) {
            result.success(true)
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            pendingPermission?.success(false)
            pendingPermission = result
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), permissionCode)
        } else {
            result.success(isEnabled())
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == permissionCode) {
            pendingPermission?.success(grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED)
            pendingPermission = null
        }
    }

    private fun show(id: Int, title: String, body: String, payload: String?): Boolean {
        if (!isEnabled()) return false
        return try {
            val intent = Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
                if (payload != null) putExtra("payload", payload)
            }
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)
            val pi = PendingIntent.getActivity(this, id, intent, flags)
            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) Notification.Builder(this, channelId) else @Suppress("DEPRECATION") Notification.Builder(this)
            builder.setSmallIcon(R.drawable.ic_stat_notify)
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(Notification.BigTextStyle().bigText(body))
                .setContentIntent(pi)
                .setAutoCancel(true)
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.notify(id, builder.build())
            true
        } catch (e: Exception) {
            false
        }
    }
}
