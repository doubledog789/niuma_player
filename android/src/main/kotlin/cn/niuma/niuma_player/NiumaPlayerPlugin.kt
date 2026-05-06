package cn.niuma.niuma_player

import android.app.Activity
import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.drawable.Icon
import android.media.AudioManager
import android.os.Build
import android.util.Log
import android.util.Rational
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.view.TextureRegistry
import java.security.MessageDigest

import cn.niuma.niuma_player.dlna.NiumaDlnaPlugin

/** NiumaPlayerPlugin */
class NiumaPlayerPlugin : FlutterPlugin, MethodCallHandler, ActivityAware {

    private lateinit var channel: MethodChannel
    private lateinit var systemChannel: MethodChannel
    private lateinit var pipChannel: MethodChannel
    private lateinit var pipEventChannel: EventChannel
    private var pipReceiver: PipBroadcastReceiver? = null

    private var messenger: BinaryMessenger? = null
    private var textureRegistry: TextureRegistry? = null
    private var applicationContext: Context? = null
    private var activityBinding: ActivityPluginBinding? = null

    private val players: MutableMap<Long, PlayerSession> = mutableMapOf()

    private var deviceMemory: DeviceMemoryStore? = null

    /// 投屏 DLNA 子 plugin（multicast lock 用）。SDK 自带不需要 host app
    /// 单独注册——onAttachedToEngine 时一起 attach。
    private val dlnaPlugin: NiumaDlnaPlugin = NiumaDlnaPlugin()

