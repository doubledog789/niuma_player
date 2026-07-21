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
 * Player-agnostic scaffolding for one player instance: phase machine, pending
 * command convergence, loop handling, heartbeat, per-instance method/event
 * channels. Subclass must construct its native player, then call [bringUp].
 */
internal abstract class PlayerSession(
    textureRegistry: TextureRegistry?,
    messenger: BinaryMessenger,
    protected val context: Context,
    private val dataSource: Map<String, Any?>,
    private val platformViewInstanceId: Long? = null,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    /// Texture mode: entry non-null, surface wired synchronously in init.
    /// PlatformView mode: entry null, surface arrives later via [pushSurface];
    /// channels keyed by `platformViewInstanceId`.
    protected val entry: TextureRegistry.SurfaceTextureEntry? =
        textureRegistry?.createSurfaceTexture()

    private val instanceId: Long = entry?.id() ?: platformViewInstanceId
        ?: throw IllegalArgumentException(
            "PlayerSession needs either a TextureRegistry (texture mode) " +
            "or a platformViewInstanceId (platform-view mode)"
        )

    /// Texture mode: wired eagerly. Platform-view mode: set later by
    /// [pushSurface] — prepare does NOT wait for a surface (see [bringUp]).
    @Volatile
    private var _surface: Surface? = entry?.surfaceTexture()?.let { Surface(it) }

    private val methodChannel: MethodChannel =
        MethodChannel(messenger, "cn.niuma/player/$instanceId")
    private val eventChannel: EventChannel =
        EventChannel(messenger, "cn.niuma/player/events/$instanceId")

    protected val mainHandler = Handler(Looper.getMainLooper())

    @Volatile
    private var eventSink: EventChannel.EventSink? = null

    @Volatile
    var released: Boolean = false
        protected set

    /// Mirrors Dart-side `setLooping`; loop is done manually in
    /// [notifyCompletion] because native looping flags are unreliable across
    /// decoders (notably IJK).
    @Volatile
    protected var loopingEnabled: Boolean = false

    /// User's latest play/pause intent — drives BUFFERING_END's resume target
    /// and whether [notifyPrepared] auto-starts.
    @Volatile
    protected var userWantsPlay: Boolean = false

    /// Heartbeat mute deadline (ms) — hides the window where currentPosition
    /// still reads as duration right after the manual-loop seekTo(0).
    @Volatile
    private var suppressHeartbeatUntilMs: Long = 0L

    // ── Pending target state ─────────────────────────────────────────────
    // Commands arriving before ready record their target here instead of
    // failing; [notifyPrepared] drains them.
    @Volatile
    private var pendingSeekMs: Long? = null
    @Volatile
    private var pendingSpeed: Float? = null
    @Volatile
    private var pendingVolume: Float? = null

    /// Set on first rendered frame; [notifyError] uses it to disambiguate
    /// transient vs network on ambiguous errors.
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
                        // Subclass hook (e.g. ExoPlayer bufferedPosition sampling).
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

    /// Per-heartbeat subclass hook; updates are coalesced into the heartbeat's
    /// single emitState.
    protected open fun onHeartbeatTick() {}

    /// Update bufferedMs WITHOUT emitting — the heartbeat's emitState picks it up.
    protected fun setBufferedMsSilently(ms: Long) {
        bufferedMs = ms.coerceAtLeast(0L)
    }

    /// Texture mode: the Flutter texture id. Platform-view mode: session
    /// identity for [PlayerSurfaceViewFactory]. Keys the plugin's players map.
    val textureId: Long get() = instanceId

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
    }

    /// Subclass calls this from `init` after constructing the native player:
    /// configure → listeners → (surface if available) → data source → prepare.
    /// Prepare does NOT wait for a surface — platform-view surfaces only exist
    /// after composition, gating on them would deadlock; [pushSurface] late-binds.
    protected fun bringUp() {
        configurePlayerOptions()
        attachUnderlyingListeners()
        _surface?.let { bindUnderlyingSurface(it) }
        applyUnderlyingDataSource(dataSource)
        phase = PHASE_OPENING
        startUnderlyingPrepare()
        emitState()
    }

    // ── Platform-view surface stack ──────────────────────────────────────
    // A session can briefly have multiple PlayerSurfaceViews (fullscreen route
    // keeps the inline one mounted). Latest pushed surface owns the binding;
    // on destroy fall back to the previous still-alive one — otherwise the
    // player keeps rendering into a dead Surface and MediaCodec errors out.
    private val surfaceStack = mutableListOf<Pair<Any, Surface>>()

    /// Called by [PlayerSurfaceView] from `surfaceCreated`：把（可能迟到的）
    /// 画面输出口绑上去，后到的 push 重绑到最新 surface；mid-flight setSurface 幂等。
    fun pushSurface(owner: Any, surface: Surface) {
        if (released) return
        surfaceStack.removeAll { it.first === owner }
        surfaceStack.add(owner to surface)
        _surface = surface
        try { bindUnderlyingSurface(surface) } catch (_: Throwable) {}
    }

    /// Called by [PlayerSurfaceView] from `surfaceDestroyed` / `dispose`: if the
    /// destroyed surface owned the binding, fall back to the most recent
    /// still-alive surface, else detach entirely (no rendering into a dead Surface).
    fun popSurface(owner: Any) {
        if (released) return
        val wasActive = surfaceStack.lastOrNull()?.first === owner
        surfaceStack.removeAll { it.first === owner }
        if (!wasActive) return
        val prev = surfaceStack.lastOrNull()?.second
        _surface = prev
        try {
            if (prev != null) {
                bindUnderlyingSurface(prev)
            } else {
                clearUnderlyingSurface()
            }
        } catch (_: Throwable) {}
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

    /// Detach the output surface（platform-view 模式所有 SurfaceView 都没了时调，
    /// 防止渲染到 dead Surface）。默认 no-op，子类按各自 API 实现。
    protected open fun clearUnderlyingSurface() {}

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

        // Drain pending targets, order seek → speed → volume → start, so the
        // first visible frame already has the right position/speed/volume.
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
        // Only meaningful while playing — a pause during buffer shouldn't
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
            // Defer restart to the next main-loop tick — synchronous seek/start
            // inside the completion callback can no-op on a half-transitioned
            // native state machine (notably IJK).
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

    /// Subclass calls this on terminal error, translating its native codes into
    /// a [PlayerErrorCategory] name (`transient` / `codecUnsupported` /
    /// `network` / `terminal` / `unknown`).
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
        // Deliberately NOT forwarded to native looping flags — inconsistent
        // across decoders; manual loop in [notifyCompletion] is uniform.
    }

    fun release() {
        if (released) return
        released = true
        stopHeartbeat()
        try { underlyingRelease() } catch (_: Throwable) {}
        // Texture mode: we own the Surface — release it. Platform-view mode:
        // the SurfaceHolder owns it; releasing would crash the host SurfaceView.
        if (entry != null) _surface?.release()
        _surface = null
        entry?.release()
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
        // Replay current snapshot so a fresh subscriber gets state immediately.
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
