package cn.niuma.niuma_player

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

/**
 * Wraps an [EventChannel.EventSink] so that all callbacks are delivered on the
 * Android main looper. Flutter's platform channels require messages to be
 * dispatched from the main thread; IjkMediaPlayer however fires its listeners
 * on worker threads. This adapter hides that detail from callers.
 */
internal class MainThreadEventSink(
    private val sink: EventChannel.EventSink
) : EventChannel.EventSink {

    private val handler = Handler(Looper.getMainLooper())

    override fun success(event: Any?) {
        post { sink.success(event) }
    }

    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
        post { sink.error(errorCode, errorMessage, errorDetails) }
    }

    override fun endOfStream() {
        post { sink.endOfStream() }
    }

    private fun post(block: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            block()
        } else {
            handler.post(block)
        }
    }
}
