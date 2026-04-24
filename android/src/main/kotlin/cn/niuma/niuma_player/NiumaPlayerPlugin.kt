package cn.niuma.niuma_player

import android.content.Context
import android.os.Build
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.view.TextureRegistry
import java.security.MessageDigest

/** NiumaPlayerPlugin */
class NiumaPlayerPlugin : FlutterPlugin, MethodCallHandler {

    private lateinit var channel: MethodChannel
    private var messenger: BinaryMessenger? = null
    private var textureRegistry: TextureRegistry? = null
    private var applicationContext: Context? = null

    private val players: MutableMap<Long, NiumaPlayer> = mutableMapOf()

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        messenger = flutterPluginBinding.binaryMessenger
        textureRegistry = flutterPluginBinding.textureRegistry
        applicationContext = flutterPluginBinding.applicationContext

        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "cn.niuma/player")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        // Preserved from scaffold so existing unit test keeps passing without
        // needing a FlutterPluginBinding.
        if (call.method == "getPlatformVersion") {
            result.success("Android ${Build.VERSION.RELEASE}")
            return
        }

        when (call.method) {
            "create" -> handleCreate(call, result)
            "dispose" -> handleDispose(call, result)
            "play" -> forward(call, result) { it.play() }
            "pause" -> forward(call, result) { it.pause() }
            "seekTo" -> forward(call, result) { p ->
                val positionMs = (call.argument<Number>("positionMs") ?: 0).toLong()
                p.seekTo(positionMs)
            }
            "setSpeed" -> forward(call, result) { p ->
                val speed = (call.argument<Number>("speed") ?: 1.0).toFloat()
                p.setSpeed(speed)
            }
            "setVolume" -> forward(call, result) { p ->
                val volume = (call.argument<Number>("volume") ?: 1.0).toFloat()
                p.setVolume(volume)
            }
            "deviceFingerprint" -> {
                result.success(mapOf("fingerprint" to deviceFingerprint()))
            }
            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        // Release every active player instance.
        val snapshot = players.values.toList()
        players.clear()
        for (p in snapshot) {
            try {
                p.release()
            } catch (_: Throwable) {
            }
        }

        channel.setMethodCallHandler(null)
        messenger = null
        textureRegistry = null
        applicationContext = null
    }

    // ---------------------------------------------------------------------
    // Handlers
    // ---------------------------------------------------------------------

    private fun handleCreate(call: MethodCall, result: Result) {
        val registry = textureRegistry
        val msg = messenger
        val ctx = applicationContext
        if (registry == null || msg == null || ctx == null) {
            result.error(
                "NIUMA_PLAYER_UNATTACHED",
                "Plugin is not attached to a FlutterEngine",
                null
            )
            return
        }

        try {
            val uri = call.argument<String>("uri")
                ?: throw IllegalArgumentException("uri is required")
            val type = call.argument<String>("type") ?: "network"
            @Suppress("UNCHECKED_CAST")
            val headers = call.argument<Map<String, String>>("headers")

            val dataSource = mapOf<String, Any?>(
                "uri" to uri,
                "type" to type,
                "headers" to headers
            )

            val player = NiumaPlayer(registry, msg, ctx, dataSource)
            players[player.textureId] = player

            result.success(
                mapOf(
                    "textureId" to player.textureId,
                    "fingerprint" to deviceFingerprint()
                )
            )
        } catch (e: Throwable) {
            result.error("NIUMA_PLAYER_CREATE_FAILED", e.message, null)
        }
    }

    private fun handleDispose(call: MethodCall, result: Result) {
        val textureId = (call.argument<Number>("textureId") ?: -1).toLong()
        val player = players.remove(textureId)
        try {
            player?.release()
            result.success(null)
        } catch (e: Throwable) {
            result.error("NIUMA_PLAYER_DISPOSE_FAILED", e.message, null)
        }
    }

    private inline fun forward(
        call: MethodCall,
        result: Result,
        block: (NiumaPlayer) -> Unit
    ) {
        val textureId = (call.argument<Number>("textureId") ?: -1).toLong()
        val player = players[textureId]
        if (player == null) {
            result.error(
                "NIUMA_PLAYER_NOT_FOUND",
                "No player for textureId=$textureId",
                null
            )
            return
        }
        try {
            block(player)
            result.success(null)
        } catch (e: Throwable) {
            result.error("NIUMA_PLAYER_ERROR", e.message, null)
        }
    }

    // ---------------------------------------------------------------------
    // Device fingerprint: sha1("MANUFACTURER|MODEL|SDK_INT") hex encoded.
    // ---------------------------------------------------------------------

    private fun deviceFingerprint(): String {
        val raw = "${Build.MANUFACTURER}|${Build.MODEL}|${Build.VERSION.SDK_INT}"
        val digest = MessageDigest.getInstance("SHA-1").digest(raw.toByteArray(Charsets.UTF_8))
        val sb = StringBuilder(digest.size * 2)
        for (b in digest) {
            val v = b.toInt() and 0xFF
            if (v < 0x10) sb.append('0')
            sb.append(Integer.toHexString(v))
        }
        return sb.toString()
    }
}
