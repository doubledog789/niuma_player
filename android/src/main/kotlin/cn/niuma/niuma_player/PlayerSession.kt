package cn.niuma.niuma_player

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.view.Surface
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry

/**
 * Common scaffolding for a single player instance bound to a Flutter texture.
 *
 * Owns:
 *  - a [TextureRegistry.SurfaceTextureEntry] for the Flutter texture id
 *  - a [Surface] handed to the underlying player
 *  - a per-instance [MethodChannel] at `cn.niuma/player/<textureId>`
 *  - a per-instance [EventChannel] at `cn.niuma/player/events/<textureId>`
 *
 * What lives here vs in the concrete subclass:
 *  - **Here (player-agnostic):** phase machine, command target convergence
 *    (pending seek/speed/volume), loop handling, optimistic phase emits,
 *    heartbeat polling, EventChannel snapshot serialization, MethodChannel
 *    dispatch.
 *  - **Subclass:** the actual native player instance (IjkMediaPlayer,
 *    ExoPlayer, …), how to wire up its callbacks, how to apply a data
 *    source, and how to translate its native error codes into a
 *    [PlayerErrorCategory] string.
 *
 * Construction protocol: the subclass's primary constructor / `init` block
 * must (1) construct the underlying native player, then (2) call [bringUp].
 * We can't put `bringUp()` in this base class's `init` because abstract
 * methods aren't safe to invoke before the subclass's own initializers run.
 */
