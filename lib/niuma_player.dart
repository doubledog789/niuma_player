// 内核
export 'package:niuma_player/src/data/default_backend_factory.dart' show DefaultBackendFactory;
export 'package:niuma_player/src/data/default_platform_bridge.dart' show DefaultPlatformBridge;
export 'package:niuma_player/src/data/device_memory.dart';
export 'package:niuma_player/src/domain/backend_factory.dart' show BackendFactory;
export 'package:niuma_player/src/domain/data_source.dart';
export 'package:niuma_player/src/domain/platform_bridge.dart' show PlatformBridge;
export 'package:niuma_player/src/domain/player_backend.dart' show PlayerBackend, PlayerBackendKind;
export 'src/domain/player_state.dart'
    show
        NiumaPlayerValue,
        PlayerPhase,
        PlayerError,
        PlayerErrorCategory,
        NiumaPlayerEvent,
        BackendSelected,
        FallbackTriggered,
        FallbackReason,
        LineSwitching,
        LineSwitched,
        LineSwitchFailed,
        PipModeChanged,
        PipRemoteAction,
        CastStarted,
        CastEnded,
        CastError;
export 'src/presentation/core/niuma_player_controller.dart'
    show NiumaPlayerController, NiumaPlayerOptions, ThumbnailFetcher;
export 'package:niuma_player/src/presentation/core/niuma_player_view.dart';
export 'package:niuma_player/src/presentation/thumbnail/niuma_thumbnail_view.dart' show NiumaThumbnailView;

// M9 主题
export 'src/presentation/core/niuma_player_theme.dart'
    show NiumaPlayerTheme, NiumaPlayerThemeData;

// M9 一体化组件 + 全屏 page
export 'package:niuma_player/src/presentation/core/niuma_player.dart'
    show NiumaPlayer, NiumaPlayerConfigScope;
export 'package:niuma_player/src/presentation/fullscreen/niuma_fullscreen_page.dart' show NiumaFullscreenPage;

// 反馈 UI（loading / error / ended 默认实现，业务可通过 NiumaPlayer 的
// loadingBuilder / errorBuilder / endedBuilder 覆盖）
export 'src/presentation/feedback/niuma_loading_indicator.dart'
    show NiumaLoadingIndicator;
export 'src/presentation/feedback/niuma_error_view.dart' show NiumaErrorView;
export 'src/presentation/feedback/niuma_ended_view.dart' show NiumaEndedView;

// 资源包路径常量 + 进度条牛马表情 thumb（5 状态）
export 'src/niuma_sdk_assets.dart'
    show NiumaSdkAssets, NiumaProgressThumbState;
export 'package:niuma_player/src/presentation/feedback/niuma_progress_thumb.dart' show NiumaProgressThumb;

// M9 缩略图悬浮预览
export 'package:niuma_player/src/presentation/thumbnail/niuma_scrub_preview.dart' show NiumaScrubPreview;

// M9 控件条组合
export 'package:niuma_player/src/presentation/control_bar/niuma_control_bar.dart' show NiumaControlBar;

// M16 配置驱动 UI（控件 enum / config / 按钮覆盖）
export 'package:niuma_player/src/presentation/control_bar/niuma_control_button.dart' show NiumaControlButton;
export 'src/presentation/control_bar/niuma_control_bar_config.dart'
    show NiumaControlBarConfig;
export 'src/presentation/control_bar/button_override.dart'
    show ButtonOverride, BuilderOverride, FieldsOverride;
export 'src/presentation/control_bar/niuma_fullscreen_control_bar.dart'
    show NiumaFullscreenControlBar;
export 'src/presentation/cast/niuma_cast_picker_panel.dart'
    show NiumaCastPickerPanel;

// M9 广告 overlay
export 'package:niuma_player/src/presentation/ad/niuma_ad_overlay.dart' show NiumaAdOverlay;

// M9 原子控件——为避免和业务方自家通用名 widget 冲突，
// 推荐使用下方 `Niuma*` 前缀的 typedef alias。原裸名仍保留向后兼容，
// 1.0 之前不删除——但新代码请用前缀名。
export 'src/presentation/controls/play_pause_button.dart'
    show PlayPauseButton;
export 'package:niuma_player/src/presentation/controls/scrub_bar.dart' show ScrubBar;
export 'package:niuma_player/src/presentation/controls/time_display.dart' show TimeDisplay;
export 'package:niuma_player/src/presentation/controls/volume_button.dart' show VolumeButton;
export 'package:niuma_player/src/presentation/controls/speed_selector.dart' show SpeedSelector;
export 'package:niuma_player/src/presentation/controls/quality_selector.dart' show QualitySelector;
export 'package:niuma_player/src/presentation/controls/subtitle_button.dart' show SubtitleButton;
export 'package:niuma_player/src/presentation/controls/danmaku_button.dart' show DanmakuButton;
export 'src/presentation/controls/fullscreen_button.dart'
    show FullscreenButton;
export 'package:niuma_player/src/presentation/controls/pip_button.dart' show PipButton;


// 编排
export 'src/orchestration/multi_source.dart'
    show MediaQuality, MediaLine, NiumaMediaSource, MultiSourcePolicy;
