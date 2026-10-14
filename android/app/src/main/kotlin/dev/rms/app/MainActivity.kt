package dev.rms.app

import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val channelName = "dev.rms.app/update"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrBlank()) {
                            result.error("no_path", "installApk requires a file path", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val file = File(path)
                            if (!file.exists()) {
                                result.error("missing_file", "No downloaded update at $path", null)
                                return@setMethodCallHandler
                            }

                            // A FileProvider URI is required from Android 7: passing a
                            // raw file:// to another app throws FileUriExposedException.
                            val uri: Uri = FileProvider.getUriForFile(
                                this,
                                "$packageName.fileprovider",
                                file,
                            )

                            val intent = Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(uri, "application/vnd.android.package-archive")
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }

                            // Android shows its own confirmation; the user may decline,
                            // which is reported back as "cancelled" rather than an error.
                            val launched = try {
                                startActivity(intent)
                                "ok"
                            } catch (e: Exception) {
                                // No installer able to handle the package archive.
                                "failed"
                            }
                            result.success(launched)
                        } catch (e: Exception) {
                            result.error("install_failed", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}