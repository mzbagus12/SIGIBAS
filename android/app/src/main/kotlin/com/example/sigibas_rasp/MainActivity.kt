package com.example.sigibas_rasp

import io.flutter.embedding.android.FlutterActivity
import android.os.Bundle
import android.view.WindowManager
import android.os.Build
import android.os.Debug
import android.content.Intent
import android.content.ClipData
import android.content.pm.PackageManager
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest

class MainActivity : FlutterActivity() {
    private var photoResult: MethodChannel.Result? = null
    private val photoRequest = 7401
    private val expectedCertificate = "14f567cbfdb8703d59a482d33c4e8279e4ecc774a5628803ba53eb7b981b937a"
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "sigibas/photos").setMethodCallHandler { call, result ->
            if (call.method != "pick") { result.notImplemented(); return@setMethodCallHandler }
            if (photoResult != null) { result.error("PHOTO_BUSY", "Pemilihan foto sedang berjalan", null); return@setMethodCallHandler }
            photoResult = result
            try {
                val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                    type = "image/*"
                    addCategory(Intent.CATEGORY_OPENABLE)
                    putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("image/png", "image/jpeg"))
                }
                startActivityForResult(intent, photoRequest)
            } catch (_: Exception) { photoResult = null; result.error("PHOTO_PICK", "Foto tidak dapat dipilih", null) }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "sigibas/reports").setMethodCallHandler { call, result ->
            if (call.method != "shareExcel") { result.notImplemented(); return@setMethodCallHandler }
            try {
                val name = call.argument<String>("name") ?: ""
                val bytes = call.argument<ByteArray>("bytes") ?: throw IllegalArgumentException()
                require(name.length <= 150 && name.matches(Regex("[A-Za-z0-9_.-]+\\.xlsx")) && bytes.size <= 10 * 1024 * 1024)
                val folder = File(cacheDir, "report_exports").apply { mkdirs() }
                val file = File(folder, name)
                require(!file.exists())
                file.writeBytes(bytes)
                val uri = FileProvider.getUriForFile(this, "$packageName.reports", file)
                val send = Intent(Intent.ACTION_SEND).apply {
                    type = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
                    putExtra(Intent.EXTRA_STREAM, uri)
                    clipData = ClipData.newRawUri("Laporan agregat", uri)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
                startActivity(Intent.createChooser(send, "Bagikan laporan Excel"))
                result.success("shared")
            } catch (_: Exception) { result.error("REPORT_SHARE", "Laporan tidak dapat dibagikan", null) }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "sigibas/security").setMethodCallHandler { call, result ->
            if (call.method != "check") { result.notImplemented(); return@setMethodCallHandler }
            try { result.success(securityFindings()) }
            catch (_: Exception) { result.error("SECURITY_CHECK", "Pemeriksaan lokal gagal", null) }
        }
    }

    @Deprecated("Android result bridge for Flutter photo selection")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != photoRequest) return
        val result = photoResult ?: return
        photoResult = null
        if (resultCode != RESULT_OK || data?.data == null) { result.success(null); return }
        try {
            val bytes = contentResolver.openInputStream(data.data!!)?.use { val output = java.io.ByteArrayOutputStream(); val buffer = ByteArray(8192); while (output.size() <= 262144) { val count = it.read(buffer, 0, minOf(buffer.size, 262145 - output.size())); if (count < 0) break; output.write(buffer, 0, count) }; output.toByteArray() }
                ?: throw IllegalArgumentException()
            require(bytes.size <= 262144)
            result.success(bytes)
        } catch (_: Exception) { result.error("PHOTO_READ", "Foto gagal dibaca atau melebihi 256 KB", null) }
    }

    @Suppress("DEPRECATION")
    private fun securityFindings(): Map<String, Boolean> {
        val roots = listOf("/system/bin/su", "/system/xbin/su", "/sbin/su", "/su/bin/su", "/data/adb/magisk")
        val rooted = roots.any { File(it).exists() } || (Build.TAGS?.contains("test-keys") == true)
        val fingerprint = Build.FINGERPRINT.lowercase()
        val hardware = Build.HARDWARE.lowercase()
        val model = Build.MODEL.lowercase()
        val emulator = fingerprint.startsWith("generic") || fingerprint.contains("emulator") ||
            model.contains("sdk_gphone") || model.contains("android sdk built for") ||
            hardware.contains("goldfish") || hardware.contains("ranchu") || hardware.contains("vbox")
        val maps = try { File("/proc/self/maps").readText().lowercase() } catch (_: Exception) { "" }
        val hooked = listOf("frida-agent", "libfrida", "xposed", "lsposed", "substrate").any { maps.contains(it) } ||
            try { Class.forName("de.robv.android.xposed.XposedBridge"); true } catch (_: Throwable) { false }
        val signatures = if (Build.VERSION.SDK_INT >= 28) {
            packageManager.getPackageInfo(packageName, PackageManager.GET_SIGNING_CERTIFICATES).signingInfo?.apkContentsSigners
        } else { packageManager.getPackageInfo(packageName, PackageManager.GET_SIGNATURES).signatures }
        val signatureMismatch = packageName != "com.example.sigibas_rasp" || signatures.isNullOrEmpty() || signatures.any {
            MessageDigest.getInstance("SHA-256").digest(it.toByteArray()).joinToString("") { b -> "%02x".format(b.toInt() and 0xff) } != expectedCertificate
        }
        return mapOf("root" to rooted, "emulator" to emulator, "hook" to hooked,
            "debugger" to (Debug.isDebuggerConnected() || Debug.waitingForDebugger()), "signature" to signatureMismatch)
    }
}
