package cn.niuma.niuma_player

import android.content.Context
import android.net.Uri
import android.view.Surface
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.view.TextureRegistry

/**
 * [PlayerSession] driven by `androidx.media3.exoplayer.ExoPlayer`.
 *
 * Hardware-decode fast path. Used as the default Android backend on devices
 * that aren't on the IJK fallback list (which DeviceMemoryStore tracks).
 *
 * NOTE: This file is currently *not* instantiated by [NiumaPlayerPlugin] —
 * the selection state machine still lives on the Dart side and only
 * IjkSession is wired up natively. The full switch happens in M3.3, when
 * native takes over selection from Dart.
 */
internal class ExoPlayerSession(
    textureRegistry: TextureRegistry,
    messenger: BinaryMessenger,
    context: Context,
    dataSource: Map<String, Any?>,
    /// Invoked when [PlaybackException] surfaces with a `codecUnsupported`
    /// category before [hadFirstFrame] is set. The plugin uses this to
    /// persist "this device needs IJK" so the next create call routes to
    /// IjkSession directly without paying the Exo prepare cost again.
    private val onCodecFailureBeforeFirstFrame: () -> Unit = {},
) : PlayerSession(textureRegistry, messenger, context, dataSource) {

    private val player: ExoPlayer = buildPlayer(context, dataSource)

    /// Tracks whether we've already mapped the first STATE_READY into a
    /// `notifyPrepared` call. Subsequent STATE_READY events become
    /// notifyBufferingEnd instead.
    private var hasReportedPrepared = false

    init {
        bringUp()
    }

    private fun buildPlayer(
        context: Context,
        dataSource: Map<String, Any?>
    ): ExoPlayer {
        @Suppress("UNCHECKED_CAST")
        val headers = dataSource["headers"] as? Map<String, String>
        val httpFactory = DefaultHttpDataSource.Factory()
            .setUserAgent("niuma_player/exo")
            .setConnectTimeoutMs(15_000)
            .setReadTimeoutMs(15_000)
            .setAllowCrossProtocolRedirects(true)
        if (headers != null && headers.isNotEmpty()) {
            httpFactory.setDefaultRequestProperties(headers)
        }
        val mediaSourceFactory = DefaultMediaSourceFactory(context)
            .setDataSourceFactory(httpFactory)
        return ExoPlayer.Builder(context)
            .setMediaSourceFactory(mediaSourceFactory)
            .build()
    }

    // ── Configure ────────────────────────────────────────────────────────

    override fun configurePlayerOptions() {
        // Defer playback to our explicit play()/pause() calls; do not
        // auto-start once buffered.
        player.playWhenReady = false
    }

    override fun attachUnderlyingListeners() {
        player.addListener(object : Player.Listener {
            override fun onPlaybackStateChanged(state: Int) {
                when (state) {
                    Player.STATE_BUFFERING -> {
                        // First buffer is part of opening — no-op until
                        // STATE_READY arrives. Subsequent buffers are
                        // mid-playback stalls.
                        if (hasReportedPrepared) {
                            notifyBufferingStart()
                        }
                    }
                    Player.STATE_READY -> {
                        if (!hasReportedPrepared) {
                            hasReportedPrepared = true
                            val size = player.videoSize
                            notifyPrepared(
                                player.duration.coerceAtLeast(0L),
                                size.width,
                                size.height,
                            )
                        } else {
                            notifyBufferingEnd()
                        }
                    }
                    Player.STATE_ENDED -> notifyCompletion()
                    Player.STATE_IDLE -> {
                        // No-op — IDLE is the pre-prepare or post-error state
                        // and we already drive phase from notifyError /
                        // PHASE_OPENING in bringUp().
                    }
                }
            }

            override fun onPlayerError(error: PlaybackException) {
                val pos = try { player.currentPosition } catch (_: Throwable) { -1L }
                val dur = try { player.duration } catch (_: Throwable) { -1L }
                val category = categorizeExoError(error.errorCode)
                // Codec failures BEFORE we ever rendered a frame strongly
                // suggest the device's MediaCodec can't handle this stream.
                // Mark memory now so the Dart-side retry routes to IJK.
                if (!hadFirstFrame && category == "codecUnsupported") {
                    try { onCodecFailureBeforeFirstFrame() } catch (_: Throwable) {}
                }
                notifyError(
                    category = category,
                    code = error.errorCode.toString(),
                    message = "ExoPlayer ${error.errorCodeName}: " +
                        "${error.message ?: "(no message)"} " +
                        "pos=${pos}/${dur}ms category=$category",
                    positionMs = pos,
                    durationMs = dur,
                )
            }

            override fun onRenderedFirstFrame() {
                notifyVideoRenderingStart()
            }

            override fun onVideoSizeChanged(size: VideoSize) {
                notifyVideoSize(size.width, size.height)
            }
        })
    }

    override fun bindUnderlyingSurface(surface: Surface) {
        player.setVideoSurface(surface)
    }

    override fun applyUnderlyingDataSource(dataSource: Map<String, Any?>) {
        val uri = dataSource["uri"] as? String
            ?: throw IllegalArgumentException("dataSource.uri is required")
        // The MediaSourceFactory we built in [buildPlayer] already knows about
        // headers and HLS detection; here we just hand it the URI.
        player.setMediaItem(MediaItem.fromUri(Uri.parse(uri)))
    }

    override fun startUnderlyingPrepare() {
        player.prepare()
    }

    // ── Command primitives ───────────────────────────────────────────────

    override fun underlyingStart() {
        player.playWhenReady = true
        player.play()
    }

    override fun underlyingPause() {
        player.playWhenReady = false
        player.pause()
    }

    override fun underlyingSeekTo(positionMs: Long) {
        player.seekTo(positionMs)
    }

    override fun underlyingSetSpeed(speed: Float) {
        player.playbackParameters = PlaybackParameters(speed)
    }

    override fun underlyingSetVolume(volume: Float) {
        player.volume = volume
    }

    override fun underlyingRelease() {
        player.release()
    }

    override fun underlyingCurrentPosition(): Long = player.currentPosition

    override fun onHeartbeatTick() {
        // ExoPlayer has no callback for "buffered position advanced". Sample
        // it once per heartbeat instead. Coalesces with the position update
        // into a single emitState by the base class.
        setBufferedMsSilently(player.bufferedPosition)
    }

    /// Map ExoPlayer's structured [PlaybackException.errorCode] to a coarse
    /// [PlayerErrorCategory] name. Numeric codes are pulled from
    /// `PlaybackException.ERROR_CODE_*` to avoid brittle string matching.
    /// Ranges:
    ///   - 1xxx — runtime / unknown
    ///   - 2xxx — IO / network
    ///   - 3xxx — content (parsing / format)
    ///   - 4xxx — decoder / renderer
    ///   - 5xxx — DRM (we don't support DRM, treat as terminal)
    ///   - 6xxx — frame processing
    ///   - 7xxx — audio sink (rarely terminal)
    private fun categorizeExoError(code: Int): String {
        return when (code) {
            // 2xxx: IO. All network / source / IO failures.
            in 2000..2999 -> "network"
            // 3xxx: parsing/format. The container/manifest is broken or
            // unsupported. Switching backends won't help.
            in 3000..3999 -> "codecUnsupported"
            // 4xxx: decoder. The codec itself can't be initialised or is
            // unsupported on this device. IJK is our designated rescue.
            in 4000..4999 -> "codecUnsupported"
            // 5xxx: DRM. Not supported here — treat as terminal.
            in 5000..5999 -> "terminal"
            else -> "unknown"
        }
    }
}
