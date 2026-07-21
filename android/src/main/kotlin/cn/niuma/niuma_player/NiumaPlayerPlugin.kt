package cn.niuma.niuma_player

import android.app.Activity
import android.app.ActivityManager
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

    /// Monotonic id allocator for platform-view mode sessions (texture mode
    /// borrows id from SurfaceTextureEntry).
    private val platformViewInstanceCounter = java.util.concurrent.atomic.AtomicLong(1)

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

        // PlatformView factory（useAndroidPlatformView = true 时用）：按
        // creationParams 的 instanceId 查已创建的 PlayerSession。
        flutterPluginBinding.platformViewRegistry.registerViewFactory(
            "cn.niuma/player_surface",
            PlayerSurfaceViewFactory { id -> players[id] },
        )
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
            "setKeepScreenOn" -> {
                handleSetKeepScreenOn(call, result)
                return
            }
            "supportsHevcDecoder" -> {
                result.success(hasHardwareHevcDecoder())
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

        // Preserved from scaffold so the existing unit test keeps passing.
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
            "getProcessHeapLimitMb" -> {
                // ActivityManager.memoryClass = 本进程标准堆上限（MB），
                // 即使大 RAM 设备也被系统 cap。NiumaPlayerPool 按它定容量。
                val am = applicationContext
                    ?.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
                result.success(am?.memoryClass ?: 256)
            }
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
            // 非 PiP 状态调也合法——只是设"下次进 PiP 的 params"。
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
        // 只检 SDK 级别——hasSystemFeature 在部分 OEM 系统误报 false 但实际
        // 能跑 PiP；真失败留给运行时 enterPictureInPictureMode 处理。
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
        // 同 requestCode + FLAG_UPDATE_CURRENT 复用同一 PendingIntent 槽位，
        // 确保图标 update 真正生效。
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
            val useAndroidPlatformView =
                call.argument<Boolean>("useAndroidPlatformView") ?: false

            val dataSource = mapOf<String, Any?>(
                "uri" to uri,
                "type" to type,
                "headers" to headers
            )

            val fingerprint = deviceFingerprint()
            // 设备记忆（Try-Fail-Remember）已移除：内核仅由 forceIjk 决定，
            // Exo→IJK 兜底在 Dart 层单次完成、不落盘。
            val useIjk = forceIjk

            // Platform-view mode: null registry + allocated instanceId；
            // surface 由 PlayerSurfaceView 在 surfaceCreated 时补绑。
            val pvInstanceId: Long? = if (useAndroidPlatformView)
                platformViewInstanceCounter.getAndIncrement() else null
            val sessionRegistry = if (useAndroidPlatformView) null else registry

            val player: PlayerSession = if (useIjk) {
                IjkSession(sessionRegistry, msg, ctx, dataSource, pvInstanceId)
            } else {
                ExoPlayerSession(sessionRegistry, msg, ctx, dataSource, pvInstanceId)
            }
            players[player.textureId] = player

            result.success(
                mapOf(
                    "textureId" to player.textureId,
                    "fingerprint" to fingerprint,
                    "selectedVariant" to (if (useIjk) "ijk" else "exo"),
                    "fromMemory" to false,
                    "isPlatformView" to useAndroidPlatformView,
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

    /// 是否存在 video/hevc 的硬件解码器（纯软解不算——能力检测只认硬解）。
    /// API 29+ 用 isSoftwareOnly，低版本按解码器名前缀识别 Google 软解。
    private fun hasHardwareHevcDecoder(): Boolean {
        return try {
            android.media.MediaCodecList(android.media.MediaCodecList.ALL_CODECS)
                .codecInfos.any { info ->
                    !info.isEncoder &&
                        info.supportedTypes.any {
                            it.equals("video/hevc", ignoreCase = true)
                        } &&
                        if (android.os.Build.VERSION.SDK_INT >= 29) {
                            !info.isSoftwareOnly
                        } else {
                            !info.name.startsWith("OMX.google.") &&
                                !info.name.startsWith("c2.android.")
                        }
                }
        } catch (_: Throwable) {
            false
        }
    }

    /// 播放中保持屏幕常亮（FLAG_KEEP_SCREEN_ON）。窗口级 flag，无需权限；
    /// app 退后台时系统自动忽略，不会真正阻止熄屏待机。
    private fun handleSetKeepScreenOn(call: MethodCall, result: Result) {
        val activity = activityBinding?.activity
        if (activity == null) {
            result.success(false)
            return
        }
        val on = call.argument<Boolean>("on") ?: false
        if (on) {
            activity.window.addFlags(
                android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
            )
        } else {
            activity.window.clearFlags(
                android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
            )
        }
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
