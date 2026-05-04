/// niuma_player SDK 资源路径常量。
///
/// 资源来自 niuma-player-assets v1.1（design-tokens.json + 31 控件 + 5
/// 进度条表情 + loading 动画），全部以 SVG 形式打包在 SDK 内。
///
/// 用法：
/// ```dart
/// SvgPicture.asset(
///   NiumaSdkAssets.icPlay,
///   width: 24,
///   colorFilter: ColorFilter.mode(Colors.white, BlendMode.srcIn),
/// )
/// ```
class NiumaSdkAssets {
  NiumaSdkAssets._();

  static const String _pkg = 'niuma_player';
  static const String _ctrl = 'packages/$_pkg/assets/player_controls';
  static const String _thumb = 'packages/$_pkg/assets/progress_thumbs';
  static const String _load = 'packages/$_pkg/assets/loading';

  // ===== 播放控制 =====
  static const String icPlay = '$_ctrl/ic_play.svg';
  static const String icPause = '$_ctrl/ic_pause.svg';
  static const String icPlayCircle = '$_ctrl/ic_play_circle.svg';
  static const String icPauseCircle = '$_ctrl/ic_pause_circle.svg';
  static const String icNext = '$_ctrl/ic_next.svg';
  static const String icPrevious = '$_ctrl/ic_previous.svg';
  static const String icForward10 = '$_ctrl/ic_forward_10.svg';
  static const String icRewind10 = '$_ctrl/ic_rewind_10.svg';

  // ===== 倍速 =====
  static const String icSpeed = '$_ctrl/ic_speed.svg';
  static const String icSpeedAlt = '$_ctrl/ic_speed_alt.svg';

  // ===== 投屏 / 画中画 =====
  static const String icCast = '$_ctrl/ic_cast.svg';
  static const String icCastConnected = '$_ctrl/ic_cast_connected.svg';
  static const String icPip = '$_ctrl/ic_pip.svg';
  static const String icPipExit = '$_ctrl/ic_pip_exit.svg';

  // ===== 弹幕 =====
  static const String icDanmakuOn = '$_ctrl/ic_danmaku_on.svg';
  static const String icDanmakuOff = '$_ctrl/ic_danmaku_off.svg';
  static const String icDanmakuSettings = '$_ctrl/ic_danmaku_settings.svg';

  // ===== 全屏 =====
  static const String icFullscreenEnter = '$_ctrl/ic_fullscreen_enter.svg';
  static const String icFullscreenExit = '$_ctrl/ic_fullscreen_exit.svg';
  static const String icFullscreenLandscape = '$_ctrl/ic_fullscreen_landscape.svg';

  // ===== 进度条拖动点 =====
  static const String icSeekDot = '$_ctrl/ic_seek_dot.svg';

  // ===== 音量 =====
  static const String icVolume = '$_ctrl/ic_volume.svg';
  static const String icVolumeMute = '$_ctrl/ic_volume_mute.svg';

  // ===== 其他 =====
  static const String icQuality = '$_ctrl/ic_quality.svg';
  static const String icSubtitle = '$_ctrl/ic_subtitle.svg';
  static const String icSettings = '$_ctrl/ic_settings.svg';
  static const String icLock = '$_ctrl/ic_lock.svg';
  static const String icUnlock = '$_ctrl/ic_unlock.svg';
  static const String icScreenshot = '$_ctrl/ic_screenshot.svg';
  static const String icClose = '$_ctrl/ic_close.svg';
  static const String icBack = '$_ctrl/ic_back.svg';

  // ===== 进度条牛马表情（5 状态）=====
  static const String thumbDefault = '$_thumb/thumb_default.svg';
  static const String thumbSmile = '$_thumb/thumb_smile.svg';
  static const String thumbSad = '$_thumb/thumb_sad.svg';
  static const String thumbShock = '$_thumb/thumb_shock.svg';
  static const String thumbSleep = '$_thumb/thumb_sleep.svg';

  // ===== Loading 动画 =====
  static const String loadingAnimated = '$_load/loading_animated.svg';

  // ===== Helpers =====

  static String playPauseIcon({required bool isPlaying, bool circle = false}) {
    if (circle) return isPlaying ? icPauseCircle : icPlayCircle;
    return isPlaying ? icPause : icPlay;
  }

  static String fullscreenIcon({required bool isFullscreen}) =>
      isFullscreen ? icFullscreenExit : icFullscreenEnter;

  static String danmakuToggleIcon({required bool isOn}) =>
      isOn ? icDanmakuOn : icDanmakuOff;

  static String castIcon({required bool isConnected}) =>
      isConnected ? icCastConnected : icCast;

  static String pipIcon({required bool isInPip}) =>
      isInPip ? icPipExit : icPip;

  static String lockIcon({required bool isLocked}) =>
      isLocked ? icLock : icUnlock;

  static String volumeIcon({required double volume}) =>
      volume == 0 ? icVolumeMute : icVolume;

  static String thumbForState(NiumaProgressThumbState state) {
    switch (state) {
      case NiumaProgressThumbState.idle:
        return thumbDefault;
      case NiumaProgressThumbState.seekForward:
        return thumbSmile;
      case NiumaProgressThumbState.seekBackward:
        return thumbSad;
      case NiumaProgressThumbState.seekFast:
        return thumbShock;
      case NiumaProgressThumbState.paused:
        return thumbSleep;
    }
  }
}

/// 进度条 thumb 的 5 种表情状态。
///
/// 由 [NiumaSdkAssets.thumbForState] 映射到具体 SVG 资源。
enum NiumaProgressThumbState {
  idle,
  seekForward,
  seekBackward,
  seekFast,
  paused,
}
