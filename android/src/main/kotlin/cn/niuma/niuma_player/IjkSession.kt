package cn.niuma.niuma_player

import android.content.Context
import android.net.Uri
import android.view.Surface
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.view.TextureRegistry
import tv.danmaku.ijk.media.player.IMediaPlayer
import tv.danmaku.ijk.media.player.IjkMediaPlayer

/**
 * [PlayerSession] driven by IjkMediaPlayer. Software-decoded rescue path for
 * devices where the system MediaCodec is unstable — slower than ExoPlayer but
 * crash-free.
 */
internal class IjkSession(
    textureRegistry: TextureRegistry?,
    messenger: BinaryMessenger,
    context: Context,
    dataSource: Map<String, Any?>,
    platformViewInstanceId: Long? = null,
) : PlayerSession(textureRegistry, messenger, context, dataSource, platformViewInstanceId) {

    private val player: IjkMediaPlayer = IjkMediaPlayer()

    init {
        bringUp()
    }

    // ── Configure ────────────────────────────────────────────────────────

    override fun configurePlayerOptions() {
        // 强制软解：IJK 在本插件的职责就是兜 MediaCodec 不稳的设备，
        // 开 mediacodec 会重新引入正在回避的硬解路径。
        player.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "mediacodec", 0)

        // We orchestrate prepare → play from the Dart side; no auto-start.
        player.setOption(
            IjkMediaPlayer.OPT_CATEGORY_PLAYER, "start-on-prepared", 0
        )

        // RV32（RGBA8888）而非默认 YV12：单张对齐纹理，避开奇数宽 / stride
        // 导致 Impeller 拒建纹理的所有角落；代价约 5-10% CPU。
        player.setOption(
            IjkMediaPlayer.OPT_CATEGORY_PLAYER, "overlay-format",
            IjkMediaPlayer.SDL_FCC_RV32.toLong()
        )

        // 限制 prepare 阶段预解码帧队列：过大时起播会快进式追时钟（前 2-3 秒
        // 3x 速），50 足够防 underrun 又看不出追帧。
        player.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "min-frames", 50)

        // framedrop 必须为 0：>0 会在软解跟不上时把所有帧 early-drop 掉，
        // 黑屏有声；0 的代价是可能渐进失步，两害取其轻。
        player.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "framedrop", 0)

        // 不要调小 probesize / analyzeduration——它们是上限不是必读量，
        // 调小会让高码率 TS 探不齐视频流（-10000 / 无限 buffering）；沿用 FFmpeg 默认。

        // Network resilience: transient failures all surface as `what=-10000
        // extra=0`, so let FFmpeg recover on its own before propagating.
        player.setOption(IjkMediaPlayer.OPT_CATEGORY_FORMAT, "reconnect", 1)
        // 绝不能开 reconnect_streamed：它把 HLS 分片的正常 EOF 也当断连，
        // 无限重连同一分片 → buffering/seek 死循环。
        player.setOption(
            IjkMediaPlayer.OPT_CATEGORY_FORMAT, "reconnect_delay_max", 5L
        )
        // Socket read timeout, microseconds. Without this, a half-open TCP
        // connection can hang IJK's read loop forever.
        player.setOption(
            IjkMediaPlayer.OPT_CATEGORY_FORMAT, "timeout", 15_000_000L
        )

        player.setOption(
            IjkMediaPlayer.OPT_CATEGORY_FORMAT,
            "protocol_whitelist",
            "async,cache,crypto,file,http,https,ijkhttphook,ijkinject,ijklivehook,ijklongurl,ijksegment,ijktcphook,pipe,rtp,tcp,tls,udp,ijkurlhook,data"
        )
    }

    override fun attachUnderlyingListeners() {
        player.setOnPreparedListener { mp ->
            notifyPrepared(mp.duration, mp.videoWidth, mp.videoHeight)
        }

        player.setOnCompletionListener {
            notifyCompletion()
        }

        player.setOnErrorListener { _, what, extra ->
            // 附带 position/duration 上下文——IJK 常报 what=-10000 extra=0，
            // 本身零信息量。
            val pos = try { player.currentPosition } catch (_: Throwable) { -1L }
            val dur = try { player.duration } catch (_: Throwable) { -1L }
            val category = categorizeError(what, extra, hadFirstFrame)
            notifyError(
                category = category,
                code = what.toString(),
                message = "IjkMediaPlayer error what=$what extra=$extra " +
                    "pos=${pos}/${dur}ms category=$category",
                positionMs = pos,
                durationMs = dur,
            )
            true
        }

        player.setOnInfoListener { _, what, _ ->
            when (what) {
                IMediaPlayer.MEDIA_INFO_BUFFERING_START -> notifyBufferingStart()
                IMediaPlayer.MEDIA_INFO_BUFFERING_END -> notifyBufferingEnd()
                IMediaPlayer.MEDIA_INFO_VIDEO_RENDERING_START ->
                    notifyVideoRenderingStart()

                // Prepare-phase stage decoration; literals avoid depending on
                // IJK-specific constants missing from some AAR builds.
                MEDIA_INFO_OPEN_INPUT -> notifyOpeningStage("openInput")
                MEDIA_INFO_FIND_STREAM_INFO -> notifyOpeningStage("findStreamInfo")
                MEDIA_INFO_COMPONENT_OPEN -> notifyOpeningStage("componentOpen")
                MEDIA_INFO_VIDEO_DECODED_START ->
                    notifyOpeningStage("videoDecodedStart")
                MEDIA_INFO_AUDIO_DECODED_START ->
                    notifyOpeningStage("audioDecodedStart")
            }
            true
        }

        player.setOnBufferingUpdateListener { _, percent ->
            // IJK reports buffering progress as 0-100 (percent of duration).
            notifyBufferedPercent(percent)
        }

        player.setOnVideoSizeChangedListener { _, w, h, _, _ ->
            notifyVideoSize(w, h)
        }
    }

    override fun clearUnderlyingSurface() {
        player.setSurface(null)
    }

    override fun bindUnderlyingSurface(surface: Surface) {
        player.setSurface(surface)
    }

    override fun applyUnderlyingDataSource(dataSource: Map<String, Any?>) {
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
                // Caller is expected to pre-resolve to an absolute file path;
                // raw asset URIs are accepted as a best-effort.
                player.setDataSource(context, Uri.parse(uri))
            }
            else -> {
                throw IllegalArgumentException("Unknown dataSource.type: $type")
            }
        }
    }

    override fun startUnderlyingPrepare() = player.prepareAsync()

    // ── Command primitives ───────────────────────────────────────────────

    override fun underlyingStart() = player.start()
    override fun underlyingPause() = player.pause()
    override fun underlyingSeekTo(positionMs: Long) = player.seekTo(positionMs)
    override fun underlyingSetSpeed(speed: Float) {
        player.setSpeed(speed)
    }
    override fun underlyingSetVolume(volume: Float) {
        player.setVolume(volume, volume)
    }
    override fun underlyingRelease() {
        try { player.stop() } catch (_: Throwable) {}
        player.release()
    }
    override fun underlyingCurrentPosition(): Long = player.currentPosition

    // ── IJK error categorisation ─────────────────────────────────────────

    /// Map IJK `what`/`extra` to a coarse [PlayerErrorCategory]，hand-tuned from
    /// observed production failures; -10000 无信息量，按是否已出首帧区分
    /// transient / network。
    private fun categorizeError(what: Int, extra: Int, hadFirstFrame: Boolean): String {
        return when (what) {
            -1010 -> "codecUnsupported"
            -1007 -> "codecUnsupported"
            100 -> "terminal"
            -1004 -> "network"
            -110 -> "network"
            -10000 -> if (hadFirstFrame) "transient" else "network"
            else -> "unknown"
        }
    }

    companion object {
        // IJK-specific MEDIA_INFO_* codes, mirrored here so we don't depend on
        // their presence in the vendored IJK AAR.
        private const val MEDIA_INFO_AUDIO_DECODED_START = 10003
        private const val MEDIA_INFO_VIDEO_DECODED_START = 10004
        private const val MEDIA_INFO_OPEN_INPUT = 10005
        private const val MEDIA_INFO_FIND_STREAM_INFO = 10006
        private const val MEDIA_INFO_COMPONENT_OPEN = 10007
    }
}
