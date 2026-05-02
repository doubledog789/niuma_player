package cn.niuma.niuma_player_example

import android.content.res.Configuration
import cn.niuma.niuma_player.NiumaPlayerPlugin
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration?,
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        NiumaPlayerPlugin.reportPipModeChanged(isInPictureInPictureMode)
    }
}
