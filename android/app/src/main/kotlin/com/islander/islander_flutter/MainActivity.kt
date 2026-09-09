package com.islander.islander_flutter

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent
import android.app.Activity

class MainActivity : FlutterActivity() {
    private var backupResult: MethodChannel.Result? = null
    private var backupBytes: ByteArray? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "islander/cache_backup")
            .setMethodCallHandler { call, result ->
                if (call.method != "save") { result.notImplemented(); return@setMethodCallHandler }
                if (backupResult != null) { result.error("busy", "已有导出操作", null); return@setMethodCallHandler }
                val bytes = call.argument<ByteArray>("bytes")
                val name = call.argument<String>("name")
                if (bytes == null || bytes.size > 34 * 1024 * 1024 || name == null || !name.matches(Regex("islander-cache-[A-Za-z0-9-]+\\.zip"))) {
                    result.error("invalid", "备份参数异常", null); return@setMethodCallHandler
                }
                backupBytes = bytes
                backupResult = result
                try {
                    startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "application/zip"
                        putExtra(Intent.EXTRA_TITLE, name)
                    }, 8103)
                } catch (error: Exception) {
                    backupBytes = null; backupResult = null
                    result.error("save", "无法打开系统文件保存器", null)
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != 8103) { super.onActivityResult(requestCode, resultCode, data); return }
        val result = backupResult ?: return
        val bytes = backupBytes
        backupResult = null; backupBytes = null
        if (resultCode != Activity.RESULT_OK || data?.data == null || bytes == null) { result.success(false); return }
        val uri = data.data!!
        Thread {
            try {
                val stream = contentResolver.openOutputStream(uri, "w") ?: throw IllegalStateException()
                stream.use { it.write(bytes) }
                runOnUiThread { result.success(true) }
            } catch (error: Exception) {
                runOnUiThread { result.error("save", "保存失败，请检查存储空间后重试", null) }
            }
        }.start()
    }
}
