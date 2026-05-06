package cn.niuma.niuma_player.dlna

import android.content.Context
import android.net.wifi.WifiManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/// Multicast lock plugin for DLNA SSDP UDP 多播。
class NiumaDlnaPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private var context: Context? = null
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "niuma_player_dlna/multicast")
        channel.setMethodCallHandler(this)
        context = binding.applicationContext
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "acquire" -> {
                acquireLock()
                result.success(null)
            }
            "release" -> {
                releaseLock()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun acquireLock() {
        val ctx = context ?: return
        if (multicastLock != null) return
        val wm = ctx.getSystemService(Context.WIFI_SERVICE) as? WifiManager ?: return
        val lock = wm.createMulticastLock("niuma_player_dlna")
        lock.setReferenceCounted(false)
        lock.acquire()
        multicastLock = lock
    }

    private fun releaseLock() {
        multicastLock?.let { if (it.isHeld) it.release() }
        multicastLock = null
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        releaseLock()
        channel.setMethodCallHandler(null)
        context = null
    }
}
