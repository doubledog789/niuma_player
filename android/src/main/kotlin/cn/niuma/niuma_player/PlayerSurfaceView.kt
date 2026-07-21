package cn.niuma.niuma_player

import android.content.Context
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import io.flutter.plugin.platform.PlatformView

/**
 * Flutter [PlatformView] backed by a [SurfaceView]，用于
 * `useAndroidPlatformView = true` 的原生渲染路径（原生缩放，画质更好）。
 * Surface 生命周期异步：surfaceCreated 时 push 给 session，销毁时 pop。
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
                // （全屏路由时），最后 push 的持有绑定。
                session.pushSurface(this@PlayerSurfaceView, holder.surface)
            }

            override fun surfaceChanged(
                holder: SurfaceHolder, format: Int, width: Int, height: Int
            ) {
                // Resize only — the Surface stays valid, no re-bind needed.
            }

            override fun surfaceDestroyed(holder: SurfaceHolder) {
                // 从 surface 栈移除自己；若正持有绑定，session 回退到上一个
                // 存活 surface，避免输出到 dead Surface 触发 codec 报错。
                session.popSurface(this@PlayerSurfaceView)
            }
        })
    }

    override fun getView(): View = surfaceView

    override fun dispose() {
        // 销毁路径可能跳过 surfaceDestroyed，再 pop 一次（幂等）。
        session.popSurface(this)
    }
}
