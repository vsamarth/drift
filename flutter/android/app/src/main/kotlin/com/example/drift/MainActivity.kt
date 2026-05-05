package com.example.drift

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "com.example.drift/file_picker"
        private const val REQUEST_CODE_PICK_FILES = 2001
    }

    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "pickFiles" -> {
                    if (pendingResult != null) {
                        result.error("ALREADY_PICKING", "A file pick is already in progress", null)
                        return@setMethodCallHandler
                    }
                    pendingResult = result
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "*/*"
                        putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
                    }
                    @Suppress("DEPRECATION")
                    startActivityForResult(intent, REQUEST_CODE_PICK_FILES)
                }
                else -> result.notImplemented()
            }
        }
    }

    @Suppress("DEPRECATION", "OVERRIDE_DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == REQUEST_CODE_PICK_FILES) {
            val result = pendingResult
            pendingResult = null
            if (result == null) {
                super.onActivityResult(requestCode, resultCode, data)
                return
            }
            if (resultCode != Activity.RESULT_OK || data == null) {
                result.success(emptyList<String>())
                return
            }
            val uris = mutableListOf<Uri>()
            val clipData = data.clipData
            if (clipData != null) {
                for (i in 0 until clipData.itemCount) {
                    uris.add(clipData.getItemAt(i).uri)
                }
            } else {
                data.data?.let { uris.add(it) }
            }
            val paths = uris.mapNotNull { uri -> copyUriToCache(uri) }
            result.success(paths)
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    // Streams a content URI to the app cache directory to avoid encoding
    // large files as bytes through the Flutter platform channel.
    private fun copyUriToCache(uri: Uri): String? {
        return try {
            val fileName = resolveFileName(uri) ?: "picked_${System.currentTimeMillis()}"
            val dir = File(cacheDir, "drift_picked")
            dir.mkdirs()
            // Prefix with timestamp so repeated picks of the same name don't collide.
            val cacheFile = File(dir, "${System.currentTimeMillis()}_$fileName")
            contentResolver.openInputStream(uri)?.use { input ->
                FileOutputStream(cacheFile).use { output ->
                    input.copyTo(output, bufferSize = 65_536)
                }
            }
            cacheFile.absolutePath
        } catch (_: Exception) {
            null
        }
    }

    private fun resolveFileName(uri: Uri): String? {
        return try {
            contentResolver.query(
                uri,
                arrayOf(OpenableColumns.DISPLAY_NAME),
                null, null, null,
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val idx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (idx >= 0) cursor.getString(idx) else null
                } else null
            }
        } catch (_: Exception) {
            null
        }
    }
}
