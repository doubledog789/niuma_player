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
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.view.TextureRegistry

/**
 * [PlayerSession] driven by ExoPlayer. Hardware-decode fast path — the default
 * Android backend; IJK is used only when the caller passes `forceIjk`.
 */
internal class ExoPlayerSession(
    textureRegistry: TextureRegistry?,
    messenger: BinaryMessenger,
    context: Context,
    dataSource: Map<String, Any?>,
    platformViewInstanceId: Long? = null,
) : PlayerSession(textureRegistry, messenger, context, dataSource, platformViewInstanceId) {

    private val player: ExoPlayer = buildPlayer(context, dataSource)

    /// First STATE_READY maps to notifyPrepared; subsequent ones become
    /// notifyBufferingEnd.
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
        // 解码器回退：硬解 codec 失败时同会话内自动试下一个（含软件）解码器，
        // 避免抛错绕 Dart 重试 IJK 时的错误闪现。
        val renderersFactory = DefaultRenderersFactory(context)
            .setEnableDecoderFallback(true)
        return ExoPlayer.Builder(context, renderersFactory)
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
                        // First buffer is part of opening; only subsequent
                        // buffers are mid-playback stalls.
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
                        // No-op — phase is already driven by notifyError / bringUp.
                    }
                }
            }

            override fun onPlayerError(error: PlaybackException) {
                val pos = try { player.currentPosition } catch (_: Throwable) { -1L }
                val dur = try { player.duration } catch (_: Throwable) { -1L }
                val category = categorizeExoError(error.errorCode)
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

    override fun clearUnderlyingSurface() {
        player.setVideoSurface(null)
    }

    override fun bindUnderlyingSurface(surface: Surface) {
        player.setVideoSurface(surface)
    }

    override fun applyUnderlyingDataSource(dataSource: Map<String, Any?>) {
        val uri = dataSource["uri"] as? String
            ?: throw IllegalArgumentException("dataSource.uri is required")
        // MediaSourceFactory already handles headers + HLS detection.
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
        // No callback for "buffered position advanced" — sample per heartbeat.
        setBufferedMsSilently(player.bufferedPosition)
    }

    /// Map [PlaybackException.errorCode] ranges to a coarse
    /// [PlayerErrorCategory]（2xxx IO / 3xxx 格式 / 4xxx 解码器 / 5xxx DRM）。
    private fun categorizeExoError(code: Int): String {
        return when (code) {
            in 2000..2999 -> "network"
            // 3xxx parsing/format：换 backend 也救不了，归 codec。
            in 3000..3999 -> "codecUnsupported"
            // 4xxx decoder：本机解不了，IJK 是指定的兜底。
            in 4000..4999 -> "codecUnsupported"
            // 5xxx DRM：不支持，terminal。
            in 5000..5999 -> "terminal"
            else -> "unknown"
        }
    }
}
