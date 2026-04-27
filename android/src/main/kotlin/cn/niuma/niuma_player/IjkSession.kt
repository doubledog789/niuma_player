package cn.niuma.niuma_player

import android.content.Context
import android.net.Uri
import android.view.Surface
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.view.TextureRegistry
import tv.danmaku.ijk.media.player.IMediaPlayer
import tv.danmaku.ijk.media.player.IjkMediaPlayer

/**
 * [PlayerSession] driven by `tv.danmaku.ijk.media.player.IjkMediaPlayer`.
 *
 * Software-decoded path (`mediacodec=0`) used as the rescue option for
 * devices where the system MediaCodec is unstable. Slower than the
 * ExoPlayer fast path but crash-free on Huawei / low-end MTK SoCs etc.
 */
internal class IjkSession(
    textureRegistry: TextureRegistry,
    messenger: BinaryMessenger,
    context: Context,
    dataSource: Map<String, Any?>
) : PlayerSession(textureRegistry, messenger, context, dataSource) {

    private val player: IjkMediaPlayer = IjkMediaPlayer()

    init {
        bringUp()
    }

    // ── Configure ────────────────────────────────────────────────────────

    override fun configurePlayerOptions() {
        // Force software decoding. IJK's raison d'être in this plugin is to
        // rescue playback on devices where the system's MediaCodec is flaky
        // (Huawei, old Xiaomi / Redmi low-end SoCs like MTK Helio G25/G35
        // where MediaCodec can segfault in native). Turning mediacodec back
        // on here would re-introduce the exact hardware path we're falling
        // back from. FFmpeg software decoding is slower but crash-free.
        player.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "mediacodec", 0)

        // We orchestrate prepare → play from the Dart side; no auto-start.
        player.setOption(
            IjkMediaPlayer.OPT_CATEGORY_PLAYER, "start-on-prepared", 0
        )

        // Emit RGBA8888 frames instead of the default YV12 3-plane layout.
        //
        // Why this matters: with YV12, IJK uploads Y / U / V as three separate
        // GL_LUMINANCE textures. Each plane's GL texture width is forced to
        // the decoder's stride (not frame width) because ES2 has no
        // GL_UNPACK_ROW_LENGTH. For videos with unusual widths — e.g. 2578
        // (not a multiple of 4 or 16) — the decoded stride is padded up
        // (2592 / 2624), and downstream consumers (Impeller / Vulkan) can
        // reject the source texture with "Could not create Impeller texture"
        // because their allocator has stricter alignment checks than ES2.
        //
        // RV32 makes IJK do YUV→RGBA on the CPU and emit a single, aligned,
        // 4-channel texture. Costs ~5-10% extra CPU but sidesteps every
        // plane/stride corner case (odd widths, 10-bit, weird SAR).
        player.setOption(
            IjkMediaPlayer.OPT_CATEGORY_PLAYER, "overlay-format",
            IjkMediaPlayer.SDL_FCC_RV32.toLong()
        )

        // Cap the pre-decode frame queue during prepare. IJK normally
        // pre-decodes a big batch of frames before reporting "prepared". With
        // software decoding those frames sit in the queue with PTS in the
        // past; when play() fires, IJK renders them as fast as possible to
        // catch up with the just-set wall clock, which users see as "the
        // first 2-3 seconds play at 3x speed" right after tap-to-play. 50
        // frames is a safe cap — enough to avoid underrun, not enough to
        // produce a visible catch-up burst.
        player.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "min-frames", 50)

        // Don't drop frames. framedrop>0 compounds with the pre-decode
        // catch-up problem on slow devices (Redmi 9A class) and looks jerky
        // without actually helping sustained sync — audio master clock
        // handles sync on its own.
        player.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "framedrop", 0)

        // Shorter demuxer probe: we only target mp4 / m3u8 in this build so
        // FFmpeg doesn't need to scan megabytes of source to figure out the
        // container. Faster prepare + smaller prepare-time buffer.
        player.setOption(
            IjkMediaPlayer.OPT_CATEGORY_FORMAT, "analyzeduration", 1_000_000L
        )
        player.setOption(
            IjkMediaPlayer.OPT_CATEGORY_FORMAT, "probesize", (100 * 1024).toLong()
        )

        // Network resilience. Transient mobile handoffs, HLS segment 404s,
        // and TLS blips all surface as `error what=-10000 extra=0` with no
        // further diagnostic info — so we give FFmpeg as much rope as
        // possible to recover on its own before propagating the error.
        player.setOption(IjkMediaPlayer.OPT_CATEGORY_FORMAT, "reconnect", 1)
        player.setOption(
            IjkMediaPlayer.OPT_CATEGORY_FORMAT, "reconnect_streamed", 1
        )
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
            // IJK errors often come through with `what=-10000 extra=0`, which
            // by itself tells us nothing. Capture the current playback
            // position + duration so the Dart / app side has enough context
            // to distinguish "failed before first frame" from "died mid-
            // playback" in bug reports.
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

                // Prepare-phase stage decoration. Numeric constants come
                // straight from IjkMediaPlayer.java — using literals avoids
                // brittle imports if the IJK AAR ships a stripped-down
                // IMediaPlayer interface without IJK-specific codes.
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
                // Asset playback via IJK requires the full filesystem path
                // resolved by Flutter's asset manager on the Dart side. We
                // expect the caller to have already resolved it to an
                // absolute file path, but also accept raw asset URIs as a
                // best-effort.
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

    /// Map IJK's `what` / `extra` codes to a coarse [PlayerErrorCategory]
    /// name. The mapping is hand-tuned from observed production failures
    /// rather than IJK's docs (which list constants without much guidance
    /// on which to retry):
    ///
    ///  - `-1010` (UNSUPPORTED) / `-1007` (MALFORMED) → codec — switching
    ///    decoders inside IJK won't help, and `-1010` specifically tells
    ///    us FFmpeg already gave up on the codec.
    ///  - `100` (SERVER_DIED) → terminal — the underlying mediaserver
    ///    crashed; no retry will recover this session.
    ///  - `-1004` (IO) / `-110` (TIMED_OUT) → network — the bytes aren't
    ///    arriving; caller should retry the line, not the player.
    ///  - `-10000` (generic IJK error, very common with `extra=0`): if
    ///    we'd already rendered a frame it's likely a transient mid-
    ///    playback glitch; if we never rendered one it's almost always a
    ///    network issue in our environment.
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
        // IJK-specific MEDIA_INFO_* codes. Values mirror the public
        // constants on `tv.danmaku.ijk.media.player.IjkMediaPlayer`.
        // Declared here so we don't depend on their presence in whichever
        // IJK AAR version is vendored in localmaven/.
        private const val MEDIA_INFO_AUDIO_DECODED_START = 10003
        private const val MEDIA_INFO_VIDEO_DECODED_START = 10004
        private const val MEDIA_INFO_OPEN_INPUT = 10005
        private const val MEDIA_INFO_FIND_STREAM_INFO = 10006
        private const val MEDIA_INFO_COMPONENT_OPEN = 10007
    }
}
