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
        LineSwitchFailed;
export 'src/presentation/niuma_player_controller.dart'
    show NiumaPlayerController, NiumaPlayerOptions, ThumbnailFetcher;
export 'src/presentation/niuma_player_view.dart';
export 'src/presentation/niuma_thumbnail_view.dart' show NiumaThumbnailView;

// M9 主题
export 'src/presentation/niuma_player_theme.dart'
    show NiumaPlayerTheme, NiumaPlayerThemeData;

// M9 缩略图悬浮预览
export 'src/presentation/niuma_scrub_preview.dart' show NiumaScrubPreview;

// M9 控件条组合
export 'src/presentation/niuma_control_bar.dart' show NiumaControlBar;

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
