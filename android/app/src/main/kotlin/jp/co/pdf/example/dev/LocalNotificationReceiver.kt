package jp.co.pdf.example.dev

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

/**
 * AlarmManager からアラームを受け取り通知を表示する BroadcastReceiver。
 * Flutter エンジンに依存しないため、アプリ kill 状態でも確実に動作する。
 */
class LocalNotificationReceiver : BroadcastReceiver() {

    companion object {
        const val CHANNEL_ID = "jal_app_notification"
        const val EXTRA_ID = "notif_id"
        const val EXTRA_TITLE = "notif_title"
        const val EXTRA_BODY = "notif_body"

        fun createChannel(context: Context) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                if (nm.getNotificationChannel(CHANNEL_ID) == null) {
                    nm.createNotificationChannel(
                        NotificationChannel(CHANNEL_ID, "アプリ通知", NotificationManager.IMPORTANCE_HIGH).apply {
                            description = "JAL機内誌アプリからのお知らせ"
                        }
                    )
                }
            }
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        val id    = intent.getIntExtra(EXTRA_ID, 0)
        val title = intent.getStringExtra(EXTRA_TITLE) ?: return
        val body  = intent.getStringExtra(EXTRA_BODY) ?: ""

        createChannel(context)

        // 通知タップでアプリを前面に出す
        val launchIntent = context.packageManager
            .getLaunchIntentForPackage(context.packageName)
            ?.apply { flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP }
        val tapPending = PendingIntent.getActivity(
            context, id, launchIntent ?: Intent(),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_popup_reminder)
            .setContentTitle(title)
            .setContentText(body)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(tapPending)
            .build()

        try {
            NotificationManagerCompat.from(context).notify(id, notification)
        } catch (_: SecurityException) {
            // POST_NOTIFICATIONS 権限が未付与の場合は無視
        }
    }
}
