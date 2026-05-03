// 内核
export 'src/data/default_backend_factory.dart' show DefaultBackendFactory;
export 'src/data/default_platform_bridge.dart' show DefaultPlatformBridge;
export 'src/data/device_memory.dart';
export 'src/domain/backend_factory.dart' show BackendFactory;
export 'src/domain/data_source.dart';
export 'src/domain/platform_bridge.dart' show PlatformBridge;
export 'src/domain/player_backend.dart' show PlayerBackend, PlayerBackendKind;
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
export 'src/presentation/niuma_player_controller.dart'
    show NiumaPlayerController, NiumaPlayerOptions, ThumbnailFetcher;
export 'src/presentation/niuma_player_view.dart';
export 'src/presentation/niuma_thumbnail_view.dart' show NiumaThumbnailView;

// M9 主题
export 'src/presentation/niuma_player_theme.dart'
    show NiumaPlayerTheme, NiumaPlayerThemeData;

// M9 一体化组件 + 全屏 page
export 'src/presentation/niuma_player.dart' show NiumaPlayer;
export 'src/presentation/niuma_fullscreen_page.dart' show NiumaFullscreenPage;

// M9 缩略图悬浮预览
export 'src/presentation/niuma_scrub_preview.dart' show NiumaScrubPreview;

// M9 控件条组合
export 'src/presentation/niuma_control_bar.dart' show NiumaControlBar;

// M9 广告 overlay
export 'src/presentation/niuma_ad_overlay.dart' show NiumaAdOverlay;

// M9 原子控件
export 'src/presentation/controls/play_pause_button.dart'
    show PlayPauseButton;
export 'src/presentation/controls/scrub_bar.dart' show ScrubBar;
export 'src/presentation/controls/time_display.dart' show TimeDisplay;
export 'src/presentation/controls/volume_button.dart' show VolumeButton;
export 'src/presentation/controls/speed_selector.dart' show SpeedSelector;
export 'src/presentation/controls/quality_selector.dart' show QualitySelector;
export 'src/presentation/controls/subtitle_button.dart' show SubtitleButton;
export 'src/presentation/controls/danmaku_button.dart' show DanmakuButton;
export 'src/presentation/controls/fullscreen_button.dart'
    show FullscreenButton;
export 'src/presentation/controls/pip_button.dart' show PipButton;

// 编排
export 'src/orchestration/multi_source.dart'
    show MediaQuality, MediaLine, NiumaMediaSource, MultiSourcePolicy;
export 'src/orchestration/thumbnail_track.dart'
    show ThumbnailFrame, WebVttCue, ThumbnailLoadState;
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
export 'src/orchestration/retry_policy.dart' show RetryPolicy;
export 'src/orchestration/ad_schedule.dart'
    show
        AdCue,
        AdController,
        NiumaAdSchedule,
        MidRollAd,
        MidRollSkipPolicy,
        PauseAdShowPolicy;
export 'src/orchestration/ad_scheduler.dart' show AdSchedulerOrchestrator;
export 'src/orchestration/auto_failover.dart' show AutoFailoverOrchestrator;

// M11 弹幕
export 'src/orchestration/danmaku_models.dart'
    show DanmakuItem, DanmakuMode, DanmakuSettings, DanmakuLoader;
export 'src/presentation/niuma_danmaku_controller.dart'
    show NiumaDanmakuController;
export 'src/presentation/niuma_danmaku_overlay.dart' show NiumaDanmakuOverlay;
export 'src/presentation/niuma_danmaku_scope.dart' show NiumaDanmakuScope;
export 'src/presentation/danmaku_settings_panel.dart' show DanmakuSettingsPanel;

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
export 'src/observability/analytics_emitter.dart' show AnalyticsEmitter;

// M13 手势
export 'src/domain/gesture_kind.dart' show GestureKind;
export 'src/domain/gesture_feedback_state.dart' show GestureFeedbackState;
export 'src/presentation/niuma_gesture_layer.dart'
    show NiumaGestureLayer, GestureHudBuilder;
export 'src/presentation/niuma_gesture_hud.dart' show NiumaGestureHud;

// M14 短视频
export 'src/presentation/niuma_short_video_player.dart' show NiumaShortVideoPlayer;
export 'src/presentation/niuma_short_video_progress_bar.dart' show NiumaShortVideoProgressBar;
export 'src/presentation/niuma_short_video_pause_indicator.dart' show NiumaShortVideoPauseIndicator;
export 'src/presentation/niuma_short_video_scrub_label.dart' show NiumaShortVideoScrubLabel;
export 'src/domain/niuma_short_video_theme.dart' show NiumaShortVideoTheme;
export 'src/presentation/niuma_short_video_fullscreen_button.dart' show NiumaShortVideoFullscreenButton;

// M15 投屏（Cast）
export 'src/cast/cast_device.dart' show CastDevice;
export 'src/cast/cast_state.dart' show CastConnectionState, CastEndReason;
export 'src/cast/cast_service.dart' show CastService;
export 'src/cast/cast_session.dart' show CastSession;
export 'src/cast/cast_registry.dart' show NiumaCastRegistry;
export 'src/presentation/cast/niuma_cast_button.dart' show NiumaCastButton;
export 'src/presentation/cast/niuma_cast_overlay.dart' show NiumaCastOverlay;
