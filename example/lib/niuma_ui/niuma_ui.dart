/// niuma_ui —— niuma_player headless 内核的**官方参考皮**（可拷贝、可丢弃）。
///
/// niuma_player 包本身只导出 headless 播放内核（`NiumaPlayerController` +
/// 编排逻辑 + 手势/全屏/弹幕 headless controller）。这套 UI——一体化
/// `NiumaPlayer`、22 个原子控件、控件条、全屏页、反馈态、弹幕/广告/缩略图/
/// cast/短视频 widget、主题——不进 SDK semver 契约，存放在 example 里供接入方
/// 按需拷贝、自由改造。
///
/// 用法：
/// ```dart
/// import 'package:niuma_player/niuma_player.dart';        // headless 核
/// import 'package:niuma_player_example/niuma_ui/niuma_ui.dart'; // 参考皮
/// ```
/// 真实业务里把 `niuma_ui/` 整个（或所需子目录）拷进你自己的工程，改 import
/// 为本地相对路径即可。
library;

// UI 资源路径常量 + 进度条牛马表情 thumb 状态枚举
export 'niuma_ui_assets.dart' show NiumaUiAssets, NiumaProgressThumbState;

// 一体化 widget + 主题
export 'core/niuma_player.dart' show NiumaPlayer, NiumaPlayerConfigScope;
export 'core/niuma_player_theme.dart'
    show NiumaPlayerTheme, NiumaPlayerThemeData;

// 全屏页 + 全屏控制扩展
export 'fullscreen/niuma_fullscreen_page.dart'
    show NiumaFullscreenPage, NiumaFullscreenControl;

// 反馈 UI
export 'feedback/niuma_loading_indicator.dart' show NiumaLoadingIndicator;
export 'feedback/niuma_error_view.dart' show NiumaErrorView;
export 'feedback/niuma_ended_view.dart' show NiumaEndedView;
export 'feedback/niuma_progress_thumb.dart' show NiumaProgressThumb;

// 缩略图 widget
export 'thumbnail/niuma_thumbnail_view.dart' show NiumaThumbnailView;
export 'thumbnail/niuma_scrub_preview.dart' show NiumaScrubPreview;

// 控件条 + 配置驱动 UI
export 'control_bar/niuma_control_bar.dart' show NiumaControlBar;
export 'control_bar/niuma_control_button.dart' show NiumaControlButton;
export 'control_bar/niuma_control_bar_config.dart' show NiumaControlBarConfig;
export 'control_bar/button_override.dart'
    show ButtonOverride, BuilderOverride, FieldsOverride;
export 'control_bar/niuma_fullscreen_control_bar.dart'
    show NiumaFullscreenControlBar;

// 广告 overlay + 调度
export 'ad/ad_schedule.dart'
    show
        AdCue,
        AdController,
        NiumaAdSchedule,
        MidRollAd,
        MidRollSkipPolicy,
        PauseAdShowPolicy;
export 'ad/ad_scheduler.dart' show AdSchedulerOrchestrator;
export 'ad/niuma_ad_overlay.dart' show NiumaAdOverlay;

// 弹幕渲染 widget + 设置面板
export 'danmaku/niuma_danmaku_overlay.dart' show NiumaDanmakuOverlay;
export 'danmaku/niuma_danmaku_scope.dart' show NiumaDanmakuScope;
export 'danmaku/danmaku_settings_panel.dart' show DanmakuSettingsPanel;

// 手势 widget
export 'gesture/niuma_gesture_layer.dart'
    show NiumaGestureLayer, GestureHudBuilder;
export 'gesture/niuma_gesture_hud.dart' show NiumaGestureHud;

// 原子控件（裸名）
export 'controls/play_pause_button.dart' show PlayPauseButton;
export 'controls/scrub_bar.dart' show ScrubBar;
export 'controls/time_display.dart' show TimeDisplay;
export 'controls/volume_button.dart' show VolumeButton;
export 'controls/speed_selector.dart' show SpeedSelector;
export 'controls/quality_selector.dart' show QualitySelector;
export 'controls/subtitle_button.dart' show SubtitleButton;
export 'controls/danmaku_button.dart' show DanmakuButton;
export 'controls/fullscreen_button.dart' show FullscreenButton;
export 'controls/pip_button.dart' show PipButton;
export 'controls/niuma_sdk_icon.dart' show NiumaSdkIcon;

// 原子控件 Niuma* 前缀 alias（推荐用名）
export 'controls/aliases.dart'
    show
        NiumaPlayPauseButton,
        NiumaScrubBar,
        NiumaTimeDisplay,
        NiumaVolumeButton,
        NiumaSpeedSelector,
        NiumaQualitySelector,
        NiumaSubtitleButton,
        NiumaDanmakuButton,
        NiumaFullscreenButton,
        NiumaPipButton;

// 短视频
export 'short_video/niuma_short_video_player.dart' show NiumaShortVideoPlayer;
export 'short_video/niuma_short_video_progress_bar.dart'
    show NiumaShortVideoProgressBar;
export 'short_video/niuma_short_video_pause_indicator.dart'
    show NiumaShortVideoPauseIndicator;
export 'short_video/niuma_short_video_scrub_label.dart'
    show NiumaShortVideoScrubLabel;
export 'short_video/niuma_short_video_fullscreen_button.dart'
    show NiumaShortVideoFullscreenButton;
export 'short_video/niuma_short_video_theme.dart' show NiumaShortVideoTheme;

// Cast UI + 协议实现（DLNA / AirPlay）+ registry
export 'cast/niuma_cast_button.dart' show NiumaCastButton;
export 'cast/niuma_cast_overlay.dart' show NiumaCastOverlay;
export 'cast/niuma_cast_picker_panel.dart' show NiumaCastPickerPanel;
export 'cast/cast_service.dart' show CastService;
export 'cast/cast_registry.dart' show NiumaCastRegistry;
export 'cast/dlna_cast_service.dart' show DlnaCastService;
export 'cast/airplay_cast_service.dart' show AirPlayCastService;