export 'src/orchestration/thumbnail_track.dart'
    show WebVttCue, ThumbnailLoadState;
export 'package:niuma_player/src/presentation/thumbnail/thumbnail_frame.dart' show ThumbnailFrame;
export 'src/orchestration/source_middleware.dart'
    show
        SourceMiddleware,
        HeaderInjectionMiddleware,
        SignedUrlMiddleware,
        runSourceMiddlewares;
export 'src/orchestration/resume_position.dart'
    show
        ResumeStorage,
        SharedPreferencesResumeStorage,
        ResumePolicy,
        ResumeBehaviour,
        ResumeKeyOf,
        defaultResumeKey,
        ResumeOrchestrator;
export 'package:niuma_player/src/orchestration/retry_policy.dart' show RetryPolicy;
export 'src/presentation/ad/ad_schedule.dart'
    show
        AdCue,
        AdController,
        NiumaAdSchedule,
        MidRollAd,
        MidRollSkipPolicy,
        PauseAdShowPolicy;
export 'package:niuma_player/src/presentation/ad/ad_scheduler.dart' show AdSchedulerOrchestrator;
export 'package:niuma_player/src/orchestration/auto_failover.dart' show AutoFailoverOrchestrator;

// M11 弹幕
export 'src/orchestration/danmaku_models.dart'
    show DanmakuItem, DanmakuMode, DanmakuSettings, DanmakuLoader;
export 'src/presentation/danmaku/niuma_danmaku_controller.dart'
    show NiumaDanmakuController;
export 'package:niuma_player/src/presentation/danmaku/niuma_danmaku_overlay.dart' show NiumaDanmakuOverlay;
export 'package:niuma_player/src/presentation/danmaku/niuma_danmaku_scope.dart' show NiumaDanmakuScope;
export 'package:niuma_player/src/presentation/danmaku/danmaku_settings_panel.dart' show DanmakuSettingsPanel;

// 可观测性
export 'src/observability/analytics_event.dart'
    show
        AnalyticsEvent,
        AdScheduled,
        AdImpression,
        AdClick,
        AdDismissed,
        AdCueType,
        AdDismissReason;
export 'package:niuma_player/src/observability/analytics_emitter.dart' show AnalyticsEmitter;

// M13 手势
export 'package:niuma_player/src/domain/gesture_kind.dart' show GestureKind;
export 'package:niuma_player/src/domain/gesture_feedback_state.dart' show GestureFeedbackState;
export 'src/presentation/gesture/niuma_gesture_layer.dart'
    show NiumaGestureLayer, GestureHudBuilder;
export 'package:niuma_player/src/presentation/gesture/niuma_gesture_hud.dart' show NiumaGestureHud;

// M14 短视频
export 'package:niuma_player/src/presentation/short_video/niuma_short_video_player.dart' show NiumaShortVideoPlayer;
export 'package:niuma_player/src/presentation/short_video/niuma_short_video_progress_bar.dart' show NiumaShortVideoProgressBar;
export 'package:niuma_player/src/presentation/short_video/niuma_short_video_pause_indicator.dart' show NiumaShortVideoPauseIndicator;
export 'package:niuma_player/src/presentation/short_video/niuma_short_video_scrub_label.dart' show NiumaShortVideoScrubLabel;
export 'package:niuma_player/src/domain/niuma_short_video_theme.dart' show NiumaShortVideoTheme;
export 'package:niuma_player/src/presentation/short_video/niuma_short_video_fullscreen_button.dart' show NiumaShortVideoFullscreenButton;

// M15 投屏（Cast）
export 'package:niuma_player/src/cast/cast_device.dart' show CastDevice;
export 'package:niuma_player/src/cast/cast_state.dart' show CastConnectionState, CastEndReason;
export 'package:niuma_player/src/cast/cast_service.dart' show CastService;
export 'package:niuma_player/src/cast/cast_session.dart' show CastSession;
export 'package:niuma_player/src/cast/cast_registry.dart' show NiumaCastRegistry;
export 'package:niuma_player/src/presentation/cast/niuma_cast_button.dart' show NiumaCastButton;
export 'package:niuma_player/src/presentation/cast/niuma_cast_overlay.dart' show NiumaCastOverlay;
// 投屏协议实现：DLNA + AirPlay 内置（合并自原 niuma_player_dlna /
// niuma_player_airplay companion package）。NiumaCastRegistry 默认自动
// register 这两个，业务方 0 配置就能用——仍可调
// `NiumaCastRegistry.register(...)` 加自家协议（如 Chromecast）。
export 'package:niuma_player/src/cast/dlna/dlna_cast_service.dart' show DlnaCastService;
export 'package:niuma_player/src/cast/airplay/airplay_cast_service.dart' show AirPlayCastService;

// 原子控件 `Niuma*` 前缀 alias（推荐用名）——避免业务方裸名冲突。
// 上方 `// M9 原子控件` 块的 10 个裸名（PlayPauseButton / ScrubBar / 等）
// 仍保留向后兼容，1.0 之前不删除；新代码建议用 `Niuma*` 前缀。
export 'src/control_aliases.dart'
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
