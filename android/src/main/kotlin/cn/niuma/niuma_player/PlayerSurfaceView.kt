package cn.niuma.niuma_player

import android.content.Context
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import io.flutter.plugin.platform.PlatformView

/**
 * Flutter [PlatformView] backed by an Android [SurfaceView]. Used when the
 * consumer opts into native platform-view rendering
 * (`NiumaPlayerOptions.useAndroidPlatformView = true`) for higher visual
 * quality (native scaling, no Flutter Texture every-frame filterQuality
 * cost).
 *
 * Surface lifecycle is asynchronous:
 *   1. Factory creates this view and registers `instanceId` → this instance.
 *   2. Android composites the SurfaceView; `surfaceCreated` fires.
 *   3. We hand the [android.view.Surface] to the bound [PlayerSession] via
 *      [PlayerSession.setSurface]. The session, which has been waiting in a
 *      "surface-pending" state, then completes its bring-up (binds surface,
 *      applies data source, kicks prepare).
 *
 * If the SurfaceView gets recreated (e.g. activity recreation, app moved
 * between displays), `surfaceCreated` fires again and we re-bind via
 * [PlayerSession.setSurface]; the session's `bindUnderlyingSurface` is
 * idempotent w.r.t. switching to a new Surface.
 */
internal class PlayerSurfaceView(
    context: Context,
    private val session: PlayerSession,
) : PlatformView {

    private val surfaceView = SurfaceView(context)

    init {
        surfaceView.holder.addCallback(object : SurfaceHolder.Callback {
            override fun surfaceCreated(holder: SurfaceHolder) {
                if (session.released) return
                // push（而非裸 set）：同一 session 可能同时有多个 SurfaceView
                // （fullscreen 路由 push 时 inline 那份仍 mounted），最后 push 的
                // 持有绑定；销毁时 pop 回退到上一个仍存活的 surface。
                session.pushSurface(this@PlayerSurfaceView, holder.surface)
            }

            override fun surfaceChanged(
                holder: SurfaceHolder, format: Int, width: Int, height: Int
            ) {
                // SurfaceView resized — the underlying Surface object stays valid,
                // no re-bind needed. ExoPlayer / IJK handle the new buffer size
                // transparently.
            }

            override fun surfaceDestroyed(holder: SurfaceHolder) {
                // 本视图的 Surface 没了（路由 pop / 不可见）。从 session 的
                // surface 栈移除自己；若自己正持有绑定，session 自动回退到上一个
                // 存活 surface（修复「退全屏 → 输出到 dead Surface → codec 报错」）。
                session.popSurface(this@PlayerSurfaceView)
            }
        })
    }

    override fun getView(): View = surfaceView

    override fun dispose() {
        // 保险：PlatformView 销毁路径可能跳过 surfaceDestroyed（顺序不保证），
        // 再 pop 一次（幂等）。
        session.popSurface(this)
    }
}