    companion object {
        const val ACTION_PIP_PLAY_PAUSE = "cn.niuma.niuma_player.ACTION_PIP_PLAY_PAUSE"
        const val PIP_EVENT_CHANNEL = "niuma_player/pip/events"
        const val PIP_METHOD_CHANNEL = "niuma_player/pip"
        const val TAG = "NiumaPlayerPlugin"

        /// EventSink 静态字段——PipBroadcastReceiver 静态访问，
        /// host Activity 的 onPictureInPictureModeChanged 也通过这个推。
        @JvmStatic
        var pipEventSink: EventChannel.EventSink? = null
            private set

        /// 提供给 host MainActivity 的 onPictureInPictureModeChanged 重写调用。
        @JvmStatic
        fun reportPipModeChanged(isInPictureInPictureMode: Boolean) {
            pipEventSink?.success(
                mapOf("event" to if (isInPictureInPictureMode) "pipStarted" else "pipStopped")
            )
        }
    }

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        messenger = flutterPluginBinding.binaryMessenger
        textureRegistry = flutterPluginBinding.textureRegistry
        applicationContext = flutterPluginBinding.applicationContext
        deviceMemory = DeviceMemoryStore(flutterPluginBinding.applicationContext)

        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "cn.niuma/player")
        channel.setMethodCallHandler(this)

        systemChannel = MethodChannel(flutterPluginBinding.binaryMessenger, "niuma_player/system")
        systemChannel.setMethodCallHandler(this)

        pipChannel = MethodChannel(flutterPluginBinding.binaryMessenger, PIP_METHOD_CHANNEL)
        pipChannel.setMethodCallHandler(this)

        pipEventChannel = EventChannel(flutterPluginBinding.binaryMessenger, PIP_EVENT_CHANNEL)
        pipEventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(args: Any?, sink: EventChannel.EventSink) {
                pipEventSink = sink
            }
            override fun onCancel(args: Any?) {
                pipEventSink = null
            }
        })

        // 投屏 DLNA 子 plugin attach——SDK 内置无需 host app 单独注册。
        dlnaPlugin.onAttachedToEngine(flutterPluginBinding)
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
            "enterPictureInPicture" -> {
                handleEnterPip(call, result)
                return
            }
            "exitPictureInPicture" -> {
                handleExitPip(result)
                return
            }
            "queryPictureInPictureSupport" -> {
                handleQueryPipSupport(result)
                return
            }
            "updatePictureInPictureActions" -> {
                handleUpdatePipActions(call, result)
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
        if (::pipChannel.isInitialized) {
            pipChannel.setMethodCallHandler(null)
        }
        if (::pipEventChannel.isInitialized) {
            pipEventChannel.setStreamHandler(null)
        }
        pipEventSink = null

        // 投屏 DLNA 子 plugin detach——释放 multicast lock 等资源。
        dlnaPlugin.onDetachedFromEngine(binding)

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
    // PiP Handlers
    // ---------------------------------------------------------------------

    private fun handleEnterPip(call: MethodCall, result: Result) {
        val activity = activityBinding?.activity
        if (activity == null) {
            result.success(false)
            return
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            result.success(false)
            return
        }
        val aspectNum = (call.argument<Int>("aspectNum") ?: 16).coerceAtLeast(1)
        val aspectDen = (call.argument<Int>("aspectDen") ?: 9).coerceAtLeast(1)

        // 进 PiP 时 isPlaying 默认 true（用户通常在播放中点 PiP 按钮）——
        // Dart 侧紧接着会调 updatePictureInPictureActions 把真实状态推过来。
        val playPauseAction = createPlayPauseRemoteAction(activity, isPlaying = true)
        val params = PictureInPictureParams.Builder()
            .setAspectRatio(Rational(aspectNum, aspectDen))
            .setActions(listOf(playPauseAction))
            .build()

        val ok = try {
            activity.enterPictureInPictureMode(params)
        } catch (e: Throwable) {
            Log.e(TAG, "enterPictureInPictureMode failed", e)
            false
        }
        result.success(ok)
    }

    /// 重新设置 PiP RemoteAction 图标——`isPlaying=true` → pause 图标，
    /// 反之 play 图标。Activity 已 detach / 非 PiP 状态下静默 no-op。
    private fun handleUpdatePipActions(call: MethodCall, result: Result) {
        val activity = activityBinding?.activity
        if (activity == null || Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            result.success(null)
            return
        }
        val isPlaying = call.argument<Boolean>("isPlaying") ?: true
        try {
            val action = createPlayPauseRemoteAction(activity, isPlaying = isPlaying)
            val params = PictureInPictureParams.Builder()
                .setActions(listOf(action))
                .build()
            // setPictureInPictureParams 在非 PiP 状态调也是合法的——只是
            // 把"下次进 PiP 用的 params"设了，不会副作用。
            activity.setPictureInPictureParams(params)
        } catch (e: Throwable) {
            Log.w(TAG, "updatePictureInPictureActions failed", e)
        }
        result.success(null)
    }

    private fun handleExitPip(result: Result) {
        // Android 系统 PiP 没有"主动退出"API——用户拖回主 app 即退出。
        // 保留接口仅对称性。
        result.success(false)
    }

    private fun handleQueryPipSupport(result: Result) {
        val activity = activityBinding?.activity
        if (activity == null) {
            Log.w(TAG, "handleQueryPipSupport: activityBinding null → false")
            result.success(false)
            return
        }
        // 只检 SDK 级别——manifest 已声明 supportsPictureInPicture="true"，
        // PackageManager.hasSystemFeature 在部分 MIUI / OEM 系统返 false 但
        // 实际能跑 PiP（系统也尊重 manifest 声明）。先信 SDK，运行时 enterPictureInPictureMode
        // 真失败再处理。
        val sdkOk = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
        val hasFeature = activity.packageManager
            .hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
        Log.d(TAG, "handleQueryPipSupport: sdkOk=$sdkOk hasFeature=$hasFeature")
        result.success(sdkOk)
    }

    private fun createPlayPauseRemoteAction(
        ctx: Context,
        isPlaying: Boolean,
    ): RemoteAction {
        val intent = Intent(ACTION_PIP_PLAY_PAUSE)
            .setPackage(ctx.packageName)
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_IMMUTABLE
        } else {
            0
        }
        // 同 requestCode + FLAG_UPDATE_CURRENT 让多次 createPlayPauseRemoteAction
        // 共享同一个 PendingIntent 槽位；setPictureInPictureParams 会按内容
        // diff 决定是否换图标——确保 update 调用真正生效。
        val pi = PendingIntent.getBroadcast(
            ctx,
            0,
            intent,
            flags or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val iconRes = if (isPlaying) {
            android.R.drawable.ic_media_pause
        } else {
            android.R.drawable.ic_media_play
        }
        val label = if (isPlaying) "Pause" else "Play"
        return RemoteAction(
            Icon.createWithResource(ctx, iconRes),
            label,
            label,
            pi,
        )
    }

    // ---------------------------------------------------------------------
    // ActivityAware
    // ---------------------------------------------------------------------

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        registerPipReceiver(binding.activity)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        unregisterPipReceiver()
        activityBinding = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activityBinding = binding
        registerPipReceiver(binding.activity)
    }

    override fun onDetachedFromActivity() {
        unregisterPipReceiver()
        activityBinding = null
    }

    private fun registerPipReceiver(activity: Activity) {
        if (pipReceiver != null) return
        val receiver = PipBroadcastReceiver()
        val filter = IntentFilter(ACTION_PIP_PLAY_PAUSE)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            activity.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            activity.registerReceiver(receiver, filter)
        }
        pipReceiver = receiver
    }

    private fun unregisterPipReceiver() {
        val receiver = pipReceiver ?: return
        val activity = activityBinding?.activity ?: return
        try {
            activity.unregisterReceiver(receiver)
        } catch (_: Throwable) {
            // ignore
        }
        pipReceiver = null
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

}
