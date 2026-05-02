package cn.niuma.niuma_player

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/// PiP 窗 RemoteAction 广播接收器。
///
/// PiP 窗内的 play/pause 按钮通过 PendingIntent.getBroadcast 发出广播，
/// 本 receiver 接收后通过 [NiumaPlayerPlugin.pipEventSink] 推送
/// `playPauseToggle` 事件到 Dart 侧，由 [NiumaPlayerController] 解析后
/// 调用 play() / pause()。
///
/// 注：dynamic-registered receiver（在 [NiumaPlayerPlugin.onAttachedToActivity]
/// 时 registerReceiver），生命周期跟 plugin 同步，不需要 manifest 静态注册。
class PipBroadcastReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == NiumaPlayerPlugin.ACTION_PIP_PLAY_PAUSE) {
            NiumaPlayerPlugin.pipEventSink?.success(
                mapOf("event" to "playPauseToggle")
            )
        }
    }
}
