package com.freeb5d.kite

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import androidx.core.app.NotificationCompat
import java.io.File
import kitecore.Kitecore

/**
 * Runs the connection as a foreground service. In "vpn" mode it creates the
 * Android VPN tunnel and hands its file descriptor to xray-core's TUN
 * inbound; in "proxy" mode it only runs xray-core's local HTTP/SOCKS proxy.
 * The notification is the Android counterpart of the desktop tray icon.
 */
class KiteVpnService : VpnService() {

    companion object {
        const val ACTION_START = "com.freeb5d.kite.START"
        const val ACTION_STOP = "com.freeb5d.kite.STOP"
        const val EXTRA_SERVER = "server"
        const val EXTRA_MODE = "mode"
        const val EXTRA_NAME = "name"
        private const val CHANNEL = "kite"
        private const val NOTIFICATION_ID = 1

        private val main = Handler(Looper.getMainLooper())
        private val listeners = mutableSetOf<(Map<String, Any?>) -> Unit>()

        @Volatile
        var status: Map<String, Any?> = mapOf("state" to "stopped")
            private set

        fun addListener(l: (Map<String, Any?>) -> Unit) {
            listeners.add(l)
            l(status)
        }

        fun removeListener(l: (Map<String, Any?>) -> Unit) {
            listeners.remove(l)
        }

        private fun publish(s: Map<String, Any?>) {
            status = s
            main.post { listeners.toList().forEach { it(s) } }
        }

        fun logFile(ctx: Context) = File(ctx.filesDir, "xray.log")
    }

    private var tun: ParcelFileDescriptor? = null
    private var worker: Thread? = null
    private var vpnMode = false
    private var netCallback: ConnectivityManager.NetworkCallback? = null
    private var currentNet: Network? = null

    private val prefs get() = getSharedPreferences("kite_service", MODE_PRIVATE)

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopConnection()
                return START_NOT_STICKY
            }
            ACTION_START -> {
                val server = intent.getStringExtra(EXTRA_SERVER) ?: return START_NOT_STICKY
                val mode = intent.getStringExtra(EXTRA_MODE) ?: "vpn"
                val name = intent.getStringExtra(EXTRA_NAME) ?: ""
                prefs.edit().putString("server", server).putString("mode", mode).putString("name", name).apply()
                startConnection(server, mode, name)
            }
            else -> {
                // Restarted by the system after it killed the service (null
                // intent) or started by always-on VPN: reconnect to the last
                // server instead of silently staying disconnected.
                val server = prefs.getString("server", null)
                if (server == null) {
                    stopSelf()
                    return START_NOT_STICKY
                }
                startConnection(server, prefs.getString("mode", "vpn") ?: "vpn", prefs.getString("name", "") ?: "")
            }
        }
        return START_STICKY
    }

    /**
     * Follows the device's default network (Wi-Fi <-> mobile, Wi-Fi dropping
     * and coming back). On a change, tells Android which network the VPN now
     * runs over and drops the connections made over the old one: they're
     * dead, and would otherwise stall traffic until the user reconnects.
     */
    private fun watchNetwork() {
        if (netCallback != null) return
        val cm = getSystemService(ConnectivityManager::class.java) ?: return
        val cb = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                val changed = currentNet != null && currentNet != network
                currentNet = network
                if (vpnMode) {
                    try { setUnderlyingNetworks(arrayOf(network)) } catch (_: Exception) {}
                }
                if (changed) Thread { try { Kitecore.resetConnections() } catch (_: Exception) {} }.start()
            }
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                cm.registerDefaultNetworkCallback(cb)
            } else {
                val req = NetworkRequest.Builder()
                    .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                    .addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
                    .build()
                cm.registerNetworkCallback(req, cb)
            }
            netCallback = cb
        } catch (_: Exception) {}
    }

    private fun unwatchNetwork() {
        val cb = netCallback ?: return
        try { getSystemService(ConnectivityManager::class.java)?.unregisterNetworkCallback(cb) } catch (_: Exception) {}
        netCallback = null
        currentNet = null
    }

    private fun startConnection(server: String, mode: String, name: String) {
        showNotification(name)
        publish(mapOf("state" to "starting", "server" to name, "mode" to mode))
        stopEngine()

        worker = Thread {
            try {
                val log = logFile(this)
                log.writeText("")
                var fd = -1L
                if (mode == "vpn") {
                    val pfd = Builder()
                        .setSession("Kite")
                        .setMtu(1500)
                        .addAddress("10.19.0.1", 30)
                        .addRoute("0.0.0.0", 0)
                        .addAddress("fd66:19::1", 126)
                        .addRoute("::", 0)
                        .addDnsServer("1.1.1.1")
                        // Kite's own traffic (xray's connection to the server,
                        // its DNS lookups) must not loop back into the tunnel.
                        .addDisallowedApplication(packageName)
                        .establish() ?: throw IllegalStateException("VPN permission was revoked")
                    // The Go core owns the fd from here and releases it on stop;
                    // closing it here too could free a number that xray-core
                    // still writes packets to (e.g. into the next log file).
                    fd = pfd.detachFd().toLong()
                }
                Kitecore.start(server, fd, log.absolutePath)
                vpnMode = mode == "vpn"
                main.post { watchNetwork() }
                publish(mapOf("state" to "running", "server" to name, "mode" to mode, "since" to System.currentTimeMillis()))
            } catch (e: Exception) {
                stopEngine()
                publish(mapOf("state" to "error", "server" to name, "mode" to mode, "message" to (e.message ?: e.toString())))
                stopForegroundCompat()
                stopSelf()
            }
        }.also { it.start() }
    }

    private fun stopEngine() {
        try { Kitecore.stop() } catch (_: Exception) {}
        try { tun?.close() } catch (_: Exception) {}
        tun = null
    }

    private fun stopConnection() {
        // The user disconnected: don't reconnect on a system restart.
        prefs.edit().remove("server").apply()
        unwatchNetwork()
        stopEngine()
        publish(mapOf("state" to "stopped"))
        stopForegroundCompat()
        stopSelf()
    }

    override fun onRevoke() {
        // Another VPN app took over, or the user revoked permission.
        stopConnection()
    }

    override fun onDestroy() {
        unwatchNetwork()
        stopEngine()
        if (status["state"] != "error") publish(mapOf("state" to "stopped"))
        super.onDestroy()
    }

    private fun showNotification(name: String) {
        val nm = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(NotificationChannel(CHANNEL, "Kite", NotificationManager.IMPORTANCE_LOW))
        }
        val open = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val stop = PendingIntent.getService(
            this, 1, Intent(this, KiteVpnService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val n: Notification = NotificationCompat.Builder(this, CHANNEL)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle("Kite")
            .setContentText(name)
            .setOngoing(true)
            .setContentIntent(open)
            .addAction(0, getString(R.string.disconnect), stop)
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIFICATION_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION_ID, n)
        }
    }

    private fun stopForegroundCompat() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
    }
}
