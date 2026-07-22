package jp.co.pdf.example.dev

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.pdf.PdfRenderer
import android.net.Uri
import android.os.Build
import android.os.ParcelFileDescriptor
import android.os.PowerManager
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File

class MainActivity : FlutterActivity() {
    companion object {
        private const val CAPTURE_CHANNEL = "jp.co.pdf.example.dev/capture_protection"
        private const val THUMBNAIL_CHANNEL = "app.pdf.thumbnail"
        private const val NOTIFICATION_CHANNEL = "app.notification.android"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 画面キャプチャ保護チャンネル
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CAPTURE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "enable" -> {
                        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        result.success(null)
                    }
                    "disable" -> {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        // PDFサムネイルチャンネル（PdfRenderer を使った高速サムネイル生成）
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, THUMBNAIL_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getThumbnail" -> {
                        val path = call.argument<String>("path")
                        val pageIndex = call.argument<Int>("pageIndex") ?: 0
                        val width = (call.argument<Double>("width") ?: 400.0).toInt()
                        if (path == null) {
                            result.error("INVALID_ARGS", "path is required", null)
                            return@setMethodCallHandler
                        }
                        Thread {
                            try {
                                val file = File(path)
                                val pfd = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
                                val renderer = PdfRenderer(pfd)
                                val page = renderer.openPage(pageIndex)
                                val height = (width * page.height.toFloat() / page.width).toInt()
                                val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                                // PDF ページは背景が透明な場合がある。
                                // ビットマップのデフォルト値は 0（透明=黒）のため、
                                // 描画前に白で塗りつぶして透明領域を白くする。
                                bitmap.eraseColor(android.graphics.Color.WHITE)
                                page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                                page.close()
                                renderer.close()
                                pfd.close()
                                val stream = ByteArrayOutputStream()
                                bitmap.compress(Bitmap.CompressFormat.JPEG, 75, stream)
                                val bytes = stream.toByteArray()
                                bitmap.recycle()
                                runOnUiThread { result.success(bytes) }
                            } catch (e: Exception) {
                                runOnUiThread { result.success(null) }
                            }
                        }.start()
                    }
                    // zonedSchedule 用タイムゾーン名（IANA 形式: "Asia/Tokyo" 等）
                    "getTimezone" -> result.success(java.util.TimeZone.getDefault().id)
                    else -> result.notImplemented()
                }
            }

        // 通知関連チャンネル
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NOTIFICATION_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {

                    // AlarmManager で通知をスケジュール。
                    // LocalNotificationReceiver が Flutter エンジン不要で通知を表示するため
                    // kill 状態でも確実に動作する。
                    "scheduleLocalNotification" -> {
                        val id      = call.argument<Int>("id") ?: 0
                        val title   = call.argument<String>("title") ?: ""
                        val body    = call.argument<String>("body") ?: ""
                        // MethodChannel は Dart int を Integer で送ることがあるため Number 経由で変換
                        val delayMs = (call.argument<Any>("delayMs") as? Number)?.toLong() ?: 1000L

                        LocalNotificationReceiver.createChannel(applicationContext)

                        val intent = Intent(applicationContext, LocalNotificationReceiver::class.java).apply {
                            putExtra(LocalNotificationReceiver.EXTRA_ID, id)
                            putExtra(LocalNotificationReceiver.EXTRA_TITLE, title)
                            putExtra(LocalNotificationReceiver.EXTRA_BODY, body)
                        }
                        val pending = PendingIntent.getBroadcast(
                            applicationContext, id, intent,
                            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                        )
                        val triggerMs = System.currentTimeMillis() + delayMs
                        val am = getSystemService(Context.ALARM_SERVICE) as AlarmManager
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerMs, pending)
                        } else {
                            am.setExact(AlarmManager.RTC_WAKEUP, triggerMs, pending)
                        }
                        result.success(null)
                    }

                    // 指定 ID のスケジュール済み通知をキャンセル
                    "cancelLocalNotification" -> {
                        val id = call.argument<Int>("id") ?: 0
                        val intent = Intent(applicationContext, LocalNotificationReceiver::class.java)
                        val pending = PendingIntent.getBroadcast(
                            applicationContext, id, intent,
                            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
                        )
                        pending?.let {
                            (getSystemService(Context.ALARM_SERVICE) as AlarmManager).cancel(it)
                            it.cancel()
                        }
                        result.success(null)
                    }

                    // 電池最適化の除外をシステムダイアログでリクエストする。
                    "requestBatteryOptimizationExemption" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                            if (!pm.isIgnoringBatteryOptimizations(packageName)) {
                                val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                                intent.data = Uri.parse("package:$packageName")
                                startActivity(intent)
                            }
                        }
                        result.success(null)
                    }

                    else -> result.notImplemented()
                }
            }
    }
}