internal abstract class PlayerSession(
    textureRegistry: TextureRegistry,
    messenger: BinaryMessenger,
    protected val context: Context,
    private val dataSource: Map<String, Any?>
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    protected val entry: TextureRegistry.SurfaceTextureEntry =
        textureRegistry.createSurfaceTexture()
    protected val surface: Surface = Surface(entry.surfaceTexture())

    private val methodChannel: MethodChannel =
        MethodChannel(messenger, "cn.niuma/player/${entry.id()}")
    private val eventChannel: EventChannel =
        EventChannel(messenger, "cn.niuma/player/events/${entry.id()}")

    protected val mainHandler = Handler(Looper.getMainLooper())

    @Volatile
    private var eventSink: EventChannel.EventSink? = null

    @Volatile
    protected var released: Boolean = false

    /// Mirrors the Dart-side `setLooping` flag. We consult it ourselves
    /// inside [notifyCompletion] instead of forwarding to a native looping
    /// flag because that mechanism is unreliable across decoder paths
    /// (IJK in particular oscillates state at the wrap-around).
    @Volatile
    protected var loopingEnabled: Boolean = false

    /// Tracks the user's most recent play/pause intent. Drives whether
    /// `BUFFERING_END` resumes to playing vs paused, and whether
    /// `notifyPrepared` auto-starts.
    @Volatile
    protected var userWantsPlay: Boolean = false

    /// Wall-clock deadline (ms) during which the heartbeat won't emit. Used
    /// to hide the brief window where the underlying player's currentPosition
    /// still reads as `duration` after we've issued `seekTo(0)` for a manual
    /// loop.
    @Volatile
    private var suppressHeartbeatUntilMs: Long = 0L

    // ── Pending target state. ───────────────────────────────────────────
    // Commands arriving while the native player isn't ready (`phase ==
    // opening`) record their target here instead of failing. [notifyPrepared]
    // drains these so the visible behaviour is "as if the user issued the
    // commands the moment we became ready".
    @Volatile
    private var pendingSeekMs: Long? = null
    @Volatile
    private var pendingSpeed: Float? = null
    @Volatile
    private var pendingVolume: Float? = null

    /// Set the first time a frame reaches the screen. Subclasses bump this
    /// from their first-frame callback. [notifyError] reads it to decide
    /// transient vs network when the underlying error is ambiguous.
    @Volatile
    protected var hadFirstFrame: Boolean = false

    // ── Snapshot fields. Touched only on the main looper. ────────────────
    private var phase: String = PHASE_IDLE
    private var positionMs: Long = 0L
    private var durationMs: Long = 0L
    private var bufferedMs: Long = 0L
    private var width: Int = 0
    private var height: Int = 0
    private var openingStage: String? = null
    private var errorCode: String? = null
    private var errorMessage: String? = null
    private var errorCategory: String? = null

    private val heartbeatRunnable: Runnable = object : Runnable {
        override fun run() {
            if (released) return
            // Only meaningful once the source is open and we have a clock.
            if (phase != PHASE_IDLE && phase != PHASE_OPENING && phase != PHASE_ERROR) {
                if (System.currentTimeMillis() >= suppressHeartbeatUntilMs) {
                    try {
                        positionMs = underlyingCurrentPosition()
                        // Subclass hook for whatever else changes per tick
                        // (e.g. ExoPlayer's bufferedPosition is read here
                        // because it has no callback for "buffer advanced").
                        onHeartbeatTick()
                        emitState()
                    } catch (_: Throwable) {
                        // swallow — player may be transitioning / released
                    }
                }
            }
            mainHandler.postDelayed(this, HEARTBEAT_INTERVAL_MS)
        }
    }

    /// Called once per heartbeat tick (every 250ms while playing/paused/etc).
    /// Subclasses can override to update fields like [setBufferedMsSilently]
    /// without triggering a separate emitState — the heartbeat coalesces all
    /// updates into one snapshot.
    protected open fun onHeartbeatTick() {}

    /// Update the buffered ms snapshot field WITHOUT emitting. Use from
    /// [onHeartbeatTick]; the heartbeat's own emitState picks up the new
    /// value alongside any position update.
    protected fun setBufferedMsSilently(ms: Long) {
        bufferedMs = ms.coerceAtLeast(0L)
    }

    val textureId: Long get() = entry.id()

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
    }

    /// Subclass calls this from its `init {}` block AFTER constructing the
    /// underlying native player and any subclass-specific state. Performs
    /// configure → listeners → surface → data source → prepare.
    protected fun bringUp() {
        configurePlayerOptions()
        attachUnderlyingListeners()
        bindUnderlyingSurface(surface)
        applyUnderlyingDataSource(dataSource)
        phase = PHASE_OPENING
        startUnderlyingPrepare()
    }

    // ── Subclass hooks ────────────────────────────────────────────────────

    /// Apply implementation-specific tuning options on the underlying
    /// player (decoder selection, buffer caps, etc).
    protected abstract fun configurePlayerOptions()

    /// Wire up the underlying player's callbacks, routing them to
    /// `notify*` methods on this base class.
    protected abstract fun attachUnderlyingListeners()

    /// Bind the Flutter [Surface] to the underlying player.
    protected abstract fun bindUnderlyingSurface(surface: Surface)

    /// Set the data source on the underlying player.
    protected abstract fun applyUnderlyingDataSource(dataSource: Map<String, Any?>)

    /// Kick off async prepare on the underlying player.
    protected abstract fun startUnderlyingPrepare()

    /// Imperative command primitives. Wrapped in try/catch by the base.
    protected abstract fun underlyingStart()
    protected abstract fun underlyingPause()
    protected abstract fun underlyingSeekTo(positionMs: Long)
    protected abstract fun underlyingSetSpeed(speed: Float)
    protected abstract fun underlyingSetVolume(volume: Float)
    protected abstract fun underlyingRelease()

    /// Read the underlying player's current playback position, in ms.
    protected abstract fun underlyingCurrentPosition(): Long

    // ── Subclass-callable callbacks ───────────────────────────────────────
    // These translate underlying-player events into phase transitions + a
    // single emitState() call. Subclasses don't touch [phase] directly.

    protected fun notifyPrepared(durationMs: Long, width: Int, height: Int) {
        if (released) return
        this.durationMs = durationMs
        this.width = width
        this.height = height
        openingStage = null

        // Drain pending target state so commands that arrived during opening
        // apply atomically. Order: seek → speed → volume → start, so the
        // first frame the user sees is at the right position with the right
        // speed/volume.
        pendingSeekMs?.let {
            try {
                underlyingSeekTo(it)
                positionMs = it
            } catch (_: Throwable) {}
            pendingSeekMs = null
        }
        pendingSpeed?.let {
            try { underlyingSetSpeed(it) } catch (_: Throwable) {}
            pendingSpeed = null
        }
        pendingVolume?.let {
            try { underlyingSetVolume(it) } catch (_: Throwable) {}
            pendingVolume = null
        }

        if (userWantsPlay) {
            try {
                underlyingStart()
                phase = PHASE_PLAYING
            } catch (_: Throwable) {
                phase = PHASE_READY
            }
        } else {
            phase = PHASE_READY
        }
        emitState()
        startHeartbeat()
    }

    protected fun notifyOpeningStage(stage: String) {
        if (released) return
        if (phase == PHASE_OPENING) {
            openingStage = stage
            emitState()
        }
    }

    protected fun notifyBufferingStart() {
        if (released) return
        // Only meaningful while playing — pausing during buffer shouldn't
        // read as buffering forever.
        if (phase == PHASE_PLAYING) {
            phase = PHASE_BUFFERING
            emitState()
        }
    }

    protected fun notifyBufferingEnd() {
        if (released) return
        if (phase == PHASE_BUFFERING) {
            phase = if (userWantsPlay) PHASE_PLAYING else PHASE_PAUSED
            emitState()
        }
    }

    protected fun notifyVideoRenderingStart() {
        if (released) return
        hadFirstFrame = true
        // Authoritative confirmation that frames are flowing. If user intent
        // is play but phase drifted, snap back.
        if (userWantsPlay && phase != PHASE_PLAYING) {
            phase = PHASE_PLAYING
            emitState()
        }
    }

    protected fun notifyCompletion() {
        if (released) return
        if (loopingEnabled) {
            // Defer the restart to the next main-loop tick. Calling
            // seekTo/start synchronously inside the underlying player's
            // completion callback can leave its native state machine
            // half-transitioned (observed with IJK) — the seek gets queued
            // but start() from a not-yet-settled COMPLETED state can no-op,
            // producing "jump to 0, then snap back to end, no playback".
            suppressHeartbeatUntilMs = System.currentTimeMillis() + 800
            mainHandler.post {
                if (released) return@post
                try {
                    underlyingSeekTo(0L)
                    underlyingStart()
                    positionMs = 0L
                    phase = PHASE_PLAYING
                    emitState()
                } catch (_: Throwable) {
                    suppressHeartbeatUntilMs = 0L
                    positionMs = durationMs
                    phase = PHASE_ENDED
                    emitState()
                }
            }
            return
        }
        positionMs = durationMs
        phase = PHASE_ENDED
        emitState()
    }

    protected fun notifyVideoSize(width: Int, height: Int) {
        if (released) return
        this.width = width
        this.height = height
        emitState()
    }

    protected fun notifyBufferedPercent(percent: Int) {
        if (released) return
        if (durationMs > 0) {
            val p = percent.coerceIn(0, 100)
            bufferedMs = durationMs * p / 100L
            emitState()
        }
    }

    protected fun notifyBufferedMs(bufferedMs: Long) {
        if (released) return
        this.bufferedMs = bufferedMs.coerceAtLeast(0L)
        emitState()
    }

    /// Subclass calls this on terminal error. It is responsible for
    /// translating its native error codes into a [PlayerErrorCategory]
    /// name (`transient` / `codecUnsupported` / `network` / `terminal` /
    /// `unknown`); see also [hadFirstFrame] for context.
    protected fun notifyError(
        category: String,
        code: String?,
        message: String,
        positionMs: Long? = null,
        durationMs: Long? = null
    ) {
        if (released) return
        if (positionMs != null && positionMs >= 0) this.positionMs = positionMs
        if (durationMs != null && durationMs >= 0) this.durationMs = durationMs
        errorCode = code
        errorCategory = category
        errorMessage = message
        phase = PHASE_ERROR
        emitState()
    }

    // ── Public command API ───────────────────────────────────────────────

    private fun isReadyForCommands(): Boolean {
        return phase != PHASE_IDLE &&
            phase != PHASE_OPENING &&
            phase != PHASE_ERROR
    }

    fun play() {
        if (released) return
        userWantsPlay = true
        if (!isReadyForCommands()) {
            // Will be honoured by [notifyPrepared] once prepare lands.
            return
        }
        try {
            underlyingStart()
        } catch (_: Throwable) {
            return
        }
        phase = PHASE_PLAYING
        emitState()
    }

    fun pause() {
        if (released) return
        userWantsPlay = false
        if (!isReadyForCommands()) return
        try {
            underlyingPause()
        } catch (_: Throwable) {
            return
        }
        phase = PHASE_PAUSED
        emitState()
    }

    fun seekTo(positionMs: Long) {
        if (released) return
        if (!isReadyForCommands()) {
            pendingSeekMs = positionMs
            return
        }
        try {
            underlyingSeekTo(positionMs)
        } catch (_: Throwable) {
            return
        }
        this.positionMs = positionMs
        emitState()
    }

    fun setSpeed(speed: Float) {
        if (released) return
        if (!isReadyForCommands()) {
            pendingSpeed = speed
            return
        }
        try { underlyingSetSpeed(speed) } catch (_: Throwable) {}
    }

    fun setVolume(volume: Float) {
        if (released) return
        val v = volume.coerceIn(0.0f, 1.0f)
        if (!isReadyForCommands()) {
            pendingVolume = v
            return
        }
        try { underlyingSetVolume(v) } catch (_: Throwable) {}
    }

    fun setLooping(looping: Boolean) {
        loopingEnabled = looping
        // Deliberately NOT forwarding to the underlying player's native
        // looping flag. Multiple decoders (notably IJK) ship inconsistent
        // implementations; manual loop in [notifyCompletion] is the only
        // way to guarantee the same observable behaviour everywhere.
    }

    fun release() {
        if (released) return
        released = true
        stopHeartbeat()
        try { underlyingRelease() } catch (_: Throwable) {}
        surface.release()
        entry.release()
        eventChannel.setStreamHandler(null)
        methodChannel.setMethodCallHandler(null)
        eventSink = null
    }

    // ── MethodChannel (per-instance) ─────────────────────────────────────

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "play" -> { play(); result.success(null) }
                "pause" -> { pause(); result.success(null) }
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
                "dispose" -> { release(); result.success(null) }
                else -> result.notImplemented()
            }
        } catch (e: Throwable) {
            result.error("NIUMA_PLAYER_ERROR", e.message, null)
        }
    }

    // ── EventChannel ─────────────────────────────────────────────────────

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        eventSink = MainThreadEventSink(events)
        // Replay current snapshot so a freshly-subscribing Dart side doesn't
        // need to special-case "never received an event yet".
        emitState()
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    private fun emitState() {
        val sink = eventSink ?: return
        sink.success(
            mapOf(
                "phase" to phase,
                "positionMs" to positionMs,
                "durationMs" to durationMs,
                "bufferedMs" to bufferedMs,
                "width" to width,
                "height" to height,
                "openingStage" to openingStage,
                "errorCode" to errorCode,
                "errorMessage" to errorMessage,
                "errorCategory" to errorCategory,
            )
        )
    }

    // ── Heartbeat ────────────────────────────────────────────────────────

    private fun startHeartbeat() {
        mainHandler.removeCallbacks(heartbeatRunnable)
        mainHandler.postDelayed(heartbeatRunnable, HEARTBEAT_INTERVAL_MS)
    }

    private fun stopHeartbeat() {
        mainHandler.removeCallbacks(heartbeatRunnable)
    }

    companion object {
        private const val HEARTBEAT_INTERVAL_MS: Long = 250

        // Phase string constants. Mirror PlayerPhase enum on the Dart side.
        const val PHASE_IDLE = "idle"
        const val PHASE_OPENING = "opening"
        const val PHASE_READY = "ready"
        const val PHASE_PLAYING = "playing"
        const val PHASE_PAUSED = "paused"
        const val PHASE_BUFFERING = "buffering"
        const val PHASE_ENDED = "ended"
        const val PHASE_ERROR = "error"
    }
}
