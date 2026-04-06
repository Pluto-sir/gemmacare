package com.example.gemmacare

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterFragmentActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "gemmacare/bundled_model")
            .setMethodCallHandler { call, result ->
                if (call.method != "prepareBundledModel") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                Thread {
                    try {
                        val path = copyBundledModelIfNeeded()
                        runOnMain { result.success(path) }
                    } catch (e: Exception) {
                        runOnMain {
                            result.error(
                                "PREPARE_FAILED",
                                e.message ?: e.javaClass.simpleName,
                                null,
                            )
                        }
                    }
                }.start()
            }
    }

    private fun runOnMain(block: () -> Unit) {
        Handler(Looper.getMainLooper()).post(block)
    }

    /**
     * Streams from APK assets to app filesDir (chunked) so large GGUF does not use Dart heap.
     * Skips copy when an existing file already matches the packaged asset size.
     */
    private fun copyBundledModelIfNeeded(): String {
        val assetPath = "models/gemma-care.gguf"
        val outFile = File(filesDir, "gemma-care.gguf")

        val expectedLen = assets.openFd(assetPath).use { it.length }
        if (outFile.exists() && outFile.length() == expectedLen) {
            return outFile.absolutePath
        }

        FileOutputStream(outFile).use { output ->
            assets.open(assetPath).use { input ->
                val buffer = ByteArray(8 * 1024 * 1024)
                var n: Int
                while (input.read(buffer).also { n = it } != -1) {
                    output.write(buffer, 0, n)
                }
            }
        }
        return outFile.absolutePath
    }
}
