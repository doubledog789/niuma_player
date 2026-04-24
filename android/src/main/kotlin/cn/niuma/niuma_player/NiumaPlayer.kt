package cn.niuma.niuma_player

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.view.Surface
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import tv.danmaku.ijk.media.player.IMediaPlayer
import tv.danmaku.ijk.media.player.IjkMediaPlayer

/**
 * Represents a single IJK-backed player instance bound to a Flutter texture.
 *
 * Each instance owns:
 *  - a [TextureRegistry.SurfaceTextureEntry] for the Flutter texture id
 *  - a [Surface] handed to [IjkMediaPlayer]
 *  - a per-instance [MethodChannel] at `cn.niuma/player/<textureId>`
 *  - a per-instance [EventChannel] at `cn.niuma/player/events/<textureId>`
 */
internal class NiumaPlayer(
    private val textureRegistry: TextureRegistry,
    private val messenger: BinaryMessenger,
    private val context: Context,
    dataSource: Map<String, Any?>
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val entry: TextureRegistry.SurfaceTextureEntry = textureRegistry.createSurfaceTexture()
    private val surface: Surface = Surface(entry.surfaceTexture())
    private val player: IjkMediaPlayer = IjkMediaPlayer()

    private val methodChannel: MethodChannel =
        MethodChannel(messenger, "cn.niuma/player/${entry.id()}")
    private val eventChannel: EventChannel =
        EventChannel(messenger, "cn.niuma/player/events/${entry.id()}")

    private val mainHandler = Handler(Looper.getMainLooper())
    private val heartbeatRunnable: Runnable = object : Runnable {
        override fun run() {
            if (!released && prepared) {
                try {
                    val sink = eventSink
                    if (sink != null) {
                        val pos = player.currentPosition
                        sink.success(
                            mapOf(
                                "event" to "positionChanged",
                                "positionMs" to pos
                            )
                        )
                    }
                } catch (_: Throwable) {
                    // swallow — player may be transitioning / released
                }
                mainHandler.postDelayed(this, HEARTBEAT_INTERVAL_MS)
            }
        }
    }

    @Volatile
    private var eventSink: EventChannel.EventSink? = null

    @Volatile
    private var prepared: Boolean = false

    @Volatile
    private var released: Boolean = false

    val textureId: Long get() = entry.id()

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)

        configureOptions()
        attachListeners()
        player.setSurface(surface)
        applyDataSource(dataSource)
        player.prepareAsync()
    }

    // ---------------------------------------------------------------------
    // Configuration
    // ---------------------------------------------------------------------

    private fun configureOptions() {
        player.setOption(
            IjkMediaPlayer.OPT_CATEGORY_PLAYER, "mediacodec", 1
        )
        player.setOption(
            IjkMediaPlayer.OPT_CATEGORY_PLAYER, "mediacodec-auto-rotate", 1
        )
        player.setOption(
            IjkMediaPlayer.OPT_CATEGORY_PLAYER, "mediacodec-handle-resolution-change", 1
        )
        player.setOption(
            IjkMediaPlayer.OPT_CATEGORY_PLAYER, "start-on-prepared", 0
        )
        player.setOption(
            IjkMediaPlayer.OPT_CATEGORY_FORMAT,
            "protocol_whitelist",
            "async,cache,crypto,file,http,https,ijkhttphook,ijkinject,ijklivehook,ijklongurl,ijksegment,ijktcphook,pipe,rtp,tcp,tls,udp,ijkurlhook,data"
        )
    }

    private fun attachListeners() {
        player.setOnPreparedListener { mp ->
            prepared = true
            emit(
                mapOf(
                    "event" to "initialized",
                    "durationMs" to mp.duration,
                    "width" to mp.videoWidth,
                    "height" to mp.videoHeight
                )
            )
            startHeartbeat()
        }

        player.setOnCompletionListener {
            emit(mapOf("event" to "playingChanged", "isPlaying" to false))
            emit(mapOf("event" to "completed"))
        }

        player.setOnErrorListener { _, what, extra ->
            emit(
                mapOf(
                    "event" to "error",
                    "code" to what.toString(),
                    "message" to "IjkMediaPlayer error what=$what extra=$extra"
                )
            )
            true
        }

        player.setOnInfoListener { _, what, _ ->
            when (what) {
                IMediaPlayer.MEDIA_INFO_BUFFERING_START ->
                    emit(mapOf("event" to "bufferingStart"))
                IMediaPlayer.MEDIA_INFO_BUFFERING_END ->
                    emit(mapOf("event" to "bufferingEnd"))
                IMediaPlayer.MEDIA_INFO_VIDEO_RENDERING_START ->
                    // Authoritative "now actually rendering" signal — confirms
                    // the optimistic playingChanged emitted in play().
                    emit(mapOf("event" to "playingChanged", "isPlaying" to true))
            }
            true
        }

        player.setOnBufferingUpdateListener { _, _ ->
            // no-op: we emit bufferingStart/End via the info listener.
            // Reserved for future percent reporting if needed.
        }

        player.setOnVideoSizeChangedListener { _, width, height, _, _ ->
            emit(
                mapOf(
                    "event" to "videoSizeChanged",
                    "width" to width,
                    "height" to height
                )
            )
        }
    }

    private fun applyDataSource(dataSource: Map<String, Any?>) {
        val uri = dataSource["uri"] as? String
            ?: throw IllegalArgumentException("dataSource.uri is required")
        val type = dataSource["type"] as? String ?: "network"
        @Suppress("UNCHECKED_CAST")
        val headers = dataSource["headers"] as? Map<String, String>

        when (type) {
            "network" -> {
                if (headers != null && headers.isNotEmpty()) {
                    player.setDataSource(context, Uri.parse(uri), headers)
                } else {
                    player.setDataSource(uri)
                }
            }
            "file" -> {
                player.setDataSource(uri)
            }
            "asset" -> {
                // Asset playback via IJK requires the full filesystem path resolved
                // by Flutter's asset manager on the Dart side. We expect the caller
                // to have already resolved it to an absolute file path, but also
                // accept raw asset URIs as a best-effort.
                player.setDataSource(context, Uri.parse(uri))
            }
            else -> {
                throw IllegalArgumentException("Unknown dataSource.type: $type")
            }
        }
    }

    // ---------------------------------------------------------------------
    // Commands
    // ---------------------------------------------------------------------

    fun play() {
        if (!released) {
            player.start()
            // IJK's `setOnStartListener` doesn't exist. Emit optimistically so
            // Dart-side state flips to playing immediately after the user
            // presses play. Actual rendering start is confirmed asynchronously
            // via MEDIA_INFO_VIDEO_RENDERING_START below.
            emit(mapOf("event" to "playingChanged", "isPlaying" to true))
        }
    }

    fun pause() {
        if (!released) {
            player.pause()
            emit(mapOf("event" to "playingChanged", "isPlaying" to false))
        }
    }

    fun seekTo(positionMs: Long) {
        if (!released) player.seekTo(positionMs)
    }

    fun setSpeed(speed: Float) {
        if (!released) player.setSpeed(speed)
    }

    fun setVolume(volume: Float) {
        if (!released) {
            val v = volume.coerceIn(0.0f, 1.0f)
            player.setVolume(v, v)
        }
    }

    fun setLooping(looping: Boolean) {
        if (!released) player.isLooping = looping
    }

    fun release() {
        if (released) return
        released = true
        stopHeartbeat()
        try {
            player.stop()
        } catch (_: Throwable) {
        }
        try {
            player.release()
        } catch (_: Throwable) {
        }
        surface.release()
        entry.release()
        eventChannel.setStreamHandler(null)
        methodChannel.setMethodCallHandler(null)
        eventSink = null
    }

    // ---------------------------------------------------------------------
    // MethodChannel (per-instance)
    // ---------------------------------------------------------------------

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "play" -> {
                    play()
                    result.success(null)
                }
                "pause" -> {
                    pause()
                    result.success(null)
                }
                "seekTo" -> {
                    val positionMs = (call.argument<Number>("positionMs") ?: 0).toLong()
                    seekTo(positionMs)
                    result.success(null)
                }
                "setSpeed" -> {
                    val speed = (call.argument<Number>("speed") ?: 1.0).toFloat()
                    setSpeed(speed)
                    result.success(null)
                }
                "setVolume" -> {
                    val volume = (call.argument<Number>("volume") ?: 1.0).toFloat()
                    setVolume(volume)
                    result.success(null)
                }
                "setLooping" -> {
                    val looping = call.argument<Boolean>("looping") ?: false
                    setLooping(looping)
                    result.success(null)
                }
                "dispose" -> {
                    release()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (e: Throwable) {
            result.error("NIUMA_PLAYER_ERROR", e.message, null)
        }
    }

    // ---------------------------------------------------------------------
    // EventChannel
    // ---------------------------------------------------------------------

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        eventSink = MainThreadEventSink(events)
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    private fun emit(payload: Map<String, Any?>) {
        eventSink?.success(payload)
    }

    // ---------------------------------------------------------------------
    // Heartbeat
    // ---------------------------------------------------------------------

    private fun startHeartbeat() {
        mainHandler.removeCallbacks(heartbeatRunnable)
        mainHandler.postDelayed(heartbeatRunnable, HEARTBEAT_INTERVAL_MS)
    }

    private fun stopHeartbeat() {
        mainHandler.removeCallbacks(heartbeatRunnable)
    }

    companion object {
        private const val HEARTBEAT_INTERVAL_MS: Long = 250
    }
}
