package cn.niuma.niuma_player

import android.content.Context
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/**
 * Factory for viewType `cn.niuma/player_surface`：按 creationParams 的
 * `instanceId` 查已创建的 [PlayerSession] 并包成 [PlayerSurfaceView]。
 */
internal class PlayerSurfaceViewFactory(
    private val sessionLookup: (Long) -> PlayerSession?,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        @Suppress("UNCHECKED_CAST")
        val params = args as? Map<String, Any?>
        val instanceId = (params?.get("instanceId") as? Number)?.toLong()
            ?: throw IllegalArgumentException(
                "PlayerSurfaceView creationParams missing 'instanceId'"
            )
        val session = sessionLookup(instanceId)
            ?: throw IllegalStateException(
                "No PlayerSession registered for instanceId=$instanceId. " +
                "The session may have been disposed before its PlatformView " +
                "got created, or the create() call hasn't returned yet."
            )
        return PlayerSurfaceView(context, session)
    }
}
