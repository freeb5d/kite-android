package com.freeb5d.kite

import android.Manifest
import android.app.UiModeManager
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.net.Uri
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors
import kitecore.Kitecore

/**
 * Bridges the Flutter UI to the Go core ("kite/core" method channel) and to
 * KiteVpnService's connection status ("kite/status" event channel).
 */
class MainActivity : FlutterActivity() {

    private val io = Executors.newCachedThreadPool()
    private val main = Handler(Looper.getMainLooper())
    private var pendingConnect: Triple<String, String, String>? = null
    private var pendingResult: MethodChannel.Result? = null

    companion object {
        private const val REQ_VPN = 1
        private const val REQ_NOTIFICATIONS = 2
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, "kite/core").setMethodCallHandler { call, result ->
            handle(call, result)
        }

        EventChannel(messenger, "kite/status").setStreamHandler(object : EventChannel.StreamHandler {
            private var listener: ((Map<String, Any?>) -> Unit)? = null
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                val l: (Map<String, Any?>) -> Unit = { status -> events.success(status) }
                listener = l
                KiteVpnService.addListener(l)
            }

            override fun onCancel(arguments: Any?) {
                listener?.let { KiteVpnService.removeListener(it) }
                listener = null
            }
        })
    }

    /** Runs [block] off the main thread and replies with its result or error. */
    private fun background(result: MethodChannel.Result, block: () -> Any?) {
        io.execute {
            try {
                val value = block()
                main.post { result.success(value) }
            } catch (e: Exception) {
                main.post { result.error("error", e.message ?: e.toString(), null) }
            }
        }
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "parseLink" -> background(result) { Kitecore.parseLink(call.arguments as String) }
            "fetchSubscription" -> background(result) { Kitecore.fetchSubscription(call.arguments as String) }
            "shareLink" -> background(result) { Kitecore.shareLink(call.arguments as String) }
            "traffic" -> result.success(Kitecore.traffic())
            "test" -> background(result) { Kitecore.testConnection() }
            "ping" -> background(result) {
                try {
                    Kitecore.ping(call.argument<String>("server"), call.argument<String>("mode") ?: "tcp").toInt()
                } catch (_: Exception) {
                    -1
                }
            }
            "log" -> background(result) {
                val f = KiteVpnService.logFile(this)
                if (!f.exists()) "" else f.readText().takeLast(8000)
            }
            "info" -> result.success(
                mapOf(
                    "version" to packageManager.getPackageInfo(packageName, 0).versionName,
                    "core" to Kitecore.coreVersion(),
                    "isTv" to isTv(),
                    "sdk" to Build.VERSION.SDK_INT,
                    "abi" to (Build.SUPPORTED_ABIS.firstOrNull() ?: ""),
                ),
            )
            "connect" -> {
                val server = call.argument<String>("server") ?: return result.error("error", "no server", null)
                val mode = call.argument<String>("mode") ?: "vpn"
                val name = call.argument<String>("name") ?: ""
                connect(server, mode, name, result)
            }
            "disconnect" -> {
                startService(Intent(this, KiteVpnService::class.java).setAction(KiteVpnService.ACTION_STOP))
                result.success(null)
            }
            "openVpnSettings" -> {
                openSettings(Settings.ACTION_VPN_SETTINGS)
                result.success(null)
            }
            "openUrl" -> {
                try {
                    startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(call.arguments as String)))
                } catch (_: Exception) {}
                result.success(null)
            }
            "installApk" -> installApk(call.arguments as String, result)
            else -> result.notImplemented()
        }
    }

    private fun isTv(): Boolean {
        val ui = getSystemService(UI_MODE_SERVICE) as UiModeManager
        return ui.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION ||
            packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK)
    }

    private fun openSettings(action: String) {
        try {
            startActivity(Intent(action))
        } catch (_: Exception) {
            startActivity(Intent(Settings.ACTION_SETTINGS))
        }
    }

    private fun connect(server: String, mode: String, name: String, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQ_NOTIFICATIONS)
        }
        if (mode == "vpn") {
            val consent = VpnService.prepare(this)
            if (consent != null) {
                pendingConnect = Triple(server, mode, name)
                pendingResult = result
                @Suppress("DEPRECATION")
                startActivityForResult(consent, REQ_VPN)
                return
            }
        }
        startVpnService(server, mode, name)
        result.success(null)
    }

    private fun startVpnService(server: String, mode: String, name: String) {
        val intent = Intent(this, KiteVpnService::class.java)
            .setAction(KiteVpnService.ACTION_START)
            .putExtra(KiteVpnService.EXTRA_SERVER, server)
            .putExtra(KiteVpnService.EXTRA_MODE, mode)
            .putExtra(KiteVpnService.EXTRA_NAME, name)
        ContextCompat.startForegroundService(this, intent)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQ_VPN) return
        val pending = pendingConnect
        val res = pendingResult
        pendingConnect = null
        pendingResult = null
        if (resultCode == RESULT_OK && pending != null) {
            startVpnService(pending.first, pending.second, pending.third)
            res?.success(null)
        } else {
            res?.error("vpn_denied", "VPN permission was not granted.", null)
        }
    }

    private fun installApk(url: String, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !packageManager.canRequestPackageInstalls()) {
            startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName")))
            result.error("install_permission", "Allow Kite to install updates, then try again.", null)
            return
        }
        background(result) {
            val dir = File(cacheDir, "updates").apply { mkdirs() }
            val apk = File(dir, "kite-update.apk")
            val conn = URL(url).openConnection() as HttpURLConnection
            conn.instanceFollowRedirects = true
            conn.connectTimeout = 30_000
            conn.readTimeout = 60_000
            conn.inputStream.use { input -> apk.outputStream().use { input.copyTo(it) } }
            val expected = conn.contentLengthLong
            if (expected > 0 && apk.length() != expected) {
                throw IllegalStateException("download incomplete")
            }
            val uri = FileProvider.getUriForFile(this, "$packageName.files", apk)
            main.post {
                startActivity(
                    Intent(Intent.ACTION_VIEW)
                        .setDataAndType(uri, "application/vnd.android.package-archive")
                        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK),
                )
            }
            null
        }
    }
}
