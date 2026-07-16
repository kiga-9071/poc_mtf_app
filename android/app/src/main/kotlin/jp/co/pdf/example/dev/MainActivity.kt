package jp.co.pdf.example.dev

import android.graphics.Bitmap
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
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
                if (call.method != "getThumbnail") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
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
    }
}
