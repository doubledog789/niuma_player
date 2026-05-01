package cn.niuma.niuma_player

import android.app.Activity
import android.content.Context
import android.media.AudioManager
import android.os.Build
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.view.TextureRegistry
import java.security.MessageDigest

/** NiumaPlayerPlugin */
class NiumaPlayerPlugin : FlutterPlugin, MethodCallHandler, ActivityAware {

    private lateinit var channel: MethodChannel
    private lateinit var systemChannel: MethodChannel
    private var messenger: BinaryMessenger? = null
    private var textureRegistry: TextureRegistry? = null
    private var applicationContext: Context? = null
    private var activityBinding: ActivityPluginBinding? = null

    private val players: MutableMap<Long, PlayerSession> = mutableMapOf()

    private var deviceMemory: DeviceMemoryStore? = null

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        messenger = flutterPluginBinding.binaryMessenger
        textureRegistry = flutterPluginBinding.textureRegistry
        applicationContext = flutterPluginBinding.applicationContext
        deviceMemory = DeviceMemoryStore(flutterPluginBinding.applicationContext)

        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "cn.niuma/player")
        channel.setMethodCallHandler(this)

        systemChannel = MethodChannel(flutterPluginBinding.binaryMessenger, "niuma_player/system")
        systemChannel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        // System channel methods (brightness + volume)
        when (call.method) {
            "getBrightness" -> {
                handleGetBrightness(result)
                return
            }
            "setBrightness" -> {
                handleSetBrightness(call, result)
                return
            }
            "getSystemVolume" -> {
                handleGetSystemVolume(result)
                return
            }
            "setSystemVolume" -> {
                handleSetSystemVolume(call, result)
                return
            }
        }

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
            "deviceMemory.get" -> handleDeviceMemoryGet(call, result)
            "deviceMemory.set" -> handleDeviceMemorySet(call, result)
            "deviceMemory.unset" -> handleDeviceMemoryUnset(call, result)
            "deviceMemory.clear" -> handleDeviceMemoryClear(result)
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
        if (::systemChannel.isInitialized) {
            systemChannel.setMethodCallHandler(null)
        }
        messenger = null
        textureRegistry = null
        applicationContext = null
        deviceMemory = null
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
            val forceIjk = call.argument<Boolean>("forceIjk") ?: false

            val dataSource = mapOf<String, Any?>(
                "uri" to uri,
                "type" to type,
                "headers" to headers
            )

            val fingerprint = deviceFingerprint()
            val memoryHit = !forceIjk && isMarkedForIjk(fingerprint)
            val useIjk = forceIjk || memoryHit

            val player: PlayerSession = if (useIjk) {
                IjkSession(registry, msg, ctx, dataSource)
            } else {
                // ExoPlayer is our default fast path. If a codec failure
                // surfaces *before the first frame*, that almost always
                // means this device can't decode this codec via system
                // MediaCodec — record that fact so the next attempt picks
                // IJK directly. The Dart-side controller will retry
                // immediately on init failure; native marking the memory
                // here means that retry hits the IJK branch.
                ExoPlayerSession(
                    registry, msg, ctx, dataSource,
                    onCodecFailureBeforeFirstFrame = {
                        deviceMemory?.set(fingerprint, DeviceMemoryStore.NO_EXPIRY)
                    },
                )
            }
            players[player.textureId] = player

            result.success(
                mapOf(
                    "textureId" to player.textureId,
                    "fingerprint" to fingerprint,
                    "selectedVariant" to (if (useIjk) "ijk" else "exo"),
                    "fromMemory" to memoryHit,
                )
            )
        } catch (e: Throwable) {
            result.error("NIUMA_PLAYER_CREATE_FAILED", e.message, null)
        }
    }

    /// Read the DeviceMemoryStore and return whether the given fingerprint
    /// is currently marked as needing IJK. Treats expired entries as "not
    /// marked" and eagerly purges them.
    private fun isMarkedForIjk(fingerprint: String): Boolean {
        val store = deviceMemory ?: return false
        val raw = store.get(fingerprint) ?: return false
        if (raw == DeviceMemoryStore.NO_EXPIRY) return true
        if (raw > System.currentTimeMillis()) return true
        // Expired — clean up so the read cost is paid once.
        store.unset(fingerprint)
        return false
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
        block: (PlayerSession) -> Unit
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
    // DeviceMemory MethodChannel handlers
    //
    // The TTL/expiry policy lives on the Dart side; this layer is a dumb
    // key-value store. `expiresAt = null` over the wire maps to the
    // [DeviceMemoryStore.NO_EXPIRY] sentinel internally.
    // ---------------------------------------------------------------------

    private fun handleDeviceMemoryGet(call: MethodCall, result: Result) {
        val store = deviceMemory
        if (store == null) {
            result.error("NIUMA_PLAYER_UNATTACHED", "DeviceMemory not initialised", null)
            return
        }
        val fingerprint = call.argument<String>("fingerprint")
        if (fingerprint == null) {
            result.error("NIUMA_PLAYER_BAD_ARGS", "fingerprint is required", null)
            return
        }
        val raw = store.get(fingerprint)
        if (raw == null) {
            result.success(null)
            return
        }
        // Sentinel → null over the wire.
        val expiresAt: Long? = if (raw == DeviceMemoryStore.NO_EXPIRY) null else raw
        result.success(mapOf("expiresAt" to expiresAt))
    }

    private fun handleDeviceMemorySet(call: MethodCall, result: Result) {
        val store = deviceMemory
        if (store == null) {
            result.error("NIUMA_PLAYER_UNATTACHED", "DeviceMemory not initialised", null)
            return
        }
        val fingerprint = call.argument<String>("fingerprint")
        if (fingerprint == null) {
            result.error("NIUMA_PLAYER_BAD_ARGS", "fingerprint is required", null)
            return
        }
        val expiresAt = (call.argument<Number>("expiresAt"))?.toLong()
            ?: DeviceMemoryStore.NO_EXPIRY
        store.set(fingerprint, expiresAt)
        result.success(null)
    }

    private fun handleDeviceMemoryUnset(call: MethodCall, result: Result) {
        val store = deviceMemory
        if (store == null) {
            result.error("NIUMA_PLAYER_UNATTACHED", "DeviceMemory not initialised", null)
            return
        }
        val fingerprint = call.argument<String>("fingerprint")
        if (fingerprint == null) {
            result.error("NIUMA_PLAYER_BAD_ARGS", "fingerprint is required", null)
            return
        }
        store.unset(fingerprint)
        result.success(null)
    }

    private fun handleDeviceMemoryClear(result: Result) {
        val store = deviceMemory
        if (store == null) {
            result.error("NIUMA_PLAYER_UNATTACHED", "DeviceMemory not initialised", null)
            return
        }
        store.clear()
        result.success(null)
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

    // ---------------------------------------------------------------------
    // System channel handlers: brightness + volume
    // ---------------------------------------------------------------------

    private fun handleGetBrightness(result: Result) {
        val activity = activityBinding?.activity
        if (activity == null) {
            result.success(0.0)
            return
        }
        val lp = activity.window.attributes
        val v = lp.screenBrightness
        // -1 = 跟随系统亮度，无法精确读，返 0.5 占位
        result.success(if (v < 0) 0.5 else v.toDouble())
    }

    private fun handleSetBrightness(call: MethodCall, result: Result) {
        val activity = activityBinding?.activity
        if (activity == null) {
            result.success(false)
            return
        }
        val value = (call.argument<Double>("value") ?: 0.5).coerceIn(0.0, 1.0)
        val lp = activity.window.attributes
        lp.screenBrightness = value.toFloat()
        activity.window.attributes = lp
        result.success(true)
    }

    private fun handleGetSystemVolume(result: Result) {
        val activity = activityBinding?.activity
        if (activity == null) {
            result.success(0.0)
            return
        }
        val am = activity.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val cur = am.getStreamVolume(AudioManager.STREAM_MUSIC)
        val max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        result.success(if (max > 0) cur.toDouble() / max else 0.0)
    }

    private fun handleSetSystemVolume(call: MethodCall, result: Result) {
        val activity = activityBinding?.activity
        if (activity == null) {
            result.success(false)
            return
        }
        val value = (call.argument<Double>("value") ?: 0.5).coerceIn(0.0, 1.0)
        val am = activity.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        val target = (value * max).toInt().coerceIn(0, max)
        am.setStreamVolume(AudioManager.STREAM_MUSIC, target, 0)
        result.success(true)
    }

    // ---------------------------------------------------------------------
    // ActivityAware
    // ---------------------------------------------------------------------

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activityBinding = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activityBinding = binding
    }

    override fun onDetachedFromActivity() {
        activityBinding = null
    }
}
