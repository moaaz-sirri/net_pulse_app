package com.example.net_pulse_app

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Build
import android.os.SystemClock
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.net.HttpURLConnection
import java.net.Proxy
import java.net.URL
import java.util.concurrent.atomic.AtomicBoolean

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "netpulse/network")
            .setMethodCallHandler { call, result ->
                val transport = when (call.argument<String>("transport")) {
                    "wifi" -> NetworkCapabilities.TRANSPORT_WIFI
                    "mobile" -> NetworkCapabilities.TRANSPORT_CELLULAR
                    else -> null
                }
                if (call.method != "transfer" || transport == null) {
                    result.notImplemented()
                } else {
                    val url = call.argument<String>("url")
                    val bytes = call.argument<Int>("bytes")
                    val upload = call.argument<Boolean>("upload")
                    if (url == null || bytes == null || bytes !in 0..10_000_000 || upload == null) {
                        result.error("invalid_measurement", "Invalid transfer parameters", null)
                    } else {
                        measureOn(transport, url, bytes, upload, result)
                    }
                }
            }
    }

    private fun measureOn(
        transport: Int,
        url: String,
        bytes: Int,
        upload: Boolean,
        result: MethodChannel.Result
    ) {
        val manager = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val started = AtomicBoolean(false)
        val request = NetworkRequest.Builder()
            .addTransportType(transport)
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
            .build()
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                if (!started.compareAndSet(false, true)) return
                Thread {
                    try {
                        val timing = transfer(network, url, bytes, upload)
                        runOnUiThread { result.success(timing) }
                    } catch (error: Exception) {
                        runOnUiThread { result.error("measurement_failed", error.message, null) }
                    } finally {
                        manager.unregisterNetworkCallback(this)
                    }
                }.start()
            }

            override fun onUnavailable() {
                if (started.compareAndSet(false, true)) {
                    runOnUiThread { result.success(null) }
                }
            }
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                manager.requestNetwork(request, callback, 7000)
            } else {
                manager.requestNetwork(request, callback)
                android.os.Handler(mainLooper).postDelayed({
                    if (started.compareAndSet(false, true)) {
                        manager.unregisterNetworkCallback(callback)
                        result.success(null)
                    }
                }, 7000)
            }
        } catch (error: Exception) {
            result.error("network_request_failed", error.message, null)
        }
    }

    private fun transfer(network: Network, endpoint: String, bytes: Int, upload: Boolean): Map<String, Long> {
        val url = URL(endpoint)
        check(url.protocol == "https") { "Measurement requires HTTPS" }
        val connection = network.openConnection(url, Proxy.NO_PROXY) as HttpURLConnection
        try {
            connection.connectTimeout = 8000
            connection.readTimeout = 12000
            connection.instanceFollowRedirects = false
            connection.useCaches = false
            connection.setRequestProperty("Accept-Encoding", "identity")
            if (upload) {
                connection.requestMethod = "POST"
                connection.doOutput = true
                connection.setFixedLengthStreamingMode(bytes)
                connection.setRequestProperty("Content-Type", "application/octet-stream")
            }
            var start = SystemClock.elapsedRealtimeNanos()
            if (upload) connection.outputStream.use { it.write(ByteArray(bytes)) }
            val status = connection.responseCode
            check(status in 200..299) { "Unexpected HTTP status $status" }
            if (upload || bytes == 0) {
                return mapOf("start" to start / 1000, "end" to SystemClock.elapsedRealtimeNanos() / 1000)
            }
            start = SystemClock.elapsedRealtimeNanos()
            val buffer = ByteArray(32 * 1024)
            var received = 0
            connection.inputStream.use { input ->
                while (true) {
                    val size = input.read(buffer)
                    if (size == -1) break
                    received += size
                    check(SystemClock.elapsedRealtimeNanos() - start < 20_000_000_000L)
                }
            }
            check(received == bytes) { "Incomplete download" }
            return mapOf("start" to start / 1000, "end" to SystemClock.elapsedRealtimeNanos() / 1000)
        } finally {
            connection.disconnect()
        }
    }
}
